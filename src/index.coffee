{resolvePath} = require 'resolve'
path = require 'path'
wch = require 'wch'
fs = require 'fsx'

# TODO: Unload babel modules when this plugin is stopped.
module.exports = (log) ->
  debug = log.debug 'wch-babel'
  babelCache = {}

  loadBabel = (pack) ->
    unless babelPath = resolvePath 'babel-core', {parent: pack.path}
      log.warn "Cannot resolve 'babel-core' from '#{pack.path}'"
      return null
    unless babel = babelCache[babelPath]
      log log.lyellow('Loading:'), shortPath babelPath
      babel = require(babelPath).transformFileSync
      babelCache[babelPath] = babel
    return babel

  shortPath = (path) ->
    path.replace process.env.HOME, '~'

  compile = (file) ->
    try mtime = fs.stat(file.dest).mtime.getTime()
    return if mtime and mtime > file.mtime_ms

    debug 'Transpiling:', shortPath file.path
    try # TODO: source maps
      {code} = @compile file.path,
        highlightCode: false
      return [code, file]

    catch err
      loc = [err.loc.line - 1, err.loc.column]
      wch.emit 'file:error',
        file: file.path
        message: err.message.slice file.path.length + 2
        location: [loc, loc]

      debug log.red('Failed to compile:'), shortPath file.path
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

  watchOptions =
    only: ['*.js']
    skip: ['**/__*__/**']
    fields: ['name', 'exists', 'new', 'mtime_ms']
    crawl: true

  attach: (pack) ->
    pack.compile = loadBabel pack
    # TODO: Emit a warning via `wch.emit`
    return unless pack.compile

    dest = path.dirname path.resolve pack.path, pack.main or 'js/index'
    changes = pack.stream 'src', watchOptions
    changes.on 'data', (file) ->
      file.dest = path.join dest, file.name
      action = if file.exists then build else clear
      action.call(pack, file).catch (err) ->
        log log.red('Error while processing:'), file.path
        console.error err.stack
