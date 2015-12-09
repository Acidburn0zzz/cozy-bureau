path  = require 'path-extra'
async = require 'async'
log   = require('printit')
    prefix: 'Cozy Desktop  '

Config  = require './config'
Devices = require './devices'
Pouch   = require './pouch'
Merge   = require './merge'
Prep    = require './prep'
Local   = require './local'
Remote  = require './remote'
Sync    = require './sync'


# App is the entry point for the CLI and GUI.
# They both can do actions and be notified by events via an App instance.
class App

    # basePath is the directory where the config and pouch are saved
    constructor: (basePath) ->
        @lang = 'fr'
        @basePath = basePath or path.homedir()
        @config = new Config @basePath
        @pouch  = new Pouch @config

    # This method is here to be surcharged by the UI
    # to ask its password to the user
    #
    # callback is a function that takes two parameters: error and password
    askPassword: (callback) ->
        callback new Error('Not implemented'), null


    # Register current device to remote Cozy and then save related informations
    # to the config file
    #
    # TODO validation of url, deviceName and syncPath
    addRemote: (url, deviceName, syncPath, callback) =>
        async.waterfall [
            @askPassword,
            (password, next) ->
                options =
                    url: url
                    deviceName: deviceName
                    password: password
                Devices.registerDevice options, next
        ], (err, credentials) =>
            if err
                log.error err
                log.error 'An error occured while registering your device.'
            else
                options =
                    path: path.resolve syncPath
                    url: url
                    deviceName: deviceName
                    password: credentials.password
                @config.addRemoteCozy options
                log.info 'The remote Cozy has properly been configured ' +
                    'to work with current device.'
            callback? err


    # Unregister current device from remote Cozy and then remove remote from
    # the config file
    # TODO also remove the pouch database
    removeRemote: (deviceName, callback) =>
        device = @config.getDevice deviceName
        async.waterfall [
            @askPassword,
            (password, next) ->
                device.password = password
                Devices.unregisterDevice device, next
        ], (err) =>
            if err
                log.error err
                log.error 'An error occured while unregistering your device.'
            else
                @config.removeRemoteCozy deviceName
                log.info 'Current device properly removed from remote cozy.'
            callback? err


    # Instanciate some objects before sync
    instanciate: ->
        @merge  = new Merge @pouch
        @prep   = new Prep @merge
        @local  = @merge.local  = new Local  @config, @prep, @pouch
        @remote = @merge.remote = new Remote @config, @prep, @pouch
        @sync   = new Sync @pouch, @local, @remote


    # Start the synchronization
    startSync: (mode, callback) ->
        @config.setMode mode
        log.info 'Run first synchronisation...'
        @sync.start mode, (err) ->
            if err
                log.error err
                log.error err.stack if err.stack
            callback? err


    # Stop the synchronisation
    stopSync: (callback) ->
        @sync.stop callback


    # Start database sync process and setup file change watcher
    synchronize: (mode, callback) =>
        @instanciate()
        device = @config.getDevice()
        if device.deviceName? and device.url? and device.path?
            @startSync mode, callback
        else
            log.error 'No configuration found, please run add-remote-cozy' +
                'command before running a synchronization.'
            callback? new Error 'No config'


    # Recreate the local pouch database
    resetDatabase: (callback) =>
        log.info "Recreates the local database..."
        @pouch.resetDatabase ->
            log.info "Database recreated"
            callback?()


    # Return the whole content of the database
    allDocs: (callback) =>
        @pouch.db.allDocs include_docs: true, callback


    # Return all docs for a given query
    query: (query, callback) =>
        @pouch.db.query query, include_docs: true, callback


    # Get useful information about the disk space
    # (total, used and left) on the remote Cozy
    getDiskSpace: (callback) =>
        device = @config.getDevice
        Devices.getDiskSpace device, callback


module.exports = App
