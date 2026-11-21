#!/system/bin/sh
# OMK PIF Sync: replaces Yurikey for Oh My KeyMint + PlayIntegrityFork.

PIF_DIR=/data/adb/modules/playintegrityfix
OMK_DIR=/data/misc/keystore/omk
OMK_STATE=/data/adb/omk
OMK_CFG=$OMK_DIR/config.toml
OMK_INJ=$OMK_DIR/injector.toml
OMK_KEYBOX=$OMK_DIR/keybox.xml
TS_DIR=/data/adb/tricky_store
KEYBOX_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
LOG_FILE=/data/local/tmp/omk_pif_sync.log

log_msg() {
  printf '%s [OMK_PIF_SYNC] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

download_url() {
  url=$1
  if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout 10 -Ls "$url"
    return $?
  fi
  for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox busybox; do
    if command -v "$bb" >/dev/null 2>&1; then
      "$bb" wget -T 10 --no-check-certificate -qO- "$url"
      return $?
    fi
  done
  return 1
}

cleanup_google() {
  log_msg "Stopping Play Store and DroidGuard processes..."
  am force-stop com.android.vending >/dev/null 2>&1 || true
  killall com.google.android.gms.unstable >/dev/null 2>&1 || true
  killall com.android.vending >/dev/null 2>&1 || true
  log_msg "Google Play Integrity processes stopped"
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

force_tangorpro_canary() {
  PIF_PROP="$PIF_DIR/custom.pif.prop"
  [ -f "$PIF_PROP" ] || return 0
  [ -f /data/adb/omk_pif_sync_no_tangorpro ] && return 0

  REL=$(read_pif_val RELEASE "$PIF_PROP")
  BID=$(read_pif_val ID "$PIF_PROP")
  INC=$(read_pif_val INCREMENTAL "$PIF_PROP")
  TYP=$(read_pif_val TYPE "$PIF_PROP")
  TGS=$(read_pif_val TAGS "$PIF_PROP")
  [ -n "$REL" ] && [ -n "$BID" ] && [ -n "$INC" ] || return 0
  [ -n "$TYP" ] || TYP=user
  [ -n "$TGS" ] || TGS=release-keys
  NEW_FP="google/tangorpro_beta/tangorpro:${REL}/${BID}/${INC}:${TYP}/${TGS}"

  tmp="${PIF_PROP}.tmp.$$"
  awk -v fp="$NEW_FP" '
    /^MODEL=/ { print "MODEL=Pixel Tablet"; next }
    /^DEVICE=/ { print "DEVICE=tangorpro"; next }
    /^PRODUCT=/ { print "PRODUCT=tangorpro_beta"; next }
    /^FINGERPRINT=/ { print "FINGERPRINT=" fp; next }
    /^DEVICE_INITIAL_SDK_INT=/ { print "DEVICE_INITIAL_SDK_INT=33"; next }
    /^ro\.build\.fingerprint=/ { print "ro.build.fingerprint=" fp; next }
    /^ro\.product\.device=/ { print "ro.product.device=tangorpro"; next }
    /^ro\.product\.name=/ { print "ro.product.name=tangorpro_beta"; next }
    /^ro\.product\.first_api_level=/ { print "ro.product.first_api_level=33"; next }
    /^spoofVendingFinger=/ { print "spoofVendingFinger=1"; next }
    { print }
  ' "$PIF_PROP" > "$tmp" && mv "$tmp" "$PIF_PROP"
  chmod 0644 "$PIF_PROP"
  log_msg "Pinned Canary profile to tangorpro (Pixel Tablet): $NEW_FP"
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
  log_msg "Running PlayIntegrityFork autopif4.sh $MATCHFLAG..."
  if sh "$PIF_DIR/autopif4.sh" $MATCHFLAG >>"$LOG_FILE" 2>&1; then
    log_msg "PlayIntegrityFork updated custom.pif.prop"
    force_tangorpro_canary
    return 0
  else
    log_msg "WARN: autopif4.sh failed (offline or blocked), keeping existing custom.pif.prop"
    return 1
  fi
}

update_keybox() {
  if [ "${FORCE_KEYBOX:-0}" != "1" ] && [ -f /data/adb/omk_pif_sync_keep_keybox ]; then
    log_msg "Keeping local keybox (/data/adb/omk_pif_sync_keep_keybox present)"
    return 0
  fi
  log_msg "Fetching keybox from $KEYBOX_URL..."
  raw_file=/data/local/tmp/omk_keybox.b64.$$
  dec_file=/data/local/tmp/omk_keybox.xml.$$
  if ! download_url "$KEYBOX_URL" > "$raw_file" 2>/dev/null || [ ! -s "$raw_file" ]; then
    rm -f "$raw_file" "$dec_file"
    log_msg "WARN: Keybox download failed, keeping existing keybox"
    return 1
  fi
  if ! base64 -d "$raw_file" > "$dec_file" 2>/dev/null || ! grep -q '<AndroidAttestation>' "$dec_file"; then
    rm -f "$raw_file" "$dec_file"
    log_msg "WARN: Downloaded keybox failed base64/XML validation, keeping existing keybox"
    return 1
  fi
  rm -f "$raw_file"

  if [ -d "$OMK_DIR" ]; then
    [ -f "$OMK_KEYBOX" ] && cp -f "$OMK_KEYBOX" "${OMK_KEYBOX}.bak"
    cp -f "$dec_file" "$OMK_KEYBOX"
    chown 1017:1017 "$OMK_KEYBOX"
    chmod 0600 "$OMK_KEYBOX"
    log_msg "Updated $OMK_KEYBOX"
  fi
  mkdir -p "$TS_DIR"
  [ -f "$TS_DIR/keybox.xml" ] && cp -f "$TS_DIR/keybox.xml" "$TS_DIR/keybox.xml.bak"
  cp -f "$dec_file" "$TS_DIR/keybox.xml"
  chmod 0600 "$TS_DIR/keybox.xml"
  rm -f "$dec_file"
  return 0
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
  tmp="${file}.tmp.$$"
  awk -v sec="[$section]" -v k="$key" -v v="$val" '
    BEGIN { in_sec=0; done_key=0 }
    /^\[.*\]/ {
      if (in_sec && !done_key) {
        print k " = \"" v "\""
        done_key=1
      }
      in_sec = ($0 == sec)
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
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

ensure_injector_scoop() {
  [ -f "$OMK_INJ" ] || return 0
  if ! grep -q '"io.github.vvb2060.keyattestation"' "$OMK_INJ"; then
    tmp="${OMK_INJ}.tmp.$$"
    awk '
      /^scoop = \[/ && !added {
        print
        print "  \"io.github.vvb2060.keyattestation\","
        added=1
        next
      }
      { print }
    ' "$OMK_INJ" > "$tmp" && mv "$tmp" "$OMK_INJ"
    log_msg "Added io.github.vvb2060.keyattestation to $OMK_INJ"
  fi
  chown 1017:1017 "$OMK_INJ"
  chmod 0600 "$OMK_INJ"
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
  log_msg "Synced OMK: brand=$BRAND device=$DEVICE model=$MODEL product=$PRODUCT patch=$SECURITY_PATCH vb_hash=$VB_HASH"
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
