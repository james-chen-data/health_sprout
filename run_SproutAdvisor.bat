@echo off
REM ============================================================
REM  SproutAdvisor Launcher
REM  Edit line below to add your API key (one time only),
REM  then double-click this file to launch the advisor.
REM ============================================================

REM  ↓↓↓  PASTE YOUR KEY BETWEEN THE QUOTES BELOW  ↓↓↓
set GEMINI_API_KEY=PASTE_YOUR_KEY_HERE

REM  ↑↑↑  GET YOUR FREE KEY AT: https://aistudio.google.com/apikey  ↑↑↑

if "%GEMINI_API_KEY%"=="PASTE_YOUR_KEY_HERE" (
    echo.
    echo  Please edit run_SproutAdvisor.bat and paste your Gemini API key.
    echo  Get a free key at: https://aistudio.google.com/apikey
    echo.
    pause
    exit /b
)

HealthSprout.exe
