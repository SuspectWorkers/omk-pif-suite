#!/system/bin/sh
MODDIR="${0%/*}"
[ -f "$MODDIR/common.sh" ] && . "$MODDIR/common.sh"

restore_toml_key() {
  r_file=$1
  r_sec=$2
  r_key=$3
  r_orig=$4
  [ -f "$r_file" ] || return 0
  dir=${r_file%/*}
  base=${r_file##*/}
  tmp="${dir}/.${base}.uninst.$$"

  if [ "$r_orig" = "<ABSENT>" ]; then
    awk -v sec="[$r_sec]" -v k="$r_key" '
      BEGIN { in_sec=(sec=="[]" ? 1 : 0) }
      /^[[:space:]]*\[.*\][[:space:]]*$/ {
        cur=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
        in_sec = (cur == sec)
        print; next
      }
      {
        if (in_sec && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=")) next
        print
      }
    ' "$r_file" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    # Boolean values in TOML (true/false) must remain unquoted; others quoted
    awk -v sec="[$r_sec]" -v k="$r_key" -v v="$r_orig" '
      BEGIN { in_sec=(sec=="[]" ? 1 : 0); done=0 }
      /^[[:space:]]*\[.*\][[:space:]]*$/ {
        if (in_sec && !done) {
          if (v == "true" || v == "false") print k " = " v
          else print k " = \"" v "\""
          done=1
        }
        cur=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
        in_sec = (cur == sec)
        print; next
      }
      {
        if (in_sec && $0 ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
          if (v == "true" || v == "false") print k " = " v
          else print k " = \"" v "\""
          done=1; next
        }
        print
      }
      END {
        if (in_sec && !done) {
          if (v == "true" || v == "false") print k " = " v
          else print k " = \"" v "\""
        }
      }
    ' "$r_file" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi

  atomic_replace_omk_file "$r_file" "$tmp" 0600
}

if [ -f "$STATE_DB" ]; then
  while IFS='|' read -r s_file s_sec s_key s_orig s_written; do
    [ -n "$s_file" ] && [ -f "$s_file" ] || continue
    if [ "$s_key" = "scoop_ka" ] && [ "$s_orig" = "<ABSENT>" ]; then
      if grep -q '"io.github.vvb2060.keyattestation"' "$s_file" 2>/dev/null; then
        dir=${s_file%/*}; base=${s_file##*/}
        tmp="${dir}/.${base}.uninst.$$"
        grep -v '"io.github.vvb2060.keyattestation"' "$s_file" > "$tmp" && atomic_replace_omk_file "$s_file" "$tmp" 0600 || rm -f "$tmp"
      fi
      continue
    fi
    cur_val=$(toml_get_in_section "$s_file" "$s_sec" "$s_key" 2>/dev/null || echo "<ABSENT>")
    if [ "$cur_val" = "$s_written" ]; then
      restore_toml_key "$s_file" "$s_sec" "$s_key" "$s_orig" || true
    fi
  done < "$STATE_DB"
fi

# Critical safeguard: never leave OMK [main].enabled=true when [filter] is unsafe
if [ -f "$OMK_INJ" ]; then
  main_en=$(toml_get_in_section "$OMK_INJ" main enabled 2>/dev/null || echo "")
  if [ "$main_en" = "true" ] && ! toml_verify_injector_safe "$OMK_INJ" >/dev/null 2>&1; then
    _write_injector_main_enabled "$OMK_INJ" false >/dev/null 2>&1 || true
    log_msg "Uninstall safety check: forced [main].enabled=false due to unsafe [filter]"
  fi
fi

reload_omk
rm -f "$STATE_DB" "$QUOTA_FILE" "$LOG_FILE" "$CRL_CACHE" 2>/dev/null || true
if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
  pm uninstall "$PROBE_PKG" >/dev/null 2>&1 || true
fi
