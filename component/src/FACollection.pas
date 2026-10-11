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
    property Enabled: Boolean read TypeEnabled write TypeEnabled default True;
    property Extension: UTF8String read FileExtension write SetExtension;
    property Description: UTF8String read TypeDescription write TypeDescription;
    property MimeType: UTF8String read MimeName write MimeName;
    property TypeIdentifier: UTF8String read DocumentIdentifier write DocumentIdentifier;
    property Role: TFileAssRole read DocumentRole write DocumentRole default farEditor;
    property WindowsIcon: UTF8String read WindowsIconPath write WindowsIconPath;
    property LinuxIcon: UTF8String read LinuxIconName write LinuxIconName;
    property MacIcon: UTF8String read MacIconName write MacIconName;
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
