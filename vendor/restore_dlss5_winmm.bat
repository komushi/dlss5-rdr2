@echo off
REM =====================================================================
REM  RESTORE_DLSS5 - remove OptiScaler DLSS5 Neural Rendering from
REM  Red Dead Redemption 2 (Epic / game root)
REM  Target: C:\Program Files\Epic Games\RedDeadRedemption2
REM
REM  Companion launcher for restore_dlss5_winmm.ps1. Real work is in the .ps1.
REM  Restores the real System32 winmm.dll (no .original backup existed for RDR2).
REM  Right-click -> Run as administrator is recommended.
REM =====================================================================
setlocal
REM %~dp0 ends with a trailing backslash; strip it so the quoted arg can't
REM create a stray '"' (the closing quote would collide with the backslash).
set "TOOLDIR=%~dp0"
if "%TOOLDIR:~-1%"=="\" set "TOOLDIR=%TOOLDIR:~0,-1%"
set "PS1=%TOOLDIR%\restore_dlss5_winmm.ps1"
if not exist "%PS1%" (
    echo ERROR: restore_dlss5_winmm.ps1 not found next to this script.
    echo Place both files in the same folder.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" ( echo. & echo DONE: DLSS5 removed. RDR2 is back to its stock state. ) else ( echo. & echo FAILED with code %RC%. See messages above. )
pause
exit /b %RC%
