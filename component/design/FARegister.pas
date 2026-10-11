unit FARegister;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, FileAssMan, ComponentEditors, FAComponentEditor, LResources;
procedure Register;
implementation
procedure Register;
begin
  RegisterComponents('FileAss', [TFileAssMan]);
  RegisterComponentEditor(TFileAssMan, TFileAssComponentEditor);
end;
initialization
  {$I resources/FileAssPalette.lrs}
end.
