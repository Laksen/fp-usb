// Heavily inspired from the STM32 driver from this project:
// https://github.com/dmitrystu/libusb_stm32/blob/master/src/usbd_stm32f103_devfs.c

(* This file is the part of the Lightweight USB device Stack for STM32 microcontrollers
 *
 * Copyright ©2016 Dmitry Filimonchuk <dmitrystu[at]gmail[dot]com>
 * Copyright ©2017 Max Chan <max[at]maxchan[dot]info>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *   http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)
unit USBHAL;

interface

uses
  USBCore;

type
  TDriverEvent = (deReset, deError,
                  deWakeup, deSuspend,
                  deSOF, deSetup, deRx, deTx);
  TDriverCallback = procedure(AData: pointer; AEvent: TDriverEvent; AEndpoint: byte);

procedure DriverState(AEnabled: boolean; ACallback: TDriverCallback=nil; AData: pointer=nil);
procedure DriverConnect(AConnect: boolean);

procedure DriverSetAddress(AAddress: byte);

procedure DriverPoll;

function EndpointConfigure(AEndpoint: byte; AType: TEndpointType; AEPSize: SizeInt): boolean;
procedure EndpointDeconfigure(AEndpoint: byte);

function EndpointStalled(AEndpoint: byte): boolean;
procedure EndpointSetStall(AEndpoint: byte; AStall: boolean);

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
function EndpointWrite(AEndpoint: byte; AData: Pointer; ALength: SizeInt): SizeInt;

implementation

const
  RCC_APB1ENR_USBEN = 1 shl 23;
  RCC_APB1RSTR_USBRST = 1 shl 23;

  USB_EP_EA = $F;
  USB_EP_STAT_TX = 3 shl 4;
  USB_EP_DTOG_TX = 1 shl 6;
  USB_EP_CTR_TX = 1 shl 7;
  USB_EP_EP_KIND = 1 shl 8;
  USB_EP_EP_TYPE = 3 shl 9;
  USB_EP_SETUP = 1 shl 11;
  USB_EP_STAT_RX = 3 shl 12;
  USB_EP_DTOG_RX = 1 shl 14;
  USB_EP_CTR_RX = 1 shl 15;

  USB_EP_STAT_TX_DISABLED = 0 shl 4;
  USB_EP_STAT_TX_STALL    = 1 shl 4;
  USB_EP_STAT_TX_NAK      = 2 shl 4;
  USB_EP_STAT_TX_VALID    = 3 shl 4;

  USB_EP_STAT_RX_DISABLED = 0 shl 12;
  USB_EP_STAT_RX_STALL    = 1 shl 12;
  USB_EP_STAT_RX_NAK      = 2 shl 12;
  USB_EP_STAT_RX_VALID    = 3 shl 12;

  USB_EP_TYPE_BULK = 0 shl 9;
  USB_EP_TYPE_CONTROL = 1 shl 9;
  USB_EP_TYPE_ISO = 2 shl 9;
  USB_EP_TYPE_INTERRUPT = 3 shl 9;

  USB_CNTR_CTRM = 1 shl 15;
  USB_CNTR_RESETM = 1 shl 10;
  USB_CNTR_ERRM = 1 shl 13;
  USB_CNTR_SOFM = 1 shl 9;
  USB_CNTR_SUSPM = 1 shl 11;
  USB_CNTR_WKUPM = 1 shl 12;

  USB_ISTR_EP_ID = $F;
  USB_ISTR_CTR = $8000;
  USB_ISTR_RESET = $0400;
  USB_ISTR_SOF = $0200;
  USB_ISTR_WKUP = $1000;
  USB_ISTR_SUSP = $0800;
  USB_CNTR_FSUSP = $0008;
  USB_ISTR_ERR = $2000;

  USB_DADDR_EF = 1 shl 7;

  PMASize = 512;
  PMAStep = 2;

  USB_EP_MASK = USB_EP_CTR_RX or USB_EP_SETUP or USB_EP_EP_TYPE or USB_EP_EP_KIND or USB_EP_CTR_TX or USB_EP_EA;

var
  Callback: TDriverCallback = nil;
  data: pointer;

type
  TBufferDescriptor = record
    Addr,
    res0,
    Count,
    res1: word;
  end;

  PBufferDescriptors = ^TBufferDescriptors;
  TBufferDescriptors = record
    case integer of
      4: (TX,  RX: TBufferDescriptor);
      5: (RX0, RX1: TBufferDescriptor);
      6: (TX0, TX1: TBufferDescriptor);

      7: (RXs: array[boolean] of TBufferDescriptor);
      8: (TXs: array[boolean] of TBufferDescriptor);
  end;

var
  PMA: array[0..(PMASize div 2)-1] of longword absolute USBMem;
  BufferDescriptors: array[0..7] of TBufferDescriptors absolute USBMem;

procedure EP_TOGGLE_SET(epr: pword; bits, mask: word); inline;
begin
  epr^ := (epr^ xor (bits)) and (USB_EP_MASK or (mask));
end;

procedure EP_DTX_UNSTALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_TX_VALID, USB_EP_STAT_TX or USB_EP_DTOG_TX or USB_EP_DTOG_RX);
end;

procedure EP_TX_STALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_TX_STALL, USB_EP_STAT_TX);
end;

procedure EP_TX_UNSTALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_TX_NAK, USB_EP_STAT_TX or USB_EP_DTOG_TX);
end;

procedure EP_TX_VALID(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_TX_VALID, USB_EP_STAT_TX);
end;

procedure EP_DRX_UNSTALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_RX_VALID or USB_EP_DTOG_TX, USB_EP_STAT_RX or USB_EP_DTOG_RX or USB_EP_DTOG_TX);
end;

procedure EP_RX_UNSTALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_RX_VALID, USB_EP_STAT_RX or USB_EP_DTOG_RX);
end;

procedure EP_RX_STALL(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_RX_STALL, USB_EP_STAT_RX);
end;

procedure EP_RX_VALID(epr: pword); inline;
begin
  EP_TOGGLE_SET(epr, USB_EP_STAT_RX_VALID, USB_EP_STAT_RX);
end;

procedure DriverState(AEnabled: boolean; ACallback: TDriverCallback; AData: pointer);
begin
  if AEnabled then
  begin
    Callback:=ACallback;
    data:=AData;

    // Enable USB Perihepral clock
    RCC.APB1ENR := RCC.APB1ENR or RCC_APB1ENR_USBEN;

    // Reset USB Peripheral
    RCC.APB1RSTR := RCC.APB1RSTR or RCC_APB1RSTR_USBRST;
    RCC.APB1RSTR := RCC.APB1RSTR and not RCC_APB1RSTR_USBRST;

    // Enable controller
    USB.CNTR := USB_CNTR_CTRM or USB_CNTR_RESETM or USB_CNTR_ERRM or USB_CNTR_SUSPM or USB_CNTR_WKUPM
{$ifdef USB_HAL_SOF}
    or USB_CNTR_SOFM
{$endif}
    ;
  end
  else
  begin
    Callback:=nil;

    // Disable USB Power
    RCC.APB1ENR := RCC.APB1ENR and (not RCC_APB1ENR_USBEN);
  end;
end;

procedure DriverConnect(AConnect: boolean);
begin
end;

procedure DriverSetAddress(AAddress: byte);
begin
  USB.DADDR:=AAddress or USB_DADDR_EF;
end;

procedure DriverPoll;
var
  reg: PLongWord;
  event: TDriverEvent;
  i: integer;
  istatus, endpoint: longword;
begin
  istatus := USB.ISTR;
  endpoint := istatus and USB_ISTR_EP_ID;

  if (istatus and USB_ISTR_CTR) <> 0 then
  begin
    reg := @USB.EPR[endpoint];
    if (reg^ and USB_EP_CTR_TX) <> 0 then
    begin
      reg^ := reg^ and (USB_EP_MASK xor USB_EP_CTR_TX);
      endpoint := endpoint or $80;
      event := deTx;
    end
    else
    begin
      reg^ := reg^ and (USB_EP_MASK xor USB_EP_CTR_RX);
      if (reg^ and USB_EP_SETUP) <> 0 then
        event := deSetup
      else
        event := deRx;
    end;
  end
  else if (istatus and USB_ISTR_RESET) <> 0 then
  begin
    USB.ISTR := USB.ISTR and not USB_ISTR_RESET;
    USB.BTABLE := 0;
    for i := 0 to 7 do
      EndpointDeconfigure(i);

    event := deReset;
  end
{$ifdef USB_HAL_SOF}
  else if (istatus and USB_ISTR_SOF) <> 0 then
  begin
    event := deSof;
    USB.ISTR := USB.ISTR and not USB_ISTR_SOF;
  end
{$endif}
  else if (istatus and USB_ISTR_WKUP) <> 0 then
  begin
    event := deWakeup;
    USB.CNTR := usb.CNTR and not USB_CNTR_FSUSP;
    USB.ISTR := USB.ISTR and not USB_ISTR_WKUP;
  end
  else if (istatus and USB_ISTR_SUSP) <> 0 then
  begin
    event := deSuspend;
    USB.CNTR := USB.CNTR or USB_CNTR_FSUSP;
    USB.ISTR := USB.ISTR and not USB_ISTR_SUSP;
  end
  else if (istatus and USB_ISTR_ERR) <> 0 then
  begin
    USB.ISTR := USB.ISTR and not USB_ISTR_ERR;
    event := deError;
  end
  else
    exit;

  Callback(data, event, endpoint);
end;

function AllocPMA(AEPSize: longword): longword;
const
  USB_PMASIZE = sizeof(USBMem);
var
  desc: PBufferDescriptors;
  i: integer;
begin
  Result := USB_PMASIZE;

  for i := 0 to 7 do
  begin
    desc:=@BufferDescriptors[i];
    if (desc^.TX.Addr<>0) and (desc^.TX.Addr<Result) then Result := desc^.TX.Addr;
    if (desc^.RX.Addr<>0) and (desc^.RX.Addr<Result) then Result := desc^.RX.Addr;
  end;

  if Result<($20+AEPSize) then
    Result := 0
  else
    Result := Result - AEPSize;
end;

function EndpointConfigure(AEndpoint: byte; AType: TEndpointType; AEPSize: SizeInt): boolean;
var
  epr: PWord;
  epIndex: longword;
  Area, RXCount: SizeInt;
  Desc: PBufferDescriptors;
const
  Configs: array[TEndpointType] of word = (USB_EP_TYPE_CONTROL, USB_EP_TYPE_BULK, USB_EP_TYPE_ISO, USB_EP_TYPE_INTERRUPT, USB_EP_TYPE_BULK or USB_EP_EP_KIND);
begin
  epIndex:=AEndpoint and 7;
  if epIndex>7 then exit(false);

  epr:=@USB.EPR[epIndex];    
  Desc:=@BufferDescriptors[epIndex];

  if Odd(AEPSize) then Inc(AEPSize);

  epr^:=Configs[AType] or epIndex;

  if (AType=etcontrol) or IsTXEndpoint(AEndpoint) then
  begin
    Area:=AllocPMA(AEPSize);
    if Area=0 then Exit(false);

    Desc^.TX.Addr:=Area;
    Desc^.TX.Count:=0;

    if AType in [etIsochronous,etBulkDoublebuffered] then
    begin
      Area:=AllocPMA(AEPSize);
      if Area=0 then Exit(false);

      Desc^.TX1.Addr:=Area;
      Desc^.TX1.Count:=0;

      EP_DTX_UNSTALL(epr);
    end
    else
      EP_TX_UNSTALL(epr);
  end;

  if not IsTXEndpoint(AEndpoint) then
  begin
    if AEpSize>=63 then
    begin
      if (AEpSize and $1F) <> 0 then
        AEpSize := AEpSize and $1F
      else
        Dec(AEpSize, $20);
      RXCount := $8000 or (AEpSize shl 5);
      Inc(AEpSize, $20);
    end
    else
      RXCount := AEpSize shl 9;

    Area:=AllocPMA(AEpSize);
    if Area=0 then Exit(False);

    Desc^.RX.Addr:=Area;
    Desc^.RX.Count:=RXCount;

    if AType in [etIsochronous,etBulkDoublebuffered] then
    begin
      Area:=AllocPMA(AEpSize);
      if Area=0 then Exit(False);

      Desc^.RX0.Addr:=Area;
      Desc^.RX0.Count:=RXCount;

      EP_DRX_UNSTALL(epr);
    end
    else
      EP_RX_UNSTALL(epr);
  end;

  result:=true;
end;

procedure EndpointDeconfigure(AEndpoint: byte);
var
  desc: PBufferDescriptors;
  epr: PWord;
begin
  epr:=@USB.EPR[AEndpoint and 7];
  desc:=@BufferDescriptors[AEndpoint and 7];

  epr^:=epr^ and (not USB_EP_MASK);

  desc^.RX.Addr:=0;
  desc^.RX.Count:=0;
  desc^.TX.Addr:=0;
  desc^.TX.Count:=0;
end;

function PMARead(ABuffer: PByte; ALength: LongInt; var ADesc: TBufferDescriptor): SizeInt;
var
  _pma: PWord;
  _t: longword;
begin
  _pma:=@PMA[ADesc.Addr shr 1];

  Result := ADesc.Count and $3FF;
  ADesc.Count := ADesc.Count and (not $3FF);
  if ALength > Result then ALength := Result;
  Result := ALength;

  if assigned(ABuffer) then
  begin
    while ALength > 0 do
    begin
      _t := _pma^;

      ABuffer^ := _t and $FF;
      Inc(ABuffer);
      Dec(ALength);
      if ALength <> 0 then
      begin
        ABuffer^ := _t shr 8;
        Inc(ABuffer);
        Inc(_pma, PMAStep);
        Dec(ALength);
      end
      else
        break;
    end;
  end;
end;

procedure PMAWrite(ABuffer: PByte; ALength: LongInt; var ADesc: TBufferDescriptor);
var
  _pma: PWord;
begin
  _pma:=@PMA[ADesc.Addr shr 1];

  ADesc.Count:=ALength;
  while (ALength > 1) do
  begin
    _pma^ := (word(ABuffer[1]) shl 8) or ABuffer[0];
    Inc(_pma, PMAStep);
    Inc(ABuffer, 2);
    Dec(ALength, 2);
  end;

  if (ALength <> 0) then
    _pma^ := ABuffer^;
end;

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
var
  epr: PWord;
begin
  AEndpoint:=AEndpoint and 7;
  epr:=@USB.EPR[AEndpoint];
  Result:=-1;

  case (epr^ and (USB_EP_STAT_RX or USB_EP_EP_KIND or USB_EP_EP_TYPE)) of
    // doublebuffered bulk endpoint
    (USB_EP_STAT_RX_VALID or USB_EP_TYPE_BULK or USB_EP_EP_KIND):
      begin
        // switching SWBUF if AEndpoint is NAKED
        case epr^ and (USB_EP_DTOG_RX or USB_EP_DTOG_TX) of
          0,
          (USB_EP_DTOG_RX or USB_EP_DTOG_TX):
            epr^:=(epr^ and USB_EP_MASK) or USB_EP_DTOG_TX;
        end;

        Result:=PMARead(AData, ASize, BufferDescriptors[AEndpoint].RXs[(epr^ and USB_EP_DTOG_TX) <> 0]);
      end;
    // isochronous endpoint */
    (USB_EP_STAT_RX_VALID or USB_EP_TYPE_ISO):
      Result:=PMARead(AData, ASize, BufferDescriptors[AEndpoint].RXs[(epr^ and USB_EP_DTOG_RX)<>0]);
    // regular endpoint */
    (USB_EP_STAT_RX_NAK or USB_EP_TYPE_BULK),
    (USB_EP_STAT_RX_NAK or USB_EP_TYPE_CONTROL),
    (USB_EP_STAT_RX_NAK or USB_EP_TYPE_INTERRUPT):
      begin
        Result:=PMARead(AData, ASize, BufferDescriptors[AEndpoint].RX);
        EP_RX_VALID(epr);
      end;
  end;
end;

function EndpointWrite(AEndpoint: byte; AData: Pointer; ALength: SizeInt): SizeInt;
var
  epr: PWord;
begin
  AEndpoint:=AEndpoint and 7;
  epr:=@USB.EPR[AEndpoint];

  case epr^ and (USB_EP_STAT_TX or USB_EP_EP_TYPE or USB_EP_EP_KIND) of
    // doublebuffered bulk endpoint
    (USB_EP_STAT_TX_NAK or USB_EP_TYPE_BULK or USB_EP_EP_KIND):
    begin
      PMAWrite(AData, ALength, BufferDescriptors[AEndpoint].TXs[(epr^ and USB_EP_DTOG_RX)<>0]);
      epr^:=(epr^ and USB_EP_MASK) or USB_EP_DTOG_RX;
    end;
    // isochronous endpoint
    (USB_EP_STAT_TX_VALID or USB_EP_TYPE_ISO):
      PMAWrite(AData, ALength, BufferDescriptors[AEndpoint].TXs[(epr^ and USB_EP_DTOG_TX)<>0]);
    // regular endpoint
    (USB_EP_STAT_TX_NAK or USB_EP_TYPE_BULK),
    (USB_EP_STAT_TX_NAK or USB_EP_TYPE_CONTROL),
    (USB_EP_STAT_TX_NAK or USB_EP_TYPE_INTERRUPT):
      begin
        PMAWrite(AData, ALength, BufferDescriptors[AEndpoint].TX);
        EP_TX_VALID(epr);
      end
  else
    // invalid or not ready
    exit(-1);
  end;
  exit(ALength);
end;

function EndpointStalled(AEndpoint: byte): boolean;
var
  status: LongWord;
begin
  status:=USB.EPR[AEndpoint and 7];

  if IsTXEndpoint(AEndpoint) then
    EndpointStalled:=(status and USB_EP_STAT_TX)=USB_EP_STAT_TX_STALL
  else
    EndpointStalled:=(status and USB_EP_STAT_RX)=USB_EP_STAT_RX_STALL;
end;

procedure EndpointSetStall(AEndpoint: byte; AStall: boolean);
var
  epIndex: longword;
  epr: PWord;
begin
  epIndex:=AEndpoint and 7;
  epr:=@USB.EPR[epIndex];

  if (epr^ and USB_EP_EP_TYPE)=USB_EP_TYPE_ISO then exit;

  if IsTXEndpoint(AEndpoint) then
  begin
    if (epr^ and USB_EP_STAT_TX)=USB_EP_STAT_TX_DISABLED then exit;

    if AStall then
      EP_TX_STALL(epr)
    else
    begin
      // If double buffered clear SW_BUF(USB_EP_DTOG_RX) as well
      if (epr^ and (USB_EP_EP_TYPE or USB_EP_EP_KIND))=(USB_EP_TYPE_BULK or USB_EP_EP_KIND) then
        EP_DTX_UNSTALL(epr)
      else
        EP_TX_UNSTALL(epr);
    end;
  end
  else
  begin
    if (epr^ and USB_EP_STAT_RX)=USB_EP_STAT_RX_DISABLED then exit;

    if AStall then
      EP_RX_STALL(epr)
    else
    begin
      // If double buffered clear SW_BUF(USB_EP_DTOG_RX) as well
      if (epr^ and (USB_EP_EP_TYPE or USB_EP_EP_KIND))=(USB_EP_TYPE_BULK or USB_EP_EP_KIND) then
        EP_DRX_UNSTALL(epr)
      else
        EP_RX_UNSTALL(epr);
    end;
  end;
end;

end.

