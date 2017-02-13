/* eslint-env mocha */

import { Cozy as CozyClient } from 'cozy-client-js'

import { FILES_DOCTYPE, ROOT_DIR_ID, TRASH_DIR_ID } from '../../src/remote/constants'
import { BuilderFactory } from '../builders'

// The URL of the Cozy instance used for tests
export const COZY_URL = process.env.COZY_URL || 'http://test.cozy-desktop.local:8080'

// A cozy-client-js instance
export const cozy = new CozyClient({cozyURL: COZY_URL})

// FIXME: Temporary hack to prevent cozy-client-js to convert node Buffers
// into node-fetch-unsupported ArrayBuffers, until we implement Stream support
// in cozy-client-js.
const origCozyFilesCreate = cozy.files.create
cozy.files.create = function (...args) {
  const origArrayBuffer = global.ArrayBuffer
  global.ArrayBuffer = Buffer
  const result = origCozyFilesCreate(...args)
  global.ArrayBuffers = origArrayBuffer
  return result
}

// Facade for all the test data builders
export const builders = new BuilderFactory(cozy)

// List files and directories in the root directory
async function rootDirContents () {
  const index = await cozy.defineIndex(FILES_DOCTYPE, ['dir_id'])
  const docs = await cozy.query(index, {
    selector: {
      dir_id: ROOT_DIR_ID,
      '$not': {_id: TRASH_DIR_ID}
    },
    fields: ['_id', 'dir_id']
  })

  return docs
}

// Delete all files and directories
export async function deleteAll () {
  const docs = await rootDirContents()

  await Promise.all(docs.map(doc => cozy.files.trashById(doc._id)))

  return cozy.files.clearTrash()
}

