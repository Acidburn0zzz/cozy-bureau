async = require 'async'
log   = require('printit')
    prefix: 'Synchronize   '


# Sync listens to PouchDB about the metadata changes, and calls local and
# remote sides to apply the changes on the filesystem and remote CouchDB
# respectively.
#
# TODO find a better name that Sync
class Sync

    constructor: (@pouch, @local, @remote, @events) ->
        @local.other = @remote
        @remote.other = @local

    # Start to synchronize the remote cozy with the local filesystem
    # First, start metadata synchronization in pouch, with the watchers
    # Then, when a stable state is reached, start applying changes from pouch
    #
    # The mode can be:
    # - readonly  if only changes from the remote cozy are applied to the fs
    # - writeonly if only changes from the fs are applied to the remote cozy
    # - full for the full synchronization of the both sides
    #
    # The callback is called only for an error
    start: (mode, callback) =>
        tasks = [
            (next) => @pouch.addAllViews next
        ]
        tasks.push @local.start  unless mode is 'readonly'
        tasks.push @remote.start unless mode is 'writeonly'
        async.waterfall tasks, (err) =>
            if err
                callback err
            else
                @events.emit 'firstMetadataSyncDone'
                # TODO queue.makeFSSimilarToDB syncToCozy, (err) ->
                async.forever @sync, callback

    # Start taking changes from pouch and applying them
    # TODO find a way to emit 'firstSyncDone'
    # TODO handle an offline mode
    sync: (callback) =>
        @pop (err, change) =>
            if err
                callback err
            else
                @apply change, callback

    # Take the next change from pouch
    # We filter with the byPath view to reject design documents
    #
    # TODO look also to the retry queue for failures
    pop: (callback) =>
        @pouch.getLocalSeq (err, seq) =>
            return callback err if err
            opts =
                live: true
                since: seq
                include_docs: true
                returnDocs: false
                filter: '_view'
                view: 'byPath'
            @pouch.db.changes(opts)
                .on 'change', (info) ->
                    @cancel()
                    callback null, info
                .on 'error',  (err) ->
                    callback err, null

    # Apply a change to both local and remote
    # At least one side should say it has already this change
    # In some cases, both sides have the change
    #
    # TODO note the success in the doc
    # TODO when applying a change fails, put it again in some queue for retry
    apply: (change, callback) =>
        log.debug 'apply', change
        doc = change.doc
        docType = doc.docType?.toLowerCase()
        switch
            when docType is 'file'
                @fileChanged doc, @applied(callback)
            when docType is 'folder'
                @folderChanged doc, @applied(callback)
            else
                callback new Error "Unknown doctype: #{doc.docType}"

    # Keep track of the sequence number and log errors
    applied: (callback) =>
        (err) =>
            if err
                log.error err
                callback err
            else
                log.debug "Applied #{change.seq}"
                @pouch.setLocalSeq change.seq, callback

    # If a file has been changed, we had to check what operation it is.
    # For a move, the first call will just keep a reference to the document,
    # and only at the second call, the move operation will be executed.
    # TODO what about overwrite and metadata update?
    fileChanged: (doc, callback) =>
        if @moveFrom
            [from, @moveFrom] = [@moveFrom, null]
            if from.moveTo is doc._id
                @fileMoved doc, from, callback
            else
                log.error "Invalid move", from, doc
                callback new Error 'Invalid move'
        else if doc.moveTo
            @moveFrom = doc
            callback()
        else if doc._deleted
            @fileDeleted doc, callback
        else
            @fileAdded doc, callback

    # Same as fileChanged, but for folder
    folderChanged: (doc, callback) =>
        if @moveFrom
            [from, @moveFrom] = [@moveFrom, null]
            if from.moveTo is doc._id
                @folderMoved doc, from, callback
            else
                log.error "Invalid move", from, doc
                callback new Error 'Invalid move'
        else if doc.moveTo
            @moveFrom = doc
            callback()
        else if doc._deleted
            @folderDeleted doc, callback
        else
            @folderAdded doc, callback

    # Let local and remote know that a file has been added
    fileAdded: (doc, callback) =>
        async.waterfall [
            (next) => @local.addFile  doc, next
            (next) => @remote.addFile doc, next
        ], callback

    # Let local and remote know that a file has been moved
    fileMoved: (doc, old, callback) =>
        async.waterfall [
            (next) => @local.moveFile  doc, old, next
            (next) => @remote.moveFile doc, old, next
        ], callback

    # Let local and remote know that a file has been deleted
    fileDeleted: (doc, callback) =>
        async.waterfall [
            (next) => @local.deleteFile  doc, next
            (next) => @remote.deleteFile doc, next
        ], callback

    # Let local and remote know that a folder has been added
    folderAdded: (doc, callback) =>
        async.waterfall [
            (next) => @local.addFolder  doc, next
            (next) => @remote.addFolder doc, next
        ], callback

    # Let local and remote know that a folder has been moved
    folderMoved: (doc, old, callback) =>
        async.waterfall [
            (next) => @local.moveFolder  doc, old, next
            (next) => @remote.moveFolder doc, old, next
        ], callback

    # Let local and remote know that a folder has been deleted
    folderDeleted: (doc, callback) =>
        async.waterfall [
            (next) => @local.deleteFolder  doc, next
            (next) => @remote.deleteFolder doc, next
        ], callback


module.exports = Sync
