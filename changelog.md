# OMK PIF Suite Changelog

## v1.8.2
- Added `Basic` / `Device` / `Strong` status badges above the status pill on the `AUTO` screen with hierarchical checks.
- Smart skip in `AUTO` mode: skips updating keybox and fingerprint when all three Play Integrity checks already pass; replaces banned keyboxes or rotates fingerprints until all three pass otherwise.
- Added sequential green/red checkmark animations (`MEETS_BASIC_INTEGRITY`, `MEETS_DEVICE_INTEGRITY`, `MEETS_STRONG_INTEGRITY`) to the result overlay.
- Updated bilingual `README.md` / `README.ru.md`.

## v1.8.1
- Redesigned `AUTO` mode with a centered VPN-style animated power button reflecting live protection status (`ON` / `BASIC` / `AUTO`).
- Rewrote project documentation (`README.md` + `README.ru.md`) with a clean English/Russian switcher.

## v1.8.0
- Added module auto-update (`updateJson` + `update.json`).
- Renamed `Basic` mode to **`AUTO`** and simplified it to one centered full-action button (all manual tools moved cleanly to **`PRO`**).
- Added live human-readable step-by-step trace under the loading spinner during sync, keybox CRL checks, and fingerprint auto-selection.
- Fixed Google Play Integrity `-8` (`TOO_MANY_REQUESTS` / throttling) by resetting Play Store's local throttling window counters during cleanup and retrying automatically.
- Kept OMK `[filter]` safety guard, atomic config updates, and safe rollback in `uninstall.sh`.

## v1.7.0
- Added proprietary autonomous background Play Integrity verification system with daily quota guard.
- Added strict OMK `[filter]` safety validation and `uninstall.sh` rollback.
