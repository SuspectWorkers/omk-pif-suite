<div align="center">

# OMK PIF Suite

**One-tap Play Integrity setup and live verification for Oh My KeyMint & PlayIntegrityFork**

**English** | [Русский](./README.ru.md)

<br>

[![Release](https://img.shields.io/github/v/release/SuspectWorkers/omk-pif-suite?style=flat-square&color=4f8cff&label=release)](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest)
![Android](https://img.shields.io/badge/Android-13%20to%2017%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Next%20%7C%20BakaSU%20%7C%20Magisk%20%7C%20APatch-222938?style=flat-square)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](./LICENSE)

</div>

---

Public keyboxes get banned every few days, random Canary builds pick fingerprints that already fail, and syncing `PlayIntegrityFork` with `Oh My KeyMint` by hand before testing in another app gets tedious fast.

**OMK PIF Suite** puts the entire workflow behind a single power button and tells you right inside the module whether your device actually passes Basic, Device, and Strong integrity.

## Why Oh My KeyMint

Unlike TrickyStore, **Oh My KeyMint** acts as a full TEE partition emulator rather than just patching keystore calls on top. That makes hardware attestation noticeably cleaner and stealthier on rooted devices, especially when paired with matching device props and a live keybox.

## What the module does

1. **Auto-sync with PlayIntegrityFork**
   Pulls fresh Canary builds via `autopif4.sh`, selects a compatible Pixel profile for your device's Android SDK (`A13` through `A17+`), and sets the right flags in `custom.pif.prop` (`spoofBuild`, `spoofProps`, `spoofVendingFinger`).

2. **Multi-source keybox rotation and ban checks**
   Scans **Specter**, **MeowDump**, **Yurikey**, or your custom URL in order. Every certificate in the chain is checked for expiry and verified against Google's live CRL (`android.googleapis.com/attestation/status`) before it ever touches your system. If every public keybox is revoked, the module drops cleanly to `BASIC` mode instead of leaving you with `Labels: []`.

3. **Auto-sync with Oh My KeyMint**
   Writes matching `brand`, `device`, `manufacturer`, `model`, `product`, `vb_hash`, and all 4 security patch fields into `config.toml`, clears stale Play Store attestation cache, and reloads OMK.

4. **Proprietary autonomous Integrity verification**
   Checks your real Play Integrity verdict silently in the background (no opening Play Store, no screen tapping, no third-party checker apps, automatic `-8` throttle counter reset) and shows Basic, Device, and Strong status right on screen.
   - If all three checks already pass, tapping `AUTO` leaves your working keybox and fingerprint untouched.
   - If Strong or Device fails, it checks whether your keybox is still alive: replaces it if banned, or rotates Pixel profiles and re-tests until all three checks pass.

---

## `AUTO` vs `PRO`

| Mode | Best for | What is inside |
|---|---|---|
| **`AUTO`** *(default)* | Daily use | Live `Basic` / `Device` / `Strong` badges above a single centered power button (`ON` / `BASIC` / `AUTO`). Runs the full check, sync, and rotation pipeline with live step-by-step trace and animated result checks. |
| **`PRO`** | Manual control | Keybox provider selector (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), Android 12 to 17+ Pixel presets (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), manual Integrity / CRL / quota checks, custom `keybox.xml` paste, and full `custom.pif.prop` editor. |

---

## Requirements

- **Zygisk**
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Install

1. Download `omk_pif_suite.zip` from [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest) *(future updates arrive automatically via `updateJson`)*.
2. Flash it in your root manager and reboot.
3. Open **WebUI** and tap the power button in **`AUTO`**.

---

## Optional flags (`/data/adb/`)

| File | Effect |
|---|---|
| `omk_pif_sync_keep_keybox` | Keep your private `keybox.xml` instead of pulling from public providers |
| `omk_pif_sync_no_tangorpro` | Keep the random Canary device picked by `autopif4.sh` |

---

<details>
<summary>Companion modules for clean AOSP / custom ROM setups</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync): Syncs `/dev/block/by-name/vbmeta` SHA-256 into `/data/adb/boot_hash` and `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props): Cleans custom ROM / `userdebug` / `test-keys` properties before `zygote` starts
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks): Performance, DPI, and installer tweaks (`CMR-W09`)

</details>
