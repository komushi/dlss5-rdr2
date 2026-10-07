# Red Dead Redemption 2 — DLSS5 (Neural Rendering) + MFG tools

One-click **apply** and **restore** for OptiScaler's DLSS5 Neural Rendering (NR)
+ RTX 40 MFG unlock on the Epic install of Red Dead Redemption 2 (RTX 4090).

> ## ⚠️ Confirmed-working route (RTX 4090 + RDR2) — READ THIS FIRST
>
> After extensive investigation, the **only confirmed working** combination for
> an RTX 4090 + RDR2 is the result of fork issue #51:
>
> **OptiScaler v0.7.7 + `E67DEE20` cross-gen runtime + Vulkan renderer + `winmm.dll` proxy**
>
> * v0.8.x has a **DLSS-NR regression on RTX 40** (feature 18 never created).
> * The DX12 route exposes **FSR2** inputs (FSR2 is DX12-only), and the upstream
>   report that matched the hardware used **Vulkan + DLSS inputs**.
> * The `E67DEE20` runtime is the **ShortFuse cross-generation 310.8** build
>   (full SHA `E67DEE209320CDAFE0E93E45675D7AA34323A53ACC57A72B2E40A181581C989A`).
>
> **Use these tools for that route:**
> * `vendor/apply_dlss5_vulkan_v0.7.7.ps1` — deploy v0.7.7 + E67DEE20 + Vulkan config
> * `vendor/restore_dlss5_winmm.ps1` — remove the whole stack (winmm-aware)
>
> The files below this note describe the **older v0.8.3 + `dbghelp.dll` + DX12 +
> FSR2** route, which is kept for reference/alternate testing but is **not** the
> confirmed combo. See `vendor/VULKAN-v0.7.7-NOTES.md` for full detail.

This is the same OptiScaler stack proven on the Cyberpunk 2077 setup
(`../dlss5-cyberpunk`), adapted for RDR2. It is **Option A** from the fork's
recommendations (OptiScaler alone). The RenoDX combo (Option C) can be tested
later — see `docs/INSTALL-DLSSNR.md`.

This tool folder is **self-contained and re-clonable**: every needed binary is
stored under `vendor\`, and the batch applies them + writes the config for you.

Target game folder (hard-coded, editable at the top of each `.ps1`):

```
C:\Program Files\Epic Games\RedDeadRedemption2
```

> Note: RDR2's executable (`RDR2.exe`) sits in the **game root**, unlike
> Cyberpunk which uses `bin\x64`. This is why the target path differs.

## Folder layout

```
dlss5-rdr2/
├── apply_dlss5.bat          Double-click to install (wrapper)
├── apply_dlss5.ps1          The install logic
├── restore_dlss5.bat        Double-click to uninstall / return to stock (wrapper)
├── restore_dlss5.ps1        The uninstall logic
├── vendor/
│   ├── OptiScaler-NR-v0.8.3-rtx40-mfg.zip    the fork's RTX40-MFG release
│   ├── nvngx_dlssnr.dll                      the RTX 40 (cross-gen) 310.8 runtime
│   └── SHA256SUMS.txt                        hashes for the two files above
├── docs/
│   └── (notes / references, e.g. RTX40-MFG.md, INSTALL-DLSSNR.md)
└── README.md
```

The `.bat` files call the matching `.ps1`. Keep each pair together in the same
folder. Right-click → **Run as administrator** is recommended (the game folder
sits under `Program Files`, so writes there need elevation).

## What `apply_dlss5` does

1. Finds `RDR2.exe` in the game root.
2. Backs up the real Windows `dbghelp.dll` → `dbghelp.dll.original` **once**
   (never overwrites an existing backup).
3. Verifies the OptiScaler release zip SHA-256, then extracts the whole archive.
4. Renames `OptiScaler.dll` → `dbghelp.dll` (the proxy RDR2 loads — the fork's
   "Option 4", chosen to avoid file-lock timing errors on fast storage).
5. Copies in `nvngx_dlssnr.dll` (the RTX 40 cross-gen 310.8 runtime) and warns
   if its hash doesn't match the documented RTX 40 value.
6. Sets the NR + MFG config **inside** `OptiScaler.ini` (section-aware, in-place).
7. Records a manifest so `restore_dlss5` can remove exactly what it added.

### Config the batch locks in (re-applied on EVERY run)

The extract step resets `OptiScaler.ini` to the distro default each time, so
anything set only in the in-game menu is silently lost on the next apply.
All persistent choices are therefore baked into the batch:

| Section | Key | Value | Purpose |
|---|---|---|---|
| `[DlssNr]` | `Enabled` | `true` | Neural Rendering on |
| `[DlssNr]` | `RunBeforeSR` | `true` | **NR before upscale** (perf-optimal) |
| `[DlssNr]` | `FinishedPicture` | `false` | Pins the NR → SR ordering |
| `[DlssNr]` | `Passes` | `1` | 1 model pass |
| `[DlssNr]` | `WorkingScale` | `1.0` | Full model res (drop to `0.5` for headroom) |
| `[DLSSG]` | `AdaMfgUnlock` | `true` | RTX 40 MFG unlock |
| `[DLSSG]` | `InterpolationCount` | `1` | **2X** MFG (2=3X, 3=4X, 4=5X) |
| `[FSR]` | `FsrNonLinearSRGB` | `true` | RDR2 colour fix for the FSR2 input |
| `[Menu]` | `ShortcutKey` | `0x70` | **F1** opens the overlay (Home is grabbed by RDR2's system menu) |
| `[Log]` | `LogToFile` / `LogLevel` | `true` / `1` | Writes `OptiScaler.log` for verification |

### The RDR2 colour key (`FsrNonLinearSRGB`, not `NonLinearSrgb`)

The fork's RDR2 issue describes the colour fix as `NonLinearSrgb = true`. In this
**v0.8.3** build that key is gone — the parser (verified against
`OptiScaler.dll`'s strings) only recognises the `Fsr`-prefixed names:
`FsrNonLinearSRGB`, `FsrNonLinearPQ`, `FsrNonLinearColorSpace`, all in the
`[FSR]` section. So the batch sets `[FSR] FsrNonLinearSRGB = true`, which marks
the FSR2 input resource as perceptual sRGB and fixes the dark / washed-out
colours this route shows in RDR2.

## What `restore_dlss5` does

- Restores `dbghelp.dll.original` → `dbghelp.dll`.
- Removes every file/folder the release added (via the manifest), plus any
  leftover proxy copies under other names.
- Removes `nvngx_dlssnr.dll` and `OptiScaler.ini`.
- Removes the `.original` backup it created.

Both scripts are **idempotent and non-destructive**: running `apply` twice or
`restore` twice is safe, and `apply` never clobbers the `dbghelp.dll.original`
backup.

## Files you must supply

These are **already stored in `vendor\`** in this repo, with their hashes
recorded in `vendor\SHA256SUMS.txt`. `apply` will refuse to run without them.

| File | Source | SHA-256 |
|---|---|---|
| `OptiScaler-NR-v0.8.3-rtx40-mfg.zip` | the fork's release page | `aac7ea64d80604a5b79f686043ba28fbefefaf98818e861a377b78122cb24448` |
| `nvngx_dlssnr.dll` | ShortFuse 310.8 **RTX 40** cross-gen runtime | `4b8d19bc3eff58a084f5eca7489c921501c203450169fb82ff4f649a4482ba05` |

`apply_dlss5.ps1` looks for these in `vendor\` first, then next to the scripts.
It also has a fallback to the Cyberpunk `nvngx_dlssnr.dll` if the vendor copy is
absent.

> Security: only download `nvngx_dlssnr.dll` from ShortFuse's pinned RenoDX
> thread. Do **not** use dlss5bridge.com (not affiliated). Verify the SHA-256.

## About the runtime hash / RTX 40 signature fallback

There are **two** DLSS5 NR runtime builds:
- **Stock NVIDIA** (`E16BCF15…`, 310.8.0.0) — signed, **RTX 50 / Blackwell only**.
- **RTX 40 re-target** (`4b8d19bc…`, 310.8.0.0 RTX40 distribution) — **not
  signed**, used on RTX 4090.

On RTX 40, NVIDIA's signed loader rejects the unsigned RTX 40 build with
`CreateFeature(18) result=0xBAD0000B` / `signature did not verify`. **This is
expected and harmless** — OptiScaler falls back to its own "compatibility
runtime" that loads the DLL by path and succeeds. **Do not** run any
"dlssnr-signature-repair" tool: it swaps in the RTX 50 signed build (`E16BCF15…`)
which faults on Ada.

### RDR2's own graphics settings the batch sets

Besides `OptiScaler.ini`, `apply_dlss5` also edits RDR2's own settings file
(`%USERPROFILE%\Documents\Rockstar Games\Red Dead Redemption 2\Settings\system.xml`)
so the game is ready for the stack. It backs the file up once to
`system.xml.dlss5.bak` before writing. These enum values are verified against
`RDR2.exe` strings and the game's own normalisation of an invalid value:

| system.xml key | Value | Meaning |
|---|---|---|
| `API` | `kSettingAPI_D3D12` | DirectX 12 (Vulkan crashes with these hooks) |
| `dlssIndex` | `0` | DLSS off (the DX12 renderer exposes FSR2, not DLSS) |
| `fsr2Index` | `2` | AMD FSR2 Balanced — the upscaler input OptiScaler hooks |
| `ReflexSettings` | `kSettingReflex_On` | Pairs with frame generation |
| `vSync` | `0` | Off (required) |
| `tripleBuffered` | `false` | Off (required) |
| `windowed` | `2` | Windowed Borderless |

Pass `-SkipGameSettings` to the `.ps1` to leave RDR2's `system.xml` untouched.
`restore_dlss5` reverts it from `system.xml.dlss5.bak` when present.

Note: RDR2 **overwrites `system.xml` when it exits**, so these settings are best
applied with the game closed. If the game is running, apply reports it and skips
the write.

## After `apply`: in-game steps

> **▶ Use the confirmed Vulkan v0.7.7 route.** The steps below are the **old
> v0.8.3 + DX12 + FSR2 + F1** flow, kept for reference only. The working combo
> is **OptiScaler v0.7.7 + `E67DEE20` runtime + Vulkan + `winmm.dll` proxy**
> (fork issue #51, RTX 4090). Follow `vendor/VULKAN-v0.7.7-NOTES.md` instead:

1. Launch RDR2. **Renderer = Vulkan** (already set in `system.xml`).
2. Use the **DLSS** upscaler input (Vulkan uses DLSS inputs, not FSR2).
3. Press **F2** to open the OptiScaler overlay (`ShortcutKey=0x71`).
4. Enable **Neural Rendering** under **DLSS Neural Rendering**.
5. Check `OptiScaler.log` for `feature=18` count > 0 and `DlssNr::Apply`/`Process`.

---

### (OLD / reference) v0.8.3 + DX12 route — does NOT produce NR on RTX 40

1. Launch RDR2. **Graphics API must be DirectX 12** — Vulkan crashes with these
   custom upscaler hooks on this build.
2. **Display Mode: Windowed Borderless**; **VSync** and **Triple Buffering**
   **Off**. (The apply script sets these + DX12 + Reflex + FSR2 + native HDR in
   `system.xml` automatically when the game is closed.)
3. Press **F1** to open the OptiScaler overlay.
4. Set the upscaler input to **FSR2** — RDR2's DX12 renderer exposes FSR2, not
   DLSS, as its upscaler input. (NR + the MFG unlock still work on top of that.)
5. Enable **Neural Rendering**; confirm the **RTX 40 MFG unlock** (2X baked in).
6. **Windows HDR / Auto HDR = OFF** (desktop stays SDR). The game's **native
   HDR** does the tone-mapping: **HDR Style: Game**, **Peak Brightness 600** —
   matches the fork's RDR2 guidance and avoids the HDR clipping the
   `FsrNonLinearSRGB` fix targets.

## Notes / caveats

- `RunBeforeSR=true` runs NR *before* the upscaler on the smaller pre-upscale
  frame — the biggest performance lever.
- The DX12 path exposes **FSR2** as the upscaler input, so the SR portion runs
  through OptiScaler's FSR path rather than native DLSS. The NR model and the
  RTX 40 MFG unlock are independent of which upscaler is used.
- RDR2 is single-player, so there is no anti-cheat ban risk. Do **not** use
  these injection tools in anti-cheat-protected multiplayer games.
- Restore first if you ever want to test the game's stock rendering again.

## Git note (large binaries)

The two `vendor\` files are ~131 MB + ~165 MB and exceed GitHub's 100 MB
per-file limit. If you push this repo to GitHub, either:
- Commit the scripts and docs but **ignore** the binaries (see `.gitignore`),
  and re-download them from the sources above; or
- Install `git lfs` and track `*.zip` / `*.dll` with Git LFS.

See `docs/RTX40-MFG.md` for the OptiScaler RTX 40 MFG specifics and
`docs/INSTALL-DLSSNR.md` for the NR runtime install details.
