const { app, BrowserWindow, session, desktopCapturer } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');

// Kalici kullanici verisi (localStorage, IndexedDB ve ayarlar asla silinmez)
const userDataPath = path.join(app.getPath('appData'), 'OmniApexStudio');
if (!fs.existsSync(userDataPath)) {
  try { fs.mkdirSync(userDataPath, { recursive: true }); } catch (_) {}
}
app.setPath('userData', userDataPath);

let bridgeProc = null;

function ensureBridgeRunning() {
  const req = http.get('http://localhost:8080/api/ping', () => {});
  req.on('error', () => {
    const candidates = [
      path.join(__dirname, '..', 'omni-bridge.ps1'),
      path.join(__dirname, 'omni-bridge.ps1'),
      path.join(process.cwd(), 'omni-bridge.ps1')
    ];
    const script = candidates.find(p => {
      try { return fs.existsSync(p); } catch (_) { return false; }
    });
    if (script && process.platform === 'win32') {
      try {
        bridgeProc = spawn('powershell.exe', [
          '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script
        ], { detached: false, stdio: 'ignore' });
      } catch (_) {}
    }
  });
}

function createWindow() {
  ensureBridgeRunning();

  // Ekran ve pencere yakalama izni (getDisplayMedia destegi)
  session.defaultSession.setDisplayMediaRequestHandler((request, callback) => {
    desktopCapturer.getSources({ types: ['screen', 'window'] }).then((sources) => {
      if (sources && sources.length > 0) {
        callback({ video: sources[0] });
      } else {
        callback({});
      }
    }).catch(() => callback({}));
  });

  const win = new BrowserWindow({
    width: 1360,
    height: 880,
    backgroundColor: '#060911',
    autoHideMenuBar: true,
    title: 'OMNI-APEX STUDIO OS v3.0',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      partition: 'persist:omni_apex_session'
    }
  });
  win.loadFile(path.join(__dirname, 'dist', 'index.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => {
  if (bridgeProc) {
    try { bridgeProc.kill(); } catch (_) {}
  }
  if (process.platform !== 'darwin') app.quit();
});
