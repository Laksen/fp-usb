unit simpleusb_helpers;

{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  simpleusb,
  simpleusb_cdc, simpleusb_msd;

type
  TMSDBulkMaxSize = 8..64;

  TSimpleHelper = record helper for TSimpleUSBDevice   
    procedure AddCDC(out ADevice: TCDCDevice; AConfigValue: byte; var ARXBuffer, ATXBuffer: array of byte);
    procedure AddMSD(var ADevice: TMSDDevice; AConfigValue: byte; AMaxPacketSize: TMSDBulkMaxSize);
  end;

implementation

uses
  USBClassCDC,
  USBClassMSD;

procedure TSimpleHelper.AddCDC(out ADevice: TCDCDevice; AConfigValue: byte; var ARXBuffer, ATXBuffer: array of byte);
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

  ADevice.Init(@self, CtrlIntf, DataIntf, DataEP, CtrlEP, ARXBuffer, ATXBuffer);
end;

procedure TSimpleHelper.AddMSD(var ADevice: TMSDDevice; AConfigValue: byte; AMaxPacketSize: TMSDBulkMaxSize);
var
  intf, msgEP: Byte;
begin
  intf:=AllocateInterface;

  msgEP:=AllocateEndpoint;

  with GetConfig(AConfigValue) do
  begin
    with AddInterface(intf, 0, USB_IC_MSD, USB_ISC_MSD_SCSI_TRANSPARENT, USB_IP_MSD_BBB) do
    begin
      AddEndpoint(dirToDevice,   msgEP, setBulk, AMaxPacketSize);
      AddEndpoint(dirFromDevice, msgEP, setBulk, AMaxPacketSize);
    end;
  end;

  ADevice.Init(@self, intf, msgEP);
end;

end.

