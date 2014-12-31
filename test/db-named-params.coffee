async = require 'async'
{assert, expect} = require 'chai'
libPath = if process.env.COVERAGE then '../lib-cov' else '../lib'
db = require(libPath)()

describe 'db.queryOne', () ->
  it 'should allow for named parameters', (done) ->
    db.queryOne 'SELECT :foo::text AS x', {foo: 'foobar'}, (err, row) ->
      expect(err).to.be.not.ok()
      expect(row.x).to.be.equal('foobar')
      done()

  it 'should allow for reusing named parameters', (done) ->
    db.queryOne 'SELECT :foo::text AS x, :foo::text AS y', {foo: 'foobar'}, (err, row) ->
      expect(err).to.be.not.ok()
      expect(row.x).to.be.equal('foobar')
      expect(row.y).to.be.equal('foobar')
      done()

  it 'should return an error when parameter values are missing', (done) ->
    db.queryOne 'SELECT :foo::text AS x, :bar::text AS y', {foo: 'foobar'}, (err, row) ->
      expect(err).to.be.ok()
      done()

  it 'should allow classic numbered parameters', (done) ->
    db.queryOne 'SELECT $1::text', ['test'], (err, row) ->
      expect(err).to.be.null()
      done()

describe 'db.update', () ->
  before (done) ->
    async.series [
      (cb) -> db.update 'CREATE TABLE IF NOT EXISTS test_db_update (x text)', cb
      (cb) -> db.update 'DELETE FROM test_db_update', cb
      (cb) -> db.update 'INSERT INTO test_db_update (x) VALUES (\'test\')', cb
    ], done

  it 'should allow for named parameters when used with literals', (done) ->
    sql =
      """
      UPDATE test_db_update
      SET x = :foo
      WHERE x = 'test'
      """
    db.update sql, {foo: 'foobar'}, (err, rowCount) ->
      expect(err).to.be.not.ok()
      expect(rowCount).to.be.equal(1)
      done()

  it 'should allow for named parameters when used with literals', (done) ->
    sql =
      """
      UPDATE test_db_update
      SET x = 'test'
      WHERE x = :foo
      """
    db.update sql, {foo: 'foobar'}, (err, rowCount) ->
      expect(err).to.be.not.ok()
      expect(rowCount).to.be.equal(1)
      done()
