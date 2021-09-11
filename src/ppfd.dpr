program ppfd;

{$R 'manifest.res' 'manifest.rc'}
{%File 'ppfd.exe.manifest'}

uses
  Windows,
  Forms,
  Classes,
  Unit1 in 'Unit1.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  SetWindowLong(Application.Handle,GWL_EXSTYLE,WS_EX_TOOLWINDOW);
  Application.ShowMainForm := false;
  Application.CreateForm(TMainForm, MainForm);
  MainForm.Start;
  Application.Run;
end.
