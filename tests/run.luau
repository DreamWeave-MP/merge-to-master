--!strict
--!native
-- The merge_to_master port's semantics the Starwind build depends on, on records small enough to
-- read.
local mergeToMaster = require '@merge-to-master'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = { [string | number]: any }

local function header(masters: { { string | number } }?): Record
  return {
    type = 'Header',
    flags = '',
    version = 1.3,
    fileType = 'Esp',
    author = '',
    description = '',
    numObjects = 0,
    masters = masters or {},
  }
end

local function dial(id: string, kind: string?): Record
  return { type = 'Dialogue', flags = '', id = id, dialogueType = kind or 'Topic' }
end

local function info(id: string, prev: string?, next: string?, fields: Record?): Record
  local record: Record = {
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

  for key, value in fields or {} do
    record[key] = value
  end

  return record
end

local function ids(records: { Record }): { string }
  return [
    for record in records
    if record.type ~= 'Header'
    => `{record.type}:{record.id or record.name or record.effectId}`
  ]
end

local function chain(records: { Record }): { string }
  return [
    for record in records
    if record.type == 'DialogueInfo'
    => `{record.id}<{record.prevId}|{record.nextId}>`
  ]
end

suite.describe('merge-to-master', function()
  local function npc(id: string): Record return { type = 'Npc', flags = '', id = id, name = id } end

  suite.it(
    'remaps the plugin\'s masters and renumbers its own references after the master\'s',
    function()
      local master = {
        header { { 'A.esm', 1 }, { 'D.esm', 1 } },
        {
          type = 'Cell',
          flags = '',
          name = 'Hall',
          data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
          references = { { mastIndex = 0, refrIndex = 41, id = 'old', temporary = true } },
        },
      }

      local plugin = {
        header { { 'A.esm', 1 }, { 'B.esp', 1 }, { 'C.esm', 1 } },
        {
          type = 'Cell',
          flags = '',
          name = 'Hall',
          data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
          references = {
            { mastIndex = 0, refrIndex = 1, id = 'new', temporary = true },
            { mastIndex = 2, refrIndex = 5, id = 'target', temporary = true },
            { mastIndex = 3, refrIndex = 7, id = 'third', temporary = true },
          },
        },
      }

      local merged = mergeToMaster.merge(plugin, master, {
        masterName = 'B.esp',
        masters = { ['a.esm'] = { header() }, ['c.esm'] = { header() } },
      })
      expect([for entry in merged[1].masters => entry[1]]).toEqual { 'A.esm', 'D.esm', 'C.esm' }
      local references = {}

      for _, reference in merged[2].references do
        references[reference.id] = `{reference.mastIndex}:{reference.refrIndex}`
      end

      expect(references).toEqual { old = '0:41', new = '0:42', target = '0:5', third = '3:7' }
    end
  )

  suite.it('places INFOs after their previous INFO and repairs the links between', function()
    local master = { header(), dial 'Topic', info('I1', '', 'I2'), info('I2', 'I1', '') }
    local plugin = {
      header { { 'Master.esm', 1 } },
      dial 'Topic',
      info('I3', 'I1', 'I2'),
      info('I0', '', ''),
      info('I9', 'missing', ''),
    }
    local merged = mergeToMaster.merge(plugin, master, { masterName = 'Master.esm' })
    expect(chain(merged)).toEqual { 'I0<|I1>', 'I1<I0|I3>', 'I3<I1|I2>', 'I2<I3|I9>', 'I9<I2|>' }
  end)

  suite.it(
    'keys the item and actor families together, and keeps only the master dialogue it merged',
    function()
      local master = { header { { 'Base.esm', 1 } }, { type = 'Creature', flags = '', id = 'Foo' } }
      local plugin = {
        header { { 'Base.esm', 1 }, { 'Master.esm', 1 } },
        npc 'foo',
        dial('Greeting 0', 'Greeting'),
        info('G1', 'V1', ''),
      }
      local base = { header(), dial('Greeting 0', 'Greeting'), info('V1', '', '') }
      local merged = mergeToMaster.merge(
        plugin,
        master,
        { masterName = 'Master.esm', masters = { ['base.esm'] = base } }
      )
      expect(ids(merged)).toEqual { 'Npc:foo', 'Dialogue:Greeting 0', 'DialogueInfo:G1' }
      expect(chain(merged)).toEqual { 'G1<V1|>' }
    end
  )

  suite.it('writes types in order, ids sorted, journals before other topics', function()
    local master = { header(), dial('b', 'Topic'), dial('a', 'Topic'), dial('z', 'Journal') }
    local plugin = {
      header { { 'Master.esm', 1 } },
      { type = 'Static', flags = '', id = 'b_rock', mesh = '' },
      { type = 'Static', flags = '', id = 'B_rock2', mesh = '' },
      { type = 'GameSetting', flags = '', id = 'sZ', value = { type = 'String', data = '' } },
    }
    local merged = mergeToMaster.merge(plugin, master, { masterName = 'Master.esm' })
    expect(ids(merged)).toEqual {
      'GameSetting:sZ',
      'Static:B_rock2',
      'Static:b_rock',
      'Dialogue:z',
      'Dialogue:a',
      'Dialogue:b',
    }
  end)
end)

return suite
