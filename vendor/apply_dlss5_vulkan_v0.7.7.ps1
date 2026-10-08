#Requires -Version 5.1
# =====================================================================
#  APPLY_DLSS5_VULKAN_v0.7.7.ps1 - install OptiScaler v0.7.7 + DLSS-NR into
#  Red Dead Redemption 2 (Epic) for the VULKAN renderer using the E67DEE20
#  cross-generation runtime (RTX 40 / Ada).
#
#  Target:  C:\Program Files\Epic Games\RedDeadRedemption2
#  Proxy:   winmm.dll  (the fork's documented proxy for VULKAN)
#  Runtime: nvngx_dlssnr.dll = E67DEE209320...989A (ShortFuse cross-gen 310.8, RTX40)
#
#  Run from apply_dlss5.bat. Param $ToolDir = where the .bat lives. The package
#  and runtime are located in this order:
#      package : <ToolDir>\vendor\OptiScaler-DLSSNR-v0.7.7.zip
#                <ToolDir>\OptiScaler-DLSSNR-v0.7.7.zip
#                C:\Windows\Temp\OptiScaler-DLSSNR-v0.7.7.zip
#      runtime : <ToolDir>\nvngx_dlssnr.dll
#                <ToolDir>\vendor\nvngx_dlssnr.dll
#                C:\Windows\Temp\nvngx_dlssnr.dll
#
#  Non-destructive: backs up the current winmm.dll proxy to winmm.dll.proxy-backup.
#  Leaves nvngx_dlss.dll (stock) and system.xml untouched. Idempotent.
#
#  NOTE: edits are section-scoped. The stock v0.7.7 INI contains many
#  'Enabled=auto' / 'Passes=auto' / 'WorkingScale=auto' keys in different
#  sections (FrameGen, DLSS, NvngxFG, DlssNr, ...). A blanket replace would
#  corrupt those, so each value is only changed inside its own section.
# =====================================================================
param(
    [Parameter(Mandatory=$false)]
    [string]$ToolDir,

    [Parameter(Mandatory=$false)]
    [string]$GameDir = 'C:\Program Files\Epic Games\RedDeadRedemption2'
)

$ErrorActionPreference = 'Stop'
function Fail { param([string]$m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Info { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }
function Ok   { param([string]$m) Write-Host "  OK  $m" -ForegroundColor Green }

# Resolve ToolDir like the Cyberpunk script (bat passes "%~dp0", may have a
# trailing backslash/quote).
if ([string]::IsNullOrWhiteSpace($ToolDir)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $ToolDir = $PSScriptRoot }
    else { $ToolDir = (Get-Location).Path }
}
$ToolDir = $ToolDir.TrimEnd('\', '"', ' ')

$Proxy     = 'winmm.dll'
$RuntimeSha= 'E67DEE209320CDAFE0E93E45675D7AA34323A53ACC57A72B2E40A181581C989A'

# ---- Locate package + runtime from $ToolDir (with fallback to Temp) ------
$PackageCandidates = @(
    (Join-Path $ToolDir 'vendor\OptiScaler-DLSSNR-v0.7.7.zip'),
    (Join-Path $ToolDir 'OptiScaler-DLSSNR-v0.7.7.zip'),
    'C:\Windows\Temp\OptiScaler-DLSSNR-v0.7.7.zip'
)
$RuntimeCandidates = @(
    (Join-Path $ToolDir 'nvngx_dlssnr.dll'),
    (Join-Path $ToolDir 'vendor\nvngx_dlssnr.dll'),
    'C:\Windows\Temp\nvngx_dlssnr.dll'
)
$Package = $PackageCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$Runtime = $RuntimeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Host '=== Apply OptiScaler v0.7.7 + DLSS-NR (VULKAN) to Red Dead Redemption 2 ===' -ForegroundColor Cyan
Write-Host "Tool dir: $ToolDir"
Write-Host "Game folder: $GameDir"
Write-Host ''

if (-not (Test-Path -LiteralPath $GameDir)) { Fail "Game folder not found: $GameDir" }
if (-not $Package) { Fail "Package not found. Looked in: $($PackageCandidates -join ', ')" }
if (-not $Runtime) { Fail "Runtime not found. Looked in: $($RuntimeCandidates -join ', ')" }
Info "Package: $Package"
Info "Runtime: $Runtime"

# --- 1. Verify runtime hash matches E67DEE20 ----------------------------
$actual = (Get-FileHash -LiteralPath $Runtime -Algorithm SHA256).Hash
if ($actual.ToUpper() -ne $RuntimeSha) {
    Fail "Runtime hash mismatch. Expected $RuntimeSha, got $actual"
}
Ok "Runtime verified: $($actual.Substring(0,8))... (E67DEE20)"

# --- 2. Check RDR2 is not running ---------------------------------------
$proc = Get-Process RDR2,PlayRDR2 -ErrorAction SilentlyContinue
if ($proc) { Fail "RDR2 is running (PID $($proc.Id)). Close the game first." }

# --- 3. Back up + clear current winmm.dll proxy -------------------------
$ProxyPath = Join-Path $GameDir $Proxy
$ProxyBak  = Join-Path $GameDir "$Proxy.proxy-backup"
if (Test-Path -LiteralPath $ProxyPath) {
    Copy-Item -LiteralPath $ProxyPath -Destination $ProxyBak -Force
    Ok "Backed up existing winmm.dll -> winmm.dll.proxy-backup"
    Remove-Item -LiteralPath $ProxyPath -Force
    Info "Cleared old winmm.dll so the fresh proxy can take its place"
}

# --- 4. Extract the v0.7.7 package into the game folder -----------------
Write-Host ''
Info "Extracting v0.7.7 package into game folder..."
Expand-Archive -LiteralPath $Package -DestinationPath $GameDir -Force
Ok "Extracted package"

# --- 5. Rename OptiScaler.dll -> winmm.dll (Vulkan proxy) ---------------
$OptiDll = Join-Path $GameDir 'OptiScaler.dll'
$Winmm   = Join-Path $GameDir $Proxy
if (-not (Test-Path -LiteralPath $OptiDll)) { Fail "OptiScaler.dll not found after extract" }
Move-Item -LiteralPath $OptiDll -Destination $Winmm -Force
Ok "Renamed OptiScaler.dll -> winmm.dll (Vulkan proxy)"

# --- 6. Place the E67DEE20 runtime beside the proxy ---------------------
$RuntimeDst = Join-Path $GameDir 'nvngx_dlssnr.dll'
Copy-Item -LiteralPath $Runtime -Destination $RuntimeDst -Force
Ok "Deployed nvngx_dlssnr.dll (E67DEE20)"

# --- 7. Configure OptiScaler.ini for Vulkan + NR (SECTION-SCOPED) -------
$Ini = Join-Path $GameDir 'OptiScaler.ini'
if (-not (Test-Path -LiteralPath $Ini)) { Fail "OptiScaler.ini not found after extract" }

$lines = Get-Content -LiteralPath $Ini
$out = New-Object System.Collections.Generic.List[string]
$section = ''
$hotfixManualPollingFound = $false
foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^\[(.*)\]$') { $section = $Matches[1]; $out.Add($ln); continue }

    # In [Upscalers]: force the Vulkan upscaler to DLSS
    if ($section -eq 'Upscalers' -and $ln -match '^VulkanUpscaler=') { $out.Add('VulkanUpscaler=dlss'); continue }

    # In [ProcessFilter]: inject only into RDR2.exe
    if ($section -eq 'ProcessFilter' -and $ln -match '^TargetProcessName=') { $out.Add('TargetProcessName=RDR2.exe'); continue }

    # In [Menu]: overlay hotkey = F2 (0x71). RDR2's system menus grab Home/Insert,
    # so F2 is a reliable, dedicated overlay key.
    if ($section -eq 'Menu' -and $ln -match '^ShortcutKey=') { $out.Add('ShortcutKey=0x71   ; F2 - overlay hotkey (set by DLSS5-RDR2 tool)'); continue }

    # In [Hotfix]: manual input polling. RDR2's WndProc chain stomps OptiScaler's
    # window-subclass hook ("subclass lost to another WndProc"), so no hotkey works.
    # Explicit polling keeps the F2 overlay key alive without the subclass.
    if ($section -eq 'Hotfix' -and $ln -match '^ManualInputPolling=') { $out.Add('ManualInputPolling=true'); $hotfixManualPollingFound = $true; continue }

    # In [DlssNr]: enable NR, run before SR, one pass, full working scale
    if ($section -eq 'DlssNr') {
        if ($ln -match '^Enabled=')                { $out.Add('Enabled=true'); continue }
        if ($ln -match '^RunBeforeSR=')            { $out.Add('RunBeforeSR=true'); continue }
        if ($ln -match '^DeferredDLSS=')           { $out.Add('DeferredDLSS=false'); continue }
        if ($ln -match '^ResidualFG=')             { $out.Add('ResidualFG=false'); continue }
        if ($ln -match '^Passes=')                 { $out.Add('Passes=1'); continue }
        if ($ln -match '^WorkingScale=')           { $out.Add('WorkingScale=1.0'); continue }
    }

    $out.Add($ln)
}

# If the [Hotfix] section never had a ManualInputPolling= line, the replace above
# silently did nothing (the batch re-extracts the package each run, so the key can
# go missing). Guarantee the F2 fix is present by inserting it right after the
# [Hotfix] header; if no [Hotfix] section exists at all, append it at the end.
if (-not $hotfixManualPollingFound) {
    $hotfixIdx = -1
    for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^\[Hotfix\]') { $hotfixIdx = $i; break } }
    if ($hotfixIdx -ge 0) {
        $out.Insert($hotfixIdx + 1, 'ManualInputPolling=true')
    } else {
        $out.Add('')
        $out.Add('[Hotfix]')
        $out.Add('ManualInputPolling=true')
    }
}
Set-Content -LiteralPath $Ini -Value $out
Ok "Configured OptiScaler.ini (VulkanUpscaler=dlss, NR enabled, Passes=1, ManualInputPolling=true)"
Ok "Configured OptiScaler.ini (VulkanUpscaler=dlss, NR enabled, Passes=1)"

# --- 8. Verification summary -------------------------------------------
Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan
Write-Host " winmm.dll (proxy):        $(Test-Path (Join-Path $GameDir 'winmm.dll'))"
Write-Host " nvngx_dlssnr.dll (E67):   $(Test-Path (Join-Path $GameDir 'nvngx_dlssnr.dll'))"
Write-Host " nvngx.dll_dlssnr fwd:     $(Test-Path (Join-Path $GameDir 'nvngx.dll_dlssnr.dll'))"
Write-Host " OptiScaler.ini:           $(Test-Path (Join-Path $GameDir 'OptiScaler.ini'))"
Write-Host ''
Write-Host 'Next: launch RDR2, set renderer to VULKAN, press F2.' -ForegroundColor Green
exit 0
