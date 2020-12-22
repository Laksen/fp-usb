unit USBHAL;

interface

uses
  USBCore;

type
  TDriverEvent = (deReset, deError,
                  deWakeup, deSuspend,
                  deSOF, deSetup, deRx, deTx);
  TDriverCallback = procedure(AData: pointer; AEvent: TDriverEvent; AEndpoint: byte);

procedure DriverState(AEnabled: boolean; ACallback: TDriverCallback=nil; AData: pointer=nil);
procedure DriverConnect(AConnect: boolean);

procedure DriverSetAddress(AAddress: byte);

procedure DriverPoll;

function EndpointConfigure(AEndpoint: byte; AType: TEndpointType; AEPSize: SizeInt): boolean;
procedure EndpointDeconfigure(AEndpoint: byte);

function EndpointStalled(AEndpoint: byte): boolean;
procedure EndpointSetStall(AEndpoint: byte; AStall: boolean);

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
function EndpointWrite(AEndpoint: byte; AData: Pointer; ALength: SizeInt): SizeInt;

implementation

procedure DriverState(AEnabled: boolean; ACallback: TDriverCallback; AData: pointer);
begin

end;

procedure DriverConnect(AConnect: boolean);
begin

end;

procedure DriverSetAddress(AAddress: byte);
begin

end;

procedure DriverPoll;
begin

end;

function EndpointConfigure(AEndpoint: byte; AType: TEndpointType; AEPSize: SizeInt): boolean;
begin

end;

procedure EndpointDeconfigure(AEndpoint: byte);
begin

end;

function EndpointStalled(AEndpoint: byte): boolean;
begin

end;

procedure EndpointSetStall(AEndpoint: byte; AStall: boolean);
begin

end;

function EndpointRead(AEndpoint: byte; AData: Pointer; ASize: SizeInt): SizeInt;
begin

end;

function EndpointWrite(AEndpoint: byte; AData: Pointer; ALength: SizeInt): SizeInt;
begin

end;

end.

