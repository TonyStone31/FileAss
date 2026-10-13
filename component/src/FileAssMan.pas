unit FileAssMan;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses FACore;

type
  { The component on the palette.  All of it is TFileAssManager in FACore,
    which a program with no forms can create for itself. }
  TFileAssMan = class(TFileAssManager)
  end;

implementation

end.
