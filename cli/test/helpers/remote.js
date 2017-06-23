/* @flow */

import cozy from 'cozy-client-js'
import path from 'path'

import { TRASH_DIR_NAME } from '../../src/remote/constants'

export class RemoteTestHelpers {
  cozy: cozy.Client

  constructor (cozy: cozy.Client) {
    this.cozy = cozy
  }

  async tree () {
    const pathsToScan = ['/', `/${TRASH_DIR_NAME}`]
    const relPaths = [`${TRASH_DIR_NAME}/`]

    while (true) {
      const dirPath = pathsToScan.shift()
      if (dirPath == null) break

      const dir = await this.cozy.files.statByPath(dirPath)
      for (const content of dir.relations('contents')) {
        const {name, type} = content.attributes
        const remotePath = path.posix.join(dirPath, name)
        let relPath = remotePath.slice(1)

        if (type === 'directory') {
          relPath += '/'
          pathsToScan.push(remotePath)
        }

        relPaths.push(relPath)
      }
    }

    return relPaths.sort()
  }
}
