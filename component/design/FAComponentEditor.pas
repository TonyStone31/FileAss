unit FAComponentEditor;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, ComponentEditors;

type
  TFileAssComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: integer; override;
    function GetVerb(Index: integer): string; override;
    procedure ExecuteVerb(Index: integer); override;
  end;

implementation

uses Forms, Controls, StdCtrls, Dialogs, PropEdits, FileAssMan, FATypes;

function TFileAssComponentEditor.GetVerbCount: integer;
begin
  Result := 5;
end;

function TFileAssComponentEditor.GetVerb(Index: integer): string;
begin
  case Index of
    0: Result := 'Edit File Types...';
    1: Result := 'Validate Configuration...';
    2: Result := 'Preview Native Registration...';
    3: Result := 'Generate Deployment Files...';
    4: Result := 'About FileAss...';
    else
      Result := '';
  end;
end;

procedure TFileAssComponentEditor.ExecuteVerb(Index: integer);
var
  Manager: TFileAssMan;
  Outcome: TFileAssResult;
  DirectoryDialog: TSelectDirectoryDialog;
  PreviewForm: TForm;
  Memo: TMemo;
  Text: TStringList;
begin
  Manager := TFileAssMan(Component);
  case Index of
    0: EditCollection(Manager, Manager.FileTypes, 'FileTypes');
    1: begin
      Outcome := Manager.Validate;
      ShowMessage(Outcome.Message);
    end;
    2: begin
      Text := TStringList.Create;
      try
        Outcome := Manager.PreviewNativeRegistration(Text);
        if not Outcome.Succeeded then
        begin
          ShowMessage(Outcome.Message);
          Exit;
        end;
        PreviewForm := TForm.CreateNew(nil);
        try
          PreviewForm.Caption := 'FileAss Native Registration Preview';
          PreviewForm.SetBounds(0, 0, 800, 560);
          PreviewForm.Position := poScreenCenter;
          Memo := TMemo.Create(PreviewForm);
          Memo.Parent := PreviewForm;
          Memo.Align := alClient;
          Memo.ReadOnly := True;
          Memo.WordWrap := False;
          Memo.ScrollBars := ssAutoBoth;
          Memo.Lines.Assign(Text);
          PreviewForm.ShowModal;
        finally
          PreviewForm.Free;
        end;
      finally
        Text.Free;
      end;
    end;
    3: begin
      DirectoryDialog := TSelectDirectoryDialog.Create(nil);
      try
        DirectoryDialog.Title := 'Choose an empty deployment output directory';
        if DirectoryDialog.Execute then
        begin
          Outcome := Manager.GenerateDeploymentFiles(DirectoryDialog.FileName);
          ShowMessage(Outcome.Message);
        end;
      finally
        DirectoryDialog.Free;
      end;
    end;
    4: ShowMessage('FileAss' + LineEnding + 'Copyright (c) 2026 Tony Stone' + LineEnding + '0BSD license' + LineEnding +
        'Available handlers are registered without replacing user defaults.');
  end;
end;

end.
