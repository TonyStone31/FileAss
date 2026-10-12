unit FATypes;
{$mode objfpc}{$H+}{$codepage utf8}{$modeswitch advancedrecords}
interface

type
  TFileAssScope = (fasCurrentUser, fasAllUsers);
  TFileAssRole = (farEditor, farViewer, farNone);
  TFileAssTarget = (fatWindows, fatLinux, fatMacOS, fatUnavailable);
  TFileAssResultCode = (farSuccess, farPartialSuccess,
    farInvalidConfiguration, farPermissionDenied, farUnsupported,
    farRequiresDeployment, farNotFound, farOperationFailed);

  TFileAssResult = record
    Code: TFileAssResultCode;
    Message: utf8string;
    Extension: utf8string;
    NativeError: longint;
    function Succeeded: boolean;
  end;
  TFileAssStatus = (fasNotRegistered, fasFullyRegistered,
    fasPartiallyRegistered, fasUnavailable, fasVerificationFailed);
  TFileAssErrorEvent = procedure(Sender: TObject; const OperationResult: TFileAssResult) of object;

function FileAssResult(Code: TFileAssResultCode; const Message: utf8string; const Extension: utf8string = ''): TFileAssResult;
function FileAssHostTarget: TFileAssTarget;

implementation

function TFileAssResult.Succeeded: boolean;
begin
  Result := Code = farSuccess;
end;

function FileAssResult(Code: TFileAssResultCode; const Message: utf8string; const Extension: utf8string): TFileAssResult;
begin
  Result.Code := Code;
  Result.Message := Message;
  Result.Extension := Extension;
  Result.NativeError := 0;
end;

function FileAssHostTarget: TFileAssTarget;
begin
  {$if defined(windows)}
Result := fatWindows;
  {$elseif defined(darwin)}
Result := fatMacOS;
  {$elseif defined(linux)}
Result := fatLinux;
  {$else}
  Result := fatUnavailable;
  {$endif}
end;

end.
