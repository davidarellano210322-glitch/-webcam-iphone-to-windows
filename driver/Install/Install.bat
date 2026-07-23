@echo off
setlocal

:: Instala el filtro DirectShow de Unity Capture (cámara virtual de NeoCamo).
:: Busca las DLLs en varias ubicaciones conocidas porque NO viven en este
:: directorio: se generan al compilar la app de escritorio (desktop_app).

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
    echo Compila desktop_app primero:  dotnet build desktop_app\desktop_app.csproj -c Release
    echo Las DLLs se generan en desktop_app\bin\Debug\net8.0-windows10.0.19041.0\
    echo Copia las DLLs junto a este .bat, o reejecuta este script tras compilar.
    echo.
    pause
    exit /B 1
)

echo Instalando filtro Unity Capture...
echo   32-bit: %DLL32%
echo   64-bit: %DLL64%
regsvr32 "%DLL32%"
regsvr32 "%DLL64%"
echo Done.
goto :EOF

:: ---------------------------------------------------------------
:: Busca una DLL en orden de preferencia y deja su ruta completa
:: en la variable cuyo nombre se pasa como primer argumento.
::   %1  = nombre de la variable de salida
::   %2  = nombre del archivo a localizar
:: ---------------------------------------------------------------
:FindDll
    set "%1="
    if exist "%~dp0%2"            ( set "%1=%~dp0%2"         & goto :EOF )
    :: Output de build de desktop_app (Debug y Release)
    for %%C in (Debug Release) do (
        for %%P in (
            "%~dp0..\..\desktop_app\bin\%%C\net8.0-windows10.0.19041.0\%2"
            "%~dp0..\..\desktop_app\bin\%%C\%2"
        ) do if exist %%P ( set "%1=%%~P" & goto :EOF )
    )
    :: Mismo directorio que el script sin subcarpeta (fallback)
    if exist "%~dp0%2" ( set "%1=%~dp0%2" )
    goto :EOF
:--------------------------------------
