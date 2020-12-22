program test;

uses
  USBCore,
  USBd;

var
  Device: TUSBDevice;
            
type
  TMyDescriptor = packed record
    Config: TUsbConfigurationDescriptor;
    Intf: TUsbInterfaceDescriptor;
  end;

const
  StringDesc: array[0..3] of PWideChar = (
    #$0304#$0409,
    #$0324'Laksen Industries',
    #$031A'Product 3000',
    #$0314'00121302');

  configDesc: TMyDescriptor = (
    Config: (
      bLength: sizeof(TUsbConfigurationDescriptor);
      bDescriptorType: USB_DESC_TYPE_Configuration;
      wTotalLength: SizeOf(TMyDescriptor);
      bNumInterfaces: 2;
      bConfigurationValue: 1;
      iConfiguration: 0;
      bmAttributes: $C0;
      bMaxPower: 50
    );
    Intf: (
      bLength: sizeof(TUsbInterfaceDescriptor);
      bDescriptorType: USB_DESC_TYPE_Interface;
      bInterfaceNumber: 0;
      bAlternateSetting: 0;
      bNumEndpoints: 1;
      bInterfaceClass: 0;
      bInterfaceSubClass: 0;
      bInterfaceProtocol: 0;
      iInterface: 0;
    );
  );

  DeviceDesc: TUsbDeviceDescriptor = (
    bLength: sizeof(TUsbDeviceDescriptor);
    bDescriptorType: USB_DESC_TYPE_Device;
    bcdUsb: $0200;
    bDeviceClass: 0;
    bDeviceSubClass: 0;
    bDeviceProtocol: 0;
    bMaxPacketSize: 8;
    idVendor: $0483;
    idProduct: $5740;
    bcdDevice: $100;
    iManufacturer: 1;
    iProduct: 2;
    iSerialNumber: 3;
    bNumConfigurations: 1
  );

function UsbCallback(var Device: TUSBDevice; AEvent: TUSBEvent; AEndpoint: byte; const ARequest: TUsbControlRequest): TUSBResponse;
begin
  result:=urStall;
end;

begin
  USBd.Enable(Device,true,@UsbCallback, DeviceDesc, ConfigDesc, StringDesc);


  while true do
    USBd.Poll;
end.

