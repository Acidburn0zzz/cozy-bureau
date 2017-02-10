/* @flow */

import { Cozy as CozyClient } from 'cozy-client-js'
import fetch from 'node-fetch'
import path from 'path'
import { Readable } from 'stream'

import { FILES_DOCTYPE, FILE_TYPE, ROOT_DIR_ID, TRASH_DIR_ID } from './constants'

import type { RemoteDoc } from './document'

function specialId (id) {
  return (
    id === ROOT_DIR_ID ||
    id === TRASH_DIR_ID ||
    id.startsWith('_design/')
  )
}

export function DirectoryNotFound (path: string, cozyURL: string) {
  this.message = `Directory ${path} was not found on Cozy ${cozyURL}`
}

// A remote Cozy instance.
//
// This class wraps cozy-client-js to:
//
// - deal with parsing and errors
// - provide custom functions (that may eventually be merged into the lib)
//
export default class RemoteCozy {
  url: string
  client: CozyClient

  constructor (url: string) {
    this.url = url
    this.client = new CozyClient({cozyURL: url})
  }

  async changes (seq: number = 0) {
    const changesUrl = `${this.url}/data/${FILES_DOCTYPE}/_changes?since=${seq}`

    let resp = await fetch(changesUrl)

    if (!resp.ok) throw new Error(`${resp.status}: ${resp.statusText}: ${changesUrl}`)

    let json = await resp.json()

    return {
      last_seq: json.last_seq,
      ids: json.results
        .map(result => result.id)
        .filter(id => !specialId(id))
    }
  }

  async find (id: string): Promise<RemoteDoc> {
    let doc = await this.client.find(FILES_DOCTYPE, id)

    if (doc.type === FILE_TYPE) {
      const parentDir = await this.client.find(FILES_DOCTYPE, doc.dir_id)
      doc.path = path.join(parentDir.path, doc.name)
    }

    return doc
  }

  async findMaybe (id: string): Promise<?RemoteDoc> {
    try {
      return await this.find(id)
    } catch (err) {
      return null
    }
  }

  async findDirectoryByPath (path: string): Promise<RemoteDoc> {
    const index = await this.client.defineIndex(FILES_DOCTYPE, ['path'])
    const results = await this.client.query(index, {selector: {path}})

    if (results.length === 0) throw new DirectoryNotFound(path, this.url)

    // FIXME: cozy-client-js query results have no _type
    return {...results[0], _type: FILES_DOCTYPE}
  }

  async downloadBinary (id: string): Promise<?Readable> {
    const resp = await this.client.files.downloadById(id)
    return resp.body
  }
}
