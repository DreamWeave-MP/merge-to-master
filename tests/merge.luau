--!strict
--!native
-- `merge` on the rest of what its header documents: the masters it is given, the objects, cells,
-- textures, and dialogue it merges, `removeDeleted`, the order it writes, and its records through
-- `@tes3conv` into a plugin.
local bytes = require '@dream/bytes'
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
  return [
    for record in records
    if record.type ~= 'Header'
    => `{record.type}:{record.id or record.cell or record.name}`
  ]
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
  return [
    for record in records
    if record.type == 'DialogueInfo'
    => `{record.id}<{record.prevId}|{record.nextId}>`
  ]
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

    expect([for entry in merged[1].masters => entry[1]]).toEqual { 'Base.ESM' }
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

  suite.it('folds the case of an id\'s ASCII letters and of no other byte', function()
    local master = { header(), static('Röck', 'old.nif') }
    local plugin = {
      header { { 'Master.esm', 1 } },
      static('RöCK', 'new.nif'),
      static('RÖCK', 'other.nif'),
    }
    local merged, summary = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual { 'Static:RÖCK', 'Static:RöCK' }
    expect(merged[3].mesh).toBe 'new.nif'
    expect(summary.merged).toBe(1)
    expect(summary.copied).toBe(1)
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
    local order = [for item in merged[2].references => `{item.id}@{item.mastIndex}:{item.refrIndex}`]

    expect(order).toEqual { 'chair@0:1', 'desk@0:2', 'carpet@1:2', 'lamp@0:3' }
    expect(placed(master[2])).toEqual { chair = '0:1', table = '0:2', rug = '1:2' }
    expect(placed(plugin[2])).toEqual { desk = '1:2', carpet = '2:2', lamp = '0:1' }
  end)

  --- Each reference of the one cell merged: its id, master, and index, in the cell's order.
  local function mergedReferences(plugin: { Record }, master: { Record }): { string }
    local merged = mergeToMaster.merge(plugin, master, {
      masterName = 'Master.esm',
      masters = { ['base.esm'] = { header() } },
    })

    return [
      for item in find(merged, 'Cell').references
      => `{item.id}@{item.mastIndex}:{item.refrIndex}`
    ]
  end

  suite.it('replaces a reference at an index of any size, whole or not', function()
    local master = {
      header { { 'Base.esm', 1 } },
      cell('Hall', {
        reference(0, 2 ^ 40, 'far'),
        reference(0, 1.5, 'half'),
        reference(1, 2 ^ 30, 'theirs'),
        reference(0, 7, 'near'),
      }),
    }

    local plugin = {
      header { { 'Master.esm', 1 }, { 'Base.esm', 1 } },
      cell('Hall', {
        reference(1, 2 ^ 40, 'farther'),
        reference(1, 1.5, 'halved'),
        reference(2, 2 ^ 30, 'ours'),
        reference(0, 1, 'new'),
      }),
    }

    expect(mergedReferences(plugin, master)).toEqual {
      'farther@0:1099511627776',
      'halved@0:1.5',
      'ours@1:1073741824',
      'near@0:7',
      'new@0:1099511627777',
    }
  end)

  suite.it('takes an index spelled as text for the number it spells', function()
    local spelled = reference(0, 0, 'spelled')
    spelled.refrIndex = '5'
    local master = { header(), cell('Hall', { spelled }) }
    local plugin = {
      header { { 'Master.esm', 1 } },
      cell('Hall', { reference(1, 5, 'numbered'), reference(0, 1, 'new') }),
    }

    expect(mergedReferences(plugin, master)).toEqual { 'numbered@0:5', 'new@0:6' }
  end)

  suite.it('keeps a reference under a master of -0 apart from one under 0', function()
    local master = { header(), cell('Hall', { reference(-0, 3, 'under') }) }
    local plugin = { header { { 'Master.esm', 1 } }, cell('Hall', { reference(1, 3, 'over') }) }

    expect(mergedReferences(plugin, master)).toEqual { 'under@-0:3', 'over@0:3' }
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
    local indices = [
      for record in merged
      if record.type == 'LandscapeTexture'
      => `{record.id}={record.index}`
    ]

    -- A landscape's texture index is one more than the texture's own; 0 is no texture.
    expect(indices).toEqual { 'Sand=0', 'rock=1', 'Grass=2' }
    expect(find(merged, 'Landscape').textureIndices.data).toEqual { { 0, 2, 3 }, { 3, 2, 0 } }
    expect(land.textureIndices.data).toEqual { { 0, 1, 2 }, { 2, 1, 0 } }
  end)

  suite.it('remaps a landscape\'s indices as tes3conv spells them, in base64', function()
    local master = { header(), texture('Sand', 0), texture('Rock', 1) }
    local grid = buffer.create(512)
    buffer.writeu16(grid, 0, 1)
    buffer.writeu16(grid, 2, 2)
    buffer.writeu16(grid, 510, 2)
    local spelled = bytes.toBase64(grid)
    local land = {
      type = 'Landscape',
      flags = '',
      grid = { 0, 0 },
      textureIndices = { data = spelled },
    }
    local plugin = { header { { 'Master.esm', 1 } }, texture('rock', 0), texture('Grass', 1), land }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local words = bytes.fromBase64(find(merged, 'Landscape').textureIndices.data)

    expect(buffer.len(words)).toBe(512)
    expect(buffer.readu16(words, 0)).toBe(2)
    expect(buffer.readu16(words, 2)).toBe(3)
    expect(buffer.readu16(words, 4)).toBe(0)
    expect(buffer.readu16(words, 510)).toBe(3)
    expect(land.textureIndices.data).toBe(spelled)
  end)

  suite.it('leaves texture indices alone in a master without textures', function()
    local master = { header(), static 'Rock' }
    local plugin = { header { { 'Master.esm', 1 } }, texture('Grass', 4) }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(find(merged, 'LandscapeTexture', 'Grass').index).toBe(4)
  end)

  suite.it('remaps only the words that number a texture of the plugin\'s', function()
    local master = { header(), texture('Sand', 0), texture('Rock', 1) }
    local grid = buffer.create(512)

    -- The last is 70001 less 65536: one more than the index of `Far`, as a word would wrap it.
    for place, word in { 0, 1, 2, 3, 65535, 4465 } do
      buffer.writeu16(grid, (place - 1) * 2, word)
    end

    local function land(column: number, data: { { number } } | string): Record
      return {
        type = 'Landscape',
        flags = '',
        grid = { column, 0 },
        textureIndices = { data = data },
      }
    end

    local plugin = {
      header { { 'Master.esm', 1 } },
      texture('rock', 0),
      texture('Grass', 1),
      texture('Far', 70000),
      texture('Half', 2.5),
      land(0, bytes.toBase64(grid)),
      land(1, { { 0, 1, 2, 3 }, { 70001, 3.5 }, {} }),
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local indices = [
      for record in merged
      if record.type == 'LandscapeTexture'
      => `{record.id}={record.index}`
    ]

    expect(indices).toEqual { 'Sand=0', 'rock=1', 'Grass=2', 'Far=3', 'Half=4' }

    local lands = {}

    for _, record in merged do
      if record.type == 'Landscape' then lands[record.grid[1] + 1] = record.textureIndices.data end
    end

    local words = bytes.fromBase64(lands[1])
    local read = [for place in range(1, 6) => buffer.readu16(words, (place - 1) * 2)]

    expect(buffer.len(words)).toBe(512)
    expect(read).toEqual { 0, 2, 3, 3, 65535, 4465 }
    expect(lands[2]).toEqual { { 0, 2, 3, 3 }, { 4, 5 }, {} }
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

  suite.it('takes an INFO without an id for one whose id is empty', function()
    local old, new = info('', '', '', 'old'), info('', '', '', 'new')
    old.id, new.id = nil, nil
    local master = { header(), dial 'Topic', info('I1', 'I0', ''), old }
    local plugin = { header { { 'Master.esm', 1 } }, dial 'Topic', new, info('I2', '', '') }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local texts = [
      for record in merged
      if record.type == 'DialogueInfo'
      => `{record.id}:{record.text}<{record.prevId}|{record.nextId}>`
    ]

    expect(texts).toEqual { 'I2:<|>', 'nil:new<I2|I1>', 'I1:<|>' }
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

  suite.it(
    'finds the references to a deleted object by its id, case folded as its own is',
    function()
      local unnamed = reference(0, 5, '')
      unnamed.id = nil
      local master = {
        header(),
        static 'Röck',
        cell('Hall', {
          reference(0, 1, 'röck'),
          reference(0, 2, 'RÖCK'),
          reference(0, 3, 'ROCK'),
          reference(0, 4, 'RöCK'),
          unnamed,
        }),
      }
      local plugin = { header { { 'Master.esm', 1 } }, static('RöCK', '', 'DELETED') }
      local log = {}
      local merged, summary = mergeToMaster.merge(
        plugin,
        master,
        { masterName = 'Master.esm', removeDeleted = true, log = log }
      )
      local kept = [for item in find(merged, 'Cell').references => `{item.id}@{item.refrIndex}`]

      expect(kept).toEqual { 'RÖCK@2', 'ROCK@3', 'nil@5' }
      expect(summary.objectsRemoved).toBe(1)
      expect(summary.referencesRemoved).toBe(2)
      expect(log).toEqual {
        'Merging object to master: STAT RöCK',
        'Removed deleted object: röck',
        'Removed deleted reference: röck (0, 1) from hall',
        'Removed deleted reference: röck (0, 4) from hall',
      }
    end
  )

  suite.it('drops only the references marked deleted when no object is', function()
    local master = {
      header(),
      static 'Rock',
      cell('Attic', { reference(0, 1, 'Rock') }),
      cell('Hall', { reference(0, 2, 'Rock'), reference(0, 3, 'Rock', { deleted = true }) }),
    }
    local plugin = { header { { 'Master.esm', 1 } }, static 'Tree' }
    local log = {}
    local merged, summary = mergeToMaster.merge(
      plugin,
      master,
      { masterName = 'Master.esm', removeDeleted = true, log = log }
    )

    expect(placed(find(merged, 'Cell', 'Attic'))).toEqual { Rock = '0:1' }
    expect(placed(find(merged, 'Cell', 'Hall'))).toEqual { Rock = '0:2' }
    expect(find(merged, 'Cell', 'Attic') == master[3]).toBe(false)
    expect(summary.referencesRemoved).toBe(1)
    expect(log).toEqual { 'Copying object to master: STAT Tree' }
  end)
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
    local order = [for record in merged[2:#merged] => record.skillId or record.effectId or record.id]

    expect(order).toEqual { 'Block', 'Armorer', 'WaterBreathing', 'Shield', 'Sand', 'Rock' }
  end)

  suite.it('writes the records of a type by their ids, byte by byte', function()
    local master = {
      header(),
      static 'rock1',
      static 'Rock2',
      static 'Rock',
      static '9',
      static 'Rock\0',
      static '10',
      static 'Rock 1',
    }

    local plugin = {
      header { { 'Master.esm', 1 } },
      static 'Bush',
      { type = 'Activator', flags = '', id = 'Zeta' },
      { type = 'Sound', flags = '', id = 'zeta', soundPath = '' },
      { type = 'Sound', flags = '', id = 'Rock', soundPath = '' },
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'Sound:Rock',
      'Sound:zeta',
      'Static:10',
      'Static:9',
      'Static:Bush',
      'Static:Rock',
      'Static:Rock\0',
      'Static:Rock 1',
      'Static:Rock2',
      'Static:rock1',
      'Activator:Zeta',
    }
  end)

  suite.it('writes a texture by an index of any size, whole or not', function()
    local master = {
      header(),
      texture('Far', 2 ^ 40),
      texture('One', 1),
      texture('Half', 0.5),
      static 'Rock',
      texture('Below', -3),
      texture('Wide', 4194303),
      texture('Narrow', 4194302),
    }
    local plugin = { header { { 'Master.esm', 1 } }, static 'Bush' }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'LandscapeTexture:Below',
      'LandscapeTexture:Half',
      'LandscapeTexture:One',
      'LandscapeTexture:Narrow',
      'LandscapeTexture:Wide',
      'LandscapeTexture:Far',
      'Static:Bush',
      'Static:Rock',
    }
  end)

  suite.it('writes textures between -1 and the greatest index among records of every sort', function()
    local master = {
      header(),
      texture('Last', 4194302),
      static 'Rock',
      texture('Seventh', 7),
      { type = 'Skill', flags = '', skillId = 'Block' },
      texture('Before', -1),
      cell 'Hall',
      texture('First', 0),
      dial 'Topic',
    }
    local plugin = { header { { 'Master.esm', 1 } }, static 'Bush', texture('before', -1) }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'Skill:nil',
      'LandscapeTexture:before',
      'LandscapeTexture:First',
      'LandscapeTexture:Seventh',
      'LandscapeTexture:Last',
      'Static:Bush',
      'Static:Rock',
      'Cell:Hall',
      'Dialogue:Topic',
    }
  end)

  suite.it('writes a skill and a magic effect it has no number for before the others', function()
    local master = {
      header(),
      { type = 'Skill', flags = '', skillId = 'Block' },
      { type = 'Skill', flags = '', skillId = 'Juggling' },
      { type = 'MagicEffect', flags = '', effectId = 'WaterBreathing' },
      { type = 'MagicEffect', flags = '', effectId = 'Tidiness' },
    }
    local plugin = { header { { 'Master.esm', 1 } }, { type = 'Skill', flags = '', skillId = 'None' } }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local order = [for record in merged[2:#merged] => record.skillId or record.effectId]

    expect(order).toEqual { 'Juggling', 'None', 'Block', 'Tidiness', 'WaterBreathing' }
  end)

  suite.it('writes cells of one name in the order they came, then its path grids', function()
    local function exterior(kind: string, column: number, row: number): Record
      local record = cell('', {}, { data = { flags = '', grid = { column, row } } })
      record.type = kind

      if kind == 'PathGrid' then record.cell, record.name = '', nil end

      return record
    end

    local master = {
      header(),
      exterior('PathGrid', 0, 0),
      exterior('Cell', 2, 0),
      cell 'Attic',
      exterior('Cell', 1, 0),
    }

    local plugin = {
      header { { 'Master.esm', 1 } },
      exterior('PathGrid', 1, 1),
      exterior('Cell', 0, 5),
      exterior('Cell', 1, 0),
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    local order = [
      for {type: kind, name, data: {grid}} in merged[2:#merged]
      => `{kind} {name} {grid[1]},{grid[2]}`
    ]

    expect(order).toEqual {
      'Cell  2,0',
      'Cell  1,0',
      'Cell  0,5',
      'PathGrid nil 0,0',
      'PathGrid nil 1,1',
      'Cell Attic 0,0',
    }
  end)

  suite.it('writes journals first among topics, the rest by their type, then id', function()
    local master = {
      header(),
      dial('Zebra', 'Topic'),
      dial('Quest', 'Journal'),
      dial('Hello', 'Greeting'),
      dial('Apple', 'Topic'),
      dial('Shout', 'Voice'),
      dial('Bribe', 'Persuasion'),
      dial('Odd', 'Elsewise'),
    }

    local plugin = {
      header { { 'Master.esm', 1 } },
      dial('Diary', 'Journal'),
      dial('apple2', 'Topic'),
      dial('Curio', 'Otherwise'),
      static 'Rock',
    }
    local merged = mergeToMaster.merge(plugin, master, Mastered)
    expect(labels(merged)).toEqual {
      'Static:Rock',
      'Dialogue:Diary',
      'Dialogue:Quest',
      'Dialogue:Apple',
      'Dialogue:Zebra',
      'Dialogue:apple2',
      'Dialogue:Shout',
      'Dialogue:Hello',
      'Dialogue:Bribe',
      'Dialogue:Curio',
      'Dialogue:Odd',
    }
  end)
end)

suite.describe('summary and log', function()
  local function sources(): ({ Record }, { Record })
    local master = {
      header { { 'Base.esm', 1 } },
      static 'Rock',
      static 'Tree',
      texture('Sand', 0),
      cell('Hall', {
        reference(0, 1, 'Rock'),
        reference(0, 2, 'Tree'),
        reference(0, 3, 'Lamp', { deleted = true }),
        reference(1, 4, 'Rock'),
      }),
      dial 'Topic',
      info('I1', '', ''),
    }

    local plugin = {
      header { { 'Base.esm', 1 }, { 'Master.esm', 1 } },
      static('rock', '', 'DELETED'),
      static 'Bush',
      texture('Grass', 0),
      cell('Hall', {}),
      cell('Wastes', {}, { data = { flags = '', grid = { 2, -3 } } }),
      dial 'TOPIC',
      info('I2', 'I1', ''),
      dial 'Rumors',
    }
    return plugin, master
  end

  local others = { ['base.esm'] = { header(), dial 'Elsewhere', info('B1', '', '') } }

  suite.it('counts what the plugin merged and copied, and nothing of the other masters', function()
    local plugin, master = sources()
    local _, summary =
      mergeToMaster.merge(plugin, master, { masterName = 'Master.esm', masters = others })

    expect(summary).toEqual {
      merged = 3,
      copied = 4,
      texturesRemapped = 1,
      objectsRemoved = 0,
      referencesRemoved = 0,
    }
  end)

  suite.it('counts what removeDeleted removed', function()
    local plugin, master = sources()
    local _, summary = mergeToMaster.merge(
      plugin,
      master,
      { masterName = 'Master.esm', masters = others, removeDeleted = true }
    )

    expect(summary.objectsRemoved).toBe(1)
    expect(summary.referencesRemoved).toBe(2)
  end)

  suite.it('adds merge_to_master\'s log lines to the list it is given, in its own order', function()
    local plugin, master = sources()
    local log = { 'Merging plugins...' }
    mergeToMaster.merge(
      plugin,
      master,
      { masterName = 'Master.esm', masters = others, removeDeleted = true, log = log }
    )

    expect(log).toEqual {
      'Merging plugins...',
      'Remapping texture index: (0 -> 1) Grass',
      'Merging object to master: STAT rock',
      'Copying object to master: STAT Bush',
      'Copying object to master: LTEX Grass',
      'Merging object to master: CELL Hall',
      'Copying object to master: CELL Wastes (2, -3)',
      'Merging object to master: topic',
      'Copying object to master: rumors',
      'Removed deleted object: rock',
      'Removed deleted reference: rock (0, 1) from hall',
    }
  end)

  suite.it('writes no line for a merge that has nothing to say', function()
    local log = {}
    local merged, summary = mergeToMaster.merge({ header() }, { header() }, {
      masterName = 'Master.esm',
      log = log,
    })

    expect(#merged).toBe(1)
    expect(log).toEqual {}
    expect(summary).toEqual {
      merged = 0,
      copied = 0,
      texturesRemapped = 0,
      objectsRemoved = 0,
      referencesRemoved = 0,
    }
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
