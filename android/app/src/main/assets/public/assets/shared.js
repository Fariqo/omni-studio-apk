/* OMNI-NEXUS APEX OS v6.0 — Shared Shell, PC/Electron/APK API Client, Theme & Ctrl+K Command Palette */
(function () {
  const IS_STANDALONE = (
    location.protocol === 'file:' ||
    location.protocol === 'capacitor:' ||
    (location.protocol === 'https:' && location.hostname === 'localhost' && !location.port)
  );

  const NAV_ITEMS = [
    { href: '/', file: 'index.html', label: '⚡ Ajan', key: 'agent', shortcut: '1' },
    { href: '/ide', file: 'ide.html', label: '📂 IDE & PC', key: 'ide', shortcut: '2' },
    { href: '/auto', file: 'auto.html', label: '🤖 Otomasyon', key: 'auto', shortcut: '3' },
    { href: '/ops', file: 'ops.html', label: '🛡️ Ops & Bulut', key: 'ops', shortcut: '4' },
    { href: '/mobile', file: 'mobile.html', label: '🎙️ Sesli', key: 'mobile' },
    { href: '/settings', file: 'settings.html', label: '⚙️ Ayarlar', key: 'settings', shortcut: '5' },
    { href: '/classic', file: 'classic.html', label: '🧩 Klasik', key: 'classic' },
  ];

  function resolvePageHref(key) {
    const item = NAV_ITEMS.find(n => n.key === key) || NAV_ITEMS[0];
    return IS_STANDALONE ? item.file : item.href;
  }

  function getApiBase() {
    const saved = (localStorage.getItem('omni_v6_api_base') || '').trim().replace(/\/+$/, '');
    if (saved) return saved;
    if (IS_STANDALONE) return 'http://127.0.0.1:8765';
    return '';
  }

  function buildUrl(path) {
    if (/^https?:\/\//i.test(path)) return path;
    const base = getApiBase();
    return base ? `${base}${path.startsWith('/') ? path : '/' + path}` : path;
  }

  function buildHeaders(extra = {}) {
    const h = Object.assign({}, extra);
    const tok = (localStorage.getItem('omni_v6_token') || '').trim();
    if (tok) h['X-Commander-Token'] = tok;
    return h;
  }

  const CMD_ITEMS = [
    { title: '⚡ Otonom Ajan Merkezi (Ana Sayfa)', sub: 'PC, Web ve GitHub araçlı sohbet (Ctrl+1)', action: () => location.href = resolvePageHref('agent') },
    { title: '📂 PC Dosya & Kod Editörü + Terminal', sub: 'Klasör gezgini, kod editörü, Git ve yedekler (Ctrl+2)', action: () => location.href = resolvePageHref('ide') },
    { title: '🤖 Otomasyon & Zamanlayıcı Stüdyosu', sub: 'Periyodik görevler ve tek-tık şablonlar (Ctrl+3)', action: () => location.href = resolvePageHref('auto') },
    { title: '🛡️ Siber, Donanım, İletişim & Bulut Kokpiti', sub: 'Portlar, OSINT, Tarayıcı, Mail, Drive/Yandisk (Ctrl+4)', action: () => location.href = resolvePageHref('ops') },
    { title: '⚙️ Otonomi Politikaları & API Ayarları', sub: 'Çalışma klasörü izinleri, onaylar, sistem kalkanı (Ctrl+5)', action: () => location.href = resolvePageHref('settings') },
    { title: '🎙️ Sesli Mobil Kokpit', sub: 'Tek elle sesli komutlar ve mikrofon kontrolü', action: () => location.href = resolvePageHref('mobile') },
    { title: '🧩 Eski Stüdyo (Klasik v5)', sub: 'APK/HTML Canvas stüdyosu', action: () => location.href = resolvePageHref('classic') },
    { title: '🔌 Sunucu Bağlantı Ayarları (PC / Mobil APK)', sub: 'Uzak PC (:8765) adresi ve X-Commander-Token tanımla', action: () => window.OmniV6.openServerModal() },
  ];

  window.OmniV6 = {
    isStandalone: IS_STANDALONE,
    pageHref: resolvePageHref,
    getApiBase,

    go(key) {
      location.href = resolvePageHref(key);
    },

    async apiGet(path) {
      const r = await fetch(buildUrl(path), {
        credentials: getApiBase() ? 'omit' : 'same-origin',
        headers: buildHeaders(),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || `HTTP ${r.status}`);
      return d;
    },

    async apiPost(path, body = {}) {
      const r = await fetch(buildUrl(path), {
        method: 'POST',
        credentials: getApiBase() ? 'omit' : 'same-origin',
        headers: buildHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify(body),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || `HTTP ${r.status}`);
      return d;
    },

    esc(s) {
      return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    toast(msg, timeout = 3200) {
      let el = document.getElementById('omniToast');
      if (!el) {
        el = document.createElement('div');
        el.id = 'omniToast';
        document.body.appendChild(el);
      }
      el.textContent = msg;
      el.style.display = 'block';
      clearTimeout(el._t);
      el._t = setTimeout(() => { el.style.display = 'none'; }, timeout);
    },

    applyTheme(theme) {
      document.body.classList.remove('theme-oled', 'theme-crt', 'theme-light');
      if (theme && theme !== 'dark') document.body.classList.add('theme-' + theme);
      localStorage.setItem('omni_v6_theme', theme || 'dark');
    },

    renderMarkdown(text) {
      const raw = String(text || '');
      const parts = raw.split(/(```[\s\S]*?```)/g);
      return parts.map(part => {
        if (part.startsWith('```') && part.endsWith('```')) {
          const inner = part.slice(3, -3);
          const nl = inner.indexOf('\n');
          const lang = nl > -1 ? (inner.slice(0, nl).trim() || 'code') : 'code';
          const code = nl > -1 ? inner.slice(nl + 1) : inner;
          const b64 = btoa(unescape(encodeURIComponent(code)));
          return `<div class="code-block"><div class="code-block-head"><span>${this.esc(lang)}</span><button class="btn btn-sm" onclick="OmniV6.copyB64('${b64}')">📋 Kopyala</button></div><pre>${this.esc(code)}</pre></div>`;
        }
        let h = this.esc(part);
        h = h.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        h = h.replace(/`([^`]+)`/g, '<code>$1</code>');
        return `<div>${h}</div>`;
      }).join('');
    },

    copyB64(b64) {
      const txt = decodeURIComponent(escape(atob(b64)));
      navigator.clipboard.writeText(txt).then(() => this.toast('✅ Kod kopyalandı.'));
    },

    openServerModal() {
      const m = document.getElementById('serverModal');
      if (!m) return;
      document.getElementById('srvBaseInput').value = localStorage.getItem('omni_v6_api_base') || (IS_STANDALONE ? 'http://127.0.0.1:8765' : '');
      document.getElementById('srvTokenInput').value = localStorage.getItem('omni_v6_token') || '';
      document.getElementById('srvTestStatus').textContent = IS_STANDALONE
        ? 'Mobil APK / Çevrimdışı mod: PC veya bulut sunucunuzun :8765 adresini girin.'
        : 'Yerel sunucu aktif — boş bırakırsanız aynı sunucu (:8765) kullanılır.';
      m.classList.add('open');
    },

    closeServerModal() {
      document.getElementById('serverModal')?.classList.remove('open');
    },

    async saveAndTestServer() {
      const base = (document.getElementById('srvBaseInput').value || '').trim().replace(/\/+$/, '');
      const tok = (document.getElementById('srvTokenInput').value || '').trim();
      if (base) localStorage.setItem('omni_v6_api_base', base);
      else localStorage.removeItem('omni_v6_api_base');
      if (tok) localStorage.setItem('omni_v6_token', tok);
      else localStorage.removeItem('omni_v6_token');

      const st = document.getElementById('srvTestStatus');
      st.textContent = '⏳ Sunucu test ediliyor...';
      try {
        const res = await this.apiGet('/api/ping');
        st.textContent = `✅ Bağlandı! (${res.version || 'v6.0'}) Sayfa yenileniyor...`;
        this.toast('✅ Sunucu bağlantısı doğrulandı.');
        setTimeout(() => location.reload(), 650);
      } catch (e) {
        st.textContent = `❌ Bağlanılamadı: ${e.message}`;
      }
    },

    mountShell(activeKey) {
      this.applyTheme(localStorage.getItem('omni_v6_theme') || 'dark');
      const curTheme = localStorage.getItem('omni_v6_theme') || 'dark';
      const header = document.createElement('header');
      header.className = 'topbar';
      header.innerHTML = `
        <div class="brand">
          <span class="brand-dot"></span>
          <span class="brand-title">OMNI-NEXUS APEX v6.0</span>
        </div>
        <nav class="nav-links">
          ${NAV_ITEMS.map(n => `<a class="nav-link ${n.key === activeKey ? 'active' : ''}" href="${resolvePageHref(n.key)}">${n.label}</a>`).join('')}
        </nav>
        <div class="top-right">
          <span id="topTelemetry" class="pill" style="cursor:pointer;" onclick="OmniV6.openServerModal()" title="Sunucu Bağlantısı / Durum">💻 ...</span>
          ${IS_STANDALONE ? `<button class="btn btn-sm" onclick="OmniV6.openServerModal()" title="PC Sunucusuna Bağlan">🔌 Sunucu</button>` : ''}
          <button class="btn btn-sm" onclick="OmniV6.openPalette()" title="Hızlı Komut Paleti">⌘ Ctrl+K</button>
          <select class="select" style="width:auto;padding:4px 8px;font-size:12px;" onchange="OmniV6.applyTheme(this.value)">
            <option value="dark" ${curTheme === 'dark' ? 'selected' : ''}>🌌 Cyber</option>
            <option value="oled" ${curTheme === 'oled' ? 'selected' : ''}>🖤 OLED</option>
            <option value="crt" ${curTheme === 'crt' ? 'selected' : ''}>📟 CRT</option>
            <option value="light" ${curTheme === 'light' ? 'selected' : ''}>☀️ Açık</option>
          </select>
        </div>
      `;
      document.body.prepend(header);

      // Command Palette DOM
      const pal = document.createElement('div');
      pal.id = 'cmdPalette';
      pal.className = 'cmd-backdrop';
      pal.innerHTML = `
        <div class="cmd-box" onclick="event.stopPropagation()">
          <div style="padding:10px 12px;">
            <input id="cmdSearchInput" class="input" placeholder="Arayüz, araç veya komut ara... (ESC ile kapat)" oninput="OmniV6.filterPalette(this.value)" />
          </div>
          <div id="cmdList"></div>
        </div>
      `;
      pal.onclick = () => this.closePalette();
      document.body.appendChild(pal);

      // Server Connection Modal DOM (Mobile APK / Remote PC)
      const sm = document.createElement('div');
      sm.id = 'serverModal';
      sm.className = 'cmd-backdrop';
      sm.innerHTML = `
        <div class="cmd-box" style="padding:18px;max-width:480px;" onclick="event.stopPropagation()">
          <div style="font-weight:800;font-size:15px;margin-bottom:10px;">🔌 Sunucu Bağlantısı (PC :8765 / Mobil APK)</div>
          <div style="display:flex;flex-direction:column;gap:10px;">
            <label style="font-size:12px;color:var(--muted);">Sunucu Adresi (Örn: http://192.168.1.25:8765 veya boş = yerel)
              <input id="srvBaseInput" class="input" style="margin-top:4px;" placeholder="http://127.0.0.1:8765" />
            </label>
            <label style="font-size:12px;color:var(--muted);">COMMANDER_TOKEN (LAN / Uzak erişim için zorunlu)
              <input id="srvTokenInput" class="input" type="password" style="margin-top:4px;" placeholder="Yerel PC için boş bırakabilirsiniz" />
            </label>
            <div id="srvTestStatus" style="font-size:12px;color:var(--muted);"></div>
            <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:4px;">
              <button class="btn btn-sm" onclick="OmniV6.closeServerModal()">Kapat</button>
              <button class="btn btn-primary btn-sm" onclick="OmniV6.saveAndTestServer()">Kaydet & Test Et</button>
            </div>
          </div>
        </div>
      `;
      sm.onclick = () => this.closeServerModal();
      document.body.appendChild(sm);

      document.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
          e.preventDefault();
          this.openPalette();
        } else if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && ['1', '2', '3', '4', '5'].includes(e.key)) {
          const target = NAV_ITEMS.find(n => n.shortcut === e.key);
          if (target) {
            e.preventDefault();
            location.href = resolvePageHref(target.key);
          }
        } else if (e.key === 'Escape') {
          this.closePalette();
          this.closeServerModal();
        }
      });

      this.refreshTelemetry();
      setInterval(() => this.refreshTelemetry(), 15000);
    },

    openPalette() {
      const p = document.getElementById('cmdPalette');
      if (!p) return;
      p.classList.add('open');
      this.filterPalette('');
      setTimeout(() => document.getElementById('cmdSearchInput')?.focus(), 30);
    },

    closePalette() {
      document.getElementById('cmdPalette')?.classList.remove('open');
    },

    filterPalette(q) {
      const list = document.getElementById('cmdList');
      if (!list) return;
      const ql = (q || '').toLowerCase();
      const filtered = CMD_ITEMS.filter(i => (i.title + ' ' + i.sub).toLowerCase().includes(ql));
      list.innerHTML = filtered.map((it, idx) => `
        <div class="cmd-item" data-idx="${idx}">
          <div><div style="font-weight:700;font-size:13px;">${this.esc(it.title)}</div><div style="font-size:11.5px;color:var(--muted);">${this.esc(it.sub)}</div></div>
          <span style="color:var(--muted);font-size:11px;">↵</span>
        </div>
      `).join('');
      list.querySelectorAll('.cmd-item').forEach((el, i) => {
        el.onclick = () => { this.closePalette(); filtered[i].action(); };
      });
    },

    async refreshTelemetry() {
      const el = document.getElementById('topTelemetry');
      if (!el) return;
      try {
        const t = await this.apiGet('/api/telemetry');
        el.textContent = `💻 CPU %${t.cpu_pct} • RAM %${t.ram_pct} • Disk ${t.disk_free_gb}GB`;
        el.className = 'pill pill-ok';
      } catch (_) {
        el.textContent = IS_STANDALONE ? '🔌 PC Sunucusuna Bağlan' : '⚠️ Sunucu Bekleniyor';
        el.className = 'pill pill-warn';
      }
    }
  };
})();
