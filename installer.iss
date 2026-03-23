; Inno Setup 脚本 - 应用安装程序
; 使用方法：用 Inno Setup 打开此文件，点击编译即可生成安装包

#define MyAppName "PsyGo"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#define MyAppPublisher "PsyGo Team"
#define MyAppURL "https://psygo.app"
#define MyAppExeName "psygo.exe"
#define VcRedistExeName "VC_redist.x64.exe"
#define BuildOutputDir "build\windows\x64\runner\Release"
#define IconFilePath "assets\logo.ico"

#if !FileExists(AddBackslash(BuildOutputDir) + MyAppExeName)
  #error "psygo.exe not found. Run flutter build windows --release first."
#endif

#if !FileExists(IconFilePath)
  #error "assets\\logo.ico not found."
#endif

#if !FileExists(VcRedistExeName)
  #error "VC_redist.x64.exe not found in project root."
#endif


[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; 安装目录（使用纯英文路径，避免中文用户名导致崩溃）
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

; 输出设置
OutputDir=installer_output
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersion}
SetupIconFile={#IconFilePath}
UninstallDisplayIcon={app}\logo.ico

; 压缩设置（lzma2 压缩率最高）
Compression=lzma2
SolidCompression=yes

; 权限设置
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
UsePreviousPrivileges=no

; 界面设置
WizardStyle=modern
DisableProgramGroupPage=yes
ShowLanguageDialog=yes
UsePreviousLanguage=no
LanguageDetectionMethod=uilanguage

; 64位设置
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible


[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"


[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; 主程序及运行依赖（包含插件 DLL、data 等）
Source: "{#BuildOutputDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 图标文件（用于快捷方式/卸载显示）
Source: "{#IconFilePath}"; DestDir: "{app}"; Flags: ignoreversion
; VC++ 运行库（必带，避免目标机器缺依赖）
Source: "{#VcRedistExeName}"; DestDir: "{tmp}"; Flags: deleteafterinstall
[Icons]
; 开始菜单快捷方式
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\logo.ico"; AppUserModelID: "com.psygo.app"
; 桌面快捷方式
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\logo.ico"; Tasks: desktopicon; AppUserModelID: "com.psygo.app"

[Run]
; 安装 VC++ 运行库（仅在未安装时执行）
Filename: "{tmp}\{#VcRedistExeName}"; Parameters: "/install /quiet /norestart"; StatusMsg: "正在安装 Visual C++ 运行库..."; Flags: waituntilterminated; Check: NeedsVCRedist
; 安装完成后运行程序
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; Check: CanLaunchApp

[Code]
function IsVCRedistInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result := False;

  if RegQueryDWordValue(
    HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed',
    Installed
  ) then
  begin
    Result := Installed = 1;
  end;
end;

function NeedsVCRedist: Boolean;
begin
  Result := not IsVCRedistInstalled;
end;

function CanLaunchApp: Boolean;
begin
  Result := IsVCRedistInstalled;
end;

function ContainsNonAscii(const S: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
  begin
    if Ord(S[I]) > 127 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  InstallDir: string;
begin
  Result := True;

  if CurPageID = wpSelectDir then
  begin
    InstallDir := WizardDirValue;
    if ContainsNonAscii(InstallDir) then
    begin
      MsgBox(
        '安装路径不能包含中文或其他非英文字符，请选择纯英文路径（例如 C:\Program Files\{#MyAppName}）。',
        mbError,
        MB_OK
      );
      Result := False;
    end;
  end;
end;
