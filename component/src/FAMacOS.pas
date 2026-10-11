unit FAMacOS;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, DOM, FATypes, FACore;
type
  TFileAssMacOSBackend = class(TFileAssBackend)
  private
    function BuildPlist(Configuration: TFileAssConfiguration;
      const TemplateFile: UTF8String; out Xml: UTF8String): TFileAssResult;
  public
    function RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; override;
    function UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult; override;
    function GetStatus(Configuration: TFileAssConfiguration;
      out Diagnostic: TFileAssResult): TFileAssStatus; override;
    function GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
      const OutputDirectory: UTF8String): TFileAssResult; override;
    function Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult; override;
    function OpenDefaultAppsSettings: TFileAssResult; override;
    function GenerateMergedPlist(Configuration: TFileAssConfiguration;
      const TemplateFile, OutputFile: UTF8String): TFileAssResult;
  end;
implementation
uses XMLRead, XMLWrite, FAFormats, FACollection;
function PlistValue(Dictionary: TDOMNode; const Key: UTF8String): TDOMNode;
var Node: TDOMNode;
begin
  Result := nil;
  Node := Dictionary.FirstChild;
  while Assigned(Node) do begin
    if (Node.NodeName = 'key') and (Node.TextContent = UTF8Decode(Key)) then begin
      Result := Node.NextSibling;
      while Assigned(Result) and (Result.NodeType <> ELEMENT_NODE) do Result := Result.NextSibling;
      Exit;
    end;
    Node := Node.NextSibling;
  end;
end;
function AddValue(Dictionary: TDOMNode; const Key, Kind: UTF8String): TDOMNode;
var KeyNode: TDOMNode;
begin
  KeyNode := Dictionary.OwnerDocument.CreateElement('key');
  KeyNode.AppendChild(Dictionary.OwnerDocument.CreateTextNode(UTF8Decode(Key)));
  Dictionary.AppendChild(KeyNode);
  Result := Dictionary.OwnerDocument.CreateElement(UTF8Decode(Kind));
  Dictionary.AppendChild(Result);
end;
procedure AddString(Dictionary: TDOMNode; const Key, Value: UTF8String);
begin
  AddValue(Dictionary, Key, 'string').AppendChild(
    Dictionary.OwnerDocument.CreateTextNode(UTF8Decode(Value)));
end;
procedure AddArrayString(List: TDOMNode; const Value: UTF8String);
var Node: TDOMNode;
begin
  Node := List.OwnerDocument.CreateElement('string');
  Node.AppendChild(List.OwnerDocument.CreateTextNode(UTF8Decode(Value)));
  List.AppendChild(Node);
end;
function PlistArray(Dictionary: TDOMNode; const Key: UTF8String): TDOMNode;
begin
  Result := PlistValue(Dictionary, Key);
  if not Assigned(Result) then Result := AddValue(Dictionary, Key, 'array')
  else if Result.NodeName <> 'array' then
    raise Exception.Create('Expected a plist array for ' + Key + '.');
end;
function TFileAssMacOSBackend.BuildPlist(Configuration: TFileAssConfiguration;
  const TemplateFile: UTF8String; out Xml: UTF8String): TFileAssResult;
var
  Document: TXMLDocument;
  Root, Dictionary, Documents, Exported, Imported, Definition, DocumentType,
    Tags, Extensions, MimeTypes, Node, ContentTypes: TDOMNode;
  Types, Mimes: TStringList;
  Stream: TStringStream;
  I, J: Integer;
  Item, First: TFileAssTypeItem;
  Identifier, Role: UTF8String;
  OwnBundle: Boolean;
  procedure AddMissing(const Key, Value: UTF8String);
  begin
    if not Assigned(PlistValue(Dictionary, Key)) then AddString(Dictionary, Key, Value);
  end;
  function ConfiguredOwnType(const Value: DOMString): Boolean;
  var Index: Integer;
  begin
    Result := False;
    if Pos(UTF8Decode(Configuration.ApplicationID + '.'), Value) <> 1 then Exit;
    for Index := 0 to Configuration.FileTypes.Count - 1 do
      if Configuration.FileTypes[Index].Enabled and
        (UTF8Decode(Configuration.FileTypes[Index].TypeIdentifier) = Value) then Exit(True);
  end;
  procedure RemoveOwned(List: TDOMNode; IsDocument: Boolean);
  var Entry, Next, Value, Child: TDOMNode; Owned, HasType: Boolean;
  begin
    Entry := List.FirstChild;
    while Assigned(Entry) do begin
      Next := Entry.NextSibling;
      if Entry.NodeName = 'dict' then begin
        Value := PlistValue(Entry, 'FileAssOwner');
        Owned := Assigned(Value) and (Value.TextContent = UTF8Decode(Configuration.ApplicationID));
        // Earlier output had no marker; adopt only this bundle's own UTI namespace.
        if not Assigned(Value) and OwnBundle then begin
          if IsDocument then begin
            Value := PlistValue(Entry, 'LSItemContentTypes');
            Owned := Assigned(Value);
            HasType := False;
            if Assigned(Value) then begin
              Child := Value.FirstChild;
              while Assigned(Child) do begin
                if Child.NodeType = ELEMENT_NODE then begin
                  HasType := True;
                  Owned := Owned and (Child.NodeName = 'string') and
                    ConfiguredOwnType(Child.TextContent);
                end;
                Child := Child.NextSibling;
              end;
            end;
            Owned := Owned and HasType;
          end else begin
            Value := PlistValue(Entry, 'UTTypeIdentifier');
            Owned := Assigned(Value) and
              ConfiguredOwnType(Value.TextContent);
          end;
        end;
        if Owned then begin List.RemoveChild(Entry); Entry.Free; end;
      end;
      Entry := Next;
    end;
  end;
  procedure CheckCollision(List: TDOMNode; const Identifier: UTF8String; IsDocument: Boolean);
  var Entry, Value, Child: TDOMNode;
  begin
    Entry := List.FirstChild;
    while Assigned(Entry) do begin
      if Entry.NodeName = 'dict' then begin
        if IsDocument then begin
          Value := PlistValue(Entry, 'LSItemContentTypes');
          if Assigned(Value) then begin
            Child := Value.FirstChild;
            while Assigned(Child) do begin
              if Child.TextContent = UTF8Decode(Identifier) then
                raise Exception.Create('An existing document declaration will be preserved: ' + Identifier);
              Child := Child.NextSibling;
            end;
          end;
        end else begin
          Value := PlistValue(Entry, 'UTTypeIdentifier');
          if Assigned(Value) and (Value.TextContent = UTF8Decode(Identifier)) then
            raise Exception.Create('An existing type declaration will be preserved: ' + Identifier);
        end;
      end;
      Entry := Entry.NextSibling;
    end;
  end;
begin
  Xml := '';
  Document := nil;
  Types := TStringList.Create;
  Mimes := TStringList.Create;
  try
    try
      Result := Configuration.Validate(fatMacOS, True);
      if not Result.Succeeded then Exit;
      OwnBundle := False;
      if TemplateFile <> '' then begin
        Stream := TStringStream.Create(FileAssReadFile(TemplateFile));
        try ReadXMLFile(Document, Stream); finally Stream.Free; end;
        Root := Document.DocumentElement;
        if Root.NodeName <> 'plist' then raise Exception.Create('Expected an XML plist template.');
        Dictionary := Root.FindNode('dict');
        if not Assigned(Dictionary) then raise Exception.Create('Expected a plist dictionary.');
        Node := PlistValue(Dictionary, 'CFBundleIdentifier');
        if Assigned(Node) and (Node.TextContent <> UTF8Decode(Configuration.ApplicationID)) then
          raise Exception.Create('The bundle identifier belongs to a different application.');
        OwnBundle := Assigned(Node);
      end else begin
        Document := TXMLDocument.Create;
        Root := Document.CreateElement('plist');
        TDOMElement(Root).SetAttribute('version', '1.0');
        Document.AppendChild(Root);
        Dictionary := Document.CreateElement('dict');
        Root.AppendChild(Dictionary);
      end;
      AddMissing('CFBundleIdentifier', Configuration.ApplicationID);
      AddMissing('CFBundleName', Configuration.ApplicationName);
      AddMissing('CFBundleExecutable', ExtractFileName(Configuration.ExecutablePath));
      AddMissing('CFBundlePackageType', 'APPL');
      AddMissing('CFBundleInfoDictionaryVersion', '6.0');
      Documents := PlistArray(Dictionary, 'CFBundleDocumentTypes');
      Exported := PlistArray(Dictionary, 'UTExportedTypeDeclarations');
      Imported := PlistArray(Dictionary, 'UTImportedTypeDeclarations');
      RemoveOwned(Documents, True);
      RemoveOwned(Exported, False);
      RemoveOwned(Imported, False);
      for I := 0 to Configuration.FileTypes.Count - 1 do
        if Configuration.FileTypes[I].Enabled and
          (Types.IndexOf(Configuration.FileTypes[I].TypeIdentifier) < 0) then
          Types.Add(Configuration.FileTypes[I].TypeIdentifier);
      for I := 0 to Types.Count - 1 do begin
        Identifier := Types[I];
        CheckCollision(Documents, Identifier, True);
        CheckCollision(Exported, Identifier, False);
        CheckCollision(Imported, Identifier, False);
        First := nil;
        for J := 0 to Configuration.FileTypes.Count - 1 do
          if Configuration.FileTypes[J].Enabled and
            (Configuration.FileTypes[J].TypeIdentifier = Identifier) then begin
            First := Configuration.FileTypes[J];
            Break;
          end;
        DocumentType := Document.CreateElement('dict');
        Documents.AppendChild(DocumentType);
        AddString(DocumentType, 'FileAssOwner', Configuration.ApplicationID);
        AddString(DocumentType, 'CFBundleTypeName', First.Description);
        case First.Role of
          farEditor: Role := 'Editor';
          farViewer: Role := 'Viewer';
        else Role := 'None'; end;
        AddString(DocumentType, 'CFBundleTypeRole', Role);
        AddString(DocumentType, 'LSHandlerRank', 'Alternate');
        if First.MacIcon <> '' then begin
          if ExtractFileName(First.MacIcon) <> First.MacIcon then
            raise Exception.Create('MacIcon must name a file in the bundle Resources directory.');
          AddString(DocumentType, 'CFBundleTypeIconFile', First.MacIcon);
        end;
        ContentTypes := AddValue(DocumentType, 'LSItemContentTypes', 'array');
        AddArrayString(ContentTypes, Identifier);
        Definition := Document.CreateElement('dict');
        if Pos(Configuration.ApplicationID + '.', Identifier) = 1 then Exported.AppendChild(Definition)
        else Imported.AppendChild(Definition);
        AddString(Definition, 'FileAssOwner', Configuration.ApplicationID);
        AddString(Definition, 'UTTypeIdentifier', Identifier);
        AddString(Definition, 'UTTypeDescription', First.Description);
        AddArrayString(AddValue(Definition, 'UTTypeConformsTo', 'array'), 'public.data');
        Tags := AddValue(Definition, 'UTTypeTagSpecification', 'dict');
        Extensions := AddValue(Tags, 'public.filename-extension', 'array');
        MimeTypes := AddValue(Tags, 'public.mime-type', 'array');
        Mimes.Clear;
        for J := 0 to Configuration.FileTypes.Count - 1 do begin
          Item := Configuration.FileTypes[J];
          if not Item.Enabled or (Item.TypeIdentifier <> Identifier) then Continue;
          if (Item.Description <> First.Description) or (Item.Role <> First.Role) or
            (Item.MacIcon <> First.MacIcon) then
            raise Exception.Create('Extensions sharing a type identifier require consistent metadata.');
          AddArrayString(Extensions, Copy(Item.Extension, 2, MaxInt));
          if (Item.MimeType <> '') and (Mimes.IndexOf(Item.MimeType) < 0) then begin
            Mimes.Add(Item.MimeType);
            AddArrayString(MimeTypes, Item.MimeType);
          end;
        end;
      end;
      Stream := TStringStream.Create('');
      try WriteXMLFile(Document, Stream); Xml := Stream.DataString; finally Stream.Free; end;
      Result := FileAssResult(farSuccess, 'Bundle metadata generated. macOS integration testing is required.');
    except on E: Exception do Result := FileAssFailure(E); end;
  finally Document.Free; Mimes.Free; Types.Free; end;
end;
function TFileAssMacOSBackend.GenerateMergedPlist(Configuration: TFileAssConfiguration;
  const TemplateFile, OutputFile: UTF8String): TFileAssResult;
var Xml: UTF8String;
begin
  try
    Result := BuildPlist(Configuration, TemplateFile, Xml);
    if not Result.Succeeded then Exit;
    if FileExists(OutputFile) then
      Exit(FileAssResult(farOperationFailed, 'The output plist already exists.'));
    FileAssWriteFile(OutputFile, Xml);
  except on E: Exception do Result := FileAssFailure(E); end;
end;
function TFileAssMacOSBackend.GenerateDeploymentFiles(Configuration: TFileAssConfiguration;
  const OutputDirectory: UTF8String): TFileAssResult;
var Xml, Path: UTF8String;
begin
  try
    Result := BuildPlist(Configuration, '', Xml);
    if not Result.Succeeded then Exit;
    Path := IncludeTrailingPathDelimiter(OutputDirectory);
    if FileExists(Path + 'Info.plist') or FileExists(Path + 'manifest.txt') then
      Exit(FileAssResult(farOperationFailed, 'Deployment output already exists.'));
    if not ForceDirectories(OutputDirectory) then raise Exception.Create('Cannot create output directory.');
    FileAssWriteFile(Path + 'Info.plist', Xml);
    FileAssWriteFile(Path + 'manifest.txt', 'Info.plist' + #10);
  except on E: Exception do Result := FileAssFailure(E); end;
end;
function TFileAssMacOSBackend.Preview(Configuration: TFileAssConfiguration; Text: TStrings): TFileAssResult;
var Xml: UTF8String;
begin
  Text.Clear;
  Result := BuildPlist(Configuration, '', Xml);
  if Result.Succeeded then Text.Text := Xml;
end;
function TFileAssMacOSBackend.RegisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
begin
  Result := FileAssResult(farRequiresDeployment, 'Install an application bundle containing the generated Info.plist.');
end;
function TFileAssMacOSBackend.UnregisterTypes(Configuration: TFileAssConfiguration): TFileAssResult;
begin
  Result := FileAssResult(farRequiresDeployment, 'Remove the installed application bundle through its installer.');
end;
function TFileAssMacOSBackend.GetStatus(Configuration: TFileAssConfiguration;
  out Diagnostic: TFileAssResult): TFileAssStatus;
begin
  Diagnostic := FileAssResult(farUnsupported, 'Launch Services inspection requires macOS testing.');
  Result := fasUnavailable;
end;
function TFileAssMacOSBackend.OpenDefaultAppsSettings: TFileAssResult;
begin
  Result := FileAssResult(farUnsupported, 'Choose a handler in Finder Get Info, under Open With.');
end;
end.
