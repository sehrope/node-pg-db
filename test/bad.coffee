async = require 'async'
{assert, expect} = require 'chai'
libPath = if process.env.COVERAGE then '../lib-cov' else '../lib'

describe 'a bad database config', () ->
  it 'should return an error when trying to connect', (done) ->
    DATABASE_URL = 'postgresq://foo:bar:baz/'
    db = require(libPath)(DATABASE_URL)
    db.connect (err, client, clientDone) ->
      expect(err).to.be.ok()
      done()

  it 'should return an error when trying to execute a query', (done) ->
    DATABASE_URL = 'postgresq://foo:bar:baz/'
    db = require(libPath)(DATABASE_URL)
    db.queryOne 'SELECT 1', (err, row) ->
      expect(err).to.be.ok()
      done()

  it 'should return an error when trying to begin a transaction', (done) ->
    DATABASE_URL = 'postgresq://foo:bar:baz/'
    db = require(libPath)(DATABASE_URL)
    db.tx (cb) ->
      cb()
    , (err) ->
      expect(err).to.be.ok()
      done()
