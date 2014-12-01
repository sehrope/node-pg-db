PARAMETER_SEPARATORS = ['"', '\'', ':', '&', ',', ';', '(', ')', '|', '=', '+', '-', '*', '%', '/', '\\', '<', '>', '^']
SKIPS = [
  {start: "'", stop: "'"}
  {start: "\"", stop: "\""}
  {start: "--", stop: "\n"}
  {start: "/*", stop: "*/"}
]

isParamSeparator = (c) ->
  return /\s/.test(c) or c in PARAMETER_SEPARATORS

skipCommentsAndQuotes = (sql, position) ->
  for skip in SKIPS
    if sql.substr(position, skip.start.length) != skip.start
      continue
    position += skip.start.length
    while sql.substr(position, skip.stop.length) != skip.stop
      position++
      if position >= sql.length
        # Comment or quote is not closed properly
        return sql.length
    position += skip.stop.length - 1
  return position

parse = (sql) ->
  if typeof(sql) != 'string' then throw new Error('sql must be a string')
  params = []
  i = 0
  throwError = (msg, pos) ->
    pos = pos || i
    throw new Error((msg || 'Error') + ' at position ' + pos + ' in statment ' + sql)
  while i < sql.length
    # First skip any quotes or comments:
    skipPos = i
    while i < sql.length
      skipPos = skipCommentsAndQuotes(sql, i)
      if i == skipPos
        break
      i = skipPos
    if i >= sql.length
      break
    # Then check to see if we're in a param block:
    if sql[i] in [':', '&', '$']
      if sql.substr(i,2) == '::'
        # Postgres-style "::" cast (skip):
        i += 2
        continue
      j = i + 1
      if sql.substr(i,2) == ':{'
        # :{foobar} style parameter:
        while j < sql.length and '}' != sql[j]
          j++
          if sql[j] in [':', '{']
            throwError 'Parameter name contains invalid character "' + sql[j] + '"'
        if j >= sql.length
          throwError 'Non-terminated named parameter declaration)'
        if j - i > 3
          params.push
            name: sql.substring(i + 2, j)
            start: i
            end: j + 1
            type: ':{}'
        j++
      else
        # :foobar or $foobar style parameter
        while j < sql.length and !isParamSeparator(sql[j])
          j++
        if (j - i) > 1
          params.push
            name: sql.substring(i + 1, j)
            start: i
            end: j
            type: sql[i]
      i = j - 1
    i++

  ret =
    sql: sql
    originalSql: sql
    params: []
    numParams: params.length
    numDistinctParams: 0
  paramTypes = {}
  namedParams = {}
  paramCount = 0
  for param in params
    paramCount++
    paramTypes[param.type] = (paramTypes[param.type] || 0) + 1
    if /^[0-9]+$/.test(param.name)
      throwError 'You cannot mix named and numbered parameters. Check parameter "' + param.name + '"', param.start
    namedParam = namedParams[param.name]
    if !namedParam
      # Increment first so that $1, $2 ... are 1-origin
      ret.numDistinctParams++
      namedParam =
        # :foo, $foo, etc (the "foo" part)
        name: param.name
        # First index ($1, $2, etc) of this parameter
        index: ret.numDistinctParams
        # All the $N spots of this parameter (for repeated parameters)
        indexes: []
      namedParams[param.name] = namedParam
      ret.params.push(namedParam)
    namedParam.indexes.push(paramCount)

  # Make sure we're not mixing $foo and :foo
  if Object.keys(paramTypes).length > 1
    throw new Error('You cannot mix multiple types of parameters in statement: ' + sql)

  if ret.numParams > 0
    for i in [ret.numParams-1..0]
      param = params[i]
      namedParam = namedParams[param.name]
      # "SELECT :foo FROM bar" => "SELECT " + "$1" + " FROM bar"
      ret.sql = ret.sql.substring(0, param.start) + '$' + namedParam.index + ret.sql.substring(param.end)

  return ret

module.exports =
  parse: parse
  # For testing:
  isParamSeparator: isParamSeparator
  skipCommentsAndQuotes: skipCommentsAndQuotes
