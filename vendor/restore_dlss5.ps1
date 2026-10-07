#Requires -Version 5.1
# =====================================================================
#  RESTORE_DLSS5.ps1 - remove OptiScaler DLSS5 (NR + MFG) hook from
#  Red Dead Redemption 2 (Epic) in:
#  C:\Program Files\Epic Games\RedDeadRedemption2
#
#  Run from restore_dlss5.bat. Non-destructive:
#   - Puts back the original dbghelp.dll from dbghelp.dll.original.
#   - Removes ONLY the files it wrote (manifest-driven) + nvngx_dlssnr.dll
#     + OptiScaler.ini + the .original backup.
#   - Leaves every other game file (rpf, .dll, settings) untouched.
#
#  If you only want to disable NR/MFG (keep OptiScaler installed), the
#  restore is unnecessary — just toggle the keys in OptiScaler.ini or use
#  the in-game overlay instead.
# =====================================================================
param(
    [Parameter(Mandatory=$false)]
    [string]$ToolDir,

    [Parameter(Mandatory=$false)]
    [string]$GameDir = 'C:\Program Files\Epic Games\RedDeadRedemption2',

    # Restore also reverts RDR2's system.xml (graphics settings) from the
    # .dlss5.bak the apply script made. Pass -SkipGameSettings to leave it.
    [switch]$SkipGameSettings
)

if ([string]::IsNullOrWhiteSpace($ToolDir)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $ToolDir = $PSScriptRoot
    } else {
        $ToolDir = (Get-Location).Path
    }
}

# The .bat wrapper passes "%~dp0", which ends in a backslash; wrapping it in
# quotes makes the closing quote collide with that backslash, so $ToolDir can
# arrive with a stray trailing '"' (e.g. "...\DLSS5-RDR2"). Normalise (drop
# trailing quotes and backslashes) so Test-Path works. Also tolerates a plain
# trailing backslash from a hand-run invocation.
$ToolDir = ($ToolDir.TrimEnd([char[]]@('"', '\'))).Trim()

$ErrorActionPreference = 'Stop'
function Fail { param([string]$m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Info { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }
function Ok   { param([string]$m) Write-Host "  OK  $m" -ForegroundColor Green }

$Proxy  = 'dbghelp.dll'
$Backup = "$Proxy.original"
$ManifestPath = Join-Path $GameDir '_dlss5_manifest.txt'

Write-Host '=== Restore Red Dead Redemption 2 (remove OptiScaler DLSS5) ===' -ForegroundColor Cyan
Write-Host "Game folder: $GameDir"
Write-Host ''

if (-not (Test-Path -LiteralPath $GameDir)) { Fail "Game folder not found: $GameDir" }

# --- 1. Restore the original dbghelp.dll ---------------------------------
$ProxyPath  = Join-Path $GameDir $Proxy
$BackupPath = Join-Path $GameDir $Backup
if (Test-Path -LiteralPath $ProxyPath) {
    if (Test-Path -LiteralPath $BackupPath) {
        Copy-Item -LiteralPath $BackupPath -Destination $ProxyPath -Force
        Ok "Restored original $Proxy from $Backup"
    } else {
        Write-Warning "Removing $Proxy but no $Backup exists to restore from. If the game needs it, reinstall/verify the game files."
    }
} else {
    Info "No $Proxy present - nothing to restore."
}

# --- 2. Remove the NR runtime + OptiScaler.ini + manifest-file set --------
$NrDll = Join-Path $GameDir 'nvngx_dlssnr.dll'
$Ini   = Join-Path $GameDir 'OptiScaler.ini'
foreach ($p in @($NrDll, $Ini)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Ok "Removed $(Split-Path $p -Leaf)" }
}

if (Test-Path -LiteralPath $ManifestPath) {
    $toRemove = @(Get-Content -LiteralPath $ManifestPath)
    foreach ($name in $toRemove) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $full = Join-Path $GameDir $name
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force; Ok "Removed $name" }
    }
    Remove-Item -LiteralPath $ManifestPath -Force
    Ok "Removed manifest"
} else {
    Info "No manifest found - skipping optional-file cleanup. (Manual: remove its config .dll files.)"
}

# --- 3. Remove the backup we created -------------------------------------
if (Test-Path -LiteralPath $BackupPath) {
    Remove-Item -LiteralPath $BackupPath -Force
    Ok "Removed backup $Backup"
}

# --- 4. Revert RDR2's graphics settings (if apply set them) --------------
if (-not $SkipGameSettings) {
    $SysXml = Join-Path $env:USERPROFILE 'Documents\Rockstar Games\Red Dead Redemption 2\Settings\system.xml'
    $SysBak = "$SysXml.dlss5.bak"
    if (Test-Path -LiteralPath $SysBak) {
        $proc = Get-Process RDR2 -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Warning "RDR2 is running (PID $($proc.Id)) - not restoring system.xml (the game overwrites it on exit). Close RDR2 and re-run restore."
        } else {
            Copy-Item -LiteralPath $SysBak -Destination $SysXml -Force
            Ok "Restored RDR2 system.xml from system.xml.dlss5.bak"
        }
    } else {
        Info "No RDR2 system.xml backup found - leaving it as-is."
    }
} else {
    Info "SkipGameSettings set - leaving RDR2's system.xml untouched."
}

Write-Host ''
Write-Host 'Done. RDR2 is back to stock.' -ForegroundColor Cyan
exit 0
