unit USBCore;

interface 

const
  rtDirectionMask = $80;
  rtTypeMask = $60;
  rtRecipientMask = $1F;

  rtDirectionToDevice = $00;
  rtDirectionToHost = $80;

  rtTypeStandard = $00;
  rtTypeClass    = $20;
  rtTypeVendor   = $40;

  rtRecipientDevice    = 0;
  rtRecipientInterface = 1;
  rtRecipientEndpoint  = 2;
  rtRecipientOther     = 3;

type
  TUsbStandardRequest = (srGetStatus = $00,
                         srClearFeature = $01,
                         srSetFeature = $03,
                         srSetAddress = $05,
                         srGetDescriptor  = $06,
                         srSetDescriptor = $07,
                         srGetConfiguration = $08,
                         srSetConfiguration = $09);

  TUsbControlRequest = record
    bmRequestType,
    bRequest: byte;
    wValue,
    wIndex,
    wLength: word;
  end;

const
  USB_DESC_TYPE_Device = $1;
  USB_DESC_TYPE_Configuration = $2;
  USB_DESC_TYPE_Interface = $4;
  USB_DESC_TYPE_Endpoint = $5;
  USB_DESC_TYPE_String = $3;

  USB_ENDPOINT_TYPE_Control = $0;
  USB_ENDPOINT_TYPE_Isochronous = $1;
  USB_ENDPOINT_TYPE_Bulk = $2;
  USB_ENDPOINT_TYPE_Interrupt = $3;

type
  PUsbDescriptor = ^TUsbDescriptor;
  TUsbDescriptor = packed record
    bLength,
    bDescriptorType: byte;
  end;

  PUsbDeviceDescriptor = ^TUsbDeviceDescriptor;
  TUsbDeviceDescriptor = packed record
    bLength,
    bDescriptorType: byte;
    bcdUsb: word;
    bDeviceClass,
    bDeviceSubClass,
    bDeviceProtocol,
    bMaxPacketSize: byte;
    idVendor,
    idProduct,
    bcdDevice: word;
    iManufacturer,
    iProduct,
    iSerialNumber,
    bNumConfigurations: byte;
  end;

  PUsbConfigurationDescriptor = ^TUsbConfigurationDescriptor;
  TUsbConfigurationDescriptor = packed record
    bLength,
    bDescriptorType: byte;
    wTotalLength: word;
    bNumInterfaces,
    bConfigurationValue,
    iConfiguration,
    bmAttributes,
    bMaxPower: byte;
  end;

  PUsbInterfaceDescriptor = ^TUsbInterfaceDescriptor;
  TUsbInterfaceDescriptor = packed record
    bLength,
    bDescriptorType,
    bInterfaceNumber,
    bAlternateSetting,
    bNumEndpoints,
    bInterfaceClass,
    bInterfaceSubClass,
    bInterfaceProtocol,
    iInterface: byte;
  end;

  PUsbEndpointDescriptor = ^TUsbEndpointDescriptor;
  TUsbEndpointDescriptor = packed record
    bLength,
    bDescriptorType,
    bEndpointAddress,
    bmAttributes: byte;
    wMaxPacketSize: word;
    bInterval: byte;
  end;

type
  TEndpointType = (etControl, etBulk, etIsochronous, etInterrupt, etBulkDoublebuffered);

function IsTXEndpoint(AAddress: byte): boolean; inline;

implementation

function IsTXEndpoint(AAddress: byte): boolean; inline;
begin
  result:=(AAddress and $80)<>0;
end;

end.

