--!strict
-- What the command suites share: records small enough to read, written as plugin files into a
-- folder of the scratch root that each case has to itself, and read back from them.
local core = require '@tes3'
local fs = require '@dream/fs'
local tes3conv = require '@tes3conv'

export type Record = { [string | number]: any }

local scratch =
  assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')

local support = {}

--- An empty folder `name` under the scratch root. The suite runs once from the source and once
--- from the packed package, so what the run before left there is removed first.
function support.folder(name: string): string
  local path = jess.fs.join(scratch, name)

  if jess.fs.exists(path) then assert(fs.remove(path, { recursive = true })) end

  jess.fs.createDir(path)
  return path
end

function support.header(masters: { { string | number } }?, fields: Record?): Record
  local record: Record = {
    type = 'Header',
    flags = '',
    version = string.unpack('<f', string.pack('<f', 1.3)),
    fileType = 'Esp',
    author = '',
    description = '',
    numObjects = 0,
    masters = masters or {},
  }

  for key, value in fields or {} do
    record[key] = value
  end

  return record
end

function support.static(id: string, mesh: string?, flags: string?): Record
  return { type = 'Static', flags = flags or '', id = id, mesh = mesh or '' }
end

function support.reference(master: number, index: number, id: string, fields: Record?): Record
  local value: Record = {
    mastIndex = master,
    refrIndex = index,
    id = id,
    temporary = true,
    translation = { 0, 0, 0 },
    rotation = { 0, 0, 0 },
  }

  for key, item in fields or {} do
    value[key] = item
  end

  return value
end

function support.cell(name: string, references: { Record }?): Record
  return {
    type = 'Cell',
    flags = '',
    name = name,
    data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
    references = references or {},
  }
end

function support.dial(id: string, kind: string?): Record
  return { type = 'Dialogue', flags = '', id = id, dialogueType = kind or 'Topic' }
end

function support.info(id: string, prev: string?, next: string?): Record
  return {
    type = 'DialogueInfo',
    flags = '',
    id = id,
    prevId = prev or '',
    nextId = next or '',
    speakerId = '',
    speakerRace = '',
    speakerClass = '',
    speakerFaction = '',
    speakerCell = '',
    playerFaction = '',
    soundPath = '',
    text = '',
    scriptText = '',
    filters = {},
    data = {
      dialogueType = 'Topic',
      disposition = 0,
      speakerRank = -1,
      speakerSex = 'Any',
      playerRank = -1,
    },
  }
end

function support.texture(id: string, index: number): Record
  return { type = 'LandscapeTexture', flags = '', id = id, index = index, fileName = `{id}.dds` }
end

--- Writes `records` as the plugin file `name` in `folder`, its header counting them as tes3
--- counts them when it saves; returns the file's path.
function support.write(folder: string, name: string, records: { Record }): string
  local plugin = tes3conv.plugin(records)
  plugin:updateRecordCount()
  local path = jess.fs.join(folder, name)
  jess.fs.write(path, plugin:save(), { backup = false })
  return path
end

--- A plugin file's records, as `@tes3conv` reads them.
function support.read(path: string): { Record }
  local bytes = assert(jess.fs.readBuffer(path), `'{path}' isn't there`)
  return tes3conv.records(core.open(bytes))
end

--- A file's bytes, as a string two of which compare.
function support.bytes(path: string): string
  local bytes = assert(jess.fs.read(path), `'{path}' isn't there`)
  return bytes
end

--- What tells a record apart: its type, and the id or name it goes by.
function support.labels(records: { Record }): { string }
  return [for record in records if record.type ~= 'Header' => `{record.type}:{record.id or record.name}`]
end

--- Each reference of a cell's: its master and index, by its id.
function support.placed(cell: Record): { [string]: string }
  local at = {}

  for _, item in cell.references do
    at[item.id] = `{item.mastIndex}:{item.refrIndex}`
  end

  return at
end

--- Each INFO's place in its chain: its id, and the ids it names before and after.
function support.chain(records: { Record }): { string }
  return [
    for record in records
    if record.type == 'DialogueInfo'
    => `{record.id}<{record.prevId}|{record.nextId}>`
  ]
end

--- The first record of a type, with the id or name given if one is.
function support.find(records: { Record }, kind: string, id: string?): Record
  for _, record in records do
    if record.type ~= kind then continue end

    if not id or record.id == id or record.name == id then return record end
  end

  error(`no {kind} {id or ''}`)
end

--- A master with a rock, a hall holding it, and a topic of two INFOs; and a plugin made on it
--- with a tree, its own rock, the hall with the tree in it and the rock moved, and an INFO
--- between the master's two. Returns the plugin's path, then the master's.
function support.pair(folder: string): (string, string)
  local master = support.write(folder, 'Master.esm', {
    support.header({}, { fileType = 'Esm', author = 'theirs' }),
    support.static('Rock', 'rock.nif'),
    support.cell('Hall', { support.reference(0, 41, 'Rock') }),
    support.dial 'Topic',
    support.info('I1', '', 'I2'),
    support.info('I2', 'I1', ''),
  })

  local plugin = support.write(folder, 'Plugin.esp', {
    support.header { { 'Master.esm', 1 } },
    support.static 'Tree',
    support.static('rock', 'boulder.nif'),
    support.cell('Hall', {
      support.reference(0, 1, 'Tree'),
      support.reference(1, 41, 'Rock', { translation = { 1, 2, 3 } }),
    }),
    support.dial 'Topic',
    support.info('I3', 'I1', 'I2'),
  })

  return plugin, master
end

return support
