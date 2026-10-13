unit FAWindows;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, Windows, Registry, ShellApi, ShlObj,
  FATypes, FACollection, FACore, FAFormats;

type
  { Windows: registry values under HKEY_CURRENT_USER, or HKEY_LOCAL_MACHINE
    for all users - a ProgID per extension named ApplicationID + extension,
    an OpenWithProgids entry pointing at it, and the application's
    capabilities under Software\FileAss.  Every ProgID carries a
    FileAssOwner value, and a ProgID without this application's is left alone. }
  TFileAssWindowsBackend = class(TFileAssBackend)
  private
    function RootKey(App: TFileAssManager): HKEY;
    procedure BuildEntries(App: TFileAssManager; Entries: TFileAssResources);
    procedure RemoveOwned(Reg: TRegistry; const ID: utf8string);
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
  ClassesKey = 'Software\Classes\';
  OwnerMark = 'FileAssOwner';

function RegDeleteTreeW(Key: HKEY; SubKey: pwidechar): longint; stdcall; external 'advapi32.dll';

{ An entry is a registry value: its Path is the key, a tab, and the name. }
procedure SplitEntry(const Path: utf8string; out Key, Name: utf8string);
var
  Tab: integer;
begin
  Tab := Pos(#9, Path);
  Key := Copy(Path, 1, Tab - 1);
  Name := Copy(Path, Tab + 1, MaxInt);
end;

function ReadValue(Reg: TRegistry; const Key, Name: utf8string; out Value: utf8string): boolean;
begin
  Value := '';
  Result := Reg.OpenKeyReadOnly(UTF8Decode(Key));
  if not Result then Exit;
  try
    Result := Reg.ValueExists(UTF8Decode(Name));
    if Result then Value := UTF8Encode(Reg.ReadString(UTF8Decode(Name)));
  finally
    Reg.CloseKey;
  end;
end;

procedure DeleteTree(Reg: TRegistry; const Key: utf8string);
var
  Status: longint;
begin
  Status := RegDeleteTreeW(Reg.RootKey, pwidechar(UTF8Decode(Key)));
  if (Status <> ERROR_SUCCESS) and (Status <> ERROR_FILE_NOT_FOUND) then RaiseLastOSError(Status);
end;

{ Deletes a key that has nothing left in it; True if it went. }
function PruneKey(Reg: TRegistry; const Key: utf8string): boolean;
var
  Names: TStringList;
begin
  Result := False;
  Names := TStringList.Create;
  try
    if not Reg.OpenKeyReadOnly(UTF8Decode(Key)) then Exit;
    Reg.GetValueNames(Names);
    Result := Names.Count = 0;
    Reg.GetKeyNames(Names);
    Result := Result and (Names.Count = 0);
    Reg.CloseKey;
    Result := Result and Reg.DeleteKey(UTF8Decode(Key));
  finally
    Names.Free;
  end;
end;

{ Removes a value, then its key and the one above if that empties them. }
procedure DeleteValue(Reg: TRegistry; const Key, Name: utf8string);
begin
  if not Reg.OpenKey(UTF8Decode(Key), False) then Exit;
  Reg.DeleteValue(UTF8Decode(Name));
  Reg.CloseKey;
  if PruneKey(Reg, Key) then PruneKey(Reg, ExtractFileDir(Key));
end;

function TFileAssWindowsBackend.RootKey(App: TFileAssManager): HKEY;
begin
  if App.RegistrationScope = fasAllUsers then Result := HKEY_LOCAL_MACHINE
  else
    Result := HKEY_CURRENT_USER;
end;

{ The registry values to write. }
procedure TFileAssWindowsBackend.BuildEntries(App: TFileAssManager; Entries: TFileAssResources);
var
  I, J: integer;
  Item: TFileAssTypeItem;
  ProgID, Key, Command, Capability, IconPath: utf8string;
  Arguments: TStringList;

  procedure Add(const Key, Name, Value: utf8string);
  begin
    Entries.AddFile(Key + #9 + Name, Value);
  end;

begin
  Capability := 'Software\FileAss\' + App.ApplicationID + '\Capabilities';
  Add(Capability, OwnerMark, App.ApplicationID);
  Add(Capability, 'ApplicationName', App.ApplicationName);
  Add(Capability, 'ApplicationDescription', App.ApplicationDescription);
  Add('Software\RegisteredApplications', App.ApplicationID, Capability);
  Arguments := TStringList.Create;
  try
    for I := 0 to App.FileTypes.Count - 1 do
    begin
      Item := App.FileTypes[I];
      if not Item.Enabled then Continue;
      if not FileAssParseArguments(Item.OpenArguments, Arguments) then
        raise EFileAssConfiguration.Create('OpenArguments has an unmatched double quote.');
      Command := FileAssWindowsArgument(App.Executable);
      for J := 0 to Arguments.Count - 1 do Command := Command + ' ' + FileAssWindowsArgument(Arguments[J]);
      Command := Command + ' "%1"';
      ProgID := App.ApplicationID + Item.Extension;
      Key := ClassesKey + ProgID;
      Add(Key, OwnerMark, App.ApplicationID);
      Add(Key, '', Item.Description);
      if Item.WindowsIcon <> '' then
      begin
        IconPath := Item.WindowsIcon;
        // a plain file name becomes "full path",0; a resource reference is taken as written
        if (Pos(',', IconPath) = 0) and (Pos('"', IconPath) = 0) then
        begin
          if (ExtractFileDrive(IconPath) = '') and (Copy(IconPath, 1, 2) <> '\\') then
            IconPath := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(App.Executable)) + IconPath);
          IconPath := FileAssWindowsArgument(IconPath) + ',0';
        end;
        Add(Key + '\DefaultIcon', '', IconPath);
      end;
      Add(Key + '\shell\open\command', '', Command);
      if App.SupportsMultipleFiles then Add(Key + '\shell\open', 'MultiSelectModel', 'Player');
      Add(ClassesKey + Item.Extension + '\OpenWithProgids', ProgID, '');
      Add(Capability + '\FileAssociations', Item.Extension, ProgID);
    end;
  finally
    Arguments.Free;
  end;
end;

{ Takes out everything this application has registered, whatever its file
  types are now: its ProgIDs are found by name and checked for its mark. }
procedure TFileAssWindowsBackend.RemoveOwned(Reg: TRegistry; const ID: utf8string);
var
  Keys: TStringList;
  I: integer;
  ProgID, Extension, Mark: utf8string;
begin
  Keys := TStringList.Create;
  try
    if Reg.OpenKeyReadOnly(UTF8Decode(ExcludeTrailingPathDelimiter(ClassesKey))) then
    begin
      Reg.GetKeyNames(Keys);
      Reg.CloseKey;
    end;
    for I := 0 to Keys.Count - 1 do
    begin
      ProgID := utf8string(Keys[I]);
      if not SameText(Copy(ProgID, 1, Length(ID) + 1), ID + '.') then Continue;
      if not ReadValue(Reg, ClassesKey + ProgID, OwnerMark, Mark) or (Mark <> ID) then Continue;
      Extension := Copy(ProgID, Length(ID) + 1, MaxInt);
      DeleteValue(Reg, ClassesKey + Extension + '\OpenWithProgids', ProgID);
      DeleteTree(Reg, ClassesKey + ProgID);
    end;
    DeleteTree(Reg, 'Software\FileAss\' + ID);
    PruneKey(Reg, 'Software\FileAss');
    DeleteValue(Reg, 'Software\RegisteredApplications', ID);
  finally
    Keys.Free;
  end;
end;

function TFileAssWindowsBackend.RegisterTypes(App: TFileAssManager): TFileAssResult;
var
  Reg: TRegistry;
  Entries: TFileAssResources;
  I: integer;
  Key, Name, Mark: utf8string;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  Entries := TFileAssResources.Create;
  try
    try
      Reg.RootKey := RootKey(App);
      BuildEntries(App, Entries);
      // a ProgID of this name that something else made is not ours to take over
      for I := 0 to Entries.Count - 1 do
      begin
        SplitEntry(Entries[I].Path, Key, Name);
        if (Name = OwnerMark) and Reg.KeyExists(UTF8Decode(Key)) and not (ReadValue(Reg, Key, OwnerMark, Mark) and (Mark = App.ApplicationID)) then
          raise Exception.Create('This registry key belongs to something else: ' + Key);
      end;
      // start clean, so a file type dropped since last time leaves nothing behind
      RemoveOwned(Reg, App.ApplicationID);
      for I := 0 to Entries.Count - 1 do
      begin
        SplitEntry(Entries[I].Path, Key, Name);
        if not Reg.OpenKey(UTF8Decode(Key), True) then RaiseLastOSError(Reg.LastError);
        try
          Reg.WriteString(UTF8Decode(Name), UTF8Decode(Entries[I].Contents));
        finally
          Reg.CloseKey;
        end;
      end;
      SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
      Result := FileAssResult(farSuccess, 'File types registered. Which program is the default is still the user''s choice.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Entries.Free;
    Reg.Free;
  end;
end;

function TFileAssWindowsBackend.UnregisterTypes(App: TFileAssManager): TFileAssResult;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey := RootKey(App);
      RemoveOwned(Reg, App.ApplicationID);
      SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
      Result := FileAssResult(farSuccess, 'File types removed.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Reg.Free;
  end;
end;

function TFileAssWindowsBackend.GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus;
var
  Reg: TRegistry;
  Entries: TFileAssResources;
  I, Correct: integer;
  Key, Name, Value: utf8string;
begin
  Result := fasVerificationFailed;
  Reg := TRegistry.Create(KEY_READ);
  Entries := TFileAssResources.Create;
  try
    try
      Reg.RootKey := RootKey(App);
      BuildEntries(App, Entries);
      Correct := 0;
      for I := 0 to Entries.Count - 1 do
      begin
        SplitEntry(Entries[I].Path, Key, Name);
        if ReadValue(Reg, Key, Name, Value) and (Value = Entries[I].Contents) then Inc(Correct);
      end;
      if Correct = 0 then Result := fasNotRegistered
      else if Correct = Entries.Count then Result := fasFullyRegistered
      else
        Result := fasPartiallyRegistered;
      Diagnostic := FileAssResult(farSuccess, Format('%d of %d registry values are in place. Which program is the default is the user''s choice.',
        [Correct, Entries.Count]));
    except
      on E: Exception do Diagnostic := FileAssFailure(E);
    end;
  finally
    Entries.Free;
    Reg.Free;
  end;
end;

{ A .reg file an installer can import, in the UTF-16 regedit expects. }
function TFileAssWindowsBackend.GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult;
var
  Entries: TFileAssResources;
  I: integer;
  Key, Name, Root, Text, Folder, Path: utf8string;
  Data: unicodestring;

  function Escape(const Value: utf8string): utf8string;
  begin
    Result := StringReplace(Value, '\', '\\', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  end;

begin
  Entries := TFileAssResources.Create;
  try
    try
      BuildEntries(App, Entries);
      if App.RegistrationScope = fasAllUsers then Root := 'HKEY_LOCAL_MACHINE'
      else
        Root := 'HKEY_CURRENT_USER';
      Text := 'Windows Registry Editor Version 5.00' + #13#10;
      for I := 0 to Entries.Count - 1 do
      begin
        SplitEntry(Entries[I].Path, Key, Name);
        Text := Text + #13#10 + '[' + Root + '\' + Key + ']' + #13#10;
        if Name = '' then Text := Text + '@'
        else
          Text := Text + '"' + Escape(Name) + '"';
        Text := Text + '="' + Escape(Entries[I].Contents) + '"' + #13#10;
      end;
      Folder := IncludeTrailingPathDelimiter(OutputDirectory);
      Path := Folder + App.ApplicationID + '.reg';
      if FileExists(UTF8Decode(Path)) or FileExists(UTF8Decode(Folder + 'manifest.txt')) then
        raise Exception.Create('The output is already there; nothing was overwritten.');
      if not ForceDirectories(UTF8Decode(OutputDirectory)) then raise Exception.Create('Cannot create ' + OutputDirectory);
      Data := widechar($FEFF) + UTF8Decode(Text);
      SetLength(Text, Length(Data) * SizeOf(widechar));
      Move(Data[1], Text[1], Length(Text));
      FileAssWriteFile(Path, Text);
      FileAssWriteFile(Folder + 'manifest.txt', ExtractFileName(Path) + #10);
      Result := FileAssResult(farSuccess, 'A .reg file was written for an installer. Nothing was registered here.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Entries.Free;
  end;
end;

function TFileAssWindowsBackend.Preview(App: TFileAssManager; Text: TStrings): TFileAssResult;
var
  Entries: TFileAssResources;
  I: integer;
begin
  Text.Clear;
  Entries := TFileAssResources.Create;
  try
    try
      BuildEntries(App, Entries);
      for I := 0 to Entries.Count - 1 do Text.Add(Entries[I].Path + ' = ' + Entries[I].Contents);
      Result := FileAssResult(farSuccess, 'This is what would be written to the registry.');
    except
      on E: Exception do Result := FileAssFailure(E);
    end;
  finally
    Entries.Free;
  end;
end;

function TFileAssWindowsBackend.OpenDefaultAppsSettings: TFileAssResult;
var
  Address: unicodestring;
  Status: PtrInt;
begin
  Address := 'ms-settings:defaultapps';
  Status := PtrInt(ShellExecuteW(0, nil, pwidechar(Address), nil, nil, SW_SHOWNORMAL));
  if Status > 32 then Result := FileAssResult(farSuccess, 'Opened the default apps settings.')
  else
  begin
    Result := FileAssResult(farOperationFailed, 'Cannot open the default apps settings.');
    Result.NativeError := Status;
  end;
end;

end.
