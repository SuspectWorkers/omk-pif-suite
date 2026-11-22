(() => {
  const PIF_DIR = '/data/adb/modules/playintegrityfix';
  const PIF_PROP = `${PIF_DIR}/custom.pif.prop`;
  const PIF_BAK = `${PIF_DIR}/custom.pif.prop.bak`;
  const SUITE_DIR = '/data/adb/modules/omk_pif_suite';
  const OMK_SYNC_ACT = `${SUITE_DIR}/action.sh`;
  const OMK_KEYBOX = '/data/misc/keystore/omk/keybox.xml';
  const OMK_INJ = '/data/misc/keystore/omk/injector.toml';
  const KEEP_KB_FLAG = '/data/adb/omk_pif_sync_keep_keybox';
  const NO_TANGOR_FLAG = '/data/adb/omk_pif_sync_no_tangorpro';
  const PROVIDER_CFG = '/data/adb/omk_pif_sync_provider';
  const CUSTOM_URL_CFG = '/data/adb/omk_pif_sync_keybox_url';
  const QUOTA_FILE = '/data/adb/omk_probe_quota.dat';
  const LAST_STATUS_FILE = '/data/adb/omk_last_status.dat';
  const SYNC_LOG = '/data/local/tmp/omk_pif_sync.log';
  const LIVE_TRACE = '/data/local/tmp/omk_live_trace.log';
  const MODE_KEY = 'omk_pif_suite_mode';

  const BUILD_KEYS = [
    'MANUFACTURER', 'BRAND', 'MODEL', 'PRODUCT', 'DEVICE',
    'FINGERPRINT', 'RELEASE', 'ID', 'INCREMENTAL',
    'SECURITY_PATCH', 'DEVICE_INITIAL_SDK_INT', 'TYPE', 'TAGS'
  ];

  const SWITCH_DEFS = [
    { key: 'spoofBuild', desc: 'Подмена java Build.* полей (MODEL, BRAND, FINGERPRINT и др.) в DroidGuard' },
    { key: 'spoofProps', desc: 'Подмена системных ro.* свойств в DroidGuard через native-перехват' },
    { key: 'spoofProvider', desc: 'Подмена/блокировка AndroidKeyStore в DroidGuard (0 с валидным keybox, 1 без keybox)' },
    { key: 'spoofSignature', desc: 'Подмена подписи ROM (release-keys); обычно 0' },
    { key: 'spoofVendingFinger', desc: 'Подменять Build.FINGERPRINT внутри Play Store (com.android.vending)' },
    { key: 'spoofVendingSdk', desc: 'Подменять SDK_INT на 32 (Android 12) в Play Store — legacy режим <A13' }
  ];

  const DEFAULT_SYS_PROPS = [
    'ro.build.fingerprint',
    'ro.build.id',
    'ro.product.device',
    'ro.product.name',
    'ro.build.version.security_patch',
    'ro.board.first_api_level',
    'ro.product.first_api_level'
  ];

  let state = {
    build: {},
    sysProps: [],
    adv: {
      spoofBuild: '1', spoofProps: '1', spoofProvider: '0',
      spoofSignature: '0', spoofVendingFinger: '1', spoofVendingSdk: '0', verboseLogs: '0'
    },
    metaComments: [],
    rawText: ''
  };

  let cbCounter = 0;
  let busyDepth = 0;
  let resultTimerId = null;

  function log(msg) {
    const el = document.getElementById('consoleLog');
    const ts = new Date().toTimeString().slice(0, 8);
    el.textContent += `[${ts}] ${msg}\n`;
    el.scrollTop = el.scrollHeight;
  }

  function toast(msg) {
    try {
      if (window.ksu && typeof window.ksu.toast === 'function') window.ksu.toast(msg);
    } catch (_) {}
  }

  function hideResultOverlay() {
    if (resultTimerId) {
      clearTimeout(resultTimerId);
      resultTimerId = null;
    }
    const overlay = document.getElementById('resultOverlay');
    const fill = document.getElementById('resultTimerFill');
    overlay.classList.add('hidden');
    overlay.classList.remove('is-success', 'is-error');
    fill.classList.remove('running');
    if (busyDepth === 0) document.body.classList.remove('modal-open');
  }

  function showResultOverlay(isSuccess, title, subtitle = '', durationMs = 4000, checks = null) {
    hideResultOverlay();
    const overlay = document.getElementById('resultOverlay');
    const iconOk = document.getElementById('resultIconSuccess');
    const iconErr = document.getElementById('resultIconError');
    const fill = document.getElementById('resultTimerFill');
    const checksEl = document.getElementById('resultChecksList');

    overlay.classList.toggle('is-success', !!isSuccess);
    overlay.classList.toggle('is-error', !isSuccess);
    iconOk.classList.toggle('hidden', !isSuccess);
    iconErr.classList.toggle('hidden', !!isSuccess);

    // Restart CSS keyframe animations cleanly
    const activeIcon = isSuccess ? iconOk : iconErr;
    activeIcon.style.animation = 'none';
    activeIcon.offsetHeight;
    activeIcon.style.animation = '';

    document.getElementById('resultTitle').textContent = title;
    document.getElementById('resultSub').textContent = subtitle;

    if (checksEl) {
      checksEl.innerHTML = '';
      if (checks && typeof checks === 'object') {
        const items = [
          { label: 'MEETS_BASIC_INTEGRITY', ok: !!checks.basic },
          { label: 'MEETS_DEVICE_INTEGRITY', ok: !!checks.device },
          { label: 'MEETS_STRONG_INTEGRITY', ok: !!checks.strong }
        ];
        items.forEach(it => {
          const row = document.createElement('div');
          row.className = `result-check-row ${it.ok ? 'is-ok' : 'is-bad'}`;
          row.innerHTML = `<span class="rc-badge">${it.ok ? '✓' : '✕'}</span><span>${it.label}</span>`;
          checksEl.appendChild(row);
        });
        checksEl.classList.remove('hidden');
      } else {
        checksEl.classList.add('hidden');
      }
    }

    fill.classList.remove('running');
    fill.style.animationDuration = `${durationMs}ms`;
    overlay.classList.remove('hidden');
    document.body.classList.add('modal-open');
    void fill.offsetWidth;
    fill.classList.add('running');

    resultTimerId = setTimeout(hideResultOverlay, durationMs);
  }

  function showLoading(title, sub = 'Пожалуйста, подождите...', withTrace = false) {
    busyDepth++;
    document.getElementById('loadingTitle').textContent = title || 'Выполняется...';
    document.getElementById('loadingSub').textContent = sub;
    const traceEl = document.getElementById('loadingTrace');
    if (traceEl) {
      traceEl.textContent = withTrace ? 'Инициализация...' : '';
      traceEl.classList.toggle('hidden', !withTrace);
    }
    document.getElementById('loadingOverlay').classList.remove('hidden');
    document.body.classList.add('modal-open');
  }

  function hideLoading() {
    busyDepth = Math.max(0, busyDepth - 1);
    if (busyDepth === 0) {
      document.getElementById('loadingOverlay').classList.add('hidden');
      const traceEl = document.getElementById('loadingTrace');
      if (traceEl) {
        traceEl.classList.add('hidden');
        traceEl.textContent = '';
      }
      document.body.classList.remove('modal-open');
    }
  }

  function updateLoadingTrace(text) {
    const el = document.getElementById('loadingTrace');
    if (!el) return;
    el.classList.remove('hidden');
    el.textContent = text || 'Выполняется...';
    el.scrollTop = el.scrollHeight;
  }

  function nextPaint() {
    return new Promise(resolve => {
      requestAnimationFrame(() => setTimeout(resolve, 45));
    });
  }

  async function withLoading(title, sub, fn) {
    showLoading(title, sub);
    await nextPaint();
    try {
      return await fn();
    } finally {
      hideLoading();
    }
  }

  function execRoot(cmd) {
    return new Promise((resolve, reject) => {
      if (!window.ksu || typeof window.ksu.exec !== 'function') {
        reject(new Error('KernelSU WebUI API (window.ksu) недоступен'));
        return;
      }
      const cbName = `__pifCb_${Date.now()}_${++cbCounter}`;
      window[cbName] = (code, stdout, stderr) => {
        try { delete window[cbName]; } catch (_) { window[cbName] = undefined; }
        resolve({ code: Number(code), stdout: stdout || '', stderr: stderr || '' });
      };
      try {
        window.ksu.exec(cmd, cbName);
      } catch (e) {
        try { delete window[cbName]; } catch (_) {}
        reject(e);
      }
    });
  }

  function toBase64Utf8(str) {
    const bytes = new TextEncoder().encode(str);
    let bin = '';
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }

  function parseAsn1Len(bytes, pos) {
    const first = bytes[pos++];
    if ((first & 0x80) === 0) return { len: first, pos };
    const count = first & 0x7f;
    let len = 0;
    for (let i = 0; i < count; i++) len = (len << 8) | bytes[pos++];
    return { len, pos };
  }

  function extractAllCertSerialsFromXml(xmlText) {
    const out = [];
    const re = /-----BEGIN CERTIFICATE-----\s*([\s\S]+?)\s*-----END CERTIFICATE-----/g;
    let m;
    while ((m = re.exec(xmlText || '')) !== null) {
      try {
        const raw = atob(m[1].replace(/\s+/g, ''));
        const bytes = new Uint8Array(raw.length);
        for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
        let p = 0;
        if (bytes[p++] !== 0x30) continue;
        p = parseAsn1Len(bytes, p).pos;
        if (bytes[p++] !== 0x30) continue;
        p = parseAsn1Len(bytes, p).pos;
        if (bytes[p] === 0xa0) {
          p++;
          const vLen = parseAsn1Len(bytes, p);
          p = vLen.pos + vLen.len;
        }
        if (bytes[p++] !== 0x02) continue;
        const sLen = parseAsn1Len(bytes, p);
        const serialBytes = bytes.slice(sLen.pos, sLen.pos + sLen.len);
        let hex = '';
        for (const b of serialBytes) hex += b.toString(16).padStart(2, '0');
        const trimmed = hex.replace(/^0+/, '') || '0';
        let dec = '';
        try { dec = BigInt('0x' + hex).toString(10); } catch (_) {}
        out.push({ hex, trimmed, dec });
      } catch (_) {}
    }
    return out;
  }

  function parsePropText(text) {
    const lines = text.replace(/\r\n/g, '\n').split('\n');
    const build = {};
    const adv = {
      spoofBuild: '1', spoofProps: '1', spoofProvider: '0',
      spoofSignature: '0', spoofVendingFinger: '0', spoofVendingSdk: '0', verboseLogs: '0'
    };
    const sysMap = new Map();
    const metaComments = [];
    const advKeys = new Set(Object.keys(adv));
    const buildSet = new Set(BUILD_KEYS);

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;
      if (line.startsWith('#')) {
        const uncommented = line.slice(1).trim();
        const eqIdx = uncommented.indexOf('=');
        if (eqIdx > 0 && uncommented.slice(0, eqIdx).startsWith('ro.')) {
          const k = uncommented.slice(0, eqIdx).trim();
          const v = uncommented.slice(eqIdx + 1).split('#')[0].trim();
          sysMap.set(k, { key: k, value: v, commented: true });
          continue;
        }
        if (/Canary|Beta|Expiry|Released/i.test(line)) metaComments.push(line);
        continue;
      }
      const eq = line.indexOf('=');
      if (eq <= 0) continue;
      const k = line.slice(0, eq).trim();
      const v = line.slice(eq + 1).split('#')[0].trim();
      if (buildSet.has(k)) build[k] = v;
      else if (advKeys.has(k)) adv[k] = v;
      else if (k.startsWith('ro.') || k.startsWith('persist.') || k.startsWith('sys.')) {
        sysMap.set(k, { key: k, value: v, commented: false });
      }
    }

    for (const k of DEFAULT_SYS_PROPS) {
      if (!sysMap.has(k)) sysMap.set(k, { key: k, value: '', commented: false });
    }

    return { build, adv, sysProps: Array.from(sysMap.values()), metaComments, rawText: text };
  }

  function serializeState() {
    const out = ['# Build Fields'];
    for (const k of BUILD_KEYS) out.push(`${k}=${(state.build[k] ?? '').trim()}`);
    out.push('', '# System Properties');
    for (const p of state.sysProps) {
      if (!p.key) continue;
      out.push(`${p.commented ? '#' : ''}${p.key}=${(p.value ?? '').trim()}`);
    }
    out.push('', '# Advanced Settings');
    for (const d of SWITCH_DEFS) out.push(`${d.key}=${state.adv[d.key] === '1' ? '1' : '0'}`);
    out.push(`verboseLogs=${(state.adv.verboseLogs ?? '0').trim()}`);
    if (state.metaComments.length) {
      out.push('');
      for (const c of state.metaComments) out.push(c);
    }
    out.push('');
    return out.join('\n');
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function escapeAttr(s) {
    return escapeHtml(s).replace(/"/g, '&quot;');
  }

  function syncRawPreview() {
    document.getElementById('rawEditor').value = serializeState();
  }

  function renderSwitches() {
    const list = document.getElementById('switchesList');
    list.innerHTML = '';
    for (const def of SWITCH_DEFS) {
      const item = document.createElement('div');
      item.className = 'switch-item';
      const checked = state.adv[def.key] === '1' ? 'checked' : '';
      item.innerHTML = `
        <div class="switch-info">
          <strong>${def.key}</strong>
          <span class="hint">${def.desc}</span>
        </div>
        <label class="toggle">
          <input type="checkbox" data-adv="${def.key}" ${checked} />
          <span class="slider"></span>
        </label>
      `;
      list.appendChild(item);
    }
    list.querySelectorAll('input[data-adv]').forEach(inp => {
      inp.addEventListener('change', e => {
        state.adv[e.target.dataset.adv] = e.target.checked ? '1' : '0';
        syncRawPreview();
      });
    });
    const vl = document.getElementById('verboseLogs');
    vl.value = ['0', '1', '2', '3', '100'].includes(state.adv.verboseLogs) ? state.adv.verboseLogs : '100';
  }

  function renderBuildFields() {
    const grid = document.getElementById('buildFieldsGrid');
    grid.innerHTML = '';
    for (const k of BUILD_KEYS) {
      const box = document.createElement('div');
      box.className = 'prop-box';
      box.innerHTML = `
        <div class="prop-head"><span class="prop-name">${k}</span></div>
        <input class="input" type="text" data-build="${k}" value="${escapeAttr(state.build[k] ?? '')}" />
      `;
      grid.appendChild(box);
    }
    grid.querySelectorAll('input[data-build]').forEach(inp => {
      inp.addEventListener('input', e => {
        state.build[e.target.dataset.build] = e.target.value;
        syncRawPreview();
      });
    });
  }

  function renderSysProps() {
    const grid = document.getElementById('sysPropsGrid');
    grid.innerHTML = '';
    state.sysProps.forEach((p, idx) => {
      const box = document.createElement('div');
      box.className = 'prop-box';
      box.innerHTML = `
        <div class="prop-head">
          <span class="prop-name">${escapeHtml(p.key)}</span>
          <label class="inline-check">
            <input type="checkbox" data-pcomment="${idx}" ${p.commented ? 'checked' : ''} />
            <span>#</span>
          </label>
        </div>
        <input class="input" type="text" data-pval="${idx}" value="${escapeAttr(p.value ?? '')}" />
      `;
      grid.appendChild(box);
    });
    grid.querySelectorAll('input[data-pcomment]').forEach(inp => {
      inp.addEventListener('change', e => {
        state.sysProps[Number(e.target.dataset.pcomment)].commented = e.target.checked;
        syncRawPreview();
      });
    });
    grid.querySelectorAll('input[data-pval]').forEach(inp => {
      inp.addEventListener('input', e => {
        state.sysProps[Number(e.target.dataset.pval)].value = e.target.value;
        syncRawPreview();
      });
    });
  }

  function renderAll() {
    renderSwitches();
    renderBuildFields();
    renderSysProps();
    syncRawPreview();
    document.getElementById('metaNote').textContent = state.metaComments.length
      ? state.metaComments.join(' | ')
      : 'Конфигурация загружена';
  }

  function setMode(mode) {
    const isPro = mode === 'pro';
    localStorage.setItem(MODE_KEY, isPro ? 'pro' : 'auto');
    document.getElementById('modeAutoBtn').classList.toggle('active', !isPro);
    document.getElementById('modeProBtn').classList.toggle('active', isPro);
    document.getElementById('autoPanel').classList.toggle('hidden', isPro);
    document.getElementById('proPanel').classList.toggle('hidden', !isPro);
    document.getElementById('btnSave').classList.toggle('hidden', !isPro);
  }

  function updateQuotaUi(used, limit, remaining) {
    const qEl = document.getElementById('stQuota');
    if (!qEl) return;
    const u = Number(used || 0);
    const l = Number(limit || 10000);
    const r = remaining !== undefined ? Number(remaining) : Math.max(0, l - u);
    qEl.textContent = `${u} / ${l} (ост. ${r})`;
    qEl.className = 'stat-v ' + (r <= 0 ? 'badge-bad' : (r < 500 ? 'badge-warn' : 'badge-ok'));
  }

  async function refreshQuota(showPopup = false) {
    try {
      const res = await execRoot(`. "${SUITE_DIR}/common.sh" && get_probe_quota`);
      const map = {};
      res.stdout.split('\n').forEach(l => {
        const i = l.indexOf('=');
        if (i > 0) map[l.slice(0, i)] = l.slice(i + 1).trim();
      });
      if (map.QUOTA_OK === '1') {
        updateQuotaUi(map.QUOTA_USED, map.QUOTA_LIMIT, map.QUOTA_REMAINING);
        const rem = Number(map.QUOTA_REMAINING || 0);
        const msg = `Использовано сегодня: ${map.QUOTA_USED} из ${map.QUOTA_LIMIT} • Осталось: ${rem}`;
        if (showPopup) {
          log('Лимит автономной системы: ' + msg);
          showResultOverlay(rem > 0, rem > 0 ? 'Запас проверок в норме' : 'Лимит проверок исчерпан', msg, 3000);
        }
      } else if (showPopup) {
        showResultOverlay(false, 'Ошибка запроса квоты', map.QUOTA_ERR || 'Нет ответа', 3000);
      }
    } catch (e) {
      if (showPopup) log('Квота: ' + e.message);
    }
  }

  function setPiChip(id, name, stateMode) {
    const el = document.getElementById(id);
    if (!el) return;
    el.classList.remove('is-ok', 'is-bad');
    if (stateMode === true) {
      el.classList.add('is-ok');
      el.textContent = `✓ ${name}: активно`;
    } else if (stateMode === false) {
      el.classList.add('is-bad');
      el.textContent = `✕ ${name}: бан`;
    } else {
      el.textContent = `• ${name}: —`;
    }
  }

  async function loadStatus() {
    try {
      const res = await execRoot(
        `echo "PIF=$(grep -m1 ^version= ${PIF_DIR}/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "OMK=$(grep -m1 ^version= /data/adb/modules/oh_my_keymint/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "INJ=$(. "${SUITE_DIR}/common.sh" && toml_get_in_section "${OMK_INJ}" main enabled 2>/dev/null || echo '?')"\n` +
        `echo "FILT=$(. "${SUITE_DIR}/common.sh" && toml_verify_injector_safe "${OMK_INJ}" >/dev/null 2>&1 && echo safe || echo unsafe)"\n` +
        `echo "PATCH=$(getprop ro.build.version.security_patch)"\n` +
        `echo "FAPI=$(getprop ro.product.first_api_level)"\n` +
        `echo "KEEPKB=$([ -f ${KEEP_KB_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "NOTANG=$([ -f ${NO_TANGOR_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "PROV=$([ -f ${PROVIDER_CFG} ] && cat ${PROVIDER_CFG} 2>/dev/null | tr -d '\\r\\n')"\n` +
        `echo "CURL=$([ -f ${CUSTOM_URL_CFG} ] && cat ${CUSTOM_URL_CFG} 2>/dev/null | tr -d '\\r\\n')"\n` +
        `echo "QUOTA=$([ -f ${QUOTA_FILE} ] && cat ${QUOTA_FILE} 2>/dev/null | tr -d '\\r\\n')"\n` +
        `echo "LSTAT=$([ -f ${LAST_STATUS_FILE} ] && cat ${LAST_STATUS_FILE} 2>/dev/null | tr -d '\\r\\n')"\n` +
        `echo "KB=$([ -s ${OMK_KEYBOX} ] && echo present || echo missing)"\n` +
        `echo "KBCRL=$(if [ -s ${OMK_KEYBOX} ] && [ -s /data/local/tmp/omk_crl_cache.json ]; then . "${SUITE_DIR}/common.sh"; krc=0; validate_keybox_file "${OMK_KEYBOX}" >/dev/null 2>&1 || krc=$?; if [ "$krc" -eq 0 ]; then echo live; elif [ "$krc" -eq 2 ]; then echo offline; else echo revoked; fi; else echo unknown; fi)"`
      );
      const map = {};
      res.stdout.split('\n').forEach(l => {
        const i = l.indexOf('=');
        if (i > 0) map[l.slice(0, i)] = l.slice(i + 1).trim();
      });
      const dev = state.build.DEVICE || '-';
      document.getElementById('stPif').textContent = `${map.PIF || 'нет'} (${dev})`;
      const omkEl = document.getElementById('stOmk');
      const injState = map.INJ === 'false' ? 'off' : (map.INJ === 'true' ? 'on' : '?');
      omkEl.textContent = `${map.OMK || 'нет'} (${injState}${map.FILT === 'unsafe' ? ', unsafe!' : ''})`;
      omkEl.className = 'stat-v ' + (map.FILT === 'unsafe' ? 'badge-bad' : (map.INJ === 'false' ? 'badge-warn' : ''));

      // Compute Basic / Device / Strong chips above status pill with strict hierarchy:
      // Strong requires Device + live non-banned keybox + safe OMK; Device requires Basic + good fingerprint
      let bOk = null; let dOk = null; let sOk = null;
      if (map.LSTAT && map.LSTAT.includes('|')) {
        const parts = map.LSTAT.split('|');
        bOk = parts[0] === '1';
        dOk = parts[1] === '1';
        sOk = parts[2] === '1';
      } else if (map.INJ === 'false') {
        bOk = true; dOk = false; sOk = false;
      }
      if (map.KB !== 'present' || map.KBCRL === 'revoked' || map.INJ !== 'true' || map.FILT !== 'safe') {
        sOk = false;
      }
      if (map.INJ === 'false') {
        dOk = false; sOk = false;
      }
      if (bOk === false) {
        dOk = false; sOk = false;
      }
      if (dOk === false) {
        sOk = false;
      }
      if (map.KBCRL === 'live' && map.INJ === 'true' && map.FILT === 'safe' && dOk === true && bOk === true) {
        sOk = true;
      }
      setPiChip('chipBasic', 'Basic', bOk);
      setPiChip('chipDevice', 'Device', dOk);
      setPiChip('chipStrong', 'Strong', sOk);

      const powerStage = document.getElementById('powerStage');
      const autoDot = document.getElementById('autoStateDot');
      const autoText = document.getElementById('autoStateText');
      const autoBtnLbl = document.getElementById('autoBtnLabel');
      if (powerStage && autoDot && autoText) {
        powerStage.classList.remove('is-on', 'is-basic');
        autoDot.classList.remove('is-on', 'is-basic');
        if (map.INJ === 'true' && map.FILT === 'safe' && map.KB === 'present') {
          powerStage.classList.add('is-on');
          autoDot.classList.add('is-on');
          autoText.textContent = sOk ? `Активно (Strong) • ${dev}` : `Активно • ${dev}`;
          if (autoBtnLbl) autoBtnLbl.textContent = 'ON';
        } else if (map.INJ === 'false') {
          powerStage.classList.add('is-basic');
          autoDot.classList.add('is-basic');
          autoText.textContent = `Режим BASIC • ${dev}`;
          if (autoBtnLbl) autoBtnLbl.textContent = 'BASIC';
        } else {
          autoText.textContent = 'Требуется настройка';
          if (autoBtnLbl) autoBtnLbl.textContent = 'AUTO';
        }
      }
      const kbEl = document.getElementById('stKeybox');
      if (map.KB !== 'present') {
        kbEl.textContent = 'отсутствует';
        kbEl.className = 'stat-v badge-bad';
      } else if (!kbEl.dataset.crlChecked) {
        kbEl.textContent = 'есть (проверьте CRL)';
        kbEl.className = 'stat-v';
      }
      document.getElementById('stRomPatch').textContent = `${map.PATCH || '-'} / API ${map.FAPI || '-'}`;
      if (map.QUOTA && map.QUOTA.includes('|')) {
        const [, qUsed, qLimit] = map.QUOTA.split('|');
        updateQuotaUi(qUsed, qLimit);
      } else {
        updateQuotaUi(0, 10000);
      }
      document.getElementById('chkKeepKeybox').checked = map.KEEPKB === '1';
      document.getElementById('chkNoTangorpro').checked = map.NOTANG === '1';
      const provSel = document.getElementById('selProvider');
      if (provSel) {
        provSel.value = ['auto', 'specter', 'meowdump', 'yurikey', 'custom'].includes(map.PROV) ? map.PROV : 'auto';
        document.getElementById('customProviderUrlRow').classList.toggle('hidden', provSel.value !== 'custom');
      }
      const urlInp = document.getElementById('customProviderUrl');
      if (urlInp && map.CURL !== undefined) urlInp.value = map.CURL;
    } catch (e) {
      log('Статус: ' + e.message);
    }
  }

  async function loadConfig() {
    try {
      const res = await execRoot(
        `if [ -f "${PIF_PROP}" ]; then cat "${PIF_PROP}"; ` +
        `elif [ -f "${PIF_DIR}/pif.prop" ]; then cat "${PIF_DIR}/pif.prop"; ` +
        `elif [ -f "${PIF_DIR}/example.pif.prop" ]; then cat "${PIF_DIR}/example.pif.prop"; fi`
      );
      if (!res.stdout.trim()) {
        log('Файл custom.pif.prop пуст или не найден');
        return;
      }
      state = parsePropText(res.stdout);
      renderAll();
      log(`Загружен ${PIF_PROP} (${res.stdout.length} байт)`);
    } catch (e) {
      log('Ошибка чтения: ' + e.message);
    }
  }

  async function checkKeyboxCrl({ silent = false, autoFallbackOnRevoked = false } = {}) {
    try {
      const kbRes = await execRoot(`cat "${OMK_KEYBOX}" 2>/dev/null || true`);
      const kbEl = document.getElementById('stKeybox');
      if (!kbRes.stdout.includes('BEGIN CERTIFICATE')) {
        kbEl.textContent = 'нет keybox.xml';
        kbEl.className = 'stat-v badge-bad';
        if (!silent) log('Keybox отсутствует или пуст.');
        if (autoFallbackOnRevoked) {
          await execRoot(`. "${SUITE_DIR}/common.sh" && enable_basic_fallback`);
          await loadConfig();
          await loadStatus();
          return {
            valid: false,
            title: 'Keybox не найден',
            subtitle: 'Автоматически включён режим только BASIC (без keybox)'
          };
        }
        return { valid: false, title: 'Keybox отсутствует', subtitle: 'Файл keybox.xml пуст или не найден' };
      }

      const serials = extractAllCertSerialsFromXml(kbRes.stdout);
      if (!serials.length) {
        kbEl.textContent = 'ошибка разбора XML';
        kbEl.className = 'stat-v badge-bad';
        return { valid: false, title: 'Ошибка Keybox', subtitle: 'Не удалось прочитать сертификаты из keybox.xml' };
      }

      const crlCmd =
        `if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 10 https://android.googleapis.com/attestation/status; ` +
        `else /data/adb/ksu/bin/busybox wget -T 10 --no-check-certificate -qO- https://android.googleapis.com/attestation/status; fi`;
      const crlRes = await execRoot(crlCmd);
      const crl = JSON.parse(crlRes.stdout);
      const entries = crl.entries || {};

      let revokedHit = null;
      for (const s of serials) {
        const entry = entries[s.hex] || entries[s.trimmed] || (s.dec ? entries[s.dec] : null) || null;
        if (entry) {
          revokedHit = { serial: s.trimmed, entry };
          break;
        }
      }

      kbEl.dataset.crlChecked = '1';
      const leafSerial = serials[0].trimmed;
      if (revokedHit) {
        const reason = revokedHit.entry.reason || revokedHit.entry.status || 'REVOKED';
        kbEl.textContent = `REVOKED (${reason})`;
        kbEl.className = 'stat-v badge-bad';
        log(`Keybox ${revokedHit.serial}: ОТОЗВАН Google CRL (${revokedHit.entry.status} / ${revokedHit.entry.reason || ''})!`);
        if (autoFallbackOnRevoked) {
          log('Автопереключение в режим только BASIC (отключаем OMK injector, включаем spoofProvider=1)...');
          await execRoot(`. "${SUITE_DIR}/common.sh" && enable_basic_fallback`);
          await loadConfig();
          await loadStatus();
          return {
            valid: false,
            title: 'Keybox отозван (REVOKED)',
            subtitle: `Серийный ${revokedHit.serial.slice(0, 12)}... (${reason}). Автоматически запущен режим только BASIC`
          };
        }
        return {
          valid: false,
          title: 'Keybox отозван (REVOKED)',
          subtitle: `Серийный ${revokedHit.serial.slice(0, 14)}... • Причина: ${reason}`
        };
      }

      kbEl.textContent = `VALID (${leafSerial.slice(0, 8)}...)`;
      kbEl.className = 'stat-v badge-ok';
      log(`Keybox ${leafSerial} (все ${serials.length} серт.): ВАЛИДЕН (отсутствует в CRL Google).`);
      return {
        valid: true,
        title: 'Keybox валиден (LIVE)',
        subtitle: `Проверено сертификатов: ${serials.length} • Leaf: ${leafSerial.slice(0, 14)}...`
      };
    } catch (e) {
      log('Проверка CRL не удалась: ' + e.message);
      return {
        valid: false,
        title: 'Ошибка проверки CRL',
        subtitle: e.message || 'Нет доступа к android.googleapis.com'
      };
    }
  }

  async function saveText(content) {
    return withLoading('Сохранение конфигурации', 'Обновляем custom.pif.prop...', async () => {
      const b64 = toBase64Utf8(content);
      const kill = document.getElementById('chkKillOnSave').checked;
      const cmd = [
        `[ -f "${PIF_PROP}" ] && cp -f "${PIF_PROP}" "${PIF_BAK}"`,
        `printf '%s' '${b64}' | base64 -d > "${PIF_PROP}.tmp"`,
        `mv -f "${PIF_PROP}.tmp" "${PIF_PROP}"`,
        `chmod 0644 "${PIF_PROP}"`,
        kill && `[ -f "${PIF_DIR}/killpi.sh" ] && sh "${PIF_DIR}/killpi.sh" || true`
      ].filter(Boolean).join(' && ');

      const res = await execRoot(cmd);
      log((res.stdout + '\n' + res.stderr).trim() || 'Сохранено в ' + PIF_PROP);
      toast(res.code === 0 ? ('Сохранено' + (kill ? ' + GMS/Play перезапущены' : '')) : ('Ошибка сохранения: ' + res.code));
      await loadStatus();
    });
  }

  async function runAction(label, sub, cmd, { reloadAfter = false, checkCrl = false, autoFallbackOnRevoked = false, showOverlay = false } = {}) {
    let crlResult = null;
    await withLoading(label, sub, async () => {
      log(`Запуск: ${label}...`);
      try {
        const res = await execRoot(cmd);
        const out = (res.stdout + '\n' + res.stderr).trim();
        log(out || `Готово (код ${res.code})`);
        if (reloadAfter) {
          await loadConfig();
          await loadStatus();
        }
        if (res.code !== 0) {
          toast(`${label}: ошибка (код ${res.code})`);
          if (showOverlay) {
            const tail = out ? out.split('\n').slice(-2).join(' • ') : `Код выхода: ${res.code}`;
            crlResult = { valid: false, title: `Ошибка: ${label}`, subtitle: tail };
          }
          return;
        }
        toast(`${label}: OK`);
        if (checkCrl) {
          crlResult = await checkKeyboxCrl({ silent: false, autoFallbackOnRevoked });
        }
      } catch (e) {
        log(`Ошибка (${label}): ${e.message}`);
        toast('Ошибка: ' + e.message);
        if (showOverlay) {
          crlResult = { valid: false, title: 'Ошибка выполнения', subtitle: e.message };
        }
      }
    });
    if (showOverlay && crlResult) {
      showResultOverlay(crlResult.valid, crlResult.title, crlResult.subtitle, 3000);
    }
  }

  function applyDevicePreset(dev, prod, model, sdk) {
    const rel = state.build.RELEASE || 'CANARY';
    const bid = state.build.ID || 'ZP11.261016.008';
    const inc = state.build.INCREMENTAL || '16754936';
    const typ = state.build.TYPE || 'user';
    const tgs = state.build.TAGS || 'release-keys';
    const fp = `google/${prod}/${dev}:${rel}/${bid}/${inc}:${typ}/${tgs}`;
    Object.assign(state.build, {
      MANUFACTURER: 'Google', BRAND: 'google', MODEL: model, PRODUCT: prod, DEVICE: dev,
      FINGERPRINT: fp, DEVICE_INITIAL_SDK_INT: sdk
    });
    const updates = new Map([
      ['ro.build.fingerprint', fp], ['ro.build.id', bid], ['ro.product.device', dev],
      ['ro.product.name', prod], ['ro.product.first_api_level', sdk]
    ]);
    for (const [k, v] of updates) {
      const ex = state.sysProps.find(p => p.key === k);
      if (ex) { ex.value = v; ex.commented = false; }
      else state.sysProps.push({ key: k, value: v, commented: false });
    }
    Object.assign(state.adv, {
      spoofBuild: '1', spoofProps: '1', spoofProvider: '0',
      spoofSignature: '0', spoofVendingFinger: '1', spoofVendingSdk: '0'
    });
    renderAll();
    log(`Применён профиль ${model} (${dev}, SDK ${sdk}). Нажмите «Сохранить».`);
  }

  function applyPreset(name) {
    if (name === 'kodiak') return applyDevicePreset('kodiak', 'kodiak_beta', 'Pixel 11 Pro XL', '37');
    if (name === 'frankel') return applyDevicePreset('frankel', 'frankel_beta', 'Pixel 10', '36');
    if (name === 'tegu') return applyDevicePreset('tegu', 'tegu_beta', 'Pixel 9a', '35');
    if (name === 'tangorpro') return applyDevicePreset('tangorpro', 'tangorpro_beta', 'Pixel Tablet', '33');
    if (name === 'felix') return applyDevicePreset('felix', 'felix_beta', 'Pixel Fold', '33');
    if (name === 'bluejay') return applyDevicePreset('bluejay', 'bluejay_beta', 'Pixel 6a', '32');

    const presets = {
      omk_a13: { spoofBuild: '1', spoofProps: '1', spoofProvider: '0', spoofSignature: '0', spoofVendingFinger: '1', spoofVendingSdk: '0' },
      pif_legacy: { spoofBuild: '1', spoofProps: '1', spoofProvider: '1', spoofSignature: '0', spoofVendingFinger: '1', spoofVendingSdk: '1' },
      all_off: { spoofBuild: '0', spoofProps: '0', spoofProvider: '0', spoofSignature: '0', spoofVendingFinger: '0', spoofVendingSdk: '0' }
    };
    const p = presets[name];
    if (!p) return;
    Object.assign(state.adv, p);
    renderSwitches();
    syncRawPreview();
    log(`Применён пресет "${name}". Нажмите «Сохранить».`);
  }

  async function toggleFlag(path, enabled, label) {
    const cmd = enabled ? `mkdir -p /data/adb && touch "${path}"` : `rm -f "${path}"`;
    const res = await execRoot(cmd);
    log(`${label}: ${enabled ? 'ВКЛ' : 'ВЫКЛ'} (rc=${res.code})`);
    await loadStatus();
  }

  async function runCrlCheckWithOverlay() {
    let result = null;
    await withLoading('Проверка Keybox в Google CRL', 'Сверяем все сертификаты цепочки...', async () => {
      result = await checkKeyboxCrl({ silent: false, autoFallbackOnRevoked: false });
    });
    if (result) {
      showResultOverlay(result.valid, result.title, result.subtitle, 3000);
    }
  }

  function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
  }

  async function runDetachedWithTrace(title, sub, shellCmd) {
    showLoading(title, sub, true);
    await nextPaint();
    const id = `${Date.now()}_${++cbCounter}`;
    const outFile = `/data/local/tmp/omk_bg_${id}.out`;
    const rcFile = `/data/local/tmp/omk_bg_${id}.rc`;
    const runFile = `/data/local/tmp/omk_bg_${id}.sh`;
    const b64Cmd = toBase64Utf8(shellCmd);

    try {
      await execRoot(
        `: > "${LIVE_TRACE}" && rm -f "${outFile}" "${rcFile}" && ` +
        `printf '%s' '${b64Cmd}' | base64 -d > "${runFile}" && chmod 0755 "${runFile}" && ` +
        `sh -c 'sh "'"${runFile}"'" >"'"${outFile}"'" 2>&1; echo $? > "'"${rcFile}"'"' >/dev/null 2>&1 </dev/null &`
      );

      let exitCode = null;
      let lastTrace = '';
      for (let tick = 0; tick < 360; tick++) {
        await sleep(450);
        const poll = await execRoot(
          `if [ -f "${rcFile}" ]; then echo "__OMK_DONE__=$(cat "${rcFile}")"; fi\n` +
          `echo "__OMK_TRACE__"\n` +
          `tail -n 14 "${LIVE_TRACE}" 2>/dev/null || true`
        );
        const text = poll.stdout || '';
        const marker = text.indexOf('__OMK_TRACE__');
        const head = marker >= 0 ? text.slice(0, marker) : '';
        const tracePart = marker >= 0 ? text.slice(marker + 13).trim() : '';
        if (tracePart && tracePart !== lastTrace) {
          lastTrace = tracePart;
          updateLoadingTrace(tracePart);
        }
        const m = /__OMK_DONE__=(-?\d+)/.exec(head);
        if (m) {
          exitCode = Number(m[1]);
          break;
        }
      }

      const outRes = await execRoot(`cat "${outFile}" 2>/dev/null || true; rm -f "${outFile}" "${rcFile}" "${runFile}"`);
      if (exitCode === null) {
        return { code: 124, stdout: outRes.stdout || '', stderr: 'Таймаут ожидания операции' };
      }
      return { code: exitCode, stdout: outRes.stdout || '', stderr: '' };
    } finally {
      hideLoading();
    }
  }

  async function runPlayStoreVerify(autoFix) {
    let overlay = null;
    const title = autoFix ? 'Проверка и автоподбор фингерпринта' : 'Проверка Play Integrity';
    const sub = autoFix
      ? 'Автономная проверка (при неудаче — автоподбор профиля)'
      : 'Запрос к автономной системе проверки Integrity';
    log(`Запуск: ${title}...`);
    try {
      const fn = autoFix ? 'verify_and_autofix_fingerprint' : 'check_play_integrity';
      const cmd = `. "${SUITE_DIR}/common.sh" && reset_trace && ${fn}`;
      const res = await runDetachedWithTrace(title, sub, cmd);
      const out = (res.stdout + '\n' + res.stderr).trim();
      if (out) log(out);

      const map = {};
      out.split('\n').forEach(l => {
        const idx = l.indexOf('=');
        if (idx > 0 && l.startsWith('RESULT_')) map[l.slice(0, idx)] = l.slice(idx + 1).trim();
      });
      const v = map.RESULT_VERDICT || 'ERROR';
      const prof = map.RESULT_PROFILE || state.build.DEVICE || '-';
      const labels = map.RESULT_LABELS || '';
      const passed = v === 'STRONG' || v === 'DEVICE';

      if (map.RESULT_USED !== undefined) {
        updateQuotaUi(map.RESULT_USED, map.RESULT_LIMIT, map.RESULT_REMAINING);
      }

      await loadConfig();
      await loadStatus();

      const bOk = map.RESULT_BASIC === '1' || passed;
      const dOk = map.RESULT_DEVICE === '1' || passed;
      const sOk = map.RESULT_STRONG === '1' || v === 'STRONG';
      const checks = (v === 'ERROR' || v === 'QUOTA') ? null : { basic: bOk, device: dOk, strong: sOk };

      overlay = {
        valid: passed,
        title: sOk
          ? 'MEETS_STRONG_INTEGRITY'
          : (dOk ? 'MEETS_DEVICE_INTEGRITY' : (v === 'QUOTA' ? 'Лимит проверок исчерпан' : `Play Integrity: ${v}`)),
        subtitle: `Профиль: ${prof} • ${labels}`,
        checks
      };
    } catch (e) {
      log('Ошибка проверки Play Integrity: ' + e.message);
      overlay = { valid: false, title: 'Ошибка проверки', subtitle: e.message, checks: null };
    }
    if (overlay) {
      showResultOverlay(overlay.valid, overlay.title, overlay.subtitle, 4000, overlay.checks);
    }
  }

  async function runAutoFullCycle(isAutoBtn = true) {
    let overlay = null;
    const title = isAutoBtn ? 'AUTO-настройка Play Integrity' : 'Full Sync (action.sh)';
    const sub = 'Живая трассировка шагов выполняется ниже...';
    log(`Запуск: ${title}...`);
    try {
      const arg = isAutoBtn ? '--auto' : '';
      const res = await runDetachedWithTrace(title, sub, `sh "${OMK_SYNC_ACT}" ${arg}`);
      const out = (res.stdout + '\n' + res.stderr).trim();
      if (out) log(out);

      const map = {};
      out.split('\n').forEach(l => {
        const idx = l.indexOf('=');
        if (idx > 0 && l.startsWith('RESULT_')) map[l.slice(0, idx)] = l.slice(idx + 1).trim();
      });

      if (map.RESULT_USED !== undefined) {
        updateQuotaUi(map.RESULT_USED, map.RESULT_LIMIT, map.RESULT_REMAINING);
      }

      await loadConfig();
      await loadStatus();

      const bOk = map.RESULT_BASIC === '1' || map.RESULT_VERDICT === 'STRONG' || map.RESULT_VERDICT === 'DEVICE';
      const dOk = map.RESULT_DEVICE === '1' || map.RESULT_VERDICT === 'STRONG' || map.RESULT_VERDICT === 'DEVICE';
      const sOk = map.RESULT_STRONG === '1' || map.RESULT_VERDICT === 'STRONG';
      const checks = (map.RESULT_VERDICT && map.RESULT_VERDICT !== 'ERROR' && map.RESULT_VERDICT !== 'QUOTA') || map.RESULT_FALLBACK === 'BASIC'
        ? { basic: bOk, device: dOk, strong: sOk }
        : null;

      if (res.code !== 0) {
        const tail = out ? out.split('\n').slice(-2).join(' • ') : `Код ошибки: ${res.code}`;
        overlay = { valid: false, title: 'Ошибка настройки', subtitle: tail, checks: null };
      } else if (map.RESULT_FALLBACK === 'BASIC') {
        overlay = {
          valid: false,
          title: 'Keybox отозваны → режим BASIC',
          subtitle: `Включён безопасный режим без keybox (${map.RESULT_PROFILE || '-'})`,
          checks: { basic: true, device: false, strong: false }
        };
      } else if (sOk || dOk) {
        overlay = {
          valid: true,
          title: sOk ? 'MEETS_STRONG_INTEGRITY' : 'MEETS_DEVICE_INTEGRITY',
          subtitle: `Профиль: ${map.RESULT_PROFILE || '-'}${map.RESULT_SKIPPED_UPDATE === '1' ? ' • Уже активно' : ''}`,
          checks
        };
      } else {
        const crl = await checkKeyboxCrl({ silent: false, autoFallbackOnRevoked: false });
        overlay = {
          valid: crl.valid && map.RESULT_VERDICT !== 'NONE',
          title: map.RESULT_VERDICT ? `Integrity: ${map.RESULT_VERDICT}` : crl.title,
          subtitle: `${map.RESULT_PROFILE || ''} • ${crl.subtitle}`,
          checks
        };
      }
    } catch (e) {
      log('Ошибка AUTO-настройки: ' + e.message);
      overlay = { valid: false, title: 'Ошибка выполнения', subtitle: e.message, checks: null };
    }
    if (overlay) {
      showResultOverlay(overlay.valid, overlay.title, overlay.subtitle, 4000, overlay.checks);
    }
  }

  function initEvents() {
    document.getElementById('resultOverlay').addEventListener('click', hideResultOverlay);
    document.getElementById('modeAutoBtn').addEventListener('click', () => setMode('auto'));
    document.getElementById('modeProBtn').addEventListener('click', () => setMode('pro'));

    document.querySelectorAll('.tab').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
      });
    });

    document.querySelectorAll('[data-preset]').forEach(btn => {
      btn.addEventListener('click', () => applyPreset(btn.dataset.preset));
    });

    document.getElementById('selProvider').addEventListener('change', async e => {
      const val = e.target.value;
      document.getElementById('customProviderUrlRow').classList.toggle('hidden', val !== 'custom');
      await execRoot(`mkdir -p /data/adb && printf '%s' '${val}' > "${PROVIDER_CFG}"`);
      log(`Провайдер keybox установлен: ${val}`);
    });

    document.getElementById('btnSaveProviderUrl').addEventListener('click', async () => {
      const url = document.getElementById('customProviderUrl').value.trim();
      const b64 = toBase64Utf8(url);
      await execRoot(`mkdir -p /data/adb && printf '%s' '${b64}' | base64 -d > "${CUSTOM_URL_CFG}"`);
      log(`Custom Keybox URL сохранён: ${url || '(пусто)'}`);
      toast('URL провайдера сохранён');
    });

    document.getElementById('btnProQuota').addEventListener('click', () => {
      withLoading('Запрос запаса проверок', 'Сверяем дневной счётчик автономной системы...', () => refreshQuota(true));
    });

    document.getElementById('chkKeepKeybox').addEventListener('change', e => toggleFlag(KEEP_KB_FLAG, e.target.checked, 'keep_keybox'));
    document.getElementById('chkNoTangorpro').addEventListener('change', e => toggleFlag(NO_TANGOR_FLAG, e.target.checked, 'no_tangorpro'));

    document.getElementById('verboseLogs').addEventListener('change', e => {
      state.adv.verboseLogs = e.target.value;
      syncRawPreview();
    });

    document.getElementById('btnReload').addEventListener('click', () => {
      withLoading('Обновление статуса', 'Читаем конфигурацию...', async () => {
        await loadConfig();
        await loadStatus();
      });
    });

    document.getElementById('btnSave').addEventListener('click', () => saveText(serializeState()));

    document.getElementById('btnApplyRaw').addEventListener('click', () => {
      state = parsePropText(document.getElementById('rawEditor').value);
      renderAll();
      log('Raw текст применён в форму.');
    });

    document.getElementById('btnSaveRaw').addEventListener('click', () => {
      const raw = document.getElementById('rawEditor').value;
      state = parsePropText(raw);
      renderAll();
      saveText(raw);
    });

    document.getElementById('btnSyncSysProps').addEventListener('click', () => {
      const map = new Map(state.sysProps.map(p => [p.key, p]));
      const pairs = [
        ['ro.build.fingerprint', state.build.FINGERPRINT || ''],
        ['ro.build.id', state.build.ID || ''],
        ['ro.product.device', state.build.DEVICE || ''],
        ['ro.product.name', state.build.PRODUCT || ''],
        ['ro.build.version.security_patch', state.build.SECURITY_PATCH || ''],
        ['ro.product.first_api_level', state.build.DEVICE_INITIAL_SDK_INT || '']
      ];
      for (const [k, v] of pairs) {
        if (!v) continue;
        if (map.has(k)) map.get(k).value = v;
        else state.sysProps.push({ key: k, value: v, commented: false });
      }
      renderSysProps();
      syncRawPreview();
      log('Build Fields скопированы в System Props.');
    });

    document.getElementById('btnAddProp').addEventListener('click', () => {
      const kEl = document.getElementById('newPropKey');
      const vEl = document.getElementById('newPropVal');
      const k = kEl.value.trim();
      const v = vEl.value.trim();
      if (!k) return;
      const existing = state.sysProps.find(p => p.key === k);
      if (existing) { existing.value = v; existing.commented = false; }
      else state.sysProps.push({ key: k, value: v, commented: false });
      kEl.value = ''; vEl.value = '';
      renderSysProps();
      syncRawPreview();
    });

    // AUTO mode single full-cycle button
    document.getElementById('btnAutoRun').addEventListener('click', () => runAutoFullCycle(true));

    // PRO mode actions
    document.getElementById('btnProFallback').addEventListener('click', () => {
      const cmd = `. "${SUITE_DIR}/common.sh" && enable_basic_fallback`;
      runAction(
        'Переключение в режим BASIC',
        'Отключаем keybox (injector=off) и включаем программный фолбэк (spoofProvider=1)...',
        cmd,
        { reloadAfter: true }
      );
    });

    document.getElementById('btnToggleKeyboxBox').addEventListener('click', () => {
      document.getElementById('customKeyboxBox').classList.toggle('hidden');
    });

    document.getElementById('btnSaveCustomKeybox').addEventListener('click', () => {
      const xml = document.getElementById('keyboxXmlInput').value.trim();
      if (!xml.includes('<AndroidAttestation>') || !xml.includes('BEGIN CERTIFICATE')) {
        toast('Некорректный keybox.xml');
        log('Ошибка: вставьте полный XML с <AndroidAttestation> и сертификатами.');
        return;
      }
      const b64 = toBase64Utf8(xml + '\n');
      const cmd =
        `mkdir -p /data/adb /data/misc/keystore/omk && ` +
        `touch "${KEEP_KB_FLAG}" && ` +
        `printf '%s' '${b64}' | base64 -d > "${OMK_KEYBOX}.tmp" && ` +
        `mv -f "${OMK_KEYBOX}.tmp" "${OMK_KEYBOX}" && ` +
        `chown 1017:1017 "${OMK_KEYBOX}" && chmod 0600 "${OMK_KEYBOX}" && ` +
        `. "${SUITE_DIR}/common.sh" && set_omk_injector_enabled true && force_tangorpro_canary && force_basic_settings && sync_omk_config && reload_omk && cleanup_google && reset_finsky_integrity_cache`;
      runAction(
        'Установка своего keybox.xml',
        'Сохраняем keybox, включаем keep_keybox и перезапускаем OMK...',
        cmd,
        { reloadAfter: true, checkCrl: true, autoFallbackOnRevoked: false, showOverlay: true }
      );
    });

    document.getElementById('btnOmkSync').addEventListener('click', () => runAutoFullCycle(false));
    document.getElementById('btnProCheckPi').addEventListener('click', () => runPlayStoreVerify(false));
    document.getElementById('btnProAutoPick').addEventListener('click', () => runPlayStoreVerify(true));
    document.getElementById('btnSyncLocal').addEventListener('click', () => {
      runAction(
        'Синхронизация PIF → OMK',
        'Обновление OMK config.toml и перезапуск...',
        `. "${SUITE_DIR}/common.sh" && sync_omk_config && reload_omk && cleanup_google`,
        { reloadAfter: true }
      );
    });
    document.getElementById('btnAutopif').addEventListener('click', () => {
      runAction('autopif4.sh -m', 'Загрузка свежего Pixel Canary профиля...', `sh "${PIF_DIR}/autopif4.sh" -m`, { reloadAfter: true });
    });
    document.getElementById('btnKillPi').addEventListener('click', () => {
      runAction('Kill GMS / Vending', 'Перезапуск процессов Play Integrity...', `sh "${PIF_DIR}/killpi.sh"`);
    });
    document.getElementById('btnCheckCrlPro').addEventListener('click', runCrlCheckWithOverlay);
    document.getElementById('btnReadSyncLog').addEventListener('click', async () => {
      const res = await execRoot(`cat "${SYNC_LOG}" 2>/dev/null || echo "Лог пуст"`);
      log('--- omk_pif_sync.log ---\n' + res.stdout.trim());
    });
    document.getElementById('btnRestoreBak').addEventListener('click', () => {
      runAction(
        'Восстановление .bak',
        'Откат custom.pif.prop.bak...',
        `if [ -f "${PIF_BAK}" ]; then cp -f "${PIF_BAK}" "${PIF_PROP}" && chmod 0644 "${PIF_PROP}" && sh "${PIF_DIR}/killpi.sh"; else echo ".bak не найден"; fi`,
        { reloadAfter: true }
      );
    });
    document.getElementById('btnClearLog').addEventListener('click', () => {
      document.getElementById('consoleLog').textContent = '';
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    try {
      if (window.ksu && typeof window.ksu.enableEdgeToEdge === 'function') window.ksu.enableEdgeToEdge(true);
    } catch (_) {}
    const savedMode = localStorage.getItem(MODE_KEY);
    setMode(savedMode === 'pro' ? 'pro' : 'auto');
    initEvents();
    loadConfig().then(() => loadStatus());
  });
})();
