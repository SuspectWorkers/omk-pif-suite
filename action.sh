#!/system/bin/sh
MODPATH="${0%/*}"
. "$MODPATH/common.sh"

AUTO_MODE=0
case "${1:-}" in
  --auto|--basic) AUTO_MODE=1 ;;
esac

LOCK_DIR=/data/local/tmp/omk_action.lock.d
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  local old_pid=""
  [ -f "$LOCK_DIR/pid" ] && old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    if tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null | grep -q 'action\.sh'; then
      echo "RESULT_BUSY=1"
      echo "RESULT_LABELS=Другая настройка уже выполняется (PID $old_pid)"
      return 1
    fi
  fi
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return 0
  fi
  echo "RESULT_BUSY=1"
  echo "RESULT_LABELS=Не удалось захватить блокировку запуска"
  return 1
}

acquire_lock || exit 2
trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

: > "$LOG_FILE"
reset_trace

check_required_modules || exit 1

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
  sp_now=$(read_pif_val spoofProvider "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "0")
  pif_dev=$(read_pif_val DEVICE "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "")
  omk_dev=$(toml_get_in_section "$OMK_CFG" device device 2>/dev/null || echo "")

  if [ "$kb_live" -ge 1 ] && [ -f "$PIF_DIR/custom.pif.prop" ]; then
    need_reload=0
    if [ "$inj_now" != "true" ]; then
      trace_msg "Обнаружен выключенный OMK injector — включаем обратно..."
      set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
      need_reload=1
    fi
    if [ "$sp_now" != "0" ]; then
      force_basic_settings
      need_reload=1
    fi
    if [ "$pif_dev" != "$omk_dev" ] || [ ! -S "$OMK_DIR/rpc.sock" ]; then
      sync_omk_config >/dev/null 2>&1 || true
      need_reload=1
    fi
    [ "$need_reload" = "1" ] && reload_omk
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

  set_omk_injector_enabled true || { reload_omk; trace_msg "ОШИБКА: небезопасный фильтр OMK"; exit 1; }
  force_basic_settings
  sync_omk_config || exit 1
  configure_zygisk_hide
  reload_omk
  cleanup_google

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
