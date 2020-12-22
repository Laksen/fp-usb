unit USBD;

interface

uses
  USBCore,
  USBHAL;

type
  TUSBResponse = (urACK, urNAK, urStall);
  TUSBDeviceCapabilities = set of (dcRemoteWakeup, dcSelfPowered);

  TUSBEvent = (ueDeconfigured, ueConfigured,
               ueControlRequest, ueControlRX, ueControlDone,
               ueTX, ueRX);

  TControlState = (
    csIdle,             // Setup -> DataOut,DataIn,StatusOut,StatusIn
    csControlDataOut,   // Write -> StatusIn
    csControlDataIn,    // Read  -> StatusOut
    csControlDataInDone,
    csControlStatusOut, // [OUT] -> Idle
    csControlStatusIn   // [IN]  -> Idle
  );

  TDeviceState = (
    dsDefault,
    dsAddressing, dsAddressed,
    dsConfigured);

  PDevice = ^TUSBDevice;
  TUSBDevice = record
    UserData: pointer;

    Capabilities: word;
    Address,
    Config,
    MaxEp0Size: byte;

    Callback: pointer;

    DevDesc,
    CfgDesc: PUsbDescriptor;
    StringDesc: PWideString;
    StringDescNum: byte;

    Request: TUsbControlRequest;
    Buffer: array[0..7] of byte;

    ControlState: TControlState;
    State: TDeviceState;

    DeviceCaps: word;

    TXData: PByte;
    TXCount: SizeInt;
    TXExact: boolean;
  end;

  TUSBCallback = function(var Device: TUSBDevice; AEvent: TUSBEvent; AEndpoint: byte; const ARequest: TUsbControlRequest): TUSBResponse;

procedure Enable(var ADevice: TUSBDevice; AEnable: boolean; ACallback: TUSBCallback; const ADeviceDesc, AConfigDesc; const AStringDesc: array of PWideChar);
procedure Connect(AConnect: boolean);

procedure EndpointConfigure(AEndpoint: byte; AEndpointType: TEndpointType; AEndpointSize: SizeInt);
procedure EndpointDeconfigure(AEndpoint: byte);

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
function EndpointWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;

function EndpointControlRead(var ADevice: TUSBDevice; AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
procedure EndpointControlWrite(var ADevice: TUSBDevice; AEndpoint: byte; AData: Pointer; ASize: SizeInt);

procedure Poll;

implementation

function FindDesc(var ADevice: TUSBDevice; ADescType, ADescIdx: Byte; out ALength: SizeInt): PUsbDescriptor;
begin
  Result:=nil;
  ALength:=-1;

  case ADescType of
    USB_DESC_TYPE_Device: result:=ADevice.DevDesc;
    USB_DESC_TYPE_Configuration:
      begin
        result:=ADevice.CfgDesc;
        ALength:=PUsbConfigurationDescriptor(result)^.wTotalLength;
      end;
    USB_DESC_TYPE_String:
      begin
        if ADescIdx<ADevice.StringDescNum then
          result:=@ADevice.StringDesc[ADescIdx][1];
      end;
  end;

  if (ALength=-1) and (result<>nil) then
    ALength:=result^.bLength;
end;

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  Result:=USBHAL.EndpointRead(AEndpoint,AData,ASize);
end;

function EndpointWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  Result:=USBHAL.EndpointWrite(AEndpoint,AData,ASize);
end;

function EndpointControlRead(var ADevice: TUSBDevice; AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  Result:=USBHAL.EndpointRead(AEndpoint,AData,ASize);
  Dec(ADevice.TXCount,Result);
end;

procedure EndpointControlWrite(var ADevice: TUSBDevice; AEndpoint: byte; AData: Pointer; ASize: SizeInt);
begin
  ADevice.TXData:=AData;
  ADevice.TXCount:=ASize;
  ADevice.TXExact:=ASize=ADevice.Request.wLength;
end;

function HandleControlRequest(var ADevice: TUSBDevice; AEndpoint: byte): TUSBResponse;
var
  DescType, DescIdx: Word;
  Desc: PUsbDescriptor;
  Len: SizeInt;
begin
  Result:=urStall;

  case ADevice.Request.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin
        case ADevice.Request.bmRequestType and rtRecipientMask of
          rtRecipientDevice:
            case TUsbStandardRequest(ADevice.Request.bRequest) of
              srGetDescriptor:
                begin
                  DescType:=ADevice.Request.wValue shr 8;
                  DescIdx:=ADevice.Request.wValue and $FF;

                  Desc:=FindDesc(ADevice, DescType, DescIdx, Len);

                  if len>ADevice.Request.wLength then
                    Len:=ADevice.Request.wLength;

                  if Desc<>nil then
                  begin
                    result:=urACK;
                    EndpointControlWrite(ADevice, $80, Desc, Len);
                  end;
                end;
              srSetAddress:
                begin
                  result:=urACK;

                  ADevice.Address:=ADevice.Request.wValue;
                  if ADevice.Address=0 then
                    ADevice.State:=dsDefault
                  else
                    ADevice.State:=dsAddressing;
                end;
              srSetConfiguration:
                begin
                  result:=urACK;

                  ADevice.Config:=ADevice.Request.wValue;
                  if ADevice.Config=0 then
                  begin
                    ADevice.State:=dsAddressed;

                    if assigned(ADevice.Callback) then
                      TUSBCallback(ADevice.Callback)(ADevice,ueDeconfigured,0,ADevice.Request);
                  end
                  else
                  begin
                    ADevice.State:=dsConfigured;

                    if assigned(ADevice.Callback) then
                      TUSBCallback(ADevice.Callback)(ADevice,ueConfigured,0,ADevice.Request);
                  end;
                end;
              srGetConfiguration:
                begin
                  result:=urACK;
                  EndpointControlWrite(ADevice, $80, @ADevice.Config, 1);
                end;
              srGetStatus:
                begin
                  result:=urACK;
                  EndpointControlWrite(ADevice, $80, @ADevice.DeviceCaps, 2);
                end
            else
            //  writeln('Unhandled: ',TUsbStandardRequest(ADevice.Request.bRequest));
            end;
          rtRecipientInterface:
            case TUsbStandardRequest(ADevice.Request.bRequest) of
              srGetStatus:
                begin
                  ADevice.Buffer[0]:=0;
                  ADevice.Buffer[1]:=0;

                  result:=urACK;
                  EndpointControlWrite(ADevice, $80, @ADevice.Buffer, 2);
                end;
            end;
          rtRecipientEndpoint:
            case TUsbStandardRequest(ADevice.Request.bRequest) of
              srClearFeature:
                begin
                  USBHAL.EndpointSetStall(ADevice.Request.wIndex, false);
                  result:=urACK;
                end;
              srSetFeature:
                begin
                  USBHAL.EndpointSetStall(ADevice.Request.wIndex, true);
                  result:=urACK;
                end;
              srGetStatus:
                begin
                  ADevice.Buffer[0]:=Ord(USBHAL.EndpointStalled(ADevice.Request.wIndex));
                  ADevice.Buffer[1]:=0;
                                      
                  result:=urACK;
                  EndpointControlWrite(ADevice, $80, @ADevice.Buffer, 2);
                end;
            end;
        end;
      end;
    rtTypeClass:
      begin
        result:=TUSBCallback(ADevice.Callback)(ADevice,ueControlRequest,AEndpoint,ADevice.Request);
      end;
  end;
end;

function DoTransmit(var ADevice: TUSBDevice): boolean;
var
  toSend: SizeInt;
begin
  result:=False;

  toSend:=ADevice.TXCount;
  if toSend>ADevice.MaxEp0Size then toSend:=ADevice.MaxEp0Size // Full packet
  else if toSend<ADevice.MaxEp0Size then Result:=True // Short packet, ending
  else if ADevice.TXExact then Result:=True;

  EndpointWrite($80,ADevice.TXData,toSend);
  Inc(ADevice.TXData,toSend);
  Dec(ADevice.TXCount,toSend);
end;

procedure EndpointStall(AEndpoint: byte);
begin
  EndpointSetStall(AEndpoint and $7F, True);
  EndpointSetStall(AEndpoint or $80, True);
end;

procedure HandleRX(var ADevice: TUSBDevice; AEndpoint: Byte);
var
  Read: SizeInt;
begin
  case ADevice.Request.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin  
        Read:=USBHAL.EndpointRead(0,@ADevice.Buffer[0],sizeof(ADevice.Buffer));

        Dec(ADevice.TXCount,Read);

        // Do read data
        if ADevice.TXCount=0 then
        begin
          ADevice.ControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
    rtTypeClass:
      begin
        TUSBCallback(ADevice.Callback)(ADevice,ueControlRX,AEndpoint,ADevice.Request);

        if ADevice.TXCount=0 then
        begin
          ADevice.ControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
  end;
end;

procedure USBCallback2(var ADevice: TUSBDevice; AEvent: TDriverEvent; AEndpoint: byte);
var
  Read: SizeInt;
  Response: TUSBResponse;
begin
  case AEvent of
    deReset:
      begin
        // Reset state
        ADevice.ControlState:=csIdle;
        ADevice.State:=dsDefault;
        ADevice.Config:=0;
        ADevice.Address:=0;

        TUSBCallback(ADevice.Callback)(ADevice,ueDeconfigured, 0, ADevice.Request);

        EndpointConfigure(0, etControl, ADevice.MaxEp0Size);

        DriverSetAddress(0);
      end;
    deSetup:
      begin                       
        Read:=USBHal.EndpointRead(0, @ADevice.Request, 8);
        if Read<>8 then
          EndpointStall(0)
        else
        begin
          Response:=HandleControlRequest(ADevice, AEndpoint);

          if Response=urStall then
            EndpointStall(0)
          else if (ADevice.Request.bmRequestType and rtDirectionMask)=rtDirectionToDevice then
          begin
            if (ADevice.Request.wLength=0) then
            begin
              ADevice.ControlState:=csControlStatusIn;
              USBHAL.EndpointWrite($80,nil,0);
            end
            else
            begin                                   
              ADevice.TXCount:=ADevice.Request.wLength;
              ADevice.ControlState:=csControlDataOut;
            end;
          end
          else
          begin
            if (ADevice.Request.wLength=0) then
            begin
              ADevice.ControlState:=csControlStatusOut
            end
            else
            begin
              if DoTransmit(ADevice) then
                ADevice.ControlState:=csControlDataInDone
              else
                ADevice.ControlState:=csControlDataIn;
            end;
          end
        end;
      end;
    deRx:
      begin
        // OUT
        case ADevice.ControlState of
          csControlDataOut:
            begin
              HandleRX(ADevice, AEndpoint);
            end;
          csControlStatusOut:
            begin
              Read:=USBHAL.EndpointRead(0,@ADevice.Buffer[0],sizeof(ADevice.Buffer));
              ADevice.ControlState:=csIdle;
            end;
          csIdle:
            begin
              if (AEndpoint and $7F)<>0 then
                TUSBCallback(ADevice.Callback)(ADevice,ueRX,AEndpoint,ADevice.Request)
              else
                Read:=USBHAL.EndpointRead(AEndpoint,@ADevice.Buffer[0],sizeof(ADevice.Buffer));
            end;
        else                              
          Read:=USBHAL.EndpointRead(AEndpoint,@ADevice.Buffer[0],sizeof(ADevice.Buffer));
        end;
      end;
    deTx:
      begin
        // IN done         
        if (AEndpoint and $7F)<>0 then
          TUSBCallback(ADevice.Callback)(ADevice,ueTX,AEndpoint,ADevice.Request)
        else
          case ADevice.ControlState of
            csControlDataIn:
              begin
                if DoTransmit(ADevice) then
                  ADevice.ControlState:=csControlDataInDone
                else
                  ADevice.ControlState:=csControlDataIn;
              end;
            csControlDataInDone:
              ADevice.ControlState:=csControlStatusOut;
            csControlStatusIn:
              begin
                case ADevice.Request.bmRequestType and rtTypeMask of
                  rtTypeClass:
                    TUSBCallback(ADevice.Callback)(ADevice,ueControlDone,AEndpoint,ADevice.Request);
                end;

                case ADevice.State of
                  dsAddressing:
                    begin
                      USBHAL.DriverSetAddress(ADevice.Address);
                      ADevice.State:=dsAddressed;
                    end;
                end;
                ADevice.ControlState:=csIdle;
              end;
          end;
      end;
  end;
end;

procedure USBCallback(AData: pointer; AEvent: TDriverEvent; AEndpoint: byte);
begin
  USBCallback2(PDevice(AData)^,AEvent,AEndpoint);
end;

procedure Enable(var ADevice: TUSBDevice; AEnable: boolean; ACallback: TUSBCallback; const ADeviceDesc, AConfigDesc; const AStringDesc: array of PWideChar);
begin
  ADevice.DevDesc:=@ADeviceDesc;
  ADevice.CfgDesc:=@AConfigDesc;
  ADevice.StringDesc:=@AStringDesc[0];
  ADevice.StringDescNum:=length(AStringDesc);

  ADevice.Callback:=ACallback;

  ADevice.MaxEp0Size:=PUsbDeviceDescriptor(@ADevice)^.bMaxPacketSize;

  USBHAL.DriverState(AEnable, @USBCallback, @ADevice);
end;

procedure Connect(AConnect: boolean);
begin
  USBHAL.DriverConnect(AConnect);
end;

procedure EndpointConfigure(AEndpoint: byte; AEndpointType: TEndpointType; AEndpointSize: SizeInt);
begin
  USBHAL.EndpointConfigure(AEndpoint,AEndpointType,AEndpointSize);
end;

procedure EndpointDeconfigure(AEndpoint: byte);
begin
  USBHAL.EndpointDeconfigure(AEndpoint and $7F);
end;

procedure Poll;
begin
  USBHAL.DriverPoll;
end;

end.

