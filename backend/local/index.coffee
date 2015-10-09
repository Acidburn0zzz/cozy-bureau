fs = require 'fs-extra'

watcher = require './watcher'


class Local
    constructor: (config, @pouch, @events) ->
        @basePath = config.path
        @tmpPath  = path.join @basePath, ".cozy-desktop"
        watcher.path = @basePath
        watcher.publisher = @events
        @other = null

    start: (mode, done) ->
        fs.ensureDir @path, ->
            watcher.start done

    createReadStream: (doc, callback) ->
        callback 'TODO'


    # Remote-to-local operations
    #
    # Steps:
    # * Checks if the doc is valid: has a path and a name
    # * Ensure that the temporary directory exists
    # * Try to find a similar file based on his checksum
    #   (in that case, it just requires a local copy)
    # * Download the linked binary from remote
    # * Write to a temporary file
    # * Ensure parent folder exists
    # * Move the temporay file to its final destination
    # * Update creation and last modification dates
    #
    createFile: (doc, callback) =>
        unless doc?.path? and doc?.name? and doc.binary?.file?.id?
            log.warn "The doc is invalid: #{JSON.stringify doc}"
            callback()

        else
            tmpFile  = path.join @tmpPath, doc.path
            parent   = path.resolve @basePath, doc.path
            filePath = path.join parent, doc.name
            binaryId = doc.binary.file.id
            checksum = doc.binary.file.checksum

            async.waterfall [
                (next) =>
                    fs.ensureDir @tmpPath, next

                (res, next) ->
                    filesystem.fileExistsLocally checksum, next

                (existingFilePath, next) =>
                    if existingFilePath
                        stream = fs.createReadStream existingFilePath
                        next null, stream
                    else
                        @other.createReadStream doc, next

                # TODO verify the checksum -> remove file if not ok
                # TODO show progress
                (stream, next) ->
                    target = fs.createWriteStream tmpFile
                    stream.pipe target
                    stream.on 'end', next

                (next) ->
                    fs.ensureDir parent, next

                (next) ->
                    fs.rename tmpFile, filePath, next

                (next) ->
                    lastModification = new Date doc.lastModification
                    fs.utimes filePath, new Date(), lastModification, next

            ], (err) ->
                fs.unlink tmpFile, ->
                    callback err


    createFolder: (doc, callback) =>
        unless doc?.path? and doc?.name?
            log.warn "The doc is invalid: #{JSON.stringify doc}"
            callback()
        else
            folderPath = path.join @path, doc.path, doc.name
            fs.ensureDir folderPath, (err, res) ->
                if err
                    callback err
                else if doc.lastModification?
                    callback()
                else
                    # Update last modification date
                    lastModification = new Date doc.lastModification
                    fs.utimes folderPath, new Date(), lastModification, callback


    # FIXME too complex
    moveFile: (doc, callback) ->
        remoteConfig = config.getConfig()
        unless doc?.path? and doc?.name?
            err = new Error "The doc is invalid: #{JSON.stringify doc}"
            return callback err

        newPath = path.join remoteConfig.path, doc.path, doc.name

        updateUtimes = (filePath, callback) ->
            if doc.lastModification
                fs.utimes filePath
                        , new Date()
                        , new Date(doc.lastModification)
                        , callback
            else
                callback()

        pouch.getKnownPath doc, (err, oldPath) ->
            return callback err if err

            if oldPath is newPath
                # Check file similarities
                # TODO: base this on the checksum too
                stats = fs.statSync newPath
                if doc.size is stats.size and not stats.isDirectory()
                    return callback()

            oldPathExists = fs.existsSync oldPath
            newPathExists = fs.existsSync newPath

            # Move the file
            if oldPathExists and not newPathExists
                if doc.binary?.file?.id?
                    pouch.db.get doc.binary.file.id, (err, doc) ->
                        doc.path = newPath
                        pouch.db.put doc, (err, res) ->
                            fs.move oldPath, newPath, (err) ->
                                return callback err if err?
                                updateUtimes newPath, callback

                else
                    fs.move oldPath, newPath, (err) ->
                        return callback err if err?
                        updateUtimes newPath, callback

            # Assume that the file has already been moved
            # TODO: base this assumption on checksum ?
            else if not oldPathExists and newPathExists
                callback()

            # No file to move, do nothing
            else if not oldPathExists
                log.error "File #{oldPath} not found, and cannot be moved."
                callback()

            # The destination file already exists, duplicate
            else if oldPathExists and newPathExists
                if doc.docType.toLowerCase() is 'folder'
                    if newPath isnt oldPath
                        fs.removeSync oldPath
                    updateUtimes newPath, callback
                else
                    log.info "File #{newPath} already exists, " +
                        "duplicating to #{newPath}.new"
                    fs.move oldPath, "#{newPath}.new", (err) ->
                        return callback err if err?
                        updateUtimes "#{newPath}.new", callback


    moveFolder: (doc, callback) =>
        # For now both operations are similar.
        @moveFile doc, callback

    deleteFile: (doc, callback) =>
        @pouch.getKnownPath doc, (err, filePath) ->
            if filePath?
                fs.remove filePath, callback
            else
                callback err

    deleteFolder: (doc, callback) =>
        @pouch.getKnownPath doc, (err, folderPath) ->
            if folderPath?
                fs.remove folderPath, callback
            else
                callback err

module.exports = Local
