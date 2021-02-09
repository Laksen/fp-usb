unit simpleusb_msd;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  simpleusb, USBCore,
  USBClassMSD;

type
  TMSDState = (
    msIdle,
    msCommand,
    msIO,
    msReadMore,
    msWrite,
    msStatus
  );

  TSCSIResult = (
    srCommandPassed,
    srCommandFailed,
    srPhaseError
  );

  TMSDDevice = record
  private
    fDevice: PSimpleUSBDevice;

    fEP: Byte;
    fIntf: Byte;

    fConfigCallback: TSimpleUSBConfigCallback;

    fControlCallback: TSimpleUSBControlReqCallback;
    fControlRXCallback: TSimpleUSBControlReqCallback;
    fControlDoneCallback: TSimpleUSBControlReqCallback;

    fEndpointTXCallback, fEndpointRXCallback: TSimpleUSBCompleteCallback;
  private
    fState: TMSDState;

    fTXBuffer: pbyte;
    fTXLeft: SizeInt;
    fTXNext: TMSDState;

    fCommandBlock: TUSBMSDCommandBlockWrapper;
    fCommandLeft,
    fCommandPos: SizeInt;

    fStatus: TUSBMSDCommandStatusWrapper;

    fBlockCount: word;
    fBlockOffset: longword;

    function ExecuteSCSI(cmd: pbyte; ACmdLength: SizeInt): TSCSIResult;
                                                                           
    procedure DoPush;
    procedure DoTX(var AData; ASize: SizeInt; ANextState: TMSDState; ADoPush: boolean = true);
  private
    procedure DoConfigure(ADevice: PSimpleUSBDevice; AConfig: byte);

    function DoControlReq(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
    function DoControlRX(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
    function DoControlDone(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;

    procedure DoEndpointRX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
    procedure DoEndpointTX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
  public
    procedure Init(ADevice: PSimpleUSBDevice; AIntf, AEP: byte);
  end;

implementation

type
  TSCSICmd = (
    TEST_UNIT_READY = $00,
    REWIND = $01,
    REQUEST_SENSE = $03,
    FORMAT = $04,
    READ_BLOCK_LIMITS = $05,
    REASSIGN_BLOCKS = $07,
    INITIALIZE_ELEMENT_STATUS = $07,
    READ_6 = $08,
    WRITE_6 = $0A,
    SEEK_6 = $0B,
    READ_REVERSE_6 = $0F,
    WRITE_FILEMARKS_6 = $10,
    SPACE_6 = $11,
    INQUIRY = $12,
    VERIFY_6 = $13,
    RECOVER_BUFFERED_DATA = $14,
    MODE_SELECT_6 = $15,
    RESERVE_6 = $16,
    RELEASE_6 = $17,
    COPY = $18,
    ERASE_6 = $19,
    MODE_SENSE_6 = $1A,
    START_STOP_UNIT = $1B,
    LOAD_UNLOAD = $1B,
    RECEIVE_DIAGNOSTIC_RESULTS = $1C,
    SEND_DIAGNOSTIC = $1D,
    PREVENT_ALLOW_MEDIUM_REMOVAL = $1E,
    READ_FORMAT_CAPACITIES = $23,
    READ_CAPACITY_10 = $25,
    READ_10 = $28,
    READ_GENERATION = $29,
    WRITE_10 = $2A,
    SEEK_10 = $2B,
    LOCATE_10 = $2B,
    ERASE_10 = $2C,
    READ_UPDATED_BLOCK = $2D,
    WRITE_AND_VERIFY_10 = $2E,
    VERIFY_10 = $2F,
    SET_LIMITS_10 = $33,
    PRE_FETCH_10 = $34,
    READ_POSITION = $34,
    SYNCHRONIZE_CACHE_10 = $35,
    LOCK_UNLOCK_CACHE_10 = $36,
    READ_DEFECT_DATA_10 = $37,
    INITIALIZE_ELEMENT_STATUS_WITH_RANGE = $37,
    MEDIUM_SCAN = $38,
    COMPARE = $39,
    COPY_AND_VERIFY = $3A,
    WRITE_BUFFER = $3B,
    READ_BUFFER = $3C,
    UPDATE_BLOCK = $3D,
    READ_LONG_10 = $3E,
    WRITE_LONG_10 = $3F,
    CHANGE_DEFINITION = $40,
    WRITE_SAME_10 = $41,
    UNMAP = $42,
    READ_TOC_PMA_ATIP = $43,
    REPORT_DENSITY_SUPPORT = $44,
    PLAY_AUDIO_10 = $45,
    GET_CONFIGURATION = $46,
    PLAY_AUDIO_MSF = $47,
    SANITIZE = $48,
    GET_EVENT_STATUS_NOTIFICATION = $4A,
    PAUSE_RESUME = $4B,
    LOG_SELECT = $4C,
    LOG_SENSE = $4D,
    XDWRITE_10 = $50,
    XPWRITE_10 = $51,
    READ_DISC_INFORMATION = $51,
    XDREAD_10 = $52,
    XDWRITEREAD_10 = $53,
    SEND_OPC_INFORMATION = $54,
    MODE_SELECT_10 = $55,
    RESERVE_10 = $56,
    RELEASE_10 = $57,
    REPAIR_TRACK = $58,
    MODE_SENSE_10 = $5A,
    CLOSE_TRACK_SESSION = $5B,
    READ_BUFFER_CAPACITY = $5C,
    SEND_CUE_SHEET = $5D,
    PERSISTENT_RESERVE_IN = $5E,
    PERSISTENT_RESERVE_OUT = $5F,
    extended_CDB = $7E,
    variable_length_CDB = $7F,
    XDWRITE_EXTENDED_16 = $80,
    WRITE_FILEMARKS_16 = $80,
    READ_REVERSE_16 = $81,
    Third_party_Copy_OUT_commands = $83,
    Third_party_Copy_IN_commands = $84,
    ATA_PASS_THROUGH_16 = $85,
    ACCESS_CONTROL_IN = $86,
    ACCESS_CONTROL_OUT = $87,
    READ_16 = $88,
    COMPARE_AND_WRITE = $89,
    WRITE_16 = $8A,
    ORWRITE = $8B,
    READ_ATTRIBUTE = $8C,
    WRITE_ATTRIBUTE = $8D,
    WRITE_AND_VERIFY_16 = $8E,
    VERIFY_16 = $8F,
    PRE_FETCH_16 = $90,
    SYNCHRONIZE_CACHE_16 = $91,
    SPACE_16 = $91,
    LOCK_UNLOCK_CACHE_16 = $92,
    LOCATE_16 = $92,
    WRITE_SAME_16 = $93,
    ERASE_16 = $93,
    SERVICE_ACTION_BIDIRECTIONAL = $9D,
    SERVICE_ACTION_IN_16 = $9E,
    SERVICE_ACTION_OUT_16 = $9F,
    REPORT_LUNS = $A0,
    ATA_PASS_THROUGH_12 = $A1,
    SECURITY_PROTOCOL_IN = $A2,
    MAINTENANCE_IN = $A3,
    MAINTENANCE_OUT = $A4,
    REPORT_KEY = $A4,
    MOVE_MEDIUM = $A5,
    PLAY_AUDIO_12 = $A5,
    EXCHANGE_MEDIUM = $A6,
    MOVE_MEDIUM_ATTACHED = $A7,
    READ_12 = $A8,
    SERVICE_ACTION_OUT_12 = $A9,
    WRITE_12 = $AA,
    SERVICE_ACTION_IN_12 = $AB,
    ERASE_12 = $AC,
    READ_DVD_STRUCTURE = $AD,
    WRITE_AND_VERIFY_12 = $AE,
    VERIFY_12 = $AF,
    SEARCH_DATA_HIGH_12 = $B0,
    SEARCH_DATA_EQUAL_12 = $B1,
    SEARCH_DATA_LOW_12 = $B2,
    SET_LIMITS_12 = $B3,
    READ_ELEMENT_STATUS_ATTACHED = $B4,
    SECURITY_PROTOCOL_OUT = $B5,
    SEND_VOLUME_TAG = $B6,
    READ_DEFECT_DATA_12 = $B7,
    READ_ELEMENT_STATUS = $B8,
    READ_CD_MSF = $B9,
    REDUNDANCY_GROUP_IN = $BA,
    REDUNDANCY_GROUP_OUT = $BB,
    SPARE_IN = $BC,
    SPARE_OUT = $BD,
    VOLUME_SET_IN = $BE,
    VOLUME_SET_OUT = $BF
  );

var
  {$packrecords 1}
  inquiry_data: record
    periph,
    rmb,
    version,
    response,
    additionalLength,
    flags0,
    flags1,
    flags2: byte;
    t10_id: array[0..7] of char;
    product_id: array[0..15] of char;
    product_revision: array[0..3] of char;
  end;

  mode_sense: record
    a,
    b,
    c,
    d: byte;
  end;

  read_cap: record
    last_block,
    block_length: longword;
  end;

  block: array[0..511] of byte;

procedure TMSDDevice.DoPush;
var
  r: SizeInt;
begin
  if fTXLeft>0 then
  begin
    r:=fDevice^.EndpointWrite(TXEndpoint(fEP), fTXBuffer, fTXLeft);

    //writeln('>', r, '(', fTXLeft,')');

    dec(fTXLeft,   r);
    inc(fTXBuffer, r);

    if fTXLeft=0 then
    begin
      if fState=msReadMore then
      begin
        dec(fBlockCount);

        if fBlockCount=0 then
          fTXNext:=msStatus
        else
          DoTX(block, 512, msReadMore, false);
      end;

      if fTXNext=msStatus then
        DoTX(fstatus, sizeof(fStatus), msIdle, false);

      fstate:=fTXNext;
    end;
  end;
end;

procedure TMSDDevice.DoEndpointTX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
begin
  if EndpointAddress(AEndpoint)=fEP then
  begin
    DoPush;
  end
  else if assigned(fEndpointTXCallback) then
    fEndpointTXCallback(ADevice, AEndpoint);
end;

procedure TMSDDevice.DoEndpointRX(ADevice: PSimpleUSBDevice; AEndpoint: byte);
var
  r: SizeInt;
  res: TSCSIResult;
begin
  if AEndpoint=fEP then
  begin
    if fState=msIdle then
    begin
      fCommandLeft:=31;
      fCommandPos:=0;

      fState:=msCommand;
    end;

    if fState=msCommand then
    begin
      r:=fDevice^.EndpointRead(AEndpoint, @pbyte(@fCommandBlock)[fCommandPos], fCommandLeft);

      dec(fCommandLeft, r);
      inc(fCommandPos,  r);

      if fCommandLeft=0 then
      begin
        {writeln(' Sig: ', hexstr(fCommandBlock.dCBWSignature, 8));
        writeln(' Tag: ', hexstr(fCommandBlock.dCBWTag, 8));
        writeln(' TL:  ', hexstr(fCommandBlock.dCBWDataTransferLength, 8));
        writeln(' Flg: ', hexstr(fCommandBlock.bmCBWFlags, 8));
        writeln(' Lun: ', hexstr(fCommandBlock.bCBWLUN, 8));
        writeln(' Len: ', hexstr(fCommandBlock.bCBWCBLength, 8));}

        fState:=msIO;
        fTXNext:=msIdle;
                      
        res:=ExecuteSCSI(@fCommandBlock.CBWCB[0], fCommandBlock.bCBWCBLength);

        fStatus.dCSWSignature:=CBSSignature;
        fStatus.dCSWTag:=fCommandBlock.dCBWTag;
        fStatus.dCSWDataResidue:=0;
        fStatus.bCSWStatus:=byte(res);

        if (fState<>msStatus) and (fState<>msWrite) and (fTXLeft=0) then
          DoTX(fStatus, sizeof(fStatus), msIdle);
      end;
    end
    else if fState=msWrite then
    begin
      r:=fDevice^.EndpointRead(AEndpoint, @block[fCommandPos], fCommandLeft);

      dec(fCommandLeft, r);
      inc(fCommandPos,  r);

      if fCommandLeft=0 then
      begin
        dec(fBlockCount);

        if fBlockCount=0 then
          DoTX(fStatus, sizeof(fStatus), msIdle);
      end;
    end;
  end
  else if assigned(fEndpointRXCallback) then
    fEndpointRXCallback(ADevice, AEndpoint);
end;

function TMSDDevice.ExecuteSCSI(cmd: pbyte; ACmdLength: SizeInt): TSCSIResult;
begin
  result:=srCommandFailed;

  //writeln(TSCSICmd(cmd[0]));

  case TSCSICmd(cmd[0]) of
    INQUIRY:
      begin
        with inquiry_data do
        begin
          periph:=$00;
          rmb:=0;
          version:=5;
          response:=2;
          additionalLength:=$1F;
          flags0:=0;
          flags1:=$80;
          flags2:=0;

          t10_id:='laks';
          product_id:='mega disk';
          product_revision:='1337';
        end;
                       
        result:=srCommandPassed;

        DoTX(inquiry_data, 36, msStatus);
      end;
    TEST_UNIT_READY:
      begin
        result:=srCommandPassed;
      end;
    MODE_SENSE_6:
      begin
        with mode_sense do
        begin
          a:=3;                         
        end;

        result:=srCommandPassed;

        DoTX(mode_sense, 4, msStatus);
      end;
    START_STOP_UNIT:
      begin
        result:=srCommandPassed;
      end;
    PREVENT_ALLOW_MEDIUM_REMOVAL:
      begin
        result:=srCommandPassed;
      end;
    READ_CAPACITY_10:
      begin
        with read_cap do
        begin
          last_block  :=$00000000;
          block_length:=$00020000;
        end;

        result:=srCommandPassed;

        DoTX(read_cap, 8, msStatus);
      end;
    READ_10:
      begin
        result:=srCommandPassed;

        fBlockOffset:=BEtoN(plongword(@cmd[2])^);
        fBlockCount:=BEtoN(pword(@cmd[7])^);

        fState:=msReadMore;
        DoTX(block[0], 512, msStatus);
      end;
    WRITE_10:
      begin
        result:=srCommandPassed; 

        fBlockOffset:=BEtoN(plongword(@cmd[2])^);
        fBlockCount:=BEtoN(pword(@cmd[7])^);

        fCommandLeft:=512;
        fCommandPos:=0;

        fState:=msWrite;
      end;
    VERIFY_10:;
  end;
end;

procedure TMSDDevice.DoTX(var AData; ASize: SizeInt; ANextState: TMSDState; ADoPush: boolean);
begin
  fTXBuffer:=@AData;
  fTXLeft:=ASize;
  fTXNext:=ANextState;

  if ADoPush then
    DoPush;
end;

procedure TMSDDevice.DoConfigure(ADevice: PSimpleUSBDevice; AConfig: byte);
begin
  fState:=msIdle;

  //fDevice^.EndpointWrite(TXEndpoint(fEP),nil,0);
  if assigned(fConfigCallback) then
    fConfigCallback(ADevice, AConfig);
end;

function TMSDDevice.DoControlReq(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
var
  maxLun: byte;
begin
  if ARequest.wIndex=fIntf then
  begin
    result:=urACK;
    case TUSBMSDRequest(ARequest.bRequest) of
      mrGetMaxLUN:
        begin
          maxLun:=0;
          fDevice^.EndpointControlWrite(AEndpoint, @maxLun, sizeof(maxLun));
        end;
      mrReset:;
    else
      result:=urStall;
    end;
  end
  else if assigned(fControlCallback) then
    result:=fControlCallback(ADevice, AEndpoint, ARequest)
  else
    result:=urStall;
end;

function TMSDDevice.DoControlRX(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
begin
  result:=urStall;
  if ARequest.wIndex=fIntf then
  begin
    case TUSBMSDRequest(ARequest.bRequest) of
      mrGetMaxLUN:;
      mrReset:;
    end;
  end
  else if assigned(fControlRXCallback) then
    result:=fControlRXCallback(ADevice, AEndpoint, ARequest);
end;

function TMSDDevice.DoControlDone(ADevice: PSimpleUSBDevice; AEndpoint: byte; var ARequest: TUsbControlRequest): TSimpleUSBResponse;
begin
  if assigned(fControlDoneCallback) then
    result:=fControlDoneCallback(ADevice, AEndpoint, ARequest)
  else
    result:=urStall;
end;

procedure TMSDDevice.Init(ADevice: PSimpleUSBDevice; AIntf, AEP: byte);
begin
  fDevice:=ADevice;

  fEP:=AEP;
  fIntf:=AIntf;

  fConfigCallback:=fDevice^.AddConfigCallback(ueConfigured, @DoConfigure);

  fControlCallback:=fDevice^.AddControlCallback(ueControlRequest, @DoControlReq);
  fControlRXCallback:=fDevice^.AddControlCallback(ueControlRX, @DoControlRX);
  fControlDoneCallback:=fDevice^.AddControlCallback(ueControlDone, @DoControlDone);

  fEndpointRXCallback:=fDevice^.AddEndpointCallback(ueRX, @DoEndpointRX);
  fEndpointTXCallback:=fDevice^.AddEndpointCallback(ueTX, @DoEndpointTX);
end;

end.

