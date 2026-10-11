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
    property ApplicationID: UTF8String read GetApplicationID write SetApplicationID;
    property ApplicationName: UTF8String read GetApplicationName write SetApplicationName;
    property ApplicationDescription: UTF8String read GetApplicationDescription write SetApplicationDescription;
    property ExecutablePath: UTF8String read GetExecutablePath write SetExecutablePath;
    property RegistrationScope: TFileAssScope read GetScope write SetScope default fasCurrentUser;
    property FileTypes: TFileAssTypeCollection read GetFileTypes write SetFileTypes;
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
