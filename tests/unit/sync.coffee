async  = require 'async'
sinon  = require 'sinon'
should = require 'should'

Sync = require '../../backend/sync'


configHelpers = require '../helpers/config'
pouchHelpers  = require '../helpers/pouch'


describe "Sync", ->

    before 'instanciate config', configHelpers.createConfig
    before 'instanciate events', configHelpers.createEvents
    before 'instanciate pouch', pouchHelpers.createDatabase
    after 'clean pouch', pouchHelpers.cleanDatabase
    after 'clean config directory', configHelpers.cleanConfig

    describe 'start', ->
        beforeEach 'instanciate sync', ->
            @local  = start: sinon.stub().yields()
            @remote = start: sinon.stub().yields()
            @sync = new Sync @config, @pouch, @local, @remote, @events
            @sync.sync = sinon.stub().yields 'stopped'

        it 'starts the metadata replication of remote in readonly', (done) ->
            @sync.start 'readonly', (err) =>
                err.should.equal 'stopped'
                @local.start.called.should.be.false()
                @remote.start.calledOnce.should.be.true()
                @sync.sync.calledOnce.should.be.true()
                done()

        it 'starts the metadata replication of local in writeonly', (done) ->
            @sync.start 'writeonly', (err) =>
                err.should.equal 'stopped'
                @local.start.calledOnce.should.be.true()
                @remote.start.called.should.be.false()
                @sync.sync.calledOnce.should.be.true()
                done()

        it 'starts the metadata replication of both in full', (done) ->
            @sync.start 'full', (err) =>
                err.should.equal 'stopped'
                @local.start.calledOnce.should.be.true()
                @remote.start.calledOnce.should.be.true()
                @sync.sync.calledOnce.should.be.true()
                done()

        it 'does not start sync if metadata replication fails', (done) ->
            @local.start = sinon.stub().yields 'failed'
            @sync.start 'full', (err) =>
                err.should.equal 'failed'
                @local.start.calledOnce.should.be.true()
                @remote.start.called.should.be.false()
                @sync.sync.calledOnce.should.be.false()
                done()

    describe 'sync', ->
        beforeEach ->
            @local = {}
            @remote = {}
            @sync = new Sync @config, @pouch, @local, @remote
            @sync.apply = sinon.stub().yields()

        it 'calls pop and apply', (done) ->
            @sync.pop = sinon.stub().yields null, { change: true }
            @sync.sync (err) =>
                should.not.exist err
                @sync.pop.calledOnce.should.be.true()
                @sync.apply.calledOnce.should.be.true()
                @sync.apply.calledWith(change: true).should.be.true()
                done()

        it 'calls pop but not apply if pop has failed', (done) ->
            @sync.pop = sinon.stub().yields 'failed'
            @sync.sync (err) =>
                err.should.equal 'failed'
                @sync.pop.calledOnce.should.be.true()
                @sync.apply.calledOnce.should.be.false()
                done()

    describe 'pop', ->
        beforeEach ->
            @local = {}
            @remote = {}
            @sync = new Sync @config, @pouch, @local, @remote
            @pouch.db.changes().on 'complete', (info) =>
                @config.setLocalSeq info.last_seq

        it 'gives the next change if there is already one', (done) ->
            pouchHelpers.createFile @pouch, 1, (err) =>
                should.not.exist err
                @sync.pop (err, change) =>
                    should.not.exist err
                    change.should.have.properties
                        id: 'file-1'
                        seq: @config.getLocalSeq() + 1
                    change.doc.should.have.properties
                        docType: 'file'
                        path: 'myfolder'
                        name: "filename-1"
                        tags: []
                        binary:
                            file:
                                id: "binary-1"
                    done()

        it 'gives only one change', (done) ->
            async.eachSeries [2..5], (i, callback) =>
                pouchHelpers.createFile @pouch, i, callback
            , (err) =>
                should.not.exist err
                spy = sinon.spy()
                @sync.pop spy
                setTimeout ->
                    spy.calledOnce.should.be.true()
                    done()
                , 10

        it 'waits for the next change if there no available change', (done) ->
            spy = sinon.spy()
            @sync.pop (err, change) =>
                spy()
                should.not.exist err
                change.should.have.properties
                    id: 'file-6'
                    seq: @config.getLocalSeq() + 1
                change.doc.should.have.properties
                    docType: 'file'
                    path: 'myfolder'
                    name: "filename-6"
                    tags: []
                    binary:
                        file:
                            id: "binary-6"
                done()
            setTimeout =>
                spy.called.should.be.false()
                pouchHelpers.createFile @pouch, 6, (err) ->
                    should.not.exist err
            , 10

    describe 'isSpecial', ->
        beforeEach ->
            @local = {}
            @remote = {}
            @sync = new Sync @config, @pouch, @local, @remote

        it 'returns true for a design document', (done) ->
            @pouch.db.get '_design/file', (err, doc) =>
                should.not.exist err
                @sync.isSpecial(doc).should.be.true()
                done()

        it 'returns false for a normal document', (done) ->
            pouchHelpers.createFile @pouch, 7, (err) =>
                should.not.exist err
                @pouch.db.get 'file-7', (err, doc) =>
                    should.not.exist err
                    @sync.isSpecial(doc).should.be.false()
                done()

    describe 'apply', ->
        it 'TODO'
