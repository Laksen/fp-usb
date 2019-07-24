unit USBClassMSD;

interface

uses
  USBCore;

const
  // Interface class
  USB_IC_MSD = $08;

  // Interface subclass
  USB_ISC_MSD_SCSI = $00;
  USB_ISC_MSD_RBC = $01;
  USB_ISC_MSD_ATAPI = $02;
  USB_ISC_MSD_UFI = $02;
  USB_ISC_MSD_SCSI_TRANSPARENT = $03;
  USB_ISC_MSD_LSD_FS = $04;
  USB_ISC_MSD_IEEE1667 = $05;

  // Interface protocol
  USB_IP_MSD_CBI_INTERRUPT = $00;
  USB_IP_MSD_CBI = $01;
  USB_IP_MSD_BBB = $50; // Bulk only

type
  TUSBMSDRequest = (
    // CBI
    mrADSC = $00,
    // Bulk only
    mrGetMaxLUN = $FE,
    mrReset = $FF
  );

  TUSBMSDCommandBlockWrapper = packed record
    dCBWSignature,
    dCBWTag,
    dCBWDataTransferLength: longword;
    bmCBWFlags,
    bCBWLUN,
    bCBWCBLength: byte;
    CBWCB: array[0..15] of byte;
  end;

  TCBWFlag = (fDataOut = 0, fDataIn = $80);
  TCBWFlags = set of TCBWFlag;

  TUSBMSDCommandStatusWrapper = packed record
    dCSWSignature,
    dCSWTag,
    dCSWDataResidue: longword;
    bCSWStatus: byte;
  end;

  TUSBMSDCommandBlockStatus = (
    cbsPassed,
    cbsFailed,
    cbsPhaseError
  );

const
  CBWSignature = $43425355;
  CBSSignature = $53425355;

implementation

end.

