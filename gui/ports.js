'use strict'
/* global Elm */ // This will keep your linter happy

const ipcRenderer = require('electron').ipcRenderer
const remote = require('remote')
const shell = require('electron').shell

const path = remote.require('path-extra')
const pkg = remote.require('./package.json')
const defaultDir = path.join(path.homedir(), 'Cozy')
const container = document.getElementById('container')
const elmectron = Elm.embed(Elm.Main, container, {
  folder: '',
  version: pkg.version
})

elmectron.ports.folder.send(defaultDir)
ipcRenderer.on('folder-chosen', (event, folder) => {
  elmectron.ports.folder.send(folder)
})
elmectron.ports.chooseFolder.subscribe(() => {
  ipcRenderer.send('choose-folder')
})

// Open external links in the browser
document.addEventListener('click', (event) => {
  if (event.target.matches('a[href^="http"]')) {
    event.preventDefault()
    shell.openExternal(event.target.href)
  }
})
