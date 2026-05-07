import { app, BrowserWindow, dialog } from 'electron';
import { startServer } from './server.js';

let mainWindow = null;
let localServer = null;

async function createWindow() {
  localServer = await startServer({ port: 0 });

  mainWindow = new BrowserWindow({
    width: 960,
    height: 740,
    minWidth: 760,
    minHeight: 560,
    title: 'HTML Book PDF',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  await mainWindow.loadURL(localServer.origin);
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

async function shutdownServer() {
  if (!localServer) {
    return;
  }

  await localServer.close();
  localServer = null;
}

app.whenReady().then(createWindow).catch(async (error) => {
  dialog.showErrorBox('HTML Book PDF 啟動失敗', error.message);
  await shutdownServer();
  app.quit();
});

app.on('window-all-closed', async () => {
  await shutdownServer();
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', async () => {
  await shutdownServer();
});

app.on('activate', async () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    await createWindow();
  }
});
