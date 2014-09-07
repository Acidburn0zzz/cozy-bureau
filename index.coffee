Promise = require 'bluebird'
fs = Promise.promisifyAll require('fs')
path = require 'path'
request = Promise.promisifyAll require('request-json')
mkdirp = Promise.promisifyAll require('mkdirp')
program = require 'commander'
read = require 'read'
touch = Promise.promisifyAll require('touch')
mime = require 'mime'
process = require 'process'
uuid = require 'node-uuid'
async = require 'async'
chokidar = require 'chokidar'
urlParser = require 'url'
log = require('printit')
    prefix: 'Data Proxy'

replication = Promise.promisifyAll require('./replication')
config = require './config'
db = Promise.promisifyAll require('./db').db
filesystem = require('./filesystem')
binary = require('./binary')


getPassword = (callback) ->
    promptMsg = 'Please enter your password to register your device to ' + \
                'your remote Cozy: '
    read prompt: promptMsg, silent: true , callback


addRemote = (url, deviceName, syncPath) ->
    getPassword (err, password) ->
        options =
            url: url
            deviceName: deviceName
            password: password

        replication.registerDevice options, (err, credentials) ->
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


removeRemote = (args) ->
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    getPassword (err, password) ->
        options =
            url: remoteConfig.url
            deviceId: remoteConfig.deviceId
            password: password

        replication.unregisterDevice options, (err) ->
            if err
                log.error err
                log.error 'An error occured while unregistering your device.'
            else
                config.removeRemoteCozy deviceName
                log.info 'Current device properly removed from remote cozy.'


replicateFromRemote = (args) ->
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    options =
        filter: (doc) ->
            doc.docType is 'Folder' or doc.docType is 'File'

    url = urlParser.parse remoteConfig.url
    url.auth = deviceName + ':' + remoteConfig.devicePassword
    replication = db.replicate.from(urlParser.format(url) + 'cozy', options)
      .on 'change', (info) ->
          console.log info
      .on 'complete', (info) ->
          log.info 'Replication is complete'
      .on 'error', (err) ->
          log.error err


replicateToRemote = (args) ->
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    options =
        filter: (doc) ->
            doc.docType is 'Folder' or doc.docType is 'File'

    url = urlParser.parse remoteConfig.url
    url.auth = "#{deviceName}:#{remoteConfig.devicePassword}"
    replication = db.replicate.to(urlParser.format(url) + 'cozy', options)
      .on 'change', (info) ->
          console.log info
      .on 'complete', (info) ->
          log.info 'Replication is complete'
      .on 'error', (err) ->
          log.error err


runSync = (args) ->
    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    watcher = chokidar.watch remoteConfig.path,
        ignored: /[\/\\]\./
        persistent: true
        ignoreInitial: not args.catchup?

    watcher
    .on 'add', (path) ->
        log.info "File added: #{path}"
        putFile deviceName, path, () ->
    .on 'addDir', (path) ->
        if path isnt remoteConfig.path
            log.info "Directory added: #{path}"
            putDirectory path, { deviceName: deviceName, recursive: false }, () ->
    .on 'change', (path) ->
        log.info "File changed: #{path}"
        putFile deviceName, path, () ->
    .on 'error', (err) ->
        log.error 'An error occured when watching changes'
        console.log err

    options =
        filter: (doc) ->
            doc.docType is 'Folder' or doc.docType is 'File'
        live: true

    url = urlParser.parse remoteConfig.url
    url.auth = deviceName + ':' + remoteConfig.devicePassword
    needTreeRebuild = false
    replication = db.sync(urlParser.format(url) + 'cozy', options)
      .on 'change', (info) ->
          if info.direction is 'pull'
              needTreeRebuild = true
          console.log info
      .on 'uptodate', (info) ->
          log.info 'Replication is complete, applying changes on the filesystem...'
          if needTreeRebuild
              if args.binary?
                  fetchBinaries deviceName, {}, () ->
                      needTreeRebuild = false
              else
                  buildFsTree deviceName, {}, () ->
                      needTreeRebuild = false
      .on 'error', (err) ->
          log.error err


watchLocalChanges = (args) ->
    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    watcher = chokidar.watch remoteConfig.path,
        ignored: /[\/\\]\./
        persistent: true
        ignoreInitial: not args.catchup?

    watcher
    .on 'add', (path) ->
        log.info "File added: #{path}"
        putFile deviceName, path, () ->
    .on 'addDir', (path) ->
        if path isnt remoteConfig.path
            log.info "Directory added: #{path}"
            putDirectory deviceName, path, { deviceName: deviceName, recursive: false }, () ->
    .on 'change', (path) ->
        log.info "File changed: #{path}"
        putFile deviceName, path, () ->
    .on 'error', (err) ->
        log.error 'An error occured when watching changes'
        console.log err

    options =
        filter: (doc) ->
            doc.docType is 'Folder' or doc.docType is 'File'
        live: true

    url = urlParser.parse remoteConfig.url
    url.auth = deviceName + ':' + remoteConfig.devicePassword
    replication = db.replicate.to(urlParser.format(url) + 'cozy', options)
      .on 'change', (info) ->
          console.log info
      .on 'uptodate', (info) ->
          log.info 'Replication is complete'
      .on 'error', (err) ->
          log.error err


watchRemoteChanges = (args) ->
    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    options =
        filter: (doc) ->
            doc.docType is 'Folder' or doc.docType is 'File'
        live: true

    url = urlParser.parse remoteConfig.url
    url.auth = deviceName + ':' + remoteConfig.devicePassword
    replication = db.replicate.from(urlParser.format(url) + 'cozy', options)
      .on 'change', (info) ->
          console.log info
      .on 'uptodate', (info) ->
          log.info 'Replication is complete, applying changes on the filesystem...'
          if args.binary?
              fetchBinaries deviceName, {}, () ->
          else
              buildFsTree deviceName, {}, () ->
      .on 'error', (err) ->
          log.error err


fetchBinaries = (args, callback) ->
    # Fix callback
    if not callback? or typeof callback is 'object'
        callback = (err) ->
            process.exit 1 if err?
            process.exit 0

    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()
    filePath = args.filePath

    # Initialize remote HTTP client
    client = request.newClient remoteConfig.url
    client.setBasicAuth deviceName, remoteConfig.devicePassword

    # Create files and directories in the FS
    buildFsTree deviceName, { filePath: filePath }, (err, res) ->

        # Fetch only files
        db.query { map: (doc) -> emit doc._id, doc if doc.docType is 'File' }, (err, res) ->
            async.each res.rows, (doc, callback) ->
                doc = doc.value
                if (not filePath? or filePath is path.join doc.path, doc.name) and doc.binary?
                    binaryPath = path.join remoteConfig.path, doc.path, doc.name
                    binaryUri = "cozy/#{doc.binary.file.id}/file"

                    # Check if binary has been downloaded already, otherwise save its path locally
                    binaryDoc =
                        docType: 'Binary'
                        path: binaryPath
                    db.put binaryDoc, doc.binary.file.id, doc.binary.file.rev, (err, res) ->
                        if err? and err.status is 409
                            # Binary already downloaded, ignore
                            callback()
                        else
                            # Fetch binary via CouchDB API
                            log.info "Downloading binary: #{path.join doc.path, doc.name}"
                            client.saveFile binaryUri, binaryPath, (err, res, body) ->
                                console.log err if err?

                                # Rebuild FS Tree to correct utime
                                buildFsTree deviceName, { filePath: path.join doc.path, doc.name }, callback
                else
                    callback()
            , callback


putDirectory = (directoryPath, args, callback) ->
    # Fix callback
    if not callback? or typeof callback is 'object'
        callback = (err) ->
            process.exit 1 if err?
            process.exit 0

    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    # Get dir name
    dirName = path.basename directoryPath
    if dirName is '.'
        return callback()

    # Find directory's parent directory
    absolutePath = path.resolve directoryPath
    relativePath = absolutePath.replace remoteConfig.path, ''
    if relativePath is absolutePath
        log.error "Directory is not located on the synchronized directory: #{absolutePath}"
        return callback()
    if relativePath.split('/').length > 2
        dirPath = relativePath.replace "/#{dirName}", ''
    else
        dirPath = ''

    # Get size and modification time
    stats = fs.statSync(absolutePath)
    dirLastModification = stats.mtime

    # Lookup for existing directory
    db.query { map: (doc) -> emit doc._id, doc if doc.docType is 'Folder' }, (err, res) ->
        for doc in res.rows
            doc = doc.value
            if doc.path is dirPath and doc.name is dirName
                if args.recursive?
                    return putSubFiles callback
                else
                    log.info "Directory already exists: #{doc.path}/#{doc.name}"
                    return callback err, res

        log.info "Creating directory doc: #{dirPath}/#{dirName}"
        newId = uuid.v4().split('-').join('')
        document =
            creationDate: dirLastModification
            docType: 'Folder'
            lastModification: dirLastModification
            name: dirName
            path: dirPath
            tags: []

        db.put document, newId, (err, res) ->
            if args.recursive?
                return putSubFiles callback
            else
                return callback err, res

    putSubFiles = (callback) ->
        # List files in directory
        fs.readdir absolutePath, (err, res) ->
            for file in res
                fileName = "#{absolutePath}/#{file}"
                # Upload file if it is a file
                if fs.lstatSync(fileName).isFile()
                    return putFile deviceName, fileName, callback
                # Upload directory recursively if it is a directory
                else if fs.lstatSync(fileName).isDirectory()
                    return putDirectory fileName, { deviceName: deviceName, recursive: true }, callback
            if res.length is 0
                log.info "No file to upload in: #{relativePath}"
                return callback err, res


putFile = (filePath, args, callback) ->
    # Fix callback
    if not callback? or typeof callback is 'object'
        callback = (err) ->
            process.exit 1 if err?
            process.exit 0

    # Get config
    remoteConfig = config.getConfig()
    deviceName = args.deviceName or config.getDeviceName()

    # Initialize remote HTTP client
    client = request.newClient remoteConfig.url
    client.setBasicAuth deviceName, remoteConfig.devicePassword

    # Get file name
    fileName = path.basename filePath

    # Find file's parent directory
    absolutePath = path.resolve filePath
    relativePath = absolutePath.replace remoteConfig.path, ''
    if relativePath is absolutePath
        log.error "File is not located on the synchronized directory: #{filePath}"
        return callback(true)
    if relativePath.split('/').length > 2
        filePath = relativePath.replace "/#{fileName}", ''
    else
        filePath = ''

    # Lookup MIME type
    fileMimeType = mime.lookup absolutePath

    # Get size and modification time
    stats = fs.statSync absolutePath
    fileLastModification = stats.mtime
    fileSize = stats.size

    # Ensure that directory exists
    putDirectory path.join(remoteConfig.path, filePath), { deviceName: deviceName }, (err, res) ->

        replication.addFilter('File').then () ->
            db.query 'file/all', (err, res) ->

        # Fetch only files with the same path/filename
        db.query { map: (doc) -> emit doc._id, doc if doc.docType is 'File' }, (err, res) ->
            for doc in res.rows
                doc = doc.value
                if doc.name is fileName and doc.path is filePath
                    existingFileId    = doc._id
                    existingFileRev   = doc._rev
                    existingFileTags  = doc.tags
                    existingFileCrea  = doc.creationDate
                    existingBinaryId  = doc.binary.file.id
                    if new Date(doc.lastModification) >= new Date(fileLastModification)
                        log.info "Unchanged file: #{doc.path}/#{doc.name}"
                        return callback err, res

            if existingBinaryId?
                # Fetch last revision from remote
                client.get "cozy/#{existingBinaryId}", (err, res, body) ->
                    if res.statusCode isnt 200
                        log.error "#{body.error}: #{body.reason}"
                    else
                        return uploadBinary body._id, body._rev, absolutePath, callback
            else
                # Fetch last revision from remote
                # Create the doc and get revision
                newBinaryId = uuid.v4().split('-').join('')
                client.put "cozy/#{newBinaryId}", { docType: 'Binary' }, (err, res, body) ->
                    if res.statusCode isnt 201
                        log.error "#{body.error}: #{body.reason}"
                    else
                        return uploadBinary body.id, body.rev, absolutePath, callback

            uploadBinary = (id, rev, absolutePath, callback) ->
                log.info "Uploading binary: #{relativePath}"
                client.putFile "cozy/#{id}/file?rev=#{rev}", absolutePath, {}, (err, res, body) ->
                    if res.statusCode isnt 201
                        log.error "#{body.error}: #{body.reason}"
                    else
                        body = JSON.parse body
                        binaryDoc =
                            docType: 'Binary'
                            path: absolutePath
                        log.info "Updating binary doc: #{absolutePath}"
                        db.put binaryDoc, body.id, body.rev, (err, res) ->
                            return putFileDoc existingFileId, existingFileRev, body.id, body.rev, callback

            putFileDoc = (id, rev, binaryId, binaryRev, callback) ->
                doc =
                    binary:
                        file:
                            id: binaryId
                            rev: binaryRev
                    class: 'document'
                    docType: 'File'
                    lastModification: fileLastModification
                    mime: fileMimeType
                    name: fileName
                    path: filePath
                    size: fileSize

                if id?
                    doc.creationDate = existingFileCrea
                    doc.tags = existingFileTags
                    log.info "Updating file doc: #{relativePath}"
                    db.put doc, id, rev, (err, res) ->
                        if err
                            console.log err
                        return callback()

                else
                    doc.creationDate = fileLastModification
                    doc.tags = []
                    newId = uuid.v4().split('-').join('')
                    log.info "Creating file doc: #{relativePath}"
                    db.put doc, newId, (err, res) ->
                        if err
                            console.log err
                        return callback()


addFilter = ->
        db.queryAsync('file/all')
        .then (res) ->
            console.log 'dude'
        .finally () ->
            console.log 'ok'

displayConfig = ->
    console.log JSON.stringify config.config, null, 2


program
    .command('add-filter')
    .description('Configure current device to sync with given cozy')
    .action addFilter

program
    .command('add-remote-cozy <url> <devicename> <syncPath>')
    .description('Configure current device to sync with given cozy')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .action addRemote

program
    .command('remove-remote-cozy')
    .description('Unsync current device with its remote cozy')
    .action removeRemote

program
    .command('replicate-from-remote')
    .description('Replicate remote files/folders to local DB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .action replicateFromRemote

program
    .command('replicate-to-remote')
    .description('Replicate local files/folders to remote DB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .action replicateToRemote

program
    .command('build-tree')
    .description('Create empty files and directories in the filesystem')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-f, --filePath [filePath]', 'specify file to build FS tree')
    .action (args) ->
        filesystem.buildTree args.filePath, () ->

program
    .command('fetch-binary')
    .description('Replicate DB binaries')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-f, --filePath [filePath]', 'specify file to fetch associated binary')
    .action (args) ->
        if args.filePath?
            binary.fetchOne args.deviceName, args.filePath, () ->
        else
            binary.fetchAll args.deviceName, () ->

program
    .command('put-file <filePath>')
    .description('Add file descriptor to PouchDB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .action putFile

program
    .command('put-dir <dirPath>')
    .description('Add folder descriptor to PouchDB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-r, --recursive', 'add every file/folder inside')
    .action putDirectory

program
    .command('watch-local')
    .description('Watch changes on the FS')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-c, --catchup', 'catchup local changes')
    .action watchLocalChanges

program
    .command('watch-remote')
    .description('Watch changes on the remote DB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-b, --binary', 'automatically fetch binaries')
    .action watchRemoteChanges

program
    .command('sync')
    .description('Watch changes on the remote DB')
    .option('-d, --deviceName [deviceName]', 'device name to deal with')
    .option('-b, --binary', 'automatically fetch binaries')
    .option('-c, --catchup', 'catchup local changes')
    .action runSync

program
    .command('display-config')
    .description('Display device configuration and exit')
    .action displayConfig

program
    .command("*")
    .description("Display help message for an unknown command.")
    .action ->
        console.log 'Unknown command, run "cozy-monitor --help"' + \
        ' to know the list of available commands.'

program.parse process.argv
