fs         = require 'fs'
path       = require 'path'
request    = require 'request-json-light'
uuid       = require 'node-uuid'
crypto     = require 'crypto'
log        = require('printit')
    prefix: 'Binary     '

config     = require './config'
pouch      = require './db'
async      = require 'async'
events     = require 'events'

module.exports = binary =


    infoPublisher: new events.EventEmitter()


    # Get checksum for given file.
    checksum: (filePath, callback) ->
        stream = fs.createReadStream filePath
        checksum = crypto.createHash 'sha1'
        checksum.setEncoding 'hex'

        stream.on 'end', ->
            checksum.end()
            callback null, checksum.read()

        stream.pipe checksum


    getRemoteDoc: (remoteId, callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        client.get "cozy/#{remoteId}", (err, res, body) ->
            if err
                callback err
            else if body.error
                callback new Error body.error
            else
                body.id  = body._id
                body.rev = body._rev
                callback null, body


    createEmptyRemoteDoc: (callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()
        data =
            docType: 'Binary'
        newId = uuid.v4().split('-').join('')
        urlPath = "cozy/#{newId}"

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        client.put urlPath, data, (err, res, body) ->
            if err
                callback err
            else if body.error
                callback new Error body.error
            else
                callback err, body


    # Upload a binary via the couchd API on the remote cozy.
    uploadAsAttachment: (remoteId, remoteRev, filePath, callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()
        relativePath = path.relative remoteConfig.path, filePath
        absPath = path.join remoteConfig.path, filePath
        urlPath = "cozy/#{remoteId}/file?rev=#{remoteRev}"

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        log.info "Uploading binary: #{relativePath}..."
        @infoPublisher.emit 'uploadBinary', absPath

        client.putFile urlPath, filePath, (err, res, body) =>
            if err
                callback err
            else
                body = JSON.parse(body) if typeof body is 'string'

                if body.error
                    callback new Error body.error
                else
                    log.info "Binary uploaded: #{relativePath}"
                    @infoPublisher.emit 'binaryUploaded', absPath
                    callback err, body


    # Change path in the binary DB document then move file in the filesystem.
    moveFromDoc: (doc, finalPath, callback) ->
        fs.rename doc.path, finalPath, (err) ->
            if err
                callback err
            else
                doc.path = finalPath
                pouch.db.put doc, callback


    # Check if a binary already exists
    # If so, return local binary DB document
    # else, return null
    docAlreadyExists: (checksum, callback) ->
        options =
            include_docs: true,
            key: checksum
        pouch.db.query 'binary/byChecksum', options, (err, docs) ->
            if err
                callback err
            else
                if not docs.rows?
                    callback null, null
                else if docs.rows.length is 0
                    callback null, null
                else
                    callback null, docs.rows[0].doc


    saveLocation: (filePath, id, rev, callback) ->
        pouch.removeIfExists id, (err) =>
            if err
                callback err
            @checksum filePath, (err, checksum) ->
                document =
                    _id: id
                    _rev: rev
                    docType: 'Binary'
                    path: filePath
                    checksum: checksum

                pouch.db.put document, (err, res) ->
                    if err
                        callback err
                    else
                        callback null, document


    # Change modification dates on file system.
    changeUtimes: (doc, binaryPath, callback) ->
        creationDate = new Date doc.creationDate
        lastModification = new Date doc.lastModification
        fs.utimes binaryPath, creationDate, lastModification, callback


    # If file exists anyway and has the right size,
    # we assume that it has already been downloaded.
    downloadFile: (options, callback) ->
        {deviceName, doc, filePath, binaryPath} = options

        remoteConfig = config.getConfig()
        deviceName ?= config.getDeviceName()

        if not fs.existsSync(binaryPath) \
           or fs.statSync(binaryPath).size isnt doc.size

            client = request.newClient remoteConfig.url
            client.setBasicAuth deviceName, remoteConfig.devicePassword

            urlPath = "cozy/#{doc.binary.file.id}/file"

            log.info "Downloading: #{filePath}..."
            client.saveFile urlPath, binaryPath, (err, res) ->

                if res
                    log.info "Binary downloaded: #{filePath}"
                    binary.infoPublisher.emit 'binaryDownloaded', binaryPath

                callback err
        else
            log.info "File already downloaded: #{filePath}"
            callback()


    # Move the binary if it has already been downloaded.
    removeBinaryIfExists: (fileDoc, binaryPath, callback) ->
        pouch.db.get fileDoc.binary.file.id, (err, binaryDoc) ->
            if err and err.status isnt 404 then callback err
            else if binaryDoc?
                pouch.db.remove binaryDoc, ->
                    if binaryDoc.path? \
                    and binaryDoc.path isnt binaryPath \
                    and fs.existsSync(binaryDoc.path)

                        fs.renameSync(binaryDoc.path, binaryPath)
                    callback()
            else
                callback()


    # Save binary path on binary object and save dates on binary.
    saveFileMetadata: (options, callback) ->
        {doc, filePath, binaryPath} = options

        if doc.binary?
            id = doc.binary.file.id
            rev = doc.binary.file.rev

            binary.saveLocation binaryPath, id, rev, (err) ->
                if err
                    callback err
                else
                    binary.changeUtimes doc, binaryPath, callback
        else
            callback null


    # Download corresponding binary
    fetchFromDoc: (deviceName, doc, callback) ->
        remoteConfig = config.getConfig()
        filePath = path.join doc.path, doc.name
        binaryPath = path.join remoteConfig.path, filePath

        if doc.binary?.file?.id?
            binary.removeBinaryIfExists doc, binaryPath, (err) ->
                if err
                    callback err
                else
                    options = {deviceName, doc, filePath, binaryPath}

                    binary.downloadFile options, (err) =>
                        if err
                            callback err
                        else
                            options = {doc, filePath, binaryPath}
                            binary.saveFileMetadata options, callback
        else
            callback null
