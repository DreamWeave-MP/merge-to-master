--!strict
--!native
--[[
@merge-to-master/commands: what merge_to_master does between reading its arguments and printing,
over plugin files.

  merge(request) -> result

`merge` takes one request, a table of plain data, and returns one result, a table of plain data:
everything a person at a terminal would have been shown or could have read in the log, and
nothing worded or laid out for one. It opens the plugin and the master, reads the plugin's other
masters from the master's folder, calls @merge-to-master, and writes the merged master over the
master, as merge_to_master 0.9.5 does:

  * the plugin's other masters are the files of those names beside the master, read for their
    dialogue only. merge_to_master is a Windows program and finds them whatever their case; so
    does this, taking the exact name first. The master itself is the file the request names,
    whatever the plugin calls it;
  * unless `overwrite` is set, the master is first moved to
    backups/merge_to_master/<stem>.<NNN>.<extension> beside it, NNN one more than the highest
    number a backup of that name has there, from 000. A master without an extension can't be
    backed up, and is then left as it was;
  * the merged master is written with its header counting its records, as tes3 writes it;
  * the log is the lines merge_to_master writes to merge_to_master.log. `log` in the request
    names a file to write them to; the result has them either way.

Nothing here reads an argument list, the environment, or standard input, and nothing prints. A
master that isn't beside the master, and a backup that can't be made, are outcomes in the result,
and nothing is written then. A request that can't be carried out at all raises its reason as a
string: a plugin or master that isn't a file or can't be read as a plugin. With `dryRun`,
everything is read and merged and nothing is written or moved: `backup` is where the master
would go.

The port's differences from merge_to_master are @merge-to-master's: references and textures are
numbered, and the log's lines written, in the order of the plugin's records instead of a hash
map's. A file's records are read as @tes3conv reads them, sorted as tes3conv writes them, so
that is the order: the same for every file holding those records.
]]

local core = require '@tes3'
local fs = require '@dream/fs'
local mergeToMaster = require '@merge-to-master'
local tes3 = require '@tes3conv/records'
local tes3conv = require '@tes3conv'

type Records = tes3.Records

export type MergeRequest = {
  --- The plugin whose contents are merged into the master: a file.
  plugin: string,
  --- The master it is merged into, and the file the merge is written over.
  master: string,
  --- Remove every object marked deleted, and the master's own references to one.
  removeDeleted: boolean?,
  --- Write over the master without keeping a backup of it.
  overwrite: boolean?,
  --- Read and merge, and write nothing.
  dryRun: boolean?,
  --- A file to write the log to: merge_to_master's is merge_to_master.log in the current folder.
  log: string?,
}

--- One of the plugin's other masters: the name the plugin has for it, and the file read.
export type MasterRead = { name: string, path: string }

--- Records, headers aside: the plugin's, the master's as it was, and the merged master's.
export type RecordCounts = { plugin: number, master: number, merged: number }

export type Outcome = 'merged' | 'missingMasters' | 'backupFailed'

export type MergeResult = {
  command: 'merge',
  --- `merged`: the merge was written over the master, or with `dryRun` would have been.
  --- `missingMasters`: the plugin names masters that aren't beside the master (`missing`).
  --- `backupFailed`: the master couldn't be backed up (`backupProblem`), and is as it was.
  outcome: Outcome,
  plugin: string,
  --- The master's path: the file the merge was written over when `written`.
  master: string,
  dryRun: boolean,
  written: boolean,
  --- Where the master as it was went, or with `dryRun` would go. Nil with `overwrite`.
  backup: string?,
  backupProblem: string?,
  --- The plugin's other masters whose dialogue was read, in the plugin's order.
  masters: { MasterRead },
  --- Those not found beside the master, by the names the plugin has for them.
  missing: { string },
  --- Nil unless the outcome is `merged`, as `summary` is.
  records: RecordCounts?,
  summary: mergeToMaster.Summary?,
  --- merge_to_master.log, line by line, as far as the command got.
  log: { string },
  --- The file the log was written to: the request's `log`, unless this was a dry run.
  logFile: string?,
}

local commands = {}

-- The folder merge_to_master names after its executable, under `backups` beside the master.
local BackupFolder = 'merge_to_master'

--- A plugin file's bytes, or the reason it can't be merged, raised.
local function contents(path: string, role: string): buffer
  if not jess.fs.isFile(path) then error(`the {role} '{path}' isn't a file`, 0) end

  local bytes = jess.fs.readBuffer(path)

  if not bytes then error(`the {role} '{path}' can't be read`, 0) end

  return bytes
end

--- merge_to_master's `from_path_dialogue_only`: of a master that isn't the target, the header
--- and the dialogue.
local function dialogueOnly(tag: string): core.Keep
  return if tag == 'TES3' or tag == 'DIAL' or tag == 'INFO' then 'whole' else 'skip'
end

--- The file `name` in `folder`: the one spelled exactly so, else the first in the folder's
--- listing that differs only in case.
local function beside(folder: string, name: string): string?
  local exact = jess.fs.join(folder, name)

  if jess.fs.isFile(exact) then return exact end

  local lowered = string.lower(name)

  -- A master named without a folder is in the current one.
  for _, entry in fs.list(if folder == '' then '.' else folder) or {} do
    if string.lower(entry) ~= lowered then continue end

    local path = jess.fs.join(folder, entry)

    if jess.fs.isFile(path) then return path end
  end

  return nil
end

--- A file name's stem and extension as Rust's `Path` splits them: at the last dot, unless the
--- only one is the first character.
local function split(name: string): (string, string?)
  local stem, extension = string.match(name, '^(.+)%.([^.]*)$')

  if not stem then return name, nil end

  return stem, extension
end

--- The number of a backup of the master named `entry`: what is between the stem and the
--- extension, dots aside, when that is a number.
local function backupNumber(entry: string, stem: string, extension: string): number?
  if string.sub(entry, 1, #stem) ~= stem then return nil end

  local rest = string.sub(entry, #stem + 1)

  if #rest < #extension or string.sub(rest, #rest - #extension + 1) ~= extension then return nil end

  local digits = string.match(string.sub(rest, 1, #rest - #extension), '^%.*(%+?%d+)%.*$')

  return digits and tonumber(digits)
end

type Backup = { folder: string, path: string }

--- merge_to_master's `backup`, as far as naming the file: where the master's backup goes, or
--- why it has nowhere to go. Nothing is made or moved.
local function backupPlace(master: string): (Backup?, string?)
  local parent = jess.fs.parent(master) or ''
  local stem, extension = split(jess.fs.fileName(master) or '')

  if not extension then return nil, `'{master}' has no extension to number a backup before` end

  local folder = jess.fs.join(parent, 'backups', BackupFolder)
  local highest: number? = nil

  if jess.fs.isDir(folder) then
    local entries, message = fs.list(folder)

    if not entries then return nil, message or `'{folder}' can't be listed` end

    for _, entry in entries do
      local number = backupNumber(entry, stem, extension)

      if number and (not highest or number > highest) then highest = number end
    end
  end

  local number = if highest then highest + 1 else 0
  local path = jess.fs.join(folder, string.format('%s.%03d.%s', stem, number, extension))

  if jess.fs.exists(path) then return nil, `'{path}' is already there` end

  return { folder = folder, path = path }, nil
end

--- Moves the master to its backup; nil, or why it couldn't be.
local function moveToBackup(master: string, {folder, path}: Backup, log: { string }): string?
  table.insert(log, `Creating backup directory: {folder}`)
  local made, unmade = fs.mkdir(folder, { recursive = true })

  if not made then return unmade or `'{folder}' can't be made` end

  table.insert(log, 'Finding next available backup file name...')
  table.insert(log, `Creating backup file: {path}`)
  local moved, unmoved = fs.rename(master, path)

  if not moved then return unmoved or `'{master}' can't be moved to '{path}'` end

  return nil
end

--- Writes the log where the request names, as merge_to_master creates its own: in a folder that
--- is there, over the one already there.
local function writeLog(request: MergeRequest, result: MergeResult)
  if not request.log or result.dryRun then return end

  local written, message = fs.writeFile(request.log, table.concat(result.log, '\n') .. '\n')

  if not written then error(message or `the log '{request.log}' can't be written`, 0) end

  result.logFile = request.log
end

--- The merged master as merge_to_master saves it: tes3 counts the records into the header.
local function saved(records: Records): buffer
  local plugin = tes3conv.plugin(records)
  plugin:updateRecordCount()
  return plugin:save()
end

function commands.merge(request: MergeRequest): MergeResult
  local dryRun = request.dryRun == true
  local log = { 'Merging plugins...' }
  local result: MergeResult = {
    command = 'merge',
    outcome = 'merged',
    plugin = request.plugin,
    master = request.master,
    dryRun = dryRun,
    written = false,
    masters = {},
    missing = {},
    log = log,
  }

  local plugin = tes3conv.records(core.open(contents(request.plugin, 'plugin')))
  local masterBytes = contents(request.master, 'master')
  local masterName = jess.fs.fileName(request.master) or request.master
  local folder = jess.fs.parent(request.master) or ''
  local others: { [string]: Records } = {}

  for _, entry in ((plugin[1].masters or {}) :: unknown) :: { { string | number } } do
    local name = tostring(entry[1])
    local key = string.lower(name)

    if key == string.lower(masterName) or others[key] then continue end

    local path = beside(folder, name)

    if not path then
      table.insert(result.missing, name)
      continue
    end

    others[key] = tes3conv.records(core.open(contents(path, 'master'), { keep = dialogueOnly }))
    table.insert(result.masters, { name = name, path = path })
  end

  if #result.missing > 0 then
    result.outcome = 'missingMasters'
    writeLog(request, result)
    return result
  end

  local master = tes3conv.records(core.open(masterBytes))
  local merged, summary = mergeToMaster.merge(plugin, master, {
    masterName = masterName,
    masters = others,
    removeDeleted = request.removeDeleted,
    log = log,
  })
  local data = saved(merged)
  result.records = { plugin = #plugin - 1, master = #master - 1, merged = #merged - 1 }
  result.summary = summary

  local backup: Backup? = nil

  if not request.overwrite then
    local problem: string?
    backup, problem = backupPlace(request.master)

    if not backup then
      if not dryRun then table.insert(log, 'Creating backup...') end

      result.outcome, result.backupProblem = 'backupFailed', problem
      writeLog(request, result)
      return result
    end

    result.backup = backup.path
  end

  if dryRun then return result end

  table.insert(log, 'Creating backup...')

  if backup then
    local problem = moveToBackup(request.master, backup, log)

    if problem then
      result.outcome, result.backup, result.backupProblem = 'backupFailed', nil, problem
      writeLog(request, result)
      return result
    end
  end

  table.insert(log, 'Saving results...')

  -- merge_to_master creates the master anew where the backup left none, and writes over it in
  -- place with --overwrite. Should that fail, the backup is moved back before the reason goes
  -- on, so a failed merge doesn't leave the folder without its master.
  local wrote, failure = fs.writeFile(request.master, data)

  if not wrote then
    if backup then fs.rename(backup.path, request.master) end

    error(failure or `the master '{request.master}' can't be written`, 0)
  end

  table.insert(log, 'Finished!')
  result.written = true
  writeLog(request, result)
  return result
end

return table.freeze(commands)
