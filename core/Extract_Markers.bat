@echo off
title Insv Marker Extractor
cd /d "%~dp0"
PowerShell -NoProfile -ExecutionPolicy Bypass -File "get_markersV2.ps1" %*