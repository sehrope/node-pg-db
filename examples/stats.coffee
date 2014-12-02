async = require 'async'
crypto = require 'crypto'
db = require('../lib/index')()

# Generate a unique ID for each SQL statement:
sqlToKey = (sql) -> crypto.createHash('sha256').update(sql).digest('hex')

# Cache of query stats:
queryStats = {}

# Add an event listener to log all SQL execution:
db.on 'executeComplete', (data) ->
  if data.elapsed > 100
    console.log 'SLOW QUERY (%s ms): %j at: %s', data.elapsed, data.sql, data.stack

  key = sqlToKey(data.sql)
  stat = queryStats[key]
  if !stat
    stat =
      id: key
      sql: data.sql
      execs: 0
      errors: 0
      minElapsed: 999999999
      maxElapsed: 0
      totalElapsed: 0
      minConnect: 999999999
      maxConnect: 0
      totalConnect: 0
    queryStats[key] = stat
  stat.execs++
  if data.err then stat.errors++
  stat.minElapsed = Math.min(stat.minElapsed, data.elapsed)
  stat.maxElapsed = Math.max(stat.maxElapsed, data.elapsed)
  stat.totalElapsed += data.elapsed
  stat.minConnect = Math.min(stat.minConnect, data.connectElapsed)
  stat.maxConnect = Math.max(stat.maxConnect, data.connectElapsed)
  stat.totalConnect += data.connectElapsed

async.parallelLimit [
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
  (cb) -> db.query 'SELECT 1 FROM pg_sleep(random())', cb
], 4, (err) ->
  if err
    console.error(err)
  else
    for key, stat of queryStats
      console.log '%j execs: %s min: %s max: %s total: %s', stat.sql, stat.execs, stat.minElapsed, stat.maxElapsed, stat.totalElapsed
  db.end()
