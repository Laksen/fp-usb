unit simpleusb;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  USBCore, USBHAL;

type
  TSimpleUSBResponse = (urACK, urNAK, urStall);

  TSimpleUSBVersion = (uv10, uv11, uv20);

  TUSBMaxPacketSize= 8..1024;
  TSimpleUSBAddress = 1..127;

  TSimpleUSBDirection = (dirToDevice, dirFromDevice);
  TSimpleUSBEndpointType = (setControl, setIsochronous, setBulk, setInterrupt);

  TSimpleUSBConfigAttribute = (caRemoteWakeup = $20, caSelfPowered = $40);
  TSimpleUSBConfigAttributes = set of TSimpleUSBConfigAttribute;

  PSimpleUSBDevice = ^TSimpleUSBDevice;
  PSimpleUSBConfigDescriptor = ^TSimpleUSBConfigDescriptor;

  TSimpleUSBDescriptor = record
  private
    fDevice: PSimpleUSBDevice;
    fDescPtr: pointer;
    function GetBuffer: PUsbDescriptor;
  public
    constructor Create(ADevice: PSimpleUSBDevice; APtr: pointer);

    property Buffer: PUsbDescriptor read GetBuffer;
  end;

  TSimpleUSBInterfaceDescriptor = record
  private
    fConfig: PSimpleUSBConfigDescriptor;
    fIntfDesc: TSimpleUSBDescriptor;
  public
    constructor Create(AConfig: PSimpleUSBConfigDescriptor; const AIntfDesc: TSimpleUSBDescriptor);

    function AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;

    procedure AddEndpoint(ADirection: TSimpleUSBDirection; AAddress: TSimpleUSBAddress; AType: TSimpleUSBEndpointType; AMaxPacketSize: word; AInterval: byte = $FF);
  end;

  TSimpleUSBConfigDescriptor = record
  private
    fDevice: PSimpleUSBDevice;
    fConfigDesc: TSimpleUSBDescriptor;
  public
    constructor Create(ADevice: PSimpleUSBDevice; const AConfigDesc: TSimpleUSBDescriptor);

    function AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;

    function AddInterface(AInterfaceNumber, AAltSetting: byte; AClass, ASubClass, AProtocol: word; AName: pwidechar = nil): TSimpleUSBInterfaceDescriptor;
  end;

  TSimpleUSBConfigCallback = procedure(ADevice: PSimpleUSBDevice; AConfig: byte) of object;
  TSimpleUSBControlReqCallback = function(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse of object;
  TSimpleUSBCompleteCallback = procedure(ADevice: PSimpleUSBDevice; AEndpoint: byte) of object;

  TSimpleUSBDevice = record
  private type
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
      dsConfigured
    );

    TUSBConfigEvent = (
      ueDeconfigured,
      ueConfigured
    );

    TUSBControlEvent = (
      ueControlRequest,
      ueControlRX,
      ueControlDone
    );

    TUSBEndpointEvent = (
      ueTX,
      ueRX
    );
  private var
    fDeviceDesc: TUsbDeviceDescriptor;

    fIntfCnt,
    fEpCnt: byte;

    fDescStorage: pbyte;
    fDescStorageSize: SizeInt;
    fDescStorageUsed: SizeInt;

    fStrDescStorage: pbyte;
    fStrDescStorageSize: SizeInt;
    fStrDescStorageUsed: SizeInt;
    fStrDescIndex: byte;

    // Internal state
    fControlState: TControlState;
    fDeviceState: TDeviceState;
    fConfig,
    fAddress: byte;

    fDeviceCaps: word;

    fRequest: TUsbControlRequest;
    fBuffer: array[0..7] of byte;  

    fTXData: PByte;
    fTXCount: SizeInt;
    fTXExact: boolean;

    fEp0PacketSize: word;

    fEnabledEPs: set of 1..127;

    // Callbacks
    fConfigCallback: array[TUSBConfigEvent] of TSimpleUSBConfigCallback;
    fControlReq:     array[TUSBControlEvent] of TSimpleUSBControlReqCallback;
    fEndpointReq:    array[TUSBEndpointEvent] of TSimpleUSBCompleteCallback;

    function FindDesc(ADescType, ADescIdx: Byte; out ALength: SizeInt): PUsbDescriptor;
    function FindCfgDesc(ADescValue: Byte; out ALength: SizeInt): PUsbDescriptor;

    function AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;
                                                               
    function  DoTransmit: boolean;

    function  HandleControlRequest(AEndpoint: byte): TSimpleUSBResponse;
    procedure HandleRX(AEndpoint: Byte);

    procedure HALCallback(AEvent: TDriverEvent; AEndpoint: byte);

    procedure DoDeconfigure;
    procedure DoConfigure;
  public
    procedure Error(AMessage: pchar);

    procedure Poll;

    function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
    function EndpointWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;

    // Control
    procedure Enable(AEp0PacketSize: Word);
    procedure SetConnected(AConnected: boolean);

    function  EndpointControlRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
    procedure EndpointControlWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt);

    // Utility
    function AllocateInterface: byte;
    function AllocateEndpoint: byte;

    // Callbacks
    function AddConfigCallback  (AEvent: TUSBConfigEvent;   const ACallback: TSimpleUSBConfigCallback): TSimpleUSBConfigCallback;
    function AddControlCallback (AEvent: TUSBControlEvent;  const ACallback: TSimpleUSBControlReqCallback): TSimpleUSBControlReqCallback;
    function AddEndpointCallback(AEvent: TUSBEndpointEvent; const ACallback: TSimpleUSBCompleteCallback): TSimpleUSBCompleteCallback;

    // Descriptors
    procedure SetDescriptorBuffer(var ABuffer; ABufferSize: SizeInt);
    function  GetDescriptorSize: SizeInt;

    procedure SetStrDescriptorBuffer(var ABuffer; ABufferSize: SizeInt);
    function  GetStrDescriptorSize: SizeInt;

    procedure ConfigureDevice(AVendorID, AProductID, AVersion: word; AManufacturer, AProduct, ASerialNumber: pwidechar; AUSBVersion: TSimpleUSBVersion; AMaxPacketSize: TUSBMaxPacketSize; ADeviceClass, ADeviceSubClass, ADeviceProtocol: word);

    function GetConfig(AConfigValue: byte): TSimpleUSBConfigDescriptor;

    function AddConfiguration(AConfigValue: byte; AConfigAttributes: TSimpleUSBConfigAttributes; AMaxPower_ma: word; AName: pwidechar = nil): TSimpleUSBConfigDescriptor;
    function AddStringDescriptor(AStr: pwidechar): byte;
  end;

function EndpointAddress(AEndpointAddr: byte): byte; inline;
function RXEndpoint(AEndpointAddr: byte): byte; inline;
function TXEndpoint(AEndpointAddr: byte): byte; inline;

implementation

function EndpointAddress(AEndpointAddr: byte): byte;
begin
  result:=AEndpointAddr and $7F;
end;

function RXEndpoint(AEndpointAddr: byte): byte; inline;
begin
  result:=AEndpointAddr;
end;

function TXEndpoint(AEndpointAddr: byte): byte; inline;
begin
  result:=AEndpointAddr or $80;
end;

procedure EndpointStall(AEndpoint: byte);
begin
  EndpointSetStall(AEndpoint and $7F, True);
  EndpointSetStall(AEndpoint or $80, True);
end;

procedure USBDeviceCallback(AData: pointer; AEvent: TDriverEvent; AEndpoint: byte);
begin
  PSimpleUSBDevice(AData)^.HALCallback(AEvent, AEndpoint);
end;

{procedure TSimpleUSBCompleteCallback.Invoke(ADevice: PSimpleUSBDevice; AEndpoint: byte);
begin
  if Method<>nil then
    Method(Data, ADevice, AEndpoint);
end;

function TSimpleUSBControlReqCallback.Invoke(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
begin
  if Method<>nil then
    result:=Method(Data, ADevice, AEndpoint, ARequest)
  else
    result:=urStall;
end;

procedure TSimpleUSBConfigCallback.Invoke(ADevice: PSimpleUSBDevice; AConfig: byte);
begin
  if Method<>nil then
  begin                            
    writeln(HexStr(Method), ',',hexstr(data));
    Method(Data, ADevice, AConfig);
  end;
end;}

function TSimpleUSBDescriptor.GetBuffer: PUsbDescriptor;
begin
  result:=PUsbDescriptor(fDescPtr);
end;

constructor TSimpleUSBDescriptor.Create(ADevice: PSimpleUSBDevice; APtr: pointer);
begin
  fDevice:=ADevice;
  fDescPtr:=APtr;
end;

function NextDescriptor(ADesc: PUsbDescriptor): PUsbDescriptor; inline;
begin
  result:=PUsbDescriptor(@PByte(ADesc)[ADesc^.bLength]);
end;

function TSimpleUSBDevice.FindDesc(ADescType, ADescIdx: Byte; out ALength: SizeInt): PUsbDescriptor;
var
  LookIn: PUsbDescriptor;
  LookSize: SizeInt;
begin
  Result:=nil;
  ALength:=-1;

  LookIn:=nil;
  LookSize:=0;

  case ADescType of
    USB_DESC_TYPE_Device: result:=@fDeviceDesc;
    USB_DESC_TYPE_Configuration:
      begin
        LookIn:=PUsbDescriptor(fDescStorage);
        LookSize:=fDescStorageUsed;
      end;
    USB_DESC_TYPE_String:
      begin        
        LookIn:=PUsbDescriptor(fStrDescStorage);
        LookSize:=fStrDescStorageUsed;
      end;
  end;

  while LookIn<>Nil do
  begin
    if LookIn^.bDescriptorType=ADescType then
    begin
      if ADescIdx=0 then
      begin
        result:=LookIn;
        break;
      end
      else
        dec(ADescIdx);
    end;

    dec(LookSize, LookIn^.bLength);
    if LookSize <= 0 then
      break;
    LookIn:=NextDescriptor(LookIn);
  end;

  if result<>nil then
  begin
    if ADescType=USB_DESC_TYPE_Configuration then
      ALength:=PUsbConfigurationDescriptor(result)^.wTotalLength
    else
      ALength:=result^.bLength;
  end;
end;

function TSimpleUSBDevice.FindCfgDesc(ADescValue: Byte; out ALength: SizeInt): PUsbDescriptor;
var
  LookIn: PUsbDescriptor;
  LookSize: SizeInt;
begin
  Result:=nil;
  ALength:=-1;

  LookIn:=PUsbDescriptor(fDescStorage);
  LookSize:=fDescStorageUsed;

  while LookIn<>Nil do
  begin
    if LookIn^.bDescriptorType=USB_DESC_TYPE_Configuration then
    begin
      if PUsbConfigurationDescriptor(LookIn)^.bConfigurationValue=ADescValue then
      begin
        result:=LookIn;
        break;
      end;
    end;

    dec(LookSize, LookIn^.bLength);
    if LookSize <= 0 then
      break;
    LookIn:=NextDescriptor(LookIn);
  end;

  if result<>nil then
    ALength:=PUsbConfigurationDescriptor(result)^.wTotalLength;
end;

function TSimpleUSBDevice.AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;
var
  ptr: pointer;
begin
  ptr:=@fDescStorage[fDescStorageUsed];

  if (fDescStorageSize-fDescStorageUsed-ASize) < 0 then
    Error('Out of desc space')
  else
    result:=TSimpleUSBDescriptor.Create(@self, ptr);  
  inc(fDescStorageUsed, ASize);
end;
function TSimpleUSBDevice.EndpointControlRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  Result:=USBHAL.EndpointRead(AEndpoint,AData,ASize);
  Dec(fTXCount,Result);
end;

procedure TSimpleUSBDevice.EndpointControlWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt);
begin
  fTXData:=AData;
  fTXCount:=ASize;
  fTXExact:=(ASize=fRequest.wLength);
end;

function TSimpleUSBDevice.HandleControlRequest(AEndpoint: byte): TSimpleUSBResponse;
var
  DescType, DescIdx: Word;
  Desc: PUsbDescriptor;
  Len: SizeInt;
begin
  Result:=urStall;

  case fRequest.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin
        case fRequest.bmRequestType and rtRecipientMask of
          rtRecipientDevice:
            case TUsbStandardRequest(fRequest.bRequest) of
              srGetDescriptor:
                begin
                  DescType:=fRequest.wValue shr 8;
                  DescIdx:=fRequest.wValue and $FF;

                  Desc:=FindDesc(DescType, DescIdx, Len);    

                  if len>fRequest.wLength then
                    Len:=fRequest.wLength;

                  if Desc<>nil then
                  begin
                    result:=urACK;
                    EndpointControlWrite($80, Desc, Len);
                  end;
                end;
              srSetAddress:
                begin
                  result:=urACK;

                  fAddress:=fRequest.wValue;
                  if fAddress=0 then
                    fDeviceState:=dsDefault
                  else
                    fDeviceState:=dsAddressing;
                end;
              srSetConfiguration:
                begin
                  result:=urACK;

                  fConfig:=lo(fRequest.wValue);
                  if fConfig=0 then
                  begin
                    fDeviceState:=dsAddressed;

                    DoDeconfigure;
                    if assigned(fConfigCallback[ueDeconfigured]) then
                      fConfigCallback[ueDeconfigured](@self,0);
                  end
                  else
                  begin
                    fDeviceState:=dsConfigured;

                    DoConfigure;
                    if assigned(fConfigCallback[ueConfigured]) then
                      fConfigCallback[ueConfigured](@self,fConfig);
                  end;
                end;
              srGetConfiguration:
                begin
                  result:=urACK;
                  EndpointControlWrite($80, @fConfig, 1);
                end;
              srGetStatus:
                begin
                  result:=urACK;
                  EndpointControlWrite($80, @fDeviceCaps, 2);
                end
            else
            //  writeln('Unhandled: ',TUsbStandardRequest(fRequest.bRequest));
            end;
          rtRecipientInterface:
            case TUsbStandardRequest(fRequest.bRequest) of
              srGetStatus:
                begin
                  fBuffer[0]:=0;
                  fBuffer[1]:=0;

                  result:=urACK;
                  EndpointControlWrite($80, @fBuffer, 2);
                end;
            end;
          rtRecipientEndpoint:
            case TUsbStandardRequest(fRequest.bRequest) of
              srClearFeature:
                begin
                  USBHAL.EndpointSetStall(fRequest.wIndex, false);
                  result:=urACK;
                end;
              srSetFeature:
                begin
                  USBHAL.EndpointSetStall(fRequest.wIndex, true);
                  result:=urACK;
                end;
              srGetStatus:
                begin
                  fBuffer[0]:=Ord(USBHAL.EndpointStalled(fRequest.wIndex));
                  fBuffer[1]:=0;

                  result:=urACK;
                  EndpointControlWrite($80, @fBuffer, 2);
                end;
            end;
        end;
      end;
    rtTypeClass:
      if assigned(fControlReq[ueControlRequest]) then
        result:=fControlReq[ueControlRequest](@self,AEndpoint,fRequest);
  end;
end;

function TSimpleUSBDevice.DoTransmit: boolean;
var
  toSend: SizeInt;
begin
  result:=False;

  toSend:=fTXCount;
  if toSend>fEp0PacketSize then toSend:=fEp0PacketSize // Full packet
  else if toSend<fEp0PacketSize then Result:=True // Short packet, ending
  else if fTXExact then Result:=True;

  EndpointWrite($80,fTXData,toSend);
  Inc(fTXData,toSend);
  Dec(fTXCount,toSend);
end;

procedure TSimpleUSBDevice.HandleRX(AEndpoint: Byte);
var
  Read: SizeInt;
begin
  case fRequest.bmRequestType and rtTypeMask of
    rtTypeStandard:
      begin
        Read:=USBHAL.EndpointRead(0,@fBuffer[0],sizeof(fBuffer));

        Dec(fTXCount,Read);

        // Do read data
        if fTXCount=0 then
        begin
          fControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
    rtTypeClass:
      begin
        if assigned(fControlReq[ueControlRX]) then
          fControlReq[ueControlRX](@self,AEndpoint,fRequest);

        if fTXCount=0 then
        begin
          fControlState:=csControlStatusIn;
          USBHAL.EndpointWrite($80,nil,0);
        end;
      end;
  end;
end;

procedure TSimpleUSBDevice.HALCallback(AEvent: TDriverEvent; AEndpoint: byte);
var
  Read: SizeInt;
  Response: TSimpleUSBResponse;
begin
  case AEvent of
    deReset:
      begin
        // Reset state
        fControlState:=csIdle;
        fDeviceState:=dsDefault;
        fConfig:=0;
        fAddress:=0;

        DoDeconfigure;
        if assigned(fConfigCallback[ueDeconfigured]) then
          fConfigCallback[ueDeconfigured](@self,0);

        EndpointConfigure(0, etControl, fEp0PacketSize);

        DriverSetAddress(0);
      end;
    deSetup:
      begin
        Read:=USBHal.EndpointRead(0, @fRequest, 8);
        if Read<>8 then
          EndpointStall(0)
        else
        begin
          Response:=HandleControlRequest(AEndpoint);

          if Response=urStall then
            EndpointStall(0)
          else if (fRequest.bmRequestType and rtDirectionMask)=rtDirectionToDevice then
          begin
            if fRequest.wLength=0 then
            begin
              fControlState:=csControlStatusIn;
              USBHAL.EndpointWrite($80,nil,0);
            end
            else
            begin
              fTXCount:=fRequest.wLength;
              fControlState:=csControlDataOut;
            end;
          end
          else
          begin
            if fRequest.wLength=0 then
              fControlState:=csControlStatusOut
            else
            begin
              if DoTransmit() then
                fControlState:=csControlDataInDone
              else
                fControlState:=csControlDataIn;
            end;
          end
        end;
      end;
    deRx:
      begin
        // OUT
        case fControlState of
          csControlDataOut:
            begin
              HandleRX(AEndpoint);
            end;
          csControlStatusOut:
            begin
              Read:=USBHAL.EndpointRead(0,@fBuffer[0],sizeof(fBuffer));
              fControlState:=csIdle;
            end;
          csIdle:
            begin
              if (AEndpoint and $7F)<>0 then
              begin
                if assigned(fEndpointReq[ueRX]) then
                  fEndpointReq[ueRX](@self,AEndpoint);
              end
              else
                Read:=USBHAL.EndpointRead(AEndpoint,@fBuffer[0],sizeof(fBuffer));
            end;
        else
          Read:=USBHAL.EndpointRead(AEndpoint,@fBuffer[0],sizeof(fBuffer));
        end;
      end;
    deTx:
      begin
        // IN done
        if (AEndpoint and $7F)<>0 then
        begin
          if assigned(fEndpointReq[ueTX]) then
            fEndpointReq[ueTX](@self,AEndpoint);
        end
        else
          case fControlState of
            csControlDataIn:
              begin
                if DoTransmit() then
                  fControlState:=csControlDataInDone
                else
                  fControlState:=csControlDataIn;
              end;
            csControlDataInDone:
              fControlState:=csControlStatusOut;
            csControlStatusIn:
              begin
                case fRequest.bmRequestType and rtTypeMask of
                  rtTypeClass:                           
                    if assigned(fControlReq[ueControlDone]) then
                      fControlReq[ueControlDone](@self,AEndpoint,fRequest);
                end;

                case fDeviceState of
                  dsAddressing:
                    begin
                      USBHAL.DriverSetAddress(fAddress);
                      fDeviceState:=dsAddressed;
                    end;
                end;
                fControlState:=csIdle;
              end;
          end;
      end;
  end;
end;

procedure TSimpleUSBDevice.DoDeconfigure;
var
  ep: 1..127;
begin
  for ep in fEnabledEPs do
    EndpointDeconfigure(ep);
  fEnabledEPs:=[];
end;

procedure TSimpleUSBDevice.DoConfigure;
var
  len: SizeInt;
  desc: PUsbDescriptor;
  ep: PUsbEndpointDescriptor;
  et: TEndpointType;
begin
  desc:=FindCfgDesc(fConfig, len);

  while len>0 do
  begin
    if desc^.bDescriptorType=USB_DESC_TYPE_Endpoint then
    begin
      ep:=PUsbEndpointDescriptor(desc);

      case ep^.bmAttributes of
        USB_ENDPOINT_TYPE_Control: et:=etControl;
        USB_ENDPOINT_TYPE_Isochronous: et:=etIsochronous;
        USB_ENDPOINT_TYPE_Bulk: et:=etBulk;
        USB_ENDPOINT_TYPE_Interrupt: et:=etInterrupt;
      else
        et:=etControl;
      end;

      USBHAL.EndpointConfigure(ep^.bEndpointAddress, et, ep^.wMaxPacketSize);
      Include(fEnabledEPs, ep^.bEndpointAddress and $7F);
    end;

    dec(len, desc^.bLength);
    desc:=NextDescriptor(desc);
  end;
end;

procedure TSimpleUSBDevice.Error(AMessage: pchar);
begin
  //writeln(AMessage);
end;

procedure TSimpleUSBDevice.Poll;
begin
  USBHAL.DriverPoll;
end;

function TSimpleUSBDevice.EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  result:=USBHAL.EndpointRead(AEndpoint,AData,ASize);
end;

function TSimpleUSBDevice.EndpointWrite(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin
  result:=USBHAL.EndpointWrite(AEndpoint,AData,ASize);
end;

procedure TSimpleUSBDevice.Enable(AEp0PacketSize: Word);
begin
  fEp0PacketSize:=AEp0PacketSize;
  USBHAL.DriverState(true, @USBDeviceCallback, @self);
end;

procedure TSimpleUSBDevice.SetConnected(AConnected: boolean);
begin
  USBHAL.DriverConnect(AConnected);
end;

function TSimpleUSBDevice.AllocateInterface: byte;
begin
  result:=fIntfCnt;
  inc(fIntfCnt);
end;

function TSimpleUSBDevice.AllocateEndpoint: byte;
begin
  if fEpCnt=0 then
    inc(fEpCnt);

  result:=fEpCnt;
  inc(fEpCnt);
end;

function TSimpleUSBDevice.AddConfigCallback(AEvent: TUSBConfigEvent; const ACallback: TSimpleUSBConfigCallback): TSimpleUSBConfigCallback;
begin
  result:=fConfigCallback[AEvent];
  fConfigCallback[AEvent]:=ACallback;
end;

function TSimpleUSBDevice.AddControlCallback(AEvent: TUSBControlEvent; const ACallback: TSimpleUSBControlReqCallback): TSimpleUSBControlReqCallback;
begin
  result:=fControlReq[AEvent];
  fControlReq[AEvent]:=ACallback;
end;

function TSimpleUSBDevice.AddEndpointCallback(AEvent: TUSBEndpointEvent; const ACallback: TSimpleUSBCompleteCallback): TSimpleUSBCompleteCallback;
begin
  result:=fEndpointReq[AEvent];
  fEndpointReq[AEvent]:=ACallback;
end;

procedure TSimpleUSBDevice.SetDescriptorBuffer(var ABuffer; ABufferSize: SizeInt);
begin
  fDescStorage:=@ABuffer;
  fDescStorageSize:=ABufferSize;
  fDescStorageUsed:=0;
end;

function TSimpleUSBDevice.GetDescriptorSize: SizeInt;
begin
  result:=fDescStorageUsed;
end;

procedure TSimpleUSBDevice.SetStrDescriptorBuffer(var ABuffer; ABufferSize: SizeInt);
begin
  fStrDescStorage:=@ABuffer;
  fStrDescStorageSize:=ABufferSize;
  fStrDescStorageUsed:=0;

  AddStringDescriptor(#$0409);
end;

function TSimpleUSBDevice.GetStrDescriptorSize: SizeInt;
begin
  result:=fStrDescStorageUsed;
end;

procedure TSimpleUSBDevice.ConfigureDevice(AVendorID, AProductID, AVersion: word; AManufacturer, AProduct, ASerialNumber: pwidechar; AUSBVersion: TSimpleUSBVersion; AMaxPacketSize: TUSBMaxPacketSize; ADeviceClass, ADeviceSubClass, ADeviceProtocol: word);
const
  versionLUT: array[TSimpleUSBVersion] of word = ($0100, $0110, $0200);
begin
  fDeviceDesc.bLength:=SizeOf(TUsbDeviceDescriptor);
  fDeviceDesc.bDescriptorType:=USB_DESC_TYPE_Device;
  fDeviceDesc.bcdUsb:=versionLUT[AUSBVersion];
  fDeviceDesc.bDeviceClass:=ADeviceClass;
  fDeviceDesc.bDeviceSubClass:=ADeviceSubClass;
  fDeviceDesc.bDeviceProtocol:=ADeviceProtocol;
  fDeviceDesc.bMaxPacketSize:=AMaxPacketSize;
  fDeviceDesc.idVendor:=AVendorID;
  fDeviceDesc.idProduct:=AProductID;
  fDeviceDesc.bcdDevice:=AVersion;
  fDeviceDesc.iManufacturer:=AddStringDescriptor(AManufacturer);
  fDeviceDesc.iProduct:=AddStringDescriptor(AProduct);
  fDeviceDesc.iSerialNumber:=AddStringDescriptor(ASerialNumber);
  fDeviceDesc.bNumConfigurations:=0;
end;

function TSimpleUSBDevice.GetConfig(AConfigValue: byte): TSimpleUSBConfigDescriptor;
var
  desc: PUsbDescriptor;
  len: SizeInt;
begin
  desc:=FindCfgDesc(AConfigValue, len);

  if desc<>nil then
    result:=TSimpleUSBConfigDescriptor.Create(@self, TSimpleUSBDescriptor.Create(@self, desc))
  else
    Error('No config found');
end;

function TSimpleUSBDevice.AddConfiguration(AConfigValue: byte; AConfigAttributes: TSimpleUSBConfigAttributes; AMaxPower_ma: word; AName: pwidechar): TSimpleUSBConfigDescriptor;
var
  desc: TSimpleUSBDescriptor;
  cfg: PUsbConfigurationDescriptor;
  attr: TSimpleUSBConfigAttribute;
begin
  inc(fDeviceDesc.bNumConfigurations);

  desc:=AllocateDescriptor(sizeof(TUsbConfigurationDescriptor));
  cfg:=PUsbConfigurationDescriptor(desc.Buffer);

  cfg^.bLength:=SizeOf(TUsbConfigurationDescriptor);
  cfg^.bDescriptorType:=USB_DESC_TYPE_Configuration;
  cfg^.wTotalLength:=SizeOf(TUsbConfigurationDescriptor);
  cfg^.bNumInterfaces:=0;
  cfg^.bConfigurationValue:=AConfigValue;
  cfg^.iConfiguration:=AddStringDescriptor(AName);
  cfg^.bmAttributes:=$80;
  for attr in AConfigAttributes do
     cfg^.bmAttributes:=cfg^.bmAttributes or byte(attr);
  cfg^.bMaxPower:=AMaxPower_ma div 2;

  result:=TSimpleUSBConfigDescriptor.Create(@self, desc);
end;

function TSimpleUSBDevice.AddStringDescriptor(AStr: pwidechar): byte;
var
  len, addr: SizeInt;
  ptr: pbyte;
begin
  if AStr=nil then
    result:=0
  else
  begin
    len:=Length(AStr)*2;

    addr:=fStrDescStorageUsed;

    if (fStrDescStorageSize-(addr+2+len)) < 0 then
    begin
      result:=0;
      Error('Out of string desc space');
    end
    else
    begin
      ptr:=@fStrDescStorage[addr];
      ptr[0]:=len+2;
      ptr[1]:=USB_DESC_TYPE_String;
      move(AStr^, ptr[2], len);

      result:=fStrDescIndex;    
      inc(fStrDescIndex);
    end;                 
    inc(fStrDescStorageUsed, len+2);
  end;
end;

constructor TSimpleUSBConfigDescriptor.Create(ADevice: PSimpleUSBDevice; const AConfigDesc: TSimpleUSBDescriptor);
begin
  fDevice:=ADevice;
  fConfigDesc:=AConfigDesc;
end;

function TSimpleUSBConfigDescriptor.AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;
begin
  result:=fDevice^.AllocateDescriptor(ASize);

  inc(PUsbConfigurationDescriptor(fConfigDesc.Buffer)^.wTotalLength, ASize);
end;

function TSimpleUSBConfigDescriptor.AddInterface(AInterfaceNumber, AAltSetting: byte; AClass, ASubClass, AProtocol: word; AName: pwidechar): TSimpleUSBInterfaceDescriptor;
var
  desc: TSimpleUSBDescriptor;
  intf: PUsbInterfaceDescriptor;
begin
  inc(PUsbConfigurationDescriptor(fConfigDesc.Buffer)^.bNumInterfaces);

  desc:=AllocateDescriptor(sizeof(TUsbInterfaceDescriptor));
  intf:=PUsbInterfaceDescriptor(desc.Buffer);

  intf^.bLength:=SizeOf(TUsbInterfaceDescriptor);
  intf^.bDescriptorType:=USB_DESC_TYPE_Interface;   
  intf^.bInterfaceNumber:=AInterfaceNumber;
  intf^.bAlternateSetting:=AAltSetting;
  intf^.bNumEndpoints:=0;
  intf^.bInterfaceClass:=AClass;
  intf^.bInterfaceSubClass:=ASubClass;
  intf^.bInterfaceProtocol:=AProtocol;
  intf^.iInterface:=fDevice^.AddStringDescriptor(AName);

  result:=TSimpleUSBInterfaceDescriptor.Create(@self, desc);
end;

constructor TSimpleUSBInterfaceDescriptor.Create(AConfig: PSimpleUSBConfigDescriptor; const AIntfDesc: TSimpleUSBDescriptor);
begin
  fConfig:=AConfig;
  fIntfDesc:=AIntfDesc;
end;

function TSimpleUSBInterfaceDescriptor.AllocateDescriptor(ASize: SizeInt): TSimpleUSBDescriptor;
begin
  result:=fConfig^.AllocateDescriptor(ASize);
end;

procedure TSimpleUSBInterfaceDescriptor.AddEndpoint(ADirection: TSimpleUSBDirection; AAddress: TSimpleUSBAddress; AType: TSimpleUSBEndpointType; AMaxPacketSize: word; AInterval: byte);
const
  dirLut: array[TSimpleUSBDirection] of byte = ($00, $80);
  attrLUT: array[TSimpleUSBEndpointType] of byte = (USB_ENDPOINT_TYPE_Control, USB_ENDPOINT_TYPE_Isochronous, USB_ENDPOINT_TYPE_Bulk, USB_ENDPOINT_TYPE_Interrupt);
var
  desc: TSimpleUSBDescriptor;
  ep: PUsbEndpointDescriptor;
begin
  inc(PUsbInterfaceDescriptor(fIntfDesc.Buffer)^.bNumEndpoints);
                                                        
  desc:=AllocateDescriptor(sizeof(TUsbEndpointDescriptor));
  ep:=PUsbEndpointDescriptor(desc.Buffer);

  ep^.bLength:=SizeOf(TUsbEndpointDescriptor);
  ep^.bDescriptorType:=USB_DESC_TYPE_Endpoint;
  ep^.bEndpointAddress:=AAddress or dirLut[ADirection];
  ep^.bmAttributes:=attrLUT[AType];
  ep^.wMaxPacketSize:=AMaxPacketSize;
  ep^.bInterval:=AInterval;
end;

end.

