unit FileAssMan;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, FATypes, FACollection, FACore;
type
  TFileAssMan = class(TComponent)
  private
    AssociationManager: TFileAssManager;
    ErrorHandler: TFileAssErrorEvent;
    function GetApplicationID: UTF8String;
    function GetApplicationName: UTF8String;
    function GetApplicationDescription: UTF8String;
    function GetExecutablePath: UTF8String;
    function GetMultipleFiles: Boolean;
    procedure SetMultipleFiles(Value: Boolean);
    function GetShowInApplicationMenu: Boolean;
    procedure SetShowInApplicationMenu(const Value: Boolean);
    function GetLinuxApplicationIcon: UTF8String;
    procedure SetLinuxApplicationIcon(const Value: UTF8String);
    function GetMacApplicationIcon: UTF8String;
    procedure SetMacApplicationIcon(const Value: UTF8String);
    function GetScope: TFileAssScope;
    function GetFileTypes: TFileAssTypeCollection;
    procedure SetApplicationID(const Value: UTF8String);
    procedure SetApplicationName(const Value: UTF8String);
    procedure SetApplicationDescription(const Value: UTF8String);
    procedure SetExecutablePath(const Value: UTF8String);
    procedure SetScope(Value: TFileAssScope);
    procedure SetFileTypes(Value: TFileAssTypeCollection);
    function Report(const Value: TFileAssResult): TFileAssResult;
    function DesignGuard: TFileAssResult;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Validate: TFileAssResult;
    function RegisterAll: TFileAssResult;
    function UnregisterAll: TFileAssResult;
    function GetRegistrationStatus: TFileAssStatus; overload;
    function GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus; overload;
    function GenerateDeploymentFiles(const OutputDirectory: UTF8String): TFileAssResult;
    function OpenDefaultAppsSettings: TFileAssResult;
    function PreviewNativeRegistration(Text: TStrings): TFileAssResult;
  published
    // Stable reverse-domain ID, such as org.example.notepad. Required for ownership;
    // keep it unchanged between releases so upgrades and removal find the same registrations.
    property ApplicationID: UTF8String read GetApplicationID write SetApplicationID;
    // Required application display name, such as My Notepad. Shown in application
    // choosers and generated registration resources.
    property ApplicationName: UTF8String read GetApplicationName write SetApplicationName;
    // Optional short description of the application, used in generated native metadata.
    property ApplicationDescription: UTF8String read GetApplicationDescription write SetApplicationDescription;
    // Absolute path of the executable to launch. Blank uses the running executable.
    // For design-time previews and deployment files, supply the final installed path.
    property ExecutablePath: UTF8String read GetExecutablePath write SetExecutablePath;
    // fasCurrentUser is the default and needs no administrator access. fasAllUsers
    // requires elevation on Windows or system-package deployment on Linux.
    property RegistrationScope: TFileAssScope read GetScope write SetScope default fasCurrentUser;
    // Default False. True uses Linux batch arguments (%F) and Windows multi-selection
    // (MultiSelectModel Player, subject to shell limits). Your startup handler must accept multiple filenames.
    property SupportsMultipleFiles: Boolean read GetMultipleFiles write SetMultipleFiles default False;
    // Default False. Show the Linux application entry in the Applications menu.
    // Registration and export use this setting; it does not enable login autostart.
    property ShowInApplicationMenu: Boolean read GetShowInApplicationMenu write SetShowInApplicationMenu default False;
    // Linux launcher icon: an SVG/128-pixel PNG path or installed theme name.
    // Relative paths resolve beside the executable; file icons are installed with ownership tracking.
    property LinuxApplicationIcon: UTF8String read GetLinuxApplicationIcon write SetLinuxApplicationIcon;
    // macOS application icon filename in Contents/Resources, such as App.icns.
    // Export references this filename; the installer must supply the icon in the bundle.
    property MacApplicationIcon: UTF8String read GetMacApplicationIcon write SetMacApplicationIcon;
    // Extensions and their document names, icons, and launch arguments. Edit the collection
    // to add file types. Registration and deployment generation both use these settings;
    // nothing is registered just by configuring or loading the component.
    property FileTypes: TFileAssTypeCollection read GetFileTypes write SetFileTypes;
    // Optional notification when an operation fails. Inspect the supplied result code
    // and message; operation methods also return that result. No automatic dialog is shown.
    property OnError: TFileAssErrorEvent read ErrorHandler write ErrorHandler;
  end;
implementation
constructor TFileAssMan.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AssociationManager := TFileAssManager.Create;
end;
destructor TFileAssMan.Destroy;
begin
  AssociationManager.Free;
  inherited Destroy;
end;
function TFileAssMan.GetApplicationID: UTF8String;
begin Result := AssociationManager.Configuration.ApplicationID; end;
function TFileAssMan.GetApplicationName: UTF8String;
begin Result := AssociationManager.Configuration.ApplicationName; end;
function TFileAssMan.GetApplicationDescription: UTF8String;
begin Result := AssociationManager.Configuration.ApplicationDescription; end;
function TFileAssMan.GetExecutablePath: UTF8String;
begin Result := AssociationManager.Configuration.ExecutablePath; end;
function TFileAssMan.GetMultipleFiles: Boolean;
begin Result := AssociationManager.Configuration.SupportsMultipleFiles; end;
procedure TFileAssMan.SetMultipleFiles(Value: Boolean);
begin AssociationManager.Configuration.SupportsMultipleFiles := Value; end;
function TFileAssMan.GetShowInApplicationMenu: Boolean;
begin Result := AssociationManager.Configuration.ShowInApplicationMenu; end;
procedure TFileAssMan.SetShowInApplicationMenu(const Value: Boolean);
begin AssociationManager.Configuration.ShowInApplicationMenu := Value; end;
function TFileAssMan.GetLinuxApplicationIcon: UTF8String;
begin Result := AssociationManager.Configuration.LinuxApplicationIcon; end;
procedure TFileAssMan.SetLinuxApplicationIcon(const Value: UTF8String);
begin AssociationManager.Configuration.LinuxApplicationIcon := Value; end;
function TFileAssMan.GetMacApplicationIcon: UTF8String;
begin Result := AssociationManager.Configuration.MacApplicationIcon; end;
procedure TFileAssMan.SetMacApplicationIcon(const Value: UTF8String);
begin AssociationManager.Configuration.MacApplicationIcon := Value; end;
function TFileAssMan.GetScope: TFileAssScope;
begin Result := AssociationManager.Configuration.RegistrationScope; end;
function TFileAssMan.GetFileTypes: TFileAssTypeCollection;
begin Result := AssociationManager.Configuration.FileTypes; end;
procedure TFileAssMan.SetApplicationID(const Value: UTF8String);
begin AssociationManager.Configuration.ApplicationID := Value; end;
procedure TFileAssMan.SetApplicationName(const Value: UTF8String);
begin AssociationManager.Configuration.ApplicationName := Value; end;
procedure TFileAssMan.SetApplicationDescription(const Value: UTF8String);
begin AssociationManager.Configuration.ApplicationDescription := Value; end;
procedure TFileAssMan.SetExecutablePath(const Value: UTF8String);
begin AssociationManager.Configuration.ExecutablePath := Value; end;
procedure TFileAssMan.SetScope(Value: TFileAssScope);
begin AssociationManager.Configuration.RegistrationScope := Value; end;
procedure TFileAssMan.SetFileTypes(Value: TFileAssTypeCollection);
begin AssociationManager.Configuration.FileTypes := Value; end;
function TFileAssMan.Report(const Value: TFileAssResult): TFileAssResult;
begin
  Result := Value;
  if not Result.Succeeded and Assigned(ErrorHandler) then ErrorHandler(Self, Result);
end;
function TFileAssMan.DesignGuard: TFileAssResult;
begin
  if csDesigning in ComponentState then
    Result := FileAssResult(farUnsupported, 'System operations are disabled at design time.')
  else Result := FileAssResult(farSuccess, '');
end;
function TFileAssMan.Validate: TFileAssResult;
begin
  Result := Report(AssociationManager.Configuration.Validate(FileAssHostTarget, csDesigning in ComponentState));
end;
function TFileAssMan.RegisterAll: TFileAssResult;
begin
  Result := DesignGuard;
  if Result.Succeeded then Result := AssociationManager.RegisterAll;
  Result := Report(Result);
end;
function TFileAssMan.UnregisterAll: TFileAssResult;
begin
  Result := DesignGuard;
  if Result.Succeeded then Result := AssociationManager.UnregisterAll;
  Result := Report(Result);
end;
function TFileAssMan.GetRegistrationStatus: TFileAssStatus;
var Diagnostic: TFileAssResult;
begin Result := GetRegistrationStatus(Diagnostic); end;
function TFileAssMan.GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus;
begin
  Result := AssociationManager.GetRegistrationStatus(Diagnostic);
  Diagnostic := Report(Diagnostic);
end;
function TFileAssMan.GenerateDeploymentFiles(const OutputDirectory: UTF8String): TFileAssResult;
begin Result := Report(AssociationManager.GenerateDeploymentFiles(OutputDirectory)); end;
function TFileAssMan.PreviewNativeRegistration(Text: TStrings): TFileAssResult;
begin Result := Report(AssociationManager.PreviewNativeRegistration(Text)); end;
function TFileAssMan.OpenDefaultAppsSettings: TFileAssResult;
begin
  Result := DesignGuard;
  if Result.Succeeded then Result := AssociationManager.OpenDefaultAppsSettings;
  Result := Report(Result);
end;
end.
