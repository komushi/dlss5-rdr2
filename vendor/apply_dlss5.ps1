#Requires -Version 5.1
# =====================================================================
#  APPLY_DLSS5.ps1 - install OptiScaler DLSS5 Neural Rendering + MFG
#  for Red Dead Redemption 2 (Epic) in:
#  C:\Program Files\Epic Games\RedDeadRedemption2
#
#  Run from apply_dlss5.bat. Param $ToolDir = where apply_dlss5.bat lives.
#  The OptiScaler release zip and the nvngx_dlssnr.dll runtime are expected
#  in a vendor\ subfolder (checked first) or directly beside the scripts.
#
#  RDR2 differs from Cyberpunk:
#   - RDR2.exe sits in the GAME ROOT (no bin\x64 subfolder).
#   - The proxy is dbghelp.dll (verified on this build, see fork issue).
#   - Game must be run in DX12; Vulkan crashes with the custom hooks.
#   - The DX12 renderer exposes FSR2 as the upscaler input (not DLSS),
#     so set the upscaler input to FSR2 in the in-game menu.
#   - RDR2 colour fix: the [OptiScaler] section does not exist in this build.
#     Use FsrNonLinearSRGB=true (in [FSR]) so the FSR2 input is treated as
#     perceptual sRGB, fixing the dark/washed-out colours. (The fork's issue
#     calls this "NonLinearSrgb" but that is an older-build key name.)
#
#  Behaviour: idempotent + non-destructive.
#   - Backs up existing dbghelp.dll -> dbghelp.dll.original ONCE.
#   - Verifies the OptiScaler release zip SHA-256 before extracting.
#   - Never deletes nvngx_dlssnr.dll, OptiScaler.ini, or the .original
#     backup on its own.
#   - Appends/merges the NR + MFG config keys into OptiScaler.ini.
# =====================================================================
param(
    [Parameter(Mandatory=$false)]
    [string]$ToolDir,

    [Parameter(Mandatory=$false)]
    [string]$GameDir = 'C:\Program Files\Epic Games\RedDeadRedemption2',

    # RDR2 needs DX12 + FSR2 input + Reflex for this stack. Default ON so a
    # plain double-click applies everything. Pass -SkipGameSettings to leave
    # RDR2's own system.xml untouched.
    [switch]$SkipGameSettings
)

# Resolve ToolDir to this script's folder. Under `-File` invocations the
# $PSCommandPath automatic var can be empty, so fall back to $PSScriptRoot;
# if that is also empty, use the current location.
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
# trailing quotes and backslashes) so Join-Path / Test-Path work. This also
# tolerates a plain trailing backslash from a hand-run invocation.
$ToolDir = ($ToolDir.TrimEnd([char[]]@('"', '\'))).Trim()

$ErrorActionPreference = 'Stop'
function Fail  { param([string]$m)  Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Info  { param([string]$m)  Write-Host "  $m" -ForegroundColor Gray }
function Ok    { param([string]$m)  Write-Host "  OK  $m" -ForegroundColor Green }

# The proxy name RDR2 loads (verified on the RDR2 build; see fork issue).
$Proxy   = 'dbghelp.dll'
$Backup  = "$Proxy.original"

# Binaries live in a vendor\ subfolder next to the scripts, so this tool
# folder is fully self-contained and re-clonable. Fall back to ToolDir for
# people who kept the old flat layout.
$VendorDir = Join-Path $ToolDir 'vendor'

# --- Verified values (do not change unless the source files change) ---
$ReleaseZipName = 'OptiScaler-NR-v0.8.3-rtx40-mfg.zip'
$ReleaseSHA     = 'aac7ea64d80604a5b79f686043ba28fbefefaf98818e861a377b78122cb24448'
$NRShaExpected  = '4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05'

# --- Config to set inside OptiScaler.ini (section-aware, in-place) --------
# Every key here is re-applied on EVERY run, because the Extract + Copy step
# resets OptiScaler.ini back to the distro default. Anything set only in the
# in-game menu is silently lost on the next apply — so persistent choices
# belong HERE instead.
$ConfigMap = [ordered]@{
    'DlssNr' = [ordered]@{
        'Enabled'        = 'true'
        'RunBeforeSR'    = 'true'
        # Pin the order: RunBeforeSR=true + FinishedPicture=false = "Generate
        # model before upscale, apply after upscale" (NR before SR on the small
        # pre-upscale frame — the performance-optimal ordering).
        'FinishedPicture' = 'false'
        'Passes'         = '1'
        'WorkingScale'   = '1.0'
    }
    'DLSSG' = [ordered]@{
        'AdaMfgUnlock'      = 'true'
        # 1=2X, 2=3X, 3=4X. Start at 2X; bump only if base FPS is high enough.
        'InterpolationCount' = '1'
    }
    'Menu' = [ordered]@{
        # Open the overlay via F1 (0x70). Home (0x24) was the original choice,
        # but RDR2 grabs Home for its system menu, so the overlay never opened.
        # F1 is a function key RDR2 leaves alone and works on compact/TKL boards.
        'ShortcutKey'    = '0x70'
    }
    'Log' = [ordered]@{
        # Write an OptiScaler.log so we can verify NR/MFG activity without the UI.
        # LogLevel: 0=Trace, 1=Debug, 2=Info.
        'LogToFile'      = 'true'
        'LogLevel'       = '1'
    }
}

# RDR2 color-space fix. The fork's issue describes this as "NonLinearSrgb=true",
# but in this v0.8.3 build the key lives in [FSR] as FsrNonLinearSRGB (the parser
# only recognises the Fsr-prefixed names — verified against OptiScaler.dll strings).
# The DX12 path exposes FSR2 as the upscaler input; marking its input as perceptual
# sRGB fixes the dark/washed-out colours RDR2 shows through this route.
$RdR2Section = 'FSR'
$RdR2Keys = [ordered]@{
    'FsrNonLinearSRGB' = 'true'
}

Write-Host '=== Apply DLSS5 (OptiScaler NR + MFG) for Red Dead Redemption 2 ===' -ForegroundColor Cyan
Write-Host "Game folder: $GameDir"
Write-Host "Tool folder: $ToolDir"
Write-Host ''

# RDR2 stores its graphics/display settings in this XML (not the game folder).
# The stack requires DX12 + FSR2 input + Reflex, so apply sets these too.
$SysXml = Join-Path $env:USERPROFILE 'Documents\Rockstar Games\Red Dead Redemption 2\Settings\system.xml'

# RDR2 system.xml enum values (verified against RDR2.exe strings + the game's
# own normalisation of an invalid value). Index -> name: 0=Off 1=Auto 2=Quality
# 3=Balanced 4=Performance 5=Ultra Performance for DLSS; FSR2 follows the same
# quality order (Quality=1, Balanced=2, ...).
$RdR2SettingsBackup = "$SysXml.dlss5.bak"

function Set-XmlValue {
    param([string]$XmlPath, [string]$Key, [string]$Value)
    $raw = Get-Content -LiteralPath $XmlPath -Raw
    $esc = [regex]::Escape($Key)
    # Handles both <Key>value</Key> and <Key value="x" /> forms.
    if ($raw -match "(?s)<$esc[^>]*>.*?</$esc>") {
        $raw = [regex]::Replace($raw, "(?s)(<$esc[^>]*>).*?(</$esc>)", "`${1}$Value`${2}")
    } elseif ($raw -match ('<' + $esc + ' value="')) {
        # Attribute form: <Key value="old" />  Replace just the value.
        $pat  = '<' + $esc + ' value="([^"]*)"'
        $rep  = '<' + $esc + ' value="' + $Value + '"'
        $raw = [regex]::Replace($raw, $pat, $rep)
    } else {
        # No prior key -> this build always has these keys; bail if absent.
        return $false
    }
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($XmlPath, $raw, $Utf8NoBom)
    return $true
}

# --- 0. Sanity: game folder + exe ----------------------------------------
if (-not (Test-Path -LiteralPath $GameDir)) { Fail "Game folder not found: $GameDir" }
if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'RDR2.exe'))) {
    Fail "RDR2.exe not found in $GameDir. Check the path."
}
Ok "Found $GameDir\RDR2.exe"

# --- 1. Back up the real dbghelp.dll (Windows Image Helper) ONCE ----------
$ProxyPath  = Join-Path $GameDir $Proxy
$BackupPath = Join-Path $GameDir $Backup
if (Test-Path -LiteralPath $ProxyPath) {
    if (Test-Path -LiteralPath $BackupPath) {
        Info "Backup already exists ($Backup) - not touching it."
    } else {
        Copy-Item -LiteralPath $ProxyPath -Destination $BackupPath -Force
        Ok "Backed up $Proxy -> $Backup"
    }
} else {
    Info "No $Proxy present - nothing to back up."
}

# --- 2. Verify release zip exists and matches SHA-256 ---------------------
$ZipPath = $null
foreach ($d in @($VendorDir, $ToolDir)) {
    $candidate = Join-Path $d $ReleaseZipName
    if (Test-Path -LiteralPath $candidate) { $ZipPath = $candidate; break }
}
if (-not $ZipPath) { Fail "Release zip not found. Place $ReleaseZipName in $VendorDir or $ToolDir." }
$ZipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
if ($ZipHash -ne $ReleaseSHA) {
    Fail "Release zip hash mismatch.`n  expected: $ReleaseSHA`n  actual:   $ZipHash`nRefusing to extract. Re-download from the release page."
}
Ok "Verified release zip SHA-256"

# --- 3. Extract the whole archive into the game folder --------------------
$Staging = Join-Path $ToolDir "._staging_dlss5"
if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging -Force | Out-Null
Info "Staging extract to $Staging ..."
Expand-Archive -LiteralPath $ZipPath -DestinationPath $Staging -Force
Ok "Extracted release archive"

# Build a manifest of top-level artifacts the release adds, so restore can
# remove exactly those later. OptiScaler.dll is excluded (we rename it); the
# nvngx_dlssnr.dll runtime is added in step 5 and handled specially.
$ArchiveTop = Get-ChildItem -LiteralPath $Staging -Force | Where-Object { $_.Name -ne 'OptiScaler.dll' }
$ManifestPlain = $ArchiveTop | ForEach-Object { $_.Name }
$ManifestPath = Join-Path $GameDir '_dlss5_manifest.txt'
[System.IO.File]::WriteAllLines($ManifestPath, [string[]]$ManifestPlain, (New-Object System.Text.UTF8Encoding($false)))
Ok "Recorded file manifest"

# Copy the whole staged tree into the game folder (merges, overwrites).
Copy-Item -Path (Join-Path $Staging '*') -Destination $GameDir -Recurse -Force
Ok "Copied OptiScaler files into game folder"

# --- 4. Rename OptiScaler.dll -> dbghelp.dll ------------------------------
$OptiDll = Join-Path $GameDir 'OptiScaler.dll'
$FinalProxy = Join-Path $GameDir $Proxy
if (-not (Test-Path -LiteralPath $OptiDll)) { Fail "OptiScaler.dll not found after extract." }
if (Test-Path -LiteralPath $FinalProxy) { Remove-Item -LiteralPath $FinalProxy -Force }
Rename-Item -LiteralPath $OptiDll -NewName $Proxy
Ok "Renamed OptiScaler.dll -> $Proxy"

# --- 5. Place the nvngx_dlssnr.dll runtime (RTX40 cross-gen 310.8) --------
$NRSrcCandidates = @(
    (Join-Path $VendorDir 'nvngx_dlssnr.dll'),
    (Join-Path $ToolDir 'nvngx_dlssnr.dll'),
    'C:\Program Files\Epic Games\Cyberpunk2077\bin\x64\nvngx_dlssnr.dll'
)
$NRSrc = $null
foreach ($c in $NRSrcCandidates) {
    if (Test-Path -LiteralPath $c) { $NRSrc = $c; break }
}
if (-not $NRSrc) {
    Fail "nvngx_dlssnr.dll not found. Place the RTX40 310.8 cross-gen runtime in $VendorDir, or in the tool folder."
}
$NRDest = Join-Path $GameDir 'nvngx_dlssnr.dll'
Copy-Item -LiteralPath $NRSrc -Destination $NRDest -Force
Ok "Placed nvngx_dlssnr.dll from $NRSrc"

$NRHash = (Get-FileHash -LiteralPath $NRDest -Algorithm SHA256).Hash
if ($NRHash -ne $NRShaExpected) {
    Write-Warning "nvngx_dlssnr.dll SHA-256 did not match the documented RTX40 value."
    Write-Warning "  expected: $NRShaExpected"
    Write-Warning "  actual:   $NRHash"
    Write-Warning "This may be a different-good build (the fork states there is no hash allowlist), but verify it is the trusted ShortFuse 310.8 RTX40 build."
} else {
    Ok "nvngx_dlssnr.dll SHA-256 matches expected RTX40 runtime"
}

# --- 6. Set the config keys inside OptiScaler.ini (section-aware) ---------
$IniPath = Join-Path $GameDir 'OptiScaler.ini'
if (-not (Test-Path -LiteralPath $IniPath)) { Fail "OptiScaler.ini not found after extract." }

$IniLines = @(Get-Content -LiteralPath $IniPath)
# Merge $ConfigMap sections, then the RDR2-specific [OptiScaler] keys.
function Set-SectionKeys {
    param([string[]]$Lines, [string]$Sec, [hashtable]$Keys)
    $secOpen  = "[$Sec]"
    $secIdx   = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^\s*\[$Sec\]\s*$") { $secIdx = $i; break }
    }
    if ($secIdx -eq -1) {
        $Lines += ''
        $Lines += $secOpen
        $secIdx = $Lines.Count - 1
    }
    $blockEnd = $Lines.Count
    for ($i = $secIdx + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[') { $blockEnd = $i; break }
    }
    foreach ($key in $Keys.Keys) {
        $val     = $Keys[$key]
        $pattern = "^\s*$key\s*="
        $keyIdx  = -1
        for ($i = $secIdx + 1; $i -lt $blockEnd; $i++) {
            if ($Lines[$i] -match $pattern) { $keyIdx = $i; break }
        }
        if ($keyIdx -eq -1) {
            $Lines = $Lines[0..($blockEnd-1)] + "$key=$val" + $Lines[$blockEnd..($Lines.Count-1)]
            $blockEnd++
            Write-Host "    Set $Sec/$key = $val (added)" -ForegroundColor Gray
        } else {
            $orig = $Lines[$keyIdx]
            if ($orig -match '(;.*)$') {
                $comment = $Matches[1]
                $Lines[$keyIdx] = "$key=$val $comment"
            } else {
                $Lines[$keyIdx] = "$key=$val"
            }
            Write-Host "    Set $Sec/$key = $val" -ForegroundColor Gray
        }
    }
    return $Lines
}

foreach ($sec in $ConfigMap.Keys) {
    $IniLines = Set-SectionKeys -Lines $IniLines -Sec $sec -Keys $ConfigMap[$sec]
}
# RDR2 color-space fix.
$IniLines = Set-SectionKeys -Lines $IniLines -Sec $RdR2Section -Keys $RdR2Keys

# Drop any now-empty trailing lines, then write UTF-8 WITHOUT BOM.
while ($IniLines.Count -gt 0 -and $IniLines[-1] -eq '') { $IniLines = $IniLines[0..($IniLines.Count-2)] }
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($IniPath, [string[]]$IniLines, $Utf8NoBom)
Ok "Set NR + MFG config in OptiScaler.ini"

# --- 7. Clean up staging ---------------------------------------------
if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
Ok "Cleaned up staging folder"

# --- 8. Set RDR2's own graphics settings (DX12 + FSR2 + Reflex) ---------
# The DX12 renderer exposes FSR2 as the upscaler input (not DLSS), and Reflex
# pairs with frame gen. RDR2 overwrites system.xml on exit, so this only
# persists if the game is NOT running when we write it.
if (-not $SkipGameSettings) {
    if (-not (Test-Path -LiteralPath $SysXml)) {
        Write-Warning "system.xml not found at $SysXml - skipping RDR2 graphics settings. Set them manually (DX12, FSR2 Balanced, Reflex On)."
    } else {
        $proc = Get-Process RDR2 -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Warning "RDR2 is running (PID $($proc.Id)). Its settings write is skipped so the game doesn't overwrite it on exit. Close RDR2, then re-run apply to set graphics settings."
        } else {
            # Back up before editing (only once).
            if (-not (Test-Path -LiteralPath $RdR2SettingsBackup)) {
                Copy-Item -LiteralPath $SysXml -Destination $RdR2SettingsBackup -Force
                Ok "Backed up RDR2 system.xml -> system.xml.dlss5.bak"
            } else {
                Info "RDR2 system.xml backup already exists - not overwriting."
            }

            # Apply the required stack settings. Enum values verified against
            # RDR2.exe strings (kSettingAPI_D3D12, kSettingReflex_On) and the
            # game's own normalisation of an invalid value.
            $settings = [ordered]@{
                'API'                       = 'kSettingAPI_D3D12'   # DirectX 12 (Vulkan crashes with these hooks)
                'dlssIndex'                 = '0'                   # DLSS off (DX12 exposes FSR2, not DLSS)
                'fsr2Index'                 = '2'                   # FSR2 Balanced (the upscaler input OptiScaler hooks)
                'ReflexSettings'            = 'kSettingReflex_On'   # pair with frame gen
                'vSync'                     = '0'                   # off
                'tripleBuffered'            = 'false'               # off
                'windowed'                  = '2'                   # Windowed Borderless
                # RDR2 native HDR (Windows Auto HDR is OFF for this setup, so
                # the game's own HDR does the tone-mapping on the OLED). Game
                # style avoids clipping; peak 500-600 / paper 300-350 is the
                # fork's RDR2 guidance. hdrFilmicMode=true = "Game" style.
                'hdr'                       = 'true'
                'hdrFilmicMode'             = 'true'                # HDR Style = Game (not Cinematic)
                'hdrIntensity'              = '100'
                'hdrPeakBrightness'         = '600'
            }
            foreach ($key in $settings.Keys) {
                $ok = Set-XmlValue -XmlPath $SysXml -Key $key -Value $settings[$key]
                if ($ok) { Write-Host "    Set RDR2/$key = $($settings[$key])" -ForegroundColor Gray }
                else     { Write-Warning "Could not set RDR2/$key - key missing in system.xml." }
            }
            Ok "Set RDR2 graphics settings (DX12 + FSR2 Balanced + Reflex On)"
        }
    }
} else {
    Info "SkipGameSettings set - leaving RDR2's system.xml untouched."
}

Write-Host ''
Write-Host 'All done. Next steps (in-game):' -ForegroundColor Cyan
Write-Host '  1. (If apply skipped or you closed/reopened RDR2 after setting them, confirm) Graphics API = DirectX 12.' -ForegroundColor Gray
Write-Host '  2. Display Mode: Windowed Borderless; VSync and Triple Buffering off.' -ForegroundColor Gray
Write-Host '  3. Upscaler input = AMD FSR2 (Balanced); Press Home to open the OptiScaler overlay.' -ForegroundColor Gray
Write-Host '  4. Enable Neural Rendering; confirm the RTX40 MFG unlock (2x baked in).' -ForegroundColor Gray
exit 0
