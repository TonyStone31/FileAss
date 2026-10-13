unit FACollection;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, FATypes;

type
  TFileAssTypeItem = class(TCollectionItem)
  private
    TypeEnabled: boolean;
    FileExtension, TypeDescription, MimeName, DocumentIdentifier: utf8string;
    WindowsIconPath, LinuxIconName, MacIconName, LaunchArguments: utf8string;
    DocumentRole: TFileAssRole;
    procedure SetExtension(const Value: utf8string);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    // False leaves this type out of the next RegisterAll or export. It does not
    // undo a registration already made.
    property Enabled: boolean read TypeEnabled write TypeEnabled default True;
    // Required. The extension, such as .mynote. It is kept in lowercase, and the
    // dot is added if you leave it off.
    property Extension: utf8string read FileExtension write SetExtension;
    // What a file of this type is called, such as My Notepad document. Not the
    // application's name.
    property Description: utf8string read TypeDescription write TypeDescription;
    // Required on Linux. The MIME type, such as application/x-my-notepad. Name it
    // for the file format and keep it the same from release to release.
    property MimeType: utf8string read MimeName write MimeName;
    // Required on macOS. The type identifier, such as org.example.notepad.document.
    // Keep it the same from release to release.
    property TypeIdentifier: utf8string read DocumentIdentifier write DocumentIdentifier;
    // macOS: whether the program edits these files (farEditor), only shows them
    // (farViewer), or neither (farNone).
    property Role: TFileAssRole read DocumentRole write DocumentRole default farEditor;
    // Windows: an .ico file such as icons/note.ico, or a resource reference like
    // C:\App\app.exe,1. A relative path is beside the executable. Ship the icon
    // with your program; it is used where it lies.
    property WindowsIcon: utf8string read WindowsIconPath write WindowsIconPath;
    // Linux: an SVG or 128-pixel PNG file, or the name of an icon in the theme.
    // A relative path is beside the executable. A file is copied into the icon
    // theme when the type is registered.
    property LinuxIcon: utf8string read LinuxIconName write LinuxIconName;
    // macOS: the icon's file name in the bundle's Resources, such as note.icns.
    // A name, not a path.
    property MacIcon: utf8string read MacIconName write MacIconName;
    // Arguments to pass before the filename, such as --. The filename is added
    // for you, so no %1 or %f. On Linux every type must use the same arguments,
    // because one desktop entry launches them all.
    property OpenArguments: utf8string read LaunchArguments write LaunchArguments;
  end;

  TFileAssTypeCollection = class(TOwnedCollection)
  private
    function GetItem(Index: integer): TFileAssTypeItem;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TFileAssTypeItem;
    property Items[Index: integer]: TFileAssTypeItem read GetItem; default;
  end;

implementation

constructor TFileAssTypeItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  TypeEnabled := True;
  DocumentRole := farEditor;
end;

procedure TFileAssTypeItem.SetExtension(const Value: utf8string);
begin
  FileExtension := LowerCase(Trim(Value));
  if (FileExtension <> '') and (FileExtension[1] <> '.') then
    FileExtension := '.' + FileExtension;
end;

function TFileAssTypeItem.GetDisplayName: string;
begin
  if FileExtension = '' then Result := inherited GetDisplayName
  else
    Result := FileExtension;
end;

procedure TFileAssTypeItem.Assign(Source: TPersistent);
var
  Item: TFileAssTypeItem;
begin
  if not (Source is TFileAssTypeItem) then
  begin
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

function TFileAssTypeCollection.GetItem(Index: integer): TFileAssTypeItem;
begin
  Result := TFileAssTypeItem(inherited Items[Index]);
end;

end.
