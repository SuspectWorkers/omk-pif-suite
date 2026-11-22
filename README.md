# OMK PIF Suite

![Version](https://img.shields.io/badge/version-v1.7.0-4f8cff?style=flat-square)
![Platform](https://img.shields.io/badge/Android-13%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Magisk%20%7C%20APatch-compatible-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

All-in-one **KernelSU / Magisk / APatch** module with a mobile-responsive **WebUI** (**Basic** and **PRO** modes) for managing **PlayIntegrityFork** (`custom.pif.prop`), verifying real device verdicts via our **proprietary autonomous Play Integrity verification system**, and safely syncing device/attestation metadata into **Oh My KeyMint (OMK)** on Android 13–17+.

---

## Features

- **Proprietary Autonomous Play Integrity Verification System:**
  - Runs **100% silently in the background** without opening Play Store, touching the screen, or relying on third-party checker apps.
  - Tracks daily check quota (**used / remaining**) directly in the WebUI status bar and aborts cleanly if the daily limit is reached.
  - **SDK-Aware Pixel Canary Selection (A13–A17+):** automatically picks compatible Pixel Canary profiles for the device's Android SDK (`tangorpro`/`felix` on A13–14, `tegu` on A15, `frankel` on A16, `kodiak` on A17+) and rotates automatically if verification returns `NONE`/`BASIC`.
- **OMK Filter Safety Guard & Clean Uninstall (`uninstall.sh`):**
  - Verifies `[filter] enabled = true` and `block_android_package = true` in `/data/misc/keystore/omk/injector.toml` before enabling `[main].enabled = true` (prevents `system_server` Keystore interception / lockscreen PIN bootloop).
  - Performs atomic writes preserving owner, permissions, and SELinux context, records original values, and safely restores them upon module removal (`uninstall.sh`).
- **Multi-Provider Keybox Cascade (`Specter/TAKR`, `MeowDump`, `Yurikey`, `Custom URL`):**
  - Automatically scans multiple keybox providers, validates X.509 certificate dates, and verifies **every certificate in the chain** against Google's live CRL (`android.googleapis.com/attestation/status`) *before* installing.
  - If all public keyboxes are revoked or expired, automatically switches to **BASIC-only fallback** (`injector.toml enabled = false` + `spoofProvider=1`) so Play Integrity never drops to `Labels: []`.
- **Two WebUI Modes (`Basic` & `PRO`):**
  - **Basic Mode (default):** one large centered **"Full Sync"** button (`action.sh --basic`) plus **Verify Integrity + Auto-Pick**, **Check Keybox (CRL)**, **Quota Check**, **BASIC-only fallback**, and custom `keybox.xml` paste with full-screen neon SweetAlert2 result animations.
  - **PRO Mode:** provider selector (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), full visual editor for **Build Fields**, **System Properties**, **Advanced Settings**, **Raw** `custom.pif.prop`, verified presets (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), and `keep_keybox` / `no_tangorpro` flags.
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
