unit FAInstanceCore;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, AdvancedIPC, FATypes;

type
  TFileAssInstanceMode = (fimSingleInstance, fimForwardParameters);
  TFileAssInstanceRole = (firStopped, firPrimary, firSecondary, firFailed);
  TFileAssParametersEvent = procedure(Sender: TObject; Parameters: TStrings; const WorkingDirectory: utf8string; Initial: boolean) of object;

  { One running copy of an application, and the launches after it handed
    to that copy.  The first to start holds a lock and becomes the primary;
    later ones post their command line to its inbox and leave.  TFileAssInstance
    is this class for a form; a program with no forms calls Start and Poll. }
  TFileAssInstanceManager = class(TComponent)
  private
    Identity: utf8string;
    InstanceMode: TFileAssInstanceMode;
    Ready, SendInitial: boolean;
    StartupParameters: TStringList;
    StartupDirectory: utf8string;
    StartupPending, Polling: boolean;
    ActivityTick: QWord;
    InstanceRole: TFileAssInstanceRole;
    Outcome: TFileAssResult;
    PrimaryLock: TObject;
    Receiver: TIPCServer;
    TransportID, GateName: utf8string;
    ParametersHandler: TFileAssParametersEvent;
    ActivationHandler: TNotifyEvent;
    SecondaryHandler, ErrorHandler: TFileAssErrorEvent;
    procedure SetIdentity(const Value: utf8string);
    procedure SetMode(Value: TFileAssInstanceMode);
    procedure DeliverParameters(Parameters: TStrings; const Directory: utf8string; Initial: boolean);
  protected
    procedure SetReady(Value: boolean); virtual;
    procedure ActivateRequested; virtual;
    procedure Report(const Value: TFileAssResult); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start: TFileAssInstanceRole; overload;
    function Start(Parameters: TStrings; const WorkingDirectory: utf8string): TFileAssInstanceRole; overload;
    function QueueParameters(Parameters: TStrings; const WorkingDirectory: utf8string): boolean;
    procedure Poll;
    procedure Stop;
    property Role: TFileAssInstanceRole read InstanceRole;
    property LastResult: TFileAssResult read Outcome;
    // GetTickCount64 at the last start or delivery, so a caller can poll less when idle.
    property LastActivity: QWord read ActivityTick;
  published
    // Your reverse-domain ID, such as org.example.notepad. Copies with the same ID,
    // user and login session count as one application. Set it before Start.
    property ApplicationID: utf8string read Identity write SetIdentity;
    // fimSingleInstance: a second launch just quits. fimForwardParameters: it hands
    // its command line to the running copy first, which gets it in OnParameters.
    // Stop before changing this.
    property Mode: TFileAssInstanceMode read InstanceMode write SetMode default fimSingleInstance;
    // Nothing is delivered until this is True. While it is False this copy is
    // still the primary, so launches during a slow startup queue up and wait
    // their turn.
    property ReadyForParameters: boolean read Ready write SetReady default False;
    // True sends the first copy's own command line through OnParameters as well,
    // with Initial = True, so one handler opens files however they arrive. False
    // if you read ParamStr yourself.
    property IncludeInitialParameters: boolean read SendInitial write SendInitial default True;
    // A command line has arrived: this copy's own (Initial = True) or a later
    // launch's. A relative filename is relative to WorkingDirectory, which is the
    // launching copy's. Copy the list if you keep it. Runs in the thread that
    // calls Poll - the main thread, for the form component.
    property OnParameters: TFileAssParametersEvent read ParametersHandler write ParametersHandler;
    // Someone started the program again with nothing on the command line. The
    // form component brings its form to the front unless you handle this.
    property OnActivateRequested: TNotifyEvent read ActivationHandler write ActivationHandler;
    // Runs in the second copy, after it has been turned away or has handed over
    // its command line. Handing over is not the same as the files being open yet.
    property OnSecondaryInstance: TFileAssErrorEvent read SecondaryHandler write SecondaryHandler;
    // Something went wrong starting up or delivering. The form component shows
    // the message if you do not handle this; Start's result and LastResult say
    // the same thing.
    property OnError: TFileAssErrorEvent read ErrorHandler write ErrorHandler;
  end;

procedure FileAssStartupParameters(Parameters: TStrings);
function FileAssWorkingDirectory: utf8string;

implementation

uses MD5, FAValidation, FAFormats
  {$ifdef unix}, BaseUnix, Unix{$endif}
  {$ifdef windows}, Windows, ShellApi{$endif};

  {$ifdef windows}
function ProcessIdToSessionId(ProcessID: DWORD; var SessionID: DWORD): BOOL; stdcall; external 'kernel32.dll';
  {$endif}

const
  {$if defined(darwin) and not declared(O_NOFOLLOW)}
  O_NOFOLLOW = $00000100;  // FPC 3.2's Darwin RTL leaves it out
  {$endif}
  ParameterMessage = 1;
  PacketSignature = $31494146;  // 'FAI1'
  // the inbox is a file anyone in the session could have written
  MaxPacketSize = 1024 * 1024;
  MaxParameterCount = 4096;

type
  { A lock the system lets go of when the process ends, however it ends: a
    named mutex on Windows, flock on a file in the temp directory elsewhere. }
  TInstanceLock = class
  private
    Handle: THandle;
    Held: boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Acquire(const Name: utf8string; WaitMilliseconds: cardinal): boolean;
  end;

  TInstanceReceiver = class(TIPCServer)
  public
    function PendingPath(RequestID: integer): string;
  end;

function TInstanceReceiver.PendingPath(RequestID: integer): string;
begin
  Result := GetPeekedRequestFileName(RequestID);
end;

constructor TInstanceLock.Create;
begin
  inherited Create;
  Handle := THandle(-1);
end;

destructor TInstanceLock.Destroy;
begin
  if Handle <> THandle(-1) then
  begin
    {$ifdef windows}
    if Held then ReleaseMutex(Handle);
    CloseHandle(Handle);
    {$else}
    fpClose(Handle);
    {$endif}
  end;
  inherited Destroy;
end;

function TInstanceLock.Acquire(const Name: utf8string; WaitMilliseconds: cardinal): boolean;
var
  {$ifdef windows}
  Status: DWORD;
  {$else}
  Path: utf8string;
  Info: TStat;
  Deadline: QWord;
  ErrorCode: integer;
  {$endif}
begin
  if Held then Exit(True);
  {$ifdef windows}
  Handle := CreateMutexW(nil, False, PWideChar(UTF8Decode('Local\' + Name)));
  if Handle = 0 then
  begin
    Handle := THandle(-1);
    RaiseLastOSError;
  end;
  Status := WaitForSingleObject(Handle, WaitMilliseconds);
  // abandoned means the last holder died with it, which is ours to take
  Held := (Status = WAIT_OBJECT_0) or (Status = WAIT_ABANDONED);
  if not Held then
  begin
    CloseHandle(Handle);
    Handle := THandle(-1);
    if Status <> WAIT_TIMEOUT then RaiseLastOSError;
  end;
  {$else}
  // the temp directory is shared, so no following a link someone left there
  Path := IncludeTrailingPathDelimiter(GetTempDir(False)) + Name + '.lock';
  Handle := fpOpen(PChar(Path), O_RDWR or O_CREAT or O_NOFOLLOW, &600);
  if Handle = THandle(-1) then RaiseLastOSError(fpGetErrno);
  if (fpFStat(Handle, Info) <> 0) or (Info.st_uid <> fpGetUID) or not FPS_ISREG(Info.st_mode) then
    raise Exception.Create('The instance lock is not a regular file owned by this user.');
  fpFcntl(Handle, F_SETFD, 1);  // a child process must not inherit the lock
  Deadline := GetTickCount64 + WaitMilliseconds;
  repeat
    Held := fpFlock(Handle, LOCK_EX or LOCK_NB) = 0;
    if Held then Break;
    ErrorCode := fpGetErrno;
    if not (ErrorCode in [ESysEAGAIN, ESysEINTR]) then RaiseLastOSError(ErrorCode);
    if GetTickCount64 >= Deadline then Break;
    Sleep(5);
  until False;
  if not Held then
  begin
    fpClose(Handle);
    Handle := THandle(-1);
  end;
  {$endif}
  Result := Held;
end;

{ The name the lock and inbox go by: one per application, user and login
  session, so two people on one machine each get their own copy. }
function ScopedID(const ID: utf8string): utf8string;
var
  Scope: utf8string;
  {$ifdef windows}
  UserName: array[0..255] of widechar;
  Size, Session: DWORD;
  {$endif}
begin
  {$ifdef windows}
  Size := Length(UserName);
  if not GetUserNameW(@UserName[0], Size) then RaiseLastOSError;
  if not ProcessIdToSessionId(GetCurrentProcessID, Session) then RaiseLastOSError;
  Scope := UTF8Encode(UnicodeString(PWideChar(@UserName[0]))) + ':' + IntToStr(Session);
  {$else}
  Scope := IntToStr(fpGetUID) + ':' + GetEnvironmentVariable('XDG_SESSION_ID');
  if GetEnvironmentVariable('XDG_SESSION_ID') = '' then
    Scope := Scope + GetEnvironmentVariable('DISPLAY') + ':' + GetEnvironmentVariable('WAYLAND_DISPLAY');
  {$endif}
  Result := 'FileAss_' + MD5Print(MD5String(ID + #0 + Scope));
end;

{ The command line as UTF-8.  ParamStr loses characters outside the system
  code page on Windows, so there it is read from the wide API. }
procedure FileAssStartupParameters(Parameters: TStrings);
var
  I: integer;
  {$ifdef windows}
  Arguments: PPWideChar;
  Count: longint;
  {$endif}
begin
  Parameters.Clear;
  {$ifdef windows}
  Arguments := PPWideChar(CommandLineToArgvW(GetCommandLineW, @Count));
  if not Assigned(Arguments) then RaiseLastOSError;
  try
    for I := 1 to Count - 1 do Parameters.Add(string(UTF8Encode(unicodestring(Arguments[I]))));
  finally
    LocalFree(HLOCAL(Arguments));
  end;
  {$else}
  for I := 1 to ParamCount do Parameters.Add(ParamStr(I));
  {$endif}
end;

function FileAssWorkingDirectory: utf8string;
  {$ifdef windows}
var
  Buffer: unicodestring;
  Count: DWORD;
  {$endif}
begin
  {$ifdef windows}
  Count := GetCurrentDirectoryW(0, nil);
  if Count = 0 then RaiseLastOSError;
  SetLength(Buffer, Count);
  Count := GetCurrentDirectoryW(Length(Buffer), PWideChar(Buffer));
  if (Count = 0) or (Count >= DWORD(Length(Buffer))) then RaiseLastOSError;
  SetLength(Buffer, Count);
  Result := UTF8Encode(Buffer);
  {$else}
  Result := utf8string(GetCurrentDir);
  {$endif}
end;

procedure WriteText(Stream: TStream; const Value: utf8string);
var
  Count: longword;
begin
  Count := Length(Value);
  if (Count > MaxPacketSize) or (Stream.Size + Count + 4 > MaxPacketSize) then
    raise Exception.Create('Startup parameters exceed the message size limit.');
  Stream.WriteBuffer(Count, SizeOf(Count));
  if Count > 0 then Stream.WriteBuffer(Value[1], Count);
end;

function ReadText(Stream: TStream): utf8string;
var
  Count: longword;
begin
  Stream.ReadBuffer(Count, SizeOf(Count));
  if (Count > MaxPacketSize) or (Count > Stream.Size - Stream.Position) then
    raise Exception.Create('Invalid startup parameter message.');
  SetLength(Result, Count);
  if Count > 0 then Stream.ReadBuffer(Result[1], Count);
end;

procedure WriteParameters(Stream: TStream; Parameters: TStrings; const Directory: utf8string);
var
  Signature, Count: longword;
  I: integer;
begin
  if Parameters.Count > MaxParameterCount then raise Exception.Create('Too many startup parameters.');
  Signature := PacketSignature;
  Count := Parameters.Count;
  Stream.WriteBuffer(Signature, SizeOf(Signature));
  Stream.WriteBuffer(Count, SizeOf(Count));
  WriteText(Stream, Directory);
  for I := 0 to Parameters.Count - 1 do WriteText(Stream, utf8string(Parameters[I]));
  Stream.Position := 0;
end;

procedure ReadParameters(Stream: TStream; Parameters: TStrings; out Directory: utf8string);
var
  Signature, Count: longword;
  I: integer;
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

procedure TFileAssInstanceManager.SetIdentity(const Value: utf8string);
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

procedure TFileAssInstanceManager.SetReady(Value: boolean);
begin
  Ready := Value;
end;

procedure TFileAssInstanceManager.Report(const Value: TFileAssResult);
begin
  Outcome := Value;
  if not Value.Succeeded and Assigned(ErrorHandler) then ErrorHandler(Self, Value);
end;

function TFileAssInstanceManager.Start: TFileAssInstanceRole;
var
  Parameters: TStringList;
begin
  Parameters := TStringList.Create;
  try
    FileAssStartupParameters(Parameters);
    Result := Start(Parameters, FileAssWorkingDirectory);
  finally
    Parameters.Free;
  end;
end;

function TFileAssInstanceManager.Start(Parameters: TStrings; const WorkingDirectory: utf8string): TFileAssInstanceRole;
var
  Gate, OwnerLock: TInstanceLock;
  Sender: TIPCClient;
  Packet: TMemoryStream;
  RequestID: integer;
begin
  if Role = firPrimary then Exit(Role);
  Gate := TInstanceLock.Create;
  OwnerLock := TInstanceLock.Create;
  Sender := nil;
  Packet := nil;
  try
    try
      if not Assigned(Parameters) then raise Exception.Create('A startup parameter list is required.');
      if Mode = fimForwardParameters then
      begin
        Packet := TMemoryStream.Create;
        WriteParameters(Packet, Parameters, WorkingDirectory);
      end;
      if not FileAssValidIdentifier(ApplicationID) then
        raise Exception.Create('Set a stable reverse-domain ApplicationID before starting instance handling.');
      TransportID := ScopedID(ApplicationID);
      GateName := TransportID + '_gate';
      // the gate is held only while the lock and inbox change hands, not while the program starts
      if not Gate.Acquire(GateName, 2000) then raise Exception.Create('Timed out waiting for the instance inbox.');
      if OwnerLock.Acquire(TransportID + '_owner', 0) then
      begin
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
      end
      else
      begin
        InstanceRole := firSecondary;
        if Mode = fimForwardParameters then
        begin
          Sender := TIPCClient.Create(nil);
          Sender.ServerID := TransportID;
          RequestID := Sender.PostRequest(ParameterMessage, Packet);
          {$ifdef unix}
          fpChmod(PChar(IncludeTrailingPathDelimiter(GetTempDir(False)) + TransportID +
            '-' + IntToHex(RequestID, 8)), &600);
          {$endif}
          Outcome := FileAssResult(farSuccess, 'Startup parameters queued for the primary instance.');
        end
        else
          Outcome := FileAssResult(farSuccess, 'Another instance is running; this launch is ignored.');
      end;
    except
      on E: Exception do
      begin
        if Assigned(Receiver) then Receiver.StopServer(False);
        FreeAndNil(Receiver);
        FreeAndNil(PrimaryLock);
        InstanceRole := firFailed;
        Outcome := FileAssFailure(E);
      end;
    end;
  finally
    Packet.Free;
    Sender.Free;
    OwnerLock.Free;
    Gate.Free;
  end;
  Report(Outcome);
  if (Role = firSecondary) and Assigned(SecondaryHandler) then SecondaryHandler(Self, Outcome);
  Result := Role;
end;

procedure TFileAssInstanceManager.DeliverParameters(Parameters: TStrings; const Directory: utf8string; Initial: boolean);
begin
  ActivityTick := GetTickCount64;
  if Initial or (Parameters.Count > 0) then
  begin
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

function TFileAssInstanceManager.QueueParameters(Parameters: TStrings; const WorkingDirectory: utf8string): boolean;
var
  Gate: TInstanceLock;
  Sender: TIPCClient;
  Packet: TMemoryStream;
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
    except
      on E: Exception do Report(FileAssFailure(E));
    end;
  finally
    Packet.Free;
    Sender.Free;
    Gate.Free;
  end;
end;

procedure TFileAssInstanceManager.Poll;
var
  Packet: TMemoryStream;
  Parameters: TStringList;
  RequestID, Kind, I: integer;
  Directory: utf8string;
  FileInfo: TSearchRec;
begin
  if Polling or (Role <> firPrimary) or not ReadyForParameters or (Mode <> fimForwardParameters) then Exit;
  Polling := True;
  Packet := TMemoryStream.Create;
  Parameters := TStringList.Create;
  try
    try
      if StartupPending then
      begin
        StartupPending := False;
        DeliverParameters(StartupParameters, StartupDirectory, True);
      end;
      for I := 1 to 32 do
      begin
        if (Role <> firPrimary) or not ReadyForParameters or not Assigned(Receiver) then Break;
        if not Receiver.PeekRequest(RequestID, Kind) then Break;
        if SysUtils.FindFirst(TInstanceReceiver(Receiver).PendingPath(RequestID), faAnyFile, FileInfo) <> 0 then
          raise Exception.Create('Cannot read the queued startup request.');
        try
          if FileInfo.Size > MaxPacketSize + SizeOf(TMessageHeader) then
            raise Exception.Create('Queued startup request exceeds the message size limit.');
        finally
          SysUtils.FindClose(FileInfo);
        end;
        Packet.Clear;
        Parameters.Clear;
        if not Receiver.ReadRequest(RequestID, Packet) then raise Exception.Create('Cannot read the queued startup request.');
        if Kind <> ParameterMessage then raise Exception.Create('Unknown instance request type.');
        ReadParameters(Packet, Parameters, Directory);
        DeliverParameters(Parameters, Directory, False);
      end;
    except
      on E: Exception do Report(FileAssFailure(E));
    end;
  finally
    Parameters.Free;
    Packet.Free;
    Polling := False;
  end;
end;

procedure TFileAssInstanceManager.Stop;
var
  Gate: TInstanceLock;
begin
  Gate := TInstanceLock.Create;
  try
    if Assigned(Receiver) then
    begin
      // what is still in the inbox stays there for whichever copy starts next
      Gate.Acquire(GateName, 2000);
      Receiver.StopServer(False);
      FreeAndNil(Receiver);
    end;
    FreeAndNil(PrimaryLock);
    InstanceRole := firStopped;
    StartupPending := False;
  finally
    Gate.Free;
  end;
end;

end.
