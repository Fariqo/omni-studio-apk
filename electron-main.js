const { app, BrowserWindow, session, desktopCapturer, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');

app.commandLine.appendSwitch('disable-features', 'BlockInsecurePrivateNetworkRequests');
app.commandLine.appendSwitch('allow-insecure-localhost', 'true');
app.commandLine.appendSwitch('ignore-certificate-errors', 'true');

const userDataPath = path.join(app.getPath('appData'), 'OmniApexStudio');
if (!fs.existsSync(userDataPath)) {
  try { fs.mkdirSync(userDataPath, { recursive: true }); } catch (_) {}
}
app.setPath('userData', userDataPath);

const DAEMON_URL = 'http://127.0.0.1:8765';
let backendProc = null;

function pingDaemon(timeoutMs = 700) {
  return new Promise((resolve) => {
    let settled = false;
    const done = (ok) => { if (!settled) { settled = true; resolve(ok); } };
    const req = http.get(`${DAEMON_URL}/api/ping`, { timeout: timeoutMs }, (res) => {
      res.resume();
      done(res.statusCode === 200);
    });
    req.on('error', () => done(false));
    req.on('timeout', () => { req.destroy(); done(false); });
  });
}

function findDaemonScript() {
  const candidates = [
    'C:\\OtonomAsistan\\Antigravity_V4_Ultra\\daemon_supervisor.py',
    path.join(__dirname, '..', 'daemon_supervisor.py'),
    path.join(process.cwd(), 'daemon_supervisor.py'),
  ];
  return candidates.find((p) => { try { return fs.existsSync(p); } catch (_) { return false; } }) || null;
}

async function ensureDaemonRunning() {
  if (await pingDaemon(600)) return true;
  const daemonScript = findDaemonScript();
  if (!daemonScript) return false;

  try {
    const pyCmd = process.platform === 'win32' ? 'py' : 'python3';
    backendProc = spawn(pyCmd, [daemonScript, '--replace'], {
      cwd: path.dirname(daemonScript),
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    backendProc.unref();
  } catch (_) {
    return false;
  }

  for (let i = 0; i < 18; i++) {
    await new Promise((r) => setTimeout(r, 350));
    if (await pingDaemon(600)) return true;
  }
  return false;
}

const SPLASH_HTML = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><style>
body{margin:0;height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;
background:#060911;color:#e5edf7;font-family:Segoe UI,system-ui,sans-serif;gap:14px}
.dot{width:14px;height:14px;border-radius:50%;background:#38bdf8;box-shadow:0 0 22px #38bdf8;animation:p 1.2s infinite}
@keyframes p{0%,100%{opacity:.4;transform:scale(.9)}50%{opacity:1;transform:scale(1.25)}}
h2{margin:0;font-size:18px;letter-spacing:.4px}p{margin:0;font-size:13px;color:#94a3b8}
</style></head><body><div class="dot"></div><h2>OMNI-NEXUS APEX OS v6.0</h2>
<p>Tek-portlu yerel otonom sunucu (:8765) başlatılıyor...</p></body></html>`;

async function createWindow() {
  const customSession = session.fromPartition('persist:omni_apex_session');
  [session.defaultSession, customSession].forEach((s) => {
    if (!s) return;
    s.setDisplayMediaRequestHandler((request, callback) => {
      desktopCapturer.getSources({ types: ['screen', 'window'] }).then((sources) => {
        if (sources && sources.length > 0) callback({ video: sources[0] });
        else callback({});
      }).catch(() => callback({}));
    });
    s.setPermissionRequestHandler((webContents, permission, callback) => callback(true));
    s.setPermissionCheckHandler(() => true);
  });

  const win = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#060911',
    autoHideMenuBar: true,
    title: 'OMNI-NEXUS APEX OS v6.0 — Otonom Ajan, PC IDE, Otomasyon & Siber/Bulut Kokpiti',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      partition: 'persist:omni_apex_session',
    },
  });

  // External http(s) links outside localhost open cleanly in default OS browser
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1:8765') || url.startsWith('http://localhost:8765')) {
      return { action: 'allow' };
    }
    shell.openExternal(url).catch(() => {});
    return { action: 'deny' };
  });

  // Show instant splash while booting local Python v6 daemon
  win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(SPLASH_HTML)}`);

  const liveReady = await ensureDaemonRunning();
  if (liveReady) {
    win.loadURL(`${DAEMON_URL}/`);
  } else {
    win.loadFile(path.join(__dirname, 'dist', 'index.html'));
  }
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
