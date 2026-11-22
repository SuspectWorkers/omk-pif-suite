# OMK PIF Suite

![Version](https://img.shields.io/badge/version-v1.8.0-4f8cff?style=flat-square)
![Platform](https://img.shields.io/badge/Android-13%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Magisk%20%7C%20APatch-compatible-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

All-in-one **KernelSU / Magisk / APatch** module with auto-update (`updateJson`) and a mobile-responsive **WebUI** (**AUTO** and **PRO** modes) for managing **PlayIntegrityFork** (`custom.pif.prop`), verifying real device verdicts via our **proprietary autonomous Play Integrity verification system**, and safely syncing device/attestation metadata into **Oh My KeyMint (OMK)** on Android 13–17+.

---

## Features

- **One-Tap `AUTO` Mode with Live Step-by-Step Trace:**
  - Centered single-button screen: fetches fresh Canary, selects SDK-compatible Pixel profile (`A13–A17+`), cascades keybox providers with X.509 + Google CRL validation, runs autonomous background Play Integrity verification (rotating profiles if needed, or falling back cleanly to **BASIC** if all keyboxes are revoked), and streams human-readable live progress right beneath the loading spinner.
- **Proprietary Autonomous Play Integrity Verification System:**
  - Runs **100% silently in the background** without opening Play Store or relying on third-party checker apps.
  - Resets Play Store's local rate-limit counters cleanly to prevent `-8` (`TOO_MANY_REQUESTS`) throttling errors during multi-profile rotation, and tracks daily quota (**used / remaining**).
- **OMK Filter Safety Guard & Clean Uninstall (`uninstall.sh`):**
  - Verifies `[filter] enabled = true` and `block_android_package = true` in `/data/misc/keystore/omk/injector.toml` before enabling `[main].enabled = true` (prevents `system_server` Keystore interception / lockscreen PIN bootloop).
  - Performs atomic writes preserving owner, permissions, and SELinux context, records original values, and safely restores them upon module removal (`uninstall.sh`).
- **Multi-Provider Keybox Cascade (`Specter/TAKR`, `MeowDump`, `Yurikey`, `Custom URL`):**
  - Automatically scans multiple keybox providers, validates X.509 certificate dates, and verifies **every certificate in the chain** against Google's live CRL (`android.googleapis.com/attestation/status`) *before* installing.
- **Full `PRO` Mode:**
  - Exposes all manual tools: provider selector, visual editor for **Build Fields**, **System Properties**, **Advanced Settings**, **Raw** `custom.pif.prop`, verified presets (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), manual quota/CRL/BASIC fallback triggers, custom `keybox.xml` paste, and `keep_keybox` / `no_tangorpro` flags.
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
