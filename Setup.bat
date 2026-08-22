@echo off
title Insv Marker Extractor - Setup
echo ==================================================
echo         Insv Marker Extractor Setup
echo ==================================================
echo.

:: Define the shadow installation directory
set "INSTALL_DIR=%LOCALAPPDATA%\Insv_Marker_Extractor"

echo [*] Creating installation directory at:
echo     %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [*] Copying core files...
copy /y "%~dp0core\get_markersV2.ps1" "%INSTALL_DIR%\" > nul
copy /y "%~dp0core\Extract_Markers.bat" "%INSTALL_DIR%\" > nul

:: Move operation context to the shadow folder
cd /d "%INSTALL_DIR%"

if exist "insvtools.exe" (
    echo [*] insvtools.exe already exists. Skipping download.
) else (
    echo [*] Downloading insvtools from GitHub...
    curl -L -o temp_insvtools.zip "https://github.com/alex-plekhanov/insvtools/releases/download/v.1.2/insvtools-native-win-1.2.zip"
    
    if not exist "temp_insvtools.zip" (
        echo.
        echo [!] ERROR: Download failed. Check your internet connection.
        pause
        exit /b
    )

    echo [*] Extracting files...
    tar -xf temp_insvtools.zip

    echo [*] Organizing dependencies...
    move /y "insvtools-native-1.2\insvtools.exe" . > nul
    move /y "insvtools-native-1.2\LICENSE" . > nul

    echo [*] Cleaning up temporary files...
    del /q temp_insvtools.zip
    rmdir /s /q "insvtools-native-1.2"
)

echo [*] Creating Desktop shortcut...
set "SHORTCUT_PATH=%USERPROFILE%\Desktop\Insv Marker Extractor.lnk"
set "TARGET_PATH=%INSTALL_DIR%\Extract_Markers.bat"
set "WORK_DIR=%INSTALL_DIR%"

:: Invoke PowerShell silently to build the .lnk shortcut file
powershell -NoProfile -Command "$wshell = New-Object -ComObject WScript.Shell; $shortcut = $wshell.CreateShortcut('%SHORTCUT_PATH%'); $shortcut.TargetPath = '%TARGET_PATH%'; $shortcut.WorkingDirectory = '%WORK_DIR%'; $shortcut.Save()"

echo.
echo ==================================================
echo [OK] INSTALLATION COMPLETE!
echo ==================================================
echo.
echo INSTALL LOCATION: 
echo %INSTALL_DIR%
echo.
echo HOW TO USE:
echo A shortcut named "Insv Marker Extractor" has been created on your Desktop.
echo Do NOT double-click the shortcut. Simply drag and drop your .insv files, 
echo .lrv files, or a folder containing them directly onto the shortcut icon.
echo.
echo You can now safely close this window and delete the downloaded setup files.
echo ==================================================
echo.
pause