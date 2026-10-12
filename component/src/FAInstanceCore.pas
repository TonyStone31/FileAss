unit FAInstanceCore;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, AdvancedIPC, FATypes;
type
  TFileAssInstanceMode = (fimSingleInstance, fimForwardParameters);
  TFileAssInstanceRole = (firStopped, firPrimary, firSecondary, firFailed);
  TFileAssParametersEvent = procedure(Sender: TObject; Parameters: TStrings;
    const WorkingDirectory: UTF8String; Initial: Boolean) of object;
  TFileAssInstanceManager = class(TComponent)
  private
    Identity: UTF8String;
    InstanceMode: TFileAssInstanceMode;
    Ready, SendInitial: Boolean;
    StartupParameters: TStringList;
    StartupDirectory: UTF8String;
    StartupPending, Polling: Boolean;
    ActivityTick: QWord;
    InstanceRole: TFileAssInstanceRole;
    Outcome: TFileAssResult;
    PrimaryLock: TObject;
    Receiver: TIPCServer;
    TransportID, GateName: UTF8String;
    ParametersHandler: TFileAssParametersEvent;
    ActivationHandler: TNotifyEvent;
    SecondaryHandler, ErrorHandler: TFileAssErrorEvent;
    procedure SetIdentity(const Value: UTF8String);
    procedure SetMode(Value: TFileAssInstanceMode);
    procedure DeliverParameters(Parameters: TStrings; const Directory: UTF8String; Initial: Boolean);
  protected
    procedure SetReady(Value: Boolean); virtual;
    procedure ActivateRequested; virtual;
    procedure Report(const Value: TFileAssResult); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start: TFileAssInstanceRole; overload;
    function Start(Parameters: TStrings; const WorkingDirectory: UTF8String): TFileAssInstanceRole; overload;
    function QueueParameters(Parameters: TStrings; const WorkingDirectory: UTF8String): Boolean;
    procedure Poll;
    procedure Stop;
    property Role: TFileAssInstanceRole read InstanceRole;
    property LastResult: TFileAssResult read Outcome;
    // GetTickCount64 time of the last start or delivery, for adaptive polling.
    property LastActivity: QWord read ActivityTick;
  published
    // Stable reverse-domain ID identifying this application's instance inbox.
    // Ownership is scoped to the current user and session. Set before Start and
    // stop instance handling before changing it; do not delay setting it until ready.
    property ApplicationID: UTF8String read Identity write SetIdentity;
    // fimSingleInstance (default) ignores secondary launches. fimForwardParameters
    // queues their startup parameters for the primary process. Set OnParameters
    // for forwarding and stop instance handling before changing the mode.
    property Mode: TFileAssInstanceMode read InstanceMode write SetMode default fimSingleInstance;
    // Default False. True permits Poll to deliver initial and queued parameters.
    // False pauses delivery while retaining primary ownership, so launches during
    // initialization still forward to this process instead of creating another primary.
    property ReadyForParameters: Boolean read Ready write SetReady default False;
    // Default True. In forwarding mode, the primary's own startup parameters use
    // OnParameters with Initial=True, including an empty initial list. False leaves
    // initial startup handling to your application; forwarded requests still arrive.
    property IncludeInitialParameters: Boolean read SendInitial write SendInitial default True;
    // Receives initial or forwarded startup parameters after readiness. Parameters
    // may contain several filenames or ordinary options; resolve relative filenames
    // against WorkingDirectory. Copy the list if retaining it after the event.
    // Initial is True only for the primary's startup. Runs in the thread calling Poll.
    property OnParameters: TFileAssParametersEvent read ParametersHandler write ParametersHandler;
    // A secondary launch forwarded no parameters. The form component restores
    // and brings forward its owner form unless this event is assigned. The console
    // manager has no default activation action. Delivery waits for readiness.
    property OnActivateRequested: TNotifyEvent read ActivationHandler write ActivationHandler;
    // Runs in the secondary process after its launch is ignored or its parameters
    // are queued. A successful queue does not confirm that files have been opened.
    // The form component then terminates if AutoTerminateSecondary is True.
    property OnSecondaryInstance: TFileAssErrorEvent read SecondaryHandler write SecondaryHandler;
    // Reports startup or delivery failures through a result code and message.
    // The form component displays unhandled errors; the console manager does not.
    // Check Start's returned role and LastResult when deciding how to continue.
    property OnError: TFileAssErrorEvent read ErrorHandler write ErrorHandler;
  end;
procedure FileAssStartupParameters(Parameters: TStrings);
function FileAssWorkingDirectory: UTF8String;
implementation
uses MD5, FAValidation, FAFormats
  {$ifdef unix}, BaseUnix, Unix{$endif}
  {$ifdef windows}, Windows, ShellApi{$endif};
{$ifdef windows}
function SessionForProcess(ProcessID: DWORD; var SessionID: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'ProcessIdToSessionId';
{$endif}
const
  ParameterMessage = 1;
  PacketSignature = $31494146;
  MaxPacketSize = 1024 * 1024;
  MaxParameterCount = 4096;
type
  TInstanceLock = class
  private
    Handle: THandle;
    Held: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Acquire(const Name: UTF8String; WaitMilliseconds: Cardinal): Boolean;
  end;
  TInstanceReceiver = class(TIPCServer)
  public
    function PendingPath(RequestID: Integer): string;
  end;
function TInstanceReceiver.PendingPath(RequestID: Integer): string;
begin Result := GetPeekedRequestFileName(RequestID); end;
constructor TInstanceLock.Create;
begin inherited Create; Handle := THandle(-1); end;
destructor TInstanceLock.Destroy;
begin
  if Handle <> THandle(-1) then begin
    {$ifdef windows}
    if Held then ReleaseMutex(Handle);
    CloseHandle(Handle);
    {$else}fpClose(Handle);{$endif}
  end;
  inherited Destroy;
end;
function TInstanceLock.Acquire(const Name: UTF8String; WaitMilliseconds: Cardinal): Boolean;
{$ifdef windows}
var Address: UnicodeString; Status: DWORD;
{$else}
var Path: UTF8String; Info: TStat; Deadline: QWord; ErrorCode: Integer;
{$endif}
begin
  if Held then Exit(True);
  {$ifdef windows}
  Address := UTF8Decode('Local\' + Name);
  Handle := CreateMutexW(nil, False, PWideChar(Address));
  if Handle = 0 then begin Handle := THandle(-1); RaiseLastOSError; end;
  Status := WaitForSingleObject(Handle, WaitMilliseconds);
  Held := (Status = WAIT_OBJECT_0) or (Status = WAIT_ABANDONED);
  if not Held then begin
    CloseHandle(Handle);
    Handle := THandle(-1);
    if Status <> WAIT_TIMEOUT then RaiseLastOSError;
  end;
  {$else}
  Path := IncludeTrailingPathDelimiter(GetTempDir(False)) + Name + '.lock';
  Handle := fpOpen(PChar(Path), O_RDWR or O_CREAT or O_NOFOLLOW, &600);
  if Handle = THandle(-1) then RaiseLastOSError(fpGetErrno);
  if (fpFStat(Handle, Info) <> 0) or (Info.st_uid <> fpGetUID) or
    not FPS_ISREG(Info.st_mode) then
    raise Exception.Create('The instance lock is not a regular file owned by this user.');
  fpFcntl(Handle, F_SETFD, 1);
  Deadline := GetTickCount64 + WaitMilliseconds;
  repeat
    Held := fpFlock(Handle, LOCK_EX or LOCK_NB) = 0;
    if Held then Break;
    ErrorCode := fpGetErrno;
    if not (ErrorCode in [ESysEAGAIN, ESysEINTR]) then RaiseLastOSError(ErrorCode);
    if GetTickCount64 >= Deadline then Break;
    Sleep(5);
  until False;
  if not Held then begin fpClose(Handle); Handle := THandle(-1); end;
  {$endif}
  Result := Held;
end;
function ScopedID(const ID: UTF8String): UTF8String;
var Scope: UTF8String;
{$ifdef windows}UserName: array[0..255] of WideChar; Size, Session: DWORD;{$endif}
begin
  {$ifdef windows}
  Size := Length(UserName);
  if not GetUserNameW(@UserName[0], Size) then RaiseLastOSError;
  if not SessionForProcess(GetCurrentProcessID, Session) then RaiseLastOSError;
  Scope := UTF8Encode(UnicodeString(PWideChar(@UserName[0]))) + ':' + IntToStr(Session);
  {$else}
  Scope := IntToStr(fpGetUID) + ':' + GetEnvironmentVariable('XDG_SESSION_ID');
  if GetEnvironmentVariable('XDG_SESSION_ID') = '' then
    Scope := Scope + GetEnvironmentVariable('DISPLAY') + ':' + GetEnvironmentVariable('WAYLAND_DISPLAY');
  {$endif}
  Result := 'FileAss_' + MD5Print(MD5String(ID + #0 + Scope));
end;
procedure FileAssStartupParameters(Parameters: TStrings);
var I: Integer;
{$ifdef windows}
type TArguments = array[0..32767] of PWideChar;
  PArguments = ^TArguments;
var Arguments: pLPWSTR; Count: LongInt;
{$endif}
begin
  Parameters.Clear;
  {$ifdef windows}
  Arguments := CommandLineToArgvW(GetCommandLineW, @Count);
  if not Assigned(Arguments) then RaiseLastOSError;
  try
    for I := 1 to Count - 1 do
      Parameters.Add(string(UTF8Encode(UnicodeString(PArguments(Arguments)^[I]))));
  finally LocalFree(HLOCAL(Arguments)); end;
  {$else}
  for I := 1 to ParamCount do Parameters.Add(ParamStr(I));
  {$endif}
end;
function FileAssWorkingDirectory: UTF8String;
{$ifdef windows}var Buffer: UnicodeString; Count: DWORD;{$endif}
begin
  {$ifdef windows}
  Count := GetCurrentDirectoryW(0, nil);
  if Count = 0 then RaiseLastOSError;
  SetLength(Buffer, Count);
  Count := GetCurrentDirectoryW(Length(Buffer), PWideChar(Buffer));
  if (Count = 0) or (Count >= DWORD(Length(Buffer))) then RaiseLastOSError;
  SetLength(Buffer, Count);
  Result := UTF8Encode(Buffer);
  {$else}Result := UTF8String(GetCurrentDir);{$endif}
end;
procedure WriteText(Stream: TStream; const Value: UTF8String);
var Count: LongWord;
begin
  Count := Length(Value);
  if (Count > MaxPacketSize) or (Stream.Size + Count + 4 > MaxPacketSize) then
    raise Exception.Create('Startup parameters exceed the message size limit.');
  Stream.WriteBuffer(Count, SizeOf(Count));
  if Count > 0 then Stream.WriteBuffer(Value[1], Count);
end;
function ReadText(Stream: TStream): UTF8String;
var Count: LongWord;
begin
  Stream.ReadBuffer(Count, SizeOf(Count));
  if (Count > MaxPacketSize) or (Count > Stream.Size - Stream.Position) then
    raise Exception.Create('Invalid startup parameter message.');
  SetLength(Result, Count);
  if Count > 0 then Stream.ReadBuffer(Result[1], Count);
end;
procedure WriteParameters(Stream: TStream; Parameters: TStrings; const Directory: UTF8String);
var Signature, Count: LongWord; I: Integer;
begin
  if Parameters.Count > MaxParameterCount then raise Exception.Create('Too many startup parameters.');
  Signature := PacketSignature;
  Count := Parameters.Count;
  Stream.WriteBuffer(Signature, SizeOf(Signature));
  Stream.WriteBuffer(Count, SizeOf(Count));
  WriteText(Stream, Directory);
  for I := 0 to Parameters.Count - 1 do WriteText(Stream, UTF8String(Parameters[I]));
  Stream.Position := 0;
end;
procedure ReadParameters(Stream: TStream; Parameters: TStrings; out Directory: UTF8String);
var Signature, Count: LongWord; I: Integer;
begin
  Stream.ReadBuffer(Signature, SizeOf(Signature));
  Stream.ReadBuffer(Count, SizeOf(Count));
  if (Signature <> PacketSignature) or (Count > MaxParameterCount) then
    raise Exception.Create('Invalid startup parameter message.');
  Directory := ReadText(Stream);
  for I := 1 to Count do Parameters.Add(string(ReadText(Stream)));
  if Stream.Position <> Stream.Size then raise Exception.Create('Unexpected data in startup parameter message.');
end;
constructor TFileAssInstanceManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  StartupParameters := TStringList.Create;
  SendInitial := True;
end;
destructor TFileAssInstanceManager.Destroy;
begin
  Stop;
  StartupParameters.Free;
  inherited Destroy;
end;
procedure TFileAssInstanceManager.SetIdentity(const Value: UTF8String);
begin
  if (Role = firPrimary) and (Value <> Identity) then
    raise Exception.Create('Stop instance handling before changing ApplicationID.');
  Identity := Value;
end;
procedure TFileAssInstanceManager.SetMode(Value: TFileAssInstanceMode);
begin
  if (Role = firPrimary) and (Value <> InstanceMode) then
    raise Exception.Create('Stop instance handling before changing Mode.');
  InstanceMode := Value;
end;
procedure TFileAssInstanceManager.SetReady(Value: Boolean);
begin Ready := Value; end;
procedure TFileAssInstanceManager.Report(const Value: TFileAssResult);
begin
  Outcome := Value;
  if not Value.Succeeded and Assigned(ErrorHandler) then ErrorHandler(Self, Value);
end;
function TFileAssInstanceManager.Start: TFileAssInstanceRole;
var Parameters: TStringList;
begin
  Parameters := TStringList.Create;
  try
    FileAssStartupParameters(Parameters);
    Result := Start(Parameters, FileAssWorkingDirectory);
  finally Parameters.Free; end;
end;
function TFileAssInstanceManager.Start(Parameters: TStrings;
  const WorkingDirectory: UTF8String): TFileAssInstanceRole;
var Gate, OwnerLock: TInstanceLock; Sender: TIPCClient; Packet: TMemoryStream; RequestID: Integer;
begin
  if Role = firPrimary then Exit(Role);
  Gate := TInstanceLock.Create;
  OwnerLock := TInstanceLock.Create;
  Sender := nil;
  Packet := nil;
  try
    try
      if not Assigned(Parameters) then raise Exception.Create('A startup parameter list is required.');
      if Mode = fimForwardParameters then begin
        Packet := TMemoryStream.Create;
        WriteParameters(Packet, Parameters, WorkingDirectory);
      end;
      if not FileAssValidIdentifier(ApplicationID) then
        raise Exception.Create('Set a stable reverse-domain ApplicationID before starting instance handling.');
      TransportID := ScopedID(ApplicationID);
      GateName := TransportID + '_gate';
      // Serialize ownership changes and inbox writes, never application startup.
      if not Gate.Acquire(GateName, 2000) then raise Exception.Create('Timed out waiting for the instance inbox.');
      if OwnerLock.Acquire(TransportID + '_owner', 0) then begin
        Receiver := TInstanceReceiver.Create(nil);
        Receiver.ServerID := TransportID;
        if not Receiver.StartServer(False) then raise Exception.Create('Cannot establish the instance inbox.');
        PrimaryLock := OwnerLock;
        OwnerLock := nil;
        InstanceRole := firPrimary;
        ActivityTick := GetTickCount64;
        StartupParameters.Assign(Parameters);
        StartupDirectory := WorkingDirectory;
        StartupPending := SendInitial and (Mode = fimForwardParameters);
        Outcome := FileAssResult(farSuccess, 'This process is the primary instance.');
      end else begin
        InstanceRole := firSecondary;
        if Mode = fimForwardParameters then begin
          Sender := TIPCClient.Create(nil);
          Sender.ServerID := TransportID;
          RequestID := Sender.PostRequest(ParameterMessage, Packet);
          {$ifdef unix}
          fpChmod(PChar(IncludeTrailingPathDelimiter(GetTempDir(False)) + TransportID +
            '-' + IntToHex(RequestID, 8)), &600);
          {$endif}
          Outcome := FileAssResult(farSuccess, 'Startup parameters queued for the primary instance.');
        end else Outcome := FileAssResult(farSuccess, 'Another instance is running; this launch is ignored.');
      end;
    except
      on E: Exception do begin
        if Assigned(Receiver) then Receiver.StopServer(False);
        FreeAndNil(Receiver);
        FreeAndNil(PrimaryLock);
        InstanceRole := firFailed;
        Outcome := FileAssFailure(E);
      end;
    end;
  finally Packet.Free; Sender.Free; OwnerLock.Free; Gate.Free; end;
  Report(Outcome);
  if (Role = firSecondary) and Assigned(SecondaryHandler) then SecondaryHandler(Self, Outcome);
  Result := Role;
end;
procedure TFileAssInstanceManager.DeliverParameters(Parameters: TStrings;
  const Directory: UTF8String; Initial: Boolean);
begin
  ActivityTick := GetTickCount64;
  if Initial or (Parameters.Count > 0) then begin
    if Assigned(ParametersHandler) then ParametersHandler(Self, Parameters, Directory, Initial)
    else if Parameters.Count > 0 then
      Report(FileAssResult(farInvalidConfiguration, 'Assign OnParameters to handle forwarded startup parameters.'));
  end
  else if not Initial and (Parameters.Count = 0) then
    ActivateRequested;
end;
procedure TFileAssInstanceManager.ActivateRequested;
begin
  if Assigned(ActivationHandler) then ActivationHandler(Self);
end;
function TFileAssInstanceManager.QueueParameters(Parameters: TStrings;
  const WorkingDirectory: UTF8String): Boolean;
var Gate: TInstanceLock; Sender: TIPCClient; Packet: TMemoryStream;
begin
  Result := False;
  Gate := TInstanceLock.Create;
  Sender := TIPCClient.Create(nil);
  Packet := TMemoryStream.Create;
  try
    try
      if Role <> firPrimary then raise Exception.Create('Start instance handling before queuing parameters.');
      WriteParameters(Packet, Parameters, WorkingDirectory);
      if not Gate.Acquire(GateName, 2000) then raise Exception.Create('Timed out waiting for the instance inbox.');
      Sender.ServerID := TransportID;
      Sender.PostRequest(ParameterMessage, Packet);
      Result := True;
    except on E: Exception do Report(FileAssFailure(E)); end;
  finally Packet.Free; Sender.Free; Gate.Free; end;
end;
procedure TFileAssInstanceManager.Poll;
var Packet: TMemoryStream; Parameters: TStringList; RequestID, Kind, I: Integer;
  Directory: UTF8String; FileInfo: TSearchRec;
begin
  if Polling or (Role <> firPrimary) or not ReadyForParameters or (Mode <> fimForwardParameters) then Exit;
  Polling := True;
  Packet := TMemoryStream.Create;
  Parameters := TStringList.Create;
  try
    try
      if StartupPending then begin
        StartupPending := False;
        DeliverParameters(StartupParameters, StartupDirectory, True);
      end;
      for I := 1 to 32 do begin
        if (Role <> firPrimary) or not ReadyForParameters or not Assigned(Receiver) then Break;
        if not Receiver.PeekRequest(RequestID, Kind) then Break;
        if SysUtils.FindFirst(TInstanceReceiver(Receiver).PendingPath(RequestID), faAnyFile, FileInfo) <> 0 then
          raise Exception.Create('Cannot read the queued startup request.');
        try
          if FileInfo.Size > MaxPacketSize + SizeOf(TMessageHeader) then
            raise Exception.Create('Queued startup request exceeds the message size limit.');
        finally SysUtils.FindClose(FileInfo); end;
        Packet.Clear;
        Parameters.Clear;
        if not Receiver.ReadRequest(RequestID, Packet) then raise Exception.Create('Cannot read the queued startup request.');
        if Kind <> ParameterMessage then raise Exception.Create('Unknown instance request type.');
        ReadParameters(Packet, Parameters, Directory);
        DeliverParameters(Parameters, Directory, False);
      end;
    except on E: Exception do Report(FileAssFailure(E)); end;
  finally Parameters.Free; Packet.Free; Polling := False; end;
end;
procedure TFileAssInstanceManager.Stop;
var Gate: TInstanceLock;
begin
  Gate := TInstanceLock.Create;
  try
    if Assigned(Receiver) then begin
      // Keep undispatched requests for the next primary, including crash recovery.
      Gate.Acquire(GateName, 2000);
      Receiver.StopServer(False);
      FreeAndNil(Receiver);
    end;
    FreeAndNil(PrimaryLock);
    InstanceRole := firStopped;
    StartupPending := False;
  finally Gate.Free; end;
end;
end.
