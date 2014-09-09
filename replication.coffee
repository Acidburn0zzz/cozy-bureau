fs         = require 'fs'
touch      = require 'touch'
request    = require 'request-json'
urlParser  = require 'url'
log        = require('printit')
             prefix: 'Data Proxy | replication'

pouch      = require './db'
config     = require './config'
filesystem = require './filesystem'
binary     = require './binary'

filters = []
remoteConfig = config.getConfig()

module.exports =

    registerDevice: (options, callback) ->
        client = request.newClient options.url
        client.setBasicAuth 'owner', options.password

        data = login: options.deviceName
        client.post 'device/', data, (err, res, body) ->
            if err
                callback err + body

            else if body.error
                callback new Error body.error

            else
                callback null,
                    id: body.id
                    password: body.password

    unregisterDevice: (options, callback) ->
        client = request.newClient options.url
        client.setBasicAuth 'owner', options.password

        client.del "device/#{options.deviceId}/", (err, res, body) ->
            if err
                callback err + body

            else if body.error
                callback new Error body.error

            else
                callback null

    runReplication: (fromRemote, toRemote, continuous, rebuildFs, fetchBinary, callback) ->
        deviceName = config.getDeviceName()
        continuous ?= false
        rebuildFs ?= false
        fetchBinary ?= false

        # Specify which way to replicate
        if fromRemote and not toRemote
            log.info "Running replication from remote database"
            replicate = pouch.db.replicate.from
        else if toRemote and not fromRemote
            log.info "Running replication to remote database"
            replicate = pouch.db.replicate.to
        else
            log.info "Running synchronization with remote database"
            replicate = pouch.db.sync

        # Replicate only files and folders for now
        options =
            filter: (doc) ->
                doc.docType is 'Folder' or doc.docType is 'File'
            live: continuous

        # Define action after replication completion
        applyChanges = (callback) ->

            # Lock file watcher to avoid remotely downloaded files to be re-uploaded
            filesystem.watchingLocked = true
            if fetchBinary

                # Fetch binaries
                binary.fetchAll deviceName, ->
                    filesystem.watchingLocked = false
                    callback null
            else

                # Or rebuild the filesystem directory tree only
                filesystem.buildTree null, ->
                    filesystem.watchingLocked = false
                    callback null

        # Do not need rebuild until docs are added
        needTreeRebuild = false

        # Set authentication
        url = urlParser.parse remoteConfig.url
        url.auth = "#{deviceName}:#{remoteConfig.devicePassword}"

        # Launch replication
        replicate(urlParser.format(url) + 'cozy', options)
        .on 'change', (info) ->
            changeMessage = "DB change: #{info.change.docs_written} doc(s) written"
            if info.direction
                # Specify direction
                changeMessage = "#{info.direction} #{changeMessage}"

            # Find out if filesystem tree needs a rebuild
            if (not info.direction? and fromRemote and info.docs_written > 0) \
                or (info.direction is 'pull' and info.change.docs_written > 0)
                needTreeRebuild = rebuildFs

        # Called only for a continuous replication
        .on 'uptodate', (info) ->
            log.info 'Replication is complete'
            if needTreeRebuild
                log.info 'Applying changes on the filesystem'
                applyChanges ->
                    needTreeRebuild = false

        # Called only for a single replication
        .on 'complete', (info) ->
            log.info 'Replication is complete'
            if fromRemote and not toRemote
                log.info 'Applying changes on the filesystem'
                applyChanges -> callback null
            else
                callback null

        .on 'error', (err) ->
            log.error err
            callback err


    runSync: (target) ->

