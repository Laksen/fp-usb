// This program demonstrates a simple CDC ACM interface
program test;
             
{$mode objfpc}
{$modeswitch advancedrecords}

uses
  consoleio,
  stm32f103fw,
  simpleusb, simpleusb_cdc, simpleusb_msd, simpleusb_helpers;

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

procedure CPSIE; assembler;
asm
  cpsie if
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
  dev: TSimpleUSBDevice;
  msd: TMSDDevice;

  cdc: TCDCDevice;
  cdcrx, cdctx: array[0..$40-1] of byte;

  descBuffer: array[0..1023] of byte;
  strDescBuffer: array[0..1023] of byte;

function UsbSend(ACh: char; AUserData: pointer): boolean;
begin
  Result:=true;
  cdc.Write(ACh, 1);
end;

{function UsbRead(var ACh: char; AUserData: pointer): boolean;
begin
  Result:=True;
  cdc.Read(ach, 1);

  if ACh=#13 then ACh:=#10;
end;}

procedure ErrHandler(ErrNo : Longint; Address : CodePointer; Frame : Pointer);
begin
  //writeln('Error!');
  while true do;
end;

procedure hard_fault_handler_c(p: plongword; lr: longword);
begin
  {writeln('Hardfault');
  writeln(' R0:  ', hexstr(p[0], 8));
  writeln(' R1:  ', hexstr(p[1], 8));
  writeln(' R2:  ', hexstr(p[2], 8));
  writeln(' R3:  ', hexstr(p[3], 8));

  writeln(' R12: ', hexstr(p[4], 8));
  writeln(' LR:  ', hexstr(p[5], 8));
  writeln(' PC:  ', hexstr(p[6], 8));
  writeln(' PSR: ', hexstr(p[7], 8));

  writeln(' LR:  ', hexstr(lr, 8));}
  while true do;
end;

procedure Hardfault_interrupt; assembler; nostackframe; [public, alias: 'Hardfault_interrupt'];
asm
  tst lr, #4
  mov r1, lr
  ite eq
  mrseq r0, msp
  mrsne r0, psp
  b hard_fault_handler_c
end;

procedure MemManage_interrupt; [public, alias: 'MemManage_interrupt']; 
begin
  //writeln('MemManage_interrupt!');
  while true do;
end;

procedure BusFault_interrupt; [public, alias: 'BusFault_interrupt'];   
begin
  //writeln('BusFault_interrupt!');
  while true do;
end;

procedure UsageFault_interrupt; [public, alias: 'UsageFault_interrupt'];
begin
  //writeln('UsageFault_interrupt!');
  while true do;
end;

procedure InitUSB;
begin
  dev.SetDescriptorBuffer(descBuffer, length(descBuffer));
  dev.SetStrDescriptorBuffer(strDescBuffer, length(strDescBuffer));

  dev.ConfigureDevice($0483, $5740, $100, 'Laksen Industries', 'Mega CDC thing', '12345678', uv20, 8, 0, 0, 0);
  dev.AddConfiguration(1, [caSelfPowered], 300);

  dev.AddCDC(cdc, 1, cdcrx, cdctx);
  dev.AddMSD(msd, 1, 64);

  dev.Enable(8);
  dev.SetConnected(true);
end;

var
  c: char;
begin
  ErrorProc:=@ErrHandler;

  RCC_Configure;
  RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOD or RCC_APB2Periph_USART1 or RCC_APB2Periph_GPIOA or RCC_APB2Periph_AFIO, Enabled);
  GPIO_Configure;

  SysTick_CLKSourceConfig(SysTick_CLKSource_HCLK_Div8);
  SysTick_SetReload((72000000 div 8) div 1000) ;
  SysTick_CounterCmd(SysTick_Counter_Enable);
  SysTick_ITConfig(Enabled);

  CPSIE;

  UART_Configure;
  consoleio.OpenIO(Output, @sendUart, nil, fmOutput, nil);
  consoleio.OpenIO(input, @UsbSend, nil, fmOutput, nil);

  writeln('Adding device');
  InitUSB;

  GPIO_ResetBits(PortD, GPIO_Pin_2); // Connect pull-up on D+ line

  while True do
  begin
    dev.Poll;

    {if cdc.Available>0 then
    begin
      cdc.Read(c,1);
      //write(c);
    end;}

    if systick_ms>=next_tick then
    begin
      inc(next_tick,1000);
      Writeln(input, 'Hello world: ', systick_ms);
    end;

    {if RXPos>0 then
    begin
      write('>');
      for i:=0 to RXPos-1 do
        write(RXBuffer[i]);
      RXPos:=0;
      writeln('<');
    end;}
  end;
end.

