async = require 'async'
{assert, expect} = require 'chai'
libPath = if process.env.COVERAGE then '../lib-cov' else '../lib'

describe 'db', () ->
  it 'should invoke execute callback when a query is executed', (done) ->
    db = require(libPath)()
    wasCalled = false
    db.on 'execute', (data) ->
      wasCalled = true
    db.query 'SELECT 1', (err, row) ->
      expect(err).to.be.not.ok()
      expect(wasCalled).to.be.true()
      done()

  it 'should invoke executeComplete callback when a query is executed', (done) ->
    db = require(libPath)()
    wasCalled = false
    db.on 'executeComplete', (data) ->
      wasCalled = true
    db.query 'SELECT 1', (err, row) ->
      expect(err).to.be.not.ok()
      expect(wasCalled).to.be.true()
      done()

describe 'db.tx', () ->
  it 'should invoke onSuccess callback when a transaction completes successfully', (done) ->
    db = require(libPath)()
    successCalled = false
    failureCalled = false
    db.tx.series [
      (cb) ->
        db.tx.onSuccess () ->
          successCalled = true
        db.tx.onFailure () ->
          failureCalled = true
        cb()
    ], (err) ->
      expect(err).to.be.not.ok()
      expect(successCalled, 'successCalled').to.be.true()
      expect(failureCalled, 'failureCalled').to.be.false()
      done()

  it 'should invoke onFailure callback when a transaction completes unsuccessfully', (done) ->
    db = require(libPath)()
    successCalled = false
    failureCalled = false
    db.tx.series [
      (cb) ->
        db.tx.onSuccess () ->
          successCalled = true
        db.tx.onFailure () ->
          failureCalled = true
        cb()
      (cb) -> db.query 'BAD SQL', cb
    ], (err) ->
      expect(err).to.be.ok()
      expect(successCalled).to.be.false()
      expect(failureCalled).to.be.true()
      done()

  it 'should normalize onSuccess callbacks', (done) ->
    db = require(libPath)()
    counter = 0
    db.tx.series [
      (cb) ->
        db.tx.onSuccess () ->
          # Sync callback (should be normalized)
          counter++
        db.tx.onSuccess () ->
          # Sync callback (should be normalized)
          counter++
          throw new Error('Fake sync error')
        db.tx.onSuccess (cb) ->
          # Async callback (will not be normalized)
          counter++
          cb()
        db.tx.onSuccess (cb) ->
          # Async callback (will not be normalized)
          counter++
          cb(new Error('Fake async error'))
        db.tx.onSuccess (cb) ->
          # Async callback (will not be normalized)
          counter++
          throw new Error('Fake sync error in async function')
          cb()
        cb()
    ], (err) ->
      expect(err).to.be.not.ok()
      expect(counter).to.be.equal(5)
      done()

describe 'db.tx.onSuccess', () ->
  it 'should return an error when no transaction exists', (done) ->
    db = require(libPath)()
    try
      db.tx.onSuccess () ->
      done(new Error())
    catch e
      done()

  it 'should return an error when cb is not a function', (done) ->
    db = require(libPath)()
    db.tx (cb) ->
      db.tx.onSuccess 'not a function'
      cb()
    , (err) ->
      expect(err).to.be.ok()
      done()

describe 'db.tx.onFailure', () ->
  it 'should return an error when no transaction exists', (done) ->
    db = require(libPath)()
    try
      db.tx.onFailure () ->
      done(new Error())
    catch e
      done()

  it 'should return an error when cb is not a function', (done) ->
    db = require(libPath)()
    db.tx (cb) ->
      db.tx.onFailure 'not a function'
      cb()
    , (err) ->
      expect(err).to.be.ok()
      done()

describe 'db.on', () ->
  it 'should return an error when event name is invalid', (done) ->
    db = require(libPath)()
    db.tx (cb) ->
      db.on 'invalid event name', () ->
      cb()
    , (err) ->
      expect(err).to.be.ok()
      done()

  it 'should return an error when callback is invalid', (done) ->
    db = require(libPath)()
    db.tx (cb) ->
      db.on 'execute', 'not a function'
      cb()
    , (err) ->
      expect(err).to.be.ok()
      done()

describe 'db.emit', () ->
  it 'should return an error when event name is invalid', (done) ->
    db = require(libPath)()
    try
      db.emit 'foobar'
      done(new Error())
    catch ignore
      done()
