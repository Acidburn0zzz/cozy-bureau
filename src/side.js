/* @flow */

import type { Metadata } from './metadata'

export type SideName =
  | "local"
  | "remote";

// eslint-disable-next-line no-undef
export interface Side {
  addFileAsync (doc: Metadata): Promise<*>;
  addFolderAsync (doc: Metadata): Promise<*>;
  overwriteFileAsync (doc: Metadata, old: ?Metadata): Promise<*>;
  updateFileMetadataAsync (doc: Metadata, old: Metadata): Promise<*>;
  updateFolderAsync (doc: Metadata, old: ?Metadata): Promise<*>;
  moveFileAsync (doc: Metadata, from: Metadata): Promise<*>;
  moveFolderAsync (doc: Metadata, from: Metadata): Promise<*>;
  trashAsync (doc: Metadata): Promise<*>;
  destroyAsync (doc: Metadata): Promise<*>;
}

export function otherSide (side: SideName): SideName {
  switch (side) {
    case 'local': return 'remote'
    case 'remote': return 'local'
    default: throw new Error(`Invalid side name: ${JSON.stringify(side)}`)
  }
}