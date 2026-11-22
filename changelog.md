# OMK PIF Suite Changelog

## v1.8.0
- Added module auto-update (`updateJson` + `update.json`).
- Renamed `Basic` mode to **`AUTO`** and simplified it to one centered full-action button (all manual tools moved cleanly to **`PRO`**).
- Added live human-readable step-by-step trace under the loading spinner during sync, keybox CRL checks, and fingerprint auto-selection.
- Fixed Google Play Integrity `-8` (`TOO_MANY_REQUESTS` / throttling) by resetting Play Store's local throttling window counters during cleanup and retrying automatically.
- Kept OMK `[filter]` safety guard, atomic config updates, and safe rollback in `uninstall.sh`.

## v1.7.0
- Added proprietary autonomous background Play Integrity verification system with daily quota guard.
- Added strict OMK `[filter]` safety validation and `uninstall.sh` rollback.
