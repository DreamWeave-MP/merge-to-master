--!strict
--!native
-- `merge` on the rest of what its header documents: the masters it is given, the objects, cells,
-- textures, and dialogue it merges, `removeDeleted`, the order it writes, and its records through
-- `@tes3conv` into a plugin.
local mergeToMaster = require '@merge-to-master'
local tes3conv = require '@tes3conv'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = { [string | number]: any }

local function header(masters: { { string | number } }?, fields: Record?): Record
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

local function static(id: string, mesh: string?, flags: string?): Record
  return { type = 'Static', flags = flags or '', id = id, mesh = mesh or '' }
end

local function reference(master: number, index: number, id: string, fields: Record?): Record
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

local function cell(name: string, references: { Record }?, fields: Record?): Record
  local record: Record = {
    type = 'Cell',
    flags = '',
    name = name,
    data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
    references = references or {},
  }

  for key, value in fields or {} do
    record[key] = value
  end

  return record
end

local function dial(id: string, kind: string?): Record
  return { type = 'Dialogue', flags = '', id = id, dialogueType = kind or 'Topic' }
end

local function info(id: string, prev: string?, next: string?, text: string?): Record
  return {
    type = 'DialogueInfo',
    flags = '',
    id = id,
    prevId = prev or '',
    nextId = next or '',
    text = text or '',
  }
end

local function texture(id: string, index: number): Record
  return { type = 'LandscapeTexture', flags = '', id = id, index = index, fileName = `{id}.dds` }
end

--- What tells a merged record apart: its type, and the id, cell, or name it goes by.
local function labels(records: { Record }): { string }
  local list = {}

  for _, record in records do
    if record.type ~= 'Header' then
      table.insert(list, `{record.type}:{record.id or record.cell or record.name}`)
    end
  end

  return list
end

--- The first record of a type, with the id or name given if one is.
local function find(records: { Record }, kind: string, id: string?): Record
  for _, record in records do
    if record.type ~= kind then continue end

    if not id or record.id == id or record.name == id then return record end
  end

  error(`no {kind} {id or ''}`)
end

--- Each reference's master and index, by its id.
local function placed(record: Record): { [string]: string }
  local at = {}

  for _, item in record.references do
    at[item.id] = `{item.mastIndex}:{item.refrIndex}`
  end

  return at
end

local function chain(records: { Record }): { string }
  local list = {}

  for _, record in records do
    if record.type == 'DialogueInfo' then
      table.insert(list, `{record.id}<{record.prevId}|{record.nextId}>`)
    end
  end

  return list
end

local Mastered = { masterName = 'Master.esm' }

suite.describe('masters', function()
  suite.it('returns the master\'s header, not the plugin\'s', function()
    local master = { header({}, { fileType = 'Esm', author = 'theirs' }), static 'Rock' }
    local plugin = { header({ { 'Master.esm', 1 } }, { author = 'mine' }), static 'Tree' }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(merged[1].type).toBe 'Header'
    expect(merged[1].fileType).toBe 'Esm'
    expect(merged[1].author).toBe 'theirs'
    expect(merged[1].masters).toEqual {}
    expect(master[1].masters).toEqual {}
    expect(plugin[1].masters).toEqual { { 'Master.esm', 1 } }
  end)

  suite.it('finds the master among the plugin\'s without regard to case', function()
    local master = { header(), cell('Hall', { reference(0, 4, 'old') }) }
    local plugin = {
      header { { 'MASTER.ESM', 1 } },
      cell('Hall', { reference(1, 4, 'theirs'), reference(0, 1, 'mine') }),
    }
    local merged = mergeToMaster.merge(plugin, master, { masterName = 'master.esm' })
    expect(merged[1].masters).toEqual {}
    expect(placed(merged[2])).toEqual { theirs = '0:4', mine = '0:5' }
  end)

  suite.it('takes a plugin that doesn\'t name the master as one made on it', function()
    local master = { header(), cell('Hall', { reference(0, 7, 'old') }) }
    local plugin = { header(), cell('Hall', { reference(0, 1, 'new') }), static 'Rock' }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(merged[1].masters).toEqual {}
    expect(labels(merged)).toEqual { 'Static:Rock', 'Cell:Hall' }
    expect(placed(merged[3])).toEqual { old = '0:7', new = '0:8' }
    expect(plugin[1].masters).toEqual {}
  end)

  suite.it('numbers the plugin\'s own references from 1 in a master with none', function()
    local master = { header(), static 'Rock' }
    local plugin = {
      header { { 'Master.esm', 1 } },
      cell('Attic', { reference(0, 5, 'first'), reference(0, 9, 'second') }),
      cell('Hall', { reference(0, 5, 'third') }),
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(placed(find(merged, 'Cell', 'Attic'))).toEqual { first = '0:1', second = '0:2' }
    expect(placed(find(merged, 'Cell', 'Hall'))).toEqual { third = '0:3' }
  end)

  suite.it('needs every other master the plugin names, by its lowercased file name', function()
    local master = { header(), static 'Rock' }
    local plugin = { header { { 'Base.ESM', 1 }, { 'Master.esm', 1 } }, static 'Tree' }

    expect(function() mergeToMaster.merge(plugin, master, Mastered) end).toThrow 'merge_to_master needs the master \'Base.ESM\''

    expect(
      function()
        mergeToMaster.merge(plugin, master, {
          masterName = 'Master.esm',
          masters = { ['Base.ESM'] = { header() } },
        })
      end
    ).toThrow 'merge_to_master needs the master \'Base.ESM\''

    local merged = mergeToMaster.merge(plugin, master, {
      masterName = 'Master.esm',
      masters = { ['base.esm'] = { header(), static 'Bush' } },
    })
    expect(labels(merged)).toEqual { 'Static:Rock', 'Static:Tree' }

    local names = {}

    for _, entry in merged[1].masters do
      table.insert(names, entry[1])
    end

    expect(names).toEqual { 'Base.ESM' }
  end)
end)

suite.describe('objects', function()
  suite.it('replaces the master\'s record of the same type and id, whatever its case', function()
    local master = { header(), static('Rock', 'old.nif'), static('Tree', 'tree.nif') }
    local plugin = { header { { 'Master.esm', 1 } }, static('ROCK', 'new.nif') }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual { 'Static:ROCK', 'Static:Tree' }
    expect(merged[2].mesh).toBe 'new.nif'
    expect(master[2].mesh).toBe 'old.nif'
  end)

  suite.it('keeps ids apart between types outside the shared families', function()
    local master = {
      header(),
      { type = 'Sound', flags = '', id = 'Rock', soundPath = 'rock.wav' },
      { type = 'Script', flags = '', id = 'Rock', text = '' },
    }
    local plugin = { header { { 'Master.esm', 1 } }, static 'rock' }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual { 'Sound:Rock', 'Script:Rock', 'Static:rock' }
  end)
end)

suite.describe('cells', function()
  suite.it('takes the plugin\'s flags, name, and data, and the fields it has', function()
    local master = {
      header(),
      cell('Hall', {}, { waterHeight = 10, mapColor = { 1, 2, 3, 0 }, region = 'Coast' }),
    }
    local plugin = {
      header { { 'Master.esm', 1 } },
      cell('HALL', {}, {
        flags = 'PERSISTENT',
        data = { flags = 'IS_INTERIOR | HAS_WATER', grid = { 0, 0 } },
        mapColor = { 9, 9, 9, 0 },
        atmosphereData = { fogDensity = 0.5 },
      }),
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(#merged).toBe(2)
    expect(merged[2]).toEqual {
      type = 'Cell',
      flags = 'PERSISTENT',
      name = 'HALL',
      data = { flags = 'IS_INTERIOR | HAS_WATER', grid = { 0, 0 } },
      region = 'Coast',
      waterHeight = 10,
      mapColor = { 9, 9, 9, 0 },
      atmosphereData = { fogDensity = 0.5 },
      references = {},
    }

    expect(master[2].name).toBe 'Hall'
    expect(master[2].mapColor).toEqual { 1, 2, 3, 0 }
  end)

  suite.it('replaces the master\'s references at the same indices and adds the rest', function()
    local master = {
      header { { 'Base.esm', 1 } },
      cell('Hall', {
        reference(0, 1, 'chair'),
        reference(0, 2, 'table'),
        reference(1, 2, 'rug'),
      }),
    }
    local plugin = {
      header { { 'Master.esm', 1 }, { 'Base.esm', 1 } },
      cell('Hall', {
        reference(1, 2, 'desk'),
        reference(2, 2, 'carpet'),
        reference(0, 1, 'lamp'),
      }),
    }
    local merged = mergeToMaster.merge(plugin, master, {
      masterName = 'Master.esm',
      masters = { ['base.esm'] = { header() } },
    })
    local order = {}

    for _, item in merged[2].references do
      table.insert(order, `{item.id}@{item.mastIndex}:{item.refrIndex}`)
    end

    expect(order).toEqual { 'chair@0:1', 'desk@0:2', 'carpet@1:2', 'lamp@0:3' }
    expect(placed(master[2])).toEqual { chair = '0:1', table = '0:2', rug = '1:2' }
    expect(placed(plugin[2])).toEqual { desk = '1:2', carpet = '2:2', lamp = '0:1' }
  end)
end)

suite.describe('textures', function()
  suite.it('keeps a texture the master has at its index, and numbers a new one after', function()
    local master = { header(), texture('Sand', 0), texture('Rock', 1) }
    local land = {
      type = 'Landscape',
      flags = '',
      grid = { 0, 0 },
      textureIndices = { data = { { 0, 1, 2 }, { 2, 1, 0 } } },
    }
    local plugin = { header { { 'Master.esm', 1 } }, texture('rock', 0), texture('Grass', 1), land }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local indices = {}

    for _, record in merged do
      if record.type == 'LandscapeTexture' then
        table.insert(indices, `{record.id}={record.index}`)
      end
    end

    -- A landscape's texture index is one more than the texture's own; 0 is no texture.
    expect(indices).toEqual { 'Sand=0', 'rock=1', 'Grass=2' }
    expect(find(merged, 'Landscape').textureIndices.data).toEqual { { 0, 2, 3 }, { 3, 2, 0 } }
    expect(land.textureIndices.data).toEqual { { 0, 1, 2 }, { 2, 1, 0 } }
  end)

  suite.it('leaves texture indices alone in a master without textures', function()
    local master = { header(), static 'Rock' }
    local plugin = { header { { 'Master.esm', 1 } }, texture('Grass', 4) }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(find(merged, 'LandscapeTexture', 'Grass').index).toBe(4)
  end)
end)

suite.describe('dialogue', function()
  suite.it('replaces an INFO in place when its previous INFO is unchanged', function()
    local master =
      { header(), dial 'Topic', info('I1', '', 'I2'), info('I2', 'I1', 'I3'), info('I3', 'I2', '') }
    local plugin = { header { { 'Master.esm', 1 } }, dial 'Topic', info('I2', 'I1', 'I3', 'new') }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(chain(merged)).toEqual { 'I1<|I2>', 'I2<I1|I3>', 'I3<I2|>' }
    expect(merged[4].text).toBe 'new'
    expect(master[4].text).toBe ''
  end)

  suite.it(
    'moves an INFO whose previous INFO changed, and leaves the ends\' outer links',
    function()
      local master = {
        header(),
        dial 'Topic',
        info('I1', '', 'I2'),
        info('I2', 'I1', 'I3'),
        info('I3', 'I2', ''),
      }
      local plugin = { header { { 'Master.esm', 1 } }, dial 'Topic', info('I3', 'I1', 'I2') }
      local merged = mergeToMaster.merge(plugin, master, Mastered)
      expect(chain(merged)).toEqual { 'I1<|I3>', 'I3<I1|I2>', 'I2<I3|I3>' }
      expect(chain(master)).toEqual { 'I1<|I2>', 'I2<I1|I3>', 'I3<I2|>' }
    end
  )

  suite.it('leaves the links of a topic with fewer than three INFOs as they are', function()
    local master = { header(), dial 'Topic', info('I1', '', '') }
    local plugin = { header { { 'Master.esm', 1 } }, dial 'Topic', info('I2', 'I1', '') }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(chain(merged)).toEqual { 'I1<|>', 'I2<I1|>' }
  end)

  suite.it('takes the plugin\'s DIAL for a topic, and a new topic whole', function()
    local master = { header(), dial 'Topic', info('I1', '', '') }
    local plugin = {
      header { { 'Master.esm', 1 } },
      dial 'TOPIC',
      dial 'Other',
      info('O2', 'O1', ''),
      info('O1', '', 'O2'),
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'Dialogue:Other',
      'DialogueInfo:O1',
      'DialogueInfo:O2',
      'Dialogue:TOPIC',
      'DialogueInfo:I1',
    }
  end)

  suite.it('refuses an INFO that follows no topic', function()
    local master = { header(), dial 'Topic' }
    local plugin = { header { { 'Master.esm', 1 } }, info('I1', '', '') }
    expect(function() mergeToMaster.merge(plugin, master, Mastered) end).toThrow 'Orphan DialogueInfo I1'
  end)
end)

suite.describe('removeDeleted', function()
  local function sources(): ({ Record }, { Record })
    local master = {
      header { { 'Base.esm', 1 } },
      static 'Rock',
      static 'Tree',
      cell('Hall', {
        reference(0, 1, 'Rock'),
        reference(0, 2, 'Tree'),
        reference(0, 3, 'Lamp', { deleted = true }),
        reference(1, 4, 'Rock'),
        reference(1, 5, 'Bench', { deleted = true }),
      }),
    }
    local plugin = { header { { 'Master.esm', 1 } }, static('rock', '', 'DELETED') }
    return plugin, master
  end

  suite.it('keeps deleted records and references without it', function()
    local plugin, master = sources()
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual { 'Static:Tree', 'Static:rock', 'Cell:Hall' }
    expect(merged[3].flags).toBe 'DELETED'
    expect(#merged[4].references).toBe(5)
  end)

  suite.it(
    'drops deleted objects, and the master\'s own references that are deleted or name one',
    function()
      local plugin, master = sources()
      local merged =
        mergeToMaster.merge(plugin, master, { masterName = 'Master.esm', removeDeleted = true })
      expect(labels(merged)).toEqual { 'Static:Tree', 'Cell:Hall' }
      expect(placed(merged[3])).toEqual { Tree = '0:2', Rock = '1:4', Bench = '1:5' }
      expect(#master[4].references).toBe(5)
    end
  )
end)

suite.describe('order', function()
  suite.it('writes cells by name, each path grid after its cell', function()
    local function grid(name: string): Record
      return { type = 'PathGrid', flags = '', cell = name, data = { grid = { 0, 0 } } }
    end

    local master = { header(), cell 'Hall', grid 'Attic' }
    local plugin = { header { { 'Master.esm', 1 } }, grid 'Hall', cell 'Cellar', cell 'Attic' }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'Cell:Attic',
      'PathGrid:Attic',
      'Cell:Cellar',
      'Cell:Hall',
      'PathGrid:Hall',
    }
  end)

  suite.it('writes textures by index, and magic effects and skills by theirs', function()
    local master = {
      header(),
      { type = 'Skill', flags = '', skillId = 'Armorer' },
      { type = 'MagicEffect', flags = '', effectId = 'Shield' },
      texture('Rock', 1),
      texture('Sand', 0),
    }
    local plugin = {
      header { { 'Master.esm', 1 } },
      { type = 'MagicEffect', flags = '', effectId = 'WaterBreathing' },
      { type = 'Skill', flags = '', skillId = 'Block' },
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local order = {}

    for index = 2, #merged do
      local record = merged[index]
      table.insert(order, record.skillId or record.effectId or record.id)
    end

    expect(order).toEqual { 'Block', 'Armorer', 'WaterBreathing', 'Shield', 'Sand', 'Rock' }
  end)
end)

suite.describe('through tes3conv', function()
  suite.it('gives records tes3conv writes as a plugin and reads back the same', function()
    local master = {
      header({}, { fileType = 'Esm' }),
      static('Rock', 'rock.nif'),
      cell('Hall', { reference(0, 1, 'Rock') }),
      dial 'Topic',
    }
    local plugin = {
      header { { 'Master.esm', 1 } },
      static('Tree', 'tree.nif'),
      cell('Hall', { reference(1, 1, 'Tree'), reference(0, 1, 'Rock') }),
      {
        type = 'GameSetting',
        flags = '',
        id = 'sName',
        value = { type = 'String', data = 'Name' },
      },
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'GameSetting:sName',
      'Static:Rock',
      'Static:Tree',
      'Cell:Hall',
      'Dialogue:Topic',
    }

    local written = tes3conv.plugin(merged)
    expect(written:count()).toBe(6)
    local back: { Record } = tes3conv.records(written)
    expect(labels(back)).toEqual(labels(merged))
    expect(back[1].fileType).toBe 'Esm'
    expect(back[1].masters).toEqual {}
    expect(back[3]).toEqual(merged[3])
    expect(placed(back[5])).toEqual { Tree = '0:1', Rock = '0:2' }
    expect(buffer.tostring(tes3conv.plugin(back):save()) == buffer.tostring(written:save())).toBe(
      true
    )
  end)
end)

return suite
