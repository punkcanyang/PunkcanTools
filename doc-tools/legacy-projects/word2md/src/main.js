const { app, BrowserWindow } = require('electron');
const path = require('path');

let mainWindow;
let server;

// 启动内置服务器
function startServer() {
  const serverPath = path.join(__dirname, 'server.cjs');
  server = require(serverPath);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 700,
    minWidth: 600,
    minHeight: 500,
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  // 等待服务器启动后加载页面
  setTimeout(() => {
    mainWindow.loadURL('http://localhost:3456');
  }, 500);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  startServer();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (server && server.server) {
    server.server.close();
  }
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  if (server && server.server) {
    server.server.close();
  }
});
