#!/system/bin/sh
MODPATH="${0%/*}"
. "$MODPATH/common.sh"

BASIC_MODE=0
[ "${1:-}" = "--basic" ] && BASIC_MODE=1

: > "$LOG_FILE"
cleanup_google
run_pif
if [ "$BASIC_MODE" = "1" ]; then
  force_tangorpro_canary
  force_basic_settings
  FORCE_KEYBOX=1 update_keybox
  kb_ok=$?
else
  update_keybox
  kb_ok=$?
fi

sync_omk_config || exit 1
configure_zygisk_hide

if [ "$kb_ok" -ne 0 ]; then
  validate_keybox_file "$OMK_KEYBOX"
  v_rc=$?
  if [ "$v_rc" -eq 1 ]; then
    enable_basic_fallback || exit 1
    log_msg "Action complete (basic=$BASIC_MODE, fallback=BASIC)"
  else
    set_omk_injector_enabled true || { reload_omk; log_msg "ERROR: OMK injector filter unsafe"; exit 1; }
    set_pif_prop spoofProvider 0
    reload_omk
    cleanup_google
    log_msg "Action complete (basic=$BASIC_MODE, keybox=KEPT_OFFLINE)"
  fi
else
  set_omk_injector_enabled true || { reload_omk; log_msg "ERROR: OMK injector filter unsafe"; exit 1; }
  set_pif_prop spoofProvider 0
  reload_omk
  cleanup_google
  verify_and_autofix_fingerprint >>"$LOG_FILE" 2>&1 || true
  log_msg "Action complete (basic=$BASIC_MODE, keybox=VALID)"
fi
