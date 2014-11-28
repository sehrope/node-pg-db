pg = require 'pg.js'
domain = require 'domain'
async = require 'async'
uid = require('rand-token').uid
{EventEmitter} = require 'events'

class DB extends EventEmitter
  ###
  Creates a new instance.

  @param {string|object} config The config URL or object for the remote database.
  @param {object} opts Optional configuration properties.
  ###
  constructor: (@config, @opts) ->
    # Unique pool key, used to namespace transactions:
    @poolKey = JSON.stringify(config)
    ###
    Property nae to store the transaction state in the active domain.
    Namespaced with the pool key to allow for multiple transaction with different data sources.
    ###
    @txKey = '_tx'

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

        exitTxDomain = () =>
          # Remove transaction state from domain:
          txd[@txKey] = null
          txd.exit()

        rollbackTx = (err, cb) =>
          client.query 'ROLLBACK', [], (rollbackErr) ->
            # TODO: Log if an error occurs
            # Return the connection to the pool and instruct it to disgard it
            done(err)
            # If defined, invoke the callback with the original error:
            cb?(err)

        txd.on 'error', (err) =>
          exitTxDomain()
          # Propagate the error the parent domain
          if activeDomain
            activeDomain.emit 'err', err
            rollbackTx(err)
          else
            rollbackTx(err, cb)

        txd.run () =>
          async.series [
            client.query.bind client, 'BEGIN', []
            task
            client.query.bind client, 'COMMIT', []
          ], (err, results) =>
            exitTxDomain()
            if err
              # An error ocurred somewhere so rollback the transaction:
              return rollbackTx(err, cb)
            # Return the connection to the pool
            done()
            # Invoke the completion callback with the result of the task:
            cb(null, results[1])

    # Primary tx function for executing a single task:      
    @tx = execTx

    # Add async helper functions:
    for name in ['series', 'parallel', 'auto']
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
    if typeof(sql) != 'string' then throw new Error('sql must be a stirng')
    if !Array.isArray(params) && typeof(params) != 'object' then throw new Error('params must be an array or object')
    if typeof(cb) != 'function' then throw new Error('cb must be a function')

    executeInternal = (client, sql, params, cb) =>
      startedAt = new Date()
      # TODO: Publish execute event
      client.query sql, params, (err, result) =>
        completedAt = new Date()
        elapsed = completedAt.getTime() - startedAt.getTime()
        # TODO: Publish executed event
        cb(err, result)

    if @tx.active
      # We're in a transaction so use the existing client:
      executeInternal(@tx.active.client, sql, params, cb)
    else
      # We're not in a transaction so use a random connection from the pool:
      @connect (err, client, done) =>
        if err then return cb(err)
        executeInternal client, sql, params, (err, result) ->
          # Return the connection to the pool, if there's an error it'll be disgarded:
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

###
@param {object|string} config The connection confirg, defaults to process.env.DATABASE_URL
@param {object} opts Additional options (optional)
@returns {object} A DB helper object.
###
module.exports = (config, opts) ->
  config ||= process.env.DATABASE_URL
  if !config
    throw new Error('config or process.env.DATABASE_URL is required')
  new DB(config || process.env.DATABASE_URL, opts)
