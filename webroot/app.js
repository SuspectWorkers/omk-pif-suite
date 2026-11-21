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
  const SYNC_LOG = '/data/local/tmp/omk_pif_sync.log';
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

  function showLoading(title, sub = 'Пожалуйста, подождите...') {
    busyDepth++;
    document.getElementById('loadingTitle').textContent = title || 'Выполняется...';
    document.getElementById('loadingSub').textContent = sub;
    document.getElementById('loadingOverlay').classList.remove('hidden');
    document.body.classList.add('modal-open');
  }

  function hideLoading() {
    busyDepth = Math.max(0, busyDepth - 1);
    if (busyDepth === 0) {
      document.getElementById('loadingOverlay').classList.add('hidden');
      document.body.classList.remove('modal-open');
    }
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

  function extractLeafSerialFromXml(xmlText) {
    const m = /-----BEGIN CERTIFICATE-----\s*([\s\S]+?)\s*-----END CERTIFICATE-----/.exec(xmlText || '');
    if (!m) return null;
    const raw = atob(m[1].replace(/\s+/g, ''));
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    let p = 0;
    if (bytes[p++] !== 0x30) return null;
    p = parseAsn1Len(bytes, p).pos;
    if (bytes[p++] !== 0x30) return null;
    p = parseAsn1Len(bytes, p).pos;
    if (bytes[p] === 0xa0) {
      p++;
      const vLen = parseAsn1Len(bytes, p);
      p = vLen.pos + vLen.len;
    }
    if (bytes[p++] !== 0x02) return null;
    const sLen = parseAsn1Len(bytes, p);
    const serialBytes = bytes.slice(sLen.pos, sLen.pos + sLen.len);
    let hex = '';
    for (const b of serialBytes) hex += b.toString(16).padStart(2, '0');
    const trimmed = hex.replace(/^0+/, '') || '0';
    return { hex, trimmed };
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
    localStorage.setItem(MODE_KEY, isPro ? 'pro' : 'basic');
    document.getElementById('modeBasicBtn').classList.toggle('active', !isPro);
    document.getElementById('modeProBtn').classList.toggle('active', isPro);
    document.getElementById('basicPanel').classList.toggle('hidden', isPro);
    document.getElementById('proPanel').classList.toggle('hidden', !isPro);
    document.getElementById('btnSave').classList.toggle('hidden', !isPro);
  }

  async function loadStatus() {
    try {
      const res = await execRoot(
        `echo "PIF=$(grep -m1 ^version= ${PIF_DIR}/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "OMK=$(grep -m1 ^version= /data/adb/modules/oh_my_keymint/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "INJ=$(grep -m1 '^enabled =' ${OMK_INJ} 2>/dev/null | awk '{print $3}')"\n` +
        `echo "PATCH=$(getprop ro.build.version.security_patch)"\n` +
        `echo "FAPI=$(getprop ro.product.first_api_level)"\n` +
        `echo "KEEPKB=$([ -f ${KEEP_KB_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "NOTANG=$([ -f ${NO_TANGOR_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "KB=$([ -s ${OMK_KEYBOX} ] && echo present || echo missing)"`
      );
      const map = {};
      res.stdout.split('\n').forEach(l => {
        const i = l.indexOf('=');
        if (i > 0) map[l.slice(0, i)] = l.slice(i + 1).trim();
      });
      const dev = state.build.DEVICE || '-';
      document.getElementById('stPif').textContent = `${map.PIF || 'нет'} (${dev})`;
      const omkEl = document.getElementById('stOmk');
      omkEl.textContent = `${map.OMK || 'нет'} (${map.INJ === 'false' ? 'off' : 'on'})`;
      omkEl.className = 'stat-v ' + (map.INJ === 'false' ? 'badge-warn' : '');
      const kbEl = document.getElementById('stKeybox');
      if (map.KB !== 'present') {
        kbEl.textContent = 'отсутствует';
        kbEl.className = 'stat-v badge-bad';
      } else if (!kbEl.dataset.crlChecked) {
        kbEl.textContent = 'есть (проверьте CRL)';
        kbEl.className = 'stat-v';
      }
      document.getElementById('stRomPatch').textContent = `${map.PATCH || '-'} / API ${map.FAPI || '-'}`;
      document.getElementById('chkKeepKeybox').checked = map.KEEPKB === '1';
      document.getElementById('chkNoTangorpro').checked = map.NOTANG === '1';
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

  async function checkKeyboxCrl(silent = false) {
    try {
      const kbRes = await execRoot(`cat "${OMK_KEYBOX}" 2>/dev/null || true`);
      const kbEl = document.getElementById('stKeybox');
      if (!kbRes.stdout.includes('BEGIN CERTIFICATE')) {
        kbEl.textContent = 'нет keybox.xml';
        kbEl.className = 'stat-v badge-bad';
        if (!silent) log('Keybox отсутствует или пуст.');
        return;
      }
      const serial = extractLeafSerialFromXml(kbRes.stdout);
      if (!serial) {
        kbEl.textContent = 'ошибка разбора XML';
        kbEl.className = 'stat-v badge-bad';
        return;
      }
      const crlCmd =
        `if command -v curl >/dev/null 2>&1; then curl -sL --connect-timeout 10 https://android.googleapis.com/attestation/status; ` +
        `else /data/adb/ksu/bin/busybox wget -T 10 --no-check-certificate -qO- https://android.googleapis.com/attestation/status; fi`;
      const crlRes = await execRoot(crlCmd);
      const crl = JSON.parse(crlRes.stdout);
      const entry = (crl.entries && (crl.entries[serial.hex] || crl.entries[serial.trimmed])) || null;
      kbEl.dataset.crlChecked = '1';
      if (entry) {
        kbEl.textContent = `REVOKED (${entry.reason || entry.status})`;
        kbEl.className = 'stat-v badge-bad';
        log(`Keybox ${serial.trimmed}: ОТОЗВАН Google CRL (${entry.status} / ${entry.reason || ''})! Нужен свежий keybox.xml (либо переключитесь на «Режим только BASIC»).`);
      } else {
        kbEl.textContent = `VALID (${serial.trimmed.slice(0, 8)}...)`;
        kbEl.className = 'stat-v badge-ok';
        log(`Keybox ${serial.trimmed}: ВАЛИДЕН (отсутствует в CRL Google).`);
      }
    } catch (e) {
      log('Проверка CRL не удалась: ' + e.message);
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

  async function runAction(label, sub, cmd, reloadAfter = false, checkCrl = false) {
    return withLoading(label, sub, async () => {
      log(`Запуск: ${label}...`);
      try {
        const res = await execRoot(cmd);
        const out = (res.stdout + '\n' + res.stderr).trim();
        log(out || `Готово (код ${res.code})`);
        toast(`${label}: ${res.code === 0 ? 'OK' : 'код ' + res.code}`);
        if (reloadAfter) {
          await loadConfig();
          await loadStatus();
        }
        if (checkCrl) {
          await checkKeyboxCrl(false);
        }
      } catch (e) {
        log(`Ошибка (${label}): ${e.message}`);
        toast('Ошибка: ' + e.message);
      }
    });
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

  function initEvents() {
    document.getElementById('modeBasicBtn').addEventListener('click', () => setMode('basic'));
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

    // Basic mode actions
    document.getElementById('btnBasicFix').addEventListener('click', () => {
      const cmd =
        `[ -f "${OMK_INJ}" ] && sed -i 's/^enabled = false/enabled = true/' "${OMK_INJ}" && chown 1017:1017 "${OMK_INJ}" && chmod 0600 "${OMK_INJ}" || true; ` +
        `sh "${OMK_SYNC_ACT}" --basic`;
      runAction('Basic Full Sync', 'Обновляем Canary (tangorpro), качаем Yurikey и синхронизируем OMK...', cmd, true, true);
    });

    document.getElementById('btnBasicCheckCrl').addEventListener('click', () => {
      withLoading('Проверка Keybox в Google CRL', 'Сверяем серийный номер сертификата...', () => checkKeyboxCrl(false));
    });

    document.getElementById('btnBasicFallback').addEventListener('click', () => {
      const cmd =
        `[ -f "${OMK_INJ}" ] && sed -i 's/^enabled = true/enabled = false/' "${OMK_INJ}" && chown 1017:1017 "${OMK_INJ}" && chmod 0600 "${OMK_INJ}" || true; ` +
        `. "${SUITE_DIR}/common.sh"; force_tangorpro_canary; ` +
        `sed -i 's/^spoofBuild=.*/spoofBuild=1/; s/^spoofProps=.*/spoofProps=1/; s/^spoofProvider=.*/spoofProvider=1/; s/^spoofVendingFinger=.*/spoofVendingFinger=1/' "${PIF_PROP}"; ` +
        `reload_omk; cleanup_google; echo "Fallback BASIC mode enabled (OMK injector off, spoofProvider=1)"`;
      runAction('Переключение в режим BASIC', 'Отключаем отозванный keybox и включаем программный фолбэк...', cmd, true, false);
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
        `[ -f "${OMK_INJ}" ] && sed -i 's/^enabled = false/enabled = true/' "${OMK_INJ}" && chown 1017:1017 "${OMK_INJ}" && chmod 0600 "${OMK_INJ}" || true && ` +
        `. "${SUITE_DIR}/common.sh" && force_tangorpro_canary && force_basic_settings && sync_omk_config && reload_omk && cleanup_google`;
      runAction('Установка своего keybox.xml', 'Сохраняем keybox, включаем keep_keybox и перезапускаем OMK...', cmd, true, true);
    });

    // PRO mode actions
    document.getElementById('btnOmkSync').addEventListener('click', () => {
      runAction('Full Sync (action.sh)', 'Запуск autopif4, keybox и синхронизации OMK...', `sh "${OMK_SYNC_ACT}"`, true, true);
    });
    document.getElementById('btnSyncLocal').addEventListener('click', () => {
      runAction('Синхронизация PIF → OMK', 'Обновление OMK config.toml и перезапуск...', `. "${SUITE_DIR}/common.sh" && sync_omk_config && reload_omk && cleanup_google`, true, false);
    });
    document.getElementById('btnAutopif').addEventListener('click', () => {
      runAction('autopif4.sh -m', 'Загрузка свежего Pixel Canary профиля...', `sh "${PIF_DIR}/autopif4.sh" -m`, true, false);
    });
    document.getElementById('btnKillPi').addEventListener('click', () => {
      runAction('Kill GMS / Vending', 'Перезапуск процессов Play Integrity...', `sh "${PIF_DIR}/killpi.sh"`, false, false);
    });
    document.getElementById('btnCheckCrlPro').addEventListener('click', () => {
      withLoading('Проверка Keybox в Google CRL', 'Сверяем серийный номер сертификата...', () => checkKeyboxCrl(false));
    });
    document.getElementById('btnReadSyncLog').addEventListener('click', async () => {
      const res = await execRoot(`cat "${SYNC_LOG}" 2>/dev/null || echo "Лог пуст"`);
      log('--- omk_pif_sync.log ---\n' + res.stdout.trim());
    });
    document.getElementById('btnRestoreBak').addEventListener('click', () => {
      runAction('Восстановление .bak', 'Откат custom.pif.prop.bak...', `if [ -f "${PIF_BAK}" ]; then cp -f "${PIF_BAK}" "${PIF_PROP}" && chmod 0644 "${PIF_PROP}" && sh "${PIF_DIR}/killpi.sh"; else echo ".bak не найден"; fi`, true, false);
    });
    document.getElementById('btnClearLog').addEventListener('click', () => {
      document.getElementById('consoleLog').textContent = '';
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    try {
      if (window.ksu && typeof window.ksu.enableEdgeToEdge === 'function') window.ksu.enableEdgeToEdge(true);
    } catch (_) {}
    setMode(localStorage.getItem(MODE_KEY) || 'basic');
    initEvents();
    loadConfig().then(() => loadStatus());
  });
})();
