; ============================================================================
;  XkScreen 星璨屏幕控制 - 一键安装包 (Inno Setup 6)
;
;  公开发布版（安装包内不含厂商组件，安装时从已装的原版软件复制）：
;     iscc installer\XkScreen.iss
;
;  个人自包含版（把厂商 DLL 直接打进安装包，双击即装好）：
;     iscc /DEmbedVendor=1 /DVendorDir="D:\path\to\official" installer\XkScreen.iss
;
;  安装内容: 驱动服务 + 网页控制台资源 + 桌面控制台 + 厂商组件副本(vendor\)
;            + 开机自启计划任务(SYSTEM) + 开始菜单/桌面快捷方式 + 卸载器
;  配置保留: C:\ProgramData\XkScreen\config.json 不随卸载删除
; ============================================================================

#define Version "0.4.1"

#ifdef EmbedVendor
  #define OutSuffix "-with-vendor"
#else
  #define OutSuffix ""
#endif

[Setup]
AppId={{7A3C5E10-9B4F-4C2A-9E6D-1F2A3B4C5D6E}
AppName=XkScreen 星璨屏幕控制
AppVersion={#Version}
AppVerName=XkScreen {#Version}
AppPublisher=Arimayuki03
AppPublisherURL=https://github.com/Arimayuki03/xkscreen
AppSupportURL=https://github.com/Arimayuki03/xkscreen
DefaultDirName={sd}\XkScreen
DefaultGroupName=XkScreen
DisableDirPage=yes
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\gui\XkScreen.Gui.exe
UninstallDisplayName=XkScreen 星璨屏幕控制
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=XkScreen-Setup-{#Version}{#OutSuffix}
SetupIconFile=..\product\XkScreen.Gui\appicon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=XkScreen 安装程序
SetupWindowTitle=XkScreen 星璨屏幕控制 - 安装
WelcomeLabel1=欢迎安装 XkScreen
WelcomeLabel2=即将在你的电脑上安装 XkScreen 星璨屏幕控制（屏幕驱动 + 可视化控制台）。%n%n安装程序将会：%n  · 部署驱动服务与网页控制台%n  · 从已安装的原版 SystemTemperatureMonitoring 复制必要组件%n  · 注册开机自启（计划任务）并立即点亮屏幕%n%n点击"下一步"继续。
WizardSelectDir=选择安装位置
SelectDirDesc=要把 XkScreen 安装到哪里？
SelectDirLabel3=安装程序将把 XkScreen 安装到以下文件夹。
SelectDirBrowseLabel=点击"下一步"继续；如需更改位置，请点击"浏览"。
WizardSelectTasks=选择附加任务
SelectTasksDesc=需要执行哪些附加任务？
SelectTasksLabel2=请选择安装 XkScreen 时要执行的附加任务，然后点击"下一步"。
WizardReady=准备安装
ReadyLabel1=安装程序已准备好开始安装 XkScreen。
ReadyLabel2a=点击"安装"开始安装；如需检查或更改设置，请点击"上一步"。
WizardInstalling=正在安装
InstallingLabel=正在安装 XkScreen，请稍候…
FinishedHeadingLabel=即将完成 XkScreen 安装
FinishedLabel=安装完成。屏幕驱动已启动。%n%n可从开始菜单或桌面打开控制台，或直接访问网页控制台：%nhttp://127.0.0.1:8899/
FinishedLabelNoIcons=安装完成。屏幕驱动已启动。%n%n网页控制台：http://127.0.0.1:8899/
ClickFinish=点击"完成"结束安装。
ButtonNext=下一步(&N) >
ButtonBack=< 上一步(&B)
ButtonInstall=安装(&I)
ButtonFinish=完成(&F)
ButtonCancel=取消
ButtonBrowse=浏览(&R)...
ButtonYes=是(&Y)
ButtonNo=否(&N)
ButtonOK=确定
ExitSetupTitle=退出安装
ExitSetupMessage=安装尚未完成，确定要退出吗？

; The two "additional tasks" live on a custom page (see [Code]) instead of the
; standard tasks page: Inno 6.7 draws that page's check boxes ~2 DIP too far
; left, so at 150% scaling their left edge is clipped away.

[Registry]
; Autostart of the console — the same HKCU Run value the console's own
; "开机自启" switch manages, so installer and app stay in sync.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "XkScreen"; ValueData: """{app}\gui\XkScreen.Gui.exe"""; Flags: uninsdeletevalue; Check: WantAutostart

[Files]
Source: "..\product\XkScreen.Service\bin\Release\net48\XkScreen.Service.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\product\frontend\out\*"; DestDir: "{app}\web"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\XkScreen.Gui.exe"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\XkScreen.Gui.dll"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\XkScreen.Gui.deps.json"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\XkScreen.Gui.runtimeconfig.json"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\Microsoft.Web.WebView2.Core.dll"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\Microsoft.Web.WebView2.WinForms.dll"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\Microsoft.Web.WebView2.Wpf.dll"; DestDir: "{app}\gui"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\runtimes\win-x64\native\WebView2Loader.dll"; DestDir: "{app}\gui\runtimes\win-x64\native"; Flags: ignoreversion
Source: "..\product\XkScreen.Gui\bin\Release\net8.0-windows\web\*"; DestDir: "{app}\gui\web"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "watch.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "watch.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "setup_tasks.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "service_host.cmd"; DestDir: "{app}"; Flags: ignoreversion
#ifdef EmbedVendor
Source: "{#VendorDir}\XKWLib.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\HardwareHelp64.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\TempComm.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\cpuidsdk.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\cpuidsdk64.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\Newtonsoft.Json.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
Source: "{#VendorDir}\System.Net.Http.dll"; DestDir: "{app}\vendor"; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\XkScreen 控制台"; Filename: "{app}\gui\XkScreen.Gui.exe"
Name: "{group}\网页控制台"; Filename: "http://127.0.0.1:8899/"
Name: "{group}\卸载 XkScreen"; Filename: "{uninstallexe}"
Name: "{autodesktop}\XkScreen 控制台"; Filename: "{app}\gui\XkScreen.Gui.exe"; Check: WantDesktopIcon

[Run]
Filename: "{app}\gui\XkScreen.Gui.exe"; Description: "立即启动 XkScreen 控制台"; Flags: postinstall nowait skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/End /TN ""XKScreenDriver"""; Flags: runhidden; RunOnceId: "taskEnd"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM XkScreen.Gui.exe /F"; Flags: runhidden; RunOnceId: "killGui"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM XkScreen.Service.exe /F"; Flags: runhidden; RunOnceId: "killService"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""XKScreenDriver"" /F"; Flags: runhidden; RunOnceId: "taskDelete"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""XKScreenDriverWatch"" /F"; Flags: runhidden; RunOnceId: "watchDelete"
; Uninstalling XkScreen returns the machine to its prior state: the original
; vendor service goes back to auto-start.
Filename: "{sys}\sc.exe"; Parameters: "config SystemTemperatureMonitoring start= auto"; Flags: runhidden; RunOnceId: "restoreVendor"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\vendor"
Type: filesandordirs; Name: "{app}\gui\XkScreen.Gui.exe.WebView2"
Type: files; Name: "{app}\xkscreen_service.log"

[Code]
const
  TASK_NAME = 'XKScreenDriver';
  WATCH_NAME = 'XKScreenDriverWatch';

var
  VendorDirFound: string;
  CbDesktop, CbStartup: TNewCheckBox;

function ReadAutostart: Boolean;
var
  V: String;
begin
  Result := RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Run', 'XkScreen', V);
end;

{ The "additional tasks" page. The standard tasks page cannot be used here: its
  check boxes are drawn ~2 DIP too far left and get clipped at non-100% DPI, so
  the left border of every box disappears. Real check box controls are drawn by
  the Windows theme and are unaffected. }
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
  { Keep a previous choice (e.g. a desktop icon the user deleted on purpose). }
  CbDesktop.Checked := not FileExists(
    ExpandConstant('{autodesktop}\XkScreen 控制台.lnk'));

  CbStartup := TNewCheckBox.Create(Page);
  CbStartup.Parent := Page.Surface;
  CbStartup.Caption := '开机时自动启动控制台';
  CbStartup.Left := 0;
  CbStartup.Top := ScaleY(66);
  CbStartup.Width := Page.SurfaceWidth;
  CbStartup.Height := ScaleY(24);
  { Mirror the console's own switch, so a re-install never silently flips it. }
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

function AddBS(const S: string): string;
begin
  Result := S;
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

{ Locate the original SystemTemperatureMonitoring installation (registry
  uninstall entries in both registry views, then the default path). }
function FindVendorDir: string;
var
  SubKeys: TArrayOfString;
  I: Integer;
  Display, Loc: string;
  Base: string;
begin
  Result := '';
  Base := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  if RegGetSubkeyNames(HKLM64, Base, SubKeys) then
    for I := 0 to GetArrayLength(SubKeys) - 1 do
      if RegQueryStringValue(HKLM64, Base + '\' + SubKeys[I], 'DisplayName', Display)
         and (Pos('SystemTemperatureMonitoring', Display) > 0)
         and RegQueryStringValue(HKLM64, Base + '\' + SubKeys[I], 'InstallLocation', Loc)
         and (Loc <> '') and FileExists(AddBS(Loc) + 'XKWLib.dll') then
      begin
        Result := AddBS(Loc);
        Exit;
      end;
  if RegGetSubkeyNames(HKLM32, Base, SubKeys) then
    for I := 0 to GetArrayLength(SubKeys) - 1 do
      if RegQueryStringValue(HKLM32, Base + '\' + SubKeys[I], 'DisplayName', Display)
         and (Pos('SystemTemperatureMonitoring', Display) > 0)
         and RegQueryStringValue(HKLM32, Base + '\' + SubKeys[I], 'InstallLocation', Loc)
         and (Loc <> '') and FileExists(AddBS(Loc) + 'XKWLib.dll') then
      begin
        Result := AddBS(Loc);
        Exit;
      end;
  if FileExists('C:\Program Files\SystemTemperatureMonitoring\XKWLib.dll') then
    Result := 'C:\Program Files\SystemTemperatureMonitoring\';
end;

function HasNet8Desktop: Boolean;
var
  FindRec: TFindRec;
begin
  Result := False;
  if FindFirst(ExpandConstant('{commonpf}\dotnet\shared\Microsoft.WindowsDesktop.App\8.*'), FindRec) then
  begin
    Result := True;
    FindClose(FindRec);
  end;
end;

function HasWebView2: Boolean;
var
  Pv: string;
begin
  Result :=
    RegQueryStringValue(HKLM32, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Pv) or
    RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Pv);
end;

function InitializeSetup: Boolean;
begin
  Result := True;
#ifndef EmbedVendor
  VendorDirFound := FindVendorDir;
  if VendorDirFound = '' then
  begin
    if MsgBox('未找到原版 SystemTemperatureMonitoring（星璨屏幕工具）的安装目录。' + #13#10 +
              'XkScreen 需要复用它的屏幕通信与传感器组件。' + #13#10 + #13#10 +
              '建议先安装原版软件，然后重新运行本安装包。' + #13#10 +
              '现在仍然继续安装吗？（屏幕在补装原版前将无法工作）',
              mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
      Exit;
    end;
  end;
#endif
  if not HasNet8Desktop then
    MsgBox('未检测到 .NET 8 桌面运行时，桌面控制台需要它。' + #13#10 +
           '下载：https://dotnet.microsoft.com/download/dotnet/8.0' + #13#10 +
           '（网页控制台不受影响）', mbInformation, MB_OK);
  if not HasWebView2 then
    MsgBox('未检测到 WebView2 运行时，桌面控制台需要它。' + #13#10 +
           '下载：https://developer.microsoft.com/microsoft-edge/webview2/' + #13#10 +
           '（网页控制台不受影响）', mbInformation, MB_OK);
end;

{ Stop any running instance (upgrade path) so files can be replaced. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  R: Integer;
begin
  Exec(ExpandConstant('{sys}\schtasks.exe'), '/End /TN "' + TASK_NAME + '"', '', SW_HIDE, ewWaitUntilTerminated, R);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM XkScreen.Gui.exe /F', '', SW_HIDE, ewWaitUntilTerminated, R);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM XkScreen.Service.exe /F', '', SW_HIDE, ewWaitUntilTerminated, R);
  Sleep(900);
  Result := '';
end;

procedure CopyVendorFiles;
var
  I: Integer;
  Names: array[0..6] of string;
  Src: string;
begin
  Names[0] := 'XKWLib.dll';
  Names[1] := 'HardwareHelp64.dll';
  Names[2] := 'TempComm.dll';
  Names[3] := 'cpuidsdk.dll';
  Names[4] := 'cpuidsdk64.dll';
  Names[5] := 'Newtonsoft.Json.dll';
  Names[6] := 'System.Net.Http.dll';
  if VendorDirFound = '' then Exit;
  ForceDirectories(ExpandConstant('{app}\vendor'));
  for I := 0 to 6 do
  begin
    Src := VendorDirFound + Names[I];
    if FileExists(Src) then
      CopyFile(Src, ExpandConstant('{app}\vendor\' + Names[I]), False);
  end;
end;

procedure WriteVendorConfig;
var
  Cfg: string;
begin
  ForceDirectories(ExpandConstant('{app}\vendor'));
  Cfg := '[config]' + #13#10 +
         'fefresh_delay=500' + #13#10 +
         'send_delay=500' + #13#10 +
         'IsLog=True' + #13#10 +
         'localPort=8890' + #13#10 +
         'LogPath=' + ExpandConstant('{app}\vendor') + #13#10 +
         'IsUdp=True' + #13#10;
  SaveStringToFile(ExpandConstant('{app}\vendor\config.ini'), Cfg, False);
end;

procedure RegisterAndStartTask;
var
  R: Integer;
  Bat: string;
begin
  { Task creation goes through a batch file: cmd parses the quoting and the
    exact schtasks form used here is verified working on this platform (the
    Task Scheduler rejects spaced+quoted /TR values, so the app lives in a
    no-space path and the batch logs every step to setup_tasks.log). }
  Bat := ExpandConstant('{app}\setup_tasks.cmd');
  if not Exec(ExpandConstant('{cmd}'), '/c "' + Bat + '"', '', SW_HIDE, ewWaitUntilTerminated, R) then
    MsgBox('注册计划任务失败：无法运行 setup_tasks.cmd。', mbError, MB_OK);
end;

procedure StopRunningDriver;
var
  R: Integer;
begin
  { An upgrade installs over a machine where the previous driver is still
    running: it holds 127.0.0.1:8899 and the USB panel, so starting the freshly
    registered task would create a second instance fighting it for the device.
    Stop both processes before Setup replaces the files. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM XkScreen.Service.exe /F', '', SW_HIDE, ewWaitUntilTerminated, R);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM XkScreen.Gui.exe /F', '', SW_HIDE, ewWaitUntilTerminated, R);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    StopRunningDriver;
  if CurStep = ssPostInstall then
  begin
#ifndef EmbedVendor
    CopyVendorFiles;
#endif
    WriteVendorConfig;
    RegisterAndStartTask;
  end;
end;
