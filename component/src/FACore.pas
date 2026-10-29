unit FACore;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, FATypes, FACollection;

type
  TFileAssManager = class;

  { What one operating system does with the settings.  FAWindows, FALinux
    and FAMacOS each have one. }
  TFileAssBackend = class
  public
    function RegisterTypes(App: TFileAssManager): TFileAssResult; virtual; abstract;
    function UnregisterTypes(App: TFileAssManager): TFileAssResult; virtual; abstract;
    function GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus; virtual; abstract;
    function GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult; virtual; abstract;
    function OpenDefaultAppsSettings: TFileAssResult; virtual; abstract;
    function Preview(App: TFileAssManager; Text: TStrings): TFileAssResult; virtual; abstract;
  end;

  { The file types of one application, and registering them.  TFileAssMan is
    this class on the component palette; a program with no forms can create
    it directly.  Nothing here needs the LCL. }
  TFileAssManager = class(TComponent)
  private
    AppIdentifier, AppName, AppDescription, ProgramPath: utf8string;
    InstallScope: TFileAssScope;
    MultipleDocuments, MenuEntry, DefaultClaim: boolean;
    LinuxAppIcon, MacAppIcon: utf8string;
    DocumentTypes: TFileAssTypeCollection;
    Backend: TFileAssBackend;
    ErrorHandler: TFileAssErrorEvent;
    procedure SetFileTypes(Value: TFileAssTypeCollection);
    function Report(const Value: TFileAssResult): TFileAssResult;
    function MayTouchSystem(out Why: TFileAssResult): boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { ExecutablePath, or this program when that is blank. }
    function Executable: utf8string;
    { Checks the settings for one platform.  An export is for some other
      machine, so it wants ExecutablePath filled in: NeedPath. }
    function ValidateFor(Target: TFileAssTarget; NeedPath: boolean = False): TFileAssResult;
    function Validate: TFileAssResult;
    function RegisterAll: TFileAssResult;
    function UnregisterAll: TFileAssResult;
    function GetRegistrationStatus: TFileAssStatus; overload;
    function GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus; overload;
    function GenerateDeploymentFiles(const OutputDirectory: utf8string): TFileAssResult;
    function OpenDefaultAppsSettings: TFileAssResult;
    function PreviewNativeRegistration(Text: TStrings): TFileAssResult;
  published
    // Required. Your own reverse-domain ID, such as org.example.notepad. Everything
    // FileAss installs is named after it, so keep it the same from release to release.
    property ApplicationID: utf8string read AppIdentifier write AppIdentifier;
    // Required. The name people see in "Open With", such as My Notepad.
    property ApplicationName: utf8string read AppName write AppName;
    // A short line about the application. Optional.
    property ApplicationDescription: utf8string read AppDescription write AppDescription;
    // Full path of the program to launch. Blank means this program. Fill it in
    // with the installed path before exporting files for an installer.
    property ExecutablePath: utf8string read ProgramPath write ProgramPath;
    // fasCurrentUser needs no administrator rights. fasAllUsers needs elevation
    // on Windows; on Linux export the files and install them with a package.
    property RegistrationScope: TFileAssScope read InstallScope write InstallScope default fasCurrentUser;
    // True if the program accepts several files in one launch: Linux then passes
    // them all at once (%F), and Windows sends a selection together. Your startup
    // code has to cope with more than one filename.
    property SupportsMultipleFiles: boolean read MultipleDocuments write MultipleDocuments default False;
    // Linux: list the program in the Applications menu. This is not autostart.
    property ShowInApplicationMenu: boolean read MenuEntry write MenuEntry default False;
    // Linux: when registering, make this program the default for its types in
    // the user's mimeapps.list, and count another program there as needing
    // repair. Off keeps whatever the user chose as the default.
    property ClaimDefault: boolean read DefaultClaim write DefaultClaim default False;
    // Linux: the program's icon - an SVG or 128-pixel PNG file, or the name of
    // an icon in the theme. A relative path is beside the executable.
    property LinuxApplicationIcon: utf8string read LinuxAppIcon write LinuxAppIcon;
    // macOS: the icon's file name in the bundle's Resources, such as App.icns.
    // The installer puts the file there; the export only names it.
    property MacApplicationIcon: utf8string read MacAppIcon write MacAppIcon;
    // The extensions, with their names, icons and launch arguments. Setting
    // these registers nothing; RegisterAll does.
    property FileTypes: TFileAssTypeCollection read DocumentTypes write SetFileTypes;
    // Called when an operation fails. The methods return the same result,
    // and no dialog is shown either way.
    property OnError: TFileAssErrorEvent read ErrorHandler write ErrorHandler;
  end;

implementation

uses
  FAValidation, FAFormats
  {$if defined(windows)}, FAWindows{$elseif defined(linux)}, FALinux{$elseif defined(darwin)}, FAMacOS{$endif};

constructor TFileAssManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DocumentTypes := TFileAssTypeCollection.Create(Self);
  {$if defined(windows)}
  Backend := TFileAssWindowsBackend.Create;
  {$elseif defined(linux)}
  Backend := TFileAssLinuxBackend.Create;
  {$elseif defined(darwin)}
  Backend := TFileAssMacOSBackend.Create;
  {$endif}
end;

destructor TFileAssManager.Destroy;
begin
  Backend.Free;
  DocumentTypes.Free;
  inherited Destroy;
end;

procedure TFileAssManager.SetFileTypes(Value: TFileAssTypeCollection);
begin
  DocumentTypes.Assign(Value);
end;

function TFileAssManager.Report(const Value: TFileAssResult): TFileAssResult;
begin
  Result := Value;
  if not Result.Succeeded and Assigned(ErrorHandler) then ErrorHandler(Self, Result);
end;

{ The form designer must never register anything, and some platforms have
  nothing to register with. }
function TFileAssManager.MayTouchSystem(out Why: TFileAssResult): boolean;
begin
  if csDesigning in ComponentState then
    Why := FileAssResult(farUnsupported, 'Nothing is changed on the system at design time.')
  else if Backend = nil then
    Why := FileAssResult(farUnsupported, 'File associations are not available on this platform.')
  else
    Why := FileAssResult(farSuccess, '');
  Result := Why.Succeeded;
end;

function TFileAssManager.Executable: utf8string;
begin
  Result := ProgramPath;
  if (Result = '') and not (csDesigning in ComponentState) then Result := FileAssExecutable;
end;

function TFileAssManager.ValidateFor(Target: TFileAssTarget; NeedPath: boolean): TFileAssResult;
var
  Path: utf8string;
begin
  if NeedPath then Path := ProgramPath
  else
    Path := Executable;
  Result := FileAssValidate(ApplicationID, ApplicationName, Path, FileTypes, Target);
  if Result.Succeeded and (FileAssContainsControl(ApplicationDescription) or FileAssContainsControl(LinuxApplicationIcon) or FileAssContainsControl(MacApplicationIcon)) then
    Result := FileAssResult(farInvalidConfiguration, 'The description and icons must not contain control characters.');
end;

function TFileAssManager.Validate: TFileAssResult;
begin
  Result := Report(ValidateFor(FileAssHostTarget));
end;

function TFileAssManager.RegisterAll: TFileAssResult;
begin
  if MayTouchSystem(Result) then Result := ValidateFor(FileAssHostTarget);
  {$ifdef windows}
  if Result.Succeeded and not FileExists(UTF8Decode(Executable)) then
  {$else}
  if Result.Succeeded and not FileExists(Executable) then
  {$endif}
    Result := FileAssResult(farNotFound, 'The executable does not exist: ' + Executable);
  if Result.Succeeded then Result := Backend.RegisterTypes(Self);
  Result := Report(Result);
end;

function TFileAssManager.UnregisterAll: TFileAssResult;
begin
  // only the ID is needed: removal goes by name, whatever the file types are now
  if MayTouchSystem(Result) and not FileAssValidIdentifier(ApplicationID) then
    Result := FileAssResult(farInvalidConfiguration, 'Invalid application identifier.');
  if Result.Succeeded then Result := Backend.UnregisterTypes(Self);
  Result := Report(Result);
end;

function TFileAssManager.GetRegistrationStatus: TFileAssStatus;
var
  Diagnostic: TFileAssResult;
begin
  Result := GetRegistrationStatus(Diagnostic);
end;

function TFileAssManager.GetRegistrationStatus(out Diagnostic: TFileAssResult): TFileAssStatus;
begin
  Result := fasVerificationFailed;
  Diagnostic := ValidateFor(FileAssHostTarget);
  if Diagnostic.Succeeded then Result := Backend.GetStatus(Self, Diagnostic);
  Diagnostic := Report(Diagnostic);
end;

function TFileAssManager.GenerateDeploymentFiles(const OutputDirectory: utf8string): TFileAssResult;
begin
  Result := ValidateFor(FileAssHostTarget, True);
  if Result.Succeeded and (Trim(OutputDirectory) = '') then
    Result := FileAssResult(farInvalidConfiguration, 'An output directory is required.');
  if Result.Succeeded then Result := Backend.GenerateDeploymentFiles(Self, OutputDirectory);
  Result := Report(Result);
end;

function TFileAssManager.PreviewNativeRegistration(Text: TStrings): TFileAssResult;
begin
  Text.Clear;
  Result := ValidateFor(FileAssHostTarget, True);
  if Result.Succeeded then Result := Backend.Preview(Self, Text);
  Result := Report(Result);
end;

function TFileAssManager.OpenDefaultAppsSettings: TFileAssResult;
begin
  if MayTouchSystem(Result) then Result := Backend.OpenDefaultAppsSettings;
  Result := Report(Result);
end;

end.
