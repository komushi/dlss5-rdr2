# Setup notes — RDR2

These are the non-obvious decisions made for Red Dead Redemption 2, kept here
so they don't get lost or re-litigated. The general "how it works" is in
`../README.md`; the upstream mechanics are in `RTX40-MFG.md` and
`INSTALL-DLSSNR.md`.

## Target machine / game

- **GPU:** NVIDIA GeForce RTX 4090 (Ada, 24 GB)
- **Game:** Red Dead Redemption 2, **Epic** install at
  `C:\Program Files\Epic Games\RedDeadRedemption2` (exe in the **game root**,
  not a `bin\x64` subfolder — unlike Cyberpunk)
- **Keyboard:** compact/TKL. The overlay hotkey is **F1** (`ShortcutKey=0x70`).
  Home was tried first but RDR2 grabs Home for its **system menu**, so the
  OptiScaler overlay never opened. F1 is a function key RDR2 leaves alone.

## Why RDR2 takes a different path than Cyberpunk

RDR2 does **not** expose native DLSS through the DX12 upscaler input the way
Cyberpunk does. On the DirectX 12 route it exposes **FSR2**. Consequences:

1. **NR still works** — the DLSS5 Neural Rendering model (`nvngx_dlssnr.dll`)
   is independent of which upscaler is used; it synthesises detail on the frame
   before SR. `RunBeforeSR=true` still applies.
2. **MFG unlock still works** — the RTX 40 MFG unlock patches the DLSS FG path
   (`nvngx_dlssg.dll`), which is separate from the upscaler choice.
3. **The SR portion runs through FSR2** (via OptiScaler's FSR path), not native
   DLSS. This is the main difference vs Cyberpunk.
4. **Colour needs the `FsrNonLinearSRGB=true` fix** — the FSR2 input resource is
   treated as perceptual sRGB, which corrects the dark / washed-out colours this
   route shows. (See README for the key-name note.)

## Why the RTX 40 runtime (`4b8d19bc…`), not the stock build

Same reasoning as Cyberpunk — two DLSS5 NR runtime builds:

| Build | Hash | Signed | Works on |
|---|---|---|---|
| Stock NVIDIA 310.8.0.0 | `E16BCF15…` | ✅ yes | RTX 50 (Blackwell) only |
| **RTX 40 re-target 310.8.0.0** | **`4b8d19bc…`** | ❌ no | **RTX 40 (Ada)** |

On RTX 40 the stock signed build faults (`0xBAD00001` / Ada init failure), so we
use the unsigned RTX 40 re-target. NVIDIA's signed loader rejects it with
`CreateFeature(18) result=0xBAD0000B` / `signature did not verify` — **expected
and harmless**: OptiScaler loads it via its own "compatibility runtime".

**Do NOT run a "dlssnr-signature-repair" tool** — it swaps in the RTX 50 signed
build (`E16BCF15…`), which breaks on Ada.

## Proxy choice (`dbghelp.dll`)

The fork's RDR2 guidance selects **Option 4 (`dbghelp.dll`)** as the proxy — the
same name Cyberpunk uses. It avoids file-lock timing errors on fast storage and
coexists with the other DLL loaders RDR2 pulls in. The `apply` script renames
`OptiScaler.dll` → `dbghelp.dll` and backs up any pre-existing real
`dbghelp.dll` → `dbghelp.dll.original` once.

## Config choices we locked in

- `RunBeforeSR=true` (`[DlssNr]`) — run NR **before** the upscaler on the smaller
  pre-upscale frame. Biggest performance lever.
- `FinishedPicture=false` (`[DlssNr]`) — pins the NR → SR ordering
  (generate before SR, apply the upscaled edit after).
- `WorkingScale=1.0` (`[DlssNr]`) — full model res; drop to `0.5` if we need
  GPU headroom.
- `InterpolationCount=1` (`[DLSSG]`) — **2X** MFG. Bump to `2` (3X) or `3` (4X)
  only if base FPS is high enough.
- `FsrNonLinearSRGB=true` (`[FSR]`) — the RDR2 colour fix on the FSR2 input.
- `ShortcutKey=0x70` (`[Menu]`) — overlay opens on **F1** (see keyboard note).
- `[Log]` LogToFile=true, LogLevel=1 — writes `OptiScaler.log` so NR/MFG activity
  can be verified without the UI.

## Settings the batch sets in RDR2's system.xml

The apply script now writes all of these directly into `system.xml`, so they
persist across re-runs (RDR2 only overwrites the file on exit). With the game
closed, `apply` bakes:

- **Graphics API → DirectX 12** (`API=kSettingAPI_D3D12`). Vulkan crashes with
  the custom upscaler hooks.
- **Display Mode → Windowed Borderless** (`windowed=2`); **VSync = Off**
  (`vSync=0`); **Triple Buffering = Off** (`tripleBuffered=false`).
- **Upscaler input → FSR2** (`fsr2Index=2`, Balanced) — the DX12 renderer
  exposes FSR2, not DLSS. DLSS off (`dlssIndex=0`).
- **Reflex → On** (`ReflexSettings=kSettingReflex_On`). Pairs with frame gen.
- **Native HDR**: `hdr=true`, `hdrFilmicMode=true` (Game style),
  `hdrIntensity=100`, `hdrPeakBrightness=600`.

## HDR

**Windows / Auto HDR is OFF** (System → Display → HDR). HDR is only wanted
in-game, not on the desktop. The **game's own native HDR** does the tone-mapping,
using the fork's guidance (Game style, peak 600) to avoid clipping.

## Manual (non-batch) settings the script can't set

- **Resolution Scaling / upscaler mode** — pick Quality/Balanced in-game so
  there is an upscale to run NR before. At "Native" or off, the SR/NR pipeline
  has nothing to do.

## Verified status

The Cyberpunk setup is fully verified end-to-end. The RDR2 setup uses the same
stack and binaries; the **one untested difference** is the FSR2-as-input path
and the `FsrNonLinearSRGB` colour fix. Verify after first launch:
- `OptiScaler.log` shows the NR feature being created (at the pre-upscale res),
- the MFG unlock patched `nvngx_dlssg.dll` and the game engages 2X,
- colours are not dark / washed out (the `FsrNonLinearSRGB` fix is working).
