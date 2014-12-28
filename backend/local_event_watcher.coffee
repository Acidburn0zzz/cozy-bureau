chokidar = require 'chokidar'
path = require 'path'
fs = require 'fs'
log = require('printit')
    prefix: 'Local watcher '

#
# Local backend files
#
filesystem = require './filesystem'
config = require './config'
publisher  = require './publisher'

#
# This file contains the filesystem watcher that will trigger operations when
# a file or a folder is added/removed/changed locally.
# Operations will be added to the a common operation queue along with the
# remote operations triggered by the remoteEventWatcher.
#
# See `operationQueue.coffee` for more information.
#
localEventWatcher =

    # Start chokidar, the filesystem watcher
    # https://github.com/paulmillr/chokidar
    #
    # continuous: Launch chokidar as a daemon, watching live changes.
    #             Default to `true`.
    #
    # fromNow: Do not mind past changes. Setting this to `false` will
    #          cause chokidar to detect every files/folders in the
    #          directory as new. Default to `true`.
    start: (continuous, fromNow) ->
        operationQueue = require './operation_queue'

        log.info 'Start watching filesystem for changes'

        remoteConfig = config.getConfig()

        continuous ?= true
        fromNow ?= true

        localEventWatcher.watcher = chokidar.watch remoteConfig.path,
            persistent: continuous
            ignoreInitial: fromNow
            interval: 2000
            binaryInterval: 2000
            #ignored: /[\/\\]\./

        # New file detected
        .on 'add', (filePath) ->
            if not filesystem.locked \
            and not filesystem.filesBeingCopied[filePath]?
                log.info "File added: #{filePath}"
                publisher.emit 'fileAddedLocally', filePath
                filesystem.isBeingCopied filePath, ->
                    operationQueue.queue.push
                        operation: 'createFileRemotely'
                        file: filePath
                    , ->

        # New directory detected
        .on 'addDir', (folderPath) ->
            if not filesystem.locked \
            and folderPath isnt remoteConfig.path
                log.info "Directory added: #{folderPath}"
                publisher.emit 'folderAddedLocally', folderPath
                operationQueue.queue.push
                    operation: 'createFolderRemotely'
                    folder: folderPath
                , ->

        # File deletion detected
        .on 'unlink', (filePath) ->

            if not filesystem.locked and not fs.existsSync filePath
                log.info "File deleted: #{filePath}"
                publisher.emit 'fileDeletedLocally', filePath
                operationQueue.queue.push
                    operation: 'deleteFileRemotely'
                    file: filePath
                , ->

        # Folder deletion detected
        .on 'unlinkDir', (folderPath) ->
            if not filesystem.locked
                log.info "Folder deleted: #{folderPath}"
                publisher.emit 'folderDeletedLocally', folderPath
                operationQueue.queue.push
                    operation: 'deleteFolderRemotely'
                    folder: folderPath
                , ->

        # File update detected
        .on 'change', (filePath) ->

            filePath = path.join remoteConfig.path, filePath

            if fs.existsSync filePath
                onChange filePath
            else
                setTimeout ->
                    if fs.existsSync filePath
                        onChange filePath
                , 1000

        .on 'error', (err) ->
            log.error 'An error occured while watching changes:'
            console.error err


    watcher: null


onChange = (filePath) ->
    # Chokidar sometimes detect changes with a relative path
    # In this case we want to adjust the path to be consistent
    re = new RegExp "^#{remoteConfig.path}"
    if not re.test filePath
        relativePath = filePath
        filePath = path.join remoteConfig.path, filePath

    if not filesystem.locked \
    and not filesystem.filesBeingCopied[filePath]? \
    and fs.existsSync filePath
        log.info "File changed: #{filePath}"
        publisher.emit 'fileChangedLocally', filePath
        filesystem.isBeingCopied filePath, ->
            log.debug "#{relativePath} copy is finished."
            operationQueue.queue.push
                operation: 'updateFileRemotely'
                file: filePath
            , ->
                log.debug 'File uploaded remotely'


module.exports = localEventWatcher
