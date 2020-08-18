unit USBClassDFU;

interface

const
  // Device
  USB_DC_DFU = $02;

  // Interface
  USB_DFU_IC = $FE; // Application specific

  USB_DFU_ISC = $01; // Device Firmware Upgrade code

  USB_DFU_IP_Runtime = $01;
  USB_DFU_IP_Upgrade = $02;

  USB_DESC_TYPE_DFU_Functional = $21;

type
  TUsbDfuFunctionalDescriptor = packed record
    bFunctionLength,
    bDescriptorType,
    bmAttributes: byte;
    wDetachTimeOut,
    wTransferSize, // Max number of bytes the device can accept per control-write transaction
    bcfDFUVersion: word;
  end;

const
  USB_DFU_FUNC_ATTR_WILL_DETACH = $08;
  USB_DFU_FUNC_ATTR_MANIFESTATION_TOLERANT = $04;
  USB_DFU_FUNC_ATTR_CAN_UPLOAD = $02;
  USB_DFU_FUNC_ATTR_CAN_DNLOAD = $01;

const
  USB_DFU_REQ_DETACH    = 0;
  USB_DFU_REQ_DNLOAD    = 1;
  USB_DFU_REQ_UPLOAD    = 2;
  USB_DFU_REQ_GETSTATUS = 3;
  USB_DFU_REQ_CLRSTATUS = 4;
  USB_DFU_REQ_GETSTATE  = 5;
  USB_DFU_REQ_ABORT     = 6;

type
  TUsbDfuStatusResponse = packed record
    bStatus: byte;
    bwPollTimeout: array[0..2] of byte;
    bState,
    iString: byte;
  end;

type
  TUsbDfuDeviceStatus = (
    dsOK = 0,
    dsErrTarget = 1,
    dsErrFile = 2,
    dsErrWrite = 3,
    dsErrErase = 4,
    dsErrCheckErased = 5,
    dsErrProg = 6,
    dsErrVerify = 7,
    dsErrAddress = 8,
    dsErrNotDone = 9,
    dsErrFirmware = 10,
    dsErrVendor = 11,
    dsErrUSBReset = 12,
    dsERrPOR = 13,
    dsErrUnknown = 14,
    dsErrStalledPkt = 15
  );

  TUsbDfuDeviceState = (
    dsAppIdle,
    dsAppDetach,
    dsDfuIdle,
    dsDfuDnloadSync,
    dsDfuDnBusy,
    dsDfuDnloadIdle,
    dsDfuManifestSync,
    dsDfuManifest,
    dsDfuManifestWaitReset,
    dsDfuUploadIdle,
    dsDfuError
  );

implementation

end.

