// This program demonstrates a simple CDC ACM interface
program test;

uses
  USBCore,
  USBClassCDC,
  consoleio,
  stm32f103fw, USBd, USBClassMSD;

procedure RCC_Configure;
begin
  RCC_DeInit;

  RCC_HSEConfig(RCC_HSE_ON);

  // Wait till HSE is ready
  if RCC_WaitForHSEStartUp then
  begin
    // Enable Prefetch Buffer
    FLASH_PrefetchBufferCmd(FLASH_PrefetchBuffer_Enable);

    // Flash 2 wait state
    FLASH_SetLatency(FLASH_Latency_2);

    // HCLK = SYSCLK
    RCC_HCLKConfig(RCC_SYSCLK_Div1);

    // PCLK2 = HCLK
    RCC_PCLK2Config(RCC_HCLK_Div1);

    // PCLK1 = HCLK/2
    RCC_PCLK1Config(RCC_HCLK_Div2);

    // PLLCLK = 8MHz * 9 = 72 MHz
    RCC_PLLConfig(RCC_PLLSource_HSE_Div1, RCC_PLLMul_9);

    // USB Clk = 72 / 1.5 = 48
    RCC_USBCLKConfig(RCC_USBCLKSource_PLLCLK_1Div5);

    // Enable PLL
    RCC_PLLCmd(Enabled);

    // Wait till PLL is ready
    while RCC_GetFlagStatus(RCC_FLAG_PLLRDY) = RCC_RESET do ;

    // Select PLL as system clock source
    RCC_SYSCLKConfig(RCC_SYSCLKSource_PLLCLK);

    // Wait till PLL is used as system clock source
    while RCC_GetSYSCLKSource() <> $08 do ;
  end;
end;

procedure GPIO_Configure;
var
  GPIO_InitStructure: TGPIO_InitTypeDef;
begin
  GPIO_DeInit(PortA);
  GPIO_DeInit(PortD);

  // USART
  GPIO_StructInit(GPIO_InitStructure);
  GPIO_InitStructure.GPIO_Pin := GPIO_Pin_9;
  GPIO_InitStructure.GPIO_Speed := GPIO_Speed_50MHz;
  GPIO_InitStructure.GPIO_Mode := GPIO_MODE_AF_PP;
  GPIO_Init(PortA, GPIO_InitStructure);

  GPIO_StructInit(GPIO_InitStructure);
  GPIO_InitStructure.GPIO_Pin := GPIO_Pin_10;
  GPIO_InitStructure.GPIO_Speed := GPIO_Speed_50MHz;
  GPIO_InitStructure.GPIO_Mode := GPIO_Mode_IN_FLOATING;
  GPIO_Init(PortA, GPIO_InitStructure);

  // USB
  GPIO_StructInit(GPIO_InitStructure);
  GPIO_InitStructure.GPIO_Pin := GPIO_Pin_11 or GPIO_Pin_12;
  GPIO_InitStructure.GPIO_Speed := GPIO_Speed_50MHz;
  GPIO_InitStructure.GPIO_Mode := GPIO_MODE_AF_PP;
  GPIO_Init(PortA, GPIO_InitStructure);

  // USB Attach
  GPIO_SetBits(PortD, GPIO_Pin_2);

  GPIO_StructInit(GPIO_InitStructure);
  GPIO_InitStructure.GPIO_Pin := GPIO_Pin_2;
  GPIO_InitStructure.GPIO_Speed := GPIO_Speed_50MHz;
  GPIO_InitStructure.GPIO_Mode := GPIO_Mode_Out_OD;
  GPIO_Init(PortD, GPIO_InitStructure);
end;

procedure UART_Configure;
var
  usart_settings: TUSART_InitTypeDef;
begin
  USART_DeInit(USART1);

  USART_StructInit(usart_settings);
  usart_settings.USART_BaudRate := 115200;
  USART_Init(USART1, usart_settings);

  USART_Cmd(USART1, Enabled);
end;

function sendUart(ACh: char; AUserData: pointer): boolean;
begin
  while not USART_GetFlagStatus(Usart1, USART_FLAG_TXE) do ;
  USART_SendData(USART1, byte(ACh));
  sendUart := True;
end;

type
  TMyDescriptor = packed record
    Config: TUsbConfigurationDescriptor;
    CommIntf: TUsbInterfaceDescriptor;

    CdcHeader: TUsbCdcHeaderDescriptor;
    CdcCall: TUsbCdcCallDescriptor;
    CdcAcm: TUsbCdcAcmDescriptor;
    CdcUnion: TUsbCdcUnionDescriptor;

    CommEp: TUsbEndpointDescriptor;

    DataIntf: TUsbInterfaceDescriptor;

    DataEpRx,
    DataEpTx: TUsbEndpointDescriptor;
  end;

const
  CDC_EP0_SIZE = $08;
  CDC_RXD_EP = $01;
  CDC_TXD_EP = $81;
  CDC_DATA_SZ = $40;
  CDC_NTF_EP = $82;
  CDC_NTF_SZ = $08;

var
  Buffer: array[0..127] of byte;
  strDesc: array[0..3] of PWideChar = (
    #$0304#$0409,
    #$0324'Laksen Industries',
    #$031A'Product 3000',
    #$0314'00121302');

const
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
    CommIntf: (
      bLength: sizeof(TUsbInterfaceDescriptor);
      bDescriptorType: USB_DESC_TYPE_Interface;
      bInterfaceNumber: 0;
      bAlternateSetting: 0;
      bNumEndpoints: 1;
      bInterfaceClass: USB_CDC_IC_COMM;
      bInterfaceSubClass: USB_CDC_ISC_ACM;
      bInterfaceProtocol: USB_CDC_IP_NONE;
      iInterface: 0;
    );
    CdcHeader: (
      bFunctionLength: sizeof(TUsbCdcHeaderDescriptor);
      bDescriptorType: USB_DESC_TYPE_CsInterface;
      bDescriptorSubType: USB_DESC_TYPE_CdcHeader;
      bcdCDC: $110
    );
    CdcCall: (
      bFunctionLength: sizeof(TUsbCdcCallDescriptor);
      bDescriptorType: USB_DESC_TYPE_CsInterface;
      bDescriptorSubType: USB_DESC_TYPE_CdcCall;
      bmCapabilities: 0;
      bDataInterface: 1;
    );
    CdcAcm: (
      bFunctionLength: sizeof(TUsbCdcAcmDescriptor);
      bDescriptorType: USB_DESC_TYPE_CsInterface;
      bDescriptorSubType: USB_DESC_TYPE_CdcAcm;
      bmCapabilities: 0;
    );
    CdcUnion: (
      bFunctionLength: sizeof(TUsbCdcUnionDescriptor);
      bDescriptorType: USB_DESC_TYPE_CsInterface;
      bDescriptorSubType: USB_DESC_TYPE_CdcUnion;
      bMasterInterface: 0;
      bSlaveInterface: 1;
    );
    CommEp: (
      bLength: sizeof(TUsbEndpointDescriptor);
      bDescriptorType: USB_DESC_TYPE_Endpoint;
      bEndpointAddress: CDC_NTF_EP;
      bmAttributes: USB_ENDPOINT_TYPE_Interrupt;
      wMaxPacketSize: CDC_NTF_SZ;
      bInterval: $FF;
    );
    DataIntf: (
      bLength: sizeof(TUsbInterfaceDescriptor);
      bDescriptorType: USB_DESC_TYPE_Interface;
      bInterfaceNumber: 1;
      bAlternateSetting: 0;
      bNumEndpoints: 2;
      bInterfaceClass: USB_CDC_IC_DATA;
      bInterfaceSubClass: USB_CDC_ISC_NONE;
      bInterfaceProtocol: USB_CDC_IP_NONE;
      iInterface: 0;
    );
    DataEpRx: (
      bLength: sizeof(TUsbEndpointDescriptor);
      bDescriptorType: USB_DESC_TYPE_Endpoint;
      bEndpointAddress: CDC_RXD_EP;
      bmAttributes: USB_ENDPOINT_TYPE_Bulk;
      wMaxPacketSize: CDC_DATA_SZ;
      bInterval: $01;
    );
    DataEpTx: (
      bLength: sizeof(TUsbEndpointDescriptor);
      bDescriptorType: USB_DESC_TYPE_Endpoint;
      bEndpointAddress: CDC_TXD_EP;
      bmAttributes: USB_ENDPOINT_TYPE_Bulk;
      wMaxPacketSize: CDC_DATA_SZ;
      bInterval: $01;
    );
  );

  devDesc: TUsbDeviceDescriptor = (
    bLength: sizeof(TUsbDeviceDescriptor);
    bDescriptorType: USB_DESC_TYPE_Device;
    bcdUsb: $0200;
    bDeviceClass: 0;
    bDeviceSubClass: 0;
    bDeviceProtocol: 0;
    bMaxPacketSize: CDC_EP0_SIZE;
    idVendor: $0483;
    idProduct: $5740;
    bcdDevice: $100;
    iManufacturer: 1;
    iProduct: 2;
    iSerialNumber: 3;
    bNumConfigurations: 1
  );

var
  LineCoding: TUSB_CDC_ACM_LINE_CODING;

procedure CPSIE; assembler;
asm
  cpsie i
end;

var
  systick_ms: longword = 0;

procedure SysTick_interrupt; [public, alias: 'SysTick_interrupt'];
begin
  inc(systick_ms);
end;

var
  next_tick: longword = 1000;
  i: Integer;

var
  TXBuffer: array[0..CDC_DATA_SZ-1] of char;
  TXPos: longint;

  RXBuffer: array[0..CDC_DATA_SZ-1] of char;
  RXPos: longint;

function clb(var Device: TUSBDevice; AEvent: TUSBEvent; AEndpoint: byte; const ARequest: TUsbControlRequest): TUSBResponse;
var
  r: SizeInt;
  buf: array[0..15] of byte;
begin        
  result:=urStall;
  case AEvent of
    ueDeconfigured:
      begin
        USBd.EndpointDeconfigure(CDC_NTF_EP);
        USBd.EndpointDeconfigure(CDC_RXD_EP);
        USBd.EndpointDeconfigure(CDC_TXD_EP);
      end;
    ueConfigured:
      begin
        USBd.EndpointConfigure(CDC_RXD_EP, etBulk, CDC_DATA_SZ);
        USBd.EndpointConfigure(CDC_TXD_EP, etBulk, CDC_DATA_SZ);
        USBd.EndpointConfigure(CDC_NTF_EP, etInterrupt, CDC_NTF_SZ);

        EndpointWrite(CDC_TXD_EP,nil,0);
      end;
    ueControlRequest:
      begin               
        result:=urACK;
        case ARequest.bRequest of
          USB_CDC_REQ_GET_LINE_CODING:
            begin
              EndpointControlWrite(Device, AEndpoint, @LineCoding, sizeof(LineCoding));
            end;                       
          USB_CDC_REQ_SET_LINE_CODING:;
          USB_CDC_REQ_SET_CONTROL_LINE_STATE:;
        else
          result:=urStall;
        end;
      end;
    ueControlRX:
      begin      
        case ARequest.bRequest of
          USB_CDC_REQ_SET_LINE_CODING:
            r:=EndpointControlRead(Device, AEndpoint,@LineCoding,sizeof(LineCoding));
          USB_CDC_REQ_SET_CONTROL_LINE_STATE:
            begin
              r:=EndpointControlRead(Device, AEndpoint,@buf[0],sizeof(buf));
            end;
        end;
      end;
    ueControlDone:
      begin
        //writeln('Control done: ', ARequest.bRequest);
      end;
    ueRX:
      begin
        if RXPos<=High(RXBuffer) then
        begin
          r:=EndpointRead(AEndpoint,@RXBuffer[RXPos],sizeof(RXBuffer)-RXPos);
          if r>0 then inc(RXPos,r);
        end;
      end;
    ueTX:
      begin
        r:=USBd.EndpointWrite(CDC_TXD_EP,@TXBuffer[0],TXPos);

        Dec(TXPos,r);
        Move(TXBuffer[r],TXBuffer[0],TXPos);
      end;
  end;
end;

function UsbSend(ACh: char; AUserData: pointer): boolean;
begin
  Result:=true;
  while true do
  begin
    if TXPos>high(TXBuffer) then
      USBd.Poll
    else
    begin
      TXBuffer[TXPos]:=ACh;
      inc(TXPos);
      Break;
    end;
  end;
end;

function UsbRead(var ACh: char; AUserData: pointer): boolean;
begin
  Result:=True;
  while true do
  begin
    if RXPos<=0 then
      USBd.Poll
    else
    begin
      ACh:=RXBuffer[0];
      Dec(RXPos);
      if RXPos>0 then Move(RXBuffer[1], RXBuffer[0], RXPos);
      break;
    end;
  end;

  if ACh=#13 then ACh:=#10;
end;

var
  ADevice: TUSBDevice;
begin
  RCC_Configure;
  RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOD or RCC_APB2Periph_USART1 or RCC_APB2Periph_GPIOA or RCC_APB2Periph_AFIO, Enabled);
  GPIO_Configure;

  SysTick_CLKSourceConfig(SysTick_CLKSource_HCLK_Div8);
  SysTick_SetReload((72000000 div 8) div 1000) ;
  SysTick_CounterCmd(SysTick_Counter_Enable);
  SysTick_ITConfig(Enabled);

  CPSIE;

  UART_Configure;

  USBd.Enable(ADevice, True, @clb, devDesc, configDesc, strDesc);
  USBd.Connect(True);
  GPIO_ResetBits(PortD, GPIO_Pin_2); // Connect pull-up on D+ line
                                                       
  //consoleio.OpenIO(Output, @sendUart, nil, fmOutput, nil);
  consoleio.OpenIO(Output, @UsbSend, nil, fmOutput, nil);
  //consoleio.OpenIO(Input, nil, @UsbRead, fmInput, nil);

  while True do
  begin
    USBd.poll;

    if systick_ms>=next_tick then
    begin
      inc(next_tick,1000);
      Writeln('Hello world: ', systick_ms);
    end;

    if RXPos>0 then
    begin
      write('>');
      for i:=0 to RXPos-1 do
        write(RXBuffer[i]);
      RXPos:=0;
      writeln('<');
    end;
  end;
end.

