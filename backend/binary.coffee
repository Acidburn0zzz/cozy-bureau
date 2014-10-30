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

module.exports =


    infoPublisher: new events.EventEmitter()


    checksum: (filePath, callback) ->
        stream = fs.createReadStream filePath
        checksum = crypto.createHash 'sha1'
        checksum.setEncoding 'hex'

        stream.on 'end', ->
            checksum.end()
            callback null, checksum.read()

        stream.pipe checksum


    moveFromDoc: (doc, finalPath, callback) ->
        # Change path in the binary DB document
        savePathInBinary = (err) ->
            if err
                callback err
            else
                doc.path = finalPath
                pouch.db.put doc, callback

        # Move file in the filesystem
        fs.rename doc.path, finalPath, savePathInBinary


    uploadAsAttachment: (remoteId, remoteRev, filePath, callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()
        relativePath = path.relative remoteConfig.path, filePath
        absPath = path.join remoteConfig.path, filePath
        urlPath = "cozy/#{remoteId}/file?rev=#{remoteRev}"

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        log.info "Uploading binary: #{relativePath}"
        @infoPublisher.emit 'uploadBinary', absPath

        returnInfos = (err, res, body) =>
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

        client.putFile urlPath, filePath, returnInfos


    createEmptyRemoteDoc: (callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()
        data = { docType: 'Binary' }
        newId = uuid.v4().split('-').join('')
        urlPath = "cozy/#{newId}"

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        onResult = (err, res, body) ->
            if err
                callback err
            else if body.error
                callback new Error body.error
            else
                callback err, body

        client.put urlPath, data, onResult


    getRemoteDoc: (remoteId, callback) ->
        remoteConfig = config.getConfig()
        deviceName = config.getDeviceName()

        client = request.newClient remoteConfig.url
        client.setBasicAuth deviceName, remoteConfig.devicePassword

        checkErrors = (err, res, body) ->
            if err
                callback err
            else if body.error
                callback new Error body.error
            else
                body.id  = body._id
                body.rev = body._rev
                callback null, body

        client.get "cozy/#{remoteId}", checkErrors


    docAlreadyExists: (checksum, callback) ->
        # Check if a binary already exists
        # If so, return local binary DB document
        # else, return null
        pouch.allBinaries true, (err, existingDocs) ->
            if err
                callback err
            else
                if existingDocs
                    # Loop through existing binaries
                    for existingDoc in existingDocs.rows
                        existingDoc = existingDoc.value
                        if existingDoc.checksum? and \
                        existingDoc.checksum is checksum
                            return callback null, existingDoc
                    return callback null, null
                else
                    return callback null, null


    saveLocation: (filePath, id, rev, callback) ->
        createDoc = (err) =>
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

        removeOrCreateDoc = (err, doc) ->
            if err and err.status isnt 404
                callback err
            else if err and err.status is 404
                createDoc()
            else
                pouch.db.remove doc, createDoc

        pouch.db.get id, removeOrCreateDoc


    fetchFromDoc: (deviceName, doc, callback) ->
        remoteConfig = config.getConfig()
        deviceName ?= config.getDeviceName()
        filePath = path.join doc.path, doc.name
        binaryPath = path.join remoteConfig.path, filePath
        relativePath = path.relative remoteConfig.path, filePath

        # Change modification dates on file system.
        changeUtimes = (err, res) ->
            if err
                callback err
            else
                creationDate = new Date doc.creationDate
                lastModification = new Date doc.lastModification
                fs.utimes binaryPath, creationDate, lastModification, callback

        # save Binary path in a binary document.
        saveBinaryPath = (err, res) =>
            if err
                callback err
            if res
                log.info "Binary downloaded: #{filePath}"
                @infoPublisher.emit 'binaryDownloaded', binaryPath
            if doc.binary?
                id = doc.binary.file.id
                rev = doc.binary.file.rev

                @saveLocation binaryPath, id, rev, changeUtimes
            else
                callback null

        downloadFile = ->
            # If file exists anyway and has the right size,
            # we assume that it has already been downloaded
            unless fs.existsSync(binaryPath) \
               and fs.statSync(binaryPath).size is doc.size

                # Initialize remote HTTP client
                client = request.newClient remoteConfig.url
                client.setBasicAuth deviceName, remoteConfig.devicePassword

                # Launch download
                urlPath = "cozy/#{doc.binary.file.id}/file"

                try
                    fs.unlinkSync binaryPath
                catch e
                    # nothing
                finally
                    client.saveFile urlPath, binaryPath, saveBinaryPath
            else
                saveBinaryPath()

        # Move the binary if it has already been downloaded
        removeBinary = (err, binaryDoc) ->
            if err and err.status isnt 404 then throw new Error err
            else if binaryDoc?
                pouch.db.remove binaryDoc, ->
                    if binaryDoc.path? and binaryDoc.path isnt binaryPath \
                    and fs.existsSync(binaryDoc.path)
                        fs.renameSync(binaryDoc.path, binaryPath)
                    downloadFile()
            else
                downloadFile()

        if doc.binary?.file?.id?
            # Check if the binary document exists
            pouch.db.get doc.binary.file.id, removeBinary
        else
            callback null
