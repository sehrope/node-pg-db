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
