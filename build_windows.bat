@echo off
setlocal enabledelayedexpansion

echo.
echo  ============================================
echo   Health Sprout -- Windows Build Script
echo  ============================================
echo.

REM ── Step 1: Check Python is available ──────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found.
    echo.
    echo Please install Python from https://python.org/downloads
    echo Make sure to check "Add Python to PATH" during install.
    echo.
    pause
    exit /b 1
)

echo [1/4] Python found.

REM ── Step 2: Install required packages ──────────────────────────────────────
echo [2/4] Installing packages (this may take a minute)...
pip install pyinstaller google-genai requests --quiet
if errorlevel 1 (
    echo [ERROR] Failed to install packages. Check your internet connection.
    pause
    exit /b 1
)
echo       Done.

REM ── Step 3: Build the executable ───────────────────────────────────────────
echo [3/4] Building HealthSprout.exe ...
echo       (This takes 1-3 minutes the first time)
echo.

pyinstaller ^
    --onefile ^
    --name "HealthSprout" ^
    --clean ^
    health_sprout_app.py

if errorlevel 1 (
    echo.
    echo [ERROR] Build failed. See output above for details.
    pause
    exit /b 1
)

REM ── Step 4: Copy exe to current folder ─────────────────────────────────────
echo [4/4] Copying HealthSprout.exe here...
copy /Y dist\HealthSprout.exe . >nul
echo.
echo  ============================================
echo   SUCCESS!  HealthSprout.exe is ready.
echo  ============================================
echo.
echo   HOW TO RUN:
echo   -----------
echo   1. Edit run_HealthSprout.bat in Notepad
echo   2. Paste your Gemini API key where shown
echo   3. Double-click run_HealthSprout.bat to launch
echo.
echo   Get your FREE API key at: https://aistudio.google.com/apikey
echo.
echo   NOTE: Windows may show a SmartScreen warning the first time.
echo   Click "More info" then "Run anyway" -- this is normal.
echo.

REM ── Clean up build artifacts ────────────────────────────────────────────────
echo Cleaning up build files...
if exist dist rmdir /s /q dist
if exist build rmdir /s /q build
if exist HealthSprout.spec del HealthSprout.spec

pause
