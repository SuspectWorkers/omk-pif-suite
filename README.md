# OMK PIF Suite

![Version](https://img.shields.io/badge/version-v1.1.0-4f8cff?style=flat-square)
![Platform](https://img.shields.io/badge/Android-13%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Magisk%20%7C%20APatch-compatible-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

All-in-one **KernelSU / Magisk / APatch** module with an integrated **WebUI** for managing **PlayIntegrityFork** (`custom.pif.prop`) and syncing device/attestation metadata into **Oh My KeyMint (OMK)** to achieve **`MEETS_STRONG_INTEGRITY`** on Android 13+.

---

## Features

- **Integrated KernelSU WebUI** (`ksu://webui?id=omk_pif_suite`):
  - Visual editor for **Build Fields**, **System Properties** (with per-key `#` comment toggles), **Advanced Settings** (`spoofBuild`, `spoofProps`, `spoofProvider`, `spoofSignature`, `spoofVendingFinger`, `spoofVendingSdk`, `verboseLogs`), and **Raw** `custom.pif.prop` editing.
  - Verified one-tap Pixel Canary presets: **`Pixel Tablet (tangorpro)`** (SDK 33), **`Pixel Fold (felix)`** (SDK 33), **`Pixel 6a (bluejay)`** (SDK 32), plus `OMK A13+` / `Legacy (<A13)` / `Off`.
  - Toggles for keybox protection (`/data/adb/omk_pif_sync_keep_keybox`) and disabling automatic `tangorpro` pinning (`/data/adb/omk_pif_sync_no_tangorpro`).
  - One-click actions: full `action.sh` sync, local `PIF -> OMK` sync, `autopif4.sh -m`, `killpi.sh`, `.bak` restore, and live log viewer (`/data/local/tmp/omk_pif_sync.log`).
- **Automated Boot & Action Sync (`service.sh` / `action.sh`):**
  - Runs `PlayIntegrityFork` `autopif4.sh -m` once online (or on Action trigger).
  - Pins the fetched Canary build (`ID`, `INCREMENTAL`, `SECURITY_PATCH`) to **`tangorpro_beta` (`Pixel Tablet`, `DEVICE_INITIAL_SDK_INT=33`, `spoofVendingFinger=1`)** unless opted out.
  - Syncs `brand`, `device`, `manufacturer`, `model`, `product`, `vb_hash`, and **all 4 patchlevel fields** (`security_patch`, `os_patchlevel`, `boot_patchlevel`, `vendor_patchlevel`) into `/data/misc/keystore/omk/config.toml`.
  - Ensures `io.github.vvb2060.keyattestation` is included in `/data/misc/keystore/omk/injector.toml`.
  - Reloads Oh My KeyMint (`/data/adb/omk/restart.all`) and cleans/restarts `com.google.android.gms` (`unstable`), `com.android.vending`, and `com.google.android.gsf`.

---

## Requirements

- **Zygisk Next** (or compatible Zygisk provider)
- **PlayIntegrityFork** (`osm0sis`, v19+)
- **Oh My KeyMint** (`1.2.6+`) with a valid `keybox.xml` at `/data/misc/keystore/omk/keybox.xml`

---

## Flag Files (`/data/adb/`)

| File | Purpose |
|---|---|
| `/data/adb/omk_pif_sync_keep_keybox` | Protects your custom `keybox.xml` from being overwritten during sync |
| `/data/adb/omk_pif_sync_no_tangorpro` | Keeps the random Canary device selected by `autopif4.sh` instead of pinning `tangorpro` |

---

## Installation

1. Download `omk_pif_suite.zip` from [**Releases**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest).
2. Flash in KernelSU / BakaSU / Magisk / APatch and reboot.
3. Open **WebUI** in your root manager or press **Action** to run a full sync.

---

## Related Modules

- [vbmeta-sync](https://github.com/SuspectWorkers/vbmeta-sync) — Syncs `/dev/block/by-name/vbmeta` SHA-256 into `/data/adb/boot_hash` and `ro.boot.vbmeta.*` (`CMR-W09`)
- [hide-lineage-props](https://github.com/SuspectWorkers/hide-lineage-props) — Generic custom ROM / `userdebug` / `test-keys` property sanitizer
- [m5-system-tweaks](https://github.com/SuspectWorkers/m5-system-tweaks) — Device-specific tweaks & WebUI for MediaPad M5 (`CMR-W09`)
