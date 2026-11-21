(() => {
  const PIF_DIR = '/data/adb/modules/playintegrityfix';
  const PIF_PROP = `${PIF_DIR}/custom.pif.prop`;
  const PIF_BAK = `${PIF_DIR}/custom.pif.prop.bak`;
  const SUITE_DIR = '/data/adb/modules/omk_pif_suite';
  const OMK_SYNC_ACT = `${SUITE_DIR}/action.sh`;
  const KEEP_KB_FLAG = '/data/adb/omk_pif_sync_keep_keybox';
  const NO_TANGOR_FLAG = '/data/adb/omk_pif_sync_no_tangorpro';
  const SYNC_LOG = '/data/local/tmp/omk_pif_sync.log';

  const BUILD_KEYS = [
    'MANUFACTURER', 'BRAND', 'MODEL', 'PRODUCT', 'DEVICE',
    'FINGERPRINT', 'RELEASE', 'ID', 'INCREMENTAL',
    'SECURITY_PATCH', 'DEVICE_INITIAL_SDK_INT', 'TYPE', 'TAGS'
  ];

  const SWITCH_DEFS = [
    { key: 'spoofBuild', desc: 'Подмена java Build.* полей (MODEL, BRAND, FINGERPRINT и др.) в DroidGuard' },
    { key: 'spoofProps', desc: 'Подмена системных ro.* свойств в DroidGuard через native-перехват' },
    { key: 'spoofProvider', desc: 'Подмена/блокировка AndroidKeyStore в DroidGuard (0 при рабочем OMK/TS, 1 без keybox)' },
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
      : 'Файл загружен';
  }

  async function loadStatus() {
    try {
      const res = await execRoot(
        `echo "PIF=$(grep -m1 ^version= ${PIF_DIR}/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "OMK=$(grep -m1 ^version= /data/adb/modules/oh_my_keymint/module.prop 2>/dev/null | cut -d= -f2)"\n` +
        `echo "PATCH=$(getprop ro.build.version.security_patch)"\n` +
        `echo "FAPI=$(getprop ro.product.first_api_level)"\n` +
        `echo "KEEPKB=$([ -f ${KEEP_KB_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "NOTANG=$([ -f ${NO_TANGOR_FLAG} ] && echo 1 || echo 0)"\n` +
        `echo "KB=$([ -s /data/misc/keystore/omk/keybox.xml ] && echo present || echo missing)"`
      );
      const map = {};
      res.stdout.split('\n').forEach(l => {
        const i = l.indexOf('=');
        if (i > 0) map[l.slice(0, i)] = l.slice(i + 1).trim();
      });
      document.getElementById('stPif').textContent = map.PIF || 'нет';
      document.getElementById('stOmk').textContent = map.OMK || 'нет';
      document.getElementById('stKeybox').textContent = `${map.KB || '-'} | ${map.NOTANG === '1' ? 'auto' : 'tangorpro'}`;
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

  async function saveText(content) {
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
  }

  async function runAction(label, cmd, reloadAfter = false) {
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
    } catch (e) {
      log(`Ошибка (${label}): ${e.message}`);
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
      MANUFACTURER: 'Google',
      BRAND: 'google',
      MODEL: model,
      PRODUCT: prod,
      DEVICE: dev,
      FINGERPRINT: fp,
      DEVICE_INITIAL_SDK_INT: sdk
    });
    const updates = new Map([
      ['ro.build.fingerprint', fp],
      ['ro.build.id', bid],
      ['ro.product.device', dev],
      ['ro.product.name', prod],
      ['ro.product.first_api_level', sdk]
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
    log(`Применён профиль ${model} (${dev}, SDK ${sdk}). Нажми «Сохранить» и при необходимости «Синхр. PIF → OMK».`);
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
    log(`Применён пресет "${name}". Нажми «Сохранить».`);
  }

  async function toggleFlag(path, enabled, label) {
    const cmd = enabled ? `mkdir -p /data/adb && touch "${path}"` : `rm -f "${path}"`;
    const res = await execRoot(cmd);
    log(`${label}: ${enabled ? 'ВКЛ' : 'ВЫКЛ'} (rc=${res.code})`);
    await loadStatus();
  }

  function initEvents() {
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

    document.getElementById('chkKeepKeybox').addEventListener('change', e => {
      toggleFlag(KEEP_KB_FLAG, e.target.checked, 'keep_keybox');
    });
    document.getElementById('chkNoTangorpro').addEventListener('change', e => {
      toggleFlag(NO_TANGOR_FLAG, e.target.checked, 'no_tangorpro');
    });

    document.getElementById('verboseLogs').addEventListener('change', e => {
      state.adv.verboseLogs = e.target.value;
      syncRawPreview();
    });

    document.getElementById('btnReload').addEventListener('click', () => { loadConfig(); loadStatus(); });
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
      log('Значения Build Fields скопированы в System Props.');
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
      kEl.value = '';
      vEl.value = '';
      renderSysProps();
      syncRawPreview();
    });

    document.getElementById('btnOmkSync').addEventListener('click', () => {
      runAction('OMK PIF Suite Sync', `sh "${OMK_SYNC_ACT}"`, true);
    });
    document.getElementById('btnSyncLocal').addEventListener('click', () => {
      runAction('Синхронизация PIF → OMK', `. "${SUITE_DIR}/common.sh" && sync_omk_config && reload_omk && cleanup_google`, true);
    });
    document.getElementById('btnAutopif').addEventListener('click', () => {
      runAction('autopif4.sh -m', `sh "${PIF_DIR}/autopif4.sh" -m`, true);
    });
    document.getElementById('btnKillPi').addEventListener('click', () => {
      runAction('killpi.sh', `sh "${PIF_DIR}/killpi.sh"`);
    });
    document.getElementById('btnReadSyncLog').addEventListener('click', async () => {
      const res = await execRoot(`cat "${SYNC_LOG}" 2>/dev/null || echo "Лог пуст"`);
      log('--- omk_pif_sync.log ---\n' + res.stdout.trim());
    });
    document.getElementById('btnRestoreBak').addEventListener('click', () => {
      runAction('Восстановление .bak', `if [ -f "${PIF_BAK}" ]; then cp -f "${PIF_BAK}" "${PIF_PROP}" && chmod 0644 "${PIF_PROP}" && sh "${PIF_DIR}/killpi.sh"; else echo ".bak не найден"; fi`, true);
    });
    document.getElementById('btnClearLog').addEventListener('click', () => {
      document.getElementById('consoleLog').textContent = '';
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    try {
      if (window.ksu && typeof window.ksu.enableEdgeToEdge === 'function') window.ksu.enableEdgeToEdge(true);
    } catch (_) {}
    initEvents();
    loadStatus();
    loadConfig();
  });
})();
