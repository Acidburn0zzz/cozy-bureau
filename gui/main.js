'use strict'
/* eslint no-unused-vars: [2, { "varsIgnorePattern": "runAsService" }] */

const Desktop = require('cozy-desktop')
const electron = require('electron')

const app = electron.app
const BrowserWindow = electron.BrowserWindow
const dialog = electron.dialog
const ipcMain = electron.ipcMain
const desktop = new Desktop(process.env.COZY_DESKTOP_DIR)

// Use a fake window to keep the application running when the main window is
// closed: it runs as a service, with a tray icon if you want to quit it
let runAsService

// Keep a global reference of the window object, if you don't, the window will
// be closed automatically when the JavaScript object is garbage collected.
let mainWindow
let tray
let device

const windowOptions = {
  width: 1024,
  height: 768,
  icon: `${__dirname}/images/icon.png`,
  skipTaskbar: true,
  closable: false
}

const startSync = (url) => {
  mainWindow.webContents.send('synchronization', url)
  if (!desktop.sync) {
    desktop.events.on('up-to-date', () => {
      mainWindow.webContents.send('up-to-date')
    })
    desktop.events.on('transfer-started', (info) => {
      mainWindow.webContents.send('transfer', info)
    })
    desktop.synchronize('full', (err) => { console.error(err) })
  }
}

const createWindow = () => {
  runAsService = new BrowserWindow({ show: false })
  mainWindow = new BrowserWindow(windowOptions)
  mainWindow.loadURL(`file://${__dirname}/index.html`)
  if (process.env.WATCH === 'true') {
    mainWindow.setBounds({ x: 0, y: 0, width: 1600, height: 768 })
    mainWindow.webContents.openDevTools()
  } else {
    mainWindow.setMenu(null)
  }
  mainWindow.on('closed', () => { mainWindow = null })
  mainWindow.webContents.on('dom-ready', () => {
    if (desktop.config.hasDevice()) {
      device = desktop.config.getDevice()
      startSync(device.url)
    }
  })
}

app.on('ready', () => {
  createWindow()
  tray = new electron.Tray(`${__dirname}/images/cozystatus-idle.png`)
  const menu = electron.Menu.buildFromTemplate([
    { label: 'Quit', click: app.quit }
  ])
  tray.setContextMenu(menu)
})

app.on('activate', () => {
  // On OS X it's common to re-create a window in the app when the
  // dock icon is clicked and there are no other windows open.
  if (mainWindow) {
    mainWindow.focus()
  } else {
    createWindow()
  }
})

// Glue code between cozy-desktop lib and the renderer process
ipcMain.on('ping-cozy', (event, url) => {
  desktop.pingCozy(url, (err, cozyUrl) => {
    let pong = null
    if (!err) {
      pong = cozyUrl
    }
    event.sender.send('cozy-pong', pong)
  })
})

ipcMain.on('register-remote', (event, arg) => {
  desktop.askPassword = (cb) => { cb(null, arg.password) }

  // It looks like Electron detects incorrectly that node has nothing to do
  // and it prevents it to send its http request to the cozy before the next
  // event. Putting new events in the event loop seems to be a work-around
  // for this mysterious bug!
  setTimeout(() => {}, 250)
  setTimeout(() => {}, 500)
  setTimeout(() => {}, 1000)

  desktop.registerRemote(arg.url, null, (err, credentials) => {
    let message = err
    if (err && err.message) {
      message = err.message
    }
    event.sender.send('remote-registered', message)
    if (!err) {
      device = {
        url: arg.url,
        name: credentials.deviceName,
        password: credentials.password
      }
    }
  })
})

ipcMain.on('choose-folder', (event) => {
  let folders = dialog.showOpenDialog({
    properties: ['openDirectory']
  })
  if (folders && folders.length > 0) {
    event.sender.send('folder-chosen', folders[0])
  }
})

ipcMain.on('start-sync', (event, arg) => {
  if (!device) {
    console.error('No device!')
    return
  }
  desktop.saveConfig(device.url, arg, device.name, device.password)
  startSync(device.url)
})

ipcMain.on('unlink-cozy', (event) => {
  if (!device) {
    console.error('No device!')
    return
  }
  desktop.askPassword = (cb) => { cb(null, device.password) }
  desktop.removeRemote(device.deviceName, (err) => {
    if (err) {
      console.error(err)
    } else {
      device = null
      event.sender.send('unlinked')
    }
  })
})

// On watch mode, automatically reload the window when sources are updated
if (process.env.WATCH === 'true') {
  const chokidar = require('chokidar')
  chokidar.watch(['index.html', 'elm.js', 'ports.js', 'styles/app.css'])
    .on('change', () => {
      if (mainWindow) {
        mainWindow.reload()
      }
    })
}
