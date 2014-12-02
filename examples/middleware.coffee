db = require('../lib/index')()
domain = require 'domain'
http = require 'http'
async = require 'async'

# Add an event listener to log all SQL statements as they are executed:
db.on 'executeComplete', (data) ->
  if data.tx
    sqls = data.tx.sqls ||= []
  else
    sqls = process.domain?.sqls
  sqls?.push
    executedAt: new Date()
    sql: data.sql
    elapsed: data.elapsed

db.on 'commitComplete', (data) ->
  console.log 'During commit complete _req:', process.domain?._req
  process.domain?.sqls?.push data.tx.sqls...

reqCounter = 0
server = http.createServer (req, res) ->
  console.log '%s - %s %s', new Date().toISOString(), req.method, req.url
  console.log 'Before _req:', process.domain?._req
  reqd = domain.create()
  reqd.add(req)
  reqd.add(res)
  reqd._req =
    id: reqCounter++
  reqd.sqls = []
  reqd.on 'error', (err) ->
    console.error 'Uncaught error:', err
  reqd.run () ->
    console.log 'During _req:', process.domain?._req
    db.tx.series [
      (cb) -> db.queryOne 'SELECT 1', cb
      (cb) -> db.queryOne 'SELECT 2', cb
      (cb) ->
        if Math.random() > .5
          db.queryOne 'SELECT 3', cb
        else
          cb(null)
      (cb) -> db.query 'SELECT x FROM generate_series(1,10) x', cb
    ], (err) ->
      console.log 'After _req:', process.domain?._req
      if err
        console.error 'Err: %s', err
        res.statusCode = 500
        res.send 'ERROR: ' + err
        return res.end()
      sqls = process.domain?.sqls
      res.statusCode = 200
      res.write JSON.stringify(sqls, null, ' ') + '\n'
      res.end()

port = process.env.PORT || 5000
server.listen port, () ->
  console.log 'Listening on port %s', port
