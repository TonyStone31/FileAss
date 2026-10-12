unit FALinux;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Process, MD5, BaseUnix, FATypes, FACollection, FACore, FAFormats;
type
  TFileAssLinuxBackend = class(TFileAssBackend)
  private
    function DataDirectory: UTF8String;
    function BuildResources(Configuration: TFileAssConfiguration;
      Resources: TFileAssResources): TFileAssResult;
    function UpdateDatabases(const Root: UTF8String): TFileAssResult;
    function CheckScope(Configuration: TFileAssConfiguration): TFileAssResult;
    function OwnedPath(const Path, ApplicationID: UTF8String): Boolean;
    procedure ReadManifest(const Root, ApplicationID: UTF8String; Manifest: TStrings);
    procedure CheckOwnedFiles(const Root: UTF8String; Manifest: TStrings);
  public
    function RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; override;
    function UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; override;
    function GetStatus(Configuration: TFileAssConfiguration;
      out Diagnostic: TFileAssResult): TFileAssStatus; override;
    function GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
      const OutputDirectory: UTF8String): TFileAssResult; override;
    function OpenDefaultAppsSettings: TFileAssResult; override;
    function Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult; override;
  end;
implementation
function TFileAssLinuxBackend.DataDirectory: UTF8String;
begin
  Result := GetEnvironmentVariable('XDG_DATA_HOME');
  if (Result = '') or (Result[1] <> '/') then begin
    Result := GetEnvironmentVariable('HOME');
    if (Result = '') or (Result[1] <> '/') then
      raise Exception.Create('An absolute HOME or XDG_DATA_HOME is required.');
    Result := IncludeTrailingPathDelimiter(Result) + '.local/share';
  end;
  Result := ExcludeTrailingPathDelimiter(Result);
end;
function TFileAssLinuxBackend.CheckScope(Configuration: TFileAssConfiguration): TFileAssResult;
begin
  if Configuration.RegistrationScope = fasAllUsers then
    Result := FileAssResult(farRequiresDeployment,
      'Use generated resources with a system package for all-user installation.')
  else Result := FileAssResult(farSuccess, '');
end;
function TFileAssLinuxBackend.BuildResources(Configuration: TFileAssConfiguration;
  Resources: TFileAssResources): TFileAssResult;
var
  Desktop, Xml, MimeList, Arguments, IconName, IconPath, Extension, StaticArguments: UTF8String;
  Item: TFileAssTypeItem;
  I, J: Integer;
  Types, Parsed: TStringList;
begin
  Result := FileAssResult(farInvalidConfiguration, '');
  Types := TStringList.Create;
  Parsed := TStringList.Create;
  try
    StaticArguments := '';
    for I := 0 to Configuration.FileTypes.Count - 1 do begin
      Item := Configuration.FileTypes[I];
      if not Item.Enabled then Continue;
      if Types.Count = 0 then StaticArguments := Item.OpenArguments
      else if Item.OpenArguments <> StaticArguments then begin
        Result.Message := 'Linux requires the same OpenArguments for all enabled file types.';
        Exit;
      end;
      if Types.IndexOf(Item.MimeType) < 0 then Types.Add(Item.MimeType);
    end;
    if not FileAssParseArguments(StaticArguments, Parsed) then begin
      Result.Message := 'OpenArguments contains an unmatched double quote.';
      Exit;
    end;
    Arguments := FileAssDesktopArgument(Configuration.ResolveExecutable(False));
    for I := 0 to Parsed.Count - 1 do
      Arguments := Arguments + ' ' + FileAssDesktopArgument(Parsed[I]);
    MimeList := '';
    Xml := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
      '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">' + #10;
    for I := 0 to Types.Count - 1 do begin
      MimeList := MimeList + Types[I] + ';';
      IconPath := '';
      Xml := Xml + '  <mime-type type="' + FileAssXml(Types[I]) + '">' + #10;
      for J := 0 to Configuration.FileTypes.Count - 1 do begin
        Item := Configuration.FileTypes[J];
        if not Item.Enabled or (Item.MimeType <> Types[I]) then Continue;
        if IconPath = '' then begin
          IconPath := Item.LinuxIcon;
          Xml := Xml + '    <comment>' + FileAssXml(Item.Description) + '</comment>' + #10;
        end else if (Item.LinuxIcon <> '') and (IconPath <> Item.LinuxIcon) then begin
          Result.Message := 'Extensions sharing a MIME type must use the same Linux icon.';
          Exit;
        end;
        Xml := Xml + '    <glob pattern="*' + FileAssXml(Item.Extension) + '"/>' + #10;
      end;
      if IconPath <> '' then begin
        if (IconPath[1] <> '/') and (Pos('/', IconPath) > 0) then
          IconPath := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(
            Configuration.ResolveExecutable(False))) + IconPath);
        if IconPath[1] = '/' then begin
          Extension := LowerCase(ExtractFileExt(IconPath));
          if not (Extension = '.svg') and not (Extension = '.png') then begin
            Result.Message := 'Linux icon files must be SVG or 128-pixel PNG files.';
            Exit;
          end;
          IconName := Configuration.ApplicationID + '-mime-' + IntToStr(I + 1);
          if Extension = '.svg' then
            Resources.AddFile('icons/hicolor/scalable/mimetypes/' + IconName + Extension,
              FileAssReadFile(IconPath))
          else Resources.AddFile('icons/hicolor/128x128/mimetypes/' + IconName + Extension,
              FileAssReadFile(IconPath));
        end else IconName := IconPath;
        // Keep a theme's generic page from outranking the custom hicolor icon.
        Xml := Xml + '    <icon name="' + FileAssXml(IconName) + '"/>' + #10 +
          '    <generic-icon name="' + FileAssXml(IconName) + '"/>' + #10;
      end;
      Xml := Xml + '  </mime-type>' + #10;
    end;
    Xml := Xml + '</mime-info>' + #10;
    if Configuration.SupportsMultipleFiles then Arguments := Arguments + ' %F'
    else Arguments := Arguments + ' %f';
    IconName := Configuration.LinuxApplicationIcon;
    if IconName = '' then IconName := 'application-x-executable';
    if Pos('/', IconName) > 0 then begin
      IconPath := IconName;
      if IconPath[1] <> '/' then
        IconPath := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(
          Configuration.ResolveExecutable(False))) + IconPath);
      Extension := LowerCase(ExtractFileExt(IconPath));
      IconName := Configuration.ApplicationID;
      if Extension = '.svg' then
        Resources.AddFile('icons/hicolor/scalable/apps/' + IconName + Extension, FileAssReadFile(IconPath))
      else if Extension = '.png' then
        Resources.AddFile('icons/hicolor/128x128/apps/' + IconName + Extension, FileAssReadFile(IconPath))
      else begin
        Result.Message := 'Linux application icons must be SVG or 128-pixel PNG files.';
        Exit;
      end;
    end;
    Desktop := '[Desktop Entry]' + #10 + 'Type=Application' + #10 +
      'Name=' + FileAssDesktopValue(Configuration.ApplicationName) + #10 +
      'Comment=' + FileAssDesktopValue(Configuration.ApplicationDescription) + #10 +
      'Exec=' + Arguments + #10 + 'Terminal=false' + #10 +
      'NoDisplay=' + LowerCase(BoolToStr(not Configuration.ShowInApplicationMenu, True)) + #10 +
      'Categories=Utility;' + #10 + 'Icon=' + FileAssDesktopValue(IconName) + #10 +
      'MimeType=' + MimeList + #10 +
      'X-FileAss-Owner=' + Configuration.ApplicationID + #10;
    Resources.AddFile('applications/' + Configuration.ApplicationID + '.desktop', Desktop);
    Resources.AddFile('mime/packages/' + Configuration.ApplicationID + '.xml', Xml);
    Result := FileAssResult(farSuccess, 'Linux resources are ready.');
  finally Parsed.Free; Types.Free; end;
end;
function TFileAssLinuxBackend.OwnedPath(const Path, ApplicationID: UTF8String): Boolean;
begin
  Result := (Path = 'applications/' + ApplicationID + '.desktop') or
    (Path = 'mime/packages/' + ApplicationID + '.xml') or
    (Path = 'icons/hicolor/scalable/apps/' + ApplicationID + '.svg') or
    (Path = 'icons/hicolor/128x128/apps/' + ApplicationID + '.png') or
    ((Pos('icons/hicolor/scalable/mimetypes/' + ApplicationID + '-mime-', Path) = 1) or
     (Pos('icons/hicolor/128x128/mimetypes/' + ApplicationID + '-mime-', Path) = 1));
  Result := Result and (Pos('..', Path) = 0) and (Pos('\', Path) = 0) and
    (Pos(#9, Path) = 0) and (Pos(#10, Path) = 0);
end;
procedure TFileAssLinuxBackend.ReadManifest(const Root, ApplicationID: UTF8String; Manifest: TStrings);
var I, Separator: Integer; Line: UTF8String;
begin
  if not FileExists(Root + '/fileass/' + ApplicationID + '.manifest') then Exit;
  Manifest.Text := FileAssReadFile(Root + '/fileass/' + ApplicationID + '.manifest');
  if (Manifest.Count = 0) or (Manifest[0] <> 'FileAss:' + ApplicationID) then
    raise Exception.Create('The ownership manifest has an invalid identity.');
  Manifest.Delete(0);
  Manifest.NameValueSeparator := #9;
  for I := 0 to Manifest.Count - 1 do begin
    Line := Manifest[I];
    Separator := Pos(#9, Line);
    if (Separator = 0) or not OwnedPath(Copy(Line, 1, Separator - 1), ApplicationID) or
      (Length(Copy(Line, Separator + 1, MaxInt)) <> 32) then
      raise Exception.Create('The ownership manifest contains an invalid resource.');
  end;
end;
procedure TFileAssLinuxBackend.CheckOwnedFiles(const Root: UTF8String; Manifest: TStrings);
var I: Integer; Path: UTF8String;
begin
  for I := 0 to Manifest.Count - 1 do begin
    Path := Root + '/' + Manifest.Names[I];
    if FileExists(Path) and
      (MD5Print(MD5String(FileAssReadFile(Path))) <> Manifest.ValueFromIndex[I]) then
      raise Exception.Create('An installed resource was changed; it will be preserved: ' + Manifest.Names[I]);
  end;
end;
function TFileAssLinuxBackend.UpdateDatabases(const Root: UTF8String): TFileAssResult;
var Output: string; Problems, IconUtility: UTF8String;
  procedure Update(const Utility, Directory: UTF8String);
  var Executable: UTF8String;
  begin
    Executable := ExeSearch(Utility);
    if Executable = '' then begin
      Problems := Problems + ExtractFileName(Utility) + ' is unavailable. ';
      Exit;
    end;
    if not RunCommand(Executable, [Directory], Output) then
      Problems := Problems + ExtractFileName(Utility) + ' failed: ' + Trim(Output) + ' ';
  end;
begin
  Problems := '';
  Update('update-mime-database', Root + '/mime');
  Update('update-desktop-database', Root + '/applications');
  if DirectoryExists(Root + '/icons/hicolor') then begin
    IconUtility := ExeSearch('gtk-update-icon-cache');
    if (IconUtility <> '') and not RunCommand(IconUtility,
      ['--ignore-theme-index', '--force', Root + '/icons/hicolor'], Output) then
      Problems := Problems + 'Icon cache update failed: ' + Trim(Output) + ' ';
    if fpUtime(PChar(Root + '/icons/hicolor'), nil) <> 0 then
      Problems := Problems + 'Cannot refresh the icon-theme timestamp. ';
  end;
  if Problems = '' then Result := FileAssResult(farSuccess, 'Association resources and databases updated.')
  else Result := FileAssResult(farPartialSuccess, 'Resources changed. ' + Problems);
end;
function TFileAssLinuxBackend.RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
var
  Resources: TFileAssResources;
  Manifest, NewManifest: TStringList;
  Backups, Obsolete: TFileAssResources;
  Existing: TStringList;
  Root, Path, ManifestPath: UTF8String;
  I, Applied, Deleted: Integer;
  HadManifest: Boolean;
  OldManifest: RawByteString;
begin
  Result := CheckScope(Configuration);
  if not Result.Succeeded then Exit;
  Resources := TFileAssResources.Create;
  Backups := TFileAssResources.Create;
  Obsolete := TFileAssResources.Create;
  Existing := TStringList.Create;
  Manifest := TStringList.Create;
  NewManifest := TStringList.Create;
  Applied := 0;
  Deleted := 0;
  NewManifest.NameValueSeparator := #9;
  try
    try
      Result := BuildResources(Configuration, Resources);
      if not Result.Succeeded then Exit;
      Root := DataDirectory;
      ManifestPath := Root + '/fileass/' + Configuration.ApplicationID + '.manifest';
      HadManifest := FileExists(ManifestPath);
      OldManifest := '';
      if HadManifest then OldManifest := FileAssReadFile(ManifestPath);
      ReadManifest(Root, Configuration.ApplicationID, Manifest);
      CheckOwnedFiles(Root, Manifest);
      NewManifest.Add('FileAss:' + Configuration.ApplicationID);
      for I := 0 to Resources.Count - 1 do begin
        Path := Root + '/' + Resources[I].Path;
        if FileExists(Path) and (Manifest.IndexOfName(Resources[I].Path) < 0) then
          raise Exception.Create('An unowned resource already exists: ' + Resources[I].Path);
        if FileExists(Path) then begin
          Backups.AddFile(Path, FileAssReadFile(Path));
          Existing.Add(Path);
        end else Backups.AddFile(Path, '');
        Backups[I].Path := Path;
        NewManifest.Add(Resources[I].Path + #9 + MD5Print(MD5String(Resources[I].Contents)));
      end;
      for I := 0 to Manifest.Count - 1 do
        if NewManifest.IndexOfName(Manifest.Names[I]) < 0 then begin
          Path := Root + '/' + Manifest.Names[I];
          if FileExists(Path) then Obsolete.AddFile(Path, FileAssReadFile(Path));
        end;
      for I := 0 to Resources.Count - 1 do begin
        Path := Root + '/' + Resources[I].Path;
        if not ForceDirectories(ExtractFileDir(Path)) then
          raise Exception.Create('Cannot create the resource directory.');
        Inc(Applied);
        FileAssWriteFile(Path, Resources[I].Contents);
      end;
      for I := 0 to Obsolete.Count - 1 do begin
        Inc(Deleted);
        if not DeleteFile(Obsolete[I].Path) then
          raise Exception.Create('Cannot remove an obsolete owned resource: ' + Obsolete[I].Path);
      end;
      if not ForceDirectories(ExtractFileDir(ManifestPath)) then
        raise Exception.Create('Cannot create the ownership directory.');
      FileAssWriteFile(ManifestPath, NewManifest.Text);
      Result := UpdateDatabases(Root);
    except
      on E: Exception do begin
        Result := FileAssFailure(E);
        if (Applied > 0) or (Deleted > 0) then begin
          try
            for I := 0 to Applied - 1 do
              if Existing.IndexOf(Backups[I].Path) >= 0 then
                FileAssWriteFile(Backups[I].Path, Backups[I].Contents)
              else if not DeleteFile(Backups[I].Path) then
                raise Exception.Create('Cannot remove a newly created resource.');
            for I := 0 to Deleted - 1 do
              FileAssWriteFile(Obsolete[I].Path, Obsolete[I].Contents);
            if HadManifest then FileAssWriteFile(ManifestPath, OldManifest)
            else if FileExists(ManifestPath) then DeleteFile(ManifestPath);
          except
            on RollbackError: Exception do begin
              Result.Code := farPartialSuccess;
              Result.Message := Result.Message + ' Recovery failed: ' + RollbackError.Message;
            end;
          end;
        end;
      end;
    end;
  finally Existing.Free; Obsolete.Free; NewManifest.Free; Manifest.Free; Backups.Free; Resources.Free; end;
end;
function TFileAssLinuxBackend.UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
var Manifest: TStringList; Root, Path: UTF8String; I, Removed: Integer;
begin
  Result := CheckScope(Configuration);
  if not Result.Succeeded then Exit;
  Manifest := TStringList.Create;
  Removed := 0;
  try
    try
      Root := DataDirectory;
      ReadManifest(Root, Configuration.ApplicationID, Manifest);
      CheckOwnedFiles(Root, Manifest);
      for I := 0 to Manifest.Count - 1 do begin
        Path := Root + '/' + Manifest.Names[I];
        if FileExists(Path) and not DeleteFile(Path) then
          raise Exception.Create('Cannot remove an owned resource: ' + Manifest.Names[I]);
        Inc(Removed);
      end;
      Path := Root + '/fileass/' + Configuration.ApplicationID + '.manifest';
      if FileExists(Path) and not DeleteFile(Path) then
        raise Exception.Create('Cannot remove the ownership manifest.');
      if Manifest.Count = 0 then Result := FileAssResult(farSuccess, 'No owned registrations remain.')
      else Result := UpdateDatabases(Root);
    except
      on E: Exception do begin
        Result := FileAssFailure(E);
        if Removed > 0 then Result.Code := farPartialSuccess;
      end;
    end;
  finally Manifest.Free; end;
end;
function TFileAssLinuxBackend.GetStatus(Configuration: TFileAssConfiguration;
  out Diagnostic: TFileAssResult): TFileAssStatus;
var Resources: TFileAssResources; Root: UTF8String; I, Correct: Integer; Manifest: TStringList;
begin
  Result := fasVerificationFailed;
  Diagnostic := CheckScope(Configuration);
  if not Diagnostic.Succeeded then Exit(fasUnavailable);
  Resources := TFileAssResources.Create;
  Manifest := TStringList.Create;
  try
    try
      Diagnostic := BuildResources(Configuration, Resources);
      if not Diagnostic.Succeeded then Exit;
      Root := DataDirectory;
      ReadManifest(Root, Configuration.ApplicationID, Manifest);
      Correct := 0;
      for I := 0 to Resources.Count - 1 do
        if (Manifest.IndexOfName(Resources[I].Path) >= 0) and
          FileExists(Root + '/' + Resources[I].Path) and
          (FileAssReadFile(Root + '/' + Resources[I].Path) = Resources[I].Contents) then Inc(Correct);
      if Correct = 0 then Result := fasNotRegistered
      else if Correct = Resources.Count then Result := fasFullyRegistered
      else Result := fasPartiallyRegistered;
      Diagnostic := FileAssResult(farSuccess, IntToStr(Correct) + ' of ' +
        IntToStr(Resources.Count) + ' configured resources match. Default selection is separate.');
    except on E: Exception do Diagnostic := FileAssFailure(E); end;
  finally Manifest.Free; Resources.Free; end;
end;
function TFileAssLinuxBackend.GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
  const OutputDirectory: UTF8String): TFileAssResult;
var Resources: TFileAssResources; I: Integer; Root, Path, Manifest: UTF8String;
begin
  Resources := TFileAssResources.Create;
  try
    try
      Result := BuildResources(Configuration, Resources);
      if not Result.Succeeded then Exit;
      Root := ExcludeTrailingPathDelimiter(ExpandFileName(OutputDirectory));
      Manifest := '';
      for I := 0 to Resources.Count - 1 do begin
        Path := Root + '/' + Resources[I].Path;
        if FileExists(Path) then raise Exception.Create('Output already exists: ' + Resources[I].Path);
        Manifest := Manifest + Resources[I].Path + #10;
      end;
      if FileExists(Root + '/manifest.txt') then raise Exception.Create('Output manifest already exists.');
      for I := 0 to Resources.Count - 1 do begin
        Path := Root + '/' + Resources[I].Path;
        if not ForceDirectories(ExtractFileDir(Path)) then raise Exception.Create('Cannot create output directory.');
        FileAssWriteFile(Path, Resources[I].Contents);
      end;
      FileAssWriteFile(Root + '/manifest.txt', Manifest);
      Result := FileAssResult(farSuccess, 'Deployment resources generated without installation.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Resources.Free; end;
end;
function TFileAssLinuxBackend.Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult;
var Resources: TFileAssResources; I: Integer;
begin
  Text.Clear;
  Resources := TFileAssResources.Create;
  try
    try
      Result := BuildResources(Configuration, Resources);
      if not Result.Succeeded then Exit;
      for I := 0 to Resources.Count - 1 do begin
        Text.Add('[' + Resources[I].Path + ']');
        if ExtractFileExt(Resources[I].Path) = '.png' then Text.Add('(binary icon resource)')
        else Text.Add(Resources[I].Contents);
        Text.Add('');
      end;
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Resources.Free; end;
end;
function TFileAssLinuxBackend.OpenDefaultAppsSettings: TFileAssResult;
var Settings: TProcess; ProgramPath: string;
begin
  ProgramPath := '';
  if Pos('cinnamon', LowerCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'))) > 0 then
    ProgramPath := ExeSearch('cinnamon-settings');
  if ProgramPath = '' then Exit(FileAssResult(farUnsupported,
    'For these document types, right-click a sample in your file manager and choose Open With to set the default application.'));
  Settings := TProcess.Create(nil);
  try
    try
      Settings.Executable := ProgramPath;
      Settings.Parameters.Add('default');
      Settings.Execute;
      Result := FileAssResult(farSuccess, 'Opened default application settings. For custom document types, use the file manager Open With dialog.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Settings.Free; end;
end;
end.
