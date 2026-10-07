#Requires -Version 5.1
# =====================================================================
#  RESTORE_DLSS5_v2.ps1 - remove OptiScaler DLSS5 from Red Dead Redemption 2 (Epic)
#  in: C:\Program Files\Epic Games\RedDeadRedemption2
#
#  WINMM-AWARE restore. The current RDR2 setup uses winmm.dll as the
#  OptiScaler proxy (the real proxy for RDR2). This restores true vanilla:
#    - Replaces the winmm.dll OptiScaler proxy with the real System32 winmm.dll
#    - Removes OptiScaler folder, OptiScaler.ini, nvngx_dlssnr.dll,
#      _dlss5_manifest.txt, OptiScaler.log
#    - Leaves nvngx_dlss.dll (stock 2.2.10) and game settings untouched
#    - Optionally reverts system.xml from the .dlss5-pre-dx12.bak
#
#  Non-destructive: backs up the proxy winmm.dll to winmm.dll.proxy-backup.
# =====================================================================
param(
    [string]$GameDir = 'C:\Program Files\Epic Games\RedDeadRedemption2',
    [switch]$SkipGameSettings
)

$ErrorActionPreference = 'Stop'
function Fail { param([string]$m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Info { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }
function Ok   { param([string]$m) Write-Host "  OK  $m" -ForegroundColor Green }

$Proxy    = 'winmm.dll'
$SysWinmm = 'C:\Windows\System32\winmm.dll'

Write-Host '=== Restore Red Dead Redemption 2 (remove OptiScaler DLSS5, winmm-aware) ===' -ForegroundColor Cyan
Write-Host "Game folder: $GameDir"
Write-Host ''

if (-not (Test-Path -LiteralPath $GameDir)) { Fail "Game folder not found: $GameDir" }

# --- 1. Restore the real Windows winmm.dll ------------------------------
$ProxyPath = Join-Path $GameDir $Proxy
$ProxyBak  = Join-Path $GameDir "$Proxy.proxy-backup"
if (Test-Path -LiteralPath $ProxyPath) {
    $size = (Get-Item -LiteralPath $ProxyPath).Length
    if ($size -gt 5000000) {
        # >5MB => it's the OptiScaler proxy, not the real (235KB) winmm.dll
        Copy-Item -LiteralPath $ProxyPath -Destination $ProxyBak -Force
        Ok "Backed up OptiScaler proxy -> $ProxyBak"
        if (Test-Path -LiteralPath $SysWinmm) {
            Copy-Item -LiteralPath $SysWinmm -Destination $ProxyPath -Force
            $v = (Get-Item -LiteralPath $ProxyPath).VersionInfo
            Ok "Restored real winmm.dll (ver $($v.FileVersion))"
        } else {
            Remove-Item -LiteralPath $ProxyPath -Force
            Ok "Removed OptiScaler proxy winmm.dll (no System32 source to copy)"
        }
    } else {
        Info "winmm.dll is already the real Windows DLL (size $size) - nothing to restore."
    }
} else {
    Info "No winmm.dll present - nothing to restore."
}

# --- 2. Remove NR runtime + OptiScaler.ini + manifest + log --------------
$NrDll   = Join-Path $GameDir 'nvngx_dlssnr.dll'
$Ini     = Join-Path $GameDir 'OptiScaler.ini'
$Log     = Join-Path $GameDir 'OptiScaler.log'
$Manifest= Join-Path $GameDir '_dlss5_manifest.txt'
foreach ($p in @($NrDll, $Ini, $Log)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Ok "Removed $(Split-Path $p -Leaf)" }
}

# --- 3. Remove the OptiScaler subfolder + manifest-listed files ----------
$OptiDir = Join-Path $GameDir 'OptiScaler'
if (Test-Path -LiteralPath $OptiDir) { Remove-Item -LiteralPath $OptiDir -Recurse -Force; Ok "Removed OptiScaler\ folder" }
if (Test-Path -LiteralPath $Manifest) {
    $toRemove = @(Get-Content -LiteralPath $Manifest)
    foreach ($name in $toRemove) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $full = Join-Path $GameDir $name
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force; Ok "Removed $name" }
    }
    Remove-Item -LiteralPath $Manifest -Force
    Ok "Removed manifest"
} else {
    Info "No manifest found - skipping optional-file cleanup."
}

# --- 4. Optionally revert RDR2 system.xml -------------------------------
if (-not $SkipGameSettings) {
    $SysXml = Join-Path $env:USERPROFILE 'Documents\Rockstar Games\Red Dead Redemption 2\Settings\system.xml'
    $SysBak = "$SysXml.dlss5-pre-dx12.bak"
    if (Test-Path -LiteralPath $SysBak) {
        $proc = Get-Process RDR2 -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Warning "RDR2 is running (PID $($proc.Id)) - not restoring system.xml. Close RDR2 and re-run."
        } else {
            Copy-Item -LiteralPath $SysBak -Destination $SysXml -Force
            Ok "Restored system.xml from system.xml.dlss5-pre-dx12.bak"
        }
    } else {
        Info "No system.xml.dlss5-pre-dx12.bak found - leaving settings as-is."
    }
} else {
    Info "SkipGameSettings set - leaving system.xml untouched."
}

Write-Host ''
Write-Host 'Done. RDR2 is back to vanilla. You can now launch the game and switch to Vulkan.' -ForegroundColor Cyan
exit 0
