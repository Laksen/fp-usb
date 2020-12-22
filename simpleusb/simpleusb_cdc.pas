unit simpleusb_cdc;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  simpleusb, USBCore,
  USBClassCDC;

const
  CDC_DATA_SZ = $40;

type
  TSimpleUSBCDCVersion = (cdcV11);

  TCDCIntfHelpers = record helper for TSimpleUSBInterfaceDescriptor
    procedure AddCDCHeaderDesc(AVersion: TSimpleUSBCDCVersion);
    procedure AddCDCCallDesc(ACapabilities, ADataInterface: byte);
    procedure AddCDCACMDesc(ACapabilities: byte);
    procedure AddCDCUnionDesc(AMasterInterface, ASlaveInterface: byte);
  end;

  PCDCDevice = ^TCDCDevice;
  TCDCDevice = record
  private
    fDevice: PSimpleUSBDevice;
    fCtrlIntf, fDataIntf: byte;
    fCtrlEP, fDataEP: byte;

    fConfigCallback: TSimpleUSBConfigCallback;

    fControlCallback: TSimpleUSBControlReqCallback;
    fControlRXCallback: TSimpleUSBControlReqCallback;
    fControlDoneCallback: TSimpleUSBControlReqCallback;

    fEndpointRXCallback: TSimpleUSBCompleteCallback;
    fEndpointTXCallback: TSimpleUSBCompleteCallback;

    // ACM State
    fLineCoding: TUSB_CDC_ACM_LINE_CODING;

    fTXBuffer: pbyte;
    fTXBufferSize: SizeInt;
    fTXPos: longint;

    fRXBuffer: pbyte;
    fRXBufferSize: SizeInt;
    fRXPos: longint;

    fBlocking: boolean;

    procedure DoConfigure(ADevice: PSimpleUSBDevice; AConfig: byte);

    function DoControlReq(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
    function DoControlRX(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
    function DoControlDone(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;

    procedure DoEndpointRX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
    procedure DoEndpointTX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
  public
    constructor Create(ADevice: PSimpleUSBDevice; ACtrlIntf, ADataIntf, ADataEP, ACtrlEP: byte; var ARXBuffer, ATXBuffer: array of byte);

    // Data interface
    function Write(const AData; ASize: SizeInt): SizeInt;
    function Read(var ABuffer; ASize: SizeInt): SizeInt;

    property Blocking: boolean read fBlocking write fBlocking;
  end;

  TSimpleCDC = record helper for TSimpleUSBDevice
    procedure AddCDC(out ADevice: TCDCDevice; AConfigValue: byte; var ARXBuffer, ATXBuffer: array of byte);
  end;

implementation

type
  PUsbCdcHeaderDescriptor = ^TUsbCdcHeaderDescriptor;
  PUsbCdcCallDescriptor   = ^TUsbCdcCallDescriptor;
  PUsbCdcAcmDescriptor    = ^TUsbCdcAcmDescriptor;
  PUsbCdcUnionDescriptor  = ^TUsbCdcUnionDescriptor;

procedure TSimpleCDC.AddCDC(out ADevice: TCDCDevice; AConfigValue: byte; var ARXBuffer, ATXBuffer: array of byte);
var
  CtrlIntf, DataIntf, DataEP, CtrlEP: Byte;
begin
  CtrlIntf:=AllocateInterface;
  DataIntf:=AllocateInterface;

  CtrlEP:=AllocateEndpoint;
  DataEP:=AllocateEndpoint;

  with GetConfig(AConfigValue) do
  begin
    with AddInterface(CtrlIntf, 0, USB_CDC_IC_COMM, USB_CDC_ISC_ACM, USB_CDC_IP_NONE) do
    begin
      AddCDCHeaderDesc(cdcV11);
      AddCDCCallDesc(0, DataIntf);
      AddCDCACMDesc(0);
      AddCDCUnionDesc(CtrlIntf, DataIntf);

      AddEndpoint(dirFromDevice, CtrlEP, setInterrupt, 8);
    end;
    with AddInterface(DataIntf, 0, USB_CDC_IC_DATA, USB_CDC_ISC_NONE, USB_CDC_IP_NONE) do
    begin
      AddEndpoint(dirToDevice,   DataEP, setBulk, length(ARXBuffer));
      AddEndpoint(dirFromDevice, DataEP, setBulk, length(ATXBuffer));
    end;
  end;

  ADevice:=TCDCDevice.Create(@self, CtrlIntf, DataIntf, DataEP, CtrlEP, ARXBuffer, ATXBuffer);
end;
               
procedure TCDCDevice.DoConfigure(ADevice: PSimpleUSBDevice; AConfig: byte);
begin
  fDevice^.EndpointWrite(TXEndpoint(fDataEP),nil,0);
  //writeln('fg: ', hexstr(fConfigCallback.Data),',', hexstr(fConfigCallback.Method));
  if assigned(fConfigCallback) then
    fConfigCallback(ADevice, AConfig);
end;
                      
function TCDCDevice.DoControlReq(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
begin
  if ARequest.wIndex=fCtrlIntf then
  begin
    result:=urACK;
    writeln(ARequest.bRequest);
    case ARequest.bRequest of
      USB_CDC_REQ_GET_LINE_CODING:
        begin
          fDevice^.EndpointControlWrite(AEndpoint, @fLineCoding, sizeof(fLineCoding));
        end;
      USB_CDC_REQ_SET_LINE_CODING:;
      USB_CDC_REQ_SET_CONTROL_LINE_STATE:
        writeln('alright');
    else
      result:=urStall;
    end;
  end
  else if assigned(fControlCallback) then
    result:=fControlCallback(ADevice, AEndpoint, ARequest)
  else
    result:=urStall;
end;

function TCDCDevice.DoControlRX(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
var
  r: SizeInt;                    
  buf: array[0..15] of byte;
begin
  result:=urStall;
  if ARequest.wIndex=fCtrlIntf then
  begin
    case ARequest.bRequest of
      USB_CDC_REQ_SET_LINE_CODING:
        r:=fDevice^.EndpointControlRead(AEndpoint,@fLineCoding,sizeof(fLineCoding));
      USB_CDC_REQ_SET_CONTROL_LINE_STATE:
        begin
          r:=fDevice^.EndpointControlRead(AEndpoint,@buf[0],sizeof(buf));
          writeln('Read ');
        end;
    end;
  end
  else if assigned(fControlRXCallback) then
    result:=fControlRXCallback(ADevice, AEndpoint, ARequest);
end;

function TCDCDevice.DoControlDone(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
begin
  if assigned(fControlDoneCallback) then
    result:=fControlDoneCallback(ADevice, AEndpoint, ARequest)
  else
    result:=urStall;
end;

procedure TCDCDevice.DoEndpointRX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
var
  r: SizeInt;
begin
    writeln('iRX');
  if AEndpoint=fDataEP then
  begin           
    writeln('RX');
    if fRXPos<fRXBufferSize then
    begin
      r:=fDevice^.EndpointRead(AEndpoint,@fRXBuffer[fRXPos],fRXBufferSize-fRXPos);
      if r>0 then inc(fRXPos,r);
    writeln('RX ', r);
    end;
  end
  else if assigned(fEndpointRXCallback) then
    fEndpointRXCallback(ADevice, AEndpoint);
end;

procedure TCDCDevice.DoEndpointTX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
var
  r: SizeInt;
begin
  if EndpointAddress(AEndpoint)=fDataEP then
  begin
    r:=fDevice^.EndpointWrite(TXEndpoint(fDataEP),@fTXBuffer[0],fTXPos);
    writeln('tx ', fTXPos,',',r);

    Dec(fTXPos,r);
    Move(fTXBuffer[r],fTXBuffer[0],fTXPos);
  end
  else if assigned(fEndpointTXCallback) then
    fEndpointTXCallback(ADevice, AEndpoint);
end;

constructor TCDCDevice.Create(ADevice: PSimpleUSBDevice; ACtrlIntf, ADataIntf, ADataEP, ACtrlEP: byte; var ARXBuffer, ATXBuffer: array of byte);
begin
  fDevice:=ADevice;

  fCtrlIntf:=ACtrlIntf;
  fDataIntf:=ADataIntf;
  fCtrlEP:=ACtrlEP;
  fDataEP:=ADataEP;

  fBlocking:=true;

  fConfigCallback:=fDevice^.AddConfigCallback(ueConfigured, @DoConfigure);

  fControlCallback:=fDevice^.AddControlCallback(ueControlRequest, @DoControlReq);
  fControlRXCallback:=fDevice^.AddControlCallback(ueControlRX, @DoControlRX);
  fControlDoneCallback:=fDevice^.AddControlCallback(ueControlDone, @DoControlDone);

  fEndpointRXCallback:=fDevice^.AddEndpointCallback(ueRX, @DoEndpointRX);
  fEndpointTXCallback:=fDevice^.AddEndpointCallback(ueTX, @DoEndpointTX);

  fRXBuffer:=@ARXBuffer[0];
  fTXBuffer:=@ATXBuffer[0];
  fRXBufferSize:=length(ARXBuffer);
  fTXBufferSize:=length(ATXBuffer);
end;

function TCDCDevice.Write(const AData; ASize: SizeInt): SizeInt;
var
  ptr: pbyte;
  left: SizeInt;
begin
  result:=0;
  ptr:=@AData;

  while ASize>0 do
  begin
    if fTXPos>=fTXBufferSize then
    begin
      if fBlocking then
        fDevice^.Poll
      else
        break;
    end
    else
    begin
      left:=fTXBufferSize-fTXPos;
      if left > ASize then
        left:=ASize;

      move(ptr[result], fTXBuffer[fTXPos], left);

      inc(fTXPos, left);
      dec(ASize, left);
      inc(result,left);
    end;
  end;
end;

function TCDCDevice.Read(var ABuffer; ASize: SizeInt): SizeInt;
var
  left: SizeInt;
  ptr: pbyte;
begin
  Result:=0; 
  ptr:=@ABuffer;

  while ASize>0 do
  begin
    if fRXPos<=0 then
    begin
      if fBlocking then
        fDevice^.Poll
      else
        break;
    end
    else
    begin        
      left:=fRXPos;
      if left > ASize then
        left:=ASize;

      move(fRXBuffer[0], ptr[result], left);

      if fRXPos>left then
        move(fRXBuffer[left], fRXBuffer[0], fRXPos-left);

      dec(fRXPos, left);
      dec(ASize, left);
      inc(result,left);
    end;
  end;
end;

procedure TCDCIntfHelpers.AddCDCHeaderDesc(AVersion: TSimpleUSBCDCVersion);
const
  versionLut: array[TSimpleUSBCDCVersion] of word = ($0110);
var
  desc: TSimpleUSBDescriptor;
  p: PUsbCdcHeaderDescriptor;
begin
  desc:=AllocateDescriptor(sizeof(p^));
  p:=PUsbCdcHeaderDescriptor(desc.Buffer);

  p^.bFunctionLength:=sizeof(p^);
  p^.bDescriptorType:=USB_DESC_TYPE_CsInterface;
  p^.bDescriptorSubType:=USB_DESC_TYPE_CdcHeader;
  p^.bcdCDC:=versionLut[AVersion];
end;

procedure TCDCIntfHelpers.AddCDCCallDesc(ACapabilities, ADataInterface: byte);
var
  desc: TSimpleUSBDescriptor;
  p: PUsbCdcCallDescriptor;
begin
  desc:=AllocateDescriptor(sizeof(p^));
  p:=PUsbCdcCallDescriptor(desc.Buffer);

  p^.bFunctionLength:=sizeof(p^);
  p^.bDescriptorType:=USB_DESC_TYPE_CsInterface;
  p^.bDescriptorSubType:=USB_DESC_TYPE_CdcCall;
  p^.bmCapabilities:=ACapabilities;
  p^.bDataInterface:=ADataInterface;
end;

procedure TCDCIntfHelpers.AddCDCACMDesc(ACapabilities: byte);
var
  desc: TSimpleUSBDescriptor;
  p: PUsbCdcAcmDescriptor;
begin
  desc:=AllocateDescriptor(sizeof(p^));
  p:=PUsbCdcAcmDescriptor(desc.Buffer);

  p^.bFunctionLength:=sizeof(p^);
  p^.bDescriptorType:=USB_DESC_TYPE_CsInterface;
  p^.bDescriptorSubType:=USB_DESC_TYPE_CdcAcm;
  p^.bmCapabilities:=ACapabilities;
end;

procedure TCDCIntfHelpers.AddCDCUnionDesc(AMasterInterface, ASlaveInterface: byte);
var
  desc: TSimpleUSBDescriptor;
  p: PUsbCdcUnionDescriptor;
begin
  desc:=AllocateDescriptor(sizeof(p^));
  p:=PUsbCdcUnionDescriptor(desc.Buffer);

  p^.bFunctionLength:=sizeof(p^);
  p^.bDescriptorType:=USB_DESC_TYPE_CsInterface;
  p^.bDescriptorSubType:=USB_DESC_TYPE_CdcUnion;
  p^.bMasterInterface:=AMasterInterface;
  p^.bSlaveInterface:=ASlaveInterface;
end;

end.

