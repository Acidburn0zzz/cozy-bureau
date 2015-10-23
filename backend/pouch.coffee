PouchDB = require 'pouchdb'
async   = require 'async'
path    = require 'path-extra'
log     = require('printit')
    prefix: 'Local Pouchdb '


# Pouchdb is used to store all the metadata about files and folders.
# These metadata can come from the local filesystem or the remote cozy instance.
#
# http://pouchdb.com/2014/06/17/12-pro-tips-for-better-code-with-pouchdb.html
#
# TODO when a file is removed, delete its binary if not used by another file
class Pouch
    constructor: (@config) ->
        @db = new PouchDB @config.dbPath
        # TODO Listener memory leak fix -> still necessary?
        @db.setMaxListeners 100
        # TODO addAllViews?
        @updater = async.queue (task, callback) =>
            @db.get task._id, (err, doc) =>
                if err?.status is 404
                    @db.put task, callback
                else if err
                    callback err
                else
                    task._rev = doc._rev
                    @db.put task, callback

    # Create database and recreate all filters
    resetDatabase: (callback) =>
        @db.destroy =>
            @db = new PouchDB @config.dbPath
            @db.setMaxListeners 100
            @addAllViews callback


    ### Mini ODM ###

    # Run a query and get document
    getByKey: (query, key, callback) =>
        return callback null, null unless key?
        params =
            include_docs: true
            key: key
        @db.query query, params, (err, res) ->
            if err?.status is 404
                callback null, null
            else if err
                callback err
            else if res.rows.length is 0
                callback null, null
            else
                callback null, res.rows[0].doc

    # Run a query and get all the results
    getAll: (query, params, callback) =>
        if typeof params is 'function'
            callback = params
            params = include_docs: true
        @db.query query, params, (err, res) ->
            if err
                callback err
            else
                docs = (row.doc for row in res.rows)
                callback null, docs

    # Return all the files
    allFiles: (params, callback) =>
        @getAll 'file/all', params, callback

    # Return the file with the given fullpath
    getFile: (key, callback) =>
        @getByKey 'file/byFullPath', key, callback

    # Return all the files with this checksum
    byChecksum: (checksum, callback) ->
        params =
            key: checksum
            include_docs: true
        @getAll 'file/byChecksum', params, callback

    # Return all the folders
    allFolders: (params, callback) =>
        @getAll 'folder/all', params, callback

    # Return the folder with the given fullpath
    getFolder: (key, callback) =>
        @getByKey 'folder/byFullPath', key, callback

    # Return all the files and folders in this path
    byPath: (path, callback) ->
        params =
            key: path
            include_docs: true
        @getAll 'byPath', params, callback


    ### Views ###

    # Create all required views in the database.
    addAllViews: (callback) ->
        async.eachSeries ['folder', 'file', 'byPath'], @addViews, callback

    # Add required views for a given doctype.
    addViews: (docType, callback) =>
        id = "_design/#{docType}"
        queries = {}

        if docType in ['file', 'folder']
            queries.all = """
                function (doc) {
                    if (doc.docType === "#{docType}") {
                        emit(doc._id);
                    }
                }
                """

        if docType in ['file', 'folder']
            queries.byFullPath = """
                function (doc) {
                    if (doc.docType === "#{docType}") {
                        if (doc.path === "") {
                            emit(doc.name);
                        } else {
                            emit(doc.path + '/' + doc.name);
                        }
                    }
                }
                """

        if docType is 'file'
            queries.byChecksum = """
                function (doc) {
                    if (doc.docType === "#{docType}") {
                        emit(doc.checksum);
                    }
                }
                """

        if docType is 'byPath'
            queries.byPath = """
                function (doc) {
                    emit(doc.path);
                }
                """

        @createDesignDoc id, queries, callback


    # Create or update given design doc.
    createDesignDoc: (id, queries, callback) =>
        doc =
            _id: id
            views: {}

        for name, query of queries
            doc.views[name] = map: query

        @db.get id, (err, currentDesignDoc) =>
            if currentDesignDoc?
                doc._rev = currentDesignDoc._rev
            @db.put doc, (err) ->
                log.info "Design document created: #{id}" unless err
                callback err

    # Remove a design document for a given docType
    removeDesignDoc: (docType, callback) =>
        id = "_design/#{docType}"
        @db.get id, (err, currentDesignDoc) =>
            if currentDesignDoc?
                @db.remove id, currentDesignDoc._rev, callback
            else
                log.warn "Trying to remove a doc that does not exist: #{id}"
                callback()


    ### Helpers ###

    # Retrieve a previous doc revision from its id
    getPreviousRev: (id, callback) =>
        options =
            revs: true
            revs_info: true
            open_revs: "all"

        @db.get id, options, (err, infos) =>
            if err
                callback err
            else if infos.length > 0 and infos[0].ok?._revisions?
                rev = infos[0].ok._revisions.ids[1]
                start = infos[0].ok._revisions.start
                rev = "#{start - 1}-#{rev}"
                @db.get id, rev: rev, callback
            else
                err = new Error 'previous revision not found'
                err.status = 404
                callback err

    # Retrieve a known path from a doc, based on the doc's previous revisions
    getKnownPath: (doc, callback) =>
        @getPreviousRev doc._id, (err, res) ->
            if err and err.status isnt 404
                callback err
            else if res?.path? and res?.name?
                filePath = path.join res.path, res.name
                callback null, filePath
            else
                log.debug "Unable to find a file/folder path"
                log.debug res
                callback null


    ### Sequence numbers ###

    # Get last local replication sequence,
    # ie the last change from pouchdb that have been applied
    getLocalSeq: (callback) =>
        @db.get '_local/localSeq', (err, doc) ->
            if err?.status is 404
                callback null, 0
            else
                callback err, doc?.seq

    # Set last local replication sequence
    # It is saved in PouchDB as a local document
    # See http://pouchdb.com/guides/local-documents.html
    setLocalSeq: (seq, callback) =>
        task =
            _id: '_local/localSeq'
            _rev: doc?._rev
            seq: seq
        @updater.push task, callback

    # Get last remote replication sequence,
    # ie the last change from couchdb that have been saved in pouch
    getRemoteSeq: (callback) =>
        @db.get '_local/remoteSeq', (err, doc) ->
            if err?.status is 404
                callback null, 0
            else
                callback err, doc?.seq

    # Set last remote replication sequence
    # It is saved in PouchDB as a local document
    # See http://pouchdb.com/guides/local-documents.html
    setRemoteSeq: (seq, callback) =>
        task =
            _id: '_local/remoteSeq'
            seq: seq
        @updater.push task, callback


module.exports = Pouch
