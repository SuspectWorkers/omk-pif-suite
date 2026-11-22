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

Public keyboxes die every few days, random Canary builds pick banned devices, and a single broken `injector.toml` flag can lock you out of your own PIN screen.

**OMK PIF Suite** replaces fragile shell snippets and manual JSON editing with a self-healing WebUI and boot/action pipeline built specifically around **Oh My KeyMint** and **PlayIntegrityFork**.

## What it does differently

- **One-button `AUTO` mode** — Tap the power button once. It pulls fresh Canary props, picks a device profile matched to your ROM's Android SDK (`A13–A17+`), hunts for a live keybox across multiple feeds, checks every certificate in the chain against Google's CRL, syncs OMK, and verifies the real Play Integrity verdict in the background. If every public keybox is revoked, it drops cleanly to `BASIC` mode instead of leaving you with `Labels: []`.
- **Proprietary autonomous Integrity probe** — Verifies real verdicts silently in the background without opening Play Store, automating screen taps, or relying on third-party checker apps. Automatically resets Play Store's local 5-call throttle window so `-8 (TOO_MANY_REQUESTS)` never breaks profile rotation, and tracks your daily check quota right in the status bar.
- **Live human-readable trace** — Instead of freezing behind a blind spinner, the overlay streams every step as it happens: Canary fetch, keybox CRL checks, OMK sync, and each profile rotation attempt, ending with a 3-second neon result screen.
- **Safety guard for your lockscreen PIN** — Before setting `[main].enabled = true` in `/data/misc/keystore/omk/injector.toml`, the module verifies that `[filter].enabled = true` and `block_android_package = true`. If the filter is unsafe, enabling is blocked and `[main].enabled` stays `false` so `system_server` never loses access to your lockscreen keys.
- **Atomic writes & clean `uninstall.sh`** — All OMK edits stage to a temp file, preserve `uid:gid`, permissions, and SELinux context, record original values, and roll back only untouched fields when uninstalled.
- **Auto-updates** — Ships with `updateJson` so KernelSU, KernelSU Next, BakaSU, and Magisk notify you on new releases.

---

## `AUTO` vs `PRO`

| Mode | Who it's for | What's on screen |
|---|---|---|
| **`AUTO`** *(default)* | Daily use | One centered power button showing live protection state (`ON` / `BASIC` / `AUTO`). Runs the full pipeline + verification automatically. |
| **`PRO`** | Fine-tuning & debugging | Keybox provider selector (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), Android 12–17+ Pixel presets (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), manual Integrity & quota checks, custom `keybox.xml` paste, `Build Fields` / `System Props` / `Raw` editors. |

---

## Requirements

- **Zygisk** (`Zygisk Next` / `ReZygisk`)
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Install

1. Grab `omk_pif_suite.zip` from [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest).
2. Flash it in your root manager and reboot.
3. Open **WebUI** and tap the power button in **`AUTO`**.

---

## Optional flag files (`/data/adb/`)

| File | Effect |
|---|---|
| `omk_pif_sync_keep_keybox` | Keeps your private `keybox.xml` during sync |
| `omk_pif_sync_no_tangorpro` | Leaves the random device picked by `autopif4.sh` untouched |

---

<details>
<summary>Companion modules for clean ROM / AOSP setups</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync) — Syncs `/dev/block/by-name/vbmeta` SHA-256 into `/data/adb/boot_hash` and `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props) — Sanitizes custom ROM / `userdebug` / `test-keys` properties before `zygote` starts
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks) — Device-specific performance, DPI, and installer tweaks (`CMR-W09`)

</details>
