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
CRL_URL="https://android.googleapis.com/attestation/status"
CRL_CACHE=/data/local/tmp/omk_crl_cache.json

SPECTER_CATALOG_PRIMARY="https://rawbin.dpejoh.com/catalog"
SPECTER_CATALOG_FALLBACK="https://rawbin.dpejoh.workers.dev/catalog"
SPECTER_KEY_PRIMARY="https://rawbin.dpejoh.com/key"
SPECTER_KEY_FALLBACK="https://rawbin.dpejoh.workers.dev/key"
SPECTER_STD="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SPECTER_SHF="1dgWnocayqxU3r6vA5lCIPYfHmkV08b4tz+KMsp2NQ9LRXihODwSj7BEFJ/ZuGTe"

MEOWDUMP_URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron"
YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"

LOG_FILE=/data/local/tmp/omk_pif_sync.log

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

cleanup_google() {
  log_msg "Stopping Play Store and DroidGuard processes..."
  am force-stop com.android.vending >/dev/null 2>&1 || true
  killall com.google.android.gms.unstable >/dev/null 2>&1 || true
  killall com.android.vending >/dev/null 2>&1 || true
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

set_omk_injector_enabled() {
  state=$1 # true or false
  [ -f "$OMK_INJ" ] || return 0
  tmp="${OMK_INJ}.tmp.$$"
  awk -v st="$state" '
    BEGIN { in_main=0 }
    /^\[.*\]/ { in_main = ($0 == "[main]"); print; next }
    {
      if (in_main && $0 ~ /^[[:space:]]*enabled[[:space:]]*=/) {
        print "enabled = " st
        next
      }
      print
    }
  ' "$OMK_INJ" > "$tmp" && mv "$tmp" "$OMK_INJ"
  chown 1017:1017 "$OMK_INJ"
  chmod 0600 "$OMK_INJ"
}

enable_basic_fallback() {
  log_msg "Switching to BASIC-only fallback (no keybox, OMK injector off, spoofProvider=1)..."
  set_omk_injector_enabled false
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
  log_msg "BASIC-only fallback active"
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
  set_omk_injector_enabled true
  set_pif_prop spoofProvider 0
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
      log_msg "Specter ($src/$ver) passed X.509 + Google CRL validation!"
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
  log_msg "Trying MeowDump provider..."
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
    log_msg "MeowDump passed X.509 + Google CRL validation!"
    return 0
  fi
  rm -f "$out_xml"
  return 1
}

fetch_yurikey_keybox() {
  out_xml=$1
  log_msg "Trying Yurikey provider..."
  raw="/data/local/tmp/omk_yk.$$"
  if ! download_url "$YURIKEY_URL" > "$raw" 2>/dev/null || [ ! -s "$raw" ]; then
    rm -f "$raw"
    return 1
  fi
  base64 -d < "$raw" > "$out_xml" 2>/dev/null || cp -f "$raw" "$out_xml"
  rm -f "$raw"
  if validate_keybox_file "$out_xml"; then
    log_msg "Yurikey passed X.509 + Google CRL validation!"
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
      set_omk_injector_enabled true
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

  provider=$(cat "$PROVIDER_CFG" 2>/dev/null | tr -d '\r\n' || echo "auto")
  [ -n "$provider" ] || provider="auto"
  dec_file="/data/local/tmp/omk_keybox_new.xml.$$"

  refresh_crl_cache 1 || true

  case "$provider" in
    specter)
      if fetch_specter_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      ;;
    meowdump)
      if fetch_meowdump_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      ;;
    yurikey)
      if fetch_yurikey_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      ;;
    custom)
      if fetch_custom_url_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      ;;
    auto|*)
      if [ -s "$CUSTOM_URL_CFG" ] && fetch_custom_url_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      if fetch_specter_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      if fetch_meowdump_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      if fetch_yurikey_keybox "$dec_file"; then
        install_keybox_file "$dec_file"; rm -f "$dec_file"; return 0
      fi
      ;;
  esac

  rm -f "$dec_file"
  log_msg "WARN: All keybox providers ($provider) returned revoked/expired or unreachable keyboxes"
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
