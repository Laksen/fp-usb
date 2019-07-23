unit usbc_cdc;

interface

const
  // Device
  USB_DC_CDC = $02;

  // Interface
  USB_CDC_IC_COMM = $02;
  USB_CDC_IC_DATA = $0A;

  USB_CDC_ISC_DLCM = $01;
  USB_CDC_ISC_ACM = $02;
  USB_CDC_ISC_ENCM = $06;

  USB_CDC_ISC_NONE = $00;

  USB_CDC_IP_NONE = $00;

  // CALL Capabilities
  USBCDCCallCapDeviceCallManagement = $01;
  USBCDCCallCapDeviceCallMgmtDataIntf = $02;

  // ACM Capabilities
  USBCDCACMCapCommFeature = $01;
  USBCDCACMCapLineFeature = $02;
  USBCDCACMCapSendBreak = $04;
  USBCDCACMCapNetworkNotification = $08;

  USB_DESC_TYPE_CsInterface = $24;
  USB_DESC_TYPE_CsEndpoint  = $25;

  USB_DESC_TYPE_CdcHeader = $00;
  USB_DESC_TYPE_CdcCall = $01;
  USB_DESC_TYPE_CdcAcm = $02;
  USB_DESC_TYPE_CdcUnion = $06;

type
  TUsbCdcHeaderDescriptor = packed record
    bFunctionLength,
    bDescriptorType,
    bDescriptorSubType: byte;
    bcdCDC: word;
  end;

  TUsbCdcCallDescriptor = packed record
    bFunctionLength,
    bDescriptorType,
    bDescriptorSubType,
    bmCapabilities,
    bDataInterface: byte;
  end;

  TUsbCdcAcmDescriptor = packed record
    bFunctionLength,
    bDescriptorType,
    bDescriptorSubType,
    bmCapabilities: byte;
  end;

  TUsbCdcUnionDescriptor = packed record
    bFunctionLength,
    bDescriptorType,
    bDescriptorSubType,
    bMasterInterface,
    bSlaveInterface: byte;
  end;

const
  USB_CDC_REQ_SET_COMM_FEATURE = $02;
  USB_CDC_REQ_GET_COMM_FEATURE = $03;
  USB_CDC_REQ_CLEAR_COMM_FEATURE = $04;
  USB_CDC_REQ_SET_AUX_LINE_STATE = $10;
  USB_CDC_REQ_SET_HOOK_STATE = $11;
  USB_CDC_REQ_PULSE_SETUP = $12;
  USB_CDC_REQ_SEND_PULSE = $13;
  USB_CDC_REQ_SET_PULSE_TIME = $14;
  USB_CDC_REQ_RING_AUX_JACK = $15;
  USB_CDC_REQ_SET_LINE_CODING = $20;
  USB_CDC_REQ_GET_LINE_CODING = $21;
  USB_CDC_REQ_SET_CONTROL_LINE_STATE = $22;
  USB_CDC_REQ_SEND_BREAK = $23;
  USB_CDC_REQ_SET_RINGER_PARMS = $30;
  USB_CDC_REQ_GET_RINGER_PARMS = $31;
  USB_CDC_REQ_SET_OPERATION_PARMS = $32;
  USB_CDC_REQ_GET_OPERATION_PARMS = $33;
  USB_CDC_REQ_SET_LINE_PARMS = $34;
  USB_CDC_REQ_GET_LINE_PARMS = $35;
  USB_CDC_REQ_DIAL_DIGITS = $36;

type
  TUSB_CDC_ACM_LINE_CODING = packed record
    dwDTERate: longword;
    bCharFormat,
    bParityType,
    bDataBits: byte;
  end;

implementation

end.

