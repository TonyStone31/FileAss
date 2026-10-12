unit FAWindows;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Windows, Registry, ShellApi, ShlObj,
  FATypes, FACollection, FACore, FAFormats;
type
  TFileAssWindowsBackend = class(TFileAssBackend)
  private
    function RootKey(Configuration: TFileAssConfiguration): HKEY;
    function ProgID(Configuration: TFileAssConfiguration; Item: TFileAssTypeItem): UTF8String;
    procedure AddInventory(Configuration: TFileAssConfiguration; Entries: TFileAssResources);
    procedure BuildEntries(Configuration: TFileAssConfiguration; Entries: TFileAssResources);
    function ReadValue(Reg: TRegistry; const Key, Name: UTF8String; out Value: UTF8String): Boolean;
    procedure Preflight(Reg: TRegistry; Configuration: TFileAssConfiguration;
      Entries: TFileAssResources);
    function ReadInstalled(Reg: TRegistry; Configuration: TFileAssConfiguration;
      Entries: TFileAssResources): Boolean;
    procedure DeleteEntry(Reg: TRegistry; Configuration: TFileAssConfiguration;
      const Path: UTF8String);
    procedure PruneKey(Reg: TRegistry; const Key: UTF8String);
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
function TFileAssWindowsBackend.RootKey(Configuration: TFileAssConfiguration): HKEY;
begin
  if Configuration.RegistrationScope = fasAllUsers then Result := HKEY_LOCAL_MACHINE
  else Result := HKEY_CURRENT_USER;
end;
function TFileAssWindowsBackend.ProgID(Configuration: TFileAssConfiguration; Item: TFileAssTypeItem): UTF8String;
begin Result := Configuration.ApplicationID + Item.Extension; end;
procedure TFileAssWindowsBackend.BuildEntries(Configuration: TFileAssConfiguration; Entries: TFileAssResources);
var I, J: Integer; Item: TFileAssTypeItem; Key, Command, Capability, IconPath: UTF8String; Arguments: TStringList;
  procedure Add(const Key, Name, Value: UTF8String);
  begin Entries.AddFile(Key + #9 + Name, Value); end;
begin
  Capability := 'Software\FileAss\' + Configuration.ApplicationID + '\Capabilities';
  Add(Capability, 'FileAssOwner', Configuration.ApplicationID);
  Add(Capability, 'ApplicationName', Configuration.ApplicationName);
  Add(Capability, 'ApplicationDescription', Configuration.ApplicationDescription);
  Add('Software\RegisteredApplications', Configuration.ApplicationID, Capability);
  Arguments := TStringList.Create;
  try
    for I := 0 to Configuration.FileTypes.Count - 1 do begin
      Item := Configuration.FileTypes[I];
      if not Item.Enabled then Continue;
      if not FileAssParseArguments(Item.OpenArguments, Arguments) then
        raise Exception.Create('OpenArguments contains an unmatched double quote.');
      Command := FileAssWindowsArgument(Configuration.ResolveExecutable(False));
      for J := 0 to Arguments.Count - 1 do Command := Command + ' ' + FileAssWindowsArgument(Arguments[J]);
      Command := Command + ' "%1"';
      Key := 'Software\Classes\' + ProgID(Configuration, Item);
      Add(Key, 'FileAssOwner', Configuration.ApplicationID);
      Add(Key, '', Item.Description);
      if Item.WindowsIcon <> '' then begin
        IconPath := Item.WindowsIcon;
        if (Pos(',', IconPath) = 0) and (Pos('"', IconPath) = 0) then begin
          if (ExtractFileDrive(IconPath) = '') and (Copy(IconPath, 1, 2) <> '\\') then
            IconPath := ExpandFileName(IncludeTrailingPathDelimiter(
              ExtractFileDir(Configuration.ResolveExecutable(False))) + IconPath);
          IconPath := FileAssWindowsArgument(IconPath) + ',0';
        end;
        Add(Key + '\DefaultIcon', '', IconPath);
      end;
      Add(Key + '\shell\open\command', '', Command);
      if Configuration.SupportsMultipleFiles then Add(Key + '\shell\open', 'MultiSelectModel', 'Player');
      Add('Software\Classes\' + Item.Extension + '\OpenWithProgids', ProgID(Configuration, Item), '');
      Add(Capability + '\FileAssociations', Item.Extension, ProgID(Configuration, Item));
    end;
  finally Arguments.Free; end;
end;
procedure TFileAssWindowsBackend.AddInventory(Configuration: TFileAssConfiguration;
  Entries: TFileAssResources);
var I, Count: Integer; Key: UTF8String;
begin
  Key := 'Software\FileAss\' + Configuration.ApplicationID + '\RegisteredValues';
  Count := Entries.Count;
  for I := 0 to Count - 1 do
    Entries.AddFile(Key + #9 + Entries[I].Path, Entries[I].Contents);
end;
function TFileAssWindowsBackend.ReadValue(Reg: TRegistry; const Key, Name: UTF8String; out Value: UTF8String): Boolean;
begin
  Value := '';
  Result := Reg.OpenKeyReadOnly(UTF8Decode(Key));
  if not Result then Exit;
  try
    Result := Reg.ValueExists(UTF8Decode(Name));
    if Result then Value := UTF8Encode(Reg.ReadString(UTF8Decode(Name)));
  finally Reg.CloseKey; end;
end;
function TFileAssWindowsBackend.ReadInstalled(Reg: TRegistry;
  Configuration: TFileAssConfiguration; Entries: TFileAssResources): Boolean;
var Names: TStringList; I, Separator: Integer; Path, Key, Name, Prefix, Extension: UTF8String;
begin
  Result := False;
  Names := TStringList.Create;
  try
    if not Reg.OpenKeyReadOnly(UTF8Decode('Software\FileAss\' +
      Configuration.ApplicationID + '\RegisteredValues')) then Exit;
    try
      Reg.GetValueNames(Names);
      for I := 0 to Names.Count - 1 do begin
        Path := UTF8String(Names[I]);
        Separator := Pos(#9, Path);
        if Separator = 0 then raise Exception.Create('Invalid registration inventory.');
        Key := Copy(Path, 1, Separator - 1);
        Name := Copy(Path, Separator + 1, MaxInt);
        Prefix := 'Software\FileAss\' + Configuration.ApplicationID + '\Capabilities';
        if not ((Key = Prefix) or (Pos(Prefix + '\', Key) = 1) or
          ((Key = 'Software\RegisteredApplications') and (Name = Configuration.ApplicationID)) or
          (Pos('Software\Classes\' + Configuration.ApplicationID + '.', Key) = 1)) then begin
          Extension := Copy(Key, Length('Software\Classes\') + 1, MaxInt);
          Separator := Pos('\', Extension);
          if Separator = 0 then raise Exception.Create('Invalid registration inventory path.');
          Extension := Copy(Extension, 1, Separator - 1);
          if (Key <> 'Software\Classes\' + Extension + '\OpenWithProgids') or
            (Name <> Configuration.ApplicationID + Extension) then
            raise Exception.Create('An unrelated registry path in the inventory will be preserved.');
        end;
        Entries.AddFile(Path, UTF8Encode(Reg.ReadString(Names[I])));
      end;
      Result := Entries.Count > 0;
    finally Reg.CloseKey; end;
  finally Names.Free; end;
end;
procedure TFileAssWindowsBackend.Preflight(Reg: TRegistry; Configuration: TFileAssConfiguration;
  Entries: TFileAssResources);
var I, Separator: Integer; Key, Name, Value, OwnerKey, Prefix: UTF8String;
  procedure CheckOwner(const OwnerKey: UTF8String);
  var Identity: UTF8String;
  begin
    if Reg.KeyExists(UTF8Decode(OwnerKey)) and
      (not ReadValue(Reg, OwnerKey, 'FileAssOwner', Identity) or
       (Identity <> Configuration.ApplicationID)) then
      raise Exception.Create('An unowned registry key will be preserved: ' + OwnerKey);
  end;
begin
  CheckOwner('Software\FileAss\' + Configuration.ApplicationID + '\Capabilities');
  Prefix := 'Software\Classes\' + Configuration.ApplicationID + '.';
  for I := 0 to Entries.Count - 1 do begin
    Separator := Pos(#9, Entries[I].Path);
    Key := Copy(Entries[I].Path, 1, Separator - 1);
    Name := Copy(Entries[I].Path, Separator + 1, MaxInt);
    if Pos(Prefix, Key) = 1 then begin
      OwnerKey := Key;
      Separator := Pos('\', Copy(Key, Length('Software\Classes\') + 1, MaxInt));
      if Separator > 0 then OwnerKey := Copy(Key, 1, Length('Software\Classes\') + Separator - 1);
      CheckOwner(OwnerKey);
    end;
    if ReadValue(Reg, Key, Name, Value) and (Value <> Entries[I].Contents) then
      raise Exception.Create('A changed registry value will be preserved: ' + Key + '\' + Name);
  end;
end;
procedure TFileAssWindowsBackend.DeleteEntry(Reg: TRegistry;
  Configuration: TFileAssConfiguration; const Path: UTF8String);
var Separator: Integer; Key, Name, Value, Parent, Inventory: UTF8String;
begin
  Separator := Pos(#9, Path);
  Key := Copy(Path, 1, Separator - 1);
  Name := Copy(Path, Separator + 1, MaxInt);
  if ReadValue(Reg, Key, Name, Value) then begin
    if not Reg.OpenKey(UTF8Decode(Key), False) then RaiseLastOSError(Reg.LastError);
    try
      if not Reg.DeleteValue(UTF8Decode(Name)) then RaiseLastOSError(Reg.LastError);
    finally Reg.CloseKey; end;
    PruneKey(Reg, Key);
    Parent := Key;
    while (Pos('\shell', Parent) > 0) or (Pos('\Capabilities\', Parent) > 0) do begin
      Parent := Copy(Parent, 1, LastDelimiter('\', Parent) - 1);
      PruneKey(Reg, Parent);
    end;
  end;
  Inventory := 'Software\FileAss\' + Configuration.ApplicationID + '\RegisteredValues';
  if Reg.OpenKey(UTF8Decode(Inventory), False) then begin
    try
      if Reg.ValueExists(UTF8Decode(Path)) and not Reg.DeleteValue(UTF8Decode(Path)) then
        RaiseLastOSError(Reg.LastError);
    finally Reg.CloseKey; end;
    PruneKey(Reg, Inventory);
  end;
end;
procedure TFileAssWindowsBackend.PruneKey(Reg: TRegistry; const Key: UTF8String);
var Names: TStringList; Empty: Boolean;
begin
  Names := TStringList.Create;
  try
    if not Reg.OpenKeyReadOnly(UTF8Decode(Key)) then Exit;
    try
      Reg.GetValueNames(Names);
      Empty := Names.Count = 0;
      Reg.GetKeyNames(Names);
      Empty := Empty and (Names.Count = 0);
    finally Reg.CloseKey; end;
    if Empty and not Reg.DeleteKey(UTF8Decode(Key)) then
      raise Exception.Create('Cannot remove an empty owned registry key.');
  finally Names.Free; end;
end;
function TFileAssWindowsBackend.RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
var Reg: TRegistry; Entries, Installed, NewEntries: TFileAssResources;
  I, J, Separator, Applied: Integer; Key, Name, Inventory: UTF8String; Known: Boolean;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  Entries := TFileAssResources.Create;
  Installed := TFileAssResources.Create;
  NewEntries := TFileAssResources.Create;
  Applied := 0;
  try
    try
      Reg.RootKey := RootKey(Configuration);
      BuildEntries(Configuration, Entries);
      // Compare existing data to the last installed values, not the next version.
      if ReadInstalled(Reg, Configuration, Installed) then begin
        Preflight(Reg, Configuration, Installed);
        for I := 0 to Entries.Count - 1 do begin
          Known := False;
          for J := 0 to Installed.Count - 1 do
            if SameText(Entries[I].Path, Installed[J].Path) then begin Known := True; Break; end;
          if not Known then NewEntries.AddFile(Entries[I].Path, Entries[I].Contents);
        end;
        Preflight(Reg, Configuration, NewEntries);
      end else Preflight(Reg, Configuration, Entries);
      Inventory := 'Software\FileAss\' + Configuration.ApplicationID + '\RegisteredValues';
      for I := 0 to Entries.Count - 1 do begin
        Separator := Pos(#9, Entries[I].Path);
        Key := Copy(Entries[I].Path, 1, Separator - 1);
        Name := Copy(Entries[I].Path, Separator + 1, MaxInt);
        if not Reg.OpenKey(UTF8Decode(Key), True) then RaiseLastOSError(Reg.LastError);
        try Reg.WriteString(UTF8Decode(Name), UTF8Decode(Entries[I].Contents));
        finally Reg.CloseKey; end;
        Inc(Applied);
        if not Reg.OpenKey(UTF8Decode(Inventory), True) then RaiseLastOSError(Reg.LastError);
        try Reg.WriteString(UTF8Decode(Entries[I].Path), UTF8Decode(Entries[I].Contents));
        finally Reg.CloseKey; end;
      end;
      for I := Installed.Count - 1 downto 0 do begin
        Known := False;
        for J := 0 to Entries.Count - 1 do
          if SameText(Installed[I].Path, Entries[J].Path) then begin Known := True; Break; end;
        if not Known then DeleteEntry(Reg, Configuration, Installed[I].Path);
      end;
      SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
      Result := FileAssResult(farSuccess, 'Registered as an available handler. User defaults are unchanged.');
    except
      on E: Exception do begin
        Result := FileAssFailure(E);
        if Applied > 0 then begin
          Result.Code := farPartialSuccess;
          Result.Message := Result.Message + ' Some registry values were written; retry after resolving the error.';
          SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
        end;
      end;
    end;
  finally NewEntries.Free; Installed.Free; Entries.Free; Reg.Free; end;
end;
function TFileAssWindowsBackend.UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
var Reg: TRegistry; Entries: TFileAssResources; I, Pass, Removed: Integer;
  OwnerMarker: Boolean;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  Entries := TFileAssResources.Create;
  Removed := 0;
  try
    try
      Reg.RootKey := RootKey(Configuration);
      if not ReadInstalled(Reg, Configuration, Entries) then BuildEntries(Configuration, Entries);
      Preflight(Reg, Configuration, Entries);
      // Leave ownership markers in place until all other values are removed.
      for Pass := 0 to 1 do
        for I := Entries.Count - 1 downto 0 do begin
          OwnerMarker := Copy(Entries[I].Path, Length(Entries[I].Path) - 11, 12) = 'FileAssOwner';
          if OwnerMarker <> (Pass = 1) then Continue;
          Inc(Removed);
          DeleteEntry(Reg, Configuration, Entries[I].Path);
        end;
      PruneKey(Reg, 'Software\FileAss\' + Configuration.ApplicationID);
      SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
      Result := FileAssResult(farSuccess, 'Owned registration values removed. User defaults are unchanged.');
    except
      on E: Exception do begin
        Result := FileAssFailure(E);
        if Removed > 0 then Result.Code := farPartialSuccess;
      end;
    end;
  finally Entries.Free; Reg.Free; end;
end;
function TFileAssWindowsBackend.GetStatus(Configuration: TFileAssConfiguration;
  out Diagnostic: TFileAssResult): TFileAssStatus;
var Reg: TRegistry; Entries: TFileAssResources; I, Separator, Correct: Integer; Key, Name, Value: UTF8String;
begin
  Result := fasVerificationFailed;
  Reg := TRegistry.Create(KEY_READ);
  Entries := TFileAssResources.Create;
  try
    try
      Reg.RootKey := RootKey(Configuration);
      BuildEntries(Configuration, Entries);
      Correct := 0;
      for I := 0 to Entries.Count - 1 do begin
        Separator := Pos(#9, Entries[I].Path);
        Key := Copy(Entries[I].Path, 1, Separator - 1);
        Name := Copy(Entries[I].Path, Separator + 1, MaxInt);
        if ReadValue(Reg, Key, Name, Value) and (Value = Entries[I].Contents) then Inc(Correct);
      end;
      if Correct = 0 then Result := fasNotRegistered
      else if Correct = Entries.Count then Result := fasFullyRegistered
      else Result := fasPartiallyRegistered;
      Diagnostic := FileAssResult(farSuccess, IntToStr(Correct) + ' of ' +
        IntToStr(Entries.Count) + ' registry values match. Default selection is separate.');
    except on E: Exception do Diagnostic := FileAssFailure(E); end;
  finally Entries.Free; Reg.Free; end;
end;
function TFileAssWindowsBackend.GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
  const OutputDirectory: UTF8String): TFileAssResult;
var Entries: TFileAssResources; I, Separator: Integer; Key, Name, Root, Text, Path: UTF8String; Data: UnicodeString;
  function Escape(const Value: UTF8String): UTF8String;
  begin
    Result := StringReplace(Value, '\', '\\', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  end;
begin
  Entries := TFileAssResources.Create;
  try
    try
      BuildEntries(Configuration, Entries);
      AddInventory(Configuration, Entries);
      if Configuration.RegistrationScope = fasAllUsers then Root := 'HKEY_LOCAL_MACHINE'
      else Root := 'HKEY_CURRENT_USER';
      Text := 'Windows Registry Editor Version 5.00' + #13#10;
      for I := 0 to Entries.Count - 1 do begin
        Separator := Pos(#9, Entries[I].Path);
        Key := Copy(Entries[I].Path, 1, Separator - 1);
        Name := Copy(Entries[I].Path, Separator + 1, MaxInt);
        Text := Text + #13#10 + '[' + Root + '\' + Key + ']' + #13#10;
        if Name = '' then Text := Text + '@'
        else Text := Text + '"' + Escape(Name) + '"';
        Text := Text + '="' + Escape(Entries[I].Contents) + '"' + #13#10;
      end;
      Path := IncludeTrailingPathDelimiter(OutputDirectory) + Configuration.ApplicationID + '.reg';
      if FileExists(UTF8Decode(Path)) or FileExists(UTF8Decode(IncludeTrailingPathDelimiter(OutputDirectory) + 'manifest.txt')) then
        raise Exception.Create('Deployment output already exists.');
      if not ForceDirectories(UTF8Decode(OutputDirectory)) then raise Exception.Create('Cannot create output directory.');
      Data := WideChar($FEFF) + UTF8Decode(Text);
      Text := '';
      SetLength(Text, Length(Data) * SizeOf(WideChar));
      Move(Data[1], Text[1], Length(Text));
      FileAssWriteFile(Path, Text);
      FileAssWriteFile(IncludeTrailingPathDelimiter(OutputDirectory) + 'manifest.txt', ExtractFileName(Path) + #10);
      Result := FileAssResult(farSuccess, 'Installer registration data generated without installation.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Entries.Free; end;
end;
function TFileAssWindowsBackend.Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult;
var Entries: TFileAssResources; I: Integer;
begin
  Text.Clear;
  Entries := TFileAssResources.Create;
  try
    try
      BuildEntries(Configuration, Entries);
      AddInventory(Configuration, Entries);
      for I := 0 to Entries.Count - 1 do
        Text.Add(Entries[I].Path + ' = ' + Entries[I].Contents);
      Result := FileAssResult(farSuccess, 'Registry values generated without installation.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Entries.Free; end;
end;
function TFileAssWindowsBackend.OpenDefaultAppsSettings: TFileAssResult;
var Address: UnicodeString; NativeResult: PtrInt;
begin
  Address := 'ms-settings:defaultapps';
  NativeResult := PtrInt(ShellExecuteW(0, nil, PWideChar(Address), nil, nil, SW_SHOWNORMAL));
  if NativeResult > 32 then Result := FileAssResult(farSuccess, 'Default application settings opened.')
  else begin
    Result := FileAssResult(farOperationFailed, 'Cannot open default application settings.');
    Result.NativeError := NativeResult;
  end;
end;
end.
