async  = require 'async'
should = require 'should'

Pouch  = require '../../backend/pouch'

configHelpers = require '../helpers/config'
pouchHelpers  = require '../helpers/pouch'


describe "Pouch", ->

    before 'instanciate config', configHelpers.createConfig
    before 'instanciate pouch', pouchHelpers.createDatabase
    after 'clean pouch', pouchHelpers.cleanDatabase
    after 'clean config directory', configHelpers.cleanConfig

    createBinary = (pouch, i, callback) ->
        doc =
            _id: "binary-#{i}"
            docType: 'Binary'
            path: '/full/path'
            checksum: "123#{i}"
        pouch.db.put doc, callback

    createFile = (pouch, i, callback) ->
        doc =
            _id: "file-#{i}"
            docType: 'File'
            path: 'myfolder'
            name: "filename-#{i}"
            tags: []
            binary:
                file:
                    id: "binary-#{i}"
        pouch.db.put doc, callback

    createFolder = (pouch, i, callback) ->
        doc =
            _id: "folder-#{i}"
            docType: 'Folder'
            path: 'myfolder'
            name: "folder-#{i}"
            tags: []
        pouch.db.put doc, callback

    before (done) ->
        async.eachSeries [1..3], (i, callback) =>
            createBinary @pouch, i, =>
                createFile @pouch, i, =>
                    createFolder @pouch, i, callback
        , done

    describe 'Filters / Views', ->

        describe 'removeFilter', ->
            it 'removes given view', (done) ->
                @pouch.folders().all (err, res) =>
                    should.not.exist err
                    @pouch.removeFilter "folder", (err) =>
                        should.not.exist err
                        @pouch.folders().all (err, res) ->
                            should.exist err
                            done()

        describe 'createDesignDoc', ->
            it "creates a new design doc", (done) ->
                id = "_design/folder"
                queries =
                    all: """
                function (doc) {
                    if (doc.docType !== undefined
                        && doc.docType.toLowerCase() === "folder") {
                        emit(doc._id, doc);
                    }
                }
                """
                @pouch.removeFilter "folder", (err) =>
                    @pouch.createDesignDoc id, queries, =>
                        @pouch.folders().all (err, res) ->
                            should.not.exist err
                            res.rows.length.should.be.equal 3
                            done()

        describe 'addFilter', ->
            it "creates all views", (done) ->
                @pouch.removeFilter "folder", (err) =>
                    @pouch.addFilter "folder", (err) =>
                        should.not.exist err
                        @pouch.folders().all (err, res) =>
                            should.not.exist err
                            @pouch.files().all (err, res) =>
                                should.not.exist err
                                @pouch.binaries().all (err, res) ->
                                    should.not.exist err
                                    done()


    describe 'ODM', ->
        describe 'newId', ->
            it "returns a complex alpha-numeric chain", ->
                Pouch.newId().length.should.equal 32

        describe 'getByKey', ->
            it 'returns document corresponding to key for given view', ->
                @pouch.getByKey 'byChecksum', null, (err, docs) ->
                    should.not.exist err
                    docs.length.should.equal 0

        describe 'files', ->
            describe 'all', ->
                it 'gets all the file documents', (done) ->
                    @pouch.files().all (err, res) ->
                        should.not.exist err
                        res.total_rows.should.be.equal 3
                        for i in [1..3]
                            fields =
                                docType: 'File'
                                path: 'myfolder'
                                name: "filename-#{i}"
                                tags: []
                                binary:
                                    file:
                                        id: "binary-#{i}"
                            res.rows[i-1].value.should.have.properties fields
                        done()

            describe 'get', ->
                it 'gets a file document by its fullpath', (done) ->
                    @pouch.files().get 'myfolder/filename-1', (err, res) ->
                        should.not.exist err
                        fields =
                            docType: 'File'
                            path: 'myfolder'
                            name: "filename-1"
                            tags: []
                            binary:
                                file:
                                    id: "binary-1"
                        res.should.have.properties fields
                        done()

            describe 'createNew', ->
                it 'creates a file document', (done) ->
                    fields =
                        path: ''
                        name: 'file-04'
                        tags: []
                    @pouch.files().createNew fields, (err, res) =>
                        should.not.exist err
                        @pouch.db.get res.id, (err, doc) ->
                            should.not.exist err
                            doc.should.have.properties fields
                            doc.docType.toLowerCase().should.be.equal 'file'
                            done()

        describe 'folders', ->
            describe 'all', ->
                it 'gets all the folder documents', (done) ->
                    @pouch.folders().all (err, res) ->
                        should.not.exist err
                        res.total_rows.should.be.equal 3
                        for i in [1..3]
                            fields =
                                docType: 'Folder'
                                path: 'myfolder'
                                name: "folder-#{i}"
                                tags: []
                            res.rows[i-1].value.should.have.properties fields
                        done()

            describe 'get', ->
                it 'gets a folder document by its fullpath', ->
                    @pouch.folders().get 'myfolder/folder-1', (err, res) ->
                        should.not.exist err
                        fields =
                            docType: 'Folder'
                            path: 'myfolder'
                            name: "folder-1"
                            tags: []
                        res.should.have.properties fields
                        done()

            describe 'createNew', ->
                it 'creates a folder document', (done) ->
                    fields =
                        path: 'myfolder'
                        name: 'folder-4'
                        tags: []
                    @pouch.folders().createNew fields, (err, res) =>
                        should.not.exist err
                        @pouch.db.get res.id, (err, doc) ->
                            should.not.exist err
                            doc.should.have.properties fields
                            doc.docType.toLowerCase().should.be.equal 'folder'

                            done()

        describe 'binaries', ->
            describe 'all', ->
                it 'gets all the binary documents', (done) ->
                    @pouch.binaries().all (err, res) ->
                        should.not.exist err
                        res.total_rows.should.be.equal 3
                        for i in [1..3]
                            fields =
                                docType: 'Binary'
                                path: '/full/path'
                                checksum: "123#{i}"
                            res.rows[i-1].value.should.have.properties fields
                        done()

            describe 'get', ->
                it 'gets a binary document by its checksum', (done) ->
                    @pouch.binaries().get '1231', (err, res) ->
                        should.not.exist err
                        fields =
                            docType: 'Binary'
                            path: '/full/path'
                            checksum: "1231"
                        res.should.have.properties fields
                        done()

    describe 'helpers', ->
        describe 'removeIfExists', ->
            it 'removes element with given id', (done) ->
                @pouch.db.get 'folder-3', (err) =>
                    should.not.exist err
                    @pouch.removeIfExists 'folder-3', (err) =>
                        should.not.exist err
                        @pouch.db.get 'folder-3', (err) ->
                            should.exist err
                            done()

            it 'doesnt return an error when the doc is not there', (done) ->
                @pouch.removeIfExists 'folder-3', (err) =>
                    @pouch.removeIfExists 'folder-3', (err) =>
                        should.not.exist err
                        @pouch.db.get 'folder-3', (err) ->
                            should.exist err
                            done()

        describe 'getPreviousRev', ->
            it "retrieves previous document's information", (done) ->
                # Get revision and remove document
                @pouch.db.get 'folder-1', (err, doc) =>
                    should.not.exist err
                    @pouch.db.remove 'folder-1', doc._rev, (err, res) =>
                        should.not.exist err
                        # Retrieve deleted document information
                        @pouch.getPreviousRev 'folder-1', (err, doc) ->
                            should.not.exist err
                            fields =
                                path: 'myfolder'
                                name: 'folder-1'
                                tags: []
                            doc.should.have.properties fields
                            done()

        describe 'getKnownPath', ->
            it 'retrieves the "last known" full path of a file', (done) ->
                @pouch.db.get 'file-1', (err, doc) =>
                    should.not.exist err
                    @pouch.getKnownPath doc, (err, path) ->
                        should.not.exist err
                        path.should.be.equal '/full/path'
                        done()

        describe 'markAsDeleted', ->
            it 'deletes the document but keeps docType and binary', (done) ->
                @pouch.db.get 'file-2', (err, doc) =>
                    should.not.exist err
                    @pouch.markAsDeleted doc, (err, res) =>
                        should.not.exist err
                        options =
                            revs: true
                            revs_info: true
                            open_revs: "all"
                        @pouch.db.get 'file-2', options, (err, infos) ->
                            should.exist infos[0].ok
                            fields =
                                binary: file: id: 'binary-2'
                                docType: 'File'
                            infos[0].ok.should.have.properties fields
                            done()

        describe 'storeLocalRev', ->
            it "stores a document under 'localrev' doctype", (done) ->
                @pouch.storeLocalRev '1-dff69', (err, res) =>
                    query = 'localrev/byRevision'
                    @pouch.db.query query, key: '1-dff69', (err, res) ->
                        should.not.exist err
                        should.exist res.rows
                        res.rows.length.should.not.be.equal 0
                        done()
