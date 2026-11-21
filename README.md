# OMK PIF Suite

![Version](https://img.shields.io/badge/version-v1.3.0-4f8cff?style=flat-square)
![Platform](https://img.shields.io/badge/Android-13%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Magisk%20%7C%20APatch-compatible-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

All-in-one **KernelSU / Magisk / APatch** module with a mobile-responsive **WebUI** (**Basic** and **PRO** modes) for managing **PlayIntegrityFork** (`custom.pif.prop`) and syncing device/attestation metadata into **Oh My KeyMint (OMK)** on Android 13+.

---

## Features

- **Multi-Provider Keybox Cascade (`Specter/TAKR`, `MeowDump`, `Yurikey`, `Custom URL`):**
  - Automatically scans multiple keybox providers (`rawbin.dpejoh.com` / `workers.dev` Specter catalog aggregating TAKR & community feeds, `MeowDump` Megatron, `Yurikey`, or a custom URL), decodes, validates X.509 certificate dates, and verifies **every certificate in the chain** against Google's live CRL (`android.googleapis.com/attestation/status`) *before* installing.
  - If all public keyboxes are revoked or expired, automatically switches to **BASIC-only fallback** (`injector.toml enabled = false` + `spoofProvider=1`) so Play Integrity never drops to `Labels: []`.
- **Two WebUI Modes (`Basic` & `PRO`):**
  - **Basic Mode (default):** one large centered **"Full Sync"** button (`action.sh --basic`) that refreshes Canary, pins `Pixel Tablet (tangorpro)`, enables `spoofBuild=1` / `spoofProps=1` / `spoofVendingFinger=1`, fetches the first non-revoked keybox across all providers, syncs OMK, restarts Play Store / DroidGuard, and displays a full-screen SweetAlert2-style **neon green checkmark** or **neon red X** (auto-switching to BASIC if revoked) with a 3-second bottom progress bar.
  - **PRO Mode:** provider selector (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), full visual editor for **Build Fields**, **System Properties**, **Advanced Settings**, **Raw** `custom.pif.prop`, verified presets (`tangorpro`, `felix`, `bluejay`), and `keep_keybox` / `no_tangorpro` flags.
- **Responsive Mobile Layout & Blocking Loading Overlay:**
  - Safe overflow handling on narrow phone screens and a full-screen blocking YouTube-style spinner overlay during sync/save operations.
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
