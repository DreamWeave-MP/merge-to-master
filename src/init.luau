--!strict
--!native
--[[
@merge-to-master: Greatness7's merge_to_master, over record lists.

  merge(plugin, master, options) -> (records, summary)

Merges `plugin` into `master`, both lists of tes3conv-shaped records with the header first (see
@tes3conv), and returns the merged master. `options.masterName` is the master's
file name, as `merge_to_master <plugin> <master>` would see it. `options.masters` maps each other
file the plugin names as a master (lowercased) to its records: merge_to_master reads only their
dialogue, to place the plugin's INFOs in the chain they continue, and drops it afterwards.
`options.removeDeleted` is `--remove-deleted`.

The summary counts what the merge did. `options.log`, when given, is a list the merge adds a line
to for each thing merge_to_master writes one to merge_to_master.log for: every texture it
renumbers, every object and topic it merges or copies, and with `removeDeleted` every object it
removes and every reference removed with its object.

What it does, as merge_to_master 0.9.5 does it:
  * objects are keyed by type and lowercased id, except that the item, actor, spell, and static
    families share one key space: a plugin's NPC replaces the master's creature of the same id;
  * a merged CELL takes the plugin's flags, name, and data, its region, map color, water height,
    and atmosphere when it has them, and both sets of references, the plugin's replacing the
    master's at the same indices;
  * a DIAL takes the plugin's record, and its INFOs are inserted after their previous INFO
    (replaced in place when that is unchanged, at the front with none, at the end when it's
    missing), then every link but the chain's ends is repaired;
  * the plugin's masters are appended to the master's, and its references renumbered to follow
    the master's highest own index; texture indices are remapped the same way;
  * records come out sorted by type, then id.

merge_to_master renumbers references and textures in hash-map order, so two runs of it number
the same merge differently. This port walks cells and textures in the order the plugin has them,
which gives every run the same numbers. Cells and path grids come out sorted by name, each path
grid after its cell, and journals before the other topics, the others by dialogue type and id:
the order merge_to_master writes them in. Its log lines are in hash-map order too; this port's
are in the plugin's order, and the master's for what `removeDeleted` removes.
]]

local bytes = require '@dream/bytes'
local plane = require '@dream/data'
local tes3 = require '@tes3conv/records'

type Table = tes3.Table
type Value = tes3.Value
type Record = tes3.Record
type Records = tes3.Records

export type Options = {
  masterName: string,
  masters: { [string]: Records }?,
  removeDeleted: boolean?,
  log: { string }?,
}

--- What a merge did. `merged` and `copied` count the plugin's objects and topics: those the
--- master had already, and those new to it. The last two count what `removeDeleted` removed: the
--- objects marked deleted, and the master's own references marked deleted or to such an object.
export type Summary = {
  merged: number,
  copied: number,
  texturesRemapped: number,
  objectsRemoved: number,
  referencesRemoved: number,
}

type Journal = { summary: Summary, log: { string }? }

-- An INFO in a topic's chain: merge_to_master's VecDeque, as a linked list with an index by id.
type Node = { info: Record, prev: Node?, next: Node? }
type Group = { dialogue: Record?, head: Node?, tail: Node?, byId: { [string]: Node } }

type PluginData = {
  header: Record,
  objects: { [string]: Record },
  order: { string },
  -- Those of `order` that are cells, and those that are textures, in its order: what the passes
  -- over a file's references and its texture indices read, without the rest.
  cells: { string },
  textures: { string },
  dialogues: { [string]: Group },
  dialogueOrder: { string },
  ignored: { [Record]: boolean },
}

local mergeToMaster = {}

-- The families merge_to_master keys under one tag, so their ids share a space.
local SharedKeys: { [string]: boolean } = {
  Activator = true,
  Alchemy = true,
  Apparatus = true,
  Armor = true,
  Bodypart = true,
  Book = true,
  Clothing = true,
  Container = true,
  Creature = true,
  Door = true,
  Enchanting = true,
  Ingredient = true,
  LeveledCreature = true,
  LeveledItem = true,
  Light = true,
  Lockpick = true,
  MiscItem = true,
  Npc = true,
  Probe = true,
  RepairItem = true,
  Spell = true,
  Static = true,
  Weapon = true,
}

-- What an object is kept under: its lowercased id, after its type's tag unless its family shares
-- its ids. A tag starts with a capital and a lowercased id with none, so the two never meet.
local function objectKey(record: Record): string?
  local id = string.lower(tes3.editorId(record))

  if id == '' then return nil end

  if SharedKeys[record.type :: string] then return id end

  return tes3.Tags[record.type :: string] .. id
end

local function newGroup(): Group return { dialogue = nil, head = nil, tail = nil, byId = {} } end

local function unlink(group: Group, node: Node)
  if node.prev then
    (node.prev :: Node).next = node.next
  else
    group.head = node.next
  end

  if node.next then
    (node.next :: Node).prev = node.prev
  else
    group.tail = node.prev
  end

  node.prev, node.next = nil, nil
end

local function pushFront(group: Group, node: Node)
  node.next = group.head

  if group.head then
    (group.head :: Node).prev = node
  else
    group.tail = node
  end

  group.head = node
end

local function pushBack(group: Group, node: Node)
  node.prev = group.tail

  if group.tail then
    (group.tail :: Node).next = node
  else
    group.head = node
  end

  group.tail = node
end

local function insertAfter(group: Group, after: Node, node: Node)
  node.prev = after
  node.next = after.next

  if after.next then
    (after.next :: Node).prev = node
  else
    group.tail = node
  end

  after.next = node
end

-- merge_to_master's `DialogueGroup::insert_info`. Ids compare exactly, as it compares them.
local function insertInfo(group: Group, info: Record)
  local id = tes3.string(info.id)
  local prevId = tes3.string(info.prevId)
  local existing = group.byId[id]

  if existing then
    if tes3.string(existing.info.prevId) == prevId then
      existing.info = info
      return
    end

    unlink(group, existing)
    group.byId[id] = nil
  end

  local node: Node = { info = info, prev = nil, next = nil }
  group.byId[id] = node

  if prevId == '' then
    pushFront(group, node)
    return
  end

  local previous = group.byId[prevId]

  if previous then
    insertAfter(group, previous, node)
  else
    pushBack(group, node)
  end
end

-- merge_to_master's `repair_links`: each INFO's links name its neighbours, except the first's
-- previous and the last's next, which stay as they were. A changed INFO is copied, so lists
-- that still hold the original see it unchanged.
local function repairLinks(group: Group, ignored: { [Record]: boolean })
  local node = group.head

  -- It walks windows of three, so a topic of one or two INFOs keeps its links as they are.
  if not (node and node.next and (node.next :: Node).next) then return end

  while node do
    local info = node.info
    local wantPrev = node.prev and tes3.string((node.prev :: Node).info.id)
    local wantNext = node.next and tes3.string((node.next :: Node).info.id)
    local fixPrev = wantPrev ~= nil and tes3.string(info.prevId) ~= wantPrev
    local fixNext = wantNext ~= nil and tes3.string(info.nextId) ~= wantNext

    if fixPrev or fixNext then
      local copy = table.clone(info)

      if fixPrev then copy.prevId = wantPrev :: string end

      if fixNext then copy.nextId = wantNext :: string end

      if ignored[info] then ignored[copy] = true end

      node.info = copy
    end

    node = node.next
  end
end

local function newData(): PluginData
  return {
    header = {},
    objects = {},
    order = {},
    cells = {},
    textures = {},
    dialogues = {},
    dialogueOrder = {},
    ignored = {},
  }
end

local function addDialogue(data: PluginData, key: string): Group
  local group = data.dialogues[key]

  if not group then
    group = newGroup()
    data.dialogues[key] = group
    table.insert(data.dialogueOrder, key)
  end

  return group
end

local function setObject(data: PluginData, key: string, record: Record)
  if data.objects[key] == nil then
    table.insert(data.order, key)

    if record.type == 'Cell' then
      table.insert(data.cells, key)
    elseif record.type == 'LandscapeTexture' then
      table.insert(data.textures, key)
    end
  end

  data.objects[key] = record
end

-- merge_to_master's `collect_objects`. With `dialogueOnly`, only DIAL and INFO, as
-- `from_path_dialogue_only` loads them.
local function collect(records: Records, dialogueOnly: boolean?): PluginData
  local data = newData()
  local current: Group? = nil

  for _, record in records do
    local kind = record.type

    if kind == 'Header' then
      data.header = record
    elseif kind == 'Dialogue' then
      current = addDialogue(data, tes3.lower(record.id));
      (current :: Group).dialogue = record
    elseif kind == 'DialogueInfo' then
      if not current then error(`Orphan DialogueInfo {tes3.string(record.id)}`) end

      insertInfo(current :: Group, record)
    elseif not dialogueOnly then
      local key = objectKey(record)

      if key then setObject(data, key, record) end
    end
  end

  return data
end

local function setAllIgnored(data: PluginData)
  for _, record in data.objects do
    data.ignored[record] = true
  end

  for _, group in data.dialogues do
    if group.dialogue then data.ignored[group.dialogue :: Record] = true end

    local node = group.head

    while node do
      data.ignored[node.info] = true
      node = node.next
    end
  end
end

-- Below this, a reference's master and index are held as one number.
local IndexLimit = 67108864

--- A reference's master and index as one number, when each is a whole number from 0 up to
--- `IndexLimit`. Written out, -0 isn't 0, so it has none: its reciprocal is below 0.
local function packedIndices(reference: Table): number?
  local master, index = reference.mastIndex, reference.refrIndex

  if type(master) ~= 'number' or type(index) ~= 'number' then return nil end

  if not (master < IndexLimit and 1 / master > 0 and master % 1 == 0) then return nil end

  if not (index < IndexLimit and 1 / index > 0 and index % 1 == 0) then return nil end

  return master * IndexLimit + index
end

-- Where each reference of a cell is in its list, by its master and index. One is cleared and
-- filled again for every cell of a merge, so that it grows to the largest cell's size once.
type Places = { [string | number]: number }

--- The master's references with the plugin's among them: each of the plugin's in place of the
--- master's at its master and index, or after them all. Two references are at the same place
--- when their indices are written the same, which whole numbers are when they are equal: with
--- `packed`, each pair is one number, and the answer is nil when a pair can't be.
local function mergeReferences(
  master: { Table },
  plugin: { Table },
  packed: boolean,
  at: Places
): { Table }?
  local references = table.clone(master)
  table.clear(at)

  for index, reference in references do
    local key: (string | number)? = if packed
      then packedIndices(reference)
      else `{reference.mastIndex}:{reference.refrIndex}`

    if not key then return nil end

    at[key] = index
  end

  for _, reference in plugin do
    local key: (string | number)? = if packed
      then packedIndices(reference)
      else `{reference.mastIndex}:{reference.refrIndex}`

    if not key then return nil end

    local index = at[key]

    if index then
      references[index] = reference
    else
      table.insert(references, reference)
      at[key] = #references
    end
  end

  return references
end

local function mergeCell(plugin: Record, master: Record, at: Places): Record
  local merged = table.clone(master)
  merged.flags = plugin.flags
  merged.name = plugin.name
  merged.data = plugin.data

  for _, field in { 'region', 'mapColor', 'waterHeight', 'atmosphereData' } do
    if plugin[field] ~= nil then merged[field] = plugin[field] end
  end

  local theirs, ours = (master.references or {}) :: { Table }, (plugin.references or {}) :: { Table }
  merged.references = mergeReferences(theirs, ours, true, at)
    or mergeReferences(theirs, ours, false, at)
  return merged
end

-- merge_to_master logs each object and topic of the plugin's as merged into the master's, or
-- copied to a master without one: `name` is its tag and id, or the topic's id lowercased.
local function note(journal: Journal, had: boolean, name: string)
  local summary = journal.summary

  if had then
    summary.merged += 1
  else
    summary.copied += 1
  end

  if journal.log then
    local verb = if had then 'Merging' else 'Copying'
    table.insert(journal.log, `{verb} object to master: {name}`)
  end
end

-- `impl MergeInto for PluginData`: `self` into `target`. Only the plugin's own merge is
-- journaled: merge_to_master silences its log while it reads the masters.
local function mergeInto(source: PluginData, target: PluginData, journal: Journal?)
  target.header = source.header
  local places: Places = {}

  for key, ignored in source.ignored do
    target.ignored[key] = ignored
  end

  for _, key in source.order do
    local object = source.objects[key]
    local existing = target.objects[key]

    if journal then
      local name = if journal.log
        then `{tes3.Tags[object.type :: string]} {tes3.editorId(object)}`
        else ''
      note(journal, existing ~= nil, name)
    end

    if existing and object.type == 'Cell' then
      local merged = mergeCell(object, existing, places)

      if source.ignored[object] then target.ignored[merged] = true end

      target.objects[key] = merged
    else
      setObject(target, key, object)
    end
  end

  for _, key in source.dialogueOrder do
    local group = source.dialogues[key]
    local existing = target.dialogues[key]

    if journal then note(journal, existing ~= nil, key) end

    if not existing then
      -- A topic the target doesn't have is moved over whole, chain and all.
      local copy = addDialogue(target, key)
      copy.dialogue = group.dialogue
      local node = group.head

      while node do
        local moved: Node = { info = node.info, prev = nil, next = nil }
        pushBack(copy, moved)
        copy.byId[tes3.string(node.info.id)] = moved
        node = node.next
      end

      continue
    end

    (existing :: Group).dialogue = group.dialogue
    local node = group.head

    while node do
      insertInfo(existing :: Group, node.info)
      node = node.next
    end

    repairLinks(existing :: Group, target.ignored)
  end
end

local function sameName(left: string, right: string): boolean
  return string.lower(left) == string.lower(right)
end

type Master = { string | number }

local function masterName(master: Value): string return tes3.string((master :: Table)[1]) end

-- merge_to_master's `get_index_remap`.
local function indexRemap(
  pluginMasters: { Master },
  masterMasters: { Master },
  target: string
): ({ Master }, { number })
  local newMasters: { Master } = table.clone(masterMasters)
  local remap = { [0] = 0 }

  for index, master in pluginMasters do
    local name = masterName(master)

    if sameName(name, target) then
      remap[index] = 0
      continue
    end

    local found: number? = nil

    for position, existing in newMasters do
      if sameName(masterName(existing), name) then
        found = position
        break
      end
    end

    if not found then
      table.insert(newMasters, master)
      found = #newMasters
    end

    remap[index] = found :: number
  end

  return newMasters, remap
end

local function nextReferenceIndex(master: PluginData): number
  local highest: number? = nil

  for _, key in master.cells do
    for _, reference in (master.objects[key].references or {}) :: { Table } do
      if reference.mastIndex == 0 then
        local index = reference.refrIndex :: number

        if not highest or index > highest then highest = index end
      end
    end
  end

  return if highest then highest + 1 else 1
end

local function remapMasters(plugin: PluginData, master: PluginData, target: string)
  local pluginMasters = (plugin.header.masters or {}) :: { Master }
  local masterMasters = (master.header.masters or {}) :: { Master }
  local newMasters, remap = indexRemap(pluginMasters, masterMasters, target)
  local header = table.clone(master.header)
  header.masters = newMasters :: { Value }
  plugin.header = header

  local identity = true

  for index = 0, #pluginMasters do
    if remap[index] ~= index then
      identity = false
      break
    end
  end

  if identity then return end

  local nextIndex = nextReferenceIndex(master)

  for _, key in plugin.cells do
    local object = plugin.objects[key]
    local references = {}

    for _, reference in (object.references or {}) :: { Table } do
      local copy = table.clone(reference)

      if copy.mastIndex == 0 then
        copy.refrIndex = nextIndex
        nextIndex += 1
      else
        copy.mastIndex = remap[copy.mastIndex :: number]
      end

      table.insert(references, copy)
    end

    local cell = table.clone(object)
    cell.references = references
    plugin.objects[key] = cell
  end
end

-- A landscape's texture indices with `remap` applied. tes3conv spells the 16 by 16 grid as the
-- base64 of its 256 little-endian words; rows of numbers are remapped as they are.
local function remapIndices(data: Value, remap: { [number]: number }): Value
  if type(data) == 'string' then
    local words = bytes.fromBase64(data)

    for offset = 0, buffer.len(words) - 2, 2 do
      local new = remap[buffer.readu16(words, offset)]

      if new then buffer.writeu16(words, offset, new) end
    end

    return bytes.toBase64(words)
  end

  local rows = {}

  for row, values in data :: { { number } } do
    local copied = table.clone(values)

    for column, value in copied do
      local new = remap[value]

      if new then copied[column] = new end
    end

    rows[row] = copied
  end

  return rows
end

--- The highest index among the master's textures, met in the order its objects are kept in.
local function walkedHighest(master: PluginData): number?
  local highest: number? = nil

  for _, object in master.objects do
    if object.type == 'LandscapeTexture' then
      local index = object.index :: number

      if not highest or index > highest then highest = index end
    end
  end

  return highest
end

--- The highest index among the master's textures, or nil when it has none. Numbers come to
--- the same in any order, so only the textures are read; an index that isn't a number, or is
--- NaN, is told from the rest by where it is met, and has them all walked as they were.
local function highestTexture(master: PluginData): number?
  local highest: number? = nil

  for _, key in master.textures do
    local index = master.objects[key].index

    if type(index) ~= 'number' or index ~= index then return walkedHighest(master) end

    if not highest or index > highest then highest = index end
  end

  return highest
end

local function remapTextures(plugin: PluginData, master: PluginData, journal: Journal)
  local highest = highestTexture(master)

  if not highest then return end

  local nextIndex = (highest :: number) + 1
  local remap: { [number]: number } = {}

  for _, key in plugin.order do
    local texture = plugin.objects[key]

    if texture.type ~= 'LandscapeTexture' then continue end

    local existing = master.objects[key]
    local old = texture.index :: number
    local new: number

    if existing and existing.type == 'LandscapeTexture' then
      new = existing.index :: number
    else
      new = nextIndex
      nextIndex += 1
    end

    if old ~= new then
      local copy = table.clone(texture)
      copy.index = new
      plugin.objects[key] = copy
      remap[old + 1] = new + 1
      journal.summary.texturesRemapped += 1

      if journal.log then
        local id = tes3.string(texture.id)
        table.insert(journal.log, `Remapping texture index: ({old} -> {new}) {id}`)
      end
    end
  end

  if next(remap) == nil then return end

  for _, key in plugin.order do
    local land = plugin.objects[key]

    if land.type ~= 'Landscape' then continue end

    local indices = land.textureIndices :: Table?

    if not indices then continue end

    local copy = table.clone(land)
    local textures = table.clone(indices)
    textures.data = remapIndices(indices.data, remap)
    copy.textureIndices = textures
    plugin.objects[key] = copy
  end
end

local function removeIgnored(data: PluginData)
  -- Only another master's records are ignored. Without one, every object and INFO stays, and
  -- the topics alone are looked at.
  if next(data.ignored) == nil then
    for key, group in data.dialogues do
      if group.dialogue == nil then data.dialogues[key] = nil end
    end

    return
  end

  for key, object in data.objects do
    if data.ignored[object] then data.objects[key] = nil end
  end

  for key, group in data.dialogues do
    if group.dialogue == nil or data.ignored[group.dialogue :: Record] then
      data.dialogues[key] = nil
      continue
    end

    local node = group.head

    while node do
      local following = node.next

      if data.ignored[node.info] then
        unlink(group, node)
        group.byId[tes3.string(node.info.id)] = nil
      end

      node = following
    end
  end
end

-- merge_to_master's `remove_deleted`. It logs each object it removes, and each reference removed
-- because its object was: one marked deleted itself goes without a line.
local function removeDeleted(data: PluginData, journal: Journal)
  -- The ids of the objects removed, lowercased; and for each id a reference has, spelled as it
  -- has it, whether that is one of them. A master places the same few ids over and over.
  local deleted: { [string]: boolean }, orphans: { [string]: boolean } = {}, {}
  local summary, log = journal.summary, journal.log

  for _, key in data.order do
    local object = data.objects[key]

    -- Most objects have no flags at all, and so none to search for the deleted one.
    if not object or object.flags == '' or not tes3.isDeleted(object) then continue end

    local id = string.lower(tes3.editorId(object))
    data.objects[key] = nil
    deleted[id] = true
    summary.objectsRemoved += 1

    if log then table.insert(log, `Removed deleted object: {id}`) end
  end

  for _, key in data.cells do
    local object = data.objects[key]

    if not object then continue end

    local kept = {}

    for _, reference in (object.references or {}) :: { Table } do
      local ownReference = reference.mastIndex == 0
      local marked = ownReference and reference.deleted == true
      local orphaned = false

      if ownReference and not marked then
        local name = tes3.string(reference.id)
        local found = orphans[name]

        if found == nil then
          found = deleted[string.lower(name)] == true
          orphans[name] = found
        end

        orphaned = found
      end

      if not marked and not orphaned then
        table.insert(kept, reference)
        continue
      end

      summary.referencesRemoved += 1

      if orphaned and log then
        local id, cell = tes3.lower(reference.id), string.lower(tes3.editorId(object))
        local indices = `({reference.mastIndex}, {reference.refrIndex})`
        table.insert(log, `Removed deleted reference: {id} {indices} from {cell}`)
      end
    end

    local copy = table.clone(object)
    copy.references = kept
    data.objects[key] = copy
  end
end

local DialogueTypeOrder: { [string]: number } =
  { Topic = 0, Voice = 1, Greeting = 2, Persuasion = 3, Journal = 4 }

local function bytesLess(left: string, right: string): boolean return left < right end

-- What places an object among the others: its type's place in tes3's order, the number a
-- texture, an effect, or a skill sorts by, its id, and its rank among records of that id. A cell
-- goes by its name and a path grid by its cell's, the path grid second.
local function placing(record: Record): (number, number, string, number)
  local kind = record.type :: string
  local hint, id, rank = 0, tes3.string(record.id), 0

  if kind == 'LandscapeTexture' then
    hint = record.index :: number
    id = ''
  elseif kind == 'MagicEffect' then
    hint = tes3.EffectIndex[tes3.string(record.effectId)] or -1
    id = ''
  elseif kind == 'Skill' then
    hint = tes3.SkillIndex[tes3.string(record.skillId)] or -1
    id = ''
  elseif kind == 'Cell' then
    id = tes3.string(record.name)
  elseif kind == 'PathGrid' then
    id, rank = tes3.string(record.cell), 1
  elseif kind == 'Landscape' then
    id = ''
  end

  return tes3.SortOrder[kind], hint, id, rank
end

--- `data`'s objects in the order merge_to_master writes them, found by comparing them pair by
--- pair: whatever places them.
local function comparedObjects(data: PluginData): { Record }
  type Entry = {
    record: Record,
    order: number,
    hint: number,
    id: string,
    rank: number,
    position: number,
  }
  local entries: { Entry } = {}

  for position, key in data.order do
    local record = data.objects[key]

    if record == nil then continue end

    local order, hint, id, rank = placing(record)

    table.insert(entries, {
      record = record,
      order = order,
      hint = hint,
      id = id,
      rank = rank,
      position = position,
    })
  end

  table.sort(entries, function(left, right)
    if left.order ~= right.order then
      return left.order < right.order
    elseif left.hint ~= right.hint then
      return left.hint < right.hint
    elseif left.id ~= right.id then
      return bytesLess(left.id, right.id)
    elseif left.rank ~= right.rank then
      return left.rank < right.rank
    end

    return left.position < right.position
  end)

  return [for entry in entries => entry.record]
end

-- What one number places an object by, each part a whole number the next can't reach: its
-- type's place, then its hint, then where its id falls among the ids, then its rank. Together
-- they stay below 2^53, where a double holds every whole number.
local OrderLimit, HintLimit, HintSpan, IdSpan = 64, 4194303, 4194304, 16777216

-- `data`'s objects in the order merge_to_master writes them. Each one's place is written as one
-- number, the ids having been put in order among themselves first, and the numbers are sorted at
-- once, objects with the same one staying in their order. One whose type has no place, or whose
-- hint isn't a small whole number, has them all compared pair by pair instead.
local function orderedObjects(data: PluginData): { Record }
  local capacity = #data.order

  if capacity >= IdSpan then return comparedObjects(data) end

  local keys = buffer.create(capacity * 8)
  local found: { Record }, ids: { string } = table.create(capacity), table.create(capacity)
  local ranks: { [string]: number } = {}
  local distinct: { string } = {}
  local count = 0

  for _, key in data.order do
    local record = data.objects[key]

    if record == nil then continue end

    local order, hint, id, rank = placing(record)
    local placed = type(order) == 'number' and order % 1 == 0 and order >= 0 and order < OrderLimit
    local hinted = type(hint) == 'number' and hint % 1 == 0 and hint >= -1 and hint < HintLimit

    if not (placed and hinted) then return comparedObjects(data) end

    buffer.writef64(keys, count * 8, (order * HintSpan + hint + 1) * IdSpan * 2 + rank)
    count += 1
    found[count], ids[count] = record, id

    if id ~= '' and not ranks[id] then
      ranks[id] = 0
      table.insert(distinct, id)
    end
  end

  if count == 0 then return {} end

  table.sort(distinct)

  for rank, id in distinct do
    ranks[id] = rank
  end

  for position, id in ids do
    if id == '' then continue end

    local slot = (position - 1) * 8
    buffer.writef64(keys, slot, buffer.readf64(keys, slot) + ranks[id] * 2)
  end

  local sorted = buffer.create(count * 4)
  plane.argsort(keys, 'f64', 0, count, sorted)
  return [for position in sorted[1:count, 'u32'] => found[position + 1]]
end

-- `data`'s topics in the order merge_to_master writes them: journals first, the rest by dialogue
-- type and id. A topic is kept under its id, so no two have one, and each is placed by one
-- number: its type's place, then where its id falls among the ids.
local function orderedGroups(data: PluginData): { Group }
  local capacity = #data.dialogueOrder
  local span = capacity + 1
  local keys = buffer.create(capacity * 8)
  local groups: { Group }, ids: { string } = table.create(capacity), table.create(capacity)
  local count = 0

  for _, key in data.dialogueOrder do
    local group = data.dialogues[key]
    local dialogue = group and group.dialogue

    if not dialogue then continue end

    local kind = tes3.string(dialogue.dialogueType)
    local place = if kind == 'Journal' then 0 else (DialogueTypeOrder[kind] or 5) + 1
    buffer.writef64(keys, count * 8, place * span)
    count += 1
    groups[count], ids[count] = group, tes3.string(dialogue.id)
  end

  if count == 0 then return groups end

  local inOrder = table.clone(ids)
  local ranks: { [string]: number } = {}
  table.sort(inOrder)

  for rank, id in inOrder do
    ranks[id] = rank
  end

  for position, id in ids do
    local slot = (position - 1) * 8
    buffer.writef64(keys, slot, buffer.readf64(keys, slot) + ranks[id])
  end

  local sorted = buffer.create(count * 4)
  plane.argsort(keys, 'f64', 0, count, sorted)
  return [for position in sorted[1:count, 'u32'] => groups[position + 1]]
end

-- The order merge_to_master writes records in: tes3's type order, then each record's sort hint
-- and id; cells and path grids by name, each path grid after its cell; journals first among
-- topics, the rest by dialogue type and id.
local function intoRecords(data: PluginData): Records
  local objects = orderedObjects(data)
  local records: Records = table.create(#objects + 1)
  records[1] = data.header
  table.move(objects, 1, #objects, 2, records)

  -- SNDG (38) sorts after cells and before dialogue; it was placed with the objects above.
  for _, group in orderedGroups(data) do
    table.insert(records, group.dialogue :: Record)
    local node = group.head

    while node do
      table.insert(records, node.info)
      node = node.next
    end
  end

  return records
end

function mergeToMaster.merge(
  plugin: Records,
  master: Records,
  options: Options
): (Records, Summary)
  local target = options.masterName
  local journal: Journal = {
    summary = {
      merged = 0,
      copied = 0,
      texturesRemapped = 0,
      objectsRemoved = 0,
      referencesRemoved = 0,
    },
    log = options.log,
  }
  local pluginData = collect(plugin)
  local pluginMasters = (pluginData.header.masters or {}) :: { Master }
  local present = false

  for _, entry in pluginMasters do
    if sameName(masterName(entry), target) then
      present = true
      break
    end
  end

  if not present then
    local header = table.clone(pluginData.header)
    local masters = table.clone(pluginMasters)
    table.insert(masters, { target, 0 })
    header.masters = masters :: { Value }
    pluginData.header = header
    pluginMasters = masters
  end

  -- merge_masters: the target whole, every other master's dialogue as ignored context. The first
  -- of them merged into nothing is itself, so the rest are merged into it.
  local merged: PluginData? = nil
  local header: Record? = nil

  for _, entry in pluginMasters do
    local name = masterName(entry)
    local data: PluginData

    if sameName(name, target) then
      data = collect(master)
      header = data.header
    else
      local records = options.masters and options.masters[string.lower(name)]

      if not records then error(`merge_to_master needs the master '{name}'`) end

      data = collect(records, true)
      setAllIgnored(data)
    end

    if merged then
      mergeInto(data, merged)
    else
      merged = data
    end
  end

  local whole = merged or newData()
  whole.header = header or {}
  remapMasters(pluginData, whole, target)
  remapTextures(pluginData, whole, journal)
  mergeInto(pluginData, whole, journal)
  removeIgnored(whole)

  if options.removeDeleted then removeDeleted(whole, journal) end

  return intoRecords(whole), journal.summary
end

return mergeToMaster
