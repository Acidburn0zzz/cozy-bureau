PouchDB = require 'pouchdb'
fs = require 'fs-extra'
async = require 'async'
log = require('printit')
    prefix: 'Data Proxy | db'

config = require './config'

db = new PouchDB(config.dbPath)

# Listener memory leak test
db.setMaxListeners 100

fs.ensureDirSync config.dir


module.exports = dbHelpers =

    db: db

    resetDatabase: (callback) ->
        PouchDB.destroy config.dbPath, ->
            dbHelpers.db = new PouchDB config.dbPath
            dbHelpers.addAllFilters callback

    files:
        rows: []
        all: (params, callback) ->
            dbHelpers.db.query 'file/all', params, callback

    allFiles: (forceQuery, callback) ->
        if forceQuery or @files.rows.length is 0
            db.query 'file/all', (err, res) ->
                @files = res or { rows: [] }
                callback err, res
        else
            callback null, @files

    folders:
        rows: []
        all: (params, callback) ->
            dbHelpers.db.query 'folder/all', params, callback

    allFolders: (forceQuery, callback) ->
        if forceQuery or @folders.rows.length is 0
            db.query 'folder/all', (err, res) ->
                @folders = res or { rows: [] }
                callback err, res
        else
            callback null, @folders

    binaries:
        rows: []
        all: (params, callback) ->
            dbHelpers.db.query 'binary/all', params, callback

    allBinaries: (forceQuery, callback) ->
        if forceQuery or @binaries.rows.length is 0
            db.query 'binary/all', (err, res) ->
                @binaries = res or { rows: [] }
                callback err, res
        else
            callback null, @binaries

    addAllFilters: (callback) ->
        async.eachSeries [ 'folder', 'file', 'binary' ], @addFilter, callback

    addFilter: (docType, callback) ->
        id = "_design/#{docType.toLowerCase()}"
        queries =
            all: """
        function (doc) {
            if (doc.docType !== undefined
                && doc.docType.toLowerCase() === "#{docType}".toLowerCase()) {
                emit(doc._id, doc);
            }
        }
        """
        if docType in ['file', 'folder', 'binary', 'File', 'Folder', 'Binary']
            queries.byFullPath = """
        function (doc) {
            if (doc.docType !== undefined
                && doc.docType.toLowerCase() === "#{docType}".toLowerCase()) {
                emit(doc.path + '/' + doc.name, doc);
            }
        }
        """

        if docType in ['binary', 'Binary']
            queries.byChecksum = """
        function (doc) {
            if (doc.docType !== undefined
                && doc.docType.toLowerCase() === "#{docType}".toLowerCase()) {
                emit(doc.checksum, null);
            }
        }
        """

        dbHelpers.createDesignDoc id, queries, (err, res) ->
            if err?
                if err.status is 409
                    callback null
                else
                    callback err
            else
                callback null


    # Create or update given design doc.
    createDesignDoc: (id, queries, callback) ->
        doc =
            _id: id
            views:
                all:
                    map: queries.all

        if queries.byFullPath?
            doc.views.byFullPath =
                map: queries.byFullPath

        if queries.byChecksum?
            doc.views.byChecksum =
                map: queries.byChecksum

        dbHelpers.db.get id, (err, currentDesignDoc) ->
            if currentDesignDoc?
                doc._rev = currentDesignDoc._rev
            dbHelpers.db.put doc, (err) ->
                if err
                    callback err
                else
                    log.info "Design document created: #{id}"
                    callback()


    removeFilter: (docType, callback) ->
        id = "_design/#{docType.toLowerCase()}"

        checkRemove = (err, res) ->
            if err?
                callback err
            else
                callback null

        log.debug id
        dbHelpers.db.get id, (err, currentDesignDoc) ->
            if currentDesignDoc?
                dbHelpers.db.remove id, currentDesignDoc._rev, checkRemove
            else
                log.warn "Trying to remove a doc that does not exist: #{id}"
                callback null



    removeIfExists: (id, callback) ->
        dbHelpers.db.get id, (err, doc) ->
            if err and err.status isnt 404
                callback err
            else if err and err.status is 404
                callback()
            else
                dbHelpers.db.remove doc, callback

