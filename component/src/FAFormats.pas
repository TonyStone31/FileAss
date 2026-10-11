unit FAFormats;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Contnrs, FATypes;
type
  TFileAssResource = class
  public
    Path: UTF8String;
    Contents: RawByteString;
  end;
  TFileAssResources = class(TObjectList)
  private
    function GetResource(Index: Integer): TFileAssResource;
  public
    constructor Create;
    procedure AddFile(const Path: UTF8String; const Contents: RawByteString);
    property Files[Index: Integer]: TFileAssResource read GetResource; default;
  end;
function FileAssReadFile(const Path: UTF8String): RawByteString;
procedure FileAssWriteFile(const Path: UTF8String; const Contents: RawByteString);
function FileAssXml(const Value: UTF8String): UTF8String;
function FileAssDesktopValue(const Value: UTF8String): UTF8String;
function FileAssDesktopArgument(const Value: UTF8String): UTF8String;
function FileAssWindowsArgument(const Value: UTF8String): UTF8String;
function FileAssParseArguments(const Value: UTF8String; Arguments: TStrings): Boolean;
function FileAssFailure(E: Exception): TFileAssResult;
function FileAssExecutable: UTF8String;
implementation
{$ifdef windows}
uses Windows;
{$endif}
constructor TFileAssResources.Create;
begin inherited Create(True); end;
function TFileAssResources.GetResource(Index: Integer): TFileAssResource;
begin Result := TFileAssResource(inherited Items[Index]); end;
procedure TFileAssResources.AddFile(const Path: UTF8String; const Contents: RawByteString);
var Resource: TFileAssResource;
begin
  Resource := TFileAssResource.Create;
  Resource.Path := Path;
  Resource.Contents := Contents;
  Add(Resource);
end;
function FileAssReadFile(const Path: UTF8String): RawByteString;
var Stream: THandleStream;
  {$ifdef windows}FileHandle: THandle;{$endif}
begin
  Result := '';
  {$ifdef windows}
  FileHandle := FileOpen(UTF8Decode(Path), fmOpenRead or fmShareDenyWrite);
  if FileHandle = THandle(-1) then RaiseLastOSError;
  Stream := THandleStream.Create(FileHandle);
  {$else}
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  {$endif}
  try
    if Stream.Size > 16 * 1024 * 1024 then
      raise EReadError.Create('Resource exceeds the 16 MB limit: ' + ExtractFileName(Path));
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
    {$ifdef windows}FileClose(FileHandle);{$endif}
  end;
end;
procedure FileAssWriteFile(const Path: UTF8String; const Contents: RawByteString);
var Stream: THandleStream;
  {$ifdef windows}FileHandle: THandle;{$endif}
begin
  {$ifdef windows}
  FileHandle := FileCreate(UTF8Decode(Path));
  if FileHandle = THandle(-1) then RaiseLastOSError;
  Stream := THandleStream.Create(FileHandle);
  {$else}
  Stream := TFileStream.Create(Path, fmCreate);
  {$endif}
  try
    if Length(Contents) > 0 then Stream.WriteBuffer(Contents[1], Length(Contents));
  finally
    Stream.Free;
    {$ifdef windows}FileClose(FileHandle);{$endif}
  end;
end;
function FileAssXml(const Value: UTF8String): UTF8String;
begin
  Result := StringReplace(Value, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;
function FileAssDesktopValue(const Value: UTF8String): UTF8String;
begin
  Result := StringReplace(Value, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
  Result := StringReplace(Result, ' ', '\s', [rfReplaceAll]);
end;
function FileAssDesktopArgument(const Value: UTF8String): UTF8String;
var I: Integer; Quoted: UTF8String;
begin
  Quoted := '"';
  for I := 1 to Length(Value) do begin
    if Value[I] in ['"', '`', '$', '\'] then Quoted := Quoted + '\';
    if Value[I] = '%' then Quoted := Quoted + '%';
    Quoted := Quoted + Value[I];
  end;
  Result := FileAssDesktopValue(Quoted + '"');
end;
function FileAssWindowsArgument(const Value: UTF8String): UTF8String;
var I, Slashes: Integer;
begin
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(Value) do begin
    if Value[I] = '\' then Inc(Slashes)
    else begin
      if Value[I] = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1)
      else Result := Result + StringOfChar('\', Slashes);
      Result := Result + Value[I];
      Slashes := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;
function FileAssParseArguments(const Value: UTF8String; Arguments: TStrings): Boolean;
var I: Integer; InQuotes, Started: Boolean; Argument: UTF8String;
begin
  Arguments.Clear;
  InQuotes := False;
  Started := False;
  Argument := '';
  I := 1;
  while I <= Length(Value) do begin
    if Value[I] = '"' then begin
      InQuotes := not InQuotes;
      Started := True;
    end else if (Value[I] = '\') and (I < Length(Value)) and
      (Value[I + 1] in ['"', '\']) then begin
      Inc(I);
      Argument := Argument + Value[I];
      Started := True;
    end else if (Value[I] = ' ') and not InQuotes then begin
      if Started then Arguments.Add(Argument);
      Argument := '';
      Started := False;
    end else begin
      Argument := Argument + Value[I];
      Started := True;
    end;
    Inc(I);
  end;
  Result := not InQuotes;
  if Result and Started then Arguments.Add(Argument);
end;
function FileAssFailure(E: Exception): TFileAssResult;
begin
  Result := FileAssResult(farOperationFailed, E.Message);
  if E is EOSError then begin
    Result.NativeError := EOSError(E).ErrorCode;
    if Result.NativeError in [5, 13] then Result.Code := farPermissionDenied;
  end;
end;
function FileAssExecutable: UTF8String;
{$ifdef windows}
var Buffer: UnicodeString; Count: DWORD;
{$endif}
begin
  {$ifdef windows}
  SetLength(Buffer, 32768);
  Count := GetModuleFileNameW(0, PWideChar(Buffer), Length(Buffer));
  if Count = 0 then RaiseLastOSError;
  if Count >= DWORD(Length(Buffer)) then
    raise Exception.Create('The executable path is too long.');
  SetLength(Buffer, Count);
  Result := UTF8Encode(Buffer);
  {$else}
  Result := ExpandFileName(ParamStr(0));
  {$endif}
end;
end.
