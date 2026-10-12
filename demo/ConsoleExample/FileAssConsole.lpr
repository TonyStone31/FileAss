program FileAssConsole;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, FACore, FATypes, FAInstanceCore;
type
  TConsoleReceiver = class
    procedure Parameters(Sender: TObject; Values: TStrings;
      const Directory: UTF8String; Initial: Boolean);
    procedure Error(Sender: TObject; const Outcome: TFileAssResult);
  end;
procedure TConsoleReceiver.Parameters(Sender: TObject; Values: TStrings;
  const Directory: UTF8String; Initial: Boolean);
var I: Integer;
begin
  WriteLn('Working directory: ', Directory);
  for I := 0 to Values.Count - 1 do WriteLn(Values[I]);
  Flush(Output);
end;
procedure TConsoleReceiver.Error(Sender: TObject; const Outcome: TFileAssResult);
begin WriteLn(StdErr, Outcome.Message); end;
procedure RunInstanceDemo(Listen: Boolean);
var Instance: TFileAssInstanceManager; Receiver: TConsoleReceiver; Args: TStringList;
begin
  Instance := TFileAssInstanceManager.Create(nil);
  Receiver := TConsoleReceiver.Create;
  Args := TStringList.Create;
  try
    Instance.ApplicationID := 'org.example.fileass.console';
    Instance.Mode := fimForwardParameters;
    Instance.OnParameters := @Receiver.Parameters;
    Instance.OnError := @Receiver.Error;
    if not Listen then FileAssStartupParameters(Args);
    case Instance.Start(Args, FileAssWorkingDirectory) of
      firPrimary: begin
        Instance.ReadyForParameters := True;
        if Listen then WriteLn('Listening for parameters. Press Ctrl+C to stop.');
        repeat
          Instance.Poll;
          if Listen then Sleep(20);
        until not Listen;
      end;
      firFailed: ExitCode := 1;
    end;
  finally Args.Free; Receiver.Free; Instance.Free; end;
end;
var Manager: TFileAssManager; Outcome: TFileAssResult; Action: UTF8String;
begin
  if ParamCount = 0 then begin
    WriteLn('Usage: FileAssConsole validate|register|remove|status|generate [output-directory]');
    WriteLn('       FileAssConsole listen');
    WriteLn('       FileAssConsole -- [parameters to deliver]');
    Exit;
  end;
  Action := UTF8String(ParamStr(1));
  if (Action = '--') or (Action = 'listen') then begin
    RunInstanceDemo(Action = 'listen');
    Exit;
  end;
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
