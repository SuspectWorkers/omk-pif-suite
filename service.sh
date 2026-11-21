#!/system/bin/sh
MODDIR="${0%/*}"
. "$MODDIR/common.sh"

{
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
  done

  i=0
  while [ "$i" -lt 15 ] && [ ! -f "$OMK_STATE/keymint-daemon.pid" ]; do
    sleep 1
    i=$((i + 1))
  done

  : > "$LOG_FILE"
  sync_omk_config && reload_omk
  configure_zygisk_hide

  i=0
  online=0
  while [ "$i" -lt 15 ]; do
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      online=1
      break
    fi
    sleep 3
    i=$((i + 1))
  done

  if [ "$online" -eq 1 ]; then
    OLD_PIF=$(sha256sum "$PIF_DIR/custom.pif.prop" 2>/dev/null | awk '{print $1}')
    OLD_KB=$(sha256sum "$OMK_KEYBOX" 2>/dev/null | awk '{print $1}')
    run_pif
    update_keybox
    NEW_PIF=$(sha256sum "$PIF_DIR/custom.pif.prop" 2>/dev/null | awk '{print $1}')
    NEW_KB=$(sha256sum "$OMK_KEYBOX" 2>/dev/null | awk '{print $1}')
    if [ "$OLD_PIF" != "$NEW_PIF" ] || [ "$OLD_KB" != "$NEW_KB" ]; then
      sync_omk_config && reload_omk
    fi
  fi

  cleanup_google
  log_msg "Boot sync finished (online=$online)"
} &
