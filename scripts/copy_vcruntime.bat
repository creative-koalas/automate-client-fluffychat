@echo off
REM 复制 VC++ Runtime DLL 到 Release 目录
set RELEASE_DIR=%~dp0..\build\windows\x64\runner\Release

if not exist "%RELEASE_DIR%" (
    echo Release 目录不存在，请先运行 flutter build windows --release
    exit /b 1
)

echo 正在复制 VC++ Runtime DLL...
copy "%SystemRoot%\System32\vcruntime140.dll" "%RELEASE_DIR%\" >nul
copy "%SystemRoot%\System32\vcruntime140_1.dll" "%RELEASE_DIR%\" >nul
copy "%SystemRoot%\System32\msvcp140.dll" "%RELEASE_DIR%\" >nul

echo 完成！文件已复制到: %RELEASE_DIR%
pause
