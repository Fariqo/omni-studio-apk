const { app, BrowserWindow } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const http = require('http');

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
      try { return require('fs').existsSync(p); } catch (_) { return false; }
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
  const win = new BrowserWindow({
    width: 1280,
    height: 840,
    backgroundColor: '#060911',
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
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
