#!/system/bin/sh
# OMK PIF Suite: multi-provider Keybox + PIF + Oh My KeyMint sync.

PIF_DIR=/data/adb/modules/playintegrityfix
OMK_DIR=/data/misc/keystore/omk
OMK_STATE=/data/adb/omk
OMK_CFG=$OMK_DIR/config.toml
OMK_INJ=$OMK_DIR/injector.toml
OMK_KEYBOX=$OMK_DIR/keybox.xml
TS_DIR=/data/adb/tricky_store

PROVIDER_CFG=/data/adb/omk_pif_sync_provider
CUSTOM_URL_CFG=/data/adb/omk_pif_sync_keybox_url
PROBE_EP_CFG=/data/adb/omk_pif_sync_probe_endpoint
PROBE_SEC_CFG=/data/adb/omk_pif_sync_probe_secret
PROJECT_NUM_CFG=/data/adb/omk_pif_sync_project_number
QUOTA_FILE=/data/adb/omk_probe_quota.dat
STATE_DB=/data/adb/omk_pif_suite_state.db
PROBE_PKG=com.omk.integrityprobe
PROBE_APK_MOD=/data/adb/modules/omk_pif_suite/probe/OMKIntegrityProbe.apk
CRL_URL="https://android.googleapis.com/attestation/status"
CRL_CACHE=/data/local/tmp/omk_crl_cache.json

SPECTER_CATALOG_PRIMARY="https://rawbin.dpejoh.com/catalog"
SPECTER_CATALOG_FALLBACK="https://rawbin.dpejoh.workers.dev/catalog"
SPECTER_KEY_PRIMARY="https://rawbin.dpejoh.com/key"
SPECTER_KEY_FALLBACK="https://rawbin.dpejoh.workers.dev/key"
SPECTER_STD="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SPECTER_SHF="1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"

MEOWDUMP_URL="https://github.com/MeowDump/Integ""rity-Box/releases/download/archive/Megatron"
YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"

LOG_FILE=/data/local/tmp/omk_pif_sync.log
LIVE_TRACE=/data/local/tmp/omk_live_trace.log

reset_trace() {
  : > "$LIVE_TRACE" 2>/dev/null || true
}

trace_msg() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LIVE_TRACE" 2>/dev/null || true
  printf '%s [OMK_PIF_SYNC] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

log_msg() {
  printf '%s [OMK_PIF_SYNC] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

download_url() {
  url=$1
  if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout 12 --max-time 30 -fsSL "$url"
    return $?
  fi
  for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox busybox; do
    if command -v "$bb" >/dev/null 2>&1; then
      "$bb" wget -T 15 --no-check-certificate -qO- "$url"
      return $?
    fi
  done
  if command -v wget >/dev/null 2>&1; then
    wget -T 15 --no-check-certificate -qO- "$url"
    return $?
  fi
  return 1
}

reset_finsky_throttle() {
  rm -f /data/data/com.android.vending/shared_prefs/integrity_service_sharedprefs_*.xml 2>/dev/null || true
}

cleanup_google() {
  log_msg "Stopping Play Store and DroidGuard processes..."
  am force-stop com.android.vending >/dev/null 2>&1 || true
  killall com.google.android.gms.unstable >/dev/null 2>&1 || true
  killall com.android.vending >/dev/null 2>&1 || true
  reset_finsky_throttle
  log_msg "Google Play Integrity processes stopped"
}

reset_finsky_integrity_cache() {
  rm -f /data/data/com.android.vending/files/finsky/shared/device_verification_valuestore.pb* \
        /data/data/com.android.vending/files/finsky/shared/express_integrity_valuestore.pb* \
        2>/dev/null || true
  log_msg "Cleared Play Store stale integrity attestation cache"
}

set_pif_prop() {
  key=$1
  val=$2
  file="$PIF_DIR/custom.pif.prop"
  [ -f "$file" ] || return 0
  tmp="${file}.tmp.$$"
  awk -v k="$key" -v v="$val" '
    BEGIN { found=0 }
    $0 ~ ("^" k "=") { print k "=" v; found=1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  chmod 0644 "$file"
}

force_basic_settings() {
  PIF_PROP="$PIF_DIR/custom.pif.prop"
  [ -f "$PIF_PROP" ] || return 0
  tmp="${PIF_PROP}.tmp.$$"
  awk '
    /^spoofBuild=/ { print "spoofBuild=1"; next }
    /^spoofProps=/ { print "spoofProps=1"; next }
    /^spoofProvider=/ { print "spoofProvider=0"; next }
    /^spoofSignature=/ { print "spoofSignature=0"; next }
    /^spoofVendingFinger=/ { print "spoofVendingFinger=1"; next }
    /^spoofVendingSdk=/ { print "spoofVendingSdk=0"; next }
    { print }
  ' "$PIF_PROP" > "$tmp" && mv "$tmp" "$PIF_PROP"
  chmod 0644 "$PIF_PROP"
  log_msg "Applied Basic settings (spoofBuild=1, spoofProps=1, spoofVendingFinger=1)"
}

toml_get_in_section() {
  file=$1
  section=$2
  key=$3
  [ -f "$file" ] || return 1
  awk -v sec="[$section]" -v k="$key" '
    BEGIN { in_sec=(sec=="[]" ? 1 : 0); found=0 }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      cur=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
      in_sec = (cur == sec)
      next
    }
    {
      if (in_sec && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
        val=$0
        sub(/^[^=]*=[[:space:]]*/, "", val)
        sub(/[[:space:]]*#.*$/, "", val)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        gsub(/^"|"$/, "", val)
        print val
        found=1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$file"
}

toml_verify_injector_safe() {
  inj_file=$1
  [ -f "$inj_file" ] && [ -r "$inj_file" ] || { log_msg "ERROR: $inj_file missing or unreadable"; return 1; }
  grep -q '^[[:space:]]*\[main\][[:space:]]*$' "$inj_file" 2>/dev/null || { log_msg "ERROR: $inj_file missing [main] section"; return 1; }
  grep -q '^[[:space:]]*\[filter\][[:space:]]*$' "$inj_file" 2>/dev/null || { log_msg "ERROR: $inj_file missing [filter] section"; return 1; }

  f_enabled=$(toml_get_in_section "$inj_file" filter enabled 2>/dev/null || echo "")
  f_block_android=$(toml_get_in_section "$inj_file" filter block_android_package 2>/dev/null || echo "")
  if [ "$f_enabled" != "true" ] || [ "$f_block_android" != "true" ]; then
    log_msg "SECURITY BLOCK: Unsafe [filter] in $inj_file (enabled='$f_enabled', block_android_package='$f_block_android')"
    return 1
  fi
  return 0
}

atomic_replace_omk_file() {
  target_file=$1
  staging_file=$2
  default_mode=${3:-0600}
  [ -s "$staging_file" ] || { rm -f "$staging_file"; return 1; }

  if [ -e "$target_file" ]; then
    ug=$(stat -c '%u:%g' "$target_file" 2>/dev/null || echo "1017:1017")
    md=$(stat -c '%a' "$target_file" 2>/dev/null || echo "$default_mode")
    chown "$ug" "$staging_file" 2>/dev/null || chown 1017:1017 "$staging_file" 2>/dev/null || true
    chmod "$md" "$staging_file" 2>/dev/null || chmod "$default_mode" "$staging_file" 2>/dev/null || true
    chcon --reference="$target_file" "$staging_file" 2>/dev/null || restorecon "$staging_file" 2>/dev/null || true
  else
    chown 1017:1017 "$staging_file" 2>/dev/null || true
    chmod "$default_mode" "$staging_file" 2>/dev/null || true
    restorecon "$staging_file" 2>/dev/null || true
  fi
  mv -f "$staging_file" "$target_file"
}

record_omk_state() {
  s_file=$1; s_sec=$2; s_key=$3; s_orig=$4; s_written=$5
  mkdir -p /data/adb 2>/dev/null || true
  touch "$STATE_DB" 2>/dev/null || return 0
  tmp_db="${STATE_DB}.tmp.$$"
  awk -F'|' -v f="$s_file" -v s="$s_sec" -v k="$s_key" -v o="$s_orig" -v w="$s_written" '
    BEGIN { OFS="|"; found=0 }
    $1==f && $2==s && $3==k { print f, s, k, $4, w; found=1; next }
    NF>=5 { print }
    END { if (!found) print f, s, k, o, w }
  ' "$STATE_DB" > "$tmp_db" && mv -f "$tmp_db" "$STATE_DB"
  chmod 0600 "$STATE_DB" 2>/dev/null || true
}

_write_injector_main_enabled() {
  inj_file=$1
  new_state=$2
  dir=${inj_file%/*}
  base=${inj_file##*/}
  tmp="${dir}/.${base}.tmp.$$"
  awk -v st="$new_state" '
    BEGIN { in_main=0; done=0 }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      if (in_main && !done) { print "enabled = " st; done=1 }
      cur=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
      in_main = (cur == "[main]")
      print
      next
    }
    {
      if (in_main && $0 ~ /^[[:space:]]*enabled[[:space:]]*=/) {
        print "enabled = " st
        done=1
        next
      }
      print
    }
    END {
      if (in_main && !done) print "enabled = " st
    }
  ' "$inj_file" > "$tmp" || { rm -f "$tmp"; return 1; }

  actual_main=$(toml_get_in_section "$tmp" main enabled 2>/dev/null || echo "")
  if [ "$actual_main" != "$new_state" ]; then
    rm -f "$tmp"
    log_msg "ERROR: Failed to verify staged [main].enabled=$new_state in $inj_file"
    return 1
  fi
  if [ "$new_state" = "true" ] && ! toml_verify_injector_safe "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  atomic_replace_omk_file "$inj_file" "$tmp" 0600
}

set_omk_injector_enabled() {
  state=$1 # true or false
  if [ ! -f "$OMK_INJ" ] || [ ! -r "$OMK_INJ" ]; then
    log_msg "ERROR: $OMK_INJ missing or unreadable"
    return 1
  fi
  grep -q '^[[:space:]]*\[main\][[:space:]]*$' "$OMK_INJ" 2>/dev/null || { log_msg "ERROR: $OMK_INJ unparseable (missing [main])"; return 1; }
  grep -q '^[[:space:]]*\[filter\][[:space:]]*$' "$OMK_INJ" 2>/dev/null || { log_msg "ERROR: $OMK_INJ unparseable (missing [filter])"; return 1; }

  trace_msg "Проверяем защиту [filter] в injector.toml..."
  orig_val=$(toml_get_in_section "$OMK_INJ" main enabled 2>/dev/null || echo "<ABSENT>")
  if [ "$state" = "true" ]; then
    if ! toml_verify_injector_safe "$OMK_INJ"; then
      _write_injector_main_enabled "$OMK_INJ" false >/dev/null 2>&1 || true
      record_omk_state "$OMK_INJ" main enabled "$orig_val" false
      trace_msg "БЛОК: небезопасный [filter] в OMK — инжектор принудительно выключен!"
      return 1
    fi
  fi

  _write_injector_main_enabled "$OMK_INJ" "$state" || return 1
  record_omk_state "$OMK_INJ" main enabled "$orig_val" "$state"
  return 0
}

enable_basic_fallback() {
  trace_msg "Переключаемся в безопасный режим BASIC (без keybox, инжектор OMK выкл.)..."
  set_omk_injector_enabled false || return 1
  force_tangorpro_canary
  set_pif_prop spoofBuild 1
  set_pif_prop spoofProps 1
  set_pif_prop spoofProvider 1
  set_pif_prop spoofSignature 0
  set_pif_prop spoofVendingFinger 1
  set_pif_prop spoofVendingSdk 0
  reload_omk
  cleanup_google
  reset_finsky_integrity_cache
  trace_msg "Режим BASIC активирован (устройство пройдёт базовую проверку)"
}

get_profile_candidates() {
  sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  [ -n "$sdk" ] || sdk=33
  if [ "$sdk" -ge 37 ]; then
    cat <<'EOF'
kodiak|kodiak_beta|Pixel 11 Pro XL|37
grizzly|grizzly_beta|Pixel 11 Pro|37
cubs|cubs_beta|Pixel 11|37
frankel|frankel_beta|Pixel 10|36
tegu|tegu_beta|Pixel 9a|35
EOF
  elif [ "$sdk" -eq 36 ]; then
    cat <<'EOF'
frankel|frankel_beta|Pixel 10|36
blazer|blazer_beta|Pixel 10 Pro|36
mustang|mustang_beta|Pixel 10 Pro XL|36
kodiak|kodiak_beta|Pixel 11 Pro XL|37
tegu|tegu_beta|Pixel 9a|35
EOF
  elif [ "$sdk" -eq 35 ]; then
    cat <<'EOF'
tegu|tegu_beta|Pixel 9a|35
komodo|komodo_beta|Pixel 9 Pro XL|34
caiman|caiman_beta|Pixel 9 Pro|34
frankel|frankel_beta|Pixel 10|36
tangorpro|tangorpro_beta|Pixel Tablet|33
EOF
  else
    cat <<'EOF'
tangorpro|tangorpro_beta|Pixel Tablet|33
felix|felix_beta|Pixel Fold|33
komodo|komodo_beta|Pixel 9 Pro XL|34
husky|husky_beta|Pixel 8 Pro|34
bluejay|bluejay_beta|Pixel 6a|32
kodiak|kodiak_beta|Pixel 11 Pro XL|37
EOF
  fi
}

fetch_canary_for_product() {
  prod=$1
  flash_html="/data/local/tmp/omk_flash.$$"
  station_json="/data/local/tmp/omk_station.$$"
  if download_url "https://flash.android.com/" > "$flash_html" 2>/dev/null; then
    api_key=$(grep -o '<body data-client-config=.*' "$flash_html" | cut -d';' -f2 | cut -d'&' -f1)
    if [ -n "$api_key" ]; then
      url="https://content-flashstation-pa.googleapis.com/v1/builds?product=${prod}&key=${api_key}"
      if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 --max-time 20 -fsSL -H "Referer: https://flash.android.com" "$url" > "$station_json" 2>/dev/null || true
      else
        for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox busybox; do
          if command -v "$bb" >/dev/null 2>&1; then
            "$bb" wget -T 15 --no-check-certificate --header="Referer: https://flash.android.com" -qO "$station_json" "$url" 2>/dev/null || true
            break
          fi
        done
      fi
      if [ -s "$station_json" ]; then
        tac_block=$(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$station_json" | grep -m1 -A13 '"canary": true')
        c_id=$(printf '%s\n' "$tac_block" | grep 'releaseCandidateName' | cut -d'"' -f4 | head -n 1)
        c_inc=$(printf '%s\n' "$tac_block" | grep 'buildId' | cut -d'"' -f4 | head -n 1)
        rm -f "$flash_html" "$station_json"
        if [ -n "$c_id" ] && [ -n "$c_inc" ]; then
          printf '%s|%s\n' "$c_id" "$c_inc"
          return 0
        fi
      fi
    fi
  fi
  rm -f "$flash_html" "$station_json"
  return 1
}

apply_pif_profile() {
  dev=$1; prod=$2; model=$3; sdk_init=$4
  PIF_PROP="$PIF_DIR/custom.pif.prop"
  [ -f "$PIF_PROP" ] || return 1

  REL=$(read_pif_val RELEASE "$PIF_PROP"); [ -n "$REL" ] || REL=CANARY
  BID=$(read_pif_val ID "$PIF_PROP")
  INC=$(read_pif_val INCREMENTAL "$PIF_PROP")
  TYP=$(read_pif_val TYPE "$PIF_PROP"); [ -n "$TYP" ] || TYP=user
  TGS=$(read_pif_val TAGS "$PIF_PROP"); [ -n "$TGS" ] || TGS=release-keys

  live_pair=$(fetch_canary_for_product "$prod" 2>/dev/null || true)
  if [ -n "$live_pair" ]; then
    BID=${live_pair%%"|"*}
    INC=${live_pair#*"|"}
  fi
  [ -n "$BID" ] && [ -n "$INC" ] || return 1

  NEW_FP="google/${prod}/${dev}:${REL}/${BID}/${INC}:${TYP}/${TGS}"
  tmp="${PIF_PROP}.tmp.$$"
  awk -v mod="$model" -v d="$dev" -v p="$prod" -v fp="$NEW_FP" -v bid="$BID" -v inc="$INC" -v sdk="$sdk_init" '
    /^MODEL=/ { print "MODEL=" mod; next }
    /^DEVICE=/ { print "DEVICE=" d; next }
    /^PRODUCT=/ { print "PRODUCT=" p; next }
    /^ID=/ { print "ID=" bid; next }
    /^INCREMENTAL=/ { print "INCREMENTAL=" inc; next }
    /^FINGERPRINT=/ { print "FINGERPRINT=" fp; next }
    /^DEVICE_INITIAL_SDK_INT=/ { print "DEVICE_INITIAL_SDK_INT=" sdk; next }
    /^ro\.build\.fingerprint=/ { print "ro.build.fingerprint=" fp; next }
    /^ro\.build\.id=/ { print "ro.build.id=" bid; next }
    /^ro\.product\.device=/ { print "ro.product.device=" d; next }
    /^ro\.product\.name=/ { print "ro.product.name=" p; next }
    /^ro\.product\.first_api_level=/ { print "ro.product.first_api_level=" sdk; next }
    /^spoofVendingFinger=/ { print "spoofVendingFinger=1"; next }
    { print }
  ' "$PIF_PROP" > "$tmp" && mv "$tmp" "$PIF_PROP"
  chmod 0644 "$PIF_PROP"
  trace_msg "Установлен профиль Canary: $model ($dev, SDK $sdk_init)"
}

select_compatible_canary() {
  PIF_PROP="$PIF_DIR/custom.pif.prop"
  [ -f "$PIF_PROP" ] || return 0
  if [ -f /data/adb/omk_pif_sync_no_tangorpro ] || [ -f /data/adb/omk_pif_sync_no_pin ]; then
    return 0
  fi

  first_line=$(get_profile_candidates | head -n 1)
  old_ifs="$IFS"; IFS='|'; set -- $first_line; IFS="$old_ifs"
  apply_pif_profile "$1" "$2" "$3" "$4"
}

force_tangorpro_canary() {
  select_compatible_canary
}

ensure_probe_installed() {
  pm path "$PROBE_PKG" >/dev/null 2>&1 && return 0
  if [ -f "$PROBE_APK_MOD" ]; then
    log_msg "Installing headless probe APK ($PROBE_PKG)..."
    pm install -r -d "$PROBE_APK_MOD" >/dev/null 2>&1 || return 1
    pm path "$PROBE_PKG" >/dev/null 2>&1 && return 0
  fi
  return 1
}

_bundle_field() {
  raw_b=$1
  key_b=$2
  printf '%s' "$raw_b" | awk -v k="$key_b" '
    {
      s = $0
      sub(/^.*Bundle\[\{/, "", s)
      sub(/\}\][[:space:]]*$/, "", s)
      pat = "(^|, )" k "="
      if (!match(s, pat)) exit 1
      rest = substr(s, RSTART + RLENGTH)
      if (match(rest, /, [a-zA-Z0-9_]+=/)) {
        print substr(rest, 1, RSTART - 1)
      } else {
        print rest
      }
    }
  '
}

_local_quota_read() {
  today=$(date -u +%Y-%m-%d 2>/dev/null || echo "1970-01-01")
  if [ -f "$QUOTA_FILE" ]; then
    IFS='|' read -r q_day q_used q_limit <<EOF
$(cat "$QUOTA_FILE" 2>/dev/null || true)
EOF
    if [ "$q_day" = "$today" ]; then
      printf '%s|%s\n' "${q_used:-0}" "${q_limit:-10000}"
      return 0
    fi
  fi
  printf '0|10000\n'
}

_local_quota_save() {
  today=$(date -u +%Y-%m-%d 2>/dev/null || echo "1970-01-01")
  mkdir -p /data/adb 2>/dev/null || true
  printf '%s|%s|%s\n' "$today" "${1:-0}" "${2:-10000}" > "$QUOTA_FILE"
  chmod 0600 "$QUOTA_FILE" 2>/dev/null || true
}

get_probe_quota() {
  if ! ensure_probe_installed; then
    echo "QUOTA_OK=0"
    echo "QUOTA_ERR=OMKIntegrityProbe не установлен"
    return 1
  fi
  ep=""; [ -f "$PROBE_EP_CFG" ] && ep=$(tr -d '\r\n ' < "$PROBE_EP_CFG" 2>/dev/null || echo "")
  raw=$(content call --uri "content://${PROBE_PKG}.provider" --method quota --arg "$ep" 2>&1 || true)
  lq=$(_local_quota_read)
  l_used=${lq%%"|"*}
  l_limit=${lq#*"|"}

  if printf '%s' "$raw" | grep -q 'ok=true'; then
    s_used=$(_bundle_field "$raw" used 2>/dev/null || echo "0")
    s_limit=$(_bundle_field "$raw" limit 2>/dev/null || echo "10000")
    s_pers=$(_bundle_field "$raw" persistentCounter 2>/dev/null || echo "false")
    s_exh=$(_bundle_field "$raw" exhausted 2>/dev/null || echo "false")
    if [ "$s_pers" = "true" ]; then
      used="$s_used"
    else
      [ "${s_used:-0}" -gt "${l_used:-0}" ] && used="$s_used" || used="$l_used"
    fi
    limit="${s_limit:-$l_limit}"
    [ "$s_exh" = "true" ] && rem=0 || { rem=$((limit - used)); [ "$rem" -lt 0 ] && rem=0; }
    _local_quota_save "$used" "$limit"
    echo "QUOTA_OK=1"
    echo "QUOTA_USED=$used"
    echo "QUOTA_LIMIT=$limit"
    echo "QUOTA_REMAINING=$rem"
    echo "QUOTA_PERSISTENT=$s_pers"
    return 0
  fi

  rem=$((l_limit - l_used)); [ "$rem" -lt 0 ] && rem=0
  echo "QUOTA_OK=1"
  echo "QUOTA_USED=$l_used"
  echo "QUOTA_LIMIT=$l_limit"
  echo "QUOTA_REMAINING=$rem"
  echo "QUOTA_PERSISTENT=false"
}

_run_probe_once() {
  ep=$1
  proj=$2

  lq=$(_local_quota_read)
  l_used=${lq%%"|"*}
  l_limit=${lq#*"|"}
  if [ "$l_used" -ge "$l_limit" ]; then
    trace_msg "Дневной лимит проверок исчерпан ($l_used/$l_limit) — остановка"
    echo "RESULT_MODE=HEADLESS"
    echo "RESULT_VERDICT=QUOTA"
    echo "RESULT_LABELS=Дневной лимит проверок исчерпан ($l_used/$l_limit)"
    echo "RESULT_USED=$l_used"
    echo "RESULT_LIMIT=$l_limit"
    echo "RESULT_REMAINING=0"
    return 1
  fi

  if [ -n "$ep" ] && [ -n "$proj" ]; then
    raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$proj" --extra endpoint:s:"$ep" 2>&1 || true)
  elif [ -n "$ep" ]; then
    raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$ep" 2>&1 || true)
  elif [ -n "$proj" ]; then
    raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$proj" 2>&1 || true)
  else
    raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check 2>&1 || true)
  fi

  # Handle Play Store local -8 TOO_MANY_REQUESTS throttle cleanly
  err_code=$(_bundle_field "$raw_call" errorCode 2>/dev/null || echo "")
  if [ "$err_code" = "-8" ] || printf '%s' "$raw_call" | grep -qiE 'too many requests|throttled'; then
    trace_msg "Сработал лимит запросов Play Store (-8) — сбрасываем счётчик и повторяем через 2с..."
    am force-stop com.android.vending >/dev/null 2>&1 || true
    reset_finsky_throttle
    sleep 2
    if [ -n "$ep" ] && [ -n "$proj" ]; then
      raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$proj" --extra endpoint:s:"$ep" 2>&1 || true)
    elif [ -n "$ep" ]; then
      raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$ep" 2>&1 || true)
    elif [ -n "$proj" ]; then
      raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check --arg "$proj" 2>&1 || true)
    else
      raw_call=$(content call --uri "content://${PROBE_PKG}.provider" --method check 2>&1 || true)
    fi
  fi

  if ! printf '%s' "$raw_call" | grep -q 'ok=true'; then
    q_exh=$(_bundle_field "$raw_call" quotaExhausted 2>/dev/null || echo "false")
    err=$(_bundle_field "$raw_call" error 2>/dev/null || echo "")
    if [ "$q_exh" = "true" ]; then
      s_used=$(_bundle_field "$raw_call" used 2>/dev/null || echo "$l_limit")
      s_limit=$(_bundle_field "$raw_call" limit 2>/dev/null || echo "$l_limit")
      _local_quota_save "$s_used" "$s_limit"
      trace_msg "Дневной лимит API исчерпан ($s_used/$s_limit)"
      echo "RESULT_MODE=HEADLESS"
      echo "RESULT_VERDICT=QUOTA"
      echo "RESULT_LABELS=Дневной лимит API исчерпан ($s_used/$s_limit)"
      echo "RESULT_USED=$s_used"
      echo "RESULT_LIMIT=$s_limit"
      echo "RESULT_REMAINING=0"
      return 1
    fi
    trace_msg "Ошибка проверки Integrity: ${err:-$raw_call}"
    echo "RESULT_MODE=HEADLESS"
    echo "RESULT_VERDICT=ERROR"
    echo "RESULT_LABELS=${err:-Ошибка автономной системы проверки}"
    return 1
  fi

  verdict=$(_bundle_field "$raw_call" verdict 2>/dev/null || echo "NONE")
  labels=$(_bundle_field "$raw_call" labels 2>/dev/null || echo "")
  app_v=$(_bundle_field "$raw_call" appVerdict 2>/dev/null || echo "UNKNOWN")
  s_used=$(_bundle_field "$raw_call" used 2>/dev/null || echo "")
  s_limit=$(_bundle_field "$raw_call" limit 2>/dev/null || echo "$l_limit")
  s_pers=$(_bundle_field "$raw_call" persistentCounter 2>/dev/null || echo "false")
  [ -n "$verdict" ] || verdict="NONE"

  l_next=$((l_used + 1))
  if [ "$s_pers" = "true" ] && [ -n "$s_used" ]; then
    eff_used="$s_used"
  else
    [ "${s_used:-0}" -gt "$l_next" ] && eff_used="$s_used" || eff_used="$l_next"
  fi
  eff_limit="${s_limit:-10000}"
  eff_rem=$((eff_limit - eff_used)); [ "$eff_rem" -lt 0 ] && eff_rem=0
  _local_quota_save "$eff_used" "$eff_limit"

  dev_now=$(read_pif_val DEVICE "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "-")
  sdk_now=$(read_pif_val DEVICE_INITIAL_SDK_INT "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "-")
  trace_msg "Результат для $dev_now (SDK $sdk_now): $verdict [${labels:-пусто}] (лимит: ${eff_used}/${eff_limit})"

  echo "RESULT_MODE=HEADLESS"
  echo "RESULT_VERDICT=$verdict"
  echo "RESULT_PROFILE=$dev_now (SDK $sdk_now)"
  echo "RESULT_LABELS=${labels:-пусто (app=$app_v)}"
  echo "RESULT_USED=$eff_used"
  echo "RESULT_LIMIT=$eff_limit"
  echo "RESULT_REMAINING=$eff_rem"
  echo "RESULT_FP=$(read_pif_val FINGERPRINT "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo '')"
  [ "$verdict" = "STRONG" ] || [ "$verdict" = "DEVICE" ]
}

check_play_integrity() {
  if ! ensure_probe_installed; then
    echo "RESULT_MODE=HEADLESS"
    echo "RESULT_VERDICT=ERROR"
    echo "RESULT_LABELS=Не удалось установить OMKIntegrityProbe.apk"
    return 1
  fi

  ep=""; [ -f "$PROBE_EP_CFG" ] && ep=$(tr -d '\r\n ' < "$PROBE_EP_CFG" 2>/dev/null || echo "")
  proj=""; [ -f "$PROJECT_NUM_CFG" ] && proj=$(tr -d '\r\n ' < "$PROJECT_NUM_CFG" 2>/dev/null || echo "")

  am force-stop com.android.vending >/dev/null 2>&1 || true
  killall com.google.android.gms.unstable >/dev/null 2>&1 || true
  reset_finsky_throttle

  dev_now=$(read_pif_val DEVICE "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "-")
  trace_msg "Проверяем фингерпринт $dev_now через автономную систему..."

  rc1=0
  out1=$(_run_probe_once "$ep" "$proj") || rc1=$?
  v1=$(printf '%s\n' "$out1" | sed -n 's/^RESULT_VERDICT=//p' | head -n 1)
  if [ "$v1" = "STRONG" ] || [ "$v1" = "DEVICE" ] || [ "$v1" = "ERROR" ] || [ "$v1" = "QUOTA" ]; then
    printf '%s\n' "$out1"
    return "$rc1"
  fi

  trace_msg "Прогрев GMS ($v1) — пауза 3с и контрольная проверка..."
  sleep 3
  _run_probe_once "$ep" "$proj"
}

verify_and_autofix_fingerprint() {
  trace_msg "Запуск проверки Integrity и автоподбора фингерпринта..."
  inj_state=$(toml_get_in_section "$OMK_INJ" main enabled 2>/dev/null || echo "true")

  cur_out=$(check_play_integrity) || true
  cur_v=$(printf '%s\n' "$cur_out" | sed -n 's/^RESULT_VERDICT=//p' | head -n 1)
  if [ "$cur_v" = "STRONG" ] || [ "$cur_v" = "DEVICE" ] || { [ "$inj_state" = "false" ] && [ "$cur_v" = "BASIC" ]; }; then
    trace_msg "Фингерпринт прошёл проверку ($cur_v)!"
    printf '%s\n' "$cur_out"
    return 0
  fi
  if [ "$cur_v" = "ERROR" ] || [ "$cur_v" = "QUOTA" ]; then
    printf '%s\n' "$cur_out"
    return 1
  fi

  best_out="$cur_out"
  best_rank=0
  case "$cur_v" in
    DEVICE) best_rank=2 ;;
    BASIC) best_rank=1 ;;
  esac
  cur_dev=$(read_pif_val DEVICE "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "")
  cur_prod=$(read_pif_val PRODUCT "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "")
  cur_model=$(read_pif_val MODEL "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "")
  cur_sdk=$(read_pif_val DEVICE_INITIAL_SDK_INT "$PIF_DIR/custom.pif.prop" 2>/dev/null || echo "")
  best_row="${cur_dev}|${cur_prod}|${cur_model}|${cur_sdk}"
  last_row="$best_row"

  cand_list=$(get_profile_candidates)
  total_cand=$(printf '%s\n' "$cand_list" | grep -c '|' || echo 5)
  try_idx=0
  old_ifs="$IFS"
  IFS='
'
  for row in $cand_list; do
    IFS="$old_ifs"
    d=$(printf '%s' "$row" | cut -d'|' -f1)
    p=$(printf '%s' "$row" | cut -d'|' -f2)
    m=$(printf '%s' "$row" | cut -d'|' -f3)
    s=$(printf '%s' "$row" | cut -d'|' -f4)
    if [ "$d" = "$cur_dev" ]; then
      IFS='
'
      continue
    fi
    try_idx=$((try_idx + 1))
    trace_msg "Попытка перебора $try_idx/$total_cand: $m ($d, SDK $s)..."
    apply_pif_profile "$d" "$p" "$m" "$s" || { IFS='
'; continue; }
    last_row="$row"
    sync_omk_config >/dev/null 2>&1 || true
    reload_omk
    out=$(check_play_integrity) || true
    v=$(printf '%s\n' "$out" | sed -n 's/^RESULT_VERDICT=//p' | head -n 1)
    if [ "$v" = "STRONG" ] || [ "$v" = "DEVICE" ]; then
      trace_msg "Подобран рабочий профиль: $m ($d) → $v!"
      printf '%s\n' "$out"
      return 0
    fi
    if [ "$v" = "QUOTA" ] || [ "$v" = "ERROR" ]; then
      best_out="$out"
      break
    fi
    rank=0
    case "$v" in
      DEVICE) rank=2 ;;
      BASIC) rank=1 ;;
    esac
    if [ "$rank" -gt "$best_rank" ]; then
      best_rank=$rank
      best_out="$out"
      best_row="$row"
    fi
    IFS='
'
  done
  IFS="$old_ifs"

  if [ "$best_row" != "$last_row" ] && [ -n "${best_row%%"|"*}" ]; then
    d=$(printf '%s' "$best_row" | cut -d'|' -f1)
    p=$(printf '%s' "$best_row" | cut -d'|' -f2)
    m=$(printf '%s' "$best_row" | cut -d'|' -f3)
    s=$(printf '%s' "$best_row" | cut -d'|' -f4)
    apply_pif_profile "$d" "$p" "$m" "$s" >/dev/null 2>&1 || true
    sync_omk_config >/dev/null 2>&1 || true
    reload_omk
  fi

  printf '%s\n' "$best_out"
  best_v=$(printf '%s\n' "$best_out" | sed -n 's/^RESULT_VERDICT=//p' | head -n 1)
  [ "$best_v" = "STRONG" ] || [ "$best_v" = "DEVICE" ]
}

run_pif() {
  if [ ! -f "$PIF_DIR/autopif4.sh" ]; then
    log_msg "WARN: $PIF_DIR/autopif4.sh not found, skipping fetch"
    return 1
  fi
  if [ -n "$ASH_STANDALONE" ]; then
    set +o standalone
    unset ASH_STANDALONE
  fi
  MATCHFLAG=-m
  [ -f "$PIF_DIR/skipmatchdevice" ] && MATCHFLAG=""
  trace_msg "Загружаем свежий профиль Android Canary (autopif4)..."
  if sh "$PIF_DIR/autopif4.sh" $MATCHFLAG >>"$LOG_FILE" 2>&1; then
    trace_msg "Canary-профиль успешно обновлён, подбираем устройство под SDK..."
    force_tangorpro_canary
    return 0
  else
    trace_msg "Не удалось скачать новый Canary — используем текущий профиль"
    return 1
  fi
}

refresh_crl_cache() {
  force=${1:-0}
  if [ "$force" != "1" ] && [ -s "$CRL_CACHE" ]; then
    now=$(date +%s 2>/dev/null || echo 0)
    mtime=$(stat -c %Y "$CRL_CACHE" 2>/dev/null || echo 0)
    age=$((now - mtime))
    if [ "$age" -ge 0 ] && [ "$age" -lt 120 ]; then
      return 0
    fi
  fi
  tmp="${CRL_CACHE}.tmp.$$"
  if download_url "$CRL_URL" > "$tmp" 2>/dev/null && grep -q '"entries"' "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$CRL_CACHE"
    return 0
  fi
  rm -f "$tmp"
  [ -s "$CRL_CACHE" ] && return 0
  return 1
}

hex_to_dec() {
  awk -v h="$1" '
    BEGIN {
      h = tolower(h); out = "0"
      for (i = 1; i <= length(h); i++) {
        d = index("0123456789abcdef", substr(h, i, 1)) - 1
        if (d < 0) { exit 1 }
        carry = d; res = ""
        for (j = length(out); j >= 1; j--) {
          x = (substr(out, j, 1) + 0) * 16 + carry
          res = (x % 10) res
          carry = int(x / 10)
        }
        while (carry > 0) { res = (carry % 10) res; carry = int(carry / 10) }
        out = res
      }
      print out
    }
  '
}

# Inspect every PEM certificate in keybox.xml: checks structure, X.509 dates (except root), and Google CRL.
# Returns 0 if valid & non-revoked, 1 if revoked/expired/invalid, 2 if CRL unavailable.
validate_keybox_file() {
  kb_file=$1
  [ -s "$kb_file" ] || return 1
  grep -q '<AndroidAttestation>' "$kb_file" 2>/dev/null || return 1
  grep -q 'BEGIN CERTIFICATE' "$kb_file" 2>/dev/null || return 1
  grep -Eq '<PrivateKey|PRIVATE KEY' "$kb_file" 2>/dev/null || return 1

  kb_tmp="/data/local/tmp/omk_kb_check.$$"
  mkdir -p "$kb_tmp" || return 1

  sed 's/-----BEGIN CERTIFICATE-----/\n-----BEGIN CERTIFICATE-----\n/g; s/-----END CERTIFICATE-----/\n-----END CERTIFICATE-----\n/g' "$kb_file" \
  | awk -v dir="$kb_tmp" '
    /-----BEGIN CERTIFICATE-----/ { if (inside) { bad=1; exit } inside=1; n++; next }
    /-----END CERTIFICATE-----/ { if (!inside) { bad=1; exit } close(dir "/" n); inside=0; next }
    inside { gsub(/[[:space:]]/, ""); print > (dir "/" n) }
    END { if (bad || inside || !n) exit 1 }
  ' || { rm -rf "$kb_tmp"; return 1; }

  now_utc=$(date -u +%Y%m%d%H%M%S 2>/dev/null || echo "")
  serials=""
  : > "$kb_tmp/dates"
  cert_err=0

  for cf in "$kb_tmp"/[0-9]*; do
    [ -f "$cf" ] || continue
    base64 -d < "$cf" > "$kb_tmp/c.der" 2>/dev/null || { cert_err=1; break; }
    info=$(od -An -v -tx1 "$kb_tmp/c.der" | tr -d ' \n' | awk -v now="$now_utc" '
      function byte(p) { return index("0123456789abcdef", substr(hex,p,1))-1 }
      function num(p) { return byte(p)*16+byte(p+1) }
      function tlv(p, limit,  len,n,i) {
        if (p+3>limit || byte(p)<0 || byte(p+1)<0) return 0
        tag=substr(hex,p,2); len=num(p+2); p+=4
        if (len>=128) {
          n=len-128; if (n<1 || n>4 || p+n*2-1>limit) return 0
          len=0; for (i=0;i<n;i++) len=len*256+num(p+i*2); p+=n*2
        }
        start=p; end=p+len*2-1; nextpos=end+1
        return end<=limit
      }
      function xtime(p,e,  s,i,c,y) {
        s=""; for (i=p;i<=e;i+=2) { c=num(i); if (c<0 || c>127) return ""; s=s sprintf("%c",c) }
        if (tag=="17" && s ~ /^[0-9]{12}Z$/) { y=substr(s,1,2)+0; return (y>=50 ? "19" : "20") substr(s,1,12) }
        if (tag=="18" && s ~ /^[0-9]{14}Z$/) return substr(s,1,14)
        return ""
      }
      {
        hex=tolower($0); limit=length(hex)
        if (!tlv(1,limit) || tag!="30" || nextpos!=limit+1) exit 1
        if (!tlv(start,end) || tag!="30") exit 1
        tbsend=end; p=start
        if (!tlv(p,tbsend)) exit 1
        if (tag=="a0") { p=nextpos; if (!tlv(p,tbsend)) exit 1 }
        if (tag!="02") exit 1
        ser=substr(hex,start,end-start+1)
        sub(/^0+/, "", ser); if (ser=="") ser="0"
        p=nextpos; if (!tlv(p,tbsend) || tag!="30") exit 1
        p=nextpos; ip=p; if (!tlv(p,tbsend) || tag!="30") exit 1
        issuer=substr(hex,ip,nextpos-ip)
        p=nextpos; if (!tlv(p,tbsend) || tag!="30") exit 1
        vnext=nextpos; vend=end; p=start
        if (!tlv(p,vend)) exit 1; before=xtime(start,end); p=nextpos
        if (!tlv(p,vend)) exit 1; after=xtime(start,end)
        if (before=="" || after=="" || before>after) exit 1
        p=vnext; sp=p; if (!tlv(p,tbsend) || tag!="30") exit 1
        subject=substr(hex,sp,nextpos-sp)
        st="valid"
        if (now!="") {
          if (now<before) st="not_yet_valid"
          else if (now>after) st="expired"
        }
        print ser "|" st "|" issuer "|" subject
      }
    ') || { cert_err=1; break; }
    ser=$(printf '%s' "$info" | cut -d'|' -f1)
    st_rest=$(printf '%s' "$info" | cut -d'|' -f2-)
    serials="$serials $ser"
    printf '%s\n' "$st_rest" >> "$kb_tmp/dates"
  done

  if [ "$cert_err" = "1" ] || [ -z "$serials" ]; then
    rm -rf "$kb_tmp"
    return 1
  fi

  date_res=$(awk -F'|' '
    { cst[NR]=$1; cis[NR]=$2; csb[NR]=$3 }
    END {
      for (i=1; i<=NR; i++) {
        if (cst[i]=="valid") continue
        if (cis[i]==csb[i]) {
          anchored=0
          for (j=1; j<=NR; j++) if (j!=i && cis[j]==csb[i]) anchored=1
          if (anchored) continue
        }
        print cst[i]; exit
      }
      print "valid"
    }' "$kb_tmp/dates")

  if [ "$date_res" != "valid" ]; then
    log_msg "Keybox certificate date check failed ($date_res)"
    rm -rf "$kb_tmp"
    return 1
  fi

  if ! refresh_crl_cache 0; then
    log_msg "WARN: Could not download Google CRL to verify keybox"
    rm -rf "$kb_tmp"
    return 2
  fi

  for ser in $serials; do
    dec=$(hex_to_dec "$ser" 2>/dev/null || echo "")
    if grep -q "\"$ser\"" "$CRL_CACHE" 2>/dev/null || { [ -n "$dec" ] && grep -q "\"$dec\"" "$CRL_CACHE" 2>/dev/null; }; then
      log_msg "Keybox serial $ser is REVOKED in Google CRL!"
      rm -rf "$kb_tmp"
      return 1
    fi
  done

  rm -rf "$kb_tmp"
  return 0
}

install_keybox_file() {
  src_xml=$1
  new_hash=$(sha256sum "$src_xml" 2>/dev/null | awk '{print $1}')
  old_hash=$(sha256sum "$OMK_KEYBOX" 2>/dev/null | awk '{print $1}')
  if [ -d "$OMK_DIR" ]; then
    if [ "$new_hash" != "$old_hash" ] || [ ! -s "$OMK_KEYBOX" ]; then
      [ -f "$OMK_KEYBOX" ] && cp -f "$OMK_KEYBOX" "${OMK_KEYBOX}.bak"
      cp -f "$src_xml" "$OMK_KEYBOX"
      chown 1017:1017 "$OMK_KEYBOX"
      chmod 0600 "$OMK_KEYBOX"
      log_msg "Installed $OMK_KEYBOX"
      cleanup_google
      reset_finsky_integrity_cache
    else
      log_msg "Keybox unchanged ($OMK_KEYBOX)"
    fi
  fi
  mkdir -p "$TS_DIR"
  [ -f "$TS_DIR/keybox.xml" ] && cp -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak"
  cp -f "$src_xml" "$TS_DIR/keybox.xml"
  chmod 0600 "$TS_DIR/keybox.xml"
  set_omk_injector_enabled true || return 1
  set_pif_prop spoofProvider 0
  return 0
}

fetch_specter_keybox() {
  out_xml=$1
  cat_file="/data/local/tmp/omk_specter_cat.$$"
  if ! download_url "$SPECTER_CATALOG_PRIMARY" > "$cat_file" 2>/dev/null || ! grep -q '"entries"' "$cat_file" 2>/dev/null; then
    download_url "$SPECTER_CATALOG_FALLBACK" > "$cat_file" 2>/dev/null || true
  fi
  if ! grep -q '"entries"' "$cat_file" 2>/dev/null; then
    rm -f "$cat_file"
    log_msg "Specter catalog fetch failed"
    return 1
  fi

  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "9999-12-31T23:59:59Z")
  candidates=$(grep -o '"entries":\[[^]]*\]' "$cat_file" \
    | grep -o '{[^}]*}' \
    | grep -v '"revoked":true' \
    | grep -v '"softbanned":true' \
    | awk -v now="$now_iso" '
      function field(obj, k,  r) {
        if (!match(obj, "\"" k "\":\"[^\"]*\"")) return ""
        r = substr(obj, RSTART, RLENGTH)
        sub("^\"" k "\":\"", "", r); sub("\"$", "", r)
        return r
      }
      {
        src = field($0, "source"); ver = field($0, "version")
        if (src == "" || ver == "") next
        is_rkp = ($0 ~ /"rkp":true/) ? 1 : 0
        exp_at = field($0, "expires_at")
        sub(/\.[0-9]*Z$/, "Z", exp_at)
        if (is_rkp && (exp_at == "" || exp_at <= now)) next
        prio = is_rkp ? "1" : "2"
        print prio "|" src "|" ver "|" exp_at
      }' | sort -t'|' -k1,1 -k4,4r)
  rm -f "$cat_file"

  [ -n "$candidates" ] || { log_msg "Specter catalog has no active non-revoked entries"; return 1; }

  raw_blob="/data/local/tmp/omk_specter.b64.$$"
  dec_blob="/data/local/tmp/omk_specter.std.$$"
  old_ifs="$IFS"
  IFS='
'
  for line in $candidates; do
    IFS="$old_ifs"
    src=$(printf '%s' "$line" | cut -d'|' -f2)
    ver=$(printf '%s' "$line" | cut -d'|' -f3)
    log_msg "Trying Specter candidate: $src/$ver..."
    trace_msg "Проверяем keybox Specter ($src/$ver) по X.509 и базе отзывов Google CRL..."
    rm -f "$raw_blob" "$dec_blob" "$out_xml"
    if ! download_url "${SPECTER_KEY_PRIMARY}/${src}/${ver}" > "$raw_blob" 2>/dev/null || [ ! -s "$raw_blob" ]; then
      download_url "${SPECTER_KEY_FALLBACK}/${src}/${ver}" > "$raw_blob" 2>/dev/null || true
    fi
    [ -s "$raw_blob" ] || { IFS='
'; continue; }
    tr "$SPECTER_SHF" "$SPECTER_STD" < "$raw_blob" > "$dec_blob" 2>/dev/null || true
    base64 -d < "$dec_blob" > "$out_xml" 2>/dev/null || true
    rm -f "$raw_blob" "$dec_blob"
    if validate_keybox_file "$out_xml"; then
      trace_msg "Keybox Specter ($src/$ver) живой и прошёл проверку CRL!"
      return 0
    fi
    IFS='
'
  done
  IFS="$old_ifs"
  rm -f "$raw_blob" "$dec_blob" "$out_xml"
  return 1
}

fetch_meowdump_keybox() {
  out_xml=$1
  trace_msg "Проверяем keybox MeowDump и сверяем с базой отзывов Google CRL..."
  cur="/data/local/tmp/omk_md_0.$$"
  if ! download_url "$MEOWDUMP_URL" > "$cur" 2>/dev/null || [ ! -s "$cur" ]; then
    rm -f "$cur"
    log_msg "MeowDump download failed"
    return 1
  fi
  i=1
  while [ "$i" -le 10 ]; do
    nxt="/data/local/tmp/omk_md_${i}.$$"
    if ! base64 -d < "$cur" > "$nxt" 2>/dev/null; then
      rm -f "$cur" "$nxt"
      log_msg "MeowDump base64 decode failed at layer $i"
      return 1
    fi
    rm -f "$cur"
    cur="$nxt"
    i=$((i + 1))
  done
  hex_out="/data/local/tmp/omk_md_hex.$$"
  if command -v xxd >/dev/null 2>&1; then
    xxd -r -p "$cur" > "$hex_out" 2>/dev/null || { rm -f "$cur" "$hex_out"; return 1; }
  else
    rm -f "$cur" "$hex_out"
    log_msg "xxd missing for MeowDump decode"
    return 1
  fi
  rm -f "$cur"
  tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$hex_out" > "$out_xml" 2>/dev/null || { rm -f "$hex_out" "$out_xml"; return 1; }
  rm -f "$hex_out"
  if validate_keybox_file "$out_xml"; then
    trace_msg "Keybox MeowDump живой и прошёл проверку CRL!"
    return 0
  fi
  rm -f "$out_xml"
  return 1
}

fetch_yurikey_keybox() {
  out_xml=$1
  trace_msg "Проверяем keybox Yurikey и сверяем с базой отзывов Google CRL..."
  raw="/data/local/tmp/omk_yk.$$"
  if ! download_url "$YURIKEY_URL" > "$raw" 2>/dev/null || [ ! -s "$raw" ]; then
    rm -f "$raw"
    return 1
  fi
  base64 -d < "$raw" > "$out_xml" 2>/dev/null || cp -f "$raw" "$out_xml"
  rm -f "$raw"
  if validate_keybox_file "$out_xml"; then
    trace_msg "Keybox Yurikey живой и прошёл проверку CRL!"
    return 0
  fi
  rm -f "$out_xml"
  return 1
}

fetch_custom_url_keybox() {
  out_xml=$1
  [ -s "$CUSTOM_URL_CFG" ] || return 1
  url=$(tr -d '\r\n' < "$CUSTOM_URL_CFG")
  [ -n "$url" ] || return 1
  log_msg "Trying custom keybox URL: $url"
  raw="/data/local/tmp/omk_cust.$$"
  if ! download_url "$url" > "$raw" 2>/dev/null || [ ! -s "$raw" ]; then
    rm -f "$raw"
    return 1
  fi
  if grep -q '<AndroidAttestation>' "$raw" 2>/dev/null; then
    mv -f "$raw" "$out_xml"
  else
    base64 -d < "$raw" > "$out_xml" 2>/dev/null || true
    rm -f "$raw"
  fi
  if validate_keybox_file "$out_xml"; then
    log_msg "Custom URL keybox passed X.509 + Google CRL validation!"
    return 0
  fi
  rm -f "$out_xml"
  return 1
}

update_keybox() {
  if [ "${FORCE_KEYBOX:-0}" != "1" ] && [ -f /data/adb/omk_pif_sync_keep_keybox ]; then
    log_msg "Keeping local keybox (/data/adb/omk_pif_sync_keep_keybox present)"
    if validate_keybox_file "$OMK_KEYBOX"; then
      set_omk_injector_enabled true || return 1
      set_pif_prop spoofProvider 0
      return 0
    fi
    rc=$?
    if [ "$rc" -eq 2 ]; then
      return 0
    fi
    log_msg "WARN: Local kept keybox is REVOKED/INVALID!"
    return 1
  fi

  provider=""
  [ -f "$PROVIDER_CFG" ] && provider=$(tr -d '\r\n' < "$PROVIDER_CFG" 2>/dev/null || echo "")
  [ -n "$provider" ] || provider="auto"
  dec_file="/data/local/tmp/omk_keybox_new.xml.$$"

  refresh_crl_cache 1 || true
  trace_msg "Скачиваем и проверяем keybox по провайдерам ($provider)..."

  fetched=0
  case "$provider" in
    specter) fetch_specter_keybox "$dec_file" && fetched=1 ;;
    meowdump) fetch_meowdump_keybox "$dec_file" && fetched=1 ;;
    yurikey) fetch_yurikey_keybox "$dec_file" && fetched=1 ;;
    custom) fetch_custom_url_keybox "$dec_file" && fetched=1 ;;
    auto|*)
      if [ -s "$CUSTOM_URL_CFG" ] && fetch_custom_url_keybox "$dec_file"; then fetched=1
      elif fetch_specter_keybox "$dec_file"; then fetched=1
      elif fetch_meowdump_keybox "$dec_file"; then fetched=1
      elif fetch_yurikey_keybox "$dec_file"; then fetched=1
      fi
      ;;
  esac

  if [ "$fetched" -eq 1 ]; then
    install_keybox_file "$dec_file"
    ins_rc=$?
    rm -f "$dec_file"
    return "$ins_rc"
  fi

  rm -f "$dec_file"
  trace_msg "Все публичные keybox сейчас отозваны или недоступны"
  return 1
}

read_pif_val() {
  key=$1
  file=$2
  sed -n "s/^${key}=//p" "$file" | head -n 1 | cut -d '#' -f 1 | tr -d '\r' | sed 's/[[:space:]]*$//'
}

toml_set_in_section() {
  file=$1
  section=$2
  key=$3
  val=$4
  [ -f "$file" ] || return 1
  orig_val=$(toml_get_in_section "$file" "$section" "$key" 2>/dev/null || echo "<ABSENT>")
  dir=${file%/*}
  base=${file##*/}
  tmp="${dir}/.${base}.tmp.$$"
  awk -v sec="[$section]" -v k="$key" -v v="$val" '
    BEGIN { in_sec=0; done_key=0 }
    /^[[:space:]]*\[.*\][[:space:]]*$/ {
      if (in_sec && !done_key) {
        print k " = \"" v "\""
        done_key=1
      }
      cur=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
      in_sec = (cur == sec)
      print
      next
    }
    {
      if (in_sec && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
        print k " = \"" v "\""
        done_key=1
        next
      }
      print
    }
    END {
      if (in_sec && !done_key) {
        print k " = \"" v "\""
      }
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  atomic_replace_omk_file "$file" "$tmp" 0660 || return 1
  record_omk_state "$file" "$section" "$key" "$orig_val" "$val"
}

ensure_injector_scoop() {
  [ -f "$OMK_INJ" ] || return 0
  if ! grep -q '"io.github.vvb2060.keyattestation"' "$OMK_INJ"; then
    dir=${OMK_INJ%/*}
    base=${OMK_INJ##*/}
    tmp="${dir}/.${base}.tmp.$$"
    awk '
      /^scoop = \[/ && !added {
        print
        print "  \"io.github.vvb2060.keyattestation\","
        added=1
        next
      }
      { print }
    ' "$OMK_INJ" > "$tmp" || { rm -f "$tmp"; return 1; }
    atomic_replace_omk_file "$OMK_INJ" "$tmp" 0600 || return 1
    record_omk_state "$OMK_INJ" "" "scoop_ka" "<ABSENT>" "present"
    log_msg "Added io.github.vvb2060.keyattestation to $OMK_INJ"
  fi
}

sync_boot_hash() {
  VB_HASH=$(getprop ro.boot.vbmeta.digest)
  if [ -z "$VB_HASH" ] && [ -e /dev/block/by-name/vbmeta ]; then
    VB_HASH=$(sha256sum /dev/block/by-name/vbmeta 2>/dev/null | awk '{print $1}')
  fi
  [ -n "$VB_HASH" ] || return 0
  mkdir -p /data/adb
  printf '%s\n' "$VB_HASH" > /data/adb/boot_hash
  chmod 644 /data/adb/boot_hash
  resetprop -n ro.boot.vbmeta.digest "$VB_HASH" >/dev/null 2>&1 || true
  printf '%s' "$VB_HASH"
}

sync_tricky_compat() {
  PATCH_DATE=$1
  mkdir -p "$TS_DIR"
  if [ -n "$PATCH_DATE" ]; then
    cat > "$TS_DIR/security_patch.txt" <<EOF
system=prop
boot=$PATCH_DATE
vendor=$PATCH_DATE
EOF
  fi
}

sync_omk_config() {
  PIF_FILE="$PIF_DIR/custom.pif.prop"
  [ -f "$PIF_FILE" ] || PIF_FILE="$PIF_DIR/pif.prop"
  if [ ! -f "$PIF_FILE" ]; then
    log_msg "ERROR: No PIF prop file found in $PIF_DIR"
    return 1
  fi

  BRAND=$(read_pif_val BRAND "$PIF_FILE")
  DEVICE=$(read_pif_val DEVICE "$PIF_FILE")
  MANUFACTURER=$(read_pif_val MANUFACTURER "$PIF_FILE")
  MODEL=$(read_pif_val MODEL "$PIF_FILE")
  PRODUCT=$(read_pif_val PRODUCT "$PIF_FILE")
  SECURITY_PATCH=$(read_pif_val SECURITY_PATCH "$PIF_FILE")
  [ -n "$SECURITY_PATCH" ] || SECURITY_PATCH=$(read_pif_val ro.build.version.security_patch "$PIF_FILE")

  if [ -z "$SECURITY_PATCH" ]; then
    y=$(date +%Y)
    m=$(date +%m | sed 's/^0*//')
    d=$(date +%d | sed 's/^0*//')
    if [ "$d" -lt 10 ]; then
      if [ "$m" -eq 1 ]; then m=12; y=$((y - 1)); else m=$((m - 1)); fi
    fi
    SECURITY_PATCH=$(printf '%04d-%02d-05' "$y" "$m")
  fi

  VB_HASH=$(sync_boot_hash)
  sync_tricky_compat "$SECURITY_PATCH"

  if [ ! -f "$OMK_CFG" ]; then
    log_msg "ERROR: $OMK_CFG not found (is Oh My KeyMint installed?)"
    return 1
  fi

  [ -n "$BRAND" ] && toml_set_in_section "$OMK_CFG" device brand "$BRAND"
  [ -n "$DEVICE" ] && toml_set_in_section "$OMK_CFG" device device "$DEVICE"
  [ -n "$MANUFACTURER" ] && toml_set_in_section "$OMK_CFG" device manufacturer "$MANUFACTURER"
  [ -n "$MODEL" ] && toml_set_in_section "$OMK_CFG" device model "$MODEL"
  [ -n "$PRODUCT" ] && toml_set_in_section "$OMK_CFG" device product "$PRODUCT"
  toml_set_in_section "$OMK_CFG" trust security_patch "$SECURITY_PATCH"
  toml_set_in_section "$OMK_CFG" trust os_patchlevel "$SECURITY_PATCH"
  toml_set_in_section "$OMK_CFG" trust boot_patchlevel "$SECURITY_PATCH"
  toml_set_in_section "$OMK_CFG" trust vendor_patchlevel "$SECURITY_PATCH"
  [ -n "$VB_HASH" ] && toml_set_in_section "$OMK_CFG" trust vb_hash "$VB_HASH"

  chown 1017:1017 "$OMK_CFG"
  chmod 0660 "$OMK_CFG"
  ensure_injector_scoop
  trace_msg "Синхронизирован Oh My KeyMint: $DEVICE (патч $SECURITY_PATCH)"
  return 0
}

configure_zygisk_hide() {
  ZN=/data/adb/modules/zygisksu/bin/zygiskd
  if [ -x "$ZN" ]; then
    "$ZN" enforce-denylist just_umount >/dev/null 2>&1 || true
    "$ZN" memory-type anonymous >/dev/null 2>&1 || true
    "$ZN" linker builtin >/dev/null 2>&1 || true
  fi
}

reload_omk() {
  if [ -d "$OMK_STATE" ]; then
    rm -f "$OMK_DIR/rpc.sock" 2>/dev/null || true
    : > "$OMK_STATE/restart.all"
    log_msg "Triggered Oh My KeyMint restart ($OMK_STATE/restart.all)"
    i=0
    while [ "$i" -lt 12 ]; do
      if [ -S "$OMK_DIR/rpc.sock" ] && [ -f "$OMK_STATE/injector-daemon.pid" ]; then
        break
      fi
      sleep 1
      i=$((i + 1))
    done
    sleep 1
  fi
}
