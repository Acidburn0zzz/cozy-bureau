/* @flow */

const {
  after,
  afterEach,
  before,
  beforeEach,
  suite,
  test
} = require('mocha')
const should = require('should')

const metadata = require('../../core/metadata')

const Builders = require('../support/builders')
const configHelpers = require('../support/helpers/config')
const cozyHelpers = require('../support/helpers/cozy')
const pouchHelpers = require('../support/helpers/pouch')
const { IntegrationTestHelpers } = require('../support/helpers/integration')

suite('Platform incompatibilities', () => {
  if (process.platform !== 'win32' && process.platform !== 'darwin') {
    test.skip(`is not tested on ${process.platform}`, () => {})
    return
  }

  let builders, cozy, helpers

  before(configHelpers.createConfig)
  before(configHelpers.registerClient)
  beforeEach(pouchHelpers.createDatabase)
  beforeEach(cozyHelpers.deleteAll)

  afterEach(() => helpers.local.clean())
  afterEach(pouchHelpers.cleanDatabase)
  after(configHelpers.cleanConfig)

  beforeEach(async function () {
    cozy = cozyHelpers.cozy
    builders = new Builders(cozy, this.pouch)
    helpers = new IntegrationTestHelpers(this.config, this.pouch, cozy)

    await helpers.local.setupTrash()
    await helpers.remote.ignorePreviousChanges()
  })

  test('add incompatible dir and file', async () => {
    await builders.remote.dir().named('di:r').create()
    await builders.remote.file().named('fi:le').create()
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'di:r/',
      'fi:le'
    ])
  })
  test('add incompatible dir with two colons', async () => {
    await builders.remote.dir().named('d:i:r').create()
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'd:i:r/'
    ])
  })
  test('add compatible dir with some incompatible content', async () => {
    await helpers.remote.createTree([
      'dir/',
      'dir/file',
      'dir/fi:le',
      'dir/sub:dir/',
      'dir/sub:dir/file',
      'dir/subdir/',
      'dir/subdir/file'
    ])
    await helpers.pullAndSyncAll()

    should(await helpers.local.tree()).deepEqual([
      'dir/',
      'dir/file',
      'dir/subdir/',
      'dir/subdir/file'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir/fi:le',
      'dir/sub:dir/',
      'dir/sub:dir/file'
    ])
  })
  test('rename incompatible -> incompatible', async () => {
    await helpers.remote.createTree(['d:ir/', 'f:ile'])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesByPath('/d:ir', {name: 'di:r'})
    await cozy.files.updateAttributesByPath('/f:ile', {name: 'fi:le'})
    await helpers.pullAndSyncAll()

    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'di:r/',
      'fi:le'
    ])
  })
  test('trash & restore incompatible', async () => {
    const docs = await helpers.remote.createTree(['d:ir/', 'f:ile'])
    await helpers.pullAndSyncAll()

    await cozy.files.trashById(docs['d:ir/']._id)
    await cozy.files.trashById(docs['f:ile']._id)
    await helpers.pullAndSyncAll()

    should(await helpers.local.tree()).be.empty()
    should(await helpers.metadataTree()).be.empty()
    should(await helpers.incompatibleTree()).be.empty()

    await cozy.files.restoreById(docs['d:ir/']._id)
    await cozy.files.restoreById(docs['f:ile']._id)
    await helpers.pullAndSyncAll()

    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'd:ir/',
      'f:ile'
    ])
  })

  test('destroy & recreate incompatible', async () => {
    const docs = await helpers.remote.createTree(['d:ir/', 'f:ile'])
    await helpers.pullAndSyncAll()

    await cozy.files.trashById(docs['d:ir/']._id)
    await cozy.files.trashById(docs['f:ile']._id)
    await cozy.files.destroyById(docs['d:ir/']._id)
    await cozy.files.destroyById(docs['f:ile']._id)
    await helpers.pullAndSyncAll()

    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).be.empty()

    await helpers.remote.createTree(['d:ir/', 'f:ile'])
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'd:ir/',
      'f:ile'
    ])
  })

  test('make compatible bottom-up', async () => {
    const docs = await helpers.remote.createTree([
      'd:ir/',
      'd:ir/sub:dir/',
      'd:ir/sub:dir/f:ile',
      'd:ir/sub:dir/subsubdir/'
    ])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesById(docs['d:ir/sub:dir/f:ile']._id, {name: 'file'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).be.empty()
    should(await helpers.incompatibleTree()).deepEqual([
      'd:ir/',
      'd:ir/sub:dir/',
      'd:ir/sub:dir/file',
      'd:ir/sub:dir/subsubdir/'
    ])

    await cozy.files.updateAttributesById(docs['d:ir/']._id, {name: 'dir'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      'dir/'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir/sub:dir/',
      'dir/sub:dir/file',
      'dir/sub:dir/subsubdir/'
    ])

    await cozy.files.updateAttributesById(docs['d:ir/sub:dir/']._id, {name: 'subdir'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      'dir/',
      'dir/subdir/',
      'dir/subdir/file',
      'dir/subdir/subsubdir/'
    ])
    should(await helpers.incompatibleTree()).be.empty()
  })

  test('rename dir compatible -> incompatible', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/subdir/',
      'dir/subdir/file'
    ])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesById(docs['dir/']._id, {name: 'dir:'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      '/Trash/dir/',
      '/Trash/dir/subdir/',
      '/Trash/dir/subdir/file'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir:/',
      'dir:/subdir/',
      'dir:/subdir/file'
    ])
  })

  test('rename dir compatible -> incompatible with already incompatible content', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/sub:dir/',
      'dir/sub:dir/file'
    ])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesById(docs['dir/']._id, {name: 'dir:'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      '/Trash/dir/'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir:/',
      'dir:/sub:dir/',
      'dir:/sub:dir/file'
    ])
  })

  test('rename file compatible -> incompatible', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/file'
    ])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesById(docs['dir/file']._id, {name: 'fi:le'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      '/Trash/file',
      'dir/'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir/fi:le'
    ])
  })

  test('rename dir compatible -> compatible with incompatible content', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/fi:le',
      'dir/sub:dir/'
    ])
    await helpers.pullAndSyncAll()

    await cozy.files.updateAttributesById(docs['dir/']._id, {name: 'dir2'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      'dir2/'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir2/fi:le',
      'dir2/sub:dir/'
    ])
  })

  test('move local dir with incompatible metadata & remote content', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/sub:dir/',
      'dir/sub:dir/file'
    ])
    await helpers.pullAndSyncAll()

    // Simulate local move
    const dir = await helpers._pouch.byRemoteIdAsync(docs['dir/']._id)
    const stats = {mtime: new Date(), ctime: new Date(), ino: dir.ino}
    // $FlowFixMe
    const dir2 = metadata.buildDir('dir2', stats)
    await helpers.prep.moveFolderAsync('local', dir2, dir)
    await helpers.syncAll()

    should(await helpers.remote.tree()).deepEqual([
      '.cozy_trash/',
      'dir2/',
      'dir2/sub:dir/',
      'dir2/sub:dir/file'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'dir2/sub:dir/',
      'dir2/sub:dir/file'
    ])
  })

  test('rename dir compatible -> incompatible -> compatible with compatible content', async () => {
    const docs = await helpers.remote.createTree([
      'dir/',
      'dir/file'
    ])
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      'dir/',
      'dir/file'
    ])
    should(await helpers.incompatibleTree()).be.empty()

    await cozy.files.updateAttributesById(docs['dir/']._id, {name: 'd:ir'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      '/Trash/dir/',
      '/Trash/dir/file'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      'd:ir/',
      'd:ir/file'
    ])

    await cozy.files.updateAttributesById(docs['dir/']._id, {name: 'dir'})
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      // XXX: We don't restore from OS trash for now. Hence the copy.
      '/Trash/dir/',
      '/Trash/dir/file',
      'dir/',
      'dir/file'
    ])
    should(await helpers.incompatibleTree()).be.empty()
  })

  test('same dirs except case -> first is created, second is incompatible', async () => {
    await helpers.remote.createTree([
      'alfred/',
      'Alfred/'
    ])
    const incompatibleNames = []
    helpers.events.on('platform-incompatibilities', incompatibilities => {
      for (let i of incompatibilities) {
        incompatibleNames.push(i.name)
      }
    })
    await helpers.pullAndSyncAll()
    should(await helpers.local.tree()).deepEqual([
      // Fun fact: if alfred & Alfred were files, Alfred would have been created locally
      'alfred/'
    ])
    should(await helpers.incompatibleTree()).deepEqual([
      // Empty since alfred and Alfred have the same identity
    ])
    should(incompatibleNames).deepEqual([
      // FIXME: Never received
      'Alfred'
    ])
  })
})
