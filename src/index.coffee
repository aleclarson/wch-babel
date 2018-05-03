{resolvePath} = require 'resolve'
path = require 'path'
wch = require 'wch'
fs = require 'fsx'

# TODO: Unload babel modules when this plugin is stopped.
module.exports = (log) ->
  babelCache = {}

  loadBabel = (pack) ->
    unless babelPath = resolvePath 'babel-core', {parent: pack.path}
      log.yellow 'warn:', "Cannot resolve 'babel-core' from '#{pack.path}'"
      return null
    unless babel = babelCache[babelPath]
      log.pale_yellow 'Loading:', shortPath babelPath
      babel = require(babelPath).transformFileSync
      babelCache[babelPath] = babel
    return babel

  shortPath = (path) ->
    path.replace process.env.HOME, '~'

  compile = (file) ->
    try mtime = fs.stat(file.dest).mtime.getTime()
    return if mtime and mtime > file.mtime_ms

    if log.verbose
      log.pale_yellow 'Transpiling:', shortPath file.path

    # TODO: Source maps
    try
      {code} = @compile file.path,
        highlightCode: false
      return [code, file]

    catch err
      loc = [err.loc.line - 1, err.loc.column]
      wch.emit 'file:error',
        file: file.path
        message: err.message.slice file.path.length + 2
        location: [loc, loc]

      if log.verbose
        log.red 'Failed to compile:', shortPath file.path
      return

  build = wch.pipeline()
    .map compile
    .save (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:build', {file: file.path, dest}

  clear = wch.pipeline()
    .delete (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:delete', {file: file.path, dest}

  streamConfig =
    crawl: true
    fields: ['name', 'exists', 'new', 'mtime_ms']
    include: ['*.js']
    exclude: ['**/__*__/**']

  attach: (pack) ->
    pack.compile = loadBabel pack
    # TODO: Emit a warning via `wch.emit`
    return unless pack.compile

    dest = path.dirname path.resolve pack.path, pack.main or 'js/index'
    changes = pack.stream 'src', streamConfig
    changes.on 'data', (file) ->
      file.dest = path.join dest, file.name
      action = if file.exists then build else clear
      action.call(pack, file).catch (err) ->
        log.red 'Error while processing:', file.path
        console.error err.stack
