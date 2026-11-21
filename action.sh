#!/system/bin/sh
MODPATH="${0%/*}"
. "$MODPATH/common.sh"

: > "$LOG_FILE"
cleanup_google
run_pif
update_keybox
sync_omk_config || exit 1
configure_zygisk_hide
reload_omk
cleanup_google
log_msg "Action complete"
