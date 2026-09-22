@echo off
REM quick_scan.bat - Wrapper para chamar quick_scan.ps1 direto do cmd.exe.

if "%~1"=="" (
    echo Uso: quick_scan.bat ^<diretorio^> [-FailOn alto^|medio^|nunca]
    echo Exemplo: quick_scan.bat src\main\java -FailOn medio
    exit /b 2
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0quick_scan.ps1" %*
exit /b %ERRORLEVEL%
