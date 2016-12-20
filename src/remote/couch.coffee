PouchDB = require 'pouchdb'
async   = require 'async'
fs      = require 'fs-extra'
isEqual = require 'lodash.isequal'
path    = require 'path'
pick    = require 'lodash.pick'
request = require 'request-json-light'
uuid    = require 'node-uuid'
log     = require('printit')
    prefix: 'Remote CouchDB'
    date: true


# Couch is an helper class for communication with a remote couchdb.
# It uses the pouchdb library for usual stuff, as it helps to deal with errors.
# But for attachments, pouchdb uses buffers, which is not ideal in node.js
# because it can takes a lot of memory. So, we prefered to use
# request-json-light, that can stream data.
class Couch

    # Create a new unique identifier for CouchDB
    @newId: ->
        uuid.v4().replace /-/g, ''

    constructor: (@config, @events) ->
        device  = @config.getDevice()
        options = @config.augmentCouchOptions
            auth:
                username: device.deviceName
                password: device.password
        @client = new PouchDB "#{device.url}/cozy", options
        @http = request.newClient device.url
        @http.setBasicAuth device.deviceName, device.password
        @online = true
        @upCallbacks = []

    # Try to ping CouchDb to check that we can communicate with it
    # (the desktop has network access and the cozy stack is up).
    ping: (callback) =>
        @client.get '', (err, res) =>
            online = not err and res.db_name?
            if online and not @online
                @goingOnline()
            else if not online and @online
                @goingOffline()
            callback @online
        return

    # Couch is available again!
    goingOnline: ->
        log.info 'The network is available again'
        @online = true
        cb() for cb in @upCallbacks
        @upCallbacks = []
        @events.emit 'online'

    # Couch is no longer available.
    # Check every minute if the network is back.
    goingOffline: ->
        log.info "The Cozy can't be reached currently"
        @online = false
        @events.emit 'offline'
        interval = setInterval =>
            @ping (available) ->
                clearInterval interval if available
        , 60000

    # The callback will be called when couch will be available again.
    whenAvailable: (callback) =>
        if @online
            callback()
        else
            @upCallbacks.push callback

    # Retrieve a document from remote cozy based on its ID
    get: (id, callback) =>
        @client.get id, callback
        return

    # Save a document on the remote couch
    put: (doc, callback) =>
        @client.put doc, callback
        return

    # Delete a document on the remote couch
    remove: (id, rev, callback) =>
        @client.remove id, rev, callback
        return

    # Get the last sequence number from the remote couch
    getLastRemoteChangeSeq: (callback) =>
        log.info "Getting last remote change sequence number:"
        options =
            descending: true
            limit: 1
        @client.changes options, (err, change) ->
            callback err, change?.last_seq
        return

    # TODO create our views on couch, instead of using those of files
    pickViewToCopy: (model, callback) =>
        log.info "Getting design doc #{model} from remote"
        @client.get "_design/#{model}", (err, designdoc) ->
            if err
                callback err
            else if designdoc.views?['files-all']
                callback null, 'files-all'
            else if designdoc.views?.all
                callback null, 'all'
            else
                callback new Error 'install files app on cozy'
        return

    # Retrieve documents from a view on the remote couch
    getFromRemoteView: (model, callback) =>
        @pickViewToCopy model, (err, viewName) =>
            return callback err if err
            log.info "Getting latest #{model} documents from remote"
            opts = include_docs: true
            @client.query "#{model}/#{viewName}", opts, (err, body) ->
                callback err, body?.rows

    # Upload given file as attachment of given document (id + revision)
    uploadAsAttachment: (id, rev, mime, attachment, callback) =>
        urlPath = "cozy/#{id}/file?rev=#{rev}"
        @http.headers['content-type'] = mime
        @http.putFile urlPath, attachment, (err, res, body) ->
            if err
                callback err
            else if body.error
                callback body.error
            else
                log.info "Binary uploaded"
                callback null, body

    # Give a readable stream of a file stored on the remote couch
    downloadBinary: (binaryId, callback) =>
        urlPath = "cozy/#{binaryId}/file"
        log.info "Download #{urlPath}"
        @http.saveFileAsStream urlPath, (err, res) ->
            if res?.statusCode is 404
                err = new Error 'Cannot download the file'
                res.on 'data', ->  # Purge the stream
            callback err, res

    # Compare two remote docs and say if they are the same,
    # i.e. can we replace one by the other with no impact
    sameRemoteDoc: (one, two) ->
        fields = ['path', 'name', 'creationDate', 'checksum', 'size']
        one = pick one, fields
        two = pick two, fields
        return isEqual one, two

    # Put the document on the remote cozy
    # In case of a conflict in CouchDB, try to see if the changes on the remote
    # sides are trivial and can be ignored.
    putRemoteDoc: (doc, old, callback) =>
        @put doc, (err, created) =>
            if err?.status is 409
                @get doc._id, (err, current) =>
                    if err
                        callback err
                    else if @sameRemoteDoc current, old
                        doc._rev = current._rev
                        @put doc, callback
                    else
                        callback new Error 'Conflict'
            else
                callback err, created

    # Remove a remote document
    # In case of a conflict in CouchDB, try to see if the changes on the remote
    # sides are trivial and can be ignored.
    removeRemoteDoc: (doc, callback) =>
        doc._deleted = true
        @put doc, (err, removed) =>
            if err?.status is 409
                @get doc._id, (err, current) =>
                    if err
                        callback err
                    else if @sameRemoteDoc current, doc
                        current._deleted = true
                        @put current, callback
                    else
                        callback new Error 'Conflict'
            else
                callback err, removed


module.exports = Couch
