program FileAssConsole;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, FACore, FATypes;
var Manager: TFileAssManager; Outcome: TFileAssResult; Action, FileName: UTF8String;
  I: Integer;
begin
  if (ParamCount > 0) and (ParamStr(1) = '--') then begin
    for I := 2 to ParamCount do begin
      FileName := ParamStr(I);
      if FileExists(UTF8Decode(FileName)) then WriteLn(FileName);
    end;
    Halt(0);
  end;
  if ParamCount = 0 then begin
    WriteLn('Usage: FileAssConsole validate|register|remove|status|generate [output-directory]');
  end;
  if ParamCount = 0 then Halt(0);
  Manager := TFileAssManager.Create;
  try
    Manager.Configuration.ApplicationID := 'org.example.fileass.console';
    Manager.Configuration.ApplicationName := 'FileAss Console';
    with Manager.Configuration.FileTypes.Add do begin
      Extension := '.faconsolenote';
      Description := 'FileAss console document';
      MimeType := 'application/x-fileass-console-note';
      TypeIdentifier := 'org.example.fileass.console.note';
      OpenArguments := '--';
    end;
    Action := ParamStr(1);
    if Action = 'validate' then Outcome := Manager.Validate
    else if Action = 'register' then Outcome := Manager.RegisterAll
    else if Action = 'remove' then Outcome := Manager.UnregisterAll
    else if Action = 'status' then Manager.GetRegistrationStatus(Outcome)
    else if (Action = 'generate') and (ParamCount = 2) then begin
      Manager.Configuration.ExecutablePath := ExpandFileName(ParamStr(0));
      Outcome := Manager.GenerateDeploymentFiles(ParamStr(2));
    end else Outcome := FileAssResult(farInvalidConfiguration, 'Unknown action or missing output directory.');
    WriteLn(Outcome.Message);
    if not Outcome.Succeeded then ExitCode := 1;
  finally Manager.Free; end;
end.
