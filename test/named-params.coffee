{assert, expect} = require 'chai'
libPath = if process.env.COVERAGE then '../lib-cov' else '../lib'
np = require libPath + '/named-params'

expectError = (cb) ->
  try
    cb()
  catch e
    return
  throw new Error('Expected an error to be thrown')

describe 'named parameter parser', () ->
  it 'should parse :foo style params', () ->
    parsed = np.parse('SELECT :foo')
    expect(parsed.sql).to.be.equal('SELECT $1')
    expect(parsed.numParams).to.be.equal(1)
    expect(parsed.params[0].name).to.be.equal('foo')

  it 'should parse $foo style params', () ->
    parsed = np.parse('SELECT $foo')
    expect(parsed.sql).to.be.equal('SELECT $1')
    expect(parsed.numParams).to.be.equal(1)
    expect(parsed.params[0].name).to.be.equal('foo')

  it 'should parse :{foo} style params', () ->
    parsed = np.parse('SELECT :{foo}')
    expect(parsed.sql).to.be.equal('SELECT $1')
    expect(parsed.numParams).to.be.equal(1)
    expect(parsed.params[0].name).to.be.equal('foo')

  it 'should parse handle spaces in :{foo bar} style params', () ->
    parsed = np.parse('SELECT :{foo bar}')
    expect(parsed.sql).to.be.equal('SELECT $1')
    expect(parsed.numParams).to.be.equal(1)
    expect(parsed.params[0].name).to.be.equal('foo bar')

  it 'should skip /* */ style comments', () ->
    parsed = np.parse('SELECT /* $foo */ 1')
    expect(parsed.sql).to.be.equal('SELECT /* $foo */ 1')
    expect(parsed.numParams).to.be.equal(0)

  it 'should skip -- style comments', () ->
    parsed = np.parse('SELECT -- $foo\n 1')
    expect(parsed.sql).to.be.equal('SELECT -- $foo\n 1')
    expect(parsed.numParams).to.be.equal(0)

  it 'should skip quoted literals', () ->
    parsed = np.parse('SELECT \'$foo\' 1')
    expect(parsed.sql).to.be.equal('SELECT \'$foo\' 1')
    expect(parsed.numParams).to.be.equal(0)

  it 'should skip quoted identifiers', () ->
    parsed = np.parse('SELECT "$foo" 1')
    expect(parsed.sql).to.be.equal('SELECT "$foo" 1')
    expect(parsed.numParams).to.be.equal(0)

  it 'should skip postgres style casts', () ->
    parsed = np.parse('SELECT blah::foo')
    expect(parsed.sql).to.be.equal('SELECT blah::foo')
    expect(parsed.numParams).to.be.equal(0)

  it 'should reject :{foo{} style params with bad characters', () ->
    expectError () ->
      parsed = np.parse('SELECT :{foo{}')

  it 'should reject mixing multiple styles of parameters', () ->
    expectError () ->
      parsed = np.parse('SELECT :foo, $foo')

  it 'should reject mixing named and numbered parameters', () ->
    expectError () ->
      parsed = np.parse('SELECT $1')

  it 'should reject parameter declarations that do not terminate', () ->
    expectError () ->
      parsed = np.parse('SELECT :{foo')

  it 'should reject when sql is not a string', () ->
    expectError () ->
      parsed = np.parse(12345)
