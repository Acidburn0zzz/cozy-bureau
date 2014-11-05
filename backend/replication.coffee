fs         = require 'fs'
path       = require 'path'
touch      = require 'touch'
request    = require 'request-json-light'
urlParser  = require 'url'
mkdirp     = require 'mkdirp'
async      = require 'async'
log        = require('printit')
    prefix: 'Replication'

pouch      = require './db'
config     = require './config'
filesystem = require './filesystem'
binary     = require './binary'

filters = []

module.exports = replication =

    replicationIsRunning: false
    treeIsBuilding: false

    # Register device remotely then returns credentials given by remote Cozy.
    # This credentials will allow the device to access to the Cozy database.
    registerDevice: (options, callback) ->
        client = request.newClient options.url
        client.setBasicAuth 'owner', options.password

        data =
            login: options.deviceName

        client.post 'device/', data, (err, res, body) ->
            if err
                callback err
            if body.error?
                if body.error is 'string'
                    log.error body.error
                else
                    callback body.error
            else
                callback null,
                    id: body.id
                    password: body.password



    # Unregister device remotely, ask for revocation.
    unregisterDevice: (options, callback) ->
        client = request.newClient options.url
        client.setBasicAuth 'owner', options.password

        client.del "device/#{options.deviceId}/", callback


    # Give the right pouch function to run the replication depending on
    # parameters.
    getReplicateFunction: (toRemote, fromRemote) ->
        if fromRemote and not toRemote
            log.info "Running replication from remote database"
            replicate = pouch.db.replicate.from
        else if toRemote and not fromRemote
            log.info "Running replication to remote database"
            replicate = pouch.db.replicate.to
        else
            log.info "Running synchronization with remote database"
            replicate = pouch.db.sync

        return replicate


    applyChanges: (since, callback) ->
        remoteConfig = config.getConfig()

        since ?= config.getSeq()

        pouch.db.changes(
            filter: (doc) ->
                doc.docType is 'Folder' or doc.docType is 'File'
            since: since
            include_docs: true
        ).on('complete', (res) ->

            async.eachSeries res.results, (change, callback) ->
                saveSeq = (err, res) ->
                    if err
                        callback err
                    else
                        config.setSeq(change.seq)
                        callback null

                if change.deleted
                    if change.doc.docType is 'Folder'
                        filesystem.changes.push
                            operation: 'removeUnusedDirectories'
                        , saveSeq
                    else if change.doc.binary?.file?.id?
                        filesystem.changes.push
                            operation: 'delete'
                            id: change.doc.binary.file.id
                        , saveSeq
                else
                    if change.doc.docType is 'Folder'
                        absPath = path.join remoteConfig.path,
                                            change.doc.path,
                                            change.doc.name
                        filesystem.changes.push
                            operation: 'newFolder'
                            path: absPath
                        , saveSeq
                            #filesystem.changes.push
                            #   operation: 'removeUnusedDirectories'
                            #, saveSeq
                    else
                        filesystem.changes.push
                            operation: 'get'
                            doc: change.doc
                        , saveSeq
            , callback

        ).on 'error', (err) ->
            callback err


    runReplication: (options, callback) ->

        remoteConfig = config.getConfig()

        fromRemote = options.fromRemote
        toRemote = options.toRemote
        continuous = options.continuous or false
        catchup = options.catchup or false
        initial = options.initial or false
        firstSync = initial

        deviceName = config.getDeviceName()
        replicate = @getReplicateFunction toRemote, fromRemote

        # Do not take into account all the changes if it is the first sync
        firstSync = initial

        # Replicate only files and folders for now
        options =
            filter: (doc) ->
                doc.docType is 'Folder' or doc.docType is 'File'
            live: not firstSync and continuous

        # Set authentication
        url = urlParser.parse remoteConfig.url
        url.auth = "#{deviceName}:#{remoteConfig.devicePassword}"
        # Format URL
        url = urlParser.format(url) + 'cozy'

        # TODO improve loggging
        # TODO extract this function
        onChange = (info) ->
            if info.change? and info.change.docs_written > 0
                changeMessage = "DB change: #{info.change.docs_written}
                                 doc(s) written"
            else if info.docs_written > 0
                changeMessage = "DB change: #{info.docs_written} doc(s) written"

            # Specify direction
            if info.direction and changeMessage?
                changeMessage = "#{info.direction} #{changeMessage}"

            log.info changeMessage if changeMessage?

        # TODO extract this function
        onComplete = (info) =>
            if firstSync
                if info.last_seq?
                    since = info.last_seq
                else if info.pull?.last_seq?
                    since = info.pull.last_seq
                else
                    since = 'now'
            else
                since = config.getSeq()

            if firstSync or \
               (info.change? and info.change.docs_written > 0) or \
               info.docs_written > 0

                @cancelReplication()

                @applyChanges since, =>
                    firstSync = false
                    options.live = true
                    @timeout = setTimeout =>
                        @replicator = replicate(url, options)
                            .on 'change', onChange
                            .on 'complete', (info) ->
                                filesystem.changes.push { operation: 'reDownload' }, ->
                                    onComplete info
                            .on 'uptodate', (info) ->
                                filesystem.changes.push { operation: 'reDownload' }, ->
                                    onComplete info
                            .on 'error', onError
                        .catch onError
                    , 5000

        # TODO extract this function
        onError = (err, data) ->
            if err?.status is 409
                log.error "Conflict, ignoring"
            else
                log.error err

            onComplete
                change:
                    docs_written: 0

        if catchup
            operation = 'catchup'
        else
            operation = 'removeUnusedDirectories'

        filesystem.changes.push { operation: operation }, =>
            @timeout = setTimeout =>
                @replicator = replicate(url, options)
                    .on 'change', onChange
                    .on 'complete', onComplete
                    .on 'uptodate', onComplete
                    .on 'error', onError
                .catch onError
            , 1000

    cancelReplication: ->
        clearTimeout @timeout
        @replicator.cancel() if @replicator?
        @timeout = null
        @replicator = null
