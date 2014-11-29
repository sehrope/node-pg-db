async = require 'async'
{assert, expect} = require 'chai'
libPath = if process.env.COVERAGE then '../lib-cov' else '../lib'
db = require(libPath)()

describe 'db.execute', () ->
  it 'should return an error if the SQL is invalid', (done) ->
    db.execute 'BAD SQL GOES HERE', (err, result) ->
      expect(err).to.be.not.null()
      done()

  it 'should return the row for single row queries', (done) ->
    db.execute 'SELECT 1 AS x', (err, result) ->
      expect(err).to.be.null
      expect(result).to.be.not.null
      expect(result).to.be.a('object')
      expect(result.rows).to.be.a('array')
      done()

  it 'should return an error if the first parameter is null (i.e. not a string)', (done) ->
    db.execute null, (err, result) ->
      expect(err).to.be.ok()
      done()

  it 'should return an error if the first parameter is an object (i.e. not a string)', (done) ->
    db.execute {foo:'bar'}, (err, result) ->
      expect(err).to.be.ok()
      done()

describe 'db.queryOne', () ->
  it 'should return an error if the SQL is invalid', (done) ->
    db.queryOne 'BAD SQL GOES HERE', (err, row) ->
      expect(err).to.be.not.null()
      done()

  it 'should return the row for single row queries', (done) ->
    db.queryOne 'SELECT 1 AS x', (err, row) ->
      expect(err).to.be.null
      expect(row).to.be.not.null
      expect(row.x).to.equal(1)
      done()

  it 'should return null for empty results for single row queries', (done) ->
    db.queryOne 'SELECT 1 AS x WHERE false', (err, row) ->
      expect(err).to.be.null
      expect(row).to.be.null
      done()

  it 'should return an error for results with more than one row', (done) ->
    db.queryOne 'SELECT x FROM generate_series(1,10) x', (err, row) ->
      expect(err).to.be.not.null
      done()

describe 'db.query', () ->
  it 'should return an error if the SQL is invalid', (done) ->
    db.query 'BAD SQL GOES HERE', (err, row) ->
      expect(err).to.be.not.null()
      done()

  it 'should return an array of rows for multi row queries', (done) ->
    db.query 'SELECT x FROM generate_series(1,10) x', (err, rows) ->
      expect(err).to.be.null
      expect(rows).to.be.a('array')
      expect(rows.length).to.be.equal(10)
      expect(rows[0].x).to.be.equal(1)
      done()

  it 'should return an empty array for empty results for multi row queries', (done) ->
    db.query 'SELECT x FROM generate_series(1,10) x WHERE false', (err, rows) ->
      expect(err).to.be.null
      expect(rows).to.be.a('array')
      expect(rows.length).to.be.equal(0)
      done()

  it 'should return an empty array for empty results for multi row queries', (done) ->
    db.query 'SELECT x FROM generate_series(1,10) x WHERE false', (err, rows) ->
      expect(err).to.be.null
      expect(rows).to.be.a('array')
      expect(rows.length).to.be.equal(0)
      done()

describe 'db.update', () ->
  it 'should return an error if the SQL is invalid', (done) ->
    db.update 'BAD SQL GOES HERE', (err, rowCount) ->
      expect(err).to.be.not.null()
      done()

  it 'should return a row count for DML statements', (done) ->
    db.update 'CREATE TABLE IF NOT EXISTS pg_db_test (x text)', (err, rowCount) ->
      expect(err).to.be.null
      expect(rowCount).to.be.a('number')
      done()

describe 'create a new DB with a null DATABASE_URL', () ->
  it 'should should throw an Error', () ->
    tmp = process.env.DATABASE_URL
    process.env.DATABASE_URL = ''
    try
      require(libPath)()
      threwError = false
    catch e
      threwError = true
    process.env.DATABASE_URL = tmp
    expect(threwError).is.equal(true)

describe 'db.end()', () ->
  it 'should close the connections in the pool even if it is usused', (done) ->
    # Add a '?' to make the URL unique:
    db = require(libPath)(process.env.DATABASE_URL + '?')
    async.series [
      (cb) -> db.end cb
    ], done

  it 'should close the connections in the pool', (done) ->
    # Add a '?' to make the URL unique:
    db = require(libPath)(process.env.DATABASE_URL + '?')
    async.series [
      (cb) -> db.query 'SELECT 1', cb
      (cb) -> db.end cb
    ], done
