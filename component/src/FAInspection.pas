unit FAInspection;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, FATypes;
function FileAssEnumerateTypes(Entries: TStrings): TFileAssResult;
function FileAssDefaultHandler(const Extension, MimeType: UTF8String;
  out Handler: UTF8String): TFileAssResult;
implementation
uses FAFormats, FAValidation
  {$if defined(windows)}, Windows, Registry{$elseif defined(linux)}, Process{$endif};
{$ifdef linux}
procedure LinuxDataDirectories(Directories: TStrings);
var Home, Value: UTF8String; Split: TStringList; I: Integer;
begin
  Home := GetEnvironmentVariable('XDG_DATA_HOME');
  if (Home = '') or (Home[1] <> '/') then
    Home := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.local/share';
  Directories.Add(Home);
  Value := GetEnvironmentVariable('XDG_DATA_DIRS');
  if Value = '' then Value := '/usr/local/share:/usr/share';
  Split := TStringList.Create;
  try
    Split.StrictDelimiter := True;
    Split.Delimiter := ':';
    Split.DelimitedText := Value;
    for I := 0 to Split.Count - 1 do
      if (Split[I] <> '') and (Split[I][1] = '/') and
        (Directories.IndexOf(Split[I]) < 0) then Directories.Add(Split[I]);
  finally Split.Free; end;
end;
{$endif}
function FileAssEnumerateTypes(Entries: TStrings): TFileAssResult;
{$ifdef linux}
var Directories, Lines: TStringList; I, J, First, Second, Flags: Integer; Line, Path, Mime, Glob: UTF8String;
{$endif}
{$ifdef windows}
var Reg: TRegistry; Names: TStringList; I: Integer; Value: UTF8String;
{$endif}
begin
  Entries.Clear;
  {$ifdef linux}
  Directories := TStringList.Create;
  Lines := TStringList.Create;
  try
    try
      LinuxDataDirectories(Directories);
      for I := 0 to Directories.Count - 1 do begin
        Path := IncludeTrailingPathDelimiter(Directories[I]) + 'mime/globs2';
        if not FileExists(Path) then Continue;
        Lines.Text := FileAssReadFile(Path);
        for J := 0 to Lines.Count - 1 do begin
          Line := Lines[J];
          if (Line = '') or (Line[1] = '#') then Continue;
          First := Pos(':', Line);
          Delete(Line, 1, First);
          Second := Pos(':', Line);
          if (First = 0) or (Second = 0) then Continue;
          Mime := Copy(Line, 1, Second - 1);
          Glob := Copy(Line, Second + 1, MaxInt);
          Flags := Pos(':', Glob);
          if Flags > 0 then SetLength(Glob, Flags - 1);
          Entries.Add(Glob + #9 + Mime + #9 + Directories[I]);
        end;
      end;
      Result := FileAssResult(farSuccess, IntToStr(Entries.Count) + ' MIME filename rules found.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Lines.Free; Directories.Free; end;
  {$elseif defined(windows)}
  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    try
      Reg.RootKey := HKEY_CLASSES_ROOT;
      if not Reg.OpenKeyReadOnly('') then RaiseLastOSError(Reg.LastError);
      Reg.GetKeyNames(Names);
      Reg.CloseKey;
      for I := 0 to Names.Count - 1 do begin
        if (Names[I] = '') or (Names[I][1] <> '.') then Continue;
        Value := '';
        if Reg.OpenKeyReadOnly(UTF8Decode(Names[I])) then begin
          try
            if Reg.ValueExists('') then Value := UTF8Encode(Reg.ReadString(UnicodeString('')));
          finally Reg.CloseKey; end;
        end;
        Entries.Add(Names[I] + #9 + Value + #9 + 'HKEY_CLASSES_ROOT');
      end;
      Result := FileAssResult(farSuccess, IntToStr(Entries.Count) + ' registered extensions found.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Names.Free; Reg.Free; end;
  {$else}
  Result := FileAssResult(farUnsupported, 'System enumeration is unavailable on this platform.');
  {$endif}
end;
function FileAssDefaultHandler(const Extension, MimeType: UTF8String;
  out Handler: UTF8String): TFileAssResult;
{$ifdef linux}
var Output: string;
{$endif}
{$ifdef windows}
var Reg: TRegistry;
{$endif}
begin
  Handler := '';
  {$ifdef linux}
  if (MimeType = '') or (MimeType[1] = '-') or (Pos('/', MimeType) < 2) then
    Exit(FileAssResult(farInvalidConfiguration, 'A valid MIME type is required.'));
  try
    if not FileExists('/usr/bin/xdg-mime') then
      Exit(FileAssResult(farUnsupported, 'xdg-mime is unavailable.'));
    if not RunCommand('/usr/bin/xdg-mime', ['query', 'default', MimeType], Output) then
      Exit(FileAssResult(farOperationFailed, 'Cannot query the default MIME handler.'));
    Handler := Trim(Output);
    if Handler = '' then Result := FileAssResult(farNotFound, 'No default handler was reported.')
    else Result := FileAssResult(farSuccess, 'Default handler queried.');
  except on E: Exception do Result := FileAssFailure(E); end;
  {$elseif defined(windows)}
  if (Extension = '') or (Extension[1] <> '.') or (Pos('\', Extension) > 0) then
    Exit(FileAssResult(farInvalidConfiguration, 'A valid extension is required.'));
  Reg := TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(UTF8Decode('Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\' + Extension + '\UserChoice')) then begin
        try
          if Reg.ValueExists('ProgId') then Handler := UTF8Encode(Reg.ReadString(UnicodeString('ProgId')));
        finally Reg.CloseKey; end;
      end;
      if Handler = '' then begin
        Reg.RootKey := HKEY_CLASSES_ROOT;
        if Reg.OpenKeyReadOnly(UTF8Decode(Extension)) then begin
          try
            if Reg.ValueExists('') then Handler := UTF8Encode(Reg.ReadString(UnicodeString('')));
          finally Reg.CloseKey; end;
        end;
      end;
      if Handler = '' then Result := FileAssResult(farNotFound, 'No default handler was reported.')
      else Result := FileAssResult(farSuccess, 'Default handler queried.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Reg.Free; end;
  {$else}
  Result := FileAssResult(farUnsupported, 'Default handler inspection is unavailable.');
  {$endif}
end;
end.
