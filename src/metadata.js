/* @flow */

import path from 'path'

// The files/dirs metadata, as stored in PouchDB
export type Metadata = {
  _id: string,
  // TODO: v3: Rename to md5sum to match remote
  checksum?: string,
  class?: string,
  creationDate: string,
  // TODO: v3: Use the same local *type fields as the remote ones
  docType: string,
  executable?: boolean,
  lastModification: string,
  mime?: string,
  path: string,
  remote: {
    _id: string,
    _rev: string
  },
  size?: string,
  tags: string[],
  sides: {
    remote: ?string,
    local: ?string
  }
}

// Build an _id from the path for a case sensitive file system (Linux, BSD)
buildIdUnix (doc) {
  doc._id = doc.path
}

// Build an _id from the path for OSX (HFS+ file system):
// - case preservative, but not case sensitive
// - unicode NFD normalization (sort of)
//
// See https://nodejs.org/en/docs/guides/working-with-different-filesystems/
// for why toUpperCase is better than toLowerCase
//
// Note: String.prototype.normalize is not available on node 0.10 and does
// nothing when node is compiled without intl option.
buildIdHFS (doc) {
  let id = doc.path
  if (id.normalize) { id = id.normalize('NFD') }
  doc._id = id.toUpperCase()
}

// Return true if the document has not a valid path
// (ie a path inside the mount point)
invalidPath (doc) {
  if (!doc.path) { return true }
  doc.path = path.normalize(doc.path)
  doc.path = doc.path.replace(/^\//, '')
  let parts = doc.path.split(path.sep)
  return (doc.path === '.') ||
          (doc.path === '') ||
          (parts.indexOf('..') >= 0)
}

// Return true if the checksum is invalid
// If the checksum is missing, it is not invalid, just missing,
// so it returns false.
// MD5 has 16 bytes.
// Base64 encoding must include padding.
invalidChecksum (doc) {
  if (doc.checksum == null) return false

  const buffer = Buffer.from(doc.checksum, 'base64')

  return buffer.byteLength !== 16 ||
    buffer.toString('base64').length !== doc.checksum.length
}
