#!/system/bin/sh
MODPATH="${0%/*}"
. "$MODPATH/common.sh"

AUTO_MODE=0
case "${1:-}" in
  --auto|--basic) AUTO_MODE=1 ;;
esac

: > "$LOG_FILE"
reset_trace

if [ "$AUTO_MODE" = "1" ]; then
  trace_msg "Проверяем текущее состояние keybox и Play Integrity..."
  refresh_crl_cache 1 || true

  kb_live=0
  if [ -s "$OMK_KEYBOX" ]; then
    validate_keybox_file "$OMK_KEYBOX"
    kb_val_rc=$?
    if [ "$kb_val_rc" -eq 0 ]; then
      kb_live=1
      trace_msg "Текущий keybox жив и не отозван"
    elif [ "$kb_val_rc" -eq 2 ]; then
      kb_live=2
      trace_msg "Google CRL недоступен — сохраняем текущий keybox"
    else
      trace_msg "Текущий keybox отозван или просрочен"
    fi
  else
    trace_msg "Keybox отсутствует"
  fi

  inj_now=$(toml_get_in_section "$OMK_INJ" main enabled 2>/dev/null || echo "false")
  if [ "$kb_live" -ge 1 ] && [ -f "$PIF_DIR/custom.pif.prop" ]; then
    if [ "$inj_now" != "true" ]; then
      set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
      set_pif_prop spoofProvider 0
      sync_omk_config >/dev/null 2>&1 || true
      reload_omk
    fi
    cleanup_google
    cur_check=$(check_play_integrity) || true
    cur_b=$(printf '%s\n' "$cur_check" | sed -n 's/^RESULT_BASIC=//p' | head -n 1)
    cur_d=$(printf '%s\n' "$cur_check" | sed -n 's/^RESULT_DEVICE=//p' | head -n 1)
    cur_s=$(printf '%s\n' "$cur_check" | sed -n 's/^RESULT_STRONG=//p' | head -n 1)
    if [ "$cur_b" = "1" ] && [ "$cur_d" = "1" ] && [ "$cur_s" = "1" ]; then
      trace_msg "Все 3 галочки (Basic, Device, Strong) уже есть — фингерпринт и keybox не меняем!"
      echo "RESULT_FALLBACK=NONE"
      echo "RESULT_SKIPPED_UPDATE=1"
      printf '%s\n' "$cur_check"
      log_msg "Action complete (auto=1, skipped_update=1, all_three_pass)"
      exit 0
    fi
    trace_msg "Не все проверки пройдены (Basic=${cur_b:-0} Device=${cur_d:-0} Strong=${cur_s:-0}) — подбираем рабочий фингерпринт..."
  fi

  cleanup_google
  kb_replaced=0
  kb_ok=1
  if [ "$kb_live" -eq 0 ]; then
    FORCE_KEYBOX=1 update_keybox
    kb_ok=$?
    [ "$kb_ok" -eq 0 ] && kb_replaced=1
  else
    kb_ok=0
  fi

  if [ "$kb_ok" -ne 0 ] && [ "$kb_live" -eq 0 ]; then
    sync_omk_config >/dev/null 2>&1 || true
    configure_zygisk_hide
    enable_basic_fallback || exit 1
    echo "RESULT_FALLBACK=BASIC"
    echo "RESULT_KEYBOX=REVOKED"
    echo "RESULT_BASIC=1"
    echo "RESULT_DEVICE=0"
    echo "RESULT_STRONG=0"
    echo "RESULT_PROFILE=$(read_pif_val DEVICE "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo '-') (SDK $(read_pif_val DEVICE_INITIAL_SDK_INT "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo '-'))"
    echo "RESULT_LABELS=Режим BASIC (публичные keybox отозваны)"
    log_msg "Action complete (auto=1, fallback=BASIC)"
    exit 0
  fi

  # Keybox is live: ensure OMK is active
  set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
  set_pif_prop spoofProvider 0
  sync_omk_config || exit 1
  configure_zygisk_hide
  reload_omk
  cleanup_google

  # If we only replaced a dead keybox and already have a fingerprint, check it first before overwriting
  if [ "$kb_replaced" = "1" ] && [ -f "$PIF_DIR/custom.pif.prop" ]; then
    after_kb=$(check_play_integrity) || true
    ab=$(printf '%s\n' "$after_kb" | sed -n 's/^RESULT_BASIC=//p' | head -n 1)
    ad=$(printf '%s\n' "$after_kb" | sed -n 's/^RESULT_DEVICE=//p' | head -n 1)
    as=$(printf '%s\n' "$after_kb" | sed -n 's/^RESULT_STRONG=//p' | head -n 1)
    if [ "$ab" = "1" ] && [ "$ad" = "1" ] && [ "$as" = "1" ]; then
      trace_msg "Новый keybox + текущий фингерпринт прошли все 3 проверки!"
      echo "RESULT_FALLBACK=NONE"
      printf '%s\n' "$after_kb"
      log_msg "Action complete (auto=1, keybox=REPLACED, fp=KEPT)"
      exit 0
    fi
  fi

  # Need a working fingerprint: pull fresh Canary, match SDK, and rotate profiles until Device+Strong pass
  run_pif || true
  force_tangorpro_canary
  force_basic_settings
  sync_omk_config || exit 1
  configure_zygisk_hide
  reload_omk
  cleanup_google

  echo "RESULT_FALLBACK=NONE"
  verify_and_autofix_fingerprint || true
  log_msg "Action complete (auto=1, keybox=VALID)"
  exit 0
fi

# Manual full sync (--force / PRO)
trace_msg "Сбрасываем кеш и лимиты Play Store..."
cleanup_google
run_pif
update_keybox
kb_ok=$?

sync_omk_config || exit 1
configure_zygisk_hide

if [ "$kb_ok" -ne 0 ]; then
  validate_keybox_file "$OMK_KEYBOX"
  v_rc=$?
  if [ "$v_rc" -eq 1 ]; then
    enable_basic_fallback || exit 1
    echo "RESULT_FALLBACK=BASIC"
    echo "RESULT_KEYBOX=REVOKED"
    echo "RESULT_BASIC=1"
    echo "RESULT_DEVICE=0"
    echo "RESULT_STRONG=0"
    log_msg "Action complete (auto=0, fallback=BASIC)"
  else
    set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
    set_pif_prop spoofProvider 0
    reload_omk
    cleanup_google
    trace_msg "Сохранён локальный keybox (CRL недоступен офлайн)"
    echo "RESULT_FALLBACK=NONE"
    log_msg "Action complete (auto=0, keybox=KEPT_OFFLINE)"
  fi
else
  set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
  set_pif_prop spoofProvider 0
  reload_omk
  cleanup_google
  echo "RESULT_FALLBACK=NONE"
  verify_and_autofix_fingerprint || true
  log_msg "Action complete (auto=0, keybox=VALID)"
fi
