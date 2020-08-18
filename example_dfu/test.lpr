// This program demonstrates a DFU interface
program test;

uses
  USBCore,
  USBClassDFU,
  stm32f103fw, USBd;

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
  usart_settings.USART_BaudRate := 500000;//115200;
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
    IntfDesc: TUsbInterfaceDescriptor;
    FuncDesc: TUsbDfuFunctionalDescriptor;
  end;

var
  Buffer: array[0..127] of byte;
  strDesc: array[0..4] of PWideChar = (
    #$0304#$0409,
    #$0324'Laksen Industries',
    #$031A'Product 3000',
    #$0314'00121302',
    #$030C'Flash');

const
  DFU_EP0_SIZE = 8;
  DFU_TRANSFER_SIZE = 64; // Transferring less than this indicates an end of transmission

const
  configDesc: TMyDescriptor = (
    Config: (
      bLength: sizeof(TUsbConfigurationDescriptor);
      bDescriptorType: USB_DESC_TYPE_Configuration;
      wTotalLength: SizeOf(TMyDescriptor);
      bNumInterfaces: 1;
      bConfigurationValue: 1;
      iConfiguration: 0;
      bmAttributes: $C0;
      bMaxPower: 50
    );
    IntfDesc: (
      bLength: sizeof(TUsbInterfaceDescriptor);
      bDescriptorType: USB_DESC_TYPE_Interface;
      bInterfaceNumber: 0;
      bAlternateSetting: 0; // Add more interfaces if you have more memory areas to write
      bNumEndpoints: 0;
      bInterfaceClass: USB_DFU_IC;
      bInterfaceSubClass: USB_DFU_ISC;
      bInterfaceProtocol: USB_DFU_IP_Upgrade;
      iInterface: 4; // 'Flash'
    );
    FuncDesc: (
      bFunctionLength: sizeof(TUsbDfuFunctionalDescriptor);
      bDescriptorType: USB_DESC_TYPE_DFU_Functional;
      bmAttributes: USB_DFU_FUNC_ATTR_CAN_DNLOAD;
      wDetachTimeOut: 0;
      wTransferSize: DFU_TRANSFER_SIZE;
      bcfDFUVersion: $200
    );
  );

  devDesc: TUsbDeviceDescriptor = (
    bLength: sizeof(TUsbDeviceDescriptor);
    bDescriptorType: USB_DESC_TYPE_Device;
    bcdUsb: $0200;
    bDeviceClass: 0;
    bDeviceSubClass: 0;
    bDeviceProtocol: 0;
    bMaxPacketSize: DFU_EP0_SIZE;
    idVendor: $0483;
    idProduct: $5740;
    bcdDevice: $100;
    iManufacturer: 1;
    iProduct: 2;
    iSerialNumber: 3;
    bNumConfigurations: 1
  );

procedure CPSIE; assembler;
asm
  cpsie i
end;

var
  dfuState: TUsbDfuDeviceState = dsDfuIdle;
  dfuStatus: TUsbDfuDeviceStatus = dsOK;

  dfuTXBuffer: array[0..DFU_TRANSFER_SIZE-1] of byte;

  dfuTopFlash: record end; external name '_stack_top';

{procedure SysTick_interrupt; [public, alias: 'SysTick_interrupt'];
begin
  inc(systick_ms);
end;}

function clb(var Device: TUSBDevice; AEvent: TUSBEvent; AEndpoint: byte; const ARequest: TUsbControlRequest): TUSBResponse;
var
  resp: TUsbDfuStatusResponse;
  buf: array[0..63] of byte;
  r: SizeInt;
begin        
  result:=urStall;

  case AEvent of
    ueControlRequest:
      begin               
        result:=urACK;
        case ARequest.bRequest of
          USB_DFU_REQ_DNLOAD:
            begin
              if ARequest.wLength=0 then
                dfuState:=dsDfuIdle
              else
                dfuState:=dsDfuDnloadIdle;
            end;
          USB_DFU_REQ_UPLOAD:
            begin
              dfuState:=dsDfuUploadIdle;

              if ARequest.wValue<10 then
              begin
                r:=DFU_TRANSFER_SIZE;
                if r>ARequest.wLength then
                  r:=ARequest.wLength;

                move(pbyte($08000000)[ARequest.wValue*DFU_EP0_SIZE], dfuTXBuffer[0], r);
                EndpointControlWrite(Device, AEndpoint, @dfuTXBuffer[0], r);
              end
              else
                dfuState:=dsDfuIdle;
            end;
          USB_DFU_REQ_GETSTATUS:
            begin
              resp.bState:=byte(dfuState);
              resp.bwPollTimeout[0]:=100;
              resp.bwPollTimeout[1]:=0;
              resp.bwPollTimeout[2]:=0;
              resp.bStatus:=byte(dfuStatus);
              resp.iString:=0;

              EndpointControlWrite(Device, AEndpoint, @resp, sizeof(resp));
            end;             
          USB_DFU_REQ_GETSTATE:
            begin
              EndpointControlWrite(Device, AEndpoint, @dfuState, sizeof(byte));
            end;
          USB_DFU_REQ_CLRSTATUS:
            begin
              dfuState:=dsDfuIdle;
              dfuStatus:=dsOK;
            end;
          USB_DFU_REQ_ABORT:
            begin
              dfuState:=dsDfuIdle;
              dfuStatus:=dsOK;
            end;
        else
          result:=urStall;
        end;
      end;
    ueControlRX:
      begin                                                       
        r:=EndpointControlRead(Device, AEndpoint,@buf[0],sizeof(buf));
        // We are probably in dsDfuDnloadIdle here, which means that r is the current amount of data read of the current block
      end;
    ueControlDone:
      begin
        // Typically called at the end of dsDfuDnloadIdle
        //dfuState:=dsDfuDnBusy;
      end;
  end;
end;

var
  ADevice: TUSBDevice;
begin
  RCC_Configure;
  RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOD or RCC_APB2Periph_USART1 or RCC_APB2Periph_GPIOA or RCC_APB2Periph_AFIO, Enabled);
  GPIO_Configure;

  {SysTick_CLKSourceConfig(SysTick_CLKSource_HCLK_Div8);
  SysTick_SetReload((72000000 div 8) div 1000) ;
  SysTick_CounterCmd(SysTick_Counter_Enable);
  SysTick_ITConfig(Enabled);}

  CPSIE;

  //UART_Configure;

  USBd.Enable(ADevice, True, @clb, devDesc, configDesc, strDesc);
  USBd.Connect(True);
  GPIO_ResetBits(PortD, GPIO_Pin_2); // Connect pull-up on D+ line

  while True do
  begin
    USBd.poll;
  end;
end.

