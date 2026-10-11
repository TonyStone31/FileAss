unit DemoMain;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Grids, FileAssMan, FATypes, FAInspection;
type
  TDemoForm = class(TForm)
    ActionsPanel, UtilitiesPanel: TPanel;
    ValidateButton, RegisterButton, RemoveButton, RefreshButton: TButton;
    GenerateButton, DefaultsButton: TButton;
    NoteIcon, SketchIcon: TImage;
    NoteLabel, SketchLabel, HintLabel, FilterLabel: TLabel;
    FileAssMan: TFileAssMan;
    Pages: TPageControl;
    ResultsTab, SystemTab, OpenedTab: TTabSheet;
    ResultsMemo, OpenedMemo: TMemo;
    BrowserPanel: TPanel;
    FilterEdit: TEdit;
    DemoOnly: TCheckBox;
    TypesGrid: TStringGrid;
    OutputDialog: TSelectDirectoryDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ValidateButtonClick(Sender: TObject);
    procedure RegisterButtonClick(Sender: TObject);
    procedure RemoveButtonClick(Sender: TObject);
    procedure RefreshButtonClick(Sender: TObject);
    procedure GenerateButtonClick(Sender: TObject);
    procedure DefaultsButtonClick(Sender: TObject);
    procedure SampleIconClick(Sender: TObject);
    procedure FilterChanged(Sender: TObject);
    procedure DocumentsDropped(Sender: TObject; const FileNames: array of string);
  private
    SystemTypes: TStringList;
    LastAction: string;
    procedure Log(const Outcome: TFileAssResult; const SuccessText: string);
    procedure RefreshRegistrations;
    procedure FillGrid;
    procedure ReceiveDocument(const FileName: string);
    function AssetPath(const RelativePath: string): string;
  end;
var DemoForm: TDemoForm;
implementation
uses LCLIntf;
{$R *.lfm}
function TDemoForm.AssetPath(const RelativePath: string): string;
begin
  Result := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0))) + RelativePath);
end;
procedure TDemoForm.Log(const Outcome: TFileAssResult; const SuccessText: string);
begin
  if Outcome.Succeeded then LastAction := SuccessText
  else if Outcome.Code = farPartialSuccess then LastAction := 'Needs attention: ' + Outcome.Message
  else LastAction := 'Could not complete the action: ' + Outcome.Message;
  RefreshRegistrations;
end;
procedure TDemoForm.FormCreate(Sender: TObject);
var I: Integer; AfterSeparator: Boolean;
begin
  SystemTypes := TStringList.Create;
  NoteIcon.Picture.LoadFromFile(AssetPath('icons/blue-note.png'));
  SketchIcon.Picture.LoadFromFile(AssetPath('icons/amber-sketch.png'));

  Application.AddOnDropFilesHandler(@DocumentsDropped);
  AfterSeparator := False;
  for I := 1 to ParamCount do begin
    if ParamStr(I) = '--' then begin AfterSeparator := True; Continue; end;
    if AfterSeparator or (Copy(ParamStr(I), 1, 1) <> '-') then ReceiveDocument(ParamStr(I));
  end;
  RefreshRegistrations;
end;
procedure TDemoForm.FormDestroy(Sender: TObject);
begin
  Application.RemoveOnDropFilesHandler(@DocumentsDropped);
  SystemTypes.Free;
end;
procedure TDemoForm.ValidateButtonClick(Sender: TObject);
begin
  Pages.ActivePage := ResultsTab;
  Log(FileAssMan.Validate, 'Registration check complete.');
end;
procedure TDemoForm.RegisterButtonClick(Sender: TObject);
begin
  Pages.ActivePage := ResultsTab;
  Log(FileAssMan.RegisterAll, 'Demo file associations installed.');
end;
procedure TDemoForm.RemoveButtonClick(Sender: TObject);
begin
  Pages.ActivePage := ResultsTab;
  Log(FileAssMan.UnregisterAll, 'Demo file associations removed.');
end;
procedure TDemoForm.RefreshButtonClick(Sender: TObject);
begin RefreshRegistrations; Pages.ActivePage := SystemTab; end;
procedure TDemoForm.RefreshRegistrations;
var Outcome: TFileAssResult; Status: TFileAssStatus; I: Integer; Handler: UTF8String;
begin
  ResultsMemo.Clear;
  if LastAction <> '' then begin
    ResultsMemo.Lines.Add(LastAction);
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
  ResultsMemo.Lines.Add('Double-click opens these files with:');
  for I := 0 to FileAssMan.FileTypes.Count - 1 do begin
    Handler := '';
    Outcome := FileAssDefaultHandler(FileAssMan.FileTypes[I].Extension,
      FileAssMan.FileTypes[I].MimeType, Handler);
    if Handler = '' then begin
      if Outcome.Succeeded or (Outcome.Code = farNotFound) then Handler := 'No default app selected'
      else Handler := Outcome.Message;
    end
    else if (Handler = FileAssMan.ApplicationID + '.desktop') or
      (Handler = FileAssMan.ApplicationID + FileAssMan.FileTypes[I].Extension) then
      Handler := FileAssMan.ApplicationName;
    ResultsMemo.Lines.Add('  ' + FileAssMan.FileTypes[I].Extension + '   →   ' + Handler);
  end;
  ResultsMemo.Lines.Add('');
  case Status of
    fasNotRegistered: ResultsMemo.Lines.Add('Next: Click Register File Types to install the demo associations.');
    fasFullyRegistered: begin
      ResultsMemo.Lines.Add('Next: Click a document icon, then double-click the selected sample.');
      ResultsMemo.Lines.Add('To change its default app, right-click the file and choose Open With.');
    end;
    fasPartiallyRegistered: ResultsMemo.Lines.Add('Next: Register again to repair missing resources.');
  end;
  Outcome := FileAssEnumerateTypes(SystemTypes);
  if not Outcome.Succeeded then begin
    ResultsMemo.Lines.Add('');
    ResultsMemo.Lines.Add('System file type list: ' + Outcome.Message);
  end;
  FillGrid;
end;
procedure TDemoForm.FillGrid;
var I, J, Row: Integer; Fields: TStringList; EntryText, Search: string; IncludeRow: Boolean;
begin
  TypesGrid.BeginUpdate;
  Fields := TStringList.Create;
  try
    Fields.Delimiter := #9;
    Fields.StrictDelimiter := True;
    Fields.QuoteChar := #0;
    TypesGrid.RowCount := 1;
    TypesGrid.Cells[0, 0] := 'Extension / filename rule';
    TypesGrid.Cells[1, 0] := 'MIME type / registered class';
    TypesGrid.Cells[2, 0] := 'Source';
    Search := LowerCase(FilterEdit.Text);
    Row := 1;
    for I := 0 to SystemTypes.Count - 1 do begin
      EntryText := SystemTypes[I];
      if (Search <> '') and (Pos(Search, LowerCase(EntryText)) = 0) then Continue;
      IncludeRow := not DemoOnly.Checked;
      if not IncludeRow then
        for J := 0 to FileAssMan.FileTypes.Count - 1 do
          if Pos(FileAssMan.FileTypes[J].Extension + #9, EntryText) > 0 then IncludeRow := True;
      if not IncludeRow then Continue;
      Fields.DelimitedText := EntryText;
      if Fields.Count < 3 then Continue;
      TypesGrid.RowCount := Row + 1;
      for J := 0 to 2 do TypesGrid.Cells[J, Row] := Fields[J];
      Inc(Row);
    end;
    if Row = 1 then begin
      TypesGrid.RowCount := 2;
      TypesGrid.Rows[1].Clear;
      TypesGrid.Cells[0, 1] := 'No matching registrations';
    end;
  finally Fields.Free; TypesGrid.EndUpdate; end;
end;
procedure TDemoForm.FilterChanged(Sender: TObject);
begin
  if Assigned(SystemTypes) then FillGrid;
end;
procedure TDemoForm.GenerateButtonClick(Sender: TObject);
var SavedPath: string;
begin
  if not OutputDialog.Execute then Exit;
  SavedPath := FileAssMan.ExecutablePath;
  try
    FileAssMan.ExecutablePath := ExpandFileName(ParamStr(0));
    Log(FileAssMan.GenerateDeploymentFiles(OutputDialog.FileName),
      'Installer resources saved to ' + OutputDialog.FileName);
  finally FileAssMan.ExecutablePath := SavedPath; end;
end;
procedure TDemoForm.DefaultsButtonClick(Sender: TObject);
var Outcome: TFileAssResult;
begin
  Outcome := FileAssMan.OpenDefaultAppsSettings;
  Log(Outcome, 'Default application settings opened.');
  if not Outcome.Succeeded then ShowMessage(Outcome.Message);
end;
procedure TDemoForm.SampleIconClick(Sender: TObject);
var Document: string;
begin
  if (Sender = NoteIcon) or (Sender = NoteLabel) then
    Document := 'documents/Blue note with spaces.fanote'
  else Document := 'documents/Amber café sketch.fasketch';
  if not SelectInFolder(AssetPath(Document)) then
    ShowMessage('Cannot show the sample document in the file manager.');
end;
procedure TDemoForm.ReceiveDocument(const FileName: string);
begin
  if not FileExists(FileName) then begin
    OpenedMemo.Lines.Add('File not found: ' + FileName);
    Pages.ActivePage := OpenedTab;
    Exit;
  end;
  OpenedMemo.Lines.Add(ExpandFileName(FileName));
  Pages.ActivePage := OpenedTab;
end;
procedure TDemoForm.DocumentsDropped(Sender: TObject; const FileNames: array of string);
var I: Integer;
begin
  for I := Low(FileNames) to High(FileNames) do ReceiveDocument(FileNames[I]);
end;
initialization
  RegisterClass(TFileAssMan);
end.
