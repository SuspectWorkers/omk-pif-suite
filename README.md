<div align="center">

# OMK PIF Suite

**One-tap Play Integrity automation for Oh My KeyMint & PlayIntegrityFork**

**English** | [Русский](./README.ru.md)

<br>

[![Release](https://img.shields.io/github/v/release/SuspectWorkers/omk-pif-suite?style=flat-square&color=4f8cff&label=release)](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest)
![Android](https://img.shields.io/badge/Android-13%20%E2%86%92%2017%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Next%20%7C%20BakaSU%20%7C%20Magisk%20%7C%20APatch-222938?style=flat-square)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](./LICENSE)

</div>

---

Public keyboxes get revoked every few days, `autopif4` picks random Pixel builds that may not fit your Android version, and keeping `PlayIntegrityFork` in sync with `Oh My KeyMint` by hand gets old fast.

**OMK PIF Suite** turns the whole Play Integrity pipeline into a single tap — and tells you right inside the module whether your device actually passes.

## How it works

1. **PlayIntegrityFork auto-sync** — Runs `autopif4.sh`, selects a compatible Pixel Canary profile for your device's Android SDK (`A13–A17+`), and configures `custom.pif.prop` (`spoofBuild`, `spoofProps`, `spoofVendingFinger`).
2. **Multi-source keybox cascade & CRL check** — Scans **Specter**, **MeowDump**, **Yurikey**, or your custom URL, verifies X.509 certificate dates and every serial in the chain against Google's live CRL (`android.googleapis.com/attestation/status`) *before* installing. If every public keybox is revoked, it switches cleanly to `BASIC` mode instead of leaving you with `Labels: []`.
3. **Oh My KeyMint auto-sync** — Writes matching `brand`, `device`, `manufacturer`, `model`, `product`, `vb_hash`, and all 4 patch-level fields into `config.toml`, clears stale Play Store attestation caches, and reloads OMK.
4. **Proprietary autonomous Play Integrity verification** — Tests the real Play Integrity verdict silently in the background (zero screen automation, no third-party checker apps, automatic `-8` throttle reset) and confirms whether the setup passes. If a fingerprint fails, it rotates through compatible Pixel profiles automatically while streaming every step live beneath the spinner.

---

## `AUTO` vs `PRO`

| Mode | Purpose | Inside |
|---|---|---|
| **`AUTO`** *(default)* | Everyday one-tap setup | Centered power button showing live state (`ON` / `BASIC` / `AUTO`). Runs the full PIF + Keybox + OMK + Integrity verification cycle with live progress trace and neon result screen. |
| **`PRO`** | Manual tuning & diagnostics | Keybox provider selector (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), Android 12–17+ Pixel presets (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), manual Integrity / CRL / quota checks, custom `keybox.xml` paste, and full `custom.pif.prop` editor. |

---

## Requirements

- **Zygisk** (`Zygisk Next` / `ReZygisk`)
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Install

1. Download `omk_pif_suite.zip` from [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest) *(future updates arrive automatically via `updateJson`)*.
2. Flash in your root manager and reboot.
3. Open **WebUI** and tap the power button in **`AUTO`**.

---

## Optional flags (`/data/adb/`)

| File | Effect |
|---|---|
| `omk_pif_sync_keep_keybox` | Keep your private `keybox.xml` instead of fetching from public providers |
| `omk_pif_sync_no_tangorpro` | Keep the random Canary device picked by `autopif4.sh` |

---

<details>
<summary>Related modules for clean AOSP / custom ROM setups</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync) — Syncs `/dev/block/by-name/vbmeta` SHA-256 into `/data/adb/boot_hash` and `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props) — Sanitizes custom ROM / `userdebug` / `test-keys` properties before `zygote` starts
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks) — Device-specific performance, DPI, and installer tweaks (`CMR-W09`)

</details>
