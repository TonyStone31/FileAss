unit DemoMain;
{$mode objfpc}{$H+}{$codepage utf8}
interface

uses Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, FileAssMan, FileAssInstance, FAInstanceCore, FATypes;

type
  TDemoForm = class(TForm)
    ActionsPanel, UtilitiesPanel: TPanel;
    ValidateButton, RegisterButton, RemoveButton: TButton;
    GenerateButton, DefaultsButton: TButton;
    MenuEntry: TCheckBox;
    NoteIcon, SketchIcon: TImage;
    NoteLabel, SketchLabel, HintLabel, InstanceLabel: TLabel;
    FileAssMan: TFileAssMan;
    FileAssInstance: TFileAssInstance;
    Pages: TPageControl;
    ResultsTab, OpenedTab: TTabSheet;
    ResultsMemo, OpenedMemo: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure ValidateButtonClick(Sender: TObject);
    procedure RegisterButtonClick(Sender: TObject);
    procedure RemoveButtonClick(Sender: TObject);
    procedure GenerateButtonClick(Sender: TObject);
    procedure DefaultsButtonClick(Sender: TObject);
    procedure SampleIconClick(Sender: TObject);
    procedure StartupParameters(Sender: TObject; Parameters: TStrings; const WorkingDirectory: utf8string; Initial: boolean);
  private
    procedure Log(const Outcome: TFileAssResult; const SuccessText: string);
    procedure ShowRegistration(const ActionText: string = '');
    procedure ReceiveDocument(const FileName: string);
    function AssetPath(const RelativePath: string): string;
  end;

var
  DemoForm: TDemoForm;

implementation

uses LCLIntf, LazFileUtils;
  {$R *.lfm}

function TDemoForm.AssetPath(const RelativePath: string): string;
begin
  Result := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))) + RelativePath);
end;

procedure TDemoForm.Log(const Outcome: TFileAssResult; const SuccessText: string);
begin
  Pages.ActivePage := ResultsTab;
  if Outcome.Succeeded then ShowRegistration(SuccessText)
  else
    ShowRegistration(Outcome.Message);
end;

procedure TDemoForm.FormCreate(Sender: TObject);
begin
  // Secondary launches forward their parameters and terminate without a window.
  if FileAssInstance.Role <> firPrimary then Exit;
  FileAssMan.LinuxApplicationIcon := 'icons/blue-note.svg';
  if FileAssMan.ExecutablePath = '' then FileAssMan.ExecutablePath := ExpandFileName(ParamStr(0));
  MenuEntry.Enabled := FileAssHostTarget = fatLinux;
  MenuEntry.Checked := FileAssMan.ShowInApplicationMenu;
  case FileAssHostTarget of
    fatWindows: GenerateButton.Caption := 'Export Registry File (.reg)...';
    fatLinux: GenerateButton.Caption := 'Export Desktop, MIME & Icon Files...';
    fatMacOS: GenerateButton.Caption := 'Export Bundle Metadata (Info.plist)...';
    else
      GenerateButton.Enabled := False;
  end;
  NoteIcon.Picture.LoadFromFile(AssetPath('icons/blue-note.png'));
  SketchIcon.Picture.LoadFromFile(AssetPath('icons/amber-sketch.png'));

  ShowRegistration;
end;

procedure TDemoForm.ValidateButtonClick(Sender: TObject);
begin
  Log(FileAssMan.Validate, 'Registration check complete.');
end;

procedure TDemoForm.RegisterButtonClick(Sender: TObject);
begin
  FileAssMan.ShowInApplicationMenu := MenuEntry.Checked;
  Log(FileAssMan.RegisterAll, 'Demo file associations installed.');
end;

procedure TDemoForm.RemoveButtonClick(Sender: TObject);
begin
  Log(FileAssMan.UnregisterAll, 'Demo file associations removed.');
end;

procedure TDemoForm.ShowRegistration(const ActionText: string);
var
  Outcome: TFileAssResult;
  Status: TFileAssStatus;
begin
  ResultsMemo.Clear;
  if ActionText <> '' then
  begin
    ResultsMemo.Lines.Add(ActionText);
    ResultsMemo.Lines.Add('');
  end;
  Status := FileAssMan.GetRegistrationStatus(Outcome);
  case Status of
    fasFullyRegistered: ResultsMemo.Lines.Add('Registration: Installed');
    fasNotRegistered: ResultsMemo.Lines.Add('Registration: Not installed');
    fasPartiallyRegistered: ResultsMemo.Lines.Add('Registration: Incomplete');
    fasUnavailable: ResultsMemo.Lines.Add('Registration: Not supported on this system');
    fasVerificationFailed: ResultsMemo.Lines.Add('Registration: Could not verify');
  end;
  if not Outcome.Succeeded then ResultsMemo.Lines.Add(Outcome.Message);
  ResultsMemo.Lines.Add('');
  case Status of
    fasNotRegistered: ResultsMemo.Lines.Add('Next: Click Register File Types to install the demo associations.');
    fasFullyRegistered: begin
      ResultsMemo.Lines.Add('Next: Click a document icon, then double-click the selected sample.');
      ResultsMemo.Lines.Add('To change its default app, right-click the file and choose Open With.');
    end;
    fasPartiallyRegistered: ResultsMemo.Lines.Add('Next: Register again to repair missing resources.');
    else
      ResultsMemo.Lines.Add('Check the diagnostic above before registering.');
  end;
end;

procedure TDemoForm.GenerateButtonClick(Sender: TObject);
var
  OutputDirectory: string;
begin
  if not SelectDirectory('Choose an empty folder for association files', '', OutputDirectory) then Exit;
  FileAssMan.ShowInApplicationMenu := MenuEntry.Checked;
  Log(FileAssMan.GenerateDeploymentFiles(OutputDirectory),
    'Association files exported to ' + OutputDirectory);
end;

procedure TDemoForm.DefaultsButtonClick(Sender: TObject);
begin
  Log(FileAssMan.OpenDefaultAppsSettings, 'Default application settings opened.');
end;

procedure TDemoForm.SampleIconClick(Sender: TObject);
var
  Document: string;
begin
  if (Sender = NoteIcon) or (Sender = NoteLabel) then
    Document := 'documents/Blue note with spaces.fanote'
  else
    Document := 'documents/Amber café sketch.fasketch';
  if not SelectInFolder(AssetPath(Document)) then
    ShowMessage('Cannot show the sample document in the file manager.');
end;

procedure TDemoForm.ReceiveDocument(const FileName: string);
begin
  if not FileExists(FileName) then
  begin
    OpenedMemo.Lines.Add('File not found: ' + FileName);
  end
  else
    OpenedMemo.Lines.Add(ExpandFileName(FileName));
  Pages.ActivePage := OpenedTab;
end;

procedure TDemoForm.StartupParameters(Sender: TObject; Parameters: TStrings; const WorkingDirectory: utf8string; Initial: boolean);
var
  I: integer;
  AfterSeparator: boolean;
  FileName: string;
begin
  // The component sends both initial and forwarded launches to this handler.
  AfterSeparator := False;
  for I := 0 to Parameters.Count - 1 do
  begin
    FileName := Parameters[I];
    if FileName = '--' then
    begin
      AfterSeparator := True;
      Continue;
    end;
    if not AfterSeparator and (Copy(FileName, 1, 1) = '-') then Continue;
    if not FilenameIsAbsolute(FileName) then
      FileName := IncludeTrailingPathDelimiter(string(WorkingDirectory)) + FileName;
    ReceiveDocument(FileName);
  end;
end;

initialization
  RegisterClass(TFileAssMan);
  RegisterClass(TFileAssInstance);
end.
