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
  USB_ISC_MSD_UFI = $04;
  USB_ISC_MSD_SCSI_TRANSPARENT = $06;
  USB_ISC_MSD_LSD_FS = $07;
  USB_ISC_MSD_IEEE1667 = $08;

  // Interface protocol
  USB_IP_MSD_CBI_INTERRUPT = $00;
  USB_IP_MSD_CBI = $01;
  USB_IP_MSD_BBB = $50; // Bulk only
  USB_IP_MSD_UAS = $62;

type
  TUSBMSDRequest = (
    // CBI
    mrADSC = $00,
    // Bulk only
    mrGetMaxLUN = $FE,
    mrReset = $FF
  );

  {$packrecords 1}
  TUSBMSDCommandBlockWrapper = record
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

  TUSBMSDCommandStatusWrapper = record
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

