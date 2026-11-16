const { app, BrowserWindow, session, desktopCapturer } = require('electron');
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

let bridgeProc = null;
let backendProc = null;

function ensureUnifiedServicesRunning() {
  // 1. Start Multi-Root Bridge (-NoBrowser so Chrome/Edge doesn't pop alongside Electron)
  const reqBridge = http.get('http://127.0.0.1:8080/api/ping', () => {});
  reqBridge.on('error', () => {
    const candidates = [
      path.join(__dirname, '..', 'omni-bridge.ps1'),
      path.join(__dirname, 'omni-bridge.ps1'),
      path.join(process.cwd(), 'omni-bridge.ps1'),
      path.join(process.resourcesPath || '', 'omni-bridge.ps1'),
      path.join(process.resourcesPath || '', 'app', 'omni-bridge.ps1')
    ];
    const script = candidates.find(p => { try { return fs.existsSync(p); } catch (_) { return false; } });
    if (script && process.platform === 'win32') {
      try {
        bridgeProc = spawn('powershell.exe', [
          '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', script, '-NoBrowser'
        ], { detached: false, stdio: 'ignore' });
      } catch (_) {}
    }
  });

  // 2. Start Unified Python Super-Backend (localhost:8765) if installed on Windows
  const reqPy = http.get('http://127.0.0.1:8765/manifest.json', () => {});
  reqPy.on('error', () => {
    const daemonScript = 'C:\\OtonomAsistan\\Antigravity_V4_Ultra\\daemon_supervisor.py';
    if (process.platform === 'win32' && fs.existsSync(daemonScript)) {
      try {
        backendProc = spawn('py', [daemonScript], {
          cwd: path.dirname(daemonScript),
          detached: true,
          stdio: 'ignore'
        });
        backendProc.unref();
      } catch (_) {}
    }
  });
}

function createWindow() {
  ensureUnifiedServicesRunning();

  const customSession = session.fromPartition('persist:omni_apex_session');
  [session.defaultSession, customSession].forEach(s => {
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
    width: 1400,
    height: 900,
    backgroundColor: '#060911',
    autoHideMenuBar: true,
    title: 'OMNI-NEXUS APEX OS v5.0 — Birleşik AI, Telefon, Drive/Yandex & RBP Stüdyosu',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      partition: 'persist:omni_apex_session'
    }
  });

  // Prefer live Unified Localhost Server if ready (auto loopback auth), fallback to dist/index.html
  http.get('http://127.0.0.1:8765/manifest.json', (res) => {
    if (res.statusCode === 200) win.loadURL('http://127.0.0.1:8765/');
    else win.loadFile(path.join(__dirname, 'dist', 'index.html'));
  }).on('error', () => {
    win.loadFile(path.join(__dirname, 'dist', 'index.html'));
  });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => {
  if (bridgeProc) { try { bridgeProc.kill(); } catch (_) {} }
  if (process.platform !== 'darwin') app.quit();
});
