unit FACore;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, FATypes, FACollection, FAValidation;
type
  TFileAssConfiguration = class(TPersistent)
  private
    AppIdentifier, AppName, AppDescription, ProgramPath: UTF8String;
    InstallScope: TFileAssScope;
    DocumentTypes: TFileAssTypeCollection;
    procedure SetFileTypes(Value: TFileAssTypeCollection);
  public
    constructor Create;
    destructor Destroy; override;
    function Validate(Target: TFileAssTarget; DesignMode: Boolean = False): TFileAssResult;
    function ResolveExecutable(DesignMode: Boolean): UTF8String;
  published
    property ApplicationID: UTF8String read AppIdentifier write AppIdentifier;
    property ApplicationName: UTF8String read AppName write AppName;
    property ApplicationDescription: UTF8String read AppDescription write AppDescription;
    property ExecutablePath: UTF8String read ProgramPath write ProgramPath;
    property RegistrationScope: TFileAssScope read InstallScope write InstallScope default fasCurrentUser;
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
  if Result.Succeeded and FileAssContainsControl(ApplicationDescription) then
    Result := FileAssResult(farInvalidConfiguration,
      'Application description must not contain control characters.');
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
