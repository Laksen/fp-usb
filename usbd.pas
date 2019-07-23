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

  TUSBCallback = function(AEvent: TUSBEvent; AEndpoint: byte; const ARequest: TUsbControlRequest): TUSBResponse;

procedure Enable(AEnable: boolean; ACallback: TUSBCallback; const ADeviceDesc, AConfigDesc; var AStringDesc: array of PWideChar);
procedure Connect(AConnect: boolean);

procedure EndpointConfigure(AEndpoint: byte; AEndpointType: TEndpointType; AEndpointSize: SizeInt);
procedure EndpointDeconfigure(AEndpoint: byte);

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
function EndpointWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;

function EndpointControlRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
procedure EndpointControlWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt);

procedure Poll;

implementation

type
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

type
  TDevice = record
    Capabilities: word;
    Address,
    Config,
    MaxEp0Size: byte;

    Callback: TUSBCallback;

    DevDesc,
    CfgDesc: PUsbDescriptor;
    StringDesc: PWideString;
    StringDescNum: byte;

    Request: TUsbControlRequest;
    Buffer: array[0..7] of byte;

    ControlState: TControlState;
    State: TDeviceState;

    TXData: PByte;
    TXCount: SizeInt;
    TXExact: boolean;
  end;

var
  Device: TDevice;

function FindDesc(ADescType, ADescIdx: Byte; out ALength: SizeInt): PUsbDescriptor;
begin
  Result:=nil;
  ALength:=-1;

  case ADescType of
    USB_DESC_TYPE_Device: result:=Device.DevDesc;
    USB_DESC_TYPE_Configuration:
      begin
        result:=Device.CfgDesc;
        ALength:=PUsbConfigurationDescriptor(result)^.wTotalLength;
      end;
    USB_DESC_TYPE_String:
      begin
        if ADescIdx<Device.StringDescNum then
          result:=@Device.StringDesc[ADescIdx][1];
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

function EndpointControlRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  Result:=USBHAL.EndpointRead(AEndpoint,AData,ASize);
  Dec(Device.TXCount,Result);
end;

procedure EndpointControlWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt);
begin
  Device.TXData:=AData;
  Device.TXCount:=ASize;
  Device.TXExact:=ASize=Device.Request.wLength;
end;

function HandleControlRequest(AEndpoint: byte): TUSBResponse;
var
  DescType, DescIdx: Word;
  Desc: PUsbDescriptor;
  Len: SizeInt;
begin
  Result:=urStall;

  case Device.Request.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin
        case Device.Request.bmRequestType and rtRecipientMask of
          rtRecipientDevice:
            case TUsbStandardRequest(Device.Request.bRequest) of
              srGetDescriptor:
                begin
                  DescType:=Device.Request.wValue shr 8;
                  DescIdx:=Device.Request.wValue and $FF;

                  Desc:=FindDesc(DescType, DescIdx, Len);

                  if len>Device.Request.wLength then
                    Len:=Device.Request.wLength;

                  if Desc<>nil then
                  begin
                    result:=urACK;
                    EndpointControlWrite($80, Desc, Len);
                  end;
                end;
              srSetAddress:
                begin
                  result:=urACK;

                  Device.Address:=Device.Request.wValue;
                  Device.State:=dsAddressing;
                end;
              srSetConfiguration:
                begin
                  result:=urACK;

                  Device.Config:=Device.Request.wValue;  
                  Device.State:=dsConfigured;

                  if assigned(device.Callback) then
                    Device.Callback(ueConfigured,0,Device.Request);
                end;
            end;
          rtRecipientInterface:;
          rtRecipientEndpoint:;
        end;
      end;
    rtTypeClass:
      begin
        result:=Device.Callback(ueControlRequest,AEndpoint,Device.Request);
      end;
  end;
end;

function DoTransmit: boolean;
var
  toSend: SizeInt;
begin
  result:=False;

  toSend:=Device.TXCount;
  if toSend>Device.MaxEp0Size then toSend:=Device.MaxEp0Size // Full packet
  else if toSend<Device.MaxEp0Size then Result:=True // Short packet, ending
  else if Device.TXExact then Result:=True;

  EndpointWrite($80,Device.TXData,toSend);
  Inc(Device.TXData,toSend);
  Dec(Device.TXCount,toSend);
end;

procedure EndpointStall(AEndpoint: byte);
begin
  EndpointSetStall(AEndpoint and $7F, True);
  EndpointSetStall(AEndpoint or $80, True);
end;

procedure HandleRX(AEndpoint: Byte);
var
  Read: SizeInt;
begin
  case Device.Request.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin  
        Read:=USBHAL.EndpointRead(0,@Device.Buffer[0],sizeof(Device.Buffer));

        Dec(Device.TXCount,Read);

        // Do read data
        if Device.TXCount=0 then
        begin
          Device.ControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
    rtTypeClass:
      begin
        Device.Callback(ueControlRX,AEndpoint,Device.Request);

        if Device.TXCount=0 then
        begin
          Device.ControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
  end;
end;

procedure USBCallback(AEvent: TDriverEvent; AEndpoint: byte);
var
  Read: SizeInt;
  Response: TUSBResponse;
begin
  case AEvent of
    deReset:
      begin
        // Reset state
        Device.ControlState:=csIdle;
        Device.State:=dsDefault;
        Device.Config:=0;
        Device.Address:=0;

        // TODO: Signal device deconfigured
        if assigned(device.Callback) then
          device.Callback(ueDeconfigured, 0, Device.Request);

        EndpointConfigure(0, etControl, Device.MaxEp0Size);

        DriverSetAddress(0);
      end;
    deSetup:
      begin                       
        Read:=USBHal.EndpointRead(0, @Device.Request, 8);
        if Read<>8 then
          EndpointStall(0)
        else
        begin
          Response:=HandleControlRequest(AEndpoint);

          if Response=urStall then
            EndpointStall(0)
          else if (Device.Request.bmRequestType and rtDirectionMask)=rtDirectionToDevice then
          begin
            if (Device.Request.wLength=0) then
            begin
              Device.ControlState:=csControlStatusIn;
              USBHAL.EndpointWrite($80,nil,0);
            end
            else
            begin                                   
              Device.TXCount:=Device.Request.wLength;
              Device.ControlState:=csControlDataOut;
            end;
          end
          else
          begin
            if (Device.Request.wLength=0) then
            begin
              Device.ControlState:=csControlStatusOut
            end
            else
            begin
              if DoTransmit() then
                Device.ControlState:=csControlDataInDone
              else
                Device.ControlState:=csControlDataIn;
            end;
          end
        end;
      end;
    deRx:
      begin
        // OUT
        case Device.ControlState of
          csControlDataOut:
            begin
              HandleRX(AEndpoint);
            end;
          csControlStatusOut:
            begin
              Read:=USBHAL.EndpointRead(0,@Device.Buffer[0],sizeof(Device.Buffer));
              Device.ControlState:=csIdle;
            end;
          csIdle:
            begin
              if (AEndpoint and $7F)<>0 then
              begin
                Device.Callback(ueRX,AEndpoint,Device.Request);
              end
              else
              begin
                Read:=USBHAL.EndpointRead(AEndpoint,@Device.Buffer[0],sizeof(Device.Buffer));
              end;
            end;
        else                              
          Read:=USBHAL.EndpointRead(AEndpoint,@Device.Buffer[0],sizeof(Device.Buffer));
        end;
      end;
    deTx:
      begin
        // IN done         
        if (AEndpoint and $7F)<>0 then
          Device.Callback(ueTX,AEndpoint,Device.Request)
        else
          case Device.ControlState of
            csControlDataIn:
              begin
                if DoTransmit() then
                  Device.ControlState:=csControlDataInDone
                else
                  Device.ControlState:=csControlDataIn;
              end;
            csControlDataInDone:
              Device.ControlState:=csControlStatusOut;
            csControlStatusIn:
              begin
                case Device.Request.bmRequestType and rtTypeMask of
                  rtTypeClass:
                    Device.Callback(ueControlDone,AEndpoint,Device.Request);
                end;

                case Device.State of
                  dsAddressing:
                    begin
                      USBHAL.DriverSetAddress(Device.Address);
                      Device.State:=dsAddressed;
                    end;
                end;
                Device.ControlState:=csIdle;
              end;
          end;
      end;
  end;
end;

procedure Enable(AEnable: boolean; ACallback: TUSBCallback; const ADeviceDesc, AConfigDesc; var AStringDesc: array of PWideChar);
begin
  Device.DevDesc:=@ADeviceDesc;
  Device.CfgDesc:=@AConfigDesc;
  Device.StringDesc:=@AStringDesc[0];
  Device.StringDescNum:=length(AStringDesc);

  Device.Callback:=ACallback;

  Device.MaxEp0Size:=8;

  USBHAL.DriverState(AEnable, @USBCallback);
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

