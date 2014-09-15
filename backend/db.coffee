PouchDB = require 'pouchdb'
fs = require 'fs-extra'
log = require('printit')
    prefix: 'Data Proxy | db'

config = require './config'

# Self-promisification
Promise = require 'bluebird'
db = Promise.promisifyAll(new PouchDB config.dbPath)

# Listener memory leak test
db.setMaxListenersAsync 30

fs.ensureDirSync config.dir

module.exports =

    db: db

    addFilter: (docType, callback) ->
        id = "_design/#{docType.toLowerCase()}"
        map = """
            function (doc) {
                if (doc.docType.toLowerCase() === "#{docType}".toLowerCase()) {
                    return emit(doc._id, doc);
                }
            }
        """

        newDesignDoc =
            _id: id
            views:
                all:
                    map: map

        checkCreation = (err, res) ->
            if err?
                if err.status is 409
                    callback null
                else
                    callback err
            else
                if not currentDesignDoc?
                    log.info "Design document created: #{id}"
                callback null

        createDesignDoc = (err, currentDesignDoc) ->
            if currentDesignDoc?
                newDesignDoc._rev = currentDesignDoc._rev
            db.put newDesignDoc, checkCreation

        db.get id, createDesignDoc

    removeFilter: (docType, callback) ->
        id = "_design/#{docType.toLowerCase()}"

        checkRemove = (err, res) ->
            if err?
                callback err
            else
                callback null

        removeDesignDoc = (err, currentDesignDoc) ->
            if currentDesignDoc?
                db.remove id, currentDesignDoc._rev, checkRemove
            else
                log.info "Design document does not exist: #{id}"
                callback null

        db.get id, removeDesignDoc
