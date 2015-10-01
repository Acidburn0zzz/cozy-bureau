#!/usr/bin/env coffee

fs = require 'fs-extra'
path = require 'path-extra'
program = require 'commander'
read = require 'read'
log = require('printit')
    prefix: 'Cozy Desktop  '

config = require '../backend/config'
filesystem = require '../backend/filesystem'
pouch = require '../backend/db'
device = require '../backend/device'
localEventWatcher = require '../backend/local_event_watcher'
remoteEventWatcher = require '../backend/remote_event_watcher'
pkg = require '../package.json'


# Helpers to get cozy password from user.
getPassword = (callback) ->
    promptMsg = 'Please enter your password to register your device to ' + \
                'your remote Cozy: '
    read prompt: promptMsg, silent: true , callback


# Register current device to remote Cozy. Then it saves related informations
# to the config file.
addRemote = (url, deviceName, syncPath) ->
    saveConfig = (err, credentials) ->
        if err
            log.error err
            log.error 'An error occured while registering your device.'
        else
            options =
                url: url
                deviceName: deviceName
                path: path.resolve syncPath
                deviceId: credentials.id
                devicePassword: credentials.password

            config.addRemoteCozy options
            log.info 'Remote Cozy properly configured to work ' + \
                     'with current device.'

    register = (err, password) ->
        options =
            url: url
            deviceName: deviceName
            password: password

        device.registerDevice options, saveConfig

    getPassword register


# Unregister current device from remote Cozy. Then it removes remote from
# config file.
removeRemote = (args) ->
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    saveConfig = (err) ->
        if err
            log.error err
            log.error 'An error occured while unregistering your device.'
        else
            config.removeRemoteCozy deviceName
            log.info 'Current device properly removed from remote cozy.'

    unregister = (err, password) ->
        options =
            url: remoteConfig.url
            deviceId: remoteConfig.deviceId
            password: password
        device.unregisterDevice options, saveConfig

    getPassword unregister


# Display the whole content of the database.
displayDatabase = ->
    pouch.db.allDocs include_docs: true, (err, results) ->
        if err
            log.error err
        else
            results.rows.map (row) ->
                console.log row.doc


# Disaply all docs returned by a given query.
displayQuery = (query) ->
    log.info "Query: #{query}"
    pouch.db.query query, (err, results) ->
        if err
            log.error err
        else
            results.rows.map (row) ->
                console.log "key: #{row.key}"
                console.log "value #{JSON.stringify row.value}"


# Start database sync process and setup file change watcher.
sync = (args) ->
    # FIXME readonly is the only supported mode for the moment
    args.readonly = true

    config.setInsecure(args.insecure?)

    config = config.getConfig()

    if config.deviceName? and config.url? and config.path?
        fs.ensureDir config.path, ->
            pouch.addAllFilters ->
                remoteEventWatcher.init args.readonly, ->
                    log.info "Init done"
                    remoteEventWatcher.start ->
                        unless args.readonly
                            localEventWatcher.start()
    else
        log.error 'No configuration found, please run add-remote-cozy' + \
            'command before running a synchronization.'


# Display current configuration
displayConfig = ->
    console.log JSON.stringify config.config, null, 2


resetDatabase = ->
    log.info "Recreates the local database..."
    pouch.resetDatabase ->
        log.info "Database recreated"


program
    .command 'add-remote-cozy <url> <devicename> <syncPath>'
    .description 'Configure current device to sync with given cozy'
    .action addRemote

program
    .command 'remove-remote-cozy'
    .description 'Unsync current device with its remote cozy'
    .option '-d, --deviceName [deviceName]', 'device name to deal with'
    .action removeRemote

program
    .command 'sync'
    .description 'Sync databases, apply and/or watch changes'
    # FIXME readonly is the only supported mode for the moment
    # .option('-r, --readonly',
    #        'only apply remote changes to local folder')
    .option('-f, --force',
            'Run sync from the beginning of all the Cozy changes.')
    .option('-k, --insecure',
            'Turn off HTTPS certificate verification.')
    .action sync

program
    .command 'reset-database'
    .description 'Recreates the local database'
    .action resetDatabase

program
    .command 'display-database'
    .description 'Display database content'
    .action displayDatabase

program
    .command 'display-query <query>'
    .description 'Display database query result'
    .action displayQuery

program
    .command 'display-config'
    .description 'Display device configuration and exit'
    .action displayConfig

program
    .command "*"
    .description "Display help message for an unknown command."
    .action ->
        log.info 'Unknown command, run "cozy-desktop --help"' + \
                 ' to know the list of available commands.'

program
    .version pkg.version


program.parse process.argv
if process.argv.length <= 2
    program.outputHelp()
