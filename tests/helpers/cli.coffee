{options} = require './helpers'

cli = require '../../cli'
replication = require '../../backend/replication'
filesystem = require '../../backend/filesystem'

# Skips user interaction to ask password
# @TODO: replace by a sinon's stub
module.exports.mockGetPassword = ->
    @trueGetPassword = cli.getPassword
    cli.getPassword = (callback) -> callback null, options.cozyPassword

# Restores regular behaviour
module.exports.restoreGetPassword = ->
    cli.getPassword = @trueGetPassword

# Configures a fake device for a fake remote Cozy
module.exports.initConfiguration = (done) ->
    @timeout 1500

    {url, syncPath} = options
    deviceName = 'tester'
    cli.addRemote url, deviceName, syncPath
    setTimeout done, 1000

# Removes the configuration
module.exports.cleanConfiguration = (done) ->
    @timeout 1500
    cli.removeRemote {}
    setTimeout done, 1000

# Starts the sync process
module.exports.startSync = (done) ->
    @timeout 3000

    continuous = true
    filesystem.watchChanges continuous, true

    # Replicate databases
    replication.runReplication
        fromRemote: false
        toRemote: false
        continuous: continuous
        rebuildTree: true
        fetchBinary: true
    , (err) -> # nothing

    setTimeout done, 2500

# replicates the remote Couch into the local Pouch
module.exports.initialReplication = (done) ->
    replication.runReplication
        fromRemote: true
        toRemote: false
        continuous: false
        rebuildTree: true
        fetchBinary: true
    , done
