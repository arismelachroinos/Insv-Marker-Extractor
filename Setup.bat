@echo off
title Insv Marker Extractor - Setup
echo ==================================================
echo             Insv Marker Extractor Setup
echo ==================================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\Insv_Marker_Extractor"

echo [*] Creating installation directory at:
echo     %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [*] Copying core files...
copy /y "%~dp0core\get_markersV2.ps1" "%INSTALL_DIR%\" > nul
copy /y "%~dp0core\Extract_Markers.bat" "%INSTALL_DIR%\" > nul

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

powershell -NoProfile -Command "$wshell = New-Object -ComObject WScript.Shell; $shortcut = $wshell.CreateShortcut('%SHORTCUT_PATH%'); $shortcut.TargetPath = '%TARGET_PATH%'; $shortcut.WorkingDirectory = '%WORK_DIR%'; $shortcut.Save()"

echo.
echo ==================================================
echo [OK] INSTALLATION COMPLETE!
echo ==================================================
echo.
echo HOW TO USE:
echo.
echo [METHOD 1: SIMPLE TIMESTAMP EXTRACTION]
echo Simply drag and drop your .insv/.lrv files (or a folder) directly onto the 
echo new Desktop shortcut. The console will print the marker timestamps.
echo.
echo [METHOD 2: COMPLETE STUDIO AUTO-KEYFRAMING]
echo 1. Open your footage in Insta360 Studio, frame your shots if you want (optionally add manual 
echo    keyframes to set your preferred camera angles), then close the app (close all of its windows).
echo 2. Drag and drop those same video files onto the Desktop shortcut.
echo 3. The script will inject the markers as keyframes, matching your angles.
echo 4. Re-open Insta360 Studio. Double-click your footage in the "Local Media"
echo    tab, and your markers will be fully editable keyframes on the timeline.
echo.
echo You can now safely close this window and delete this setup folder.
echo ==================================================
echo.
pause