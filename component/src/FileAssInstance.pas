unit FileAssInstance;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, ExtCtrls, FileAssMan, FAInstanceCore, FATypes;
type
  TFileAssInstance = class(TFileAssInstanceManager)
  private
    Associations: TFileAssMan;
    StartupEnabled, AutomaticReady, QuitSecondary, OwnerCreating, NativeFiles: Boolean;
    MessageTimer: TTimer;
    procedure SetAssociations(Value: TFileAssMan);
    procedure SetEnabled(Value: Boolean);
    procedure CheckMessages(Sender: TObject);
    procedure AfterStartup(Data: PtrInt);
    procedure OwnerCreated(Sender: TObject);
    procedure FilesOpened(Sender: TObject; const FileNames: array of string);
    procedure DeliverPending(Data: PtrInt);
  protected
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure SetReady(Value: Boolean); override;
    procedure ActivateRequested; override;
    procedure Report(const Value: TFileAssResult); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start: TFileAssInstanceRole; reintroduce;
    procedure Stop; reintroduce;
  published
    // Default False. True starts instance handling when the form loads. At runtime,
    // setting True starts and False stops it. The designer never starts instance handling;
    // this property does not register file associations. Explicit Start is also available.
    property Enabled: Boolean read StartupEnabled write SetEnabled default False;
    // Optional association component supplying ApplicationID when Start runs.
    // When assigned, its ID takes precedence over this component's ApplicationID.
    // Linking it does not register associations. Stop before changing this reference.
    property FileAssMan: TFileAssMan read Associations write SetAssociations;
    // Default True. Routes LCL file-open/drop notifications through OnParameters
    // in forwarding mode, using the same readiness gate. Disable if your application
    // already handles these notifications, to avoid processing a file twice.
    property HandleFileOpenEvents: Boolean read NativeFiles write NativeFiles default True;
    // Default True. Marks the primary ready after normal owner-form creation.
    // Set False if initialization continues afterward, then set ReadyForParameters=True
    // yourself when the application can handle files. Ownership is claimed immediately.
    property AutoReady: Boolean read AutomaticReady write AutomaticReady default True;
    // Default True. Secondary or failed launches terminate without showing the main
    // form. False leaves shutdown to your code. FormCreate can still run; skip primary-only
    // startup work there when Role is not firPrimary.
    property AutoTerminateSecondary: Boolean read QuitSecondary write QuitSecondary default True;
  end;
implementation
uses SysUtils, Forms, Dialogs;
constructor TFileAssInstance.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutomaticReady := True;
  QuitSecondary := True;
  NativeFiles := True;
  MessageTimer := TTimer.Create(Self);
  MessageTimer.Enabled := False;
  MessageTimer.Interval := 50;
  MessageTimer.OnTimer := @CheckMessages;
end;
destructor TFileAssInstance.Destroy;
begin
  Stop;
  inherited Destroy;
end;
procedure TFileAssInstance.SetAssociations(Value: TFileAssMan);
begin
  if Value = Associations then Exit;
  if Role = firPrimary then raise EComponentError.Create('Stop instance handling before changing FileAssMan.');
  if Assigned(Associations) then Associations.RemoveFreeNotification(Self);
  Associations := Value;
  if Assigned(Associations) then Associations.FreeNotification(Self);
end;
procedure TFileAssInstance.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = Associations) then Associations := nil;
end;
procedure TFileAssInstance.SetEnabled(Value: Boolean);
begin
  StartupEnabled := Value;
  if (csLoading in ComponentState) or (csDesigning in ComponentState) then Exit;
  if Value then Start else Stop;
end;
procedure TFileAssInstance.Loaded;
begin
  inherited Loaded;
  if StartupEnabled and not (csDesigning in ComponentState) then Start;
end;
function TFileAssInstance.Start: TFileAssInstanceRole;
begin
  if csDesigning in ComponentState then Exit(firStopped);
  if Role = firPrimary then Exit(Role);
  if Assigned(Associations) then ApplicationID := Associations.ApplicationID;
  Result := inherited Start;
  if Result = firPrimary then begin
    MessageTimer.Interval := 50;
    MessageTimer.Enabled := True;
    Application.AddOnDropFilesHandler(@FilesOpened);
    if (Owner is TCustomForm) and (fsCreating in TCustomForm(Owner).FormState) then begin
      OwnerCreating := True;
      TCustomForm(Owner).AddHandlerCreate(@OwnerCreated);
    end else Application.QueueAsyncCall(@AfterStartup, 0);
  end else if QuitSecondary then begin
    Application.ShowMainForm := False;
    Application.Terminate;
  end;
end;
procedure TFileAssInstance.OwnerCreated(Sender: TObject);
begin
  if not OwnerCreating then Exit;
  OwnerCreating := False;
  Application.QueueAsyncCall(@AfterStartup, 0);
end;
procedure TFileAssInstance.AfterStartup(Data: PtrInt);
begin
  if Role <> firPrimary then Exit;
  if AutoReady then ReadyForParameters := True;
  Poll;
end;
procedure TFileAssInstance.SetReady(Value: Boolean);
begin
  if Value = ReadyForParameters then Exit;
  inherited SetReady(Value);
  if Value and (Role = firPrimary) and not (csDestroying in ComponentState) then
    Application.QueueAsyncCall(@DeliverPending, 0);
end;
procedure TFileAssInstance.DeliverPending(Data: PtrInt);
begin if not OwnerCreating then Poll; end;
procedure TFileAssInstance.CheckMessages(Sender: TObject);
begin
  if OwnerCreating then Exit;
  Poll;
  // Poll briskly around startup and recent deliveries, gently once idle.
  if GetTickCount64 - LastActivity > 10000 then MessageTimer.Interval := 250
  else MessageTimer.Interval := 50;
end;
procedure TFileAssInstance.FilesOpened(Sender: TObject; const FileNames: array of string);
var Parameters: TStringList; I: Integer;
begin
  if not HandleFileOpenEvents or (Mode <> fimForwardParameters) then Exit;
  Parameters := TStringList.Create;
  try
    for I := Low(FileNames) to High(FileNames) do Parameters.Add(FileNames[I]);
    QueueParameters(Parameters, FileAssWorkingDirectory);
  finally Parameters.Free; end;
end;
procedure TFileAssInstance.ActivateRequested;
var Target: TCustomForm;
begin
  if Assigned(OnActivateRequested) then inherited ActivateRequested
  else begin
    if Owner is TCustomForm then Target := TCustomForm(Owner) else Target := Application.MainForm;
    if not Assigned(Target) then Exit;
    if Target.WindowState = wsMinimized then Target.WindowState := wsNormal;
    Target.Show;
    Target.BringToFront;
  end;
end;
procedure TFileAssInstance.Report(const Value: TFileAssResult);
begin
  inherited Report(Value);
  if not Value.Succeeded and not Assigned(OnError) then ShowMessage(Value.Message);
end;
procedure TFileAssInstance.Stop;
begin
  if Assigned(MessageTimer) then MessageTimer.Enabled := False;
  OwnerCreating := False;
  if (Owner is TCustomForm) and not (csDestroying in Owner.ComponentState) then
    TCustomForm(Owner).RemoveHandlerCreate(@OwnerCreated);
  Application.RemoveAsyncCalls(Self);
  Application.RemoveOnDropFilesHandler(@FilesOpened);
  inherited Stop;
end;
end.
