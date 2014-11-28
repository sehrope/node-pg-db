async = require 'async'
{assert, expect} = require 'chai'
db = require(if process.env.COVERAGE then '../lib-cov' else '../lib')()

###
Returns the current transaction in from the database.
###
getTransactionId = (cb) ->
  db.queryOne 'SELECT txid_current() AS tx', (err, row) ->
    if err then return cb(err)
    return cb(null, row.tx)

###
Same as getTransactionId(...) but with a 100 ms delay (server side).
###
slowGetTransactionId = (cb) ->
  db.queryOne 'SELECT txid_current() AS tx FROM pg_sleep(.1)', (err, row) ->
    if err then return cb(err)
    return cb(null, row.tx)

###
Same as getTransactionId(...) but with a 100 ms delay (client side).
###
fakeSlowGetTransactionId = (cb) -> setTimeout getTransactionId, 100, cb

syncError = (cb) -> throw new Error('Fake uncaught error')
asyncError = (cb) -> cb(new Error('Fake async error'))
noop = (cb) -> process.nextTick cb, null

createAndClearTestTable = (cb) ->
  async.series [
    (cb) -> db.update 'CREATE TABLE IF NOT EXISTS pg_db_test (x text)', cb
    (cb) -> db.update 'DELETE FROM pg_db_test', cb
  ], cb

describe 'db.tx', () ->
  it 'should not have _tx defined on the domain after the transaction completes', (done) ->
    db.tx noop, (err) ->
      expect(err).to.be.not.ok()
      expect(process.domain?._tx).to.be.not.ok()
      done()

  it 'should have _tx defined on the domain during the transaction', (done) ->
    db.tx (cb) ->
      expect(process.domain._tx).to.be.ok()
      cb()
    , (err) ->
      expect(err).to.be.not.ok()
      done()

  it 'should revert to the prior active domain on completion', (done) ->
    d = require('domain').create()
    d.foo = 'foobar'
    checkStillInDomain = () ->
      expect(process.domain?.foo).to.be.equal('foobar')
    d.run () ->
      checkStillInDomain()
      db.tx noop, (err) ->
        checkStillInDomain()
        done()

  it 'should propagate uncaught errors if there is an active domain', (done) ->
    d = require('domain').create()
    d.on 'error', (err) ->
      done()
    d.run () ->
      db.tx syncError, (err) ->
        done(new Error('domain error was not propagated'))

  it 'should handle uncaught errors when there is no active domain', (done) ->
    db.tx syncError, (err) ->
      expect(err).to.be.not.null
      done()

  it 'should return different transaction ids for separate transactions', (done) ->
    async.parallel [
      (cb) -> db.tx getTransactionId, cb
      (cb) -> db.tx slowGetTransactionId, cb
      (cb) -> db.tx getTransactionId, cb
      (cb) -> db.tx fakeSlowGetTransactionId, cb
      (cb) -> db.tx getTransactionId, cb
    ], (err, results) ->
      expect(err).to.be.not.ok()
      expect(results).to.be.a('array')
      expect(results.length).to.be.equal(5)
      txIds = {}
      for txId in results
        expect(txId of txIds).to.be.false()
      done()

describe 'db.tx.series', () ->
  it 'should return the same transaction id for multiple statements', (done) ->
    db.tx.series [
      getTransactionId
      slowGetTransactionId
      fakeSlowGetTransactionId
      slowGetTransactionId
      getTransactionId
    ], (err, results) ->
      expect(err).to.be.null()
      expect(results).to.be.a('array')
      expect(results.length).to.be.equal(5)
      txId = results[0]
      # NOTE: node-postgres returns bigint as a string:
      expect(txId).to.be.a('string')
      for result in results
        expect(result).to.be.equal(txId)
      done()

describe 'db.tx.parallel', () ->
  it 'should return the same transaction id for multiple statements', (done) ->
    db.tx.parallel [
      getTransactionId
      slowGetTransactionId
      fakeSlowGetTransactionId
      slowGetTransactionId
      getTransactionId
    ], (err, results) ->
      expect(err).to.be.null()
      expect(results).to.be.a('array')
      expect(results.length).to.be.equal(5)
      txId = results[0]
      # NOTE: node-postgres returns bigint as a string:
      expect(txId).to.be.a('string')
      for result in results
        expect(result).to.be.equal(txId)
      done()

describe 'db.tx.auto', () ->
  it 'should return the same transaction id for multiple statements', (done) ->
    db.tx.auto
      foo: getTransactionId
      bar: slowGetTransactionId
      baz: ['foo', 'bar', fakeSlowGetTransactionId]
      bam: ['baz', fakeSlowGetTransactionId]
    , (err, results) ->
      expect(err).to.be.null()
      expect(results).to.be.a('object')
      txId = results.foo
      expect(results).to.deep.equals
        foo: txId
        bar: txId
        baz: txId
        bam: txId
      done()

describe 'db.tx.queryOne', () ->
  it 'should return an error when no transaction exists', (done) ->
    db.tx.queryOne 'SELECT 1 AS x', (err, row) ->
      expect(err).to.be.ok()
      done()

  it 'should not return an error when a transaction exists', (done) ->
    db.tx (cb) ->
      db.tx.queryOne 'SELECT 1 AS x', (err, row) ->
        expect(err).to.be.not.ok()  
        expect(row).to.be.ok()
        expect(row.x).to.be.equal(1)
        cb(null)
    , done

describe 'db.tx.query', () ->
  it 'should return an error when no transaction exists', (done) ->
    db.tx.query 'SELECT 1 AS x', (err, rows) ->
      expect(err).to.be.ok()
      done()

  it 'should not return an error when a transaction exists', (done) ->
    db.tx (cb) ->
      db.tx.query 'SELECT 1 AS x', (err, rows) ->
        expect(err).to.be.not.ok()  
        expect(rows).to.be.ok()
        expect(rows.length).to.be.equal(1)
        cb(null)
    , done

describe 'db.tx.update', () ->
  it 'should return an error when no transaction exists', (done) ->
    db.tx.update 'CREATE TABLE IF NOT EXISTS pg_db_test (x text)', (err, rowCount) ->
      expect(err).to.be.ok()
      done()

  it 'should not return an error when a transaction exists', (done) ->
    db.tx (cb) ->
      db.tx.update 'CREATE TABLE IF NOT EXISTS pg_db_test (x text)', (err, rowCount) ->
        expect(err).to.be.not.ok()
        cb(null)
    , done

describe 'db.tx', () ->
  it 'should COMMIT transaction that succeed', (done) ->
    createAndClearTestTable (err) ->
      expect(err).to.be.not.ok()
      db.tx.series [
        (cb) -> db.queryOne 'SELECT 1', cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test1')", cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test2')", cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test3')", cb
      ], (err) ->
        expect(err).to.be.not.ok()
        db.queryOne 'SELECT COUNT(*)::int AS count FROM pg_db_test', (err, row) ->
          expect(err).to.be.not.ok()
          expect(row.count).to.be.equal(3)
          done()

  it 'should ROLLBACK transaction that fail', (done) ->
    createAndClearTestTable (err) ->
      expect(err).to.be.not.ok()
      db.tx.series [
        (cb) -> db.queryOne 'SELECT 1', cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test1')", cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test2')", cb
        (cb) -> db.update "INSERT INTO pg_db_test (x) VALUES ('test3')", cb
        (cb) -> db.update 'SOME BAD SQL', cb
      ], (err) ->
        expect(err).to.be.ok()
        db.queryOne 'SELECT COUNT(*)::int AS count FROM pg_db_test', (err, row) ->
          expect(err).to.be.not.ok()
          expect(row.count).to.be.equal(0)
          done()
