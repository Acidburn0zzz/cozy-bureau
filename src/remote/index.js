/* @flow */

import Config from '../config'
import * as conversion from '../conversion'
import RemoteCozy from './cozy'
import { jsonApiToRemoteDoc } from './document'
import logger from '../logger'
import Pouch from '../pouch'
import Prep from '../prep'
import Watcher from './watcher'

import type { RemoteDoc } from './document'
import type { FileStreamProvider } from '../file_stream_provider'
import type { Metadata } from '../metadata'
import type { Side } from '../side' // eslint-disable-line
import type { Callback } from '../utils/func'

const log = logger({
  prefix: 'Remote writer ',
  date: true
})

export default class Remote implements Side {
  other: FileStreamProvider
  pouch: Pouch
  watcher: Watcher
  remoteCozy: RemoteCozy

  constructor (config: Config, prep: Prep, pouch: Pouch) {
    this.pouch = pouch
    this.remoteCozy = new RemoteCozy(config)
    this.watcher = new Watcher(pouch, prep, this.remoteCozy)
  }

  start () {
    return this.watcher.start()
  }

  stop () {
    return this.watcher.stop()
  }

  unregister () {
    return this.remoteCozy.unregister()
  }

  // Create a readable stream for the given doc
  async createReadStream (doc: Metadata, callback: Callback) {
    try {
      const stream = await this.remoteCozy.downloadBinary(doc.remote._id, callback)
      callback(null, stream)
    } catch (err) {
      callback(err)
    }
  }

  // Create a folder on the remote cozy instance
  async addFolder (doc: Metadata, callback: Callback) {
    try {
      log.info(`${doc.path}: Creating folder...`)

      const [dirPath, name] = conversion.extractDirAndName(doc.path)
      const dir: RemoteDoc = await this.remoteCozy.findDirectoryByPath(dirPath)
      const created: RemoteDoc = await this.remoteCozy.createDirectory({
        name,
        dirID: dir._id,
        lastModifiedDate: doc.lastModification
      })

      doc.remote = {
        _id: created._id,
        _rev: created._rev
      }

      callback(null, created)
    } catch (err) {
      callback(err)
    }
  }

  async addFileAsync (doc: Metadata): Promise<RemoteDoc> {
    log.info(`${doc.path}: Uploading new file...`)
    const stream = await this.other.createReadStreamAsync(doc)
    const [dirPath, name] = conversion.extractDirAndName(doc.path)
    const dir = await this.remoteCozy.findDirectoryByPath(dirPath)
    const created = await this.remoteCozy.createFile(stream, {
      name,
      dirID: dir._id,
      executable: doc.executable,
      contentType: doc.mime,
      lastModifiedDate: new Date(doc.lastModification)
    })

    doc.remote = {
      _id: created._id,
      _rev: created._rev
    }

    return created
  }

  // FIXME: Drop this wrapper as soon as Sync uses promises
  addFile (doc: Metadata, callback: Callback) {
    try {
      this.addFileAsync(doc)
        .then(created => callback(null, created))
        .catch(callback)
    } catch (err) {
      callback(err)
    }
  }

  async overwriteFileAsync (doc: Metadata, old: Metadata): Promise<RemoteDoc> {
    log.info(`${doc.path}: Uploading new file version...`)
    const stream = await this.other.createReadStreamAsync(doc)
    const updated = await this.remoteCozy.updateFileById(doc.remote._id, stream, {
      contentType: doc.mime,
      checksum: doc.checksum,
      lastModifiedDate: new Date(doc.lastModification)
    })

    doc.remote._rev = updated._rev

    return jsonApiToRemoteDoc(updated)
  }

  async overwriteFile (doc: Metadata, old: Metadata, callback: Callback) {
    try {
      const updated = await this.overwriteFileAsync(doc, old)
      callback(null, updated)
    } catch (err) {
      callback(err)
    }
  }

  async updateFileMetadataAsync (doc: Metadata, old: any): Promise<*> {
    log.info(`${doc.path}: Updating file metadata...`)
    // TODO: v3: addFile() when no old.remote

    // TODO: v3: Update more metadata, not just the last modification date.
    const attrs = {}

    // TODO: v3: ifMatch old rev
    const updated = await this.remoteCozy.updateAttributesById(old.remote._id, attrs, {})

    // TODO: v3: Handle trivial remote changes and conflicts.
    // See Couch#putRemoteDoc() and #sameRemoteDoc()

    doc.remote = {
      _id: updated._id,
      _rev: updated._rev
    }

    return updated
  }

  updateFileMetadata (doc: Metadata, old: any, callback: Callback) {
    try {
      this.updateFileMetadataAsync(doc, old)
        .then(() => { callback() })
        .catch(callback)
    } catch (err) {
      callback(err)
    }
  }

  async moveFileAsync (newMetadata: Metadata, oldMetadata: Metadata): Promise<Metadata> {
    log.info(`${oldMetadata.path}: Moving to ${newMetadata.path}`)
    // TODO: v3: Call addFile() when !from.remote?
    // TODO: v3: Call addFile() when file not found on cozy
    // TODO: v3: Call addFolder() on DirectoryNotFound?
    const [newDirPath, newName]: [string, string] = conversion.extractDirAndName(newMetadata.path)
    const newDir: RemoteDoc = await this.remoteCozy.findDirectoryByPath(newDirPath)
    const newRemoteDoc: RemoteDoc = await this.remoteCozy.updateAttributesById(oldMetadata.remote._id, {
      name: newName,
      dir_id: newDir._id
    })

    newMetadata.remote = {
      _id: newRemoteDoc._id,
      _rev: newRemoteDoc._rev
    }

    return conversion.createMetadata(newRemoteDoc)
  }

  moveFile (doc: Metadata, from: Metadata, callback: Callback): void {
    // $FlowFixMe
    this.moveFileAsync(doc, from).asCallback(callback)
  }

  async updateFolderAsync (doc: Metadata, old: Metadata): Promise<Metadata> {
    log.info(`${doc.path}: Updating metadata...`)
    const [newParentDirPath, newName] = conversion.extractDirAndName(doc.path)
    const newParentDir = await this.remoteCozy.findDirectoryByPath(newParentDirPath)
    const newRemoteDoc = await this.remoteCozy.updateAttributesById(old.remote._id, {
      name: newName,
      dir_id: newParentDir._id
    })
    doc.remote._rev = newRemoteDoc._rev

    return conversion.createMetadata(newRemoteDoc)
  }

  updateFolder (doc: Metadata, old: Metadata, callback: Callback) {
    // $FlowFixMe
    this.updateFolderAsync(doc, old).asCallback(callback)
  }

  async destroyAsync (doc: Metadata): Promise<void> {
    log.info(`${doc.path}: Destroying...`)
    await this.remoteCozy.destroyById(doc.remote._id)
  }

  destroy (doc: Metadata, callback: Callback) {
    // $FlowFixMe
    this.destroyAsync(doc).asCallback(callback)
  }

  async trashAsync (doc: Metadata): Promise<void> {
    log.info(`${doc.path}: Moving to the trash...`)
    await this.remoteCozy.trashById(doc.remote._id)
  }

  trash (doc: Metadata, callback: Callback) {
    // $FlowFixMe
    this.trashAsync(doc).asCallback(callback)
  }

  // FIXME: Temporary stubs so we can do some acceptance testing on file upload
  //        without getting errors for missing methods.

  moveFolder (doc: Metadata, from: Metadata, callback: Callback) {
    callback(new Error('Remote#moveFolder() is not implemented'))
  }
}
