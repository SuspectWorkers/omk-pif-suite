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
else
  update_keybox
fi
sync_omk_config || exit 1
configure_zygisk_hide
reload_omk
cleanup_google
log_msg "Action complete (basic=$BASIC_MODE)"
