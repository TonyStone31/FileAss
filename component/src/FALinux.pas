unit FALinux;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, Process, BaseUnix, FATypes, FACollection, FACore, FAFormats;

type
  { Linux: a .desktop entry, a shared-mime-info package and icons, under the
    user's data directory.  Every file is named after the ApplicationID, so
    what belongs to an application is found by its name. }
  TFileAssLinuxBackend = class(TFileAssBackend)
  private
    function DataDirectory: utf8string;
    procedure BuildResources(App: TFileAssManager; Resources: TFileAssResources);
    function RemoveInstalled(const Root, ID: utf8string; Keep: TFileAssResources): integer;
    function UpdateDatabases(const Root: utf8string): TFileAssResult;
  public
    function RegisterTypes(App: TFileAssManager): TFileAssResult; override;
    function UnregisterTypes(App: TFileAssManager): TFileAssResult; override;
    function GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus; override;
    function GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult; override;
    function OpenDefaultAppsSettings: TFileAssResult; override;
    function Preview(App: TFileAssManager; Text: TStrings): TFileAssResult; override;
  end;

implementation

const
  AllUsersHint = 'For all users, export the files and install them with a system package.';

function TFileAssLinuxBackend.DataDirectory: utf8string;
begin
  Result := GetEnvironmentVariable('XDG_DATA_HOME');
  if (Result = '') or (Result[1] <> '/') then
  begin
    Result := GetEnvironmentVariable('HOME');
    if (Result = '') or (Result[1] <> '/') then
      raise Exception.Create('Neither XDG_DATA_HOME nor HOME names a directory.');
    Result := IncludeTrailingPathDelimiter(Result) + '.local/share';
  end;
  Result := ExcludeTrailingPathDelimiter(Result);
end;

{ The files to install, as paths below the data directory. }
procedure TFileAssLinuxBackend.BuildResources(App: TFileAssManager; Resources: TFileAssResources);
var
  Desktop, Xml, MimeList, Exec, IconName, Arguments: utf8string;
  Item: TFileAssTypeItem;
  I, J: integer;
  Types, Parsed: TStringList;

  { An icon given as a file is installed into the hicolor theme under Name;
    one given as a theme name is used as it is. }
  function Icon(const Source, Kind, Name: utf8string): utf8string;
  var
    Path, Ext: utf8string;
  begin
    if Pos('/', Source) = 0 then Exit(Source);
    Path := Source;
    if Path[1] <> '/' then Path := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(App.Executable)) + Path);
    Ext := LowerCase(ExtractFileExt(Path));
    if Ext = '.svg' then Resources.AddFile('icons/hicolor/scalable/' + Kind + '/' + Name + Ext, FileAssReadFile(Path))
    else if Ext = '.png' then Resources.AddFile('icons/hicolor/128x128/' + Kind + '/' + Name + Ext, FileAssReadFile(Path))
    else
      raise EFileAssConfiguration.Create('A Linux icon file must be an SVG or a 128-pixel PNG: ' + Source);
    Result := Name;
  end;

begin
  Types := TStringList.Create;
  Parsed := TStringList.Create;
  try
    // one .desktop entry launches every type, so there is one set of arguments
    Arguments := '';
    for I := 0 to App.FileTypes.Count - 1 do
    begin
      Item := App.FileTypes[I];
      if not Item.Enabled then Continue;
      if Types.Count = 0 then Arguments := Item.OpenArguments
      else if Item.OpenArguments <> Arguments then
        raise EFileAssConfiguration.Create('On Linux every file type must have the same OpenArguments.');
      if Types.IndexOf(Item.MimeType) < 0 then Types.Add(Item.MimeType);
    end;
    if not FileAssParseArguments(Arguments, Parsed) then
      raise EFileAssConfiguration.Create('OpenArguments has an unmatched double quote.');

    MimeList := '';
    Xml := '<?xml version="1.0" encoding="UTF-8"?>' + #10 + '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">' + #10;
    for I := 0 to Types.Count - 1 do
    begin
      MimeList := MimeList + Types[I] + ';';
      IconName := '';
      Xml := Xml + '  <mime-type type="' + FileAssXml(Types[I]) + '">' + #10;
      for J := 0 to App.FileTypes.Count - 1 do
      begin
        Item := App.FileTypes[J];
        if not Item.Enabled or (Item.MimeType <> Types[I]) then Continue;
        if IconName = '' then
        begin
          IconName := Item.LinuxIcon;
          Xml := Xml + '    <comment>' + FileAssXml(Item.Description) + '</comment>' + #10;
        end
        else if (Item.LinuxIcon <> '') and (Item.LinuxIcon <> IconName) then
          raise EFileAssConfiguration.Create('Extensions sharing a MIME type must share a Linux icon.');
        Xml := Xml + '    <glob pattern="*' + FileAssXml(Item.Extension) + '"/>' + #10;
      end;
      if IconName <> '' then
      begin
        IconName := Icon(IconName, 'mimetypes', App.ApplicationID + '-mime-' + IntToStr(I + 1));
        // generic-icon too, or a theme's plain page outranks the icon just installed
        Xml := Xml + '    <icon name="' + FileAssXml(IconName) + '"/>' + #10 + '    <generic-icon name="' + FileAssXml(IconName) + '"/>' + #10;
      end;
      Xml := Xml + '  </mime-type>' + #10;
    end;
    Xml := Xml + '</mime-info>' + #10;

    Exec := FileAssDesktopArgument(App.Executable);
    for I := 0 to Parsed.Count - 1 do Exec := Exec + ' ' + FileAssDesktopArgument(Parsed[I]);
    if App.SupportsMultipleFiles then Exec := Exec + ' %F'
    else
      Exec := Exec + ' %f';
    if App.LinuxApplicationIcon = '' then IconName := 'application-x-executable'
    else
      IconName := Icon(App.LinuxApplicationIcon, 'apps', App.ApplicationID);
    Desktop := '[Desktop Entry]' + #10 + 'Type=Application' + #10 + 'Name=' + FileAssDesktopValue(App.ApplicationName) + #10 + 'Comment=' +
      FileAssDesktopValue(App.ApplicationDescription) + #10 + 'Exec=' + Exec + #10 + 'Terminal=false' + #10 + 'NoDisplay=' +
      LowerCase(BoolToStr(not App.ShowInApplicationMenu, True)) + #10 + 'Categories=Utility;' + #10 + 'Icon=' + FileAssDesktopValue(IconName) + #10 + 'MimeType=' + MimeList + #10;
    Resources.AddFile('applications/' + App.ApplicationID + '.desktop', Desktop);
    Resources.AddFile('mime/packages/' + App.ApplicationID + '.xml', Xml);
  finally
    Parsed.Free;
    Types.Free;
  end;
end;

{ Deletes this application's installed files, except those in Keep, and
  says how many went. }
function TFileAssLinuxBackend.RemoveInstalled(const Root, ID: utf8string; Keep: TFileAssResources): integer;
const
  // the last is a list earlier versions kept of what they had installed
  single: array[0..4] of string = ('applications/%s.desktop', 'mime/packages/%s.xml', 'icons/hicolor/scalable/apps/%s.svg',
    'icons/hicolor/128x128/apps/%s.png', 'fileass/%s.manifest');
  TypeIcons: array[0..1] of string = ('icons/hicolor/scalable/mimetypes/', 'icons/hicolor/128x128/mimetypes/');
var
  Found: TStringList;
  Info: TSearchRec;
  I: integer;
begin
  Result := 0;
  Found := TStringList.Create;
  try
    for I := Low(single) to High(single) do Found.Add(Format(single[I], [ID]));
    for I := Low(TypeIcons) to High(TypeIcons) do
    begin
      if FindFirst(Root + '/' + TypeIcons[I] + ID + '-mime-*', faAnyFile, Info) = 0 then
        repeat
          Found.Add(TypeIcons[I] + Info.Name);
        until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    for I := 0 to Found.Count - 1 do
    begin
      if Assigned(Keep) and (Keep.IndexOfPath(Found[I]) >= 0) then Continue;
      if not FileExists(Root + '/' + Found[I]) then Continue;
      if not DeleteFile(Root + '/' + Found[I]) then raise Exception.Create('Cannot remove ' + Found[I]);
      Inc(Result);
    end;
  finally
    Found.Free;
  end;
end;

{ The desktop reads its caches, not the files, so they are rebuilt. }
function TFileAssLinuxBackend.UpdateDatabases(const Root: utf8string): TFileAssResult;
var
  Output: string;
  Problems, IconUtility: utf8string;

  procedure Update(const Utility, Directory: utf8string);
  var
    Executable: utf8string;
  begin
    Executable := ExeSearch(Utility);
    if Executable = '' then Problems := Problems + Utility + ' is not installed. '
    else if not RunCommand(Executable, [Directory], Output) then
      Problems := Problems + Utility + ' failed: ' + Trim(Output) + ' ';
  end;

begin
  Problems := '';
  Update('update-mime-database', Root + '/mime');
  Update('update-desktop-database', Root + '/applications');
  if DirectoryExists(Root + '/icons/hicolor') then
  begin
    IconUtility := ExeSearch('gtk-update-icon-cache');
    if (IconUtility <> '') and not RunCommand(IconUtility, ['--ignore-theme-index', '--force', Root + '/icons/hicolor'], Output) then
      Problems := Problems + 'gtk-update-icon-cache failed: ' + Trim(Output) + ' ';
    // a newer directory time is what makes running programs look again
    fpUtime(PChar(Root + '/icons/hicolor'), nil);
  end;
  if Problems = '' then Result := FileAssResult(farSuccess, 'File types registered.')
  else
    Result := FileAssResult(farPartialSuccess, 'The files are in place, but: ' + Problems);
end;

function TFileAssLinuxBackend.RegisterTypes(App: TFileAssManager): TFileAssResult;
var
  Resources: TFileAssResources;
  Root, Path: utf8string;
  I: integer;
begin
  if App.RegistrationScope = fasAllUsers then Exit(FileAssResult(farRequiresDeployment, AllUsersHint));
  Resources := TFileAssResources.Create;
  try
    try
      BuildResources(App, Resources);
      Root := DataDirectory;
      for I := 0 to Resources.Count - 1 do
      begin
        Path := Root + '/' + Resources[I].Path;
        if not ForceDirectories(ExtractFileDir(Path)) then raise Exception.Create('Cannot create ' + ExtractFileDir(Path));
        FileAssWriteFile(Path, Resources[I].Contents);
      end;
      // whatever an earlier registration installed that this one does not
      RemoveInstalled(Root, App.ApplicationID, Resources);
      Result := UpdateDatabases(Root);
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Resources.Free;
  end;
end;

function TFileAssLinuxBackend.UnregisterTypes(App: TFileAssManager): TFileAssResult;
var
  Root: utf8string;
begin
  if App.RegistrationScope = fasAllUsers then Exit(FileAssResult(farRequiresDeployment, AllUsersHint));
  try
    Root := DataDirectory;
    if RemoveInstalled(Root, App.ApplicationID, nil) = 0 then Exit(FileAssResult(farSuccess, 'Nothing was registered.'));
    Result := UpdateDatabases(Root);
    if Result.Succeeded then Result.Message := 'File types removed.';
  except
    on E: Exception do Result := FileAssFailure(E);
  end;
end;

function TFileAssLinuxBackend.GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus;
var
  Resources: TFileAssResources;
  Root: utf8string;
  I, Correct: integer;
begin
  Result := fasVerificationFailed;
  if App.RegistrationScope = fasAllUsers then
  begin
    Diagnostic := FileAssResult(farRequiresDeployment, AllUsersHint);
    Exit(fasUnavailable);
  end;
  Resources := TFileAssResources.Create;
  try
    try
      BuildResources(App, Resources);
      Root := DataDirectory;
      Correct := 0;
      for I := 0 to Resources.Count - 1 do
        if FileExists(Root + '/' + Resources[I].Path) and (FileAssReadFile(Root + '/' + Resources[I].Path) = Resources[I].Contents) then
          Inc(Correct);
      if Correct = 0 then Result := fasNotRegistered
      else if Correct = Resources.Count then Result := fasFullyRegistered
      else
        Result := fasPartiallyRegistered;
      Diagnostic := FileAssResult(farSuccess, Format('%d of %d files are installed and current. Which program is the default is the user''s choice.',
        [Correct, Resources.Count]));
    except
      on E: Exception do Diagnostic := FileAssFailure(E);
    end;
  finally
    Resources.Free;
  end;
end;

function TFileAssLinuxBackend.GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult;
var
  Resources: TFileAssResources;
  I: integer;
  Root, Path, List: utf8string;
begin
  Resources := TFileAssResources.Create;
  try
    try
      BuildResources(App, Resources);
      Root := ExcludeTrailingPathDelimiter(ExpandFileName(OutputDirectory));
      // nothing already there is overwritten
      List := '';
      for I := 0 to Resources.Count - 1 do
      begin
        if FileExists(Root + '/' + Resources[I].Path) then raise Exception.Create('Already there: ' + Resources[I].Path);
        List := List + Resources[I].Path + #10;
      end;
      if FileExists(Root + '/manifest.txt') then raise Exception.Create('Already there: manifest.txt');
      for I := 0 to Resources.Count - 1 do
      begin
        Path := Root + '/' + Resources[I].Path;
        if not ForceDirectories(ExtractFileDir(Path)) then raise Exception.Create('Cannot create ' + ExtractFileDir(Path));
        FileAssWriteFile(Path, Resources[I].Contents);
      end;
      FileAssWriteFile(Root + '/manifest.txt', List);
      Result := FileAssResult(farSuccess, 'Files written for an installer. Nothing was registered here.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Resources.Free;
  end;
end;

function TFileAssLinuxBackend.Preview(App: TFileAssManager; Text: TStrings): TFileAssResult;
var
  Resources: TFileAssResources;
  I: integer;
begin
  Text.Clear;
  Resources := TFileAssResources.Create;
  try
    try
      BuildResources(App, Resources);
      for I := 0 to Resources.Count - 1 do
      begin
        Text.Add('[' + Resources[I].Path + ']');
        if ExtractFileExt(Resources[I].Path) = '.png' then Text.Add('(a PNG icon)')
        else
          Text.Add(Resources[I].Contents);
        Text.Add('');
      end;
      Result := FileAssResult(farSuccess, 'This is what would be installed.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Resources.Free;
  end;
end;

{ Only Cinnamon has a settings page worth opening for this; elsewhere the
  file manager's Open With is the place. }
function TFileAssLinuxBackend.OpenDefaultAppsSettings: TFileAssResult;
var
  Settings: TProcess;
  ProgramPath: string;
begin
  ProgramPath := '';
  if Pos('cinnamon', LowerCase(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'))) > 0 then ProgramPath := ExeSearch('cinnamon-settings');
  if ProgramPath = '' then
    Exit(FileAssResult(farUnsupported, 'Right-click one of the files in your file manager and choose Open With to set the default program.'));
  Settings := TProcess.Create(nil);
  try
    try
      Settings.Executable := ProgramPath;
      Settings.Parameters.Add('default');
      Settings.Execute;
      Result := FileAssResult(farSuccess, 'Opened the default applications settings.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Settings.Free;
  end;
end;

end.
