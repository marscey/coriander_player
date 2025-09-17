@echo off

REM Batch script to build desktop_lyric component
REM This script provides an easy way to run PowerShell script with build mode selection

REM Set code page for Chinese display
chcp 65001 >nul

REM Display welcome message
cls
echo ============================================================================
echo             Coriander Player - Desktop Lyric Build Helper
echo ============================================================================
echo.
echo This script will run build_desktop_lyric.ps1 to build and deploy desktop_lyric component
echo.

REM Prompt user for build mode selection
:SELECT_BUILD_MODE
echo Please select build mode:
echo 1. Release (default)
echo 2. Debug
set /p BUILD_MODE_CHOICE=Enter your choice (1-2) or press Enter for default: 

REM Validate user input
if "%BUILD_MODE_CHOICE%"=="" set BUILD_MODE_CHOICE=1
if "%BUILD_MODE_CHOICE%"=="1" set BUILD_MODE=Release
if "%BUILD_MODE_CHOICE%"=="2" set BUILD_MODE=Debug

REM Check if valid choice was made
if not defined BUILD_MODE (
echo Invalid choice. Please enter 1 or 2.
echo.
goto SELECT_BUILD_MODE
)

echo.
echo You have selected %BUILD_MODE% mode.
echo Press any key to start building...
pause >nul

REM Run PowerShell script with build mode parameter
echo.
echo Starting build process in %BUILD_MODE% mode, please wait...
powershell -ExecutionPolicy Bypass -File "%~dp0\build_desktop_lyric.ps1" -BuildMode %BUILD_MODE%

REM Check build result
if %ERRORLEVEL% EQU 0 (
    echo.
echo %BUILD_MODE% build succeeded! Press any key to exit.
) else (
    echo.
echo %BUILD_MODE% build failed! Please check error messages above.
echo Press any key to exit.
)
pause >nul