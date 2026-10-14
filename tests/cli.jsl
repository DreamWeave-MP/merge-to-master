--!strict
--!native
-- `@merge-to-master/cli`: the argument lists it reads into `commands.merge`'s request and the
-- ones it refuses and why, the text it makes of a result built here by hand, the exit status of
-- each outcome, and whole runs on plugin files in the scratch root. A run's messages go to the
-- suite's own standard error.
local cli = require '@merge-to-master/cli'
local commands = require '@merge-to-master/commands'
local support = require './support'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()

local Log = './merge_to_master.log'

-- Each argument list `parse` refuses, and what it says of it: merge_to_master's own words.
local Refused: { { argv: { string }, message: string } } = {
  {
    argv = { '--remove-deleted' },
    message = 'the following required arguments were not provided: <PLUGIN> <MASTER>',
  },
  {
    argv = { 'Plugin.esp' },
    message = 'the following required arguments were not provided: <MASTER>',
  },
  {
    argv = { '-o', 'Plugin.esp' },
    message = 'the following required arguments were not provided: <MASTER>',
  },
  {
    argv = { 'Plugin.esp', 'Master.esm', 'Other.esm' },
    message = 'unexpected argument \'Other.esm\' found',
  },
  {
    argv = { 'Plugin.esp', 'Master.esm', '--', '--overwrite' },
    message = 'unexpected argument \'--overwrite\' found',
  },
  { argv = { '--bogus', 'Plugin.esp', 'Master.esm' }, message = 'unexpected argument \'--bogus\' found' },
  { argv = { 'Plugin.esp', 'Master.esm', '--dry-run' }, message = 'unexpected argument \'--dry-run\' found' },
  { argv = { 'Plugin.esp', 'Master.esm', '-x' }, message = 'unexpected argument \'-x\' found' },
  { argv = { 'Plugin.esp', 'Master.esm', '-rx' }, message = 'unexpected argument \'-x\' found' },
  { argv = { 'Plugin.esp', 'Master.esm', '-R' }, message = 'unexpected argument \'-R\' found' },
  { argv = { 'Plugin.esp', 'Master.esm', '-v' }, message = 'unexpected argument \'-v\' found' },
  { argv = { '--Overwrite', 'Plugin.esp', 'Master.esm' }, message = 'unexpected argument \'--Overwrite\' found' },
  { argv = { '--bogus', '--help' }, message = 'unexpected argument \'--bogus\' found' },
  {
    argv = { 'Plugin.esp', 'Master.esm', '--overwrite=true' },
    message = 'unexpected value \'true\' for \'--overwrite\' found; no more were expected',
  },
  {
    argv = { 'Plugin.esp', 'Master.esm', '--remove-deleted=' },
    message = 'unexpected value \'\' for \'--remove-deleted\' found; no more were expected',
  },
  {
    argv = { 'Plugin.esp', 'Master.esm', '-r=1' },
    message = 'unexpected value \'1\' for \'--remove-deleted\' found; no more were expected',
  },
  {
    argv = { '-o', 'Plugin.esp', 'Master.esm', '--overwrite' },
    message = 'the argument \'--overwrite\' cannot be used multiple times',
  },
  {
    argv = { '-rr', 'Plugin.esp', 'Master.esm' },
    message = 'the argument \'--remove-deleted\' cannot be used multiple times',
  },
}

local Backup = 'mods/backups/merge_to_master/Master.000.esm'

--- A result as `commands.merge` returns one, with `fields` over a merge that was written with
--- no backup kept and no log file named.
local function result(fields: { [string]: unknown }?): commands.MergeResult
  local built: { [string]: unknown } = {
    command = 'merge',
    outcome = 'merged',
    plugin = 'mods/Plugin.esp',
    master = 'mods/Master.esm',
    dryRun = false,
    written = true,
    masters = {},
    missing = {},
    records = { plugin = 1, master = 1, merged = 2 },
    summary = { merged = 0, copied = 1, texturesRemapped = 0, objectsRemoved = 0, referencesRemoved = 0 },
    log = { 'Merging plugins...' },
  }

  for key, value in fields or {} do
    built[key] = value
  end

  return (built :: unknown) :: commands.MergeResult
end

suite.describe('parse', function()
  suite.it('reads the plugin and then the master, and leaves unset the flags it wasn\'t given', function()
    local command, message = cli.parse { 'Plugin.esp', 'Master.esm' }
    expect(command).toEqual {
      action = 'merge',
      request = { plugin = 'Plugin.esp', master = 'Master.esm', log = Log },
    }
    expect(message).toBeNil()
  end)

  suite.it('maps each flag onto the request, under either spelling', function()
    local long = cli.parse { '--remove-deleted', '--overwrite', 'Plugin.esp', 'Master.esm' }
    local short = cli.parse { '-r', '-o', 'Plugin.esp', 'Master.esm' }
    local wanted = {
      action = 'merge',
      request = {
        plugin = 'Plugin.esp',
        master = 'Master.esm',
        removeDeleted = true,
        overwrite = true,
        log = Log,
      },
    }

    expect(long).toEqual(wanted)
    expect(short).toEqual(wanted)
  end)

  suite.it('takes one flag alone', function()
    expect(cli.parse { '-r', 'Plugin.esp', 'Master.esm' }).toEqual {
      action = 'merge',
      request = { plugin = 'Plugin.esp', master = 'Master.esm', removeDeleted = true, log = Log },
    }

    expect(cli.parse { 'Plugin.esp', 'Master.esm', '--overwrite' }).toEqual {
      action = 'merge',
      request = { plugin = 'Plugin.esp', master = 'Master.esm', overwrite = true, log = Log },
    }
  end)

  suite.it('takes flags sharing a dash, and flags before, between, and after the arguments', function()
    local wanted = {
      action = 'merge',
      request = {
        plugin = 'Plugin.esp',
        master = 'Master.esm',
        removeDeleted = true,
        overwrite = true,
        log = Log,
      },
    }

    expect(cli.parse { '-ro', 'Plugin.esp', 'Master.esm' }).toEqual(wanted)
    expect(cli.parse { 'Plugin.esp', '-or', 'Master.esm' }).toEqual(wanted)
    expect(cli.parse { 'Plugin.esp', '-o', 'Master.esm', '-r' }).toEqual(wanted)
  end)

  suite.it('takes what follows -- as it is spelled, and a lone dash as an argument', function()
    expect(cli.parse { '-o', '--', '-Plugin.esp', '--overwrite' }).toEqual {
      action = 'merge',
      request = { plugin = '-Plugin.esp', master = '--overwrite', overwrite = true, log = Log },
    }

    expect(cli.parse { '-', 'Master.esm' }).toEqual {
      action = 'merge',
      request = { plugin = '-', master = 'Master.esm', log = Log },
    }
  end)

  suite.it('keeps the arguments\' paths as they are given', function()
    local command = cli.parse { 'mods/My Plugin.esp', '/data/Data Files/Master.esm' }
    expect(command).toEqual {
      action = 'merge',
      request = { plugin = 'mods/My Plugin.esp', master = '/data/Data Files/Master.esm', log = Log },
    }
  end)

  suite.it('puts the log in the folder it is given in place of the current one', function()
    local command = cli.parse({ 'Plugin.esp', 'Master.esm' }, 'work')
    expect(command).toEqual {
      action = 'merge',
      request = {
        plugin = 'Plugin.esp',
        master = 'Master.esm',
        log = jess.fs.join('work', 'merge_to_master.log'),
      },
    }
  end)

  suite.it('reads help and version under each spelling, wherever nothing before them is refused', function()
    for _, argv in { { '--help' }, { '-h' }, { 'Plugin.esp', '-h' }, { '-rh' }, { '-h', '--bogus' } } do
      local command, message = cli.parse(argv)
      expect(command).toEqual { action = 'help' }
      expect(message).toBeNil()
    end

    for _, argv in { { '--version' }, { '-V' }, { '-oV', 'Plugin.esp' }, { '-V', '-h' } } do
      local command, message = cli.parse(argv)
      expect(command).toEqual { action = 'version' }
      expect(message).toBeNil()
    end
  end)

  suite.it('reads no arguments at all as a call for the usage', function()
    local command, message = cli.parse {}
    expect(command).toEqual { action = 'usage' }
    expect(message).toBeNil()
  end)

  suite.it('refuses what it can\'t read, in merge_to_master\'s words', function()
    for _, case in Refused do
      local command, message = cli.parse(case.argv)
      expect(command).toBeNil()
      expect(message).toBe(case.message)
    end
  end)

  suite.it('leaves the argument list as it was', function()
    local argv = { '-r', 'Plugin.esp', '--', 'Master.esm' }
    cli.parse(argv)
    expect(argv).toEqual { '-r', 'Plugin.esp', '--', 'Master.esm' }
  end)
end)

suite.describe('render', function()
  suite.it('ends a merge as merge_to_master does', function()
    expect(cli.render(result { backup = Backup, logFile = Log })).toBe(
      'Merge Successful: mods/Master.esm\nLog available at: ./merge_to_master.log'
    )
  end)

  suite.it('names no log when none was written', function()
    expect(cli.render(result { backup = Backup })).toBe 'Merge Successful: mods/Master.esm'
  end)

  suite.it('says a dry run wrote nothing, and where the backup would go', function()
    local dry = result { dryRun = true, written = false, backup = Backup }
    expect(cli.render(dry)).toBe(
      `Dry run, nothing written: mods/Master.esm\nBackup would be: {Backup}`
    )

    local overwriting = result { dryRun = true, written = false }
    expect(cli.render(overwriting)).toBe 'Dry run, nothing written: mods/Master.esm'
  end)

  suite.it('names the masters that weren\'t beside the master', function()
    local missing = result {
      outcome = 'missingMasters',
      written = false,
      missing = { 'Morrowind.esm', 'Tribunal.esm' },
      logFile = Log,
    }

    expect(cli.render(missing)).toBe(
      'merge-to-master: \'mods/Plugin.esp\' names masters that aren\'t beside \'mods/Master.esm\': Morrowind.esm, Tribunal.esm'
    )
  end)

  suite.it('says the backup failed in merge_to_master\'s words, and why', function()
    local failed = result {
      outcome = 'backupFailed',
      written = false,
      backupProblem = '\'mods/Master\' has no extension to number a backup before',
    }

    expect(cli.render(failed)).toBe(
      'merge-to-master: Failed to create backup. \'mods/Master\' has no extension to number a backup before'
    )
  end)
end)

suite.describe('status', function()
  suite.it('is 0 for a merge, written or dry, and 9 for one that stopped', function()
    expect(cli.status(result())).toBe(0)
    expect(cli.status(result { dryRun = true, written = false })).toBe(0)
    expect(cli.status(result { outcome = 'missingMasters', written = false })).toBe(9)
    expect(cli.status(result { outcome = 'backupFailed', written = false })).toBe(9)
  end)
end)

suite.describe('run', function()
  suite.it(
    'numbers its exit statuses as Jess\'s other commands do',
    function() expect(cli.Exit).toEqual { ok = 0, invalidInput = 8, runtime = 9 } end
  )

  suite.it('returns 0 for help and for the version', function()
    expect(cli.run { '--help' }).toBe(0)
    expect(cli.run { '-h' }).toBe(0)
    expect(cli.run { '--version' }).toBe(0)
    expect(cli.run { '-V' }).toBe(0)
  end)

  suite.it('returns 8 for no arguments, and for every command line parse refuses', function()
    expect(cli.run {}).toBe(8)

    for _, case in Refused do
      expect(cli.run(case.argv)).toBe(8)
    end
  end)

  suite.it('returns 8 for an argument that isn\'t a file, and writes nothing', function()
    local folder = support.folder 'cli-not-files'
    local plugin, master = support.pair(folder)
    local missing = jess.fs.join(folder, 'Nothing.esp')
    local before = support.bytes(master)

    expect(cli.run({ missing, master }, folder)).toBe(8)
    expect(cli.run({ plugin, folder }, folder)).toBe(8)
    expect(cli.run({ plugin, jess.fs.join(folder, 'Nothing.esm'), '-o' }, folder)).toBe(8)
    expect(support.bytes(master) == before).toBe(true)
    expect(jess.fs.isDir(jess.fs.join(folder, 'backups'))).toBe(false)
    expect(jess.fs.exists(jess.fs.join(folder, 'merge_to_master.log'))).toBe(false)
  end)

  suite.it('merges, backs the master up, writes the log, and returns 0', function()
    local folder = support.folder 'cli-merge'
    local plugin, master = support.pair(folder)
    local before = support.bytes(master)
    local backup = jess.fs.join(folder, 'backups', 'merge_to_master', 'Master.000.esm')

    expect(cli.run({ plugin, master }, folder)).toBe(0)
    expect(support.bytes(backup) == before).toBe(true)
    expect(support.chain(support.read(master))).toEqual { 'I1<|I3>', 'I3<I1|I2>', 'I2<I3|>' }

    local log = support.bytes(jess.fs.join(folder, 'merge_to_master.log'))
    expect(string.sub(log, 1, 19)).toBe 'Merging plugins...\n'
    expect(string.sub(log, -11)).toBe '\nFinished!\n'
    expect(log).toContain(`Creating backup file: {backup}\n`)
  end)

  suite.it('removes deleted objects with -r and keeps no backup with -o', function()
    local folder = support.folder 'cli-flags'
    local master = support.write(folder, 'Master.esm', {
      support.header({}, { fileType = 'Esm' }),
      support.static 'Rock',
      support.static 'Tree',
    })

    local plugin = support.write(folder, 'Plugin.esp', {
      support.header { { 'Master.esm', 1 } },
      support.static('rock', '', 'DELETED'),
    })

    expect(cli.run({ '-ro', plugin, master }, folder)).toBe(0)
    expect(support.labels(support.read(master))).toEqual { 'Static:Tree' }
    expect(jess.fs.isDir(jess.fs.join(folder, 'backups'))).toBe(false)
  end)

  suite.it('returns 9 for a master of the plugin\'s that isn\'t there, the master as it was', function()
    local folder = support.folder 'cli-missing-master'
    local master =
      support.write(folder, 'Master.esm', { support.header({}, { fileType = 'Esm' }), support.static 'Rock' })
    local plugin = support.write(folder, 'Plugin.esp', {
      support.header { { 'Gone.esm', 1 }, { 'Master.esm', 1 } },
      support.static 'Tree',
    })
    local before = support.bytes(master)

    expect(cli.run({ plugin, master }, folder)).toBe(9)
    expect(support.bytes(master) == before).toBe(true)
    expect(jess.fs.isDir(jess.fs.join(folder, 'backups'))).toBe(false)
  end)

  suite.it('returns 9 for a file that isn\'t a plugin', function()
    local folder = support.folder 'cli-not-a-plugin'
    local _, master = support.pair(folder)
    local text = jess.fs.join(folder, 'Notes.esp')
    jess.fs.write(text, 'not a plugin at all', { backup = false })
    local before = support.bytes(master)

    expect(cli.run({ text, master }, folder)).toBe(9)
    expect(support.bytes(master) == before).toBe(true)
  end)
end)

return suite
