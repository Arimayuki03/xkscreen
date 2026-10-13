; Layout check for the custom "附加任务" page used by XkScreen.iss.
; Non-elevated so it can be launched and captured without UAC.
; Compile: iscc /Q .tools/probe_tasks.iss
[Setup]
AppName=XkScreen Probe
AppVersion=1.0
DefaultDirName={sd}\XkProbe
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=probe_tasks_c
WizardStyle=modern
Compression=none
Uninstallable=no
CreateAppDir=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupWindowTitle=XkScreen Probe - 安装

[Icons]
Name: "{autodesktop}\XkScreen 控制台"; Filename: "{app}\probe.exe"; Check: WantDesktopIcon

[Code]
var
  CbDesktop, CbStartup: TNewCheckBox;

function ReadAutostart: Boolean;
var
  V: String;
begin
  Result := RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Run', 'XkScreen', V);
end;

procedure InitializeWizard;
var
  Page: TWizardPage;
  Lbl: TNewStaticText;
begin
  Page := CreateCustomPage(wpSelectTasks, '选择附加任务', '需要执行哪些附加任务？');

  Lbl := TNewStaticText.Create(Page);
  Lbl.Parent := Page.Surface;
  Lbl.Left := 0;
  Lbl.Top := 0;
  Lbl.Width := Page.SurfaceWidth;
  Lbl.Height := ScaleY(30);
  Lbl.AutoSize := False;
  Lbl.WordWrap := True;
  Lbl.Caption := '请选择安装 XkScreen 时要执行的附加任务，然后点击"下一步"。';

  CbDesktop := TNewCheckBox.Create(Page);
  CbDesktop.Parent := Page.Surface;
  CbDesktop.Caption := '创建桌面快捷方式';
  CbDesktop.Left := 0;
  CbDesktop.Top := ScaleY(36);
  CbDesktop.Width := Page.SurfaceWidth;
  CbDesktop.Height := ScaleY(24);
  CbDesktop.Checked := True;

  CbStartup := TNewCheckBox.Create(Page);
  CbStartup.Parent := Page.Surface;
  CbStartup.Caption := '开机时自动启动控制台';
  CbStartup.Left := 0;
  CbStartup.Top := ScaleY(66);
  CbStartup.Width := Page.SurfaceWidth;
  CbStartup.Height := ScaleY(24);
  CbStartup.Checked := ReadAutostart;
end;

function WantDesktopIcon: Boolean;
begin
  Result := (CbDesktop <> nil) and CbDesktop.Checked;
end;

function WantAutostart: Boolean;
begin
  Result := (CbStartup <> nil) and CbStartup.Checked;
end;
