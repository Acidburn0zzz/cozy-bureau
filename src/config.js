import fs from 'fs-extra'
import path from 'path'
import urlParser from 'url'
let log = require('printit')({
  prefix: 'Config        ',
  date: true
})

// Config can keep some configuration parameters in a JSON file,
// like the devices credentials or the mount path
class Config {

  // Create config file if it doesn't exist.
  constructor (basePath) {
    this.configPath = path.join(basePath, 'config.json')
    this.dbPath = path.join(basePath, 'db')
    fs.ensureDirSync(this.dbPath)
    fs.ensureFileSync(this.configPath)

    if (fs.readFileSync(this.configPath).toString() === '') {
      this.reset()
    }

    this.config = require(this.configPath)
  }

  // Reset the configuration
  reset () {
    this.config = Object.create(null)
    this.clear()
    this.persist()
  }

  // Save configuration to file system.
  persist () {
    fs.writeFileSync(this.configPath, this.toJSON())
  }

  // Transform the config to a JSON string
  toJSON () {
    return JSON.stringify(this.config, null, 2)
  }

  // Get the path on the local file system of the synchronized folder
  getSyncPath () {
    return this.config.path
  }

  // Set the path on the local file system of the synchronized folder
  setSyncPath (path) {
    this.config.path = path
  }

  // Return the URL of the cozy instance
  getCozyUrl () {
    return this.config.url
  }

  // Set the URL of the cozy instance
  setCozyUrl (url) {
    this.config.url = url
  }

  // Return true if a device has been configured
  hasClient () {
    return !!this.config.client
  }

  // Return config related to the OAuth client
  getClient () {
    if (!this.config.client) {
      throw new Error(`Device not configured`)
    }
    return this.config.client
  }

  // Set the remote configuration
  saveClient (options) {
    this.config.client = options
    this.persist()
  }

  // Set the pull, push or full mode for this device
  // It will throw an exception if the mode is not compatible with the last
  // mode used!
  saveMode (mode) {
    let old = this.config.mode
    if (old === mode) {
      return true
    } else if (old) {
      throw new Error('Incompatible mode')
    }
    this.config.mode = mode
    this.persist()
  }

  ///////////////////////////////////////////////////////////
  // Implement the Storage interface for cozy-client-js oauth

  save (key, value) {
    this.config.credentials[key] = value
    return Promise.resolve(value)
  }

  load (key) {
    return Promise.resolve(this.config.credentials[key])
  }

  delete (key) {
    const deleted = delete this.config.credentials[key]
    return Promise.resolve(deleted)
  }

  clear () {
    this.config.credentials = Object.create(null)
    return Promise.resolve()
  }
}

export default Config
