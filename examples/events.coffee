db = require('../lib/index')()

# Add an event listener to log all SQL statements as they are executed:
db.on 'execute', (data) ->
  console.log 'SQL: %j', data.sql

# Add an event listener to log all SQL errors:
db.on 'executeComplete', (data) ->
  if data.err
    console.log 'SQL ERROR: %s', data.err
    console.log '      SQL: %j', data.sql
    console.log '%s', data.stack

doStuff = () ->
  db.query 'SELECT 1', (err, row) ->
  db.query 'SELECT 2', (err, row) ->

doOtherStuff = () ->
  db.query 'SELECT * FROM non_existent_table', (err, row) ->

# This will succeed 
doStuff()

# This will fail and the stack trace should show the caller info:
doOtherStuff()

db.end()
