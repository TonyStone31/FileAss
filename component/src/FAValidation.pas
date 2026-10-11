unit FAValidation;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, FATypes, FACollection;
function FileAssValidIdentifier(const Value: UTF8String): Boolean;
function FileAssContainsControl(const Value: UTF8String): Boolean;
function FileAssValidate(const ApplicationID, ApplicationName,
  ExecutablePath: UTF8String; FileTypes: TFileAssTypeCollection;
  Target: TFileAssTarget): TFileAssResult;
implementation
function FileAssValidIdentifier(const Value: UTF8String): Boolean;
var I: Integer; StartOfPart: Boolean; Parts: Integer;
begin
  Result := False;
  StartOfPart := True;
  Parts := 1;
  for I := 1 to Length(Value) do begin
    if Value[I] = '.' then begin
      if StartOfPart then Exit;
      StartOfPart := True;
      Inc(Parts);
    end else begin
      if StartOfPart and not (Value[I] in ['a'..'z', 'A'..'Z']) then Exit;
      if not (Value[I] in ['a'..'z', 'A'..'Z', '0'..'9', '-']) then Exit;
      StartOfPart := False;
    end;
  end;
  Result := not StartOfPart and (Parts >= 2);
end;
function FileAssContainsControl(const Value: UTF8String): Boolean;
var I: Integer;
begin
  Result := True;
  for I := 1 to Length(Value) do
    if Ord(Value[I]) < 32 then Exit;
  Result := False;
end;
function ValidExtension(const Value: UTF8String): Boolean;
var I: Integer;
begin
  Result := False;
  if (Length(Value) < 2) or (Value[1] <> '.') then Exit;
  for I := 2 to Length(Value) do
    if not (Value[I] in ['a'..'z', '0'..'9', '_', '-']) then Exit;
  Result := True;
end;
function ValidMime(const Value: UTF8String): Boolean;
var I, Slash: Integer;
begin
  Result := False;
  Slash := Pos('/', Value);
  if (Slash <= 1) or (Slash = Length(Value)) then Exit;
  for I := 1 to Length(Value) do
    if (I <> Slash) and not (Value[I] in
      ['a'..'z', 'A'..'Z', '0'..'9', '!', '#', '$', '&', '^', '_', '.', '+', '-']) then Exit;
  Result := True;
end;
function FileAssValidate(const ApplicationID, ApplicationName,
  ExecutablePath: UTF8String; FileTypes: TFileAssTypeCollection;
  Target: TFileAssTarget): TFileAssResult;
var I, J, EnabledCount: Integer; Item: TFileAssTypeItem;
begin
  Result := FileAssResult(farInvalidConfiguration, 'Invalid application identifier.');
  if not FileAssValidIdentifier(ApplicationID) then Exit;
  Result.Message := 'Application name is required and must not contain control characters.';
  if (Trim(ApplicationName) = '') or FileAssContainsControl(ApplicationName) then Exit;
  Result.Message := 'An explicit executable path without control characters is required.';
  if (ExecutablePath = '') or FileAssContainsControl(ExecutablePath) then Exit;
  Result.Message := 'The executable path must be absolute for the target platform.';
  if Target = fatWindows then begin
    if not (((Length(ExecutablePath) >= 3) and (ExecutablePath[2] = ':') and
      (ExecutablePath[3] in ['\', '/'])) or (Copy(ExecutablePath, 1, 2) = '\\')) then Exit;
    Result.Message := 'Windows executable paths cannot contain double quotes.';
    if Pos('"', ExecutablePath) > 0 then Exit;
  end else if ExecutablePath[1] <> '/' then Exit;
  EnabledCount := 0;
  for I := 0 to FileTypes.Count - 1 do begin
    Item := FileTypes[I];
    if not Item.Enabled then Continue;
    Inc(EnabledCount);
    Result.Extension := Item.Extension;
    Result.Message := 'Invalid file extension.';
    if not ValidExtension(Item.Extension) then Exit;
    for J := 0 to I - 1 do
      if FileTypes[J].Enabled and SameText(FileTypes[J].Extension, Item.Extension) then begin
        Result.Message := 'Duplicate enabled file extension.';
        Exit;
      end;
    Result.Message := 'File type properties must not contain control characters.';
    if FileAssContainsControl(Item.Description) or FileAssContainsControl(Item.OpenArguments) or
      FileAssContainsControl(Item.WindowsIcon) or FileAssContainsControl(Item.LinuxIcon) or
      FileAssContainsControl(Item.MacIcon) then Exit;
    Result.Message := 'A valid MIME type is required for Linux.';
    if (Target = fatLinux) and not ValidMime(Item.MimeType) then Exit;
    Result.Message := 'A valid type identifier is required for macOS.';
    if (Target = fatMacOS) and not FileAssValidIdentifier(Item.TypeIdentifier) then Exit;
  end;
  Result.Extension := '';
  Result.Message := 'At least one enabled file type is required.';
  if EnabledCount = 0 then Exit;
  if Target = fatUnavailable then
    Result := FileAssResult(farUnsupported, 'The target platform is unavailable.')
  else Result := FileAssResult(farSuccess, 'Configuration is valid.');
end;
end.
