program FileAssDemo;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, DemoMain;
begin
  RequireDerivedFormResource := True;
  Application.Initialize;
  Application.CreateForm(TDemoForm, DemoForm);
  Application.Run;
end.
