@echo off
REM Wrapper para chamar quick_scan.ps1 direto do cmd.exe, sem precisar lembrar
REM a sintaxe do PowerShell nem mudar a Execution Policy do sistema.
REM
REM Uso:
REM   scripts\quick_scan.bat <diretorio-alvo>

if "%~1"=="" (
    echo Uso: quick_scan.bat ^<diretorio-alvo^>
    echo Exemplo: quick_scan.bat src\main\java
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0quick_scan.ps1" %1
exit /b %ERRORLEVEL%
