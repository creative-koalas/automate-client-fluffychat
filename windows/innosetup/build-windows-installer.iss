; Psygo Setup (Admin + Program Files + Chinese + VC++ runtime)

#define MyAppName "Psygo"
#define MyAppVersion "1.0"
#define MyAppPublisher "创意考拉"
#define MyAppURL "https://psygoai.com"
#define MyAppExeName "psygo.exe"

#define MySourceDir "{#SourcePath}\..\..\..\build\windows\x64\runner\Release"
#define VCRedistSource "{#SourcePath}\..\VC_redist.x64.exe"
#define VCRedistFileName "VC_redist.x64.exe"
#define IconFilePath "{#SourcePath}\..\..\..\assets\logo_opaque.ico"

; ---- compile-time sanity checks (recommended) ----
#if !FileExists(AddBackslash(MySourceDir) + MyAppExeName)
  #error "psygo.exe not found. Check MySourceDir relative path from windows\\innosetup."
#endif

#if !FileExists(VCRedistSource)
  #error "VC_redist.x64.exe not found next to the .iss file."
#endif

[Setup]
AppId={{5E54E4CA-1605-418C-8FB2-9A0D5AE9869F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
SetupIconFile={#IconFilePath}

DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

DisableProgramGroupPage=yes

PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline

OutputBaseFilename=Psygo-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务"; Flags: checkedonce

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Copy redist into temp with its normal filename
Source: "{#VCRedistSource}"; DestDir: "{tmp}"; DestName: "{#VCRedistFileName}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; IMPORTANT: run the file *by its temp filename*, not the original source path
Filename: "{tmp}\{#VCRedistFileName}"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "正在安装运行库（Microsoft Visual C++ 2015-2022）..."; \
  Flags: waituntilterminated

Filename: "{app}\{#MyAppExeName}"; Description: "运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'),
      '/F /IM "{#MyAppExeName}" /T',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

