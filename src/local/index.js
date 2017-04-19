/* @flow */

import async from 'async'
import Promise from 'bluebird'
import EventEmitter from 'events'
import clone from 'lodash.clone'
import fs from 'fs-extra'
import path from 'path'
import * as stream from 'stream'
import trash from 'trash'

import Config from '../config'
import logger from '../logger'
import { isUpToDate } from '../metadata'
import Pouch from '../pouch'
import Prep from '../prep'
import Watcher from './watcher'

import type { FileStreamProvider } from '../file_stream_provider'
import type { Metadata } from '../metadata'
import type { Side } from '../side' // eslint-disable-line
import type { Callback } from '../utils/func'

const log = logger({
  component: 'LocalWriter'
})
// Local is the class that interfaces cozy-desktop with the local filesystem.
// It uses a watcher, based on chokidar, to listen for file and folder changes.
// It also applied changes from the remote cozy on the local filesystem.
class Local implements Side {
  prep: Prep
  pouch: Pouch
  events: EventEmitter
  syncPath: string
  tmpPath: string
  watcher: Watcher
  other: FileStreamProvider

  constructor (config: Config, prep: Prep, pouch: Pouch, events: EventEmitter) {
    this.prep = prep
    this.pouch = pouch
    this.events = events
    this.syncPath = config.syncPath
    this.tmpPath = path.join(this.syncPath, '.cozy-desktop')
    this.watcher = new Watcher(this.syncPath, this.prep, this.pouch)
    // $FlowFixMe
    this.other = null

    Promise.promisifyAll(this)
  }

  // Start initial replication + watching changes in live
  start () {
    fs.ensureDirSync(this.syncPath)
    return this.watcher.start()
  }

  // Stop watching the file system
  stop () {
    return this.watcher.stop()
  }

  // Create a readable stream for the given doc
  createReadStreamAsync (doc: Metadata): Promise<stream.Readable> {
    try {
      let filePath = path.resolve(this.syncPath, doc.path)
      let stream = fs.createReadStream(filePath)
      return new Promise((resolve, reject) => {
        stream.on('open', () => resolve(stream))
        stream.on('error', err => reject(err))
      })
    } catch (err) {
      return Promise.reject(err)
    }
  }

  /* Helpers */

  // Return a function that will update last modification date
  // and does a chmod +x if the file is executable
  //
  // Note: UNIX has 3 timestamps for a file/folder:
  // - atime for last access
  // - ctime for change (metadata or content)
  // - utime for update (content only)
  // This function updates utime and ctime according to the last
  // modification date.
  metadataUpdater (doc: Metadata) {
    let filePath = path.resolve(this.syncPath, doc.path)
    return function (callback: Callback) {
      let next = function (err) {
        if (doc.executable) {
          return fs.chmod(filePath, '755', callback)
        } else {
          return callback(err)
        }
      }
      if (doc.updated_at) {
        let updated = new Date(doc.updated_at)
        return fs.utimes(filePath, updated, updated, () =>
          // Ignore errors
          next()
        )
      } else {
        return next()
      }
    }
  }

  // Check if a file corresponding to given checksum already exists
  fileExistsLocally (checksum: string, callback: Callback) {
    return this.pouch.byChecksum(checksum, (err, docs) => {
      if (err) {
        return callback(err)
      } else if ((docs == null) || (docs.length === 0)) {
        return callback(null, false)
      } else {
        let paths = Array.from(docs).filter((doc) => isUpToDate('local', doc)).map((doc) =>
                    path.resolve(this.syncPath, doc.path))
        return async.detect(paths, (filePath, next) =>
                    fs.exists(filePath, found => next(null, found))

        , callback)
      }
    })
  }

  /* Write operations */

  // Add a new file, or replace an existing one
  //
  // Steps to create a file:
  //   * Try to find a similar file based on his checksum
  //     (in that case, it just requires a local copy)
  //   * Or download the linked binary from remote
  //   * Write to a temporary file
  //   * Ensure parent folder exists
  //   * Move the temporay file to its final destination
  //   * Update creation and last modification dates
  //
  // Note: if no checksum was available for this file, we download the file
  // from the remote document. Later, chokidar will fire an event for this new
  // file. The checksum will then be computed and added to the document, and
  // then pushed to CouchDB.
  addFile (doc: Metadata, callback: Callback) {
    let tmpFile = path.resolve(this.tmpPath, `${path.basename(doc.path)}.tmp`)
    let filePath = path.resolve(this.syncPath, doc.path)
    let parent = path.resolve(this.syncPath, path.dirname(doc.path))

    log.info(`Put file ${filePath}`)

    return async.waterfall([
      next => {
        if (doc.md5sum != null) {
          return this.fileExistsLocally(doc.md5sum, next)
        } else {
          return next(null, false)
        }
      },

      (existingFilePath, next) => {
        return fs.ensureDir(this.tmpPath, () => {
          if (existingFilePath) {
            log.info(`Recopy ${existingFilePath} -> ${filePath}`)
            this.events.emit('transfer-copy', doc)
            return fs.copy(existingFilePath, tmpFile, next)
          } else {
            return this.other.createReadStreamAsync(doc).then(
              (stream) => {
                // Don't use async callback here!
                // Async does some magic and the stream can throw an
                // 'error' event before the next async is called...
                let target = fs.createWriteStream(tmpFile)
                stream.pipe(target)
                target.on('finish', next)
                target.on('error', next)
                // Emit events to track the download progress
                let info = clone(doc)
                info.way = 'down'
                info.eventName = `transfer-down-${doc._id}`
                this.events.emit('transfer-started', info)
                stream.on('data', data => {
                  return this.events.emit(info.eventName, data)
                }
                              )
                return target.on('finish', () => {
                  return this.events.emit(info.eventName, {finished: true})
                })
              },
              (err) => { next(err) }
            )
          }
        })
      },

      next => {
        if (doc.md5sum != null) {
          return this.watcher.checksum(tmpFile, function (err, md5sum) {
            if (err) {
              return next(err)
            } else if (md5sum === doc.md5sum) {
              return next()
            } else {
              return next(new Error('Invalid checksum'))
            }
          })
        } else {
          return next()
        }
      },

      next => fs.ensureDir(parent, () => fs.rename(tmpFile, filePath, next)),

      this.metadataUpdater(doc)

    ], function (err) {
      if (err) { log.warn('addFile failed:', err, doc) }
      return fs.unlink(tmpFile, () => callback(err))
    })
  }

  addFileAsync: (Metadata) => Promise<*>

  // Create a new folder
  addFolder (doc: Metadata, callback: Callback) {
    let folderPath = path.join(this.syncPath, doc.path)
    log.info(`Put folder ${folderPath}`)
    return fs.ensureDir(folderPath, err => {
      if (err) {
        return callback(err)
      } else {
        return this.metadataUpdater(doc)(callback)
      }
    })
  }

  addFolderAsync: (Metadata) => Promise<*>

  // Overwrite a file
  overwriteFile (doc: Metadata, old: ?Metadata, callback: Callback) {
    return this.addFile(doc, callback)
  }

  overwriteFileAsync: (Metadata, ?Metadata) => Promise<*>

  // Update the metadata of a file
  updateFileMetadata (doc: Metadata, old: Metadata, callback: Callback) {
    log.info(`${doc.path}: Updating file metadata...`)
    return this.metadataUpdater(doc)(callback)
  }

  updateFileMetadataAsync: (Metadata, Metadata) => Promise<*>

  // Update a folder
  updateFolder (doc: Metadata, old: ?Metadata, callback: Callback) {
    return this.addFolder(doc, callback)
  }

  updateFolderAsync: (Metadata, ?Metadata) => Promise<*>

  // Move a file from one place to another
  moveFile (doc: Metadata, old: Metadata, callback: Callback) {
    log.info(`Move file ${old.path} → ${doc.path}`)
    let oldPath = path.join(this.syncPath, old.path)
    let newPath = path.join(this.syncPath, doc.path)
    let parent = path.join(this.syncPath, path.dirname(doc.path))

    return async.waterfall([
      next => fs.exists(oldPath, function (oldPathExists) {
        if (oldPathExists) {
          return fs.ensureDir(parent, () => fs.rename(oldPath, newPath, next))
        } else {
          return fs.exists(newPath, function (newPathExists) {
            if (newPathExists) {
              return next()
            } else {
              log.error(`File ${oldPath} not found`)
              return next(new Error(`${oldPath} not found`))
            }
          })
        }
      }),

      this.metadataUpdater(doc)

    ], err => {
      if (err) {
        log.error(`Error while moving ${JSON.stringify(doc, null, 2)}`)
        log.error(JSON.stringify(old, null, 2))
        log.error(err)
        return this.addFile(doc, callback)
      } else {
        this.events.emit('transfer-move', doc, old)
        return callback(null)
      }
    })
  }

  moveFileAsync: (Metadata, Metadata) => Promise<*>

  // Move a folder
  moveFolder (doc: Metadata, old: Metadata, callback: Callback) {
    log.info(`Move folder ${old.path} → ${doc.path}`)
    let oldPath = path.join(this.syncPath, old.path)
    let newPath = path.join(this.syncPath, doc.path)
    let parent = path.join(this.syncPath, path.dirname(doc.path))

    return async.waterfall([
      next => fs.exists(oldPath, oldPathExists =>
        fs.exists(newPath, function (newPathExists) {
          if (oldPathExists && newPathExists) {
            return fs.rmdir(oldPath, next)
          } else if (oldPathExists) {
            return fs.ensureDir(parent, () => fs.rename(oldPath, newPath, next))
          } else if (newPathExists) {
            return next()
          } else {
            log.error(`Folder ${oldPath} not found`)
            return next(new Error(`${oldPath} not found`))
          }
        })
      ),

      this.metadataUpdater(doc)

    ], err => {
      if (err) {
        log.error(`Error while moving ${JSON.stringify(doc, null, 2)}`)
        log.error(JSON.stringify(old, null, 2))
        log.error(err)
        return this.addFolder(doc, callback)
      } else {
        return callback(null)
      }
    })
  }

  moveFolderAsync: (Metadata, Metadata) => Promise<*>

  trashAsync (doc: Metadata): Promise<*> {
    log.info(`Delete ${doc.path}`)
    this.events.emit('delete-file', doc)
    let fullpath = path.join(this.syncPath, doc.path)
    return trash([fullpath])
  }

  // Rename a file/folder to resolve a conflict
  resolveConflict (dst: Metadata, src: Metadata, callback: Callback) {
    log.info(`Resolve a conflict: ${src.path} → ${dst.path}`)
    let srcPath = path.join(this.syncPath, src.path)
    let dstPath = path.join(this.syncPath, dst.path)
    fs.rename(srcPath, dstPath, callback)
    // Don't fire an event for the deleted file
    return setTimeout(() => {
      const p = this.watcher.pending
      if (p.hasPath(src.path)) { p.clear(src.path) }
    }, 1000)
  }

  resolveConflictAsync: (Metadata, Metadata) => Promise<*>
}

export default Local
