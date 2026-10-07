# RDR2 — the confirmed-working route: OptiScaler v0.7.7 + E67DEE20 + Vulkan

This is the **only configuration reported working on an RTX 4090 with RDR2**
(fork issue #51). Everything else we tried on the DX12 path failed to create a
Neural Rendering feature (feature 18 = 0, `DlssNr::Apply/Process` = 0).

## Why the earlier DX12 setup didn't work

1. **v0.8.x has an RTX 40 DLSS-NR regression.** The loaded `OptiScaler.dll` is
   v0.8.3; per the fork's issue tracker, NR regressed on RTX 40 in 0.8.x. The
   log showed `feature=18` count of 0 — the model was never created.
2. **Runtime.** We tried `4B8D19BC` (driver-load rejection `0xBAD00000`) and
   `6EB209E7` (SF-v2, crashes the game). The fork documents the **`E67DEE20`**
   ShortFuse cross-generation 310.8 build for RTX 20/30/40 — that is the one
   we now use.
3. **Renderer.** On DX12 RDR2 exposes **FSR2** upscaler inputs (FSR2 is DX12
   only). The matching success report used **Vulkan**, where the game's DLSS
   inputs are mandatory.

## The confirmed combo

| Component | Value |
|---|---|
| OptiScaler | **v0.7.7** `OptiScaler-DLSSNR-v0.7.7.zip` (SHA `4a315a3b…`) |
| NR runtime | **`E67DEE209320CDAFE0E93E45675D7AA34323A53ACC57A72B2E40A181581C989A`** |
| Forwarder | `nvngx.dll_dlssnr.dll` (ships in the v0.7.7 package) |
| Proxy | **`winmm.dll`** — the fork's documented proxy for **Vulkan** |
| Renderer | **Vulkan** |
| INI `[Upscalers]` | `VulkanUpscaler=dlss` |
| INI `[DlssNr]` | `Enabled=true`, `RunBeforeSR=true`, `Passes=1`, `WorkingScale=1.0`, `DeferredDLSS=false`, `ResidualFG=false` |
| INI `[ProcessFilter]` | `TargetProcessName=RDR2.exe` |

## Files

- `vendor/apply_dlss5_vulkan_v0.7.7.ps1` — deploys the stack (extract package →
  rename `OptiScaler.dll`→`winmm.dll` → drop the runtime → set the INI).
- `vendor/restore_dlss5_winmm.ps1` — removes the stack and restores the real
  `C:\Windows\System32\winmm.dll` (RDR2 had no `winmm.dll.original` backup, so
  the real Windows DLL is the restore source).
- `vendor/v0.7.7/` — the extracted v0.7.7 package payload (git-ignored; large).
- `runtimes/nvngx_dlssnr.dll` — the `E67DEE20` runtime (git-ignored; 165 MB).

## Sources (verify everything)

- OptiScaler v0.7.7 release (official fork, not a mirror):
  `https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass/releases/download/v0.7.7/OptiScaler-DLSSNR-v0.7.7.zip`
  SHA-256 `4a315a3b3ee495631bd7cb1f562f609af577443602e507bfc7a7e6749c296258`.
- `nvngx_dlssnr.dll` runtime: **only** ShortFuse's pinned RenoDX thread
  (Discord). SHA-256 must be `E67DEE2093…`. Do **not** use dlss5bridge.com or
  any mirror, and do **not** run the signature-repair tool (it swaps in the RTX 50
  `E16BCF15` build that faults on Ada).

## In-game steps

1. Launch RDR2.
2. **Graphics API → Vulkan.**
3. If the upscaler input needs selecting, use **DLSS** (Vulkan uses DLSS inputs).
4. Press **F2** to open the OptiScaler overlay (set via `ShortcutKey=0x71` in
   `[Menu]`; RDR2's system menus grab Home/Insert, so F2 is a dedicated key).
5. Enable **Neural Rendering** under **DLSS Neural Rendering**.
6. Confirm the log shows the feature is created (`feature=18` > 0) and that
   `DlssNr::Apply` / `Process` runs — a flat grey difference view
   (`DebugView=1`..3) means the model is doing nothing.

## Caveat

The data point (issue #51) was v0.7.7 + Vulkan on RTX 4090. If this still shows
no effect, the remaining unknowns are the exact driver version and how RDR2's
Vulkan swapchain feeds OptiScaler — but this is the combination to validate
first.
