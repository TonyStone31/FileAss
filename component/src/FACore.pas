unit FACore;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, FATypes, FACollection, FAValidation;
type
  TFileAssConfiguration = class(TPersistent)
  private
    AppIdentifier, AppName, AppDescription, ProgramPath: UTF8String;
    InstallScope: TFileAssScope;
    MultipleDocuments, MenuEntry: Boolean;
    LinuxAppIcon, MacAppIcon: UTF8String;
    DocumentTypes: TFileAssTypeCollection;
    procedure SetFileTypes(Value: TFileAssTypeCollection);
  public
    constructor Create;
    destructor Destroy; override;
    function Validate(Target: TFileAssTarget; DesignMode: Boolean = False): TFileAssResult;
    function ResolveExecutable(DesignMode: Boolean): UTF8String;
  published
    // Stable reverse-domain ID, such as org.example.notepad. Required for ownership;
    // keep it unchanged between releases so upgrades and removal find the same registrations.
    property ApplicationID: UTF8String read AppIdentifier write AppIdentifier;
    // Required application display name, such as My Notepad. Shown in application
    // choosers and generated registration resources.
    property ApplicationName: UTF8String read AppName write AppName;
    // Optional short description of the application, used in generated native metadata.
    property ApplicationDescription: UTF8String read AppDescription write AppDescription;
    // Absolute path of the executable to launch. Blank uses the running executable.
    // For design-time previews and deployment files, supply the final installed path.
    property ExecutablePath: UTF8String read ProgramPath write ProgramPath;
    // fasCurrentUser is the default and needs no administrator access. fasAllUsers
    // requires elevation on Windows or system-package deployment on Linux.
    property RegistrationScope: TFileAssScope read InstallScope write InstallScope default fasCurrentUser;
    // Default False. True uses Linux batch arguments (%F) and Windows multi-selection
    // (MultiSelectModel Player, subject to shell limits). Your startup handler must accept multiple filenames.
    property SupportsMultipleFiles: Boolean read MultipleDocuments write MultipleDocuments default False;
    // Default False. Show the Linux application entry in the Applications menu.
    // Registration and export use this setting; it does not enable login autostart.
    property ShowInApplicationMenu: Boolean read MenuEntry write MenuEntry default False;
    // Linux launcher icon: an SVG/128-pixel PNG path or installed theme name.
    // Relative paths resolve beside the executable; file icons are installed with ownership tracking.
    property LinuxApplicationIcon: UTF8String read LinuxAppIcon write LinuxAppIcon;
    // macOS application icon filename in Contents/Resources, such as App.icns.
    // Export references this filename; the installer must supply the icon in the bundle.
    property MacApplicationIcon: UTF8String read MacAppIcon write MacAppIcon;
    // Extensions and their document names, icons, and launch arguments. Edit the collection
    // to add file types. Registration and deployment generation both use these settings;
    // nothing is registered just by configuring or loading the component.
    property FileTypes: TFileAssTypeCollection read DocumentTypes write SetFileTypes;
  end;
  TFileAssBackend = class
  public
    function RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; virtual; abstract;
    function UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; virtual; abstract;
    function GetStatus(Configuration: TFileAssConfiguration;
      out Diagnostic: TFileAssResult): TFileAssStatus; virtual; abstract;
    function GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
      const OutputDirectory: UTF8String): TFileAssResult; virtual; abstract;
    function OpenDefaultAppsSettings: TFileAssResult; virtual; abstract;
    function Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult; virtual; abstract;
  end;
  TFileAssManager = class
  private
    Settings: TFileAssConfiguration;
    NativeBackend: TFileAssBackend;
  public
    constructor Create;
    destructor Destroy; override;
    function Validate: TFileAssResult;
    function RegisterAll: TFileAssResult;
    function UnregisterAll: TFileAssResult;
    function GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus;
    function GenerateDeploymentFiles(const OutputDirectory: UTF8String): TFileAssResult;
    function OpenDefaultAppsSettings: TFileAssResult;
    function PreviewNativeRegistration(Text: TStrings): TFileAssResult;
    property Configuration: TFileAssConfiguration read Settings;
  end;
implementation
uses
  FAFormats
  {$if defined(windows)}, FAWindows{$elseif defined(linux)}, FALinux{$elseif defined(darwin)}, FAMacOS{$endif};

function CreateBackend: TFileAssBackend;
begin
  {$if defined(windows)}Result := TFileAssWindowsBackend.Create;
  {$elseif defined(linux)}Result := TFileAssLinuxBackend.Create;
  {$elseif defined(darwin)}Result := TFileAssMacOSBackend.Create;
  {$else}Result := nil;{$endif}
end;
constructor TFileAssConfiguration.Create;
begin
  inherited Create;
  DocumentTypes := TFileAssTypeCollection.Create(Self);
  InstallScope := fasCurrentUser;
end;
destructor TFileAssConfiguration.Destroy;
begin
  DocumentTypes.Free;
  inherited Destroy;
end;
procedure TFileAssConfiguration.SetFileTypes(Value: TFileAssTypeCollection);
begin
  DocumentTypes.Assign(Value);
end;
function TFileAssConfiguration.ResolveExecutable(DesignMode: Boolean): UTF8String;
begin
  Result := ProgramPath;
  if (Result = '') and not DesignMode then Result := FileAssExecutable;
end;
function TFileAssConfiguration.Validate(Target: TFileAssTarget;
  DesignMode: Boolean): TFileAssResult;
begin
  Result := FileAssValidate(ApplicationID, ApplicationName,
    ResolveExecutable(DesignMode), FileTypes, Target);
  if Result.Succeeded and (FileAssContainsControl(ApplicationDescription) or
    FileAssContainsControl(LinuxApplicationIcon) or FileAssContainsControl(MacApplicationIcon)) then
    Result := FileAssResult(farInvalidConfiguration,
      'Application description and icons must not contain control characters.');
end;
constructor TFileAssManager.Create;
begin
  inherited Create;
  Settings := TFileAssConfiguration.Create;
  NativeBackend := CreateBackend;
end;
destructor TFileAssManager.Destroy;
begin
  NativeBackend.Free;
  Settings.Free;
  inherited Destroy;
end;
function TFileAssManager.Validate: TFileAssResult;
begin
  Result := Configuration.Validate(FileAssHostTarget);
end;
function TFileAssManager.RegisterAll: TFileAssResult;
begin
  Result := Validate;
  if not Result.Succeeded then Exit;
  {$ifdef windows}
  if not FileExists(UTF8Decode(Configuration.ResolveExecutable(False))) then
  {$else}
  if not FileExists(Configuration.ResolveExecutable(False)) then
  {$endif}
    Exit(FileAssResult(farNotFound, 'The configured executable does not exist.'));
  if Assigned(NativeBackend) then Result := NativeBackend.RegisterTypes(Configuration)
  else Result := FileAssResult(farRequiresDeployment, 'This platform requires bundle deployment.');
end;
function TFileAssManager.UnregisterAll: TFileAssResult;
begin
  if not FileAssValidIdentifier(Configuration.ApplicationID) then
    Exit(FileAssResult(farInvalidConfiguration, 'Invalid application identifier.'));
  if Assigned(NativeBackend) then Result := NativeBackend.UnregisterTypes(Configuration)
  else Result := FileAssResult(farUnsupported, 'Native removal is unavailable.');
end;
function TFileAssManager.GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus;
begin
  Diagnostic := Validate;
  if not Diagnostic.Succeeded then Exit(fasVerificationFailed);
  if Assigned(NativeBackend) then Result := NativeBackend.GetStatus(Configuration, Diagnostic)
  else begin
    Diagnostic := FileAssResult(farUnsupported, 'Native inspection is unavailable.');
    Result := fasUnavailable;
  end;
end;
function TFileAssManager.GenerateDeploymentFiles(const OutputDirectory: UTF8String): TFileAssResult;
begin
  Result := Configuration.Validate(FileAssHostTarget, True);
  if not Result.Succeeded then Exit;
  if Trim(OutputDirectory) = '' then
    Result := FileAssResult(farInvalidConfiguration, 'An output directory is required.')
  else if Assigned(NativeBackend) then
    Result := NativeBackend.GenerateDeploymentFiles(Configuration, OutputDirectory)
  else Result := FileAssResult(farUnsupported, 'Deployment generation is unavailable.');
end;
function TFileAssManager.PreviewNativeRegistration(Text: TStrings): TFileAssResult;
begin
  Text.Clear;
  Result := Configuration.Validate(FileAssHostTarget, True);
  if not Result.Succeeded then Exit;
  if Assigned(NativeBackend) then Result := NativeBackend.Preview(Configuration, Text)
  else Result := FileAssResult(farUnsupported, 'Native preview is unavailable.');
end;
function TFileAssManager.OpenDefaultAppsSettings: TFileAssResult;
begin
  if Assigned(NativeBackend) then Result := NativeBackend.OpenDefaultAppsSettings
  else Result := FileAssResult(farUnsupported, 'Default application settings are unavailable.');
end;
end.
