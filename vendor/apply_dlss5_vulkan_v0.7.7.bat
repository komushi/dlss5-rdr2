@echo off
REM =====================================================================
REM  APPLY_DLSS5_VULKAN - install OptiScaler v0.7.7 DLSS5 Neural Rendering
REM  for Red Dead Redemption 2 (Epic / game root)
REM  Target: C:\Program Files\Epic Games\RedDeadRedemption2
REM  Renderer: VULKAN (winmm.dll proxy + E67DEE20 runtime)
REM
REM  This is a self-contained launcher. All real work is done by the
REM  companion apply_dlss5_vulkan_v0.7.7.ps1 in the same folder, invoked
REM  with the temporary folder passed as %1.
REM  Right-click -> Run as administrator is recommended.
REM =====================================================================
setlocal
REM %~dp0 ends with a trailing backslash; strip it so the quoted arg can't
REM create a stray '"' (the closing quote would collide with the backslash).
set "TOOLDIR=%~dp0"
if "%TOOLDIR:~-1%"=="\" set "TOOLDIR=%TOOLDIR:~0,-1%"
set "PS1=%TOOLDIR%\apply_dlss5_vulkan_v0.7.7.ps1"
if not exist "%PS1%" (
    echo ERROR: apply_dlss5_vulkan_v0.7.7.ps1 not found next to this script.
    echo Place both files in the same folder.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%TOOLDIR%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
    echo.
    echo DONE: DLSS5 applied - Vulkan renderer + E67DEE20 runtime.
    echo Launch RDR2 and press F2 to enable Neural Rendering.
) else (
    echo.
    echo FAILED with code %RC%. See messages above.
)
pause
exit /b %RC%
