--!strict
--!native
--[[
@merge-to-master/cli: merge_to_master's command line, over @merge-to-master/commands.

  parse(argv, folder?) -> (command, nil) | (nil, message)
  render(result) -> text
  status(result) -> exit status
  run(argv, folder?) -> exit status

  merge-to-master [OPTIONS] <PLUGIN> <MASTER>

The arguments and flags are merge_to_master 0.9.5's, read as it reads them: `-r`/`--remove-deleted`
and `-o`/`--overwrite` take no value and can share a dash (`-ro`), each at most once; `--` ends the
flags; `-h`/`--help` and `-V`/`--version` stop the reading where they stand. `parse` reads an
argument list into the request `commands.merge` takes, touching no file, or says what it
couldn't read in merge_to_master's words. No arguments at all is a command of its own, `usage`:
merge_to_master then prints its help and fails.

`render` is a result as the text merge_to_master ends on: `Merge Successful: <master>` and
`Log available at: <log>`. Where it stops with an error, this says why in one line. `status` is
the exit status of that outcome. `run` does the three in turn: it checks that both arguments are
files, as merge_to_master's argument parser does, calls `commands.merge`, and writes the text to
standard error, where merge_to_master writes it. The log is merge_to_master.log in the current
folder, as it is there: `./merge_to_master.log`. `folder` stands in for the current folder, for a
caller that isn't run from where the log should go.

Exit statuses: 0 when the master was merged; 8 when the command line can't be used (no
arguments, an unknown or repeated flag, a missing or extra argument, an argument that isn't a
file), where merge_to_master exits 2; 9 when the merge failed (a master of the plugin's that
isn't beside the master, a backup that couldn't be made, a file that isn't a plugin), where
merge_to_master exits 1. Messages go to standard error as `merge-to-master: <message>`.
]]

local commands = require '@merge-to-master/commands'
local process = require '@dream/process'

export type Command = {
  action: 'merge' | 'help' | 'usage' | 'version',
  --- What `commands.merge` is to be called with, when the action is `merge`.
  request: commands.MergeRequest?,
}

--- A flag: its spellings, and what it does.
type Flag = { long: string, short: string, action: 'set' | 'help' | 'version' }

local Exit = table.freeze { ok = 0, invalidInput = 8, runtime = 9 }

-- The release of merge_to_master this follows: what `--version` prints.
local Version = '0.9.5'

-- The log merge_to_master writes in the current folder.
local LogName = 'merge_to_master.log'

local Flags: { Flag } = {
  { long = 'remove-deleted', short = 'r', action = 'set' },
  { long = 'overwrite', short = 'o', action = 'set' },
  { long = 'help', short = 'h', action = 'help' },
  { long = 'version', short = 'V', action = 'version' },
}

local Long: { [string]: Flag }, Short: { [string]: Flag } = {}, {}

for _, flag in Flags do
  Long[flag.long] = flag
  Short[flag.short] = flag
end

local Usage = [[
merge-to-master: Greatness7's merge_to_master 0.9.5 for Jess, under the package's hyphenated name

Merge the contents of a plugin into a master.

Usage: merge-to-master [OPTIONS] <PLUGIN> <MASTER>

Arguments:
  <PLUGIN>  The plugin that will be merged into <MASTER>.
  <MASTER>  The master that <PLUGIN> will be merged into.

Options:
  -r, --remove-deleted  Remove all objects that are marked as DELETED.
  -o, --overwrite       Overwrite <MASTER> without creating a backup.
  -h, --help            Print help
  -V, --version         Print version

<MASTER> is replaced by the merge. Without --overwrite it is first moved to
backups/merge_to_master/<name>.<NNN>.<extension> beside it, numbered after the backups already
there. The plugin's other masters are read from <MASTER>'s folder, for their dialogue only, and
found there whatever their case. merge_to_master.log is written in the current folder.

merge_to_master numbers the plugin's references and textures, and writes its log's lines, in
hash-map order, differently each run. This does all three in the order tes3conv sorts the
plugin's records, every run.

Exit status: 0 merged; 8 the command line can't be used (merge_to_master exits 2); 9 the merge
failed (merge_to_master exits 1).]]

local function out(text: string) process.write('stdout', `{text}\n`) end

local function err(text: string) process.write('stderr', `{text}\n`) end

local function usage(message: string): number
  err(`merge-to-master: {message}`)
  return Exit.invalidInput
end

local function parse(argv: { string }, folder: string?): (Command?, string?)
  if #argv == 0 then return { action = 'usage' :: 'usage' }, nil end

  local positional: { string } = {}
  local given: { [string]: boolean } = {}
  local literal = false

  -- What a flag does where it stands: the command it ends the reading with, or why it can't be
  -- given.
  local function apply(flag: Flag): (Command?, string?)
    if flag.action == 'help' then return { action = 'help' :: 'help' }, nil end

    if flag.action == 'version' then return { action = 'version' :: 'version' }, nil end

    if given[flag.long] then
      return nil, `the argument '--{flag.long}' cannot be used multiple times`
    end

    given[flag.long] = true
    return nil, nil
  end

  for _, argument in argv do
    if literal or argument == '-' or string.sub(argument, 1, 1) ~= '-' then
      if #positional == 2 then return nil, `unexpected argument '{argument}' found` end

      table.insert(positional, argument)
      continue
    end

    if argument == '--' then
      literal = true
      continue
    end

    if string.sub(argument, 1, 2) == '--' then
      local name, value = string.match(argument, '^%-%-([^=]*)=(.*)$')
      local flag = Long[name or string.sub(argument, 3)]

      if not flag then
        return nil, `unexpected argument '--{name or string.sub(argument, 3)}' found`
      end

      if value then
        return nil, `unexpected value '{value}' for '--{flag.long}' found; no more were expected`
      end

      local command, message = apply(flag)

      if command or message then return command, message end

      continue
    end

    local last: Flag? = nil

    for index = 2, #argument do
      local letter = string.sub(argument, index, index)
      local flag = Short[letter]

      if letter == '=' and last then
        local value = string.sub(argument, index + 1)
        return nil, `unexpected value '{value}' for '--{last.long}' found; no more were expected`
      end

      if not flag then return nil, `unexpected argument '-{letter}' found` end

      local command, message = apply(flag)

      if command or message then return command, message end

      last = flag
    end
  end

  if #positional == 0 then
    return nil, 'the following required arguments were not provided: <PLUGIN> <MASTER>'
  end

  if #positional == 1 then
    return nil, 'the following required arguments were not provided: <MASTER>'
  end

  local request: commands.MergeRequest = {
    plugin = positional[1],
    master = positional[2],
    removeDeleted = given['remove-deleted'],
    overwrite = given['overwrite'],
    log = if folder then jess.fs.join(folder, LogName) else `./{LogName}`,
  }

  return { action = 'merge' :: 'merge', request = request }, nil
end

local function render(result: commands.MergeResult): string
  if result.outcome == 'missingMasters' then
    local names = table.concat(result.missing, ', ')
    return `merge-to-master: '{result.plugin}' names masters that aren't beside '{result.master}': {names}`
  end

  if result.outcome == 'backupFailed' then
    return `merge-to-master: Failed to create backup. {result.backupProblem or ''}`
  end

  local lines = {}

  if result.dryRun then
    table.insert(lines, `Dry run, nothing written: {result.master}`)

    if result.backup then table.insert(lines, `Backup would be: {result.backup}`) end
  else
    table.insert(lines, `Merge Successful: {result.master}`)
  end

  if result.logFile then table.insert(lines, `Log available at: {result.logFile}`) end

  return table.concat(lines, '\n')
end

local function status(result: commands.MergeResult): number
  return if result.outcome == 'merged' then Exit.ok else Exit.runtime
end

--- Says why the run stopped: the error's message, without the script position `error` puts in
--- front of one that isn't the command's own.
local function failed(caught: unknown): number
  err(`merge-to-master: {(string.gsub(tostring(caught), '^[^\n]-:%d+: ', ''))}`)
  return Exit.runtime
end

local function run(argv: { string }, folder: string?): number
  local command, message = parse(argv, folder)

  if not command then return usage(message :: string) end

  if command.action == 'help' then
    out(Usage)
    return Exit.ok
  end

  if command.action == 'version' then
    out(`merge-to-master {Version}`)
    return Exit.ok
  end

  if command.action == 'usage' then
    err(Usage)
    return Exit.invalidInput
  end

  local request = command.request :: commands.MergeRequest

  -- merge_to_master's argument parser takes only files for its two arguments.
  for _, argument in { { '<PLUGIN>', request.plugin }, { '<MASTER>', request.master } } do
    local name, path = argument[1], argument[2]

    if not jess.fs.isFile(path) then
      return usage(`invalid value '{path}' for '{name}': Invalid file path: {path}`)
    end
  end

  -- `merge` raises for a file that can't be read as a plugin, or written.
  local ran, result = pcall(commands.merge, request)

  if not ran then return failed(result) end

  err(render(result))
  return status(result)
end

return table.freeze { Exit = Exit, parse = parse, render = render, status = status, run = run }
