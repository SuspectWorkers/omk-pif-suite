#!/system/bin/sh
MODPATH="${0%/*}"
. "$MODPATH/common.sh"

AUTO_MODE=0
case "${1:-}" in
  --auto|--basic) AUTO_MODE=1 ;;
esac

: > "$LOG_FILE"
reset_trace
trace_msg "Сбрасываем кеш и лимиты Play Store..."
cleanup_google
run_pif
if [ "$AUTO_MODE" = "1" ]; then
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
    trace_msg "Включён режим только BASIC (все публичные keybox отозваны)"
    echo "RESULT_FALLBACK=BASIC"
    verify_and_autofix_fingerprint || true
    log_msg "Action complete (auto=$AUTO_MODE, fallback=BASIC)"
  else
    set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
    set_pif_prop spoofProvider 0
    reload_omk
    cleanup_google
    trace_msg "Сохранён локальный keybox (CRL недоступен офлайн)"
    echo "RESULT_FALLBACK=NONE"
    log_msg "Action complete (auto=$AUTO_MODE, keybox=KEPT_OFFLINE)"
  fi
else
  set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
  set_pif_prop spoofProvider 0
  reload_omk
  cleanup_google
  echo "RESULT_FALLBACK=NONE"
  verify_and_autofix_fingerprint || true
  log_msg "Action complete (auto=$AUTO_MODE, keybox=VALID)"
fi
