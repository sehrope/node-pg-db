pg = require 'pg'
domain = require 'domain'
async = require 'async'
uid = require('rand-token').uid
np = require './named-params'

eventTypes = [
  'begin'
  'beginComplete'
  'execute'
  'executeComplete'
  'commit'
  'commitComplete'
  'rollback'
  'rollbackComplete'
]
eventTypesMap = {}
for event in eventTypes
  eventTypesMap[event] = true

parsedSqlCache = {}
parse = (sql) ->
  parsedSql = parsedSqlCache[sql]
  if !parsedSql
    parsedSql = np.parse(sql)
    parsedSqlCache[sql] = parsedSql
  return parsedSql


###
Wraps a function to ignore any returned or thrown errors.
If cb has no args (i.e. sync) it's turned into an async function instead.
###
asyncIgnorify = (cb) ->
  if cb.length == 0
    return (callback) ->
      try
        cb()
      catch ignore
      callback()
  return (callback) ->
    try
      cb () ->
        callback()
    catch ignore
      callback()

class DB
  ###
  Creates a new instance.

  @param {string|object} config The config URL or object for the remote database.
  @param {object} opts Optional configuration properties.
  ###
  constructor: (@config, @opts = {}) ->
    @poolKey = JSON.stringify(@config)
    @txKey = '_tx-' + @poolKey
    @_listeners = {}

    ###
    Execute task in a transaction.
    This will:
    1) Fetch a new connection from the pool
    2) Issue a BEGIN to start a new transaction
    3) Execute the task(...) callback
    4) Issue either a ROLLBACK or COMMIT (depending on whether task was successful)
    5) Execute the cb(...) callback

    @param {function} task The task to execution, a function(err, cb).
    @param {function} cb The callback to execute on transaction completion, a function(err, results...).
    ###
    execTx = (task, cb) =>
      txStack = (new Error()).stack
      @connect (err, client, done) =>
        if err then return cb(err)
        # The current active domain (if any):
        activeDomain = process.domain
        # Create a new domain for the transaction:
        txd = domain.create()

        tx = txd[@txKey] =
          # Unique id:
          id: uid(24)
          # Creation timestamp:
          createdAt: new Date()
          # Database client to use throughout transactionm:
          client: client
          # Stack when the transaction was first created:
          stack: txStack
          # Event listeners
          onSuccess: []
          onFailure: []

        # If any transaction completion callbacks have been registered then execute them
        doTxCompletionCallbacks = (err, cb) ->
          callbacks = if err then tx.onFailure else tx.onSuccess
          if callbacks.length == 0 then return cb(null)
          async.series callbacks, cb

        invokeCb = (err, results) ->
          doTxCompletionCallbacks err, () ->
            if activeDomain
              activeDomain.run () ->
                cb(err, results)
            else
              cb(err, results)

        exitTxDomain = () =>
          # Remove transaction state from domain:
          txd[@txKey] = null
          txd.exit()

        rollbackTx = (err, cb) =>
          @emit 'rollback',
            tx: tx
            err: err
          client.query 'ROLLBACK', [], (rollbackErr) =>
            @emit 'rollbackComplete',
              tx: tx
              err: err
              rollbackErr: rollbackErr
            # Return the connection to the pool and instruct it to discard it
            done(err)
            # If defined, invoke the callback with the original error:
            cb?(err)

        txd.on 'error', (err) =>
          exitTxDomain()
          # Propagate the error the parent domain
          if activeDomain
            activeDomain.emit 'error', err
            rollbackTx(err)
          else
            rollbackTx(err, invokeCb)

        txd.run () =>
          async.series [
            (cb) =>
              @emit 'begin', {tx}
              cb(null)
            client.query.bind client, 'BEGIN', []
            (cb) =>
              @emit 'beginComplete', {tx}
              cb(null)
            task
            (cb) =>
              @emit 'commit', {tx}
              cb(null)
            client.query.bind client, 'COMMIT', []
          ], (err, results) =>
            exitTxDomain()
            if err
              # An error ocurred somewhere so rollback the transaction:
              return rollbackTx(err, invokeCb)
            if activeDomain
              activeDomain.run () => @emit 'commitComplete', {tx}
            else
              @emit 'commitComplete', {tx}
            # Return the connection to the pool
            done()
            # Invoke the completion callback with the result of the task:
            invokeCb(null, results[3])

    # Primary tx function for executing a single task:
    @tx = execTx

    @tx.onSuccess = (cb) =>
      if !@tx.active then throw new Error('Transaction required')
      if typeof(cb) != 'function' then throw new Error('cb must be a function')
      @tx.active.onSuccess.push asyncIgnorify(cb)
    @tx.onFailure = (cb) =>
      if !@tx.active then throw new Error('Transaction required')
      if typeof(cb) != 'function' then throw new Error('cb must be a function')
      @tx.active.onFailure.push asyncIgnorify(cb)

    # Add async helper functions:
    for name in ['series', 'parallel', 'auto', 'waterfall']
      do (name) =>
        asyncFunc = async[name]
        @tx[name] = (tasks, cb) =>
          task = (cb) -> asyncFunc tasks, cb
          execTx task, cb

    ###
    Add transactional versions of helper functions.
    These functions check whether a transaction is active and if not return an error.
    If so, they invoke the equivalently named helper function
    ###
    for name in ['execute', 'query', 'queryOne', 'update']
      do (name) =>
        helperFunc = @[name]
        @tx[name] = (sql, params, cb) =>
          if !@tx.active
            if !cb then cb = params
            return setImmediate cb, new Error('Transaction required')
          helperFunc(sql, params, cb)

    ###
    Getter to return the active transaction.
    If no transaction is active then null is returned.
    ###
    Object.defineProperty @tx, 'active',
      get: () => process.domain?[@txKey] || null

  ###
  Add an event listener.
  ###
  on: (event, listener) =>
    if !eventTypesMap[event] then throw new Error('invalid event type: ' + event)
    if typeof(listener) != 'function' then throw new Error('listener must be a function')
    @_listeners[event] ||= []
    @_listeners[event].push(listener)

  emit: (event, data...) =>
    if !eventTypesMap[event] then throw new Error('invalid event type: ' + event)
    listeners = @_listeners[event]
    if !listeners then return
    for listener in listeners
      listener(data...)

  ###
  Convenience function to get a connection from the pool.
  This is a thin wrapper around pg.connect(...) using the supplied connection config.

  @params {function} cb The callback to be invoked with the connection, function(err, client, done)
  ###
  connect: (cb) => pg.connect @config, cb

  ###
  Low level function to execute a SQL command.
  If an active transaction is in progress then the shared client for that transaction will be used.
  If not, a random connection will be retrieved from the pool of connections.

  NOTE: This function may be called with two arguments (skipping the "params" arg).

  @param {string} sql The SQL to execute.
  @param {array|object} params Optional parameters for the SQL command.
  @param {function} cb The callback to be invoked on completion of the command, function(err, result).
  ###
  execute: (sql, params, cb) =>
    if !cb
      # When called with two args assume that there are no parameters
      cb = params
      params = []
    # Sanity check for args:
    if typeof(cb) != 'function' then throw new Error('cb must be a function')
    if typeof(sql) != 'string' then return setImmediate cb, new Error('sql must be a string')
    if !Array.isArray(params) && typeof(params) != 'object' then return setImmediate cb, new Error('params must be an array or object')
    # Save the stack of the caller:
    startedAt = new Date()
    stack = new Error().stack

    originalSql = sql
    originalParams = params
    if params and !Array.isArray(params)
      try
        parsedSql = parse(sql)
        params = np.convertParamValues(parsedSql, params)
        sql = parsedSql.sql
      catch parseError
        return setImmediate cb, parseError

    executeInternal = (client, sql, params, cb) =>
      executeId = uid(32)
      connectedAt = new Date()
      @emit 'execute',
        id: executeId
        sql: originalSql
        params: originalParams
        parsedSql: sql
        parsedParams: params
        tx: @tx.active
        stack: stack
        startedAt: startedAt
        connectedAt: connectedAt
      client.query sql, params, (err, result) =>
        completedAt = new Date()
        elapsed = completedAt.getTime() - startedAt.getTime()
        @emit 'executeComplete',
          id: executeId
          startedAt: startedAt
          connectedAt: connectedAt
          completedAt: completedAt
          elapsed: completedAt.getTime() - startedAt.getTime()
          sql: originalSql
          parsedSql: sql
          params: params
          tx: @tx.active
          err: err
          result: result
          stack: stack
        cb(err, result)

    if @tx.active
      # We're in a transaction so use the existing client:
      executeInternal(@tx.active.client, sql, params, cb)
    else
      # We're not in a transaction so use a random connection from the pool:
      @connect (err, client, done) =>
        if err then return cb(err)
        executeInternal client, sql, params, (err, result) ->
          # Return the connection to the pool, if there's an error it'll be discarded:
          done(err)
          cb(err, result)

  ###
  Wrapper atop execute(...) for queries that are expected to return a set of rows.

  NOTE: This function may be called with two arguments (skipping the "params" arg).

  @param {string} sql The SQL to execute.
  @param {array|object} params Optional parameters for the SQL command.
  @param {function} cb The callback to be invoked on completion of the command, function(err, rows).
  ###
  query: (sql, params, cb) =>
    if !cb
      # When called with two args assume that there are no parameters
      cb = params
      params = []
    @execute sql, params, (err, result) =>
      cb(err, result?.rows)

  ###
  Wrapper atop execute(...) for queries that are expected to return a single row.
  If the result contains no rows then "null" will be returned.
  If the result contains more than one row then an Error will be returned.

  NOTE: This function may be called with two arguments (skipping the "params" arg).

  @param {string} sql The SQL to execute.
  @param {array|object} params Optional parameters for the SQL command.
  @param {function} cb The callback to be invoked on completion of the command, function(err, row).
  ###
  queryOne: (sql, params, cb) =>
    if !cb
      # When called with two args assume that there are no parameters
      cb = params
      params = []
    @execute sql, params, (err, result) =>
      if result?.rows.length > 1
        return cb(new Error('Expected 1 row but result returned ' + result.rows.length + 'rows'))
      cb(err, result?.rows[0] || null)

  ###
  Wrapper atop execute(...) for queries that are expected only return an updated row count.
  Ex: INSERT or UPDATE statements without a RETURNING ... clause.

  NOTE: This function may be called with two arguments (skipping the "params" arg).

  @param {string} sql The SQL to execute.
  @param {array|object} params Optional parameters for the SQL command.
  @param {function} cb The callback to be invoked on completion of the command, function(err, rowCount).
  ###
  update: (sql, params, cb) =>
    if !cb
      # When called with two args assume that there are no parameters
      cb = params
      params = []
    @execute sql, params, (err, result) =>
      cb(err, result?.rowCount)

  ###
  Shutdown the connection pool and close all open connections.

  @param {function} cb Optional callback to be invoked after connection pool is closed.
  ###
  end: (cb) =>
    pool = pg.pools.all[@poolKey]
    if pool
      pool.drain () ->
        pool.destroyAllNow cb || ->
    else
      if cb then setImmediate cb


cache = {}

###
@param {object|string} config The connection confirg, defaults to process.env.DATABASE_URL
@param {object} opts Additional options (optional)
@returns {object} A DB helper object.
###
module.exports = (config, opts) ->
  config ||= process.env.DATABASE_URL
  if !config
    throw new Error('config or process.env.DATABASE_URL is required')
  cacheKey = JSON.stringify(config)
  if !cache[cacheKey]
    cache[cacheKey] = new DB(config, opts)
  return cache[cacheKey]
