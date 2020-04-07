{
Serial communication port (UART). In Windows it COM-port, real or virtual.
In Linux it /dev/ttyS or /dev/ttyUSB. Also, Linux use file /var/lock/LCK..ttyS for port locking

(C) Sergey Bodrov, 2012-2018

Properties:
  Port - port name (COM1, /dev/ttyS01)
  BaudRate - data excange speed
  MinDataBytes - minimal bytes count in buffer for triggering event OnDataAppear

Methods:
  Open() - Opens port. As parameter it use port initialization string:
    InitStr = 'Port,BaudRate,DataBits,Parity,StopBits,SoftFlow,HardFlow'

    Port - COM port name (COM1, /dev/ttyS01)
    BaudRate - connection speed (50..4000000 bits per second), default 9600
    DataBits - default 8
    Parity - (N - None, O - Odd, E - Even, M - Mark or S - Space) default N
    StopBits - (1, 1.5, 2)
    SoftFlow - Enable XON/XOFF byte ($11 for resume and $13 for pause transmission), default 1
    HardFlow - Enable CTS/RTS handshake, default 0

Events:
  OnOpen - Triggered after sucсessful connection.
  OnClose - Triggered after disconnection.
}
unit DataPortSerial;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$DEFINE NO_LIBC}
{$ENDIF}

interface

uses
  {$IFNDEF MSWINDOWS}
    {$IFNDEF NO_LIBC}
    Libc,
    KernelIoctl,
    {$ELSE}
    termio, baseunix, unix,
    {$ENDIF}
    {$IFNDEF FPC}
    Types,
    {$ENDIF}
  {$ELSE}
    Windows,
  {$ENDIF}
  SysUtils, Classes, DataPort, DataPortUART, synaser, synautil;

type
  { TSerialClient - serial port reader/writer, based on Ararat Synapse }
  TSerialClient = class(TThread)
  private
    FSerial: TBlockSerial;
    sFromPort: AnsiString;
    sLastError: string;
    FSafeMode: Boolean;
    FOnIncomingMsgEvent: TMsgEvent;
    FOnErrorEvent: TMsgEvent;
    FOnConnectEvent: TNotifyEvent;
    FDoConfig: Boolean;
    procedure SyncProc();
    procedure SyncProcOnError();
    procedure SyncProcOnConnect();
  protected
    FParentDataPort: TDataPortUART;
    function IsError(): Boolean;
    procedure Execute(); override;
  public
    sPort: string;
    BaudRate: Integer;
    DataBits: Integer;
    Parity: char;
    StopBits: TSerialStopBits;
    FlowControl: TSerialFlowControl;
    CalledFromThread: Boolean;
    sToSend: AnsiString;
    SleepInterval: Integer;
    constructor Create(AParent: TDataPortUART); reintroduce;
    property SafeMode: Boolean read FSafeMode write FSafeMode;
    property Serial: TBlockSerial read FSerial;
    property OnIncomingMsgEvent: TMsgEvent read FOnIncomingMsgEvent
      write FOnIncomingMsgEvent;
    property OnErrorEvent: TMsgEvent read FOnErrorEvent write FOnErrorEvent;
    property OnConnectEvent: TNotifyEvent read FOnConnectEvent write FOnConnectEvent;
    { Set port parameters (baud rate, data bits, etc..) }
    procedure Config();
    function SendString(const AData: AnsiString): Boolean;
    procedure SendStream(st: TStream);
  end;

  { TDataPortSerial - serial DataPort }
  TDataPortSerial = class(TDataPortUART)
  private
    FSerialClient: TSerialClient;
    FParity: AnsiChar;
    FDataBits: Integer;
    FMinDataBytes: Integer;
    FBaudRate: Integer;
    FPort: string;
    FFlowControl: TSerialFlowControl;
    FStopBits: TSerialStopBits;
    function CloseClient(): Boolean;
  protected
    procedure SetBaudRate(AValue: Integer); override;
    procedure SetDataBits(AValue: Integer); override;
    procedure SetParity(AValue: AnsiChar); override;
    procedure SetStopBits(AValue: TSerialStopBits); override;
    procedure SetFlowControl(AValue: TSerialFlowControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy(); override;
    { Open serial DataPort
         InitStr = 'Port,BaudRate,DataBits,Parity,StopBits,SoftFlow,HardFlow'

         Port - COM port name (COM1, /dev/tty01)
         BaudRate - connection speed (50..4000000 bits per second), default 9600
         DataBits - default 8
         Parity - (N - None, O - Odd, E - Even, M - Mark or S - Space) default N
         StopBits - (1, 1.5, 2)
         SoftFlow - Enable XON/XOFF handshake, default 0
         HardFlow - Enable CTS/RTS handshake, default 0 }
    procedure Open(const AInitStr: string = ''); override;
    procedure Close(); override;
    function Push(const AData: AnsiString): Boolean; override;
    class function GetSerialPortNames(): string;

    { Get modem wires status (DSR,CTS,Ring,Carrier) }
    function GetModemStatus(): TModemStatus; override;
    { Set DTR (Data Terminal Ready) signal }
    procedure SetDTR(AValue: Boolean); override;
    { Set RTS (Request to send) signal }
    procedure SetRTS(AValue: Boolean); override;

    property SerialClient: TSerialClient read FSerialClient;

  published
    { Serial port name (COM1, /dev/ttyS01) }
    property Port: string read FPort write FPort;
    { BaudRate - connection speed (50..4000000 bits per second), default 9600 }
    property BaudRate: Integer read FBaudRate write SetBaudRate;
    { DataBits - default 8  (5 for Baudot code, 7 for true ASCII) }
    property DataBits: Integer read FDataBits write SetDataBits;
    { Parity - (N - None, O - Odd, E - Even, M - Mark or S - Space) default N }
    property Parity: AnsiChar read FParity write SetParity;
    { StopBits - (stb1, stb15, stb2), default stb1 }
    property StopBits: TSerialStopBits read FStopBits write SetStopBits;
    { FlowControl - (sfcNone, sfcSend, sfcReady, sfcSoft) default sfcNone }
    property FlowControl: TSerialFlowControl read FFlowControl write SetFlowControl;
    { Minimum bytes in incoming buffer to trigger OnDataAppear }
    property MinDataBytes: Integer read FMinDataBytes write FMinDataBytes;
    property Active;
    property OnDataAppear;
    property OnError;
    property OnOpen;
    property OnClose;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('DataPort', [TDataPortSerial]);
end;

// === TSerialClient ===
constructor TSerialClient.Create(AParent: TDataPortUART);
begin
  inherited Create(True);
  FParentDataPort := AParent;
  SleepInterval := 10;
end;

procedure TSerialClient.Config();
begin
  FDoConfig := True;
end;

procedure TSerialClient.SyncProc();
begin
  if not CalledFromThread then
  begin
    CalledFromThread := True;
    try
      if Assigned(OnIncomingMsgEvent) then
        OnIncomingMsgEvent(Self, sFromPort);
    finally
      CalledFromThread := False;
    end;
  end;
end;

procedure TSerialClient.SyncProcOnError();
begin
  if not CalledFromThread then
  begin
    CalledFromThread := True;
    try
      if Assigned(OnErrorEvent) then
        OnErrorEvent(Self, sLastError);
    finally
      CalledFromThread := False;
    end;
  end;
end;

procedure TSerialClient.SyncProcOnConnect();
begin
  if not CalledFromThread then
  begin
    CalledFromThread := True;
    try
      if Assigned(OnConnectEvent) then
        OnConnectEvent(Self);
    finally
      CalledFromThread := False;
    end;
  end;
end;

function TSerialClient.IsError(): Boolean;
begin
  Result := (Serial.LastError <> 0) and (Serial.LastError <> ErrTimeout);
  if Result then
  begin
    sLastError := Serial.LastErrorDesc;
    if Assigned(FParentDataPort.OnError) then
      Synchronize(SyncProcOnError)
    else if Assigned(OnErrorEvent) then
      OnErrorEvent(Self, sLastError);
    Terminate();
  end
end;

procedure TSerialClient.Execute();
var
  SoftFlow: Boolean;
  HardFlow: Boolean;
  iStopBits: Integer;
begin
  sLastError := '';
  SoftFlow := False;
  HardFlow := False;
  iStopBits := 1;

  if Terminated then Exit;

  FSerial := TBlockSerial.Create();
  try
    Serial.DeadlockTimeout := 3000;
    Serial.Connect(sPort);
    Sleep(SleepInterval);
    if Serial.LastError = 0 then
    begin
      case StopBits of
        stb1:  iStopBits := SB1;
        stb15: iStopBits := SB1andHalf;
        stb2:  iStopBits := SB2;
      end;

      if FlowControl = sfcSoft then
        SoftFlow := True
      else if FlowControl = sfcSend then
        HardFlow := True;

      Serial.Config(BaudRate, DataBits, Parity, iStopBits, SoftFlow, HardFlow);
      FDoConfig := False;
      Sleep(SleepInterval);
    end;

    if not IsError() then
    begin
      if Assigned(FParentDataPort.OnOpen) then
        Synchronize(SyncProcOnConnect)
      else if Assigned(OnConnectEvent) then
        OnConnectEvent(Self);
    end;

    while not Terminated do
    begin
      sLastError := '';

      Serial.GetCommState();
      if IsError() then
        Break;

      if FDoConfig then
      begin
        if FlowControl = sfcSoft then
          SoftFlow := True
        else if FlowControl = sfcSend then
          HardFlow := True;
        Serial.Config(BaudRate, DataBits, Parity, iStopBits, SoftFlow, HardFlow);
        FDoConfig := False;
        Sleep(SleepInterval);
      end
      else
      begin
        sFromPort := Serial.RecvPacket(SleepInterval);
      end;

      if IsError() then
        Break
      else if (Length(sFromPort) > 0) then
      begin
        try
          if Assigned(FParentDataPort.OnDataAppear) then
            Synchronize(SyncProc)
          else
          if Assigned(OnIncomingMsgEvent) then
            OnIncomingMsgEvent(Self, sFromPort);
        finally
          sFromPort := '';
        end;
      end;

      Sleep(1);

      if sToSend <> '' then
      begin
        if Serial.CanWrite(SleepInterval) then
        begin
          Serial.SendString(sToSend);
          if IsError() then
            Break;
          sToSend := '';
        end;
      end;

    end;
  finally
    FreeAndNil(FSerial);
  end;
end;

function TSerialClient.SendString(const AData: AnsiString): Boolean;
begin
  Result := False;
  if not Assigned(Self.Serial) then
    Exit;
  if SafeMode then
    Self.sToSend := Self.sToSend + AData
  else
  begin
    if Serial.CanWrite(100) then
      Serial.SendString(AData);
    if (Serial.LastError <> 0) and (Serial.LastError <> ErrTimeout) then
    begin
      sLastError := Serial.LastErrorDesc;
      Synchronize(SyncProc);
      Exit;
    end;
  end;
  Result := True;
end;

procedure TSerialClient.SendStream(st: TStream);
var
  ss: TStringStream;
begin
  if not Assigned(Self.Serial) then
    Exit;
  if SafeMode then
  begin
    ss := TStringStream.Create('');
    try
      ss.CopyFrom(st, st.Size);
      Self.sToSend := Self.sToSend + ss.DataString;
    finally
      ss.Free();
    end;
  end
  else
  begin
    Serial.SendStreamRaw(st);
    if Serial.LastError <> 0 then
    begin
      sLastError := Serial.LastErrorDesc;
      Synchronize(SyncProc);
    end;
  end;
end;


{ TDataPortSerial }

constructor TDataPortSerial.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSerialClient := nil;
end;

destructor TDataPortSerial.Destroy();
begin
  if Assigned(FSerialClient) then
  begin
    FSerialClient.OnIncomingMsgEvent := nil;
    FSerialClient.OnErrorEvent := nil;
    FSerialClient.OnConnectEvent := nil;
    FreeAndNil(FSerialClient);
  end;
  inherited Destroy();
end;

function TDataPortSerial.CloseClient(): Boolean;
begin
  Result := True;
  if Assigned(FSerialClient) then
  begin
    Result := not FSerialClient.CalledFromThread;
    if Result then
    begin
      FSerialClient.OnIncomingMsgEvent := nil;
      FSerialClient.OnErrorEvent := nil;
      FSerialClient.OnConnectEvent := nil;
      FreeAndNil(FSerialClient);
    end
    else
      FSerialClient.Terminate()
  end;
end;

procedure TDataPortSerial.Open(const AInitStr: string = '');
{$IFDEF UNIX}
var
  s: string;
{$ENDIF}
begin
  inherited Open(AInitStr);

  if not CloseClient() then
    Exit;

  FSerialClient := TSerialClient.Create(Self);
  FSerialClient.OnIncomingMsgEvent := OnIncomingMsgHandler;
  FSerialClient.OnErrorEvent := OnErrorHandler;
  FSerialClient.OnConnectEvent := OnConnectHandler;
  FSerialClient.SafeMode := HalfDuplex;

  FSerialClient.sPort := FPort;
  FSerialClient.BaudRate := FBaudRate;
  FSerialClient.DataBits := FDataBits;
  FSerialClient.Parity := FParity;
  FSerialClient.StopBits := FStopBits;
  FSerialClient.FlowControl := FFlowControl;

  // Check serial port
  //if Pos(Port, synaser.GetSerialPortNames())=0 then Exit;
  {$IFDEF UNIX}
  // detect lock file name
  if Pos('tty', Port) > 0 then
  begin
    s := '/var/lock/LCK..' + Copy(Port, Pos('tty', Port), maxint);
    if FileExists(s) then
    begin
      // try to remove lock file (if any)
      DeleteFile(s);
    end;
  end;
  {$ENDIF}
  FSerialClient.Suspended := False;
  // don't set FActive - will be set in OnConnect event after successfull connection
end;

procedure TDataPortSerial.Close();
begin
  if Assigned(FSerialClient) then
  begin
    if FSerialClient.CalledFromThread then
      FSerialClient.Terminate()
    else
      FreeAndNil(FSerialClient);
  end;
  inherited Close();
end;

class function TDataPortSerial.GetSerialPortNames: string;
begin
  Result := synaser.GetSerialPortNames();
end;

function TDataPortSerial.GetModemStatus(): TModemStatus;
var
  ModemWord: Integer;
begin
  if Assigned(SerialClient) and Assigned(SerialClient.Serial) then
  begin
    ModemWord := SerialClient.Serial.ModemStatus();
    {$IFNDEF MSWINDOWS}
    FModemStatus.DSR := (ModemWord and TIOCM_DSR) > 0;
    FModemStatus.CTS := (ModemWord and TIOCM_CTS) > 0;
    FModemStatus.Carrier := (ModemWord and TIOCM_CAR) > 0;
    FModemStatus.Ring := (ModemWord and TIOCM_RNG) > 0;
    {$ELSE}
    FModemStatus.DSR := (ModemWord and MS_DSR_ON) > 0;
    FModemStatus.CTS := (ModemWord and MS_CTS_ON) > 0;
    FModemStatus.Carrier := (ModemWord and MS_RLSD_ON) > 0;
    FModemStatus.Ring := (ModemWord and MS_RING_ON) > 0;
    {$ENDIF}
  end;
  Result := inherited GetModemStatus;
end;

procedure TDataPortSerial.SetDTR(AValue: Boolean);
begin
  if Assigned(SerialClient) and Assigned(SerialClient.Serial) then
  begin
    SerialClient.Serial.DTR := AValue;
  end;
  inherited SetDTR(AValue);
end;

procedure TDataPortSerial.SetRTS(AValue: Boolean);
begin
  if Assigned(SerialClient) and Assigned(SerialClient.Serial) then
  begin
    SerialClient.Serial.RTS := AValue;
  end;
  inherited SetRTS(AValue);
end;

function TDataPortSerial.Push(const AData: AnsiString): Boolean;
begin
  Result := False;
  if Assigned(SerialClient) and FLock.BeginWrite() then
  begin
    try
      Result := SerialClient.SendString(AData);
    finally
      FLock.EndWrite();
    end;
  end;
end;

procedure TDataPortSerial.SetBaudRate(AValue: Integer);
begin
  inherited SetBaudRate(AValue);
  if Active then
  begin
    SerialClient.BaudRate := FBaudRate;
    SerialClient.Config();
  end;
end;

procedure TDataPortSerial.SetDataBits(AValue: Integer);
begin
  inherited SetDataBits(AValue);
  if Active then
  begin
    SerialClient.DataBits := FDataBits;
    SerialClient.Config();
  end;
end;

procedure TDataPortSerial.SetParity(AValue: AnsiChar);
begin
  inherited SetParity(AValue);
  if Active then
  begin
    SerialClient.Parity := FParity;
    SerialClient.Config();
  end;
end;

procedure TDataPortSerial.SetFlowControl(AValue: TSerialFlowControl);
begin
  inherited SetFlowControl(AValue);
  if Active then
  begin
    SerialClient.FlowControl := FFlowControl;
    SerialClient.Config();
  end;
end;

procedure TDataPortSerial.SetStopBits(AValue: TSerialStopBits);
begin
  inherited SetStopBits(AValue);
  if Active then
  begin
    SerialClient.StopBits := FStopBits;
    SerialClient.Config();
  end;
end;

end.
