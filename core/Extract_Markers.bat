@echo off
title Insv Marker Extractor

:: Change directory to the shadow install folder
cd /d "%~dp0"

:: Pass all arguments (even if empty) to PowerShell
PowerShell -NoProfile -ExecutionPolicy Bypass -File "get_markersV2.ps1" %*