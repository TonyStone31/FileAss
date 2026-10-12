unit FACollection;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, FATypes;
type
  TFileAssTypeItem = class(TCollectionItem)
  private
    TypeEnabled: Boolean;
    FileExtension, TypeDescription, MimeName, DocumentIdentifier: UTF8String;
    WindowsIconPath, LinuxIconName, MacIconName, LaunchArguments: UTF8String;
    DocumentRole: TFileAssRole;
    procedure SetExtension(const Value: UTF8String);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    // Default True. False excludes this item from registration and deployment generation.
    // Changing this property alone does not modify already installed associations.
    property Enabled: Boolean read TypeEnabled write TypeEnabled default True;
    // Required filename extension, such as .mynote. A missing leading dot is added;
    // surrounding whitespace is removed and the extension is stored in lowercase.
    property Extension: UTF8String read FileExtension write SetExtension;
    // Human-readable document type name, such as My Notepad document.
    // Used by native registration metadata; this is not the application name.
    property Description: UTF8String read TypeDescription write TypeDescription;
    // Linux MIME type, such as application/x-my-notepad. Required on Linux.
    // Choose a stable type describing your file format rather than the application.
    property MimeType: UTF8String read MimeName write MimeName;
    // macOS document type identifier, such as org.example.notepad.document.
    // Required for generated macOS bundle metadata; keep it stable between releases.
    property TypeIdentifier: UTF8String read DocumentIdentifier write DocumentIdentifier;
    // macOS document role: farEditor (default), farViewer, or farNone.
    // This property does not change the user's default application.
    property Role: TFileAssRole read DocumentRole write DocumentRole default farEditor;
    // Optional .ico path or Windows icon resource reference, such as icons/note.ico
    // or an executable/resource path with an icon index. Relative paths resolve beside
    // the application executable; distribute the referenced file with your application.
    property WindowsIcon: UTF8String read WindowsIconPath write WindowsIconPath;
    // Optional SVG or 128-pixel PNG path, or an installed icon-theme name.
    // Relative file paths resolve beside the executable. FileAss installs file-based icons
    // for the MIME type; distribute the source icon with your application.
    property LinuxIcon: UTF8String read LinuxIconName write LinuxIconName;
    // Optional icon filename in the application bundle's Resources directory,
    // such as note.icns. Supply a filename, not a directory path.
    property MacIcon: UTF8String read MacIconName write MacIconName;
    // Optional arguments before the filename, such as --. FileAss appends the filename;
    // do not include %1, %f, or %F placeholders. All enabled Linux items must use
    // the same arguments because they share one desktop application entry.
    property OpenArguments: UTF8String read LaunchArguments write LaunchArguments;
  end;
  TFileAssTypeCollection = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TFileAssTypeItem;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TFileAssTypeItem;
    property Items[Index: Integer]: TFileAssTypeItem read GetItem; default;
  end;
implementation
constructor TFileAssTypeItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  TypeEnabled := True;
  DocumentRole := farEditor;
end;
procedure TFileAssTypeItem.SetExtension(const Value: UTF8String);
begin
  FileExtension := LowerCase(Trim(Value));
  if (FileExtension <> '') and (FileExtension[1] <> '.') then
    FileExtension := '.' + FileExtension;
end;
function TFileAssTypeItem.GetDisplayName: string;
begin
  if FileExtension = '' then Result := inherited GetDisplayName
  else Result := FileExtension;
end;
procedure TFileAssTypeItem.Assign(Source: TPersistent);
var Item: TFileAssTypeItem;
begin
  if not (Source is TFileAssTypeItem) then begin
    inherited Assign(Source);
    Exit;
  end;
  Item := TFileAssTypeItem(Source);
  TypeEnabled := Item.Enabled;
  Extension := Item.Extension;
  TypeDescription := Item.Description;
  MimeName := Item.MimeType;
  DocumentIdentifier := Item.TypeIdentifier;
  DocumentRole := Item.Role;
  WindowsIconPath := Item.WindowsIcon;
  LinuxIconName := Item.LinuxIcon;
  MacIconName := Item.MacIcon;
  LaunchArguments := Item.OpenArguments;
end;
constructor TFileAssTypeCollection.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TFileAssTypeItem);
end;
function TFileAssTypeCollection.Add: TFileAssTypeItem;
begin
  Result := TFileAssTypeItem(inherited Add);
end;
function TFileAssTypeCollection.GetItem(Index: Integer): TFileAssTypeItem;
begin
  Result := TFileAssTypeItem(inherited Items[Index]);
end;
end.
