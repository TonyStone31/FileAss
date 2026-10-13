unit FAMacOS;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, FATypes, FACollection, FACore;

type
  { macOS takes an application's file types from the Info.plist in its
    bundle, so there is nothing to register while the program runs.  This
    writes those Info.plist entries for whoever builds the bundle. }
  TFileAssMacOSBackend = class(TFileAssBackend)
  private
    function BuildPlist(App: TFileAssManager): utf8string;
  public
    function RegisterTypes(App: TFileAssManager): TFileAssResult; override;
    function UnregisterTypes(App: TFileAssManager): TFileAssResult; override;
    function GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus; override;
    function GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult; override;
    function Preview(App: TFileAssManager; Text: TStrings): TFileAssResult; override;
    function OpenDefaultAppsSettings: TFileAssResult; override;
  end;

implementation

uses FAFormats;

const
  InTheBundle = 'macOS reads file types from the application bundle''s Info.plist; export it and install the bundle.';

function Tag(const Kind, Value: utf8string): utf8string;
begin
  Result := '<' + Kind + '>' + FileAssXml(Value) + '</' + Kind + '>';
end;

function Pair(const Key, Value: utf8string): utf8string;
begin
  Result := Tag('key', Key) + Tag('string', Value) + #10;
end;

function List(const Key: utf8string; Values: TStrings): utf8string;
var
  I: integer;
begin
  Result := Tag('key', Key) + '<array>';
  for I := 0 to Values.Count - 1 do Result := Result + Tag('string', Values[I]);
  Result := Result + '</array>' + #10;
end;

{ A file name in the bundle's Resources, not a path. }
procedure CheckIconName(const Name: utf8string);
begin
  if (ExtractFileName(Name) <> Name) or (Pos('\', Name) > 0) then
    raise EFileAssConfiguration.Create('A macOS icon is a file name in the bundle''s Resources, not a path: ' + Name);
end;

function TFileAssMacOSBackend.BuildPlist(App: TFileAssManager): utf8string;
var
  Documents, Exported, Imported, Declaration, Role, Rank, Identifier: utf8string;
  Types, Values: TStringList;
  Item, First: TFileAssTypeItem;
  I, J: integer;
  Own: boolean;
begin
  Documents := '';
  Exported := '';
  Imported := '';
  Types := TStringList.Create;
  Values := TStringList.Create;
  try
    // several extensions may share one type identifier; each identifier is declared once
    for I := 0 to App.FileTypes.Count - 1 do
      if App.FileTypes[I].Enabled and (Types.IndexOf(App.FileTypes[I].TypeIdentifier) < 0) then Types.Add(App.FileTypes[I].TypeIdentifier);
    for I := 0 to Types.Count - 1 do
    begin
      Identifier := Types[I];
      First := nil;
      for J := 0 to App.FileTypes.Count - 1 do
      begin
        Item := App.FileTypes[J];
        if not Item.Enabled or (Item.TypeIdentifier <> Identifier) then Continue;
        if First = nil then First := Item
        else if (Item.Description <> First.Description) or (Item.Role <> First.Role) or (Item.MacIcon <> First.MacIcon) then
          raise EFileAssConfiguration.Create('Extensions sharing a type identifier must have the same description, role and icon.');
      end;
      if First.MacIcon <> '' then CheckIconName(First.MacIcon);
      case First.Role of
        farEditor: Role := 'Editor';
        farViewer: Role := 'Viewer';
        else
          Role := 'None';
      end;
      // a type under the application's own ID is its to export; any other it only opens
      Own := Pos(App.ApplicationID + '.', Identifier) = 1;
      if Own then Rank := 'Owner'
      else
        Rank := 'Alternate';
      Values.Clear;
      Values.Add(Identifier);
      Documents := Documents + '<dict>' + #10 + Pair('CFBundleTypeName', First.Description) + Pair('CFBundleTypeRole', Role) + Pair('LSHandlerRank', Rank);
      if First.MacIcon <> '' then Documents := Documents + Pair('CFBundleTypeIconFile', First.MacIcon);
      Documents := Documents + List('LSItemContentTypes', Values) + '</dict>' + #10;

      Declaration := '<dict>' + #10 + Pair('UTTypeIdentifier', Identifier) + Pair('UTTypeDescription', First.Description);
      if First.MacIcon <> '' then Declaration := Declaration + Pair('UTTypeIconFile', First.MacIcon);
      Values.Clear;
      Values.Add('public.data');
      Values.Add('public.content');
      Declaration := Declaration + List('UTTypeConformsTo', Values) + Tag('key', 'UTTypeTagSpecification') + '<dict>' + #10;
      Values.Clear;
      for J := 0 to App.FileTypes.Count - 1 do
        if App.FileTypes[J].Enabled and (App.FileTypes[J].TypeIdentifier = Identifier) then
          Values.Add(Copy(App.FileTypes[J].Extension, 2, MaxInt));
      Declaration := Declaration + List('public.filename-extension', Values);
      Values.Clear;
      for J := 0 to App.FileTypes.Count - 1 do
      begin
        Item := App.FileTypes[J];
        if Item.Enabled and (Item.TypeIdentifier = Identifier) and (Item.MimeType <> '') and (Values.IndexOf(Item.MimeType) < 0) then
          Values.Add(Item.MimeType);
      end;
      if Values.Count > 0 then Declaration := Declaration + List('public.mime-type', Values);
      Declaration := Declaration + '</dict>' + #10 + '</dict>' + #10;
      if Own then Exported := Exported + Declaration
      else
        Imported := Imported + Declaration;
    end;

    Result := '<?xml version="1.0" encoding="UTF-8"?>' + #10 + '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' +
      #10 + '<plist version="1.0">' + #10 + '<dict>' + #10 + Pair('CFBundleIdentifier', App.ApplicationID) + Pair('CFBundleName', App.ApplicationName) +
      Pair('CFBundleExecutable', ExtractFileName(App.ExecutablePath)) + Pair('CFBundlePackageType', 'APPL') + Pair('CFBundleInfoDictionaryVersion', '6.0');
    if App.MacApplicationIcon <> '' then
    begin
      CheckIconName(App.MacApplicationIcon);
      Result := Result + Pair('CFBundleIconFile', App.MacApplicationIcon);
    end;
    Result := Result + Tag('key', 'CFBundleDocumentTypes') + '<array>' + #10 + Documents + '</array>' + #10;
    if Exported <> '' then Result := Result + Tag('key', 'UTExportedTypeDeclarations') + '<array>' + #10 + Exported + '</array>' + #10;
    if Imported <> '' then Result := Result + Tag('key', 'UTImportedTypeDeclarations') + '<array>' + #10 + Imported + '</array>' + #10;
    Result := Result + '</dict>' + #10 + '</plist>' + #10;
  finally
    Values.Free;
    Types.Free;
  end;
end;

function TFileAssMacOSBackend.GenerateDeploymentFiles(App: TFileAssManager; const OutputDirectory: utf8string): TFileAssResult;
var
  Folder: utf8string;
begin
  try
    Result := App.ValidateFor(fatMacOS, True);
    if not Result.Succeeded then Exit;
    Folder := IncludeTrailingPathDelimiter(OutputDirectory);
    if FileExists(Folder + 'Info.plist') or FileExists(Folder + 'manifest.txt') then
      raise Exception.Create('The output is already there; nothing was overwritten.');
    if not ForceDirectories(OutputDirectory) then raise Exception.Create('Cannot create ' + OutputDirectory);
    FileAssWriteFile(Folder + 'Info.plist', BuildPlist(App));
    FileAssWriteFile(Folder + 'manifest.txt', 'Info.plist' + #10);
    Result := FileAssResult(farSuccess, 'Info.plist written. Its entries go into the application bundle''s own Info.plist.');
  except
    on E: Exception do Result := FileAssFailure(E);
  end;
end;

function TFileAssMacOSBackend.Preview(App: TFileAssManager; Text: TStrings): TFileAssResult;
begin
  Text.Clear;
  try
    Result := App.ValidateFor(fatMacOS, True);
    if not Result.Succeeded then Exit;
    Text.Text := BuildPlist(App);
    Result := FileAssResult(farSuccess, 'This is what the bundle''s Info.plist needs.');
  except
    on E: Exception do Result := FileAssFailure(E);
  end;
end;

function TFileAssMacOSBackend.RegisterTypes(App: TFileAssManager): TFileAssResult;
begin
  Result := FileAssResult(farRequiresDeployment, InTheBundle);
end;

function TFileAssMacOSBackend.UnregisterTypes(App: TFileAssManager): TFileAssResult;
begin
  Result := FileAssResult(farRequiresDeployment, 'On macOS the file types go when the application bundle is removed.');
end;

function TFileAssMacOSBackend.GetStatus(App: TFileAssManager; out Diagnostic: TFileAssResult): TFileAssStatus;
begin
  Diagnostic := FileAssResult(farUnsupported, InTheBundle);
  Result := fasUnavailable;
end;

function TFileAssMacOSBackend.OpenDefaultAppsSettings: TFileAssResult;
begin
  Result := FileAssResult(farUnsupported, 'In Finder, choose Get Info on one of the files and set Open With.');
end;

end.
