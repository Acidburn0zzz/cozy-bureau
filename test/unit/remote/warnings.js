/* eslint-env mocha */
/* @flow */

const should = require('should')
const sinon = require('sinon')

const { Poller, POLLING_DELAY } = require('../../../core/remote/warnings')

const warningBuilders = require('../../support/builders/remote/warning')

describe('remote/warnings.Poller', () => {
  let clock, cozy, events, poller

  beforeEach(() => {
    clock = sinon.useFakeTimers()
    cozy = {settings: {warnings: sinon.stub().resolves([])}}
    events = {emit: sinon.spy()}
    // $FlowFixMe
    poller = new Poller(cozy, events)
  })

  afterEach(() => {
    clock.restore()
  })

  describe('#poll()', () => {
    it('emits warnings if any', async () => {
      const warnings = warningBuilders.list()
      cozy.settings.warnings.resolves(warnings)

      await poller.poll()

      should(events.emit).have.been.calledOnce()
      should(events.emit).have.been.calledWith('remoteWarnings', warnings)
    })

    it('emits nothing otherwise', async () => {
      await poller.poll()

      should(events.emit).not.have.been.called()
    })
  })

  describe('#start()', () => {
    it('polls continuously according to POLLING_DELAY', async () => {
      const warnings = warningBuilders.list()
      cozy.settings.warnings.onSecondCall().resolves(warnings)

      poller.start()
      clock.tick(POLLING_DELAY)
      await poller.currentPolling

      should(cozy.settings.warnings).have.been.calledTwice()
      should(events.emit).have.been.calledOnce()
      should(events.emit).have.been.calledWith('remoteWarnings', warnings)
    })
  })

  describe('#stop()', () => {
    beforeEach(async () => {
      poller.start()
      await poller.stop()
    })

    it('waits for current polling to complete if any', () => {
      should.not.exist(poller.currentPolling)
    })

    it('cancels upcoming pollings', () => {
      cozy.settings.warnings.onSecondCall().resolves(warningBuilders.list())
      clock.tick(POLLING_DELAY)
      should(cozy.settings.warnings).have.been.calledOnce()
      should(events.emit).not.have.been.called()
    })
  })
})
