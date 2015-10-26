async = require 'async'
path  = require 'path'
log   = require('printit')
    prefix: 'Normalizer    '

Pouch = require './pouch'


# When the local filesystem or the remote cozy detects a change, it calls this
# class to inform it. This class will check this event, add some informations,
# and save it in pouchdb. It avoids a lot of bogus data in pouchdb, like file
# created in the folder that doesn't exist.
#
# The documents in PouchDB have similar informations of those in CouchDB, but
# are not structured in the same way. In particular, the _id are uuid in CouchDB
# and the path to the file/folder in PouchDB.
#
# File:
#   - _id / _rev
#   - docType: 'file'
#   - checksum
#   - creationDate
#   - lastModification
#   - tags
#   - size
#   - class
#   - mime
#   - backends
#
# Folder:
#   - _id / _rev
#   - docType: 'folder'
#   - creationDate
#   - lastModification
#   - tags
#   - backends
#
# Conflicts can happen when we try to write one document for a path when
# another document already exists for the same path. The resolution depends of
# the type of the documents:
#   - for two files, we rename the latter with a -conflict suffix
#   - for two folders, we merge them
#   - for a file and a folder, TODO
#
# TODO find a better name than Normalizer for this class
# TODO update metadata
class Normalizer
    constructor: (@pouch) ->

    ### Helpers ###

    # Return true if the document has a valid id
    # (ie a path inside the mount point)
    # TODO what other things are not authorized? ~? $?
    # TODO forbid _design and _local?
    invalidId: (doc) ->
        return true unless doc._id
        doc._id = path.normalize doc._id
        doc._id = doc._id.replace /^\//, ''
        parts = doc._id.split path.sep
        return doc._id is '.' or
            doc._id is '' or
            parts[0] is '..'

    # Return true if the checksum is valid
    # SHA-1 has 40 hexadecimal letters
    invalidChecksum: (doc) ->
        doc.checksum ?= ''
        doc.checksum = doc.checksum.toLowerCase()
        return not doc.checksum.match /^[a-f0-9]{40}$/

    # Be sure that the tree structure for the given path exists
    ensureParentExist: (doc, callback) =>
        parent = path.dirname doc._id
        if parent is '.'
            callback()
        else
            @pouch.db.get parent, (err, folder) =>
                if folder
                    callback()
                else
                    @ensureParentExist _id: parent, (err) =>
                        if err
                            callback err
                        else
                            @putFolder _id: parent, callback

    # Delete every files and folders inside the given folder
    emptyFolder: (folder, callback) =>
        @pouch.byRecursivePath folder._id, (err, docs) =>
            if err
                log.error err
                callback err
            else if docs.length is 0
                callback null
            else
                # XXX in the changes feed, nested subfolder must be deleted
                # before their parents, hence the reverse order.
                docs = docs.reverse()
                for doc in docs
                    doc._deleted = true
                @pouch.db.bulkDocs docs, callback

    # Helper to save a file or a folder
    # (create, move, update the metadata or the content)
    # TODO move
    putDoc: (doc, callback) =>
        if doc.docType is 'file'
            @putFile doc, callback
        else if doc.docType is 'folder'
            @putFolder doc, callback
        else
            callback new Error "Unexpected docType: #{doc.docType}"

    # Simple helper to delete a file or a folder
    deleteDoc: (doc, callback) =>
        if doc.docType is 'file'
            @deleteFile doc, callback
        else if doc.docType is 'folder'
            @deleteFolder doc, callback
        else
            callback new Error "Unexpected docType: #{doc.docType}"


    ### Actions ###

    # Expectations:
    #   - the file path and name are present and valid
    #   - the checksum is present
    # Actions:
    #   - force the 'file' docType
    #   - add the creation date if missing
    #   - add the last modification date if missing
    #   - create the tree structure if needed
    #   - overwrite a possible existing file with the same path
    # TODO how to tell if it's an overwrite or a conflict?
    # TODO conflict with a folder
    putFile: (doc, callback) ->
        if @invalidId doc
            log.warn "Invalid id: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid id'
        else if @invalidChecksum doc
            log.warn "Invalid checksum: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid checksum'
        else
            @pouch.db.get doc._id, (err, file) =>
                doc.docType = 'file'
                doc.lastModification ?= new Date
                if file
                    doc._rev = file._rev
                    doc.creationDate ?= file.creationDate
                    if file.checksum is doc.checksum
                        doc.size  ?= file.size
                        doc.class ?= file.class
                        doc.mime  ?= file.mime
                    @pouch.db.put doc, callback
                else
                    doc.creationDate ?= new Date
                    @ensureParentExist doc, =>
                        @pouch.db.put doc, callback

    # Expectations:
    #   - the folder path and name are present and valid
    # Actions:
    #   - add the creation date if missing
    #   - add the last modification date if missing
    #   - create the tree structure if needed
    #   - overwrite metadata if this folder alredy existed in pouch
    # TODO how to tell if it's an overwrite or a conflict?
    # TODO conflict with a file
    # TODO how can we remove a tag?
    putFolder: (doc, callback) ->
        if @invalidId doc
            log.warn "Invalid id: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid id'
        else
            @pouch.db.get doc._id, (err, folder) =>
                doc.docType = 'folder'
                doc.lastModification ?= (new Date).toString()
                if folder
                    doc._rev = folder._rev
                    doc.creationDate ?= folder.creationDate
                    doc.tags ?= []
                    for tag in folder.tags or []
                        doc.tags.push tag unless tag in doc.tags
                    @pouch.db.put doc, callback
                else
                    doc.creationDate ?= (new Date).toString()
                    @ensureParentExist doc, =>
                        @pouch.db.put doc, callback

    # Expectations:
    #   - the file id is present
    #   - the new file path and name are present and valid
    # Actions:
    #   - create the tree structure if needed
    # TODO
    #   - overwrite the destination if it was present
    moveFile: (doc, callback) ->
        if not doc._id
            log.warn "Missing _id: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Missing id'
        else if doc.docType isnt 'file'
            log.warn "Invalid docType: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid docType'
        else if @invalidPathOrName doc
            log.warn "Invalid path or name: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid path or name'
        else if @invalidChecksum doc
            log.warn "Invalid checksum: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid checksum'
        else
            @ensureParentExist doc, =>
                @pouch.db.put doc, callback

    # Expectations:
    #   - the folder id is present
    #   - the new folder path and name are present and valid
    # Actions:
    #   - create the tree structure if needed
    # TODO
    #   - move every file and folder inside this folder
    #   - overwrite the destination if it was present
    moveFolder: (doc, callback) ->
        if not doc._id
            log.warn "Missing _id: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Missing id'
        else if doc.docType isnt 'folder'
            log.warn "Invalid docType: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid docType'
        else if @invalidPathOrName doc
            log.warn "Invalid path or name: #{JSON.stringify doc, null, 2}"
            callback? new Error 'Invalid path or name'
        else
            @ensureParentExist doc, =>
                @pouch.db.put doc, callback
            # TODO
            # 1. create the destination doc (if it doesn't exist)
            # 2. @pouch.byPath to list all files and folders inside the source
            # 3. move them to the destination with moveFile and moveFolder
            # 4. remove the source doc

    # Expectations:
    #   - the file still exists in pouch
    #   - the file can be found by its _id
    deleteFile: (doc, callback) ->
        async.waterfall [
            # Find the file
            (next) =>
                @pouch.db.get doc._id, next
            # Delete it
            (file, next) =>
                file._deleted = true
                @pouch.db.put file, next
        ], callback

    # Expectations:
    #   - the folder still exists in pouch
    #   - the folder can be found by its _id
    # Actions:
    #   - delete every file and folder inside this folder
    deleteFolder: (doc, callback) ->
        async.waterfall [
            # Find the folder
            (next) =>
                @pouch.db.get doc._id, next
            # Delete everything inside this folder
            (folder, next) =>
                @emptyFolder folder, (err) ->
                    next err, folder
            # Delete the folder
            (folder, next) =>
                folder._deleted = true
                @pouch.db.put folder, next
        ], callback


module.exports = Normalizer
