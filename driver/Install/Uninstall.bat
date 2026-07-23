@echo off
setlocal

:: Desinstala el filtro DirectShow de Unity Capture.
:: Busca las DLLs en varias ubicaciones (no viven en este directorio).

:: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

call :FindDll DLL32 "UnityCaptureFilter32.dll"
call :FindDll DLL64 "UnityCaptureFilter64.dll"

if "%DLL32%"=="" (
    echo.
    echo [ERROR] No se encontro UnityCaptureFilter32.dll.
    echo Desinstalacion abortada: regsvr32 necesita la DLL para registrar /u.
    echo Compila desktop_app o copia las DLLs junto a este .bat y reintenta.
    echo.
    pause
    exit /B 1
)

echo Uninstalling Unity Capture filter ...
regsvr32 /u "%DLL32%"
regsvr32 /u "%DLL64%"
echo Done.
goto :EOF

:FindDll
    set "%1="
    if exist "%~dp0%2"            ( set "%1=%~dp0%2"         & goto :EOF )
    for %%C in (Debug Release) do (
        for %%P in (
            "%~dp0..\..\desktop_app\bin\%%C\net8.0-windows10.0.19041.0\%2"
            "%~dp0..\..\desktop_app\bin\%%C\%2"
        ) do if exist %%P ( set "%1=%%~P" & goto :EOF )
    )
    if exist "%~dp0%2" ( set "%1=%~dp0%2" )
    goto :EOF
:--------------------------------------
