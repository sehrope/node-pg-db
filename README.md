# pg-db

[![NPM](https://nodei.co/npm/pg-db.png?downloads=true&downloadRank=true&stars=true)](https://nodei.co/npm/pg-db/)

[![Build Status](https://travis-ci.org/sehrope/node-pg-db.svg?branch=master)](https://travis-ci.org/sehrope/node-pg-db)

# Overview
Helper module atop [node-postgres](https://github.com/brianc/node-postgres) that adds transaction management, simpler query API, event hooks, and more.

* [Install](#install)
* [Usage](#usage)
* [Features](#features)
* [Transaction](#transactions)
* [Named Parameter Support](#named-parameters)
* [API](#api)
    * [Query API](#query-api)
    * [Transaction API - Control Flow](#transaction-api---control-flow)
    * [Transaction API - Query and DML](#transaction-api---query-and-dml)
    * [Transaction API - Success/Failure Hooks](#transaction-api---success-or-failure-hooks)
* [Events API](#events-api)
* [Building and Testing](#building-and-testing)
* [License](#license)

# Install

    $ npm install pg-db --save

# Usage

    // Create using default connection config of process.env.DATABASE_URL:
    var db = require('pg-db')();

    db.query('SELECT foo, bar, baz FROM some_table', function(err, rows){
      if( err ) return console.error('Err: %s', err);
      console.log('Rows: %j', rows);
    });

# Features
* Convenient wrapper functions - *callbacks for single row, multiple rows, or update row counts*
* Automatically return connections to the pool - *no need to call `done()`*
* SQL errors automatically destory the connection - *no need to call `done(err)`*
* Named parameters - *`... WHERE foo = :foo` instead of `... WHERE foo = $1`*
* Transactions - *automatic and transparent!*
* Event hooks - *register callbacks when queries get executed - great for logging!*
* Transaction event hooks - *register callbacks when a transaction completes - great for cache invalidation!*

# Transactions
Transactions are implemented using [domains](http://nodejs.org/api/domain.html). This allows the same node-postgres `client` object to be used by separate parts of your application without having to manually pass it as an argument.

Any other modules that use `pg-db` for query execution will automatically be part of the ongoing transaction. This allows you to easily compose multiple database interactions together without needing to pass a transactional context object to every single function.

    // Foo.update(foo, cb) - Updates a Foo model object
    // Audit.create(message, cb) - Creates an audit record

    db.tx.series([
      async.apply(Foo.update, foo),
      async.apply(Audit.create, 'Updating foo id=' + foo.id)
    ], cb);

# Named Parameters
Named parameter support allows you to use descriptive names for parameters in SQL queries.
This leads to much cleaner SQL that's easier to both read and write.

Example:

    // SQL with numbered parameters:
    db.queryOne('SELECT * FROM some_table WHERE foo = $1'
              , [123]
              , function(err, row) {...})
    
    // SQL with named parameters:
    db.queryOne('SELECT * FROM some_table WHERE foo = :foo'
              , {foo: 123}
              , function(err, row) {...})

A more complicated example:

    // Classic style with positional parameters:
    db.update('INSERT INTO user'
                  + ' (id, name, email, password_hash)'
                  + ' VALUES '
                  + ' ($1, $2, $3, $4)'
               , [1, 'alice', 'alice@example.org', hash('t0ps3cret')]
               , function(err, rowCount) { /* do something */ });
    
    // Same query with named parameters:
    db.update('INSERT INTO user'
                  + ' (id, name, email, password_hash)'
                  + ' VALUES '
                  + ' (:id, :name, :email, :passwordHash)'
               , {id: 1, name: 'alice', email: 'alice@example.org', passwordHash: hash('t0ps3cret')}
               , function(err, rowCount) { /* do something */ });

Another example with a model object:

    var widget = {
      id: 12345,
      name: 'My Widget',
      type: 'xg17',
      owner: 'me@example.org'
    };
    
    // Classic style with positional parameters:
    db.update('INSERT INTO widgets'
                  + ' (id, name, type, owner)'
                  + ' VALUES '
                  + ' ($1, $2, $3, $4)'
               , [widget.id, widget.name, widget.type, widget.owner]
               , function(err, rowCount) { /* do something */ });
    
    // Same query with named parameters:
    db.update('INSERT INTO widgets'
                  + ' (id, name, type, owner)'
                  + ' VALUES '
                  + ' (:id, :name, :type, :owner)'
               // We can just pass in the object as is:
               , widget
               , function(err, rowCount) { /* do something */ });

# API

## Query API
If a transaction is in progress then all functions of the Query API will automatically use the connection `client` for the transactions.

If no transaction is in progress then a random connection will be retrieved from the pool of connections. After execution completes the connection will be returned to the pool.

If an error occurrs then by default the pool wil be instructed to destroy the connection. Internally, this is done by invoking `done(err)`.


### query(sql, [params], function cb(err, rows))
Execute SQL with the optional parameters and invoke the callback with the result rows.

This function is intended to be used with SQL that returns back a set of rows such as a `SELECT ...` statement. If no rows are returned then the callback will be invoked with an empty array.

### queryOne(sql, [params], function cb(err, row))
Execute SQL with the optional parameters and invoke the callback with the first result row.

This function is intended to be used with SQL that returns back a single row. If no rows are returned then the callback is invoked with a `null` value for row. If more than one row is returned then the callback is invoked with an `Error`.

__NOTE:__ *This function will return an `Error` if multiple rows are returned. This is intentional as it probably means your SQL is wrong.*

### update(sql, [params], function cb(err, rowCount))
Execute SQL with the optional parameters and invoke the callback with the number of rows that were modified.

This function is intended to be used with SQL that performs DML (e.g. `INSERT`, `UPDATE`, `DELETE`).

### execute(sql, [params], function cb(err, result))
Execute SQL with the optional parameters and invoke the callback with the raw result object returned by node-postgres.

This function is used internally by `query`, `queryOne`, and `update`. It's useful when you'd like to use both the `rowCount` and `rows`. Otherwise it's probably more convenient to use one of the other functions.

## Transaction API - Control Flow

### db.tx(function task(cb), function cb(err, result))
Executes a task in a transaction and invokes the callback with the result of the task.

### db.tx.series(tasks, function cb(err, results))
Convenience wrapper for executing a series of tasks within a transaction.

Internally this executes the tasks by calling [async.series](https://github.com/caolan/async#seriestasks-callback).

### db.tx.parallel(tasks, function cb(err, results))
Convenience wrapper for executing tasks in parallel within a transaction.

Internally this executes the tasks by calling [async.parallel](https://github.com/caolan/async#parallel).

### db.tx.auto(tasks, function cb(err, results))
Convenience wrapper for executing multiple tasks that depended on each other within a transaction.

Internally this executes the tasks by calling [async.auto](https://github.com/caolan/async#auto).

### db.tx.waterfall(tasks, function cb(err, results))
Convenience wrapper for executing tasks in a waterfall, passing each result to the next task, within a transaction.

Internally this executes the tasks by calling [async.waterfall](https://github.com/caolan/async#waterfall).

## Transaction API - Query and DML
Each of these functions checks whether a transaction is currently in progress and then invokes the equivalent non-tx function of the same name.

### db.tx.query(sql, [params], function cb(err, rows))
Ensure we're running within a transaction and execute the command.

If no transaction is in progress then the callback is invoked with an error. Otherwise this behaves exactly like the non-tx version.

### db.tx.queryOne(sql, [params], function cb(err, row))
Ensure we're running within a transaction and execute the command.

If no transaction is in progress then the callback is invoked with an error. Otherwise this behaves exactly like the non-tx version.

### db.tx.update(sql, [params], function cb(err, rowCount))
Ensure we're running within a transaction and execute the command.

If no transaction is in progress then the callback is invoked with an error. Otherwise this behaves exactly like the non-tx version.

### db.tx.execute(sql, [params], function cb(err, result))
Ensure we're running within a transaction and execute the command.

If no transaction is in progress then the callback is invoked with an error. Otherwise this behaves exactly like the non-tx version.

## Transaction API - Success or Failure Hooks
The transaction API allows for registering callbacks to execute on completion of the current transaction. If no transaction is in progress then an error will be thrown.

If a callback has an arity of 0, i.e. `function() {...}`, then it is assumed to be a synchronous function.
Otherwise it is assumed to accept a single paramater for the callback function that should be invoked, i.e. `function(cb) {...}`.

Any errors thrown or asynchronously returned back from callbacks are ignored.
Multiple callbacks are executed in the order they are registered.

### db.tx.onSuccess(function([cb]) callback)
Register a callback function to execute if the transaction is successful (i.e. after successful COMMIT)).

### db.tx.onFailure(function([cb]) callback)
Register a callback function to execute if the transaction is unsuccessful (e.g. a ROLLBACK is issued).

## Events API
### db.on(event, function(data...))
Register a callback to execute when a given event occurs.

The follow event types are supported:

* execute - triggered whenever a query is executed.
* executeComplete - triggered after a query is executed.
* begin - triggered before a transaction is started.
* beginComplete - triggered after a transaction is started.
* commit - triggered when a transaction is about to be committed.
* commitComplete - triggered after a transaction is committed.
* rollback - triggered when a transaction is about to be rolled back.
* rollbackComplete - triggered after a transaction is rolled back.

# Building and Testing
To buld the module run:

    $ make

To run the tests first create a `test/env` file. You can use `test/env.example` as a template. Edit the `DATABASE_URL` property to point to a Postgres database.

Then, to run the tests run:

    $ make test

# License
See the [LICENSE](LICENSE) file for details.
