-- Smoke tests for GroupChevron/GroupChevron.lua against a minimal stub of the WoW API.
-- The stub only covers what the addon calls; it checks the glue code, not the real client.

local WHITE = { 1, 1, 1, 1 }
-- NAMEPLATE_FONT stands for Blizzard's nameplate font object.
local NAMEPLATE_FONT = { name = "SystemFont_NamePlate" }
-- textureMissing makes every SetTexture fail, as a client that cannot load the file.
local textureMissing = false
local BLUE = { 0, 0.5, 1, 1 }

local function newFontString(color, text)
  local fs = { color = { color[1], color[2], color[3], color[4] }, text = text or "Farbatosz Marokbar" }
  function fs:GetText() return self.text end
  function fs:SetAlpha(a) self.alpha = a end
  function fs:GetAlpha() return self.alpha or 1 end
  -- Blizzard's names use a font object (a font family with alphabet fallbacks).
  fs.fontObject = NAMEPLATE_FONT
  function fs:GetFontObject() return self.fontObject end
  function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
  function fs:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
  function fs:GetTextColor() return unpack(self.color) end
  fs.font = { "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" }
  function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
  function fs:GetFont() return unpack(self.font) end
  return fs
end

local function newRegion()
  local r = { shown = true, points = {} }
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i) return unpack(self.points[i] or {}) end
  function r:GetWidth() return self.width or 0 end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetAlpha(a) self.alpha = a end
  r.SetAllPoints = function() end
  function r:SetRotation(a) self.rotation = a end
  function r:SetScale(sc) self.scale = sc end
  function r:GetScale() return self.scale or 1 end
  function r:SetColorTexture(cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end
  -- Textures: the chevron's "V"s (a file path; a "missing" path fails to load).
  function r:SetTexture(path)
    self.texture = path
    return not textureMissing
  end
  function r:SetVertexColor(cr, cg, cb, ca) self.vertex = { cr, cg, cb, ca } end
  function r:SetTexCoord(...) self.texcoord = { ... } end
  function r:SetAtlas(name) self.atlas, self.texture = name, nil end
  return r
end

-- newLabel is a FontString created by the addon (the full name).
local function newLabel(parent)
  local l = newRegion()
  l.parent, l.kind = parent, "FontString"
  function l:SetFont(path, size, flags) self.font, self.fontObject = { path, size, flags }, nil end
  function l:SetFontObject(o) self.fontObject, self.font = o, nil end
  function l:SetText(t) self.text = t end
  function l:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
  return l
end

local function newFrame(parent)
  local f = newRegion()
  f.parent, f.events, f.textures = parent, {}, {}
  function f:RegisterEvent(e) self.events[e] = true end
  f.scripts = {}
  function f:SetScript(name, fn)
    self.scripts[name] = fn
    self.onEvent = fn
  end
  function f:CreateTexture()
    local t = newRegion()
    self.textures[#self.textures + 1] = t
    return t
  end
  f.labels = {}
  function f:CreateFontString()
    local l = newLabel(self)
    self.labels[#self.labels + 1] = l
    return l
  end
  return f
end

-- newPlate returns a nameplate showing unit, whose name FontString is in UnitFrame[field].
local function newPlate(unit, field, color)
  local uf = { unit = unit }
  if field then
    uf[field] = newFontString(color or WHITE)
  end
  return { UnitFrame = uf, namePlateUnitToken = unit }
end

-- newPart returns a frame or region of kind (e.g. "Frame", "Texture") with a real parent /
-- children / regions tree, added to parent's children (frames) or regions (anything else).
local function newPart(kind, parent, globalName, base)
  local o = base or newRegion()
  o.kind, o.parent, o.children, o.regions, o.globalName = kind, parent, {}, {}, globalName
  o.hooks = {}
  function o:GetParent() return self.parent end
  function o:GetChildren() return unpack(self.children) end
  function o:GetRegions() return unpack(self.regions) end
  function o:GetObjectType() return self.kind end
  function o:GetName() return self.globalName end
  function o:SetAlpha(a) self.alpha = a end
  if kind ~= "Texture" and kind ~= "FontString" then
    function o:HookScript(script, fn) self.hooks[#self.hooks + 1] = { script, fn } end
  end
  if parent then
    local list = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
    list[#list + 1] = o
  end
  return o
end

-- show runs the OnShow hooks of a part, as the game does when it shows it again.
local function show(part)
  part.alpha = 1
  for _, h in ipairs(part.hooks) do
    if h[1] == "OnShow" then
      h[2](part)
    end
  end
end

-- newTreePlate returns a plate shaped like the Forever client's (build 1.60.1): the name is a
-- region of UnitFrame (or, with nested, of a NameContainer frame inside it), next to a health
-- bar container, a cast bar and a classification texture.
local function newTreePlate(unit, nested)
  local uf = newPart("Button", nil)
  uf.unit = unit
  local holder = uf
  if nested then
    holder = newPart("Frame", uf)
    uf.NameContainer = holder
    uf.NameContainer.Glow = newPart("Texture", holder)
  end
  uf.name = newPart("FontString", holder, nil, newFontString(BLUE))
  uf.HealthBarsContainer = newPart("Frame", uf, "NamePlate1HealthBars")
  uf.HealthBarsContainer.bar = newPart("Texture", uf.HealthBarsContainer)
  uf.castBar = newPart("StatusBar", uf)
  uf.AurasFrame = newPart("Frame", uf)
  uf.classificationIndicator = newPart("Texture", uf)
  local plate = newPart("Frame", nil)
  plate.UnitFrame, plate.namePlateUnitToken = uf, unit
  uf.parent = plate
  return plate
end

-- load runs Core.lua and GroupChevron.lua in a fresh fake client.
-- NEUTRAL_SETTINGS are the settings the specs run with unless they say otherwise (see load).
local NEUTRAL_SETTINGS = {
  chevsize = 1, textsize = 1, buffsize = 1, namegap = 0, othernamegap = 0, font = "default", classcolor = false,
  hostilechevsize = 1, friendchevsize = 1, guildchevsize = 1, hostilesize = 1, hostilenamegap = 0, othersize = 1,
  friendsize = 1, guildsize = 1,
  -- Friendly NPCs are left as Blizzard draws them unless a spec turns their options on.
  npccompact = false,
}

local function load(opts)
  opts = opts or {}
  local env = {}
  local frames, printed, hooks = {}, {}, {}
  -- world.flist[unit] / world.bnet[unit]: the unit is on the character friends list / a
  -- Battle.net friend's character (by GUID "Player-<unit>"); world.timers: pending C_Timer.After.
  -- world.classes[unit]: the unit's class token (UnitClass); C_ClassColor knows MAGE and
  -- PRIEST, RAID_CLASS_COLORS MAGE, PRIEST and WARLOCK (so WARLOCK needs the fallback).
  local world = { plates = {}, players = {}, party = {}, friends = {}, health = {}, flist = {}, bnet = {},
    classes = {}, timers = {}, cvars = { nameplateShowFriends = "1" }, levels = {}, guilds = {},
    -- world.inGuild: the player is in a guild; world.guild[unit]: the unit is in the player's
    -- guild (UnitIsInMyGuild); world.guildCalls counts the guild questions asked.
    inGuild = false, guild = {}, guildCalls = 0,
    -- world.attackable[unit]: UnitCanAttack("player", unit); world.quests[unit]: the unit is tied
    -- to an active quest (C_QuestLog.UnitIsRelatedToActiveQuest); world.questCalls counts the asks.
    attackable = {}, quests = {}, questCalls = 0 }
  local modernColors = { MAGE = { 0, 1, 1 }, PRIEST = { 1, 1, 1 } }
  local api = {
    print = function(msg) printed[#printed + 1] = msg end,
    CreateFrame = function(_, _, parent)
      local f = newFrame(parent)
      frames[#frames + 1] = f
      if type(parent) == "table" and type(parent.children) == "table" then
        parent.children[#parent.children + 1] = f
      end
      return f
    end,
    C_NamePlate = {
      GetNamePlateForUnit = function(unit) return world.plates[unit] end,
      GetNamePlates = function()
        local out = {}
        for _, p in pairs(world.plates) do
          out[#out + 1] = p
        end
        return out
      end,
    },
    C_CVar = { GetCVar = function(name) return world.cvars[name] end },
    UnitIsPlayer = function(unit) return world.players[unit] == true end,
    UnitInParty = function(unit) return world.party[unit] == true end,
    UnitInRaid = function() return nil end,
    UnitIsUnit = function(a, b)
      if b == "target" then
        return world.target ~= nil and a == world.target
      end
      return a == b
    end,
    UnitIsFriend = function(a, b) return a == "player" and world.friends[b] == true end,
    UnitCanAttack = function(a, b) return a == "player" and world.attackable[b] == true end,
    C_QuestLog = {
      UnitIsRelatedToActiveQuest = function(unit)
        world.questCalls = world.questCalls + 1
        return world.quests[unit] == true
      end,
    },
    UnitGUID = function(unit) return "Player-" .. tostring(unit) end,
    C_FriendList = { IsFriend = function(guid) return world.flist[guid:sub(8)] == true end },
    C_BattleNet = {
      GetAccountInfoByGUID = function(guid)
        world.bnetCalls = (world.bnetCalls or 0) + 1
        if world.bnet[guid:sub(8)] then
          return { isFriend = true }
        end
        return nil
      end,
    },
    IsInGuild = function() return world.inGuild end,
    UnitIsInMyGuild = function(unit)
      world.guildCalls = world.guildCalls + 1
      return world.guild[unit] == true
    end,
    UnitClass = function(unit)
      local token = world.classes[unit]
      return token and ("Localised " .. token), token, 1
    end,
    C_ClassColor = {
      GetClassColor = function(token)
        local c = modernColors[token]
        return c and { GetRGB = function() return c[1], c[2], c[3] end } or nil
      end,
    },
    RAID_CLASS_COLORS = {
      MAGE = { r = 0, g = 1, b = 1 },
      PRIEST = { r = 1, g = 1, b = 1 },
      WARLOCK = { r = 1, g = 0, b = 1 },
    },
    C_Timer = { After = function(_, fn) world.timers[#world.timers + 1] = fn end },
    -- world.health[unit] = { hp, max }; unknown units are at full health.
    UnitHealth = function(unit) return (world.health[unit] or { 100, 100 })[1] end,
    UnitHealthMax = function(unit) return (world.health[unit] or { 100, 100 })[2] end,
    -- world.levels[unit]: the unit's level; unknown units have none (nil: not readable).
    UnitLevel = function(unit) return world.levels[unit] end,
    -- world.guilds[unit]: the name of the unit's guild (GetGuildInfo); unknown units have none.
    GetGuildInfo = function(unit) return world.guilds[unit] end,
    -- hooksecurefunc("Global", fn) or hooksecurefunc(object, "Method", fn): hooks[name] = fn.
    hooksecurefunc = function(a, b, c)
      if type(a) == "table" then
        hooks[b] = c
      else
        hooks[a] = b
      end
    end,
    CompactUnitFrame_UpdateName = function() end,
    SlashCmdList = {},
  }
  for k, v in pairs(opts.overrides or {}) do
    api[k] = v
  end
  if api.decorate then
    local base, decorate = api.CreateFrame, api.decorate
    api.decorate = nil
    api.CreateFrame = function(kind, name, parent, template)
      return decorate(base(kind, name, parent, template), kind, parent, template)
    end
  end
  for k, v in pairs(api) do
    env[k] = v
  end
  env._G = env
  env.GroupChevronDB = opts.saved
  if not opts.factory and (opts.saved == nil or type(opts.saved) == "table") then
    -- Most specs were written for neutral settings (size 1, no name gap, Blizzard's font, class
    -- colour off): fill them in unless the spec sets its own or asks for the factory defaults
    -- (opts.factory), which are what a new install gets.
    env.GroupChevronDB = opts.saved or {}
    for k, v in pairs(NEUTRAL_SETTINGS) do
      if env.GroupChevronDB[k] == nil then
        env.GroupChevronDB[k] = v
      end
    end
  end
  setmetatable(env, { __index = _G })

  local ns = {}
  for _, file in ipairs({ "GroupChevron/NpcRoles.lua", "GroupChevron/Core.lua", "GroupChevron/GroupChevron.lua" }) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)
    chunk("GroupChevron", ns)
    -- opts.shipped stands for the roles shipped with the addon (NpcRoles.lua); the specs never
    -- depend on the real list, which grows with every import.
    if file == "GroupChevron/NpcRoles.lua" then
      ns.NpcRoles = opts.shipped or {}
    end
  end
  env.frames, env.printed, env.hooks, env.world = frames, printed, hooks, world
  env.fire = function(event, ...)
    for _, f in ipairs(frames) do
      if f.events[event] and f.onEvent then
        f.onEvent(f, event, ...)
      end
    end
  end
  env.slash = function(msg) env.SlashCmdList.GROUPCHEVRON(msg) end
  -- runTimers runs the pending C_Timer.After callbacks.
  env.runTimers = function()
    local pending = world.timers
    world.timers = {}
    for _, fn in ipairs(pending) do
      fn()
    end
  end
  -- chevron returns the chevron frame created on a plate's UnitFrame, if any.
  env.chevron = function(plate)
    for _, f in ipairs(frames) do
      if f.parent == plate.UnitFrame and #f.textures > 0 then
        return f
      end
    end
    return nil
  end
  -- label returns the addon's full-name FontString on a plate, if any.
  env.label = function(plate)
    for _, f in ipairs(frames) do
      if f.parent == plate.UnitFrame and #f.labels > 0 then
        return f.labels[1], f
      end
    end
    return nil
  end
  env.fire("ADDON_LOADED", "GroupChevron")
  return env
end

-- vcount counts the "V" textures of a chevron frame (not their black outlines).
local function vcount(frame)
  local n = 0
  for _, t in ipairs(frame.textures) do
    if t.texture == "Interface\\AddOns\\GroupChevron\\chevron.tga" and not t.owner then
      n = n + 1
    end
  end
  return n
end

local function hex(c)
  return string.format("#%02X%02X%02X", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
    math.floor(c[3] * 255 + 0.5))
end

local function printedContains(env, s)
  for _, line in ipairs(env.printed) do
    if line:find(s, 1, true) then
      return true
    end
  end
  return false
end

describe("GroupChevron", function()
  it("initialises its SavedVariables and hooks the name update", function()
    local env = load({ saved = { enabled = "bad" } })
    assert.is_true(env.GroupChevronDB.enabled)
    assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))
    assert.is_function(env.hooks.CompactUnitFrame_UpdateName)
  end)

  it("gives a new install the factory defaults of the settings page", function()
    local db = load({ factory = true }).GroupChevronDB
    assert.is_true(db.enabled)
    assert.are.equal("#FF4FD8", hex(db.color))
    assert.are.equal("outline", db.font)
    assert.are.equal(3, db.chevsize)
    assert.are.equal(1.75, db.textsize)
    assert.are.equal(1, db.barsize)
    assert.are.equal(1.1, db.buffsize)
    assert.are.equal(5, db.namegap)
    assert.is_true(db.compact)
    assert.is_true(db.classcolor)
    assert.is_true(db.showlevel)
    assert.are.equal(1.5, db.othersize)
    assert.are.equal(1, db.otherbarsize)
    assert.are.equal(5, db.othernamegap)
    assert.are.equal("#3FA7FF", hex(db.friendcolor))
    assert.is_true(db.friendchevron)
    assert.is_true(db.bnetfriends)
    assert.are.equal("#40FF40", hex(db.guildcolor))
    assert.is_true(db.guildchevron)
    -- The hostiles start like the friendlies: chevron at the friends' chevron size, text size 1.5,
    -- name height 5; the colour is yellow. Friends and guildmates: text size 1.75.
    assert.are.equal("#FFFF00", hex(db.hostilecolor))
    assert.are.equal(3, db.hostilechevsize)
    assert.are.equal(1.5, db.hostilesize)
    assert.are.equal(1.75, db.friendsize)
    assert.are.equal(1.75, db.guildsize)
    assert.are.equal(5, db.hostilenamegap)
  end)

  it("keeps the values a player already saved when the defaults change", function()
    local db = load({ factory = true, saved = { chevsize = 1, textsize = 2, namegap = 0, font = "default",
      classcolor = false } }).GroupChevronDB
    assert.are.equal(1, db.chevsize)
    assert.are.equal(2, db.textsize)
    assert.are.equal(0, db.namegap)
    assert.are.equal("default", db.font)
    assert.is_false(db.classcolor)
    assert.are.equal(1.1, db.buffsize) -- never saved: the new default
  end)

  it("marks a group member and leaves everyone else alone", function()
    local env = load()
    local member = newPlate("nameplate1", "name", BLUE)
    local stranger = newPlate("nameplate2", "name", BLUE)
    env.world.plates.nameplate1, env.world.plates.nameplate2 = member, stranger
    env.world.players.nameplate1, env.world.players.nameplate2 = true, true
    env.world.party.nameplate1 = true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")

    assert.are.equal("#FF4FD8", hex(member.UnitFrame.name.color))
    assert.are.equal("#FF4FD8", hex(member.UnitFrame.name.vertex))
    local ch = env.chevron(member)
    assert.is_truthy(ch)
    assert.is_true(ch.shown)
    assert.are.equal(2, vcount(ch))
    assert.are.equal("Interface\\AddOns\\GroupChevron\\chevron.tga", ch.textures[1].texture)
    assert.are.equal("#FF4FD8", hex(ch.textures[1].vertex))
    -- The full name is ours, in pink, over Blizzard's (faded), and carries the chevron.
    local label, holder = env.label(member)
    assert.is_true(holder.shown)
    assert.are.equal("Farbatosz Marokbar", label.text)
    assert.are.equal("#FF4FD8", hex(label.color))
    assert.are.equal(NAMEPLATE_FONT, label.fontObject) -- Blizzard's font object: same alphabets
    assert.are.equal(1, holder.scale)
    assert.are.equal(member.UnitFrame.name, label.points[1][2])
    assert.are.equal(0, member.UnitFrame.name.alpha)
    assert.are.equal(label, ch.points[1][2]) -- anchored to our name
    assert.is_nil(env.label(stranger))
    assert.is_nil(stranger.UnitFrame.name.alpha)
    assert.are.same(BLUE, stranger.UnitFrame.name.color)
    assert.is_nil(stranger.UnitFrame.name.vertex)
    assert.is_nil(env.chevron(stranger))

    -- Blizzard recolours the name: the hook puts our colour back.
    member.UnitFrame.name:SetTextColor(unpack(WHITE))
    env.hooks.CompactUnitFrame_UpdateName(member.UnitFrame)
    assert.are.equal("#FF4FD8", hex(member.UnitFrame.name.color))
    -- ... never for someone else.
    env.hooks.CompactUnitFrame_UpdateName(stranger.UnitFrame)
    assert.are.same(BLUE, stranger.UnitFrame.name.color)
  end)

  it("never leaves a mark on a plate that leaves the group or is recycled", function()
    local env = load()
    local plate = newPlate("nameplate1", "name", BLUE)
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local ch = env.chevron(plate)
    assert.is_true(ch.shown)

    -- Leaves the group: chevron hidden, the colour from before is back.
    env.world.party.nameplate1 = nil
    env.fire("GROUP_ROSTER_UPDATE")
    assert.is_false(ch.shown)
    assert.are.same(BLUE, plate.UnitFrame.name.color)

    -- Joins again, then the plate is removed and reused for a stranger.
    env.world.party.nameplate1 = true
    env.fire("GROUP_ROSTER_UPDATE")
    assert.is_true(ch.shown)
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    assert.is_false(ch.shown)
    assert.are.same(BLUE, plate.UnitFrame.name.color)
    env.world.party.nameplate1 = nil
    plate.UnitFrame.name:SetTextColor(1, 0, 0) -- Blizzard colours the new unit
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert.is_false(ch.shown)
    assert.are.same({ 1, 0, 0, 1 }, plate.UnitFrame.name.color)
    -- One chevron frame and one name frame per plate, reused.
    env.world.party.nameplate1 = true
    env.fire("GROUP_ROSTER_UPDATE")
    local n = 0
    for _, f in ipairs(env.frames) do
      if f.parent == plate.UnitFrame then
        n = n + 1
      end
    end
    assert.are.equal(2, n)
  end)

  it("handles /gchev", function()
    local env = load()
    local plate = newPlate("nameplate1", "Name", BLUE)
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local fs = plate.UnitFrame.Name

    env.slash("")
    assert.is_true(printedContains(env, "on, colour #FF4FD8, name field: UnitFrame.Name"))

    env.slash("color #00ff00")
    assert.are.equal("#00FF00", hex(fs.color))
    assert.are.equal("#00FF00", hex(env.chevron(plate).textures[1].vertex))
    env.slash("color nope")
    assert.is_true(printedContains(env, "invalid colour"))
    assert.are.equal("#00FF00", hex(env.GroupChevronDB.color))

    -- off restores the colour Blizzard had set, not one of ours.
    env.slash("off")
    assert.is_false(env.GroupChevronDB.enabled)
    assert.are.same(BLUE, fs.color)
    assert.is_false(env.chevron(plate).shown)
    env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
    assert.are.same(BLUE, fs.color)

    env.slash("ON")
    env.slash("reset")
    assert.are.equal("#FF4FD8", hex(fs.color))
    assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))

    env.world.plates.target = plate
    env.slash("debug")
    assert.is_true(printedContains(env, "name field UnitFrame.Name, group member: yes"))
  end)

  it("draws the chevron without a name field and says so once", function()
    local env = load()
    local plate = newPlate("nameplate1", nil)
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    env.fire("GROUP_ROSTER_UPDATE")
    local ch = env.chevron(plate)
    assert.is_true(ch.shown)
    assert.are.equal(plate.UnitFrame, ch.points[1][2])
    local n = 0
    for _, line in ipairs(env.printed) do
      if line:find("name text not found", 1, true) then
        n = n + 1
      end
    end
    assert.are.equal(1, n)
  end)

  it("sets chevsize and textsize with /gchev, refusing invalid values", function()
    local env = load()
    local plate = newPlate("nameplate1", "name", BLUE)
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local ch = env.chevron(plate)
    local w, h = ch.w, ch.h
    local arm = ch.textures[1]
    local armW = arm.w
    local label = env.label(plate)

    env.slash("textsize")
    assert.is_true(printedContains(env, "textsize 1"))
    for _, bad in ipairs({ "textsize 3.1", "textsize 0.9", "textsize abc" }) do
      env.slash(bad)
      assert.is_true(printedContains(env, "from 1 to 3"))
    end
    env.slash("chevsize 5.05")
    assert.is_true(printedContains(env, "from 1 to 5"))
    assert.are.equal(1, env.GroupChevronDB.textsize)
    assert.are.equal(1, env.GroupChevronDB.chevsize)
    assert.are.equal(10, plate.UnitFrame.name.font[2])

    env.slash("textsize 2")
    env.slash("chevsize 2")
    assert.are.equal(2, env.GroupChevronDB.textsize)
    assert.are.equal(2, env.GroupChevronDB.chevsize)
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" }, plate.UnitFrame.name.font) -- never SetFont
    local _, holder = env.label(plate)
    assert.are.equal(2, holder.scale)
    assert.are.equal(NAMEPLATE_FONT, label.fontObject)
    assert.are.equal(w * 2, ch.w)
    assert.are.equal(h * 2, ch.h)
    assert.are.equal(armW * 2, arm.w)
    assert.are.equal(2, ch.points[1][5]) -- the gap is not scaled
    assert.are.equal(1, ch.textures[1].alpha)
    assert.are.equal(0.5, ch.textures[2].alpha)
    -- The second "V" sits twice as far below the first.
    local dy = ch.textures[1].points[1][5] - ch.textures[2].points[1][5]
    assert.are.near(8, dy, 1e-9)
  end)

  it("enlarges the name of group members only, never touching Blizzard's font", function()
    local env = load({ saved = { textsize = 2 } })
    local member = newPlate("nameplate1", "name", BLUE)
    local stranger = newPlate("nameplate2", "name", BLUE)
    env.world.plates.nameplate1, env.world.plates.nameplate2 = member, stranger
    env.world.players.nameplate1, env.world.players.nameplate2 = true, true
    env.world.party.nameplate1 = true
    env.world.friends.nameplate2 = true -- compact: our name at the normal size
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    local orig = { "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" }
    local _, mh = env.label(member)
    local sl, sh = env.label(stranger)
    assert.are.equal(2, mh.scale)
    assert.are.equal(1, sh.scale)
    assert.are.same(BLUE, sl.color)
    assert.are.equal(NAMEPLATE_FONT, sl.fontObject)

    -- Refreshes and Blizzard updates keep the factor (a scale, never compounded).
    for _ = 1, 3 do
      env.fire("GROUP_ROSTER_UPDATE")
      env.hooks.CompactUnitFrame_UpdateName(member.UnitFrame)
    end
    assert.are.equal(2, mh.scale)

    -- Recycled for a stranger, turned off, factor changed: Blizzard's font is never changed.
    env.world.party.nameplate1 = nil
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    env.world.party.nameplate1 = true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    env.slash("textsize 1.5")
    assert.are.equal(1.5, mh.scale)
    env.slash("off")
    assert.is_false(mh.shown)
    assert.are.equal(1, member.UnitFrame.name.alpha)
    for _, p in ipairs({ member, stranger }) do
      assert.are.same(orig, p.UnitFrame.name.font)
      assert.are.equal(NAMEPLATE_FONT, p.UnitFrame.name.fontObject)
    end
  end)

  it("uses the font of a name without a font object, or leaves an unreadable one alone", function()
    local env = load({ saved = { textsize = 2 } })
    local plate = newPlate("nameplate1", "name", BLUE)
    plate.UnitFrame.name.fontObject = nil
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local label, holder = env.label(plate)
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" }, label.font)
    assert.are.equal(2, holder.scale)

    -- Neither a font object nor a readable font: Blizzard's name stays, pink, as it was.
    local other = newPlate("nameplate3", "name", BLUE)
    other.UnitFrame.name.fontObject = nil
    other.UnitFrame.name.GetFont = function() error("boom") end
    env.world.plates.nameplate3 = other
    env.world.players.nameplate3, env.world.party.nameplate3 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    assert.is_nil(env.label(other))
    assert.is_nil(other.UnitFrame.name.alpha)
    assert.are.equal(10, other.UnitFrame.name.font[2])
    assert.are.equal("#FF4FD8", hex(other.UnitFrame.name.color))
    -- Without a name FontString, textsize is a no-op and the chevron still shows.
    local bare = newPlate("nameplate2", nil)
    env.world.plates.nameplate2 = bare
    env.world.players.nameplate2, env.world.party.nameplate2 = true, true
    assert.has_no.errors(function() env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2") end)
    assert.is_true(env.chevron(bare).shown)
  end)

  it("draws the full name, never cut, and gives Blizzard's name back", function()
    local env = load()
    local plate = newPlate("nameplate1", "name", BLUE)
    plate.UnitFrame.name.text = "Farbatosz Marokbar-Longrealm"
    env.world.plates.nameplate1 = plate
    env.world.players.nameplate1, env.world.party.nameplate1 = true, true
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local label, holder = env.label(plate)
    assert.are.equal("Farbatosz Marokbar-Longrealm", label.text)
    assert.are.equal(0, plate.UnitFrame.name.alpha)

    -- Blizzard changes the text: the hook copies it.
    plate.UnitFrame.name.text = "Renamed"
    env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
    assert.are.equal("Renamed", label.text)

    -- Leaves the group (not a friend: default plate): our name hidden, Blizzard's back.
    env.world.party.nameplate1 = nil
    env.fire("GROUP_ROSTER_UPDATE")
    assert.is_false(holder.shown)
    assert.are.equal(1, plate.UnitFrame.name.alpha)

    -- A name we cannot read stays Blizzard's: no fading, chevron on Blizzard's name.
    plate.UnitFrame.name.GetText = function() error("secret") end
    env.world.party.nameplate1 = true
    env.fire("GROUP_ROSTER_UPDATE")
    assert.is_false(holder.shown)
    assert.are.equal(1, plate.UnitFrame.name.alpha)
    assert.are.equal(plate.UnitFrame.name, env.chevron(plate).points[1][2])
    assert.are.equal("#FF4FD8", hex(plate.UnitFrame.name.color))
  end)

  it("falls back to a drawn chevron when the texture cannot be loaded", function()
    textureMissing = true
    local ok, err = pcall(function()
      local env = load()
      local plate = newPlate("nameplate1", "name", BLUE)
      env.world.plates.nameplate1 = plate
      env.world.players.nameplate1, env.world.party.nameplate1 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      local ch = env.chevron(plate)
      assert.is_true(ch.shown)
      local arms = 0
      for _, t in ipairs(ch.textures) do
        if t.color then
          arms = arms + 1
          assert.are.equal("#FF4FD8", hex(t.color))
        end
      end
      assert.are.equal(4, arms)
      assert.is_true(printedContains(env, "chevron texture not found"))
    end)
    textureMissing = false
    assert(ok, err)
  end)

  it("says once when friendly nameplates are off", function()
    local env = load()
    env.world.cvars.nameplateShowFriends = "0"
    env.fire("PLAYER_ENTERING_WORLD")
    env.fire("PLAYER_ENTERING_WORLD")
    local n = 0
    for _, line in ipairs(env.printed) do
      if line:find("friendly player nameplates are off", 1, true) then
        n = n + 1
      end
    end
    assert.are.equal(1, n)
  end)

  it("never lets an error reach the UI and reports it once", function()
    local env = load({ overrides = { UnitIsPlayer = function() error("boom") end } })
    local plate = newPlate("nameplate1", "name", BLUE)
    env.world.plates.nameplate1 = plate
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert.are.same(BLUE, plate.UnitFrame.name.color) -- errors count as "not a member"

    -- A forbidden plate (friendly plates in instances) is skipped without any message.
    env.C_NamePlate.GetNamePlates = function() error("boom") end
    env.world.plates.nameplate1 = setmetatable({}, { __index = function() error("forbidden") end })
    assert.has_no.errors(function()
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
      env.fire("PLAYER_TARGET_CHANGED")
      env.fire("GROUP_ROSTER_UPDATE")
      env.hooks.CompactUnitFrame_UpdateName(env.world.plates.nameplate1)
    end)
    assert.are.equal(0, #env.printed)

    -- Any other error is reported once.
    local env2 = load()
    local broken = newPlate("nameplate1", "name", BLUE)
    broken.UnitFrame.name.SetTextColor = function() error("boom") end
    env2.world.plates.nameplate1 = broken
    env2.world.players.nameplate1, env2.world.party.nameplate1 = true, true
    assert.has_no.errors(function()
      env2.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      env2.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    end)
    local n = 0
    for _, line in ipairs(env2.printed) do
      if line:find("GChev", 1, true) and line:find("NAME_PLATE_UNIT_ADDED", 1, true) then
        n = n + 1
      end
    end
    assert.are.equal(1, n)
  end)

  describe("compact mode", function()
    -- alphas returns the alpha of the parts compact mode touches (nil = never touched).
    local function alphas(plate)
      local uf = plate.UnitFrame
      return { uf.HealthBarsContainer.alpha, uf.castBar.alpha, uf.classificationIndicator.alpha }
    end

    local function untouchedAncestry(env, plate)
      local uf = plate.UnitFrame
      assert.is_nil(plate.alpha)
      assert.is_nil(uf.alpha)
      -- Blizzard's name is replaced by the addon's full name (same colour, base size).
      assert.are.equal(0, uf.name.alpha)
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.is_nil(holder.alpha)
      assert.are.same(uf.name.color, label.color)
      assert.are.equal(uf.name.text, label.text)
      assert.is_true(plate.shown)
      assert.is_true(uf.shown)
      assert.is_nil(uf.HealthBarsContainer.bar.alpha) -- inside a faded frame: left alone
    end

    -- friend sets up a friendly non-member player on nameplate2.
    local function friend(env, plate)
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    end

    it("is on by default and shows only the name of friendly non-members", function()
      local env = load()
      assert.is_true(env.GroupChevronDB.compact)
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      untouchedAncestry(env, plate)
      assert.are.same(BLUE, plate.UnitFrame.name.color) -- game colour untouched
      assert.is_nil(env.chevron(plate))

      -- The game shows a part again: faded at once, and each frame is hooked only once.
      for _ = 1, 3 do
        env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
        env.fire("GROUP_ROSTER_UPDATE")
      end
      assert.are.equal(1, #plate.UnitFrame.castBar.hooks)
      assert.are.equal(1, #plate.UnitFrame.HealthBarsContainer.hooks)
      show(plate.UnitFrame.castBar)
      assert.are.equal(0, plate.UnitFrame.castBar.alpha)

      -- A part that appears later is caught by the next name update.
      local late = newPart("Frame", plate.UnitFrame)
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.equal(0, late.alpha)
    end)

    it("shows the health bar of a hurt friend, and fades it again once healed", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      env.world.health.nameplate2 = { 40, 100 }
      friend(env, plate)
      assert.is_nil(uf.HealthBarsContainer.alpha) -- never faded
      assert.are.same({ 0, 0 }, { uf.castBar.alpha, uf.classificationIndicator.alpha })

      -- Healed: the bar is faded on the next health event, and stays faded when shown again.
      env.world.health.nameplate2 = { 100, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      show(uf.HealthBarsContainer)
      assert.are.equal(0, uf.HealthBarsContainer.alpha)

      -- Hurt again: the bar comes back at once, and a later OnShow does not fade it.
      env.world.health.nameplate2 = { 99, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 1, 0, 0 }, alphas(plate))
      show(uf.HealthBarsContainer)
      assert.are.equal(1, uf.HealthBarsContainer.alpha)
      env.hooks.CompactUnitFrame_UpdateName(uf)
      assert.are.same({ 1, 0, 0 }, alphas(plate))

      -- Max health raised: the same check.
      env.world.health.nameplate2 = { 99, 99 }
      env.fire("UNIT_MAXHEALTH", "nameplate2")
      assert.are.same({ 0, 0, 0 }, alphas(plate))

      -- Health events for other plates, members or unknown units change nothing.
      assert.has_no.errors(function()
        env.fire("UNIT_HEALTH", "player")
        env.fire("UNIT_HEALTH", "nameplate9")
        env.fire("UNIT_HEALTH", nil)
      end)
      assert.are.same({ 0, 0, 0 }, alphas(plate))

      -- An unreadable health counts as full (Core.HealthMissing, see its spec): name only.
      env.world.health.nameplate2 = { "?", 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
    end)

    describe("with secret health (health curve)", function()
      -- secrets: poison value -> the number it stands for (only the spec's fakes look it up).
      local secrets = setmetatable({}, { __mode = "k" })
      -- secret returns a value standing for v that raises an error on any read: arithmetic,
      -- comparison, concatenation, indexing, calling or tostring, as a secret value in game.
      local function secret(v)
        local p = newproxy(true)
        local mt = getmetatable(p)
        local function boom() error("secret value read") end
        for _, k in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len",
          "__eq", "__lt", "__le", "__index", "__newindex", "__call", "__tostring" }) do
          mt[k] = boom
        end
        secrets[p] = v
        return p
      end
      local function isSecret(v) return secrets[v] ~= nil end

      -- curveAPI fakes a client with secret health values: UnitHealth / UnitHealthMax /
      -- UnitHealthPercent are secret; UnitHealthPercent(unit, false, curve) gives a colour whose alpha is the curve
      -- (piecewise linear between its points) at the health fraction, secret too. s.calls counts
      -- the UnitHealthPercent calls with a curve, s.curves the curves built; health is read
      -- from s.env.world.health (s.env is set once loaded).
      local function curveAPI(s)
        local function health(unit)
          return s.env.world.health[unit] or { 100, 100 }
        end
        local function fraction(unit)
          local h = health(unit)
          return h[1] / h[2]
        end
        return {
          issecretvalue = isSecret,
          UnitHealth = function(unit) return secret(health(unit)[1]) end,
          UnitHealthMax = function(unit) return secret(health(unit)[2]) end,
          CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
          C_CurveUtil = {
            CreateColorCurve = function()
              local curve = { points = {} }
              function curve:AddPoint(x, c) self.points[#self.points + 1] = { x, c } end
              s.curves[#s.curves + 1] = curve
              return curve
            end,
          },
          UnitHealthPercent = function(unit, predicted, curve)
            if s.fail then
              error("UnitHealthPercent refused")
            end
            local x = fraction(unit)
            if curve == nil then
              return secret(x)
            end
            assert(predicted == false)
            s.calls, s.last = s.calls + 1, curve
            local pts, a = curve.points, curve.points[#curve.points][2].a
            for i = 2, #pts do
              if x <= pts[i][1] then
                local x0, a0, x1, a1 = pts[i - 1][1], pts[i - 1][2].a, pts[i][1], pts[i][2].a
                a = a0 + (a1 - a0) * (x - x0) / (x1 - x0)
                break
              end
            end
            return { GetRGBA = function() return 1, 1, 1, secret(a) end }
          end,
        }
      end

      -- setup returns a fresh client with secret health and a compact friend on nameplate2 (hurt
      -- at 40 / 100). The health bar records the number behind the secret it is given, and
      -- refuses one while s.refuse is set (a frame that prevents secret values).
      local function setup(s, opts)
        s.calls, s.curves = 0, {}
        -- Health events before ADDON_LOADED read nothing; the world exists once loaded.
        s.env = { world = { health = {} } }
        local overrides = curveAPI(s)
        for k, v in pairs(opts or {}) do
          overrides[k] = v
        end
        local env = load({ overrides = overrides })
        s.env = env
        local plate = newTreePlate("nameplate2")
        local bar = plate.UnitFrame.HealthBarsContainer
        bar.given = 0
        function bar:IsShown() return self.shown end
        function bar:GetAlpha() return self.alpha or 1 end
        function bar:SetAlpha(a)
          if isSecret(a) then
            if s.refuse then
              error("Attempt to add secret aspect on an object that prevents secret values")
            end
            self.given = self.given + 1
            a = secrets[a]
          end
          self.alpha = a
        end
        env.world.health.nameplate2 = { 40, 100 }
        friend(env, plate)
        return env, plate
      end

      it("shows the bar of a hurt friend from the curve's secret alpha, and fades it at full health", function()
        local s = {}
        local env, plate = setup(s)
        local uf = plate.UnitFrame
        -- The curve: built once, white, alpha 1 below full health and 0 at full health.
        assert.are.equal(1, #s.curves)
        local pts = s.curves[1].points
        assert.are.same({ 0, 0.999, 1 }, { pts[1][1], pts[2][1], pts[3][1] })
        assert.are.same({ 1, 1, 0 }, { pts[1][2].a, pts[2][2].a, pts[3][2].a })
        assert.are.same({ 1, 1, 1 }, { pts[1][2].r, pts[1][2].g, pts[1][2].b })
        assert.are.equal(s.curves[1], s.last)
        -- Hurt: the bar gets the curve's alpha (given straight, as a secret), the rest is faded.
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        assert.are.equal(1, uf.HealthBarsContainer.given)

        -- Healed: applied again on the health event, without comparing it with the last one.
        env.world.health.nameplate2 = { 100, 100 }
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        -- The game shows the bar again: the curve's alpha again, not a fade.
        show(uf.HealthBarsContainer)
        assert.are.equal(0, uf.HealthBarsContainer.alpha)
        env.world.health.nameplate2 = { 99, 100 }
        show(uf.HealthBarsContainer)
        assert.are.equal(1, uf.HealthBarsContainer.alpha)

        -- Every health event re-applies it (the same answer too: it cannot be compared).
        local given = uf.HealthBarsContainer.given
        env.fire("UNIT_HEALTH", "nameplate2")
        env.fire("UNIT_MAXHEALTH", "nameplate2")
        assert.are.equal(given + 2, uf.HealthBarsContainer.given)
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        env.world.health.nameplate2 = { 77, 77 }
        env.fire("UNIT_MAXHEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        -- Name updates and other units change nothing; the curve is still built only once.
        env.world.health.nameplate2 = { 10, 100 }
        env.hooks.CompactUnitFrame_UpdateName(uf)
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        assert.has_no.errors(function()
          env.fire("UNIT_HEALTH", "player")
          env.fire("UNIT_HEALTH", "nameplate9")
        end)
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        assert.are.equal(1, #s.curves)
        assert.is_false(printedContains(env, "error in"))
      end)

      it("gives the bar alpha 1 back when the plate stops being compact", function()
        local s = {}
        local env, plate = setup(s)
        local uf = plate.UnitFrame
        env.world.health.nameplate2 = { 100, 100 }
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))

        -- Targeted: the full plate, every part (the bar included) back at 1; OnShow leaves it.
        env.world.target = "nameplate2"
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 1, 1, 1 }, alphas(plate))
        show(uf.HealthBarsContainer)
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 1, 1, 1 }, alphas(plate))

        -- Untargeted: compact again; then compact off.
        env.world.target = nil
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        env.slash("compact off")
        assert.are.same({ 1, 1, 1 }, alphas(plate))
        assert.is_false(printedContains(env, "error in"))
      end)

      it("keeps the plate name-only when the curve fails, and never reads the secret health", function()
        -- UnitHealthPercent raises an error: the fallback reads UnitHealth / UnitHealthMax, which
        -- are secret, so the health counts as unknown: name only.
        local s = { fail = true }
        local env, plate = setup(s)
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))

        -- It works again: the next plate refresh drives the bar by the curve ...
        s.fail = false
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        -- ... and fails again later: the health event compacts the plate again, name only.
        s.fail = true
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        show(plate.UnitFrame.HealthBarsContainer)
        assert.are.equal(0, plate.UnitFrame.HealthBarsContainer.alpha)

        -- The bar refuses a secret alpha: faded instead (name only), no error.
        s.fail, s.refuse = false, true
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        assert.is_false(printedContains(env, "error in"))
      end)

      it("falls back to the readable health without the curve API", function()
        for _, missing in ipairs({ "UnitHealthPercent", "C_CurveUtil", "CreateColor" }) do
          local s = {}
          local env, plate = setup(s, {
            [missing] = false,
            -- Readable health, as on clients without secret values.
            UnitHealth = function(unit) return (s.env.world.health[unit] or { 100, 100 })[1] end,
            UnitHealthMax = function(unit) return (s.env.world.health[unit] or { 100, 100 })[2] end,
          })
          env.fire("UNIT_HEALTH", "nameplate2")
          assert.is_nil(plate.UnitFrame.HealthBarsContainer.alpha, missing) -- hurt: never faded
          assert.are.equal(0, s.calls)
          env.world.health.nameplate2 = { 100, 100 }
          env.fire("UNIT_HEALTH", "nameplate2")
          assert.are.same({ 0, 0, 0 }, alphas(plate))
          assert.is_false(printedContains(env, "error in"))
        end
      end)

      it("drops a compact plate's level while the curve shows the bar, and keeps it in doubt", function()
        local s = {}
        local env, plate = setup(s)
        env.world.levels.nameplate2 = 19
        env.fire("UNIT_LEVEL", "nameplate2")
        local label, holder = env.label(plate)
        local short = holder.labels[2]
        assert.is_truthy(short)
        local NAME = "Farbatosz Marokbar"
        -- visible lists the texts of our labels at alpha 1 (the numbers behind the secrets).
        local function visible()
          local out = {}
          for _, l in ipairs({ label, short }) do
            local a = l.alpha
            if secrets[a] ~= nil then
              a = secrets[a]
            end
            if a == 1 then
              out[#out + 1] = l.text
            end
          end
          return out
        end
        assert.are.equal(0, plate.UnitFrame.name.alpha) -- Blizzard's name covered by ours
        -- Both curves: built once each; the name with the level follows the opposite one.
        assert.are.equal(2, #s.curves)
        local pts = s.curves[2].points
        assert.are.same({ 0, 0, 1 }, { pts[1][2].a, pts[2][2].a, pts[3][2].a })
        -- Hurt (40 %): the bar is shown, so the name alone.
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        assert.are.same({ NAME }, visible())
        -- Both labels look the same and sit on the same spot.
        assert.are.same(label.color, short.color)
        assert.are.equal(NAMEPLATE_FONT, short.fontObject)
        assert.are.same(label.points, short.points)

        -- Healed: the suffix is back on the health event, with no plate re-add; hurt: gone.
        env.world.health.nameplate2 = { 100, 100 }
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        assert.are.same({ NAME .. " (19)" }, visible())
        env.world.health.nameplate2 = { 99, 100 }
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ NAME }, visible())
        env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
        assert.are.same({ NAME }, visible())
        assert.are.equal(2, #s.curves)

        -- The bar refuses the secret alpha (faded, name only): the suffix stays.
        s.refuse = true
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 0, 0, 0 }, alphas(plate))
        assert.are.same({ NAME .. " (19)" }, visible())
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ NAME .. " (19)" }, visible())
        -- The curve fails (unknown health, name only): the suffix stays.
        s.refuse, s.fail = false, true
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ NAME .. " (19)" }, visible())
        -- Our label refuses a secret alpha: the suffix stays.
        s.fail = false
        function label:SetAlpha(a)
          if isSecret(a) then
            error("Attempt to add secret aspect on an object that prevents secret values")
          end
          self.alpha = a
        end
        env.fire("PLAYER_TARGET_CHANGED")
        assert.are.same({ 1, 0, 0 }, alphas(plate))
        assert.are.same({ NAME .. " (19)" }, visible())

        -- Targeted: the full plate, Blizzard's name and level; level off: never a suffix.
        env.world.target = "nameplate2"
        env.fire("PLAYER_TARGET_CHANGED")
        assert.is_false(holder.shown)
        assert.are.equal(1, plate.UnitFrame.name.alpha)
        env.world.target = nil
        env.fire("PLAYER_TARGET_CHANGED")
        env.slash("level off")
        env.world.health.nameplate2 = { 100, 100 }
        env.fire("UNIT_HEALTH", "nameplate2")
        assert.are.same({ NAME }, visible())
        assert.is_false(printedContains(env, "error in"))
      end)

      it("prints the health, whether it is secret, and the bar's state with /gchev debug", function()
        local s = {}
        local env, plate0 = setup(s)
        env.world.target, env.world.plates.target = "nameplate2", plate0
        env.fire("PLAYER_TARGET_CHANGED")
        env.slash("debug")
        assert.is_true(printedContains(env, "debug: UnitHealth secret, UnitHealthMax secret, UnitHealthPercent secret"))
        assert.is_true(printedContains(env, "debug: health curve: UnitHealthPercent yes, "
          .. "C_CurveUtil.CreateColorCurve yes, CreateColor yes, curve built, alpha secret"))
        assert.is_true(printedContains(env, "debug: health bar part NamePlate1HealthBars: shown true, alpha 1"))
        assert.is_false(printedContains(env, "error in"))

        -- Without the curve API and with readable health.
        local env2 = load({ overrides = { issecretvalue = isSecret } })
        local plate = newTreePlate("nameplate2")
        env2.world.health.nameplate2 = { 40, 100 }
        env2.world.target, env2.world.plates.target = "nameplate2", plate
        friend(env2, plate)
        env2.slash("debug")
        assert.is_true(printedContains(env2, "debug: UnitHealth 40, UnitHealthMax 100, UnitHealthPercent missing"))
        assert.is_true(printedContains(env2, "alpha unavailable (fallback: UnitHealth / UnitHealthMax)"))
      end)
    end)

    it("sizes the names of compact plates with othersize, members' with textsize", function()
      local env = load({ saved = { textsize = 2 } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      local label, holder = env.label(plate)
      assert.are.equal(1, holder.scale)

      env.slash("othersize")
      assert.is_true(printedContains(env, "othersize 1 (1 to 3, default 1.5)"))
      env.slash("othersize 1.75")
      assert.are.equal(1.75, env.GroupChevronDB.othersize)
      assert.are.equal(1.75, holder.scale)
      assert.are.equal(NAMEPLATE_FONT, label.fontObject)
      env.slash("othersize 0.5")
      assert.is_true(printedContains(env, "invalid othersize"))
      assert.are.equal(1.75, env.GroupChevronDB.othersize)

      -- Joins the group: textsize; leaves: othersize again.
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(2, holder.scale)
      env.world.party.nameplate2 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(1.75, holder.scale)

      env.slash("")
      assert.is_true(printedContains(env, "othersize 1.75, otherbarsize 1"))
      assert.is_true(printedContains(env, "othersize 1-3"))
    end)

    -- Blizzard's nameplate globals as the Classic Era UI defines them (content 154 - 2 x 12 = 130).
    local function layout()
      return {
        NamePlateDriverFrame = {
          GetNamePlateScale = function(_, style) return { horizontal = 1, style = style } end,
          GetNamePlateWidth = function() return 154 end,
        },
        NamePlateConstants = { STYLE_CVAR = "nameplateStyle" },
        NamePlateSetupOptions = { insetWidth = 12, castBarToHealthBarSpacing = 2 },
      }
    end

    it("widens the health bar about its centre from Blizzard's layout, then lays it out back", function()
      local env = load({ saved = { barsize = 2, otherbarsize = 1.5 }, overrides = layout() })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      local cast = newPart("Frame", uf)
      uf.CastBarsContainer = cast
      local bar = uf.HealthBarsContainer
      local blizzard = { { "BOTTOMLEFT", cast, "TOPLEFT", 0, 2 }, { "BOTTOMRIGHT", cast, "TOPRIGHT", 0, 2 } }

      -- A friendly outside the group first (otherbarsize 1.5): 65 more, 32.5 per side.
      friend(env, plate)
      assert.are.equal(1.5, bar.scale)
      assert.are.same({ { "BOTTOMLEFT", cast, "TOPLEFT", -32.5 / 1.5, 2 / 1.5 },
        { "BOTTOMRIGHT", cast, "TOPRIGHT", 32.5 / 1.5, 2 / 1.5 } }, bar.points)
      -- Then a member (barsize 2): 130 more, 65 per side (32.5 in the doubled bar's units).
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(2, bar.scale)
      assert.are.same({ { "BOTTOMLEFT", cast, "TOPLEFT", -32.5, 1 }, { "BOTTOMRIGHT", cast, "TOPRIGHT", 32.5, 1 } },
        bar.points)

      env.slash("barsize 1")
      assert.are.equal(1, bar.scale)
      assert.are.same(blizzard, bar.points)
      env.slash("barsize 2")
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.equal(1, bar.scale)
      assert.are.same(blizzard, bar.points)
    end)

    it("never touches the anchors of a bar left at size 1", function()
      local env = load({ overrides = layout() })
      local plate = newTreePlate("nameplate2")
      plate.UnitFrame.CastBarsContainer = newPart("Frame", plate.UnitFrame)
      env.world.party.nameplate2 = true
      friend(env, plate)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.same({}, plate.UnitFrame.HealthBarsContainer.points)
    end)

    it("lifts a member's name (and so its chevron) above buffs enlarged by buffsize", function()
      local o = layout()
      o.NamePlateConstants.AURA_ITEM_HEIGHT = 25
      local env = load({ saved = { buffsize = 2, textsize = 2 }, overrides = o })
      local plate = newTreePlate("nameplate2")
      plate.UnitFrame.AurasFrame.auraItemScale = 0.8
      env.world.party.nameplate2 = true
      friend(env, plate)
      local label = env.label(plate)
      -- 25 x 0.8 x 1 gains 20; half above the middle: 10, in our frame's units (textsize 2): 5.
      assert.are.same({ "BOTTOM", plate.UnitFrame.name, "BOTTOM", 0, 5 }, label.points[1])
      env.slash("buffsize 1")
      assert.are.same({ "BOTTOM", plate.UnitFrame.name, "BOTTOM", 0, 0 }, env.label(plate).points[1])
    end)

    it("raises members' names by namegap over the buff lift and friendlies' by othernamegap, independently", function()
      local o = layout()
      o.NamePlateConstants.AURA_ITEM_HEIGHT = 25
      local env = load({ saved = { buffsize = 2, textsize = 2 }, overrides = o })
      local plate = newTreePlate("nameplate2")
      plate.UnitFrame.AurasFrame.auraItemScale = 0.8
      local fs = plate.UnitFrame.name
      local function offset()
        local label = env.label(plate)
        assert.are.equal(fs, label.points[1][2])
        return label.points[1][5]
      end

      -- A compact friendly: no gap by default (the layout as before).
      friend(env, plate)
      assert.are.equal(0, offset())
      env.slash("othernamegap")
      assert.is_true(printedContains(env, "othernamegap 0 (-10 to 40, default 5)"))
      env.slash("othernamegap 6")
      assert.are.equal(6, env.GroupChevronDB.othernamegap)
      assert.are.equal(6, offset())
      -- namegap is for members only.
      env.slash("namegap 4")
      assert.are.equal(4, env.GroupChevronDB.namegap)
      assert.are.equal(6, offset())

      -- Joins the group: (buff lift 10 + namegap 4) / textsize 2; othernamegap does not apply.
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(7, offset())
      assert.are.equal(env.label(plate), env.chevron(plate).points[1][2]) -- the chevron follows
      env.slash("othernamegap -3")
      assert.are.equal(7, offset())
      env.slash("buffsize 1")
      assert.are.equal(2, offset())

      -- Leaves: othernamegap again, at othersize 1.
      env.world.party.nameplate2 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(-3, offset())

      -- Invalid values are refused and change nothing.
      env.slash("namegap 2.5")
      assert.is_true(printedContains(env, "invalid namegap"))
      env.slash("othernamegap 41")
      assert.is_true(printedContains(env, "invalid othernamegap"))
      env.slash("namegap -11")
      assert.are.equal(4, env.GroupChevronDB.namegap)
      assert.are.equal(-3, env.GroupChevronDB.othernamegap)
      assert.are.equal(-3, offset())

      env.slash("")
      assert.is_true(printedContains(env, "buffsize 1, namegap 4"))
      assert.is_true(printedContains(env, "otherbarsize 1, othernamegap -3"))
      assert.is_true(printedContains(env, "namegap -10-40"))

      -- Released: Blizzard's name visible again, nothing of ours left.
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.equal(1, fs.alpha)
    end)

    it("only scales the bar when Blizzard's layout is unknown, and says so once", function()
      local env = load({ saved = { barsize = 2 } })
      local plate = newTreePlate("nameplate2")
      local bar = plate.UnitFrame.HealthBarsContainer
      env.world.party.nameplate2 = true
      friend(env, plate)
      assert.are.equal(2, bar.scale)
      assert.are.same({}, bar.points)
      assert.is_true(printedContains(env, "health bar size changes the height only"))
    end)

    it("scales the health bar and buffs of members, and the bar of friendlies, then restores them", function()
      local env = load({ saved = { barsize = 1.5, buffsize = 2, otherbarsize = 1.25 } })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      uf.AurasFrame.scale = 0.8 -- Blizzard's own scale is kept as the base
      friend(env, plate)
      assert.are.equal(1.25, uf.HealthBarsContainer.scale) -- compact: otherbarsize
      assert.are.equal(0.8, uf.AurasFrame.scale) -- faded in compact mode, never scaled

      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(1.5, uf.HealthBarsContainer.scale)
      assert.are.near(1.6, uf.AurasFrame.scale, 1e-9)
      env.slash("barsize 3")
      assert.are.equal(3, uf.HealthBarsContainer.scale)
      env.slash("buffsize 1")
      assert.are.near(0.8, uf.AurasFrame.scale, 1e-9)
      env.slash("buffsize 2")

      -- Leaves the group: back to the friendly size, the buffs to Blizzard's scale.
      env.world.party.nameplate2 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(1.25, uf.HealthBarsContainer.scale)
      assert.are.near(0.8, uf.AurasFrame.scale, 1e-9)

      -- Targeted (full plate): still the friendly size; removed, or the addon off: original
      -- scales.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(1.25, uf.HealthBarsContainer.scale)
      env.world.target = nil
      env.world.party.nameplate2 = true
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(3, uf.HealthBarsContainer.scale)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      assert.are.near(0.8, uf.AurasFrame.scale, 1e-9)
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal(3, uf.HealthBarsContainer.scale)
      env.slash("off")
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      assert.are.near(0.8, uf.AurasFrame.scale, 1e-9)

      env.slash("on")
      env.slash("")
      assert.is_true(printedContains(env, "barsize 3, buffsize 2"))
      assert.is_true(printedContains(env, "otherbarsize 1.25"))
      env.slash("otherbarsize 4")
      assert.is_true(printedContains(env, "invalid otherbarsize"))
    end)

    it("leaves enemies and NPCs alone", function()
      local env = load()
      local enemy, npc = newTreePlate("nameplate3"), newTreePlate("nameplate4")
      env.world.plates.nameplate3, env.world.plates.nameplate4 = enemy, npc
      env.world.players.nameplate3 = true
      env.world.friends.nameplate4 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
      env.hooks.CompactUnitFrame_UpdateName(enemy.UnitFrame)
      assert.are.same({}, alphas(enemy))
      assert.are.same({}, alphas(npc))
    end)

    it("shows the full plate of the target and of members, never keeping a hidden part", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      local cast = plate.UnitFrame.castBar

      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      show(cast) -- the hook does nothing once the plate left compact mode
      assert.are.equal(1, cast.alpha)
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.same({ 1, 1, 1 }, alphas(plate))

      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 0, 0, 0 }, alphas(plate))

      -- Joins the group: full plate, pink name, chevron.
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      assert.are.equal("#FF4FD8", hex(plate.UnitFrame.name.color))
      local ch = env.chevron(plate)
      assert.is_true(ch.shown)
      show(cast)
      assert.are.equal(1, cast.alpha)

      -- Leaves: name only again, the chevron hidden but never faded, the colour back.
      env.world.party.nameplate2 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.is_false(ch.shown)
      assert.is_nil(ch.alpha)
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      untouchedAncestry(env, plate)

      -- A member's name update hook switches a compact plate back at once.
      env.world.party.nameplate2 = true
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
    end)

    it("cleans a UnitFrame that comes back from Blizzard's pool under another plate (enemies without a name)",
      function()
        local env = load()
        local plateA = newTreePlate("nameplate2")
        local uf = plateA.UnitFrame
        friend(env, plateA)
        assert.are.equal(0, uf.name.alpha) -- compact: Blizzard's name faded under ours
        local _, holder = env.label(plateA)
        assert.is_true(holder.shown)

        -- Blizzard releases the UnitFrame, and our removal handler cannot reach it (no plate
        -- for the token any more, or the plate without its UnitFrame).
        plateA.UnitFrame = nil
        env.world.plates.nameplate2 = nil
        env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")

        -- The pool hands it to another plate, for an enemy player: Blizzard sets the unit and
        -- updates the name.
        local plateB = newPart("Frame", nil)
        plateB.UnitFrame, plateB.namePlateUnitToken = uf, "nameplate3"
        uf.parent, uf.unit = plateB, "nameplate3"
        env.world.plates.nameplate3 = plateB
        env.world.players.nameplate3 = true
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        env.hooks.CompactUnitFrame_UpdateName(uf)
        assert.are.equal(1, uf.name.alpha)
        assert.is_false(holder.shown)
        assert.are.same({ 1, 1, 1 }, alphas(plateB))
      end)

    it("draws a plate's own name inside the UnitFrame it shows now, not the one it had first", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      local first = plate.UnitFrame
      friend(env, plate)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      -- The plate comes back for another friendly with another UnitFrame from the pool (the
      -- first one may be hidden in the pool: anything of ours inside it would be invisible).
      local other = newTreePlate("nameplate2").UnitFrame
      plate.UnitFrame, other.parent = other, plate
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      local label, holder = env.label(plate)
      assert.are.equal(other, holder.parent)
      assert.are.equal(other.name, label.points[1][2])
      assert.are.equal(0, other.name.alpha)
      assert.are.equal(1, first.name.alpha)
    end)

    -- Blizzard's nameplate driver, whose methods GroupChevron post-hooks.
    local function driver()
      return { NamePlateDriverFrame = { ReleaseUnitFrame = function() end, OnNamePlateAdded = function() end } }
    end

    it("undoes everything on a UnitFrame when Blizzard's driver gives it back to the pool", function()
      local env = load({ overrides = driver() })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      friend(env, plate)
      assert.are.equal(0, uf.name.alpha)
      local _, holder = env.label(plate)
      -- The driver releases it (the plate still holds it while the driver runs), whatever the
      -- order of the REMOVED handlers.
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      assert.are.equal(1, uf.name.alpha)
      assert.is_false(holder.shown)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
    end)

    it("applies the mode once Blizzard's driver has given a plate its UnitFrame and unit", function()
      local env = load({ overrides = driver() })
      local plateA = newTreePlate("nameplate2")
      local uf = plateA.UnitFrame
      friend(env, plateA)
      -- Released unseen (no hook call, no usable REMOVED), then handed to an enemy's plate;
      -- Blizzard does not update the name, and our ADDED handler ran before the acquisition.
      plateA.UnitFrame = nil
      env.world.plates.nameplate2 = nil
      local plateB = newPart("Frame", nil)
      plateB.namePlateUnitToken = "nameplate3"
      env.world.plates.nameplate3 = plateB
      env.world.players.nameplate3 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      plateB.UnitFrame, uf.parent, uf.unit = uf, plateB, "nameplate3"
      env.hooks.OnNamePlateAdded(env.NamePlateDriverFrame, "nameplate3")
      assert.are.equal(1, uf.name.alpha)
      assert.are.same({ 1, 1, 1 }, alphas(plateB))
    end)

    it("cleans a pooled UnitFrame on the next refresh even without a name update", function()
      local env = load()
      local plateA = newTreePlate("nameplate2")
      local uf = plateA.UnitFrame
      friend(env, plateA)
      plateA.UnitFrame = nil
      env.world.plates.nameplate2 = nil
      env.fire("PLAYER_TARGET_CHANGED") -- any RefreshAll: the UnitFrame is in no plate
      assert.are.equal(1, uf.name.alpha)
    end)

    -- 0.12.1, enemies without a name a third time: in game, the plate missing its name was the
    -- target's (so refreshed by PLAYER_TARGET_CHANGED) and still had no name. Not a missed
    -- moment: what the addon remembered of the fade was wrong.

    it("gives an enemy target its name back even when nothing records the fade", function()
      local env = load()
      local plate = newTreePlate("nameplate3")
      env.world.plates.nameplate3 = plate
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      -- Blizzard's name at alpha 0 with no record of ours (a fade from an earlier unit whose
      -- record was lost, whatever the path).
      plate.UnitFrame.name.alpha = 0
      env.world.target = "nameplate3"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(1, plate.UnitFrame.name.alpha)
      -- The name update hook heals it too.
      plate.UnitFrame.name.alpha = 0
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
    end)

    it("never gives a name back at alpha 0, even after a failed restore", function()
      local env = load({ overrides = driver() })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      local fs = uf.name
      friend(env, plate)
      assert.are.equal(0, fs.alpha)
      -- The SetAlpha(1) that gives the name back fails during the release (silently swallowed
      -- before 0.12.1, which then dropped the record: the name stayed faded).
      local blocked = true
      local set = fs.SetAlpha
      fs.SetAlpha = function(self, a)
        if a == 1 and blocked then
          error("blocked")
        end
        set(self, a)
      end
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      assert.are.equal(0, fs.alpha)
      blocked = false
      -- Before 0.12.1 the next friendly read alpha 0 as Blizzard's own and gave it back as 0.
      friend(env, plate)
      assert.are.equal(0, fs.alpha) -- covered by our name again
      plate.UnitFrame, uf.parent = nil, nil
      env.world.plates.nameplate2 = nil
      -- The pool hands the UnitFrame to an enemy's plate.
      local enemy = newPart("Frame", nil)
      enemy.UnitFrame, enemy.namePlateUnitToken = uf, "nameplate3"
      uf.parent, uf.unit = enemy, "nameplate3"
      env.world.plates.nameplate3 = enemy
      env.hooks.OnNamePlateAdded(env.NamePlateDriverFrame, "nameplate3")
      assert.are.equal(1, fs.alpha)
      local _, holder = env.label(enemy)
      assert.is_false(holder.shown)
    end)

    it("lists the plates without a visible name with /gchev names, changing nothing", function()
      local env = load({ overrides = driver() })
      local enemy, mate = newTreePlate("nameplate3"), newTreePlate("nameplate2")
      env.world.plates.nameplate3 = enemy
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      friend(env, mate)
      enemy.UnitFrame.name.alpha = 0 -- left faded, not a target
      env.slash("names")
      assert.is_truthy(printedContains(env, 'names: nameplate3 "?" alpha 0 shown nil, remembered faded: no'))
      assert.is_falsy(printedContains(env, "names: nameplate2")) -- covered by our own name
      assert.is_truthy(printedContains(env,
        "names: 2 plate(s), 1 without a visible name, 0 marked at Blizzard's size; driver hooks: release on"))
      assert.are.equal(0, enemy.UnitFrame.name.alpha) -- only reports
    end)

    it("says why a marked member's name stays Blizzard's (not textsize), with /gchev names and debug", function()
      local overrides = driver()
      overrides.issecretvalue = function(v) return v == "secret" end
      local env = load({ overrides = overrides })
      local plate = newTreePlate("nameplate2")
      local fs = plate.UnitFrame.name
      fs.text = "secret" -- the client gives the name text as a secret value
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.party.nameplate2 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal("#FF4FD8", hex(fs.color)) -- marked: our colour on Blizzard's name
      assert.are.equal(1, fs:GetAlpha()) -- but Blizzard's name, at Blizzard's size
      env.slash("names")
      assert.is_truthy(printedContains(env,
        'names: nameplate2 "?" marked, our own name not drawn: name text unreadable (secret or empty)'))
      assert.is_truthy(printedContains(env, "names: 1 plate(s), 0 without a visible name, 1 marked at Blizzard's size"))
      env.world.target, env.world.plates.target = "nameplate2", plate
      env.slash("debug")
      assert.is_truthy(printedContains(env,
        "debug: marked, but our own name is not drawn: name text unreadable (secret or empty) (text secret)"))

      -- Readable again: our own name is drawn and nothing is reported.
      fs.text = "Farbatosz Marokbar"
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(0, fs:GetAlpha())
      env.slash("names")
      local last = env.printed[#env.printed]
      assert.is_truthy(last:find("0 without a visible name, 0 marked at Blizzard's size", 1, true), last)
      assert.is_false(printedContains(env, "error in"))
    end)

    it("retries a failed restore on the next refresh and when leaving combat", function()
      local env = load({ overrides = driver() })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      local fs = uf.name
      friend(env, plate)
      local blocked = true
      local set = fs.SetAlpha
      fs.SetAlpha = function(self, a)
        if a == 1 and blocked then
          error("blocked")
        end
        set(self, a)
      end
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      plate.UnitFrame = nil
      env.world.plates.nameplate2 = nil
      assert.are.equal(0, fs.alpha) -- in the pool, still faded
      assert.is_truthy(printedContains(env, "could not give a nameplate name back"))
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(0, fs.alpha) -- still blocked
      blocked = false
      env.fire("PLAYER_REGEN_ENABLED")
      assert.are.equal(1, fs.alpha)
    end)

    it("restores a removed or recycled plate", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      show(plate.UnitFrame.castBar)
      assert.are.equal(1, plate.UnitFrame.castBar.alpha)

      -- Reused without a removal event for an enemy player.
      friend(env, plate)
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      env.world.friends.nameplate2 = nil
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.same({ 1, 1, 1 }, alphas(plate))

      -- Disappears without a removal event: the next refresh restores it.
      friend(env, plate)
      env.world.plates.nameplate2 = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
    end)

    it("keeps the name's ancestors when the name is nested", function()
      local env = load()
      local plate = newTreePlate("nameplate2", true)
      friend(env, plate)
      local uf = plate.UnitFrame
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(0, uf.NameContainer.Glow.alpha)
      assert.is_nil(uf.NameContainer.alpha)
      untouchedAncestry(env, plate)
    end)

    it("hides nothing when the name is not inside UnitFrame", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      plate.UnitFrame.name.parent = newPart("Frame", nil)
      friend(env, plate)
      assert.are.same({}, alphas(plate))
    end)

    it("is switched with /gchev compact and /gchev off", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)

      env.slash("")
      assert.is_true(printedContains(env, "compact on (other friendly players: name only), 1 plate(s) compact"))
      assert.is_true(printedContains(env, "compact on|off"))
      env.slash("compact")
      assert.is_true(printedContains(env, "compact on (on or off, default on)"))
      env.slash("compact maybe")
      assert.is_true(printedContains(env, "invalid compact \"maybe\""))
      assert.is_true(env.GroupChevronDB.compact)

      env.slash("compact OFF")
      assert.is_false(env.GroupChevronDB.compact)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      env.slash("compact on")
      assert.are.same({ 0, 0, 0 }, alphas(plate))

      env.slash("off")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      show(plate.UnitFrame.castBar)
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      env.slash("on")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
    end)

    it("keeps compact off across reloads and resets an invalid saved value", function()
      local env = load({ saved = { compact = false } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      assert.are.same({}, alphas(plate))
      assert.is_true(load({ saved = { compact = "no" } }).GroupChevronDB.compact)
    end)

    it("lists the parts in /gchev debug", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.world.plates.target = plate
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: mode compact"))
      assert.is_true(printedContains(env, "debug: hidden 4 part(s)"))
      assert.is_true(printedContains(env, "NamePlate1HealthBars (Frame)"))
      assert.is_true(printedContains(env, "castBar (StatusBar)"))
      assert.is_true(printedContains(env, "classificationIndicator (Texture)"))

      -- The target itself is shown in full: debug lists what compact would hide.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: mode default"))
      assert.is_true(printedContains(env, "debug: compact would hide 4 part(s)"))
    end)
  end)

  describe("friends", function()
    local function alphas(plate)
      local uf = plate.UnitFrame
      return { uf.HealthBarsContainer.alpha, uf.castBar.alpha, uf.classificationIndicator.alpha }
    end

    -- friend sets up a friendly player on the character friends list (or, with bnet, a
    -- Battle.net friend's character) on nameplate2.
    local function friend(env, plate, bnet)
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
      if bnet then
        env.world.bnet.nameplate2 = true
      else
        env.world.flist.nameplate2 = true
      end
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    end

    -- looksFriend checks the friend colour on our name and Blizzard's, and the chevron.
    local function looksFriend(env, plate, color, chevronShown)
      local uf = plate.UnitFrame
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.are.equal(color, hex(label.color))
      assert.are.equal(color, hex(uf.name.color))
      assert.are.equal(0, uf.name.alpha)
      local ch = env.chevron(plate)
      if chevronShown then
        assert.is_true(ch.shown)
        assert.are.equal(color, hex(ch.textures[1].vertex))
        assert.are.equal(label, ch.points[1][2])
      else
        assert.is_true(ch == nil or ch.shown == false)
      end
    end

    it("colours a friend's compact plate and adds the chevron", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      looksFriend(env, plate, "#3FA7FF", true)
      local _, holder = env.label(plate)
      assert.are.equal(1, holder.scale)

      -- Name updates and health changes keep the look.
      plate.UnitFrame.name:SetTextColor(unpack(BLUE))
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      looksFriend(env, plate, "#3FA7FF", true)
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 1, 0, 0 }, alphas(plate))
      looksFriend(env, plate, "#3FA7FF", true)
      show(plate.UnitFrame.castBar)
      assert.are.equal(0, plate.UnitFrame.castBar.alpha)
    end)

    it("keeps the colour and chevron on a friend who is the target, with the full plate", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looksFriend(env, plate, "#3FA7FF", true)
      show(plate.UnitFrame.castBar)
      assert.are.equal(1, plate.UnitFrame.castBar.alpha)
      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      looksFriend(env, plate, "#3FA7FF", true)
    end)

    it("sizes a friend's full plate with friendsize and otherbarsize (compact off), not the member sizes", function()
      local env = load({ saved = { compact = false, friendsize = 2, othersize = 3, otherbarsize = 2, textsize = 3,
        barsize = 2 } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      assert.are.same({}, alphas(plate))
      looksFriend(env, plate, "#3FA7FF", true)
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      assert.are.equal(2, plate.UnitFrame.HealthBarsContainer.scale)

      -- Off gives the original bar scale back.
      env.slash("off")
      assert.are.equal(1, plate.UnitFrame.HealthBarsContainer.scale)
    end)

    it("keeps a friend's full plate at size 1 with the default othersize and otherbarsize", function()
      local env = load({ saved = { compact = false, textsize = 3, barsize = 2 } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      local _, holder = env.label(plate)
      assert.are.equal(1, holder.scale)
      assert.is_true((plate.UnitFrame.HealthBarsContainer.scale or 1) == 1)
    end)

    it("uses the friendsize and otherbarsize of compact plates", function()
      local env = load({ saved = { friendsize = 2, othersize = 3, otherbarsize = 1.5 } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      assert.are.equal(1.5, plate.UnitFrame.HealthBarsContainer.scale)
      -- The target (full plate, compact on): the same sizes, no jump either way.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(2, holder.scale)
      assert.are.equal(1.5, plate.UnitFrame.HealthBarsContainer.scale)
      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(2, holder.scale)
      assert.are.equal(1.5, plate.UnitFrame.HealthBarsContainer.scale)
      -- Released: Blizzard's bar scale back.
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.equal(1, plate.UnitFrame.HealthBarsContainer.scale)
    end)

    it("gives a group member the member look, and Blizzard's colour back when no longer marked", function()
      local env = load({ saved = { barsize = 2 } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looksFriend(env, plate, "#FF4FD8", true)
      assert.are.equal(2, plate.UnitFrame.HealthBarsContainer.scale)
      -- Blizzard's update hook (no colour restore) on the way back keeps Blizzard's colour known.
      env.world.party.nameplate2 = nil
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      looksFriend(env, plate, "#3FA7FF", true)
      assert.are.equal(1, plate.UnitFrame.HealthBarsContainer.scale)

      -- No longer a friend: the plain compact plate, Blizzard's colour, no chevron.
      env.world.flist.nameplate2 = nil
      env.fire("FRIENDLIST_UPDATE")
      env.runTimers()
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      local label = env.label(plate)
      assert.are.same(BLUE, label.color)
      assert.is_false(env.chevron(plate).shown)
    end)

    it("hides the chevron with friendchevron off and sets the colour with friendcolor", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.slash("friendchevron")
      assert.is_true(printedContains(env, "friendchevron on (on or off, default on)"))
      env.slash("friendchevron maybe")
      assert.is_true(printedContains(env, "invalid friendchevron \"maybe\""))
      assert.is_true(env.GroupChevronDB.friendchevron)
      env.slash("friendchevron off")
      assert.is_false(env.GroupChevronDB.friendchevron)
      looksFriend(env, plate, "#3FA7FF", false)

      env.slash("friendcolor")
      assert.is_true(printedContains(env, "friendcolor #3FA7FF (default #3FA7FF)"))
      env.slash("friendcolor #12")
      assert.is_true(printedContains(env, "invalid friendcolor \"#12\""))
      assert.are.equal("#3FA7FF", hex(env.GroupChevronDB.friendcolor))
      env.slash("friendcolor #00ff00")
      looksFriend(env, plate, "#00FF00", false)
      env.slash("friendchevron on")
      looksFriend(env, plate, "#00FF00", true)

      -- /gchev reset is the member colour only.
      env.slash("reset")
      assert.are.equal("#00FF00", hex(env.GroupChevronDB.friendcolor))

      -- Off restores everything, on brings the look back.
      env.slash("off")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
      assert.is_false(env.chevron(plate).shown)
      local _, holder = env.label(plate)
      assert.is_false(holder.shown)
      env.slash("on")
      looksFriend(env, plate, "#00FF00", true)
    end)

    it("counts Battle.net friends unless bnetfriends is off", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate, true)
      looksFriend(env, plate, "#3FA7FF", true)
      env.slash("bnetfriends off")
      assert.is_false(env.GroupChevronDB.bnetfriends)
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_false(env.chevron(plate).shown)
      local calls = env.world.bnetCalls
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(calls, env.world.bnetCalls) -- never asked while off
      env.slash("bnetfriends nope")
      assert.is_true(printedContains(env, "invalid bnetfriends \"nope\""))
      env.slash("bnetfriends on")
      looksFriend(env, plate, "#3FA7FF", true)
    end)

    it("leaves friends alone when the friend APIs are missing", function()
      local env = load({ overrides = { C_FriendList = false, C_BattleNet = false } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_nil(env.chevron(plate))
      env.world.plates.target = plate
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target friend: no (API missing)"))
    end)

    it("never marks an enemy player or the player as a friend", function()
      local env = load()
      local enemy = newTreePlate("nameplate3")
      env.world.plates.nameplate3 = enemy
      env.world.players.nameplate3, env.world.flist.nameplate3 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      assert.are.same(BLUE, enemy.UnitFrame.name.color)
      assert.is_nil(env.chevron(enemy))
    end)

    it("undoes the friend look when the UnitFrame is released or the plate removed", function()
      local env = load({ overrides = { NamePlateDriverFrame = { ReleaseUnitFrame = function() end } } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
      assert.is_false(env.chevron(plate).shown)

      friend(env, plate)
      looksFriend(env, plate, "#3FA7FF", true)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_false(env.chevron(plate).shown)
      -- Reused for a stranger: Blizzard's new colour stays.
      env.world.flist.nameplate2 = nil
      plate.UnitFrame.name:SetTextColor(1, 0, 0)
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.same({ 1, 0, 0, 1 }, plate.UnitFrame.name.color)
    end)

    it("coalesces friend list events into one refresh", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.world.flist.nameplate2 = nil
      for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" }) do
        env.fire(e)
      end
      assert.are.equal(1, #env.world.timers)
      assert.are.equal("#3FA7FF", hex(plate.UnitFrame.name.color)) -- not yet
      env.runTimers()
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      env.fire("BN_FRIEND_INFO_CHANGED")
      assert.are.equal(1, #env.world.timers) -- a new burst, a new refresh
    end)

    it("refreshes at once without C_Timer, and survives unknown events", function()
      local env = load({ overrides = {
        C_Timer = false,
        decorate = function(f)
          local register = f.RegisterEvent
          f.RegisterEvent = function(self, e)
            if e:sub(1, 3) == "BN_" then
              error("unknown event " .. e)
            end
            register(self, e)
          end
          return f
        end,
      } })
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      looksFriend(env, plate, "#3FA7FF", true)
      env.world.flist.nameplate2 = nil
      env.fire("FRIENDLIST_UPDATE")
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_false(printedContains(env, "error in"))
    end)

    it("prints the friend state in /gchev and /gchev debug", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friend(env, plate)
      env.world.target = "nameplate2"
      env.world.plates.target = plate
      env.slash("")
      assert.is_true(printedContains(env,
        "friends: colour #3FA7FF, friendsize 1, chevron on, Battle.net friends on, 1 plate(s) marked"))
      assert.is_true(printedContains(env, "friendcolor #RRGGBB | friendchevron on|off | bnetfriends on|off"))
      env.fire("PLAYER_TARGET_CHANGED")
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target friend: yes (character list)"))
      assert.is_true(printedContains(env, "debug: mode friend"))
      env.world.flist.nameplate2, env.world.bnet.nameplate2 = nil, true
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target friend: yes (Battle.net)"))
      env.world.bnet.nameplate2 = nil
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target friend: no (none)"))
    end)
  end)

  describe("level", function()
    local NAME = "Farbatosz Marokbar"

    local function alphas(plate)
      local uf = plate.UnitFrame
      return { uf.HealthBarsContainer.alpha, uf.castBar.alpha, uf.classificationIndicator.alpha }
    end

    -- friendly sets up a friendly non-member player of level on nameplate2 (on the character
    -- friends list with listed).
    local function friendly(env, plate, level, listed)
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
      env.world.levels.nameplate2 = level
      env.world.flist.nameplate2 = listed or nil
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    end

    -- shown returns our name's text when it is shown over Blizzard's faded one, else nil (and
    -- then Blizzard's name is visible).
    local function shown(env, plate)
      local label, holder = env.label(plate)
      local uf = plate.UnitFrame
      assert.are.equal(NAME, uf.name.text) -- Blizzard's text is never changed
      if label and holder.shown then
        assert.are.equal(0, uf.name.alpha)
        assert.are.equal(NAMEPLATE_FONT, label.fontObject)
        return label.text
      end
      assert.are.equal(1, uf.name.alpha or 1)
      return nil
    end

    it("shows a compact friendly's level in the name's colour and size, without the health bar", function()
      local env = load({ saved = { othersize = 2 } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      local label, holder = env.label(plate)
      assert.are.same(BLUE, label.color)
      assert.are.equal(2, holder.scale)
      assert.is_nil(env.chevron(plate))

      -- UNIT_LEVEL re-applies it; an unknown level is "??".
      env.world.levels.nameplate2 = 20
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME .. " (20)", shown(env, plate))
      env.world.levels.nameplate2 = -1
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME .. " (??)", shown(env, plate))
      -- Hurt: the health bar shows Blizzard's level beside it, so the suffix goes (same label,
      -- same colour and size) and comes back at full health, without a plate re-add.
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 1, 0, 0 }, alphas(plate))
      assert.are.equal(NAME, shown(env, plate))
      assert.are.equal(label, env.label(plate))
      assert.are.same(BLUE, label.color)
      assert.are.equal(2, holder.scale)
      env.world.levels.nameplate2 = 21
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME, shown(env, plate))
      env.world.health.nameplate2 = { 100, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(NAME .. " (21)", shown(env, plate))
      -- Other units' events change nothing.
      env.world.levels.nameplate2 = 30
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_LEVEL", "target")
      env.fire("UNIT_LEVEL", "player")
      env.fire("UNIT_HEALTH", "player")
      assert.are.equal(NAME .. " (21)", shown(env, plate))
      assert.is_true(env.frames[1].events.UNIT_LEVEL)
    end)

    it("draws the name of a full plate with compact off at othersize, never with the level", function()
      local env = load({ saved = { compact = false, othersize = 2 } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.are.same({}, alphas(plate)) -- the rest of the plate stays Blizzard's
      -- Blizzard's health bar shows the level: no suffix.
      assert.are.equal(NAME, shown(env, plate))
      local label, holder = env.label(plate)
      assert.are.same(BLUE, label.color)
      assert.are.equal(2, holder.scale)
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.scale) -- otherbarsize 1: never touched

      -- Blizzard recolours the name: ours follows.
      plate.UnitFrame.name:SetTextColor(1, 0, 0)
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.same({ 1, 0, 0, 1 }, label.color)

      -- Level changes and health change nothing: still our name alone at othersize.
      env.world.levels.nameplate2 = nil
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME, shown(env, plate))
      assert.are.equal(2, holder.scale)
      env.world.levels.nameplate2 = 5
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME, shown(env, plate))
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.equal(NAME, shown(env, plate))
      env.world.health.nameplate2 = nil

      -- Off gives Blizzard's name back; compact on brings the level (bar hidden), off drops it.
      env.slash("off")
      assert.is_nil(shown(env, plate))
      env.slash("on")
      assert.are.equal(NAME, shown(env, plate))
      env.slash("compact on")
      assert.are.equal(NAME .. " (5)", shown(env, plate))
      assert.are.equal(2, holder.scale)
      env.slash("compact off")
      assert.are.equal(NAME, shown(env, plate))
      assert.are.equal(2, holder.scale)
      assert.are.same({ 1, 1, 1 }, alphas(plate))
    end)

    it("keeps Blizzard's name on a full plate at the default othersize, level on", function()
      local env = load({ saved = { compact = false } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.is_nil(shown(env, plate))
      assert.is_nil(env.label(plate))
    end)

    it("sizes a targeted friendly's full plate with othersize and otherbarsize (compact on)", function()
      local env = load({ saved = { othersize = 2, otherbarsize = 1.5, showlevel = false } })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      friendly(env, plate, 19)
      -- Compact: our name at othersize, no level.
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(NAME, shown(env, plate))
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      assert.are.equal(1.5, uf.HealthBarsContainer.scale)

      -- Targeted: the full plate, the same sizes (no jump either way).
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      assert.are.equal(NAME, shown(env, plate))
      assert.are.equal(2, holder.scale)
      assert.are.equal(1.5, uf.HealthBarsContainer.scale)
      env.slash("othersize 2.5")
      assert.are.equal(2.5, holder.scale)
      env.slash("otherbarsize 1")
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      env.slash("otherbarsize 1.5")
      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(2.5, holder.scale)
      assert.are.equal(1.5, uf.HealthBarsContainer.scale)

      -- Released as the target: Blizzard's scale and name back.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      assert.is_nil(shown(env, plate))

      -- The same UnitFrame now showing an enemy: nothing of the friendly's sizes stays.
      env.world.friends.nameplate2 = false
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      assert.is_nil(shown(env, plate))
    end)

    it("gives a targeted enemy's plate back its scale when its UnitFrame showed a friendly", function()
      local env = load({ saved = { compact = false, otherbarsize = 2 } })
      local plate = newTreePlate("nameplate2")
      local uf = plate.UnitFrame
      friendly(env, plate, 19)
      assert.are.equal(2, uf.HealthBarsContainer.scale)
      -- Blizzard's name-update hook on a UnitFrame that now shows an enemy (no restore).
      env.world.friends.nameplate2 = false
      env.hooks.CompactUnitFrame_UpdateName(uf)
      assert.are.equal(1, uf.HealthBarsContainer.scale)
      assert.is_nil(shown(env, plate))
    end)

    it("keeps Blizzard's name on a full plate without the level at the default othersize", function()
      local env = load({ saved = { compact = false, showlevel = false } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.is_nil(shown(env, plate))
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.scale)
    end)

    it("draws a plain full plate's name to move it by othernamegap, and gives Blizzard's back at 0", function()
      local env = load({ saved = { compact = false, showlevel = false, namegap = 9 } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.is_nil(shown(env, plate)) -- namegap is for members only
      env.slash("othernamegap 5")
      assert.are.equal(NAME, shown(env, plate))
      assert.are.same({ "BOTTOM", plate.UnitFrame.name, "BOTTOM", 0, 5 }, env.label(plate).points[1])
      local _, holder = env.label(plate)
      assert.are.equal(1, holder.scale)
      env.slash("othernamegap 0")
      assert.is_nil(shown(env, plate))
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.scale)
    end)

    it("leaves the level out on a friendly target, and shows friends' in their colour under the chevron", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      -- The target's full plate: Blizzard's bar shows the level, Blizzard's name stays.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      assert.is_nil(shown(env, plate))

      -- A friend: the friend colour, compact or as the target, the chevron above our name; the
      -- level only on the compact plate.
      env.world.flist.nameplate2 = true
      env.fire("FRIENDLIST_UPDATE")
      env.runTimers()
      assert.are.equal(NAME, shown(env, plate))
      local label = env.label(plate)
      assert.are.equal("#3FA7FF", hex(label.color))
      local ch = env.chevron(plate)
      assert.is_true(ch.shown)
      assert.are.same({ "BOTTOM", label, "TOP", 0, 2 }, ch.points[1])
      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      assert.are.equal("#3FA7FF", hex(label.color))
      env.world.levels.nameplate2 = 21
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME .. " (21)", shown(env, plate))
    end)

    it("never shows the level of a group member, an enemy or an NPC", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19, true)
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal(NAME, shown(env, plate))
      assert.are.equal("#FF4FD8", hex(env.label(plate).color))
      env.fire("UNIT_LEVEL", "nameplate2")
      assert.are.equal(NAME, shown(env, plate))

      local enemy = newTreePlate("nameplate3")
      env.world.plates.nameplate3 = enemy
      env.world.players.nameplate3, env.world.levels.nameplate3 = true, 19
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      assert.is_nil(shown(env, enemy))
      assert.is_nil(env.label(enemy))

      local npc = newTreePlate("nameplate4")
      env.world.plates.nameplate4 = npc
      env.world.friends.nameplate4, env.world.levels.nameplate4 = true, 19
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
      assert.is_nil(env.label(npc))
    end)

    it("shows the name alone when UnitLevel is missing, fails or returns a secret value", function()
      local secret = {}
      for name, fn in pairs({
        missing = false,
        error = function() error("restricted") end,
        secret = function() return secret end,
      }) do
        local env = load({ overrides = {
          UnitLevel = fn,
          issecretvalue = function(v) return v == secret end,
        } })
        local plate = newTreePlate("nameplate2")
        friendly(env, plate, 19)
        assert.are.equal(NAME, shown(env, plate), name)
        local full = newTreePlate("nameplate2")
        env.slash("compact off")
        friendly(env, full, 19)
        assert.is_nil(shown(env, full), name)
        assert.is_false(printedContains(env, "error in"), name)
      end
    end)

    it("is switched with /gchev level, refusing invalid values", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      env.slash("level")
      assert.is_true(printedContains(env, "level on (on or off, default on)"))
      env.slash("level maybe")
      assert.is_true(printedContains(env, "invalid level \"maybe\""))
      assert.is_true(env.GroupChevronDB.showlevel)
      env.slash("level off")
      assert.is_false(env.GroupChevronDB.showlevel)
      assert.is_true(printedContains(env, "level off"))
      assert.are.equal(NAME, shown(env, plate))
      env.slash("compact off")
      assert.is_nil(shown(env, plate))
      env.slash("level on")
      assert.is_nil(shown(env, plate)) -- full plate: never the level
      env.slash("compact on")
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      env.slash("")
      assert.is_true(printedContains(env, "friendlies: level on; othersize 1, otherbarsize 1"))
      assert.is_true(printedContains(env, "| level on|off | compact on|off |"))
    end)

    it("keeps showlevel off across reloads and resets an invalid saved value", function()
      assert.is_false(load({ saved = { showlevel = false } }).GroupChevronDB.showlevel)
      assert.is_true(load({ saved = { showlevel = "no" } }).GroupChevronDB.showlevel)
    end)

    it("gives Blizzard's name back when the UnitFrame is released or the plate removed", function()
      local env = load({ overrides = { NamePlateDriverFrame = { ReleaseUnitFrame = function() end } } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, 19)
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      assert.is_nil(shown(env, plate))
      friendly(env, plate, 19)
      assert.are.equal(NAME .. " (19)", shown(env, plate))
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.is_nil(shown(env, plate))
      -- A UnitFrame no plate shows any more is cleaned by the next refresh.
      friendly(env, plate, 19)
      env.world.plates.nameplate2 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.is_nil(shown(env, plate))
    end)
  end)

  describe("guildmates", function()
    local function alphas(plate)
      local uf = plate.UnitFrame
      return { uf.HealthBarsContainer.alpha, uf.castBar.alpha, uf.classificationIndicator.alpha }
    end

    -- guildmate sets up a friendly player in the player's guild (not a friend) on nameplate2.
    local function guildmate(env, plate)
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
      env.world.inGuild, env.world.guild.nameplate2 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    end

    local function looks(env, plate, color, chevronShown)
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.are.equal(color, hex(label.color))
      assert.are.equal(color, hex(plate.UnitFrame.name.color))
      local ch = env.chevron(plate)
      if chevronShown then
        assert.is_true(ch.shown)
        assert.are.equal(color, hex(ch.textures[1].vertex))
      else
        assert.is_true(ch == nil or ch.shown == false)
      end
    end

    it("colours a guildmate's compact plate green with the chevron, also as the target", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      looks(env, plate, "#40FF40", true)
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looks(env, plate, "#40FF40", true)
    end)

    it("colours the default plate of a guildmate with compact off", function()
      local env = load({ saved = { compact = false } })
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      assert.are.same({}, alphas(plate))
      looks(env, plate, "#40FF40", true)
    end)

    it("shows a guildmate's level after their name, in green, on compact plates only", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      env.world.levels.nameplate2 = 19
      guildmate(env, plate)
      local label = env.label(plate)
      assert.are.equal("Farbatosz Marokbar (19)", label.text)
      assert.are.equal("#40FF40", hex(label.color))

      env.slash("compact off")
      local full = newTreePlate("nameplate2")
      env.world.levels.nameplate2 = 19
      guildmate(env, full)
      local fullLabel = env.label(full)
      assert.are.equal("Farbatosz Marokbar", fullLabel.text)
      assert.are.equal("#40FF40", hex(fullLabel.color))
    end)

    it("shows a friend who is also a guildmate as a friend, and a member as a member", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      env.world.flist.nameplate2 = true
      env.fire("PLAYER_GUILD_UPDATE")
      env.runTimers()
      looks(env, plate, "#3FA7FF", true)
      env.world.party.nameplate2 = true
      env.fire("GROUP_ROSTER_UPDATE")
      looks(env, plate, "#FF4FD8", true)
    end)

    it("does not mark anyone, nor ask the guild API, when not in a guild", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      env.world.inGuild = false
      env.world.guildCalls = 0
      env.fire("GUILD_ROSTER_UPDATE")
      env.runTimers()
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_false(env.chevron(plate).shown)
      assert.are.equal(0, env.world.guildCalls)
    end)

    it("leaves everyone alone when the guild APIs are missing", function()
      local env = load({ overrides = { IsInGuild = false, UnitIsInMyGuild = false } })
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.is_nil(env.chevron(plate))
    end)

    it("hides the chevron with guildchevron off and sets the colour with guildcolor", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      env.slash("guildchevron")
      assert.is_true(printedContains(env, "guildchevron on (on or off, default on)"))
      env.slash("guildchevron maybe")
      assert.is_true(printedContains(env, "invalid guildchevron \"maybe\""))
      assert.is_true(env.GroupChevronDB.guildchevron)
      env.slash("guildchevron off")
      assert.is_false(env.GroupChevronDB.guildchevron)
      looks(env, plate, "#40FF40", false)
      env.slash("guildcolor")
      assert.is_true(printedContains(env, "guildcolor #40FF40 (default #40FF40)"))
      env.slash("guildcolor #12")
      assert.is_true(printedContains(env, "invalid guildcolor \"#12\""))
      assert.are.equal("#40FF40", hex(env.GroupChevronDB.guildcolor))
      env.slash("guildcolor #ff0000")
      looks(env, plate, "#FF0000", false)
    end)

    it("coalesces the guild events into one refresh", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      env.world.guild.nameplate2 = nil
      env.fire("PLAYER_GUILD_UPDATE")
      env.fire("GUILD_ROSTER_UPDATE")
      env.fire("GUILD_ROSTER_UPDATE")
      assert.are.equal(1, #env.world.timers)
      env.runTimers()
      assert.are.same(BLUE, plate.UnitFrame.name.color)
    end)

    it("prints the guild state in /gchev and /gchev debug", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      guildmate(env, plate)
      env.world.target = "nameplate2"
      env.world.plates.target = plate
      env.slash("")
      assert.is_true(printedContains(env, "guildmates: colour #40FF40, guildsize 1, chevron on, 1 plate(s) marked"))
      assert.is_true(printedContains(env, "guildcolor #RRGGBB | guildchevron on|off"))
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target guildmate: yes (UnitIsInMyGuild)"))
      env.world.guild.nameplate2 = nil
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target guildmate: no (none)"))
    end)
  end)

  describe("class colour", function()
    local function alphas(plate)
      local uf = plate.UnitFrame
      return { uf.HealthBarsContainer.alpha, uf.castBar.alpha, uf.classificationIndicator.alpha }
    end

    -- friendly sets up a friendly player of class token (not grouped, not a friend) on unit.
    local function friendly(env, plate, unit, token)
      env.world.plates[unit] = plate
      env.world.players[unit], env.world.friends[unit] = true, true
      env.world.classes[unit] = token
      env.fire("NAME_PLATE_UNIT_ADDED", unit)
    end

    -- looksClass checks our name in color over Blizzard's (faded), without a chevron.
    local function looksClass(env, plate, color)
      local uf = plate.UnitFrame
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.are.equal(color, hex(label.color))
      assert.are.equal(color, hex(uf.name.color))
      assert.are.equal(0, uf.name.alpha)
      local ch = env.chevron(plate)
      assert.is_true(ch == nil or ch.shown == false)
    end

    -- looksBlizzard checks Blizzard's name is back: its colour and alpha, our name hidden.
    local function looksBlizzard(env, plate)
      local uf = plate.UnitFrame
      assert.are.same(BLUE, uf.name.color)
      assert.are.equal(1, uf.name.alpha)
      local _, holder = env.label(plate)
      assert.is_false(holder.shown)
    end

    -- looksSized checks our name in Blizzard's colour over Blizzard's (faded), at size.
    local function looksSized(env, plate, size)
      local uf = plate.UnitFrame
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.are.same(BLUE, uf.name.color)
      assert.are.equal(BLUE[1], label.color[1])
      assert.are.equal(BLUE[2], label.color[2])
      assert.are.equal(BLUE[3], label.color[3])
      assert.are.equal(0, uf.name.alpha)
      assert.are.equal(size, holder.scale)
    end

    it("is off by default: friendlies keep Blizzard's colour", function()
      local env = load()
      assert.is_false(env.GroupChevronDB.classcolor)
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.are.same(BLUE, env.label(plate).color)
    end)

    it("colours a compact friendly and the target, and gives Blizzard's colour back when off", function()
      local env = load({ saved = { classcolor = true, othersize = 2 } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      looksClass(env, plate, "#00FFFF")
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)

      -- Blizzard recolours the name, the unit gets hurt: the look stays.
      plate.UnitFrame.name:SetTextColor(unpack(BLUE))
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      looksClass(env, plate, "#00FFFF")
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.same({ 1, 0, 0 }, alphas(plate))
      looksClass(env, plate, "#00FFFF")

      -- The target: full plate, still in the class colour, at othersize.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looksClass(env, plate, "#00FFFF")
      assert.are.equal(2, holder.scale)
      env.world.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
      looksClass(env, plate, "#00FFFF")

      -- Off: the plain compact plate, Blizzard's colour on both names.
      env.slash("classcolor off")
      assert.is_false(env.GroupChevronDB.classcolor)
      assert.are.same({ 1, 0, 0 }, alphas(plate))
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      assert.are.same(BLUE, env.label(plate).color)
      -- And the target with the setting off: Blizzard's plate, the name in Blizzard's colour
      -- at othersize.
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looksSized(env, plate, 2)
    end)

    it("draws the name itself with compact off, leaving the rest of the plate Blizzard's", function()
      local env = load({ saved = { classcolor = true, compact = false, othersize = 2, otherbarsize = 2 } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      assert.are.same({}, alphas(plate))
      looksClass(env, plate, "#00FFFF")
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      assert.are.equal(2, plate.UnitFrame.HealthBarsContainer.scale)

      -- Without the class colour: Blizzard's colour, still othersize and otherbarsize.
      env.slash("classcolor off")
      looksSized(env, plate, 2)
      assert.are.equal(2, plate.UnitFrame.HealthBarsContainer.scale)
      env.slash("classcolor on")
      looksClass(env, plate, "#00FFFF")
      env.slash("off")
      looksBlizzard(env, plate)
      assert.are.equal(1, plate.UnitFrame.HealthBarsContainer.scale)
      env.slash("on")
      looksClass(env, plate, "#00FFFF")
      -- Turning compact on and off again keeps it.
      env.slash("compact on")
      assert.are.same({ 0, 0, 0 }, alphas(plate))
      looksClass(env, plate, "#00FFFF")
      env.slash("compact off")
      assert.are.same({ 1, 1, 1 }, alphas(plate))
      looksClass(env, plate, "#00FFFF")
    end)

    it("leaves members' and friends' colours alone", function()
      local env = load({ saved = { classcolor = true } })
      local member = newTreePlate("nameplate1")
      friendly(env, member, "nameplate1", "MAGE")
      env.world.party.nameplate1 = true
      env.fire("GROUP_ROSTER_UPDATE")
      assert.are.equal("#FF4FD8", hex(member.UnitFrame.name.color))
      assert.is_true(env.chevron(member).shown)

      local friend = newTreePlate("nameplate2")
      env.world.flist.nameplate2 = true
      friendly(env, friend, "nameplate2", "MAGE")
      assert.are.equal("#3FA7FF", hex(friend.UnitFrame.name.color))
      assert.are.equal("#3FA7FF", hex(env.label(friend).color))
      assert.is_true(env.chevron(friend).shown)

      -- Unfriended: the class colour, the chevron gone.
      env.world.flist.nameplate2 = nil
      env.fire("FRIENDLIST_UPDATE")
      env.runTimers()
      looksClass(env, friend, "#00FFFF")
      -- Leaves the group: the class colour too.
      env.world.party.nameplate1 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      looksClass(env, member, "#00FFFF")
    end)

    it("falls back to RAID_CLASS_COLORS, and keeps Blizzard's colour for an unknown class", function()
      local env = load({ saved = { classcolor = true, compact = false } })
      local warlock = newTreePlate("nameplate2")
      friendly(env, warlock, "nameplate2", "WARLOCK")
      looksClass(env, warlock, "#FF00FF")
      local pirate = newTreePlate("nameplate3")
      friendly(env, pirate, "nameplate3", "PIRATE")
      assert.are.same(BLUE, pirate.UnitFrame.name.color)
      assert.is_nil(env.label(pirate))
      local none = newTreePlate("nameplate4")
      friendly(env, none, "nameplate4", nil)
      assert.are.same(BLUE, none.UnitFrame.name.color)
      assert.is_nil(env.label(none))
      -- An enemy player is never coloured.
      local enemy = newTreePlate("nameplate5")
      env.world.plates.nameplate5, env.world.players.nameplate5 = enemy, true
      env.world.classes.nameplate5 = "MAGE"
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
      assert.are.same(BLUE, enemy.UnitFrame.name.color)
      assert.is_nil(env.label(enemy))
    end)

    it("keeps Blizzard's colour when the class APIs are missing or fail", function()
      for _, overrides in ipairs({
        { C_ClassColor = false, RAID_CLASS_COLORS = false },
        { UnitClass = false },
        { UnitClass = function() error("restricted") end },
        { C_ClassColor = { GetClassColor = function() error("boom") end }, RAID_CLASS_COLORS = false },
      }) do
        local env = load({ saved = { classcolor = true, compact = false }, overrides = overrides })
        local plate = newTreePlate("nameplate2")
        friendly(env, plate, "nameplate2", "MAGE")
        assert.are.same(BLUE, plate.UnitFrame.name.color)
        assert.is_nil(env.label(plate))
        assert.is_false(printedContains(env, "error in"))
      end
      -- Without C_ClassColor, RAID_CLASS_COLORS answers.
      local env = load({ saved = { classcolor = true, compact = false }, overrides = { C_ClassColor = false } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      looksClass(env, plate, "#00FFFF")
    end)

    it("undoes the look when the UnitFrame is released or the plate removed", function()
      local env = load({ saved = { classcolor = true, compact = false },
        overrides = { NamePlateDriverFrame = { ReleaseUnitFrame = function() end } } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      env.hooks.ReleaseUnitFrame(env.NamePlateDriverFrame, plate)
      looksBlizzard(env, plate)

      friendly(env, plate, "nameplate2", "MAGE")
      looksClass(env, plate, "#00FFFF")
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      looksBlizzard(env, plate)
      -- Reused for an enemy: Blizzard's new colour stays, nothing of ours.
      env.world.friends.nameplate2 = nil
      plate.UnitFrame.name:SetTextColor(1, 0, 0)
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.same({ 1, 0, 0, 1 }, plate.UnitFrame.name.color)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
    end)

    it("sets classcolor with /gchev, refusing invalid values", function()
      local env = load()
      env.slash("classcolor")
      assert.is_true(printedContains(env, "classcolor off (on or off, default on)"))
      env.slash("classcolor maybe")
      assert.is_true(printedContains(env, "invalid classcolor \"maybe\""))
      assert.is_false(env.GroupChevronDB.classcolor)
      env.slash("classcolor ON")
      assert.is_true(env.GroupChevronDB.classcolor)
      assert.is_true(printedContains(env, "classcolor on"))
      env.slash("classcolour off")
      assert.is_false(env.GroupChevronDB.classcolor)
      -- /gchev reset is the member colour only.
      env.slash("classcolor on")
      env.slash("reset")
      assert.is_true(env.GroupChevronDB.classcolor)
    end)

    it("prints the class in /gchev and /gchev debug", function()
      local env = load({ saved = { classcolor = true } })
      local plate = newTreePlate("nameplate2")
      friendly(env, plate, "nameplate2", "MAGE")
      env.slash("")
      assert.is_true(printedContains(env, "class colour on (other friendly players' names), 1 plate(s) coloured"))
      assert.is_true(printedContains(env, "compact on|off | classcolor on|off | font default"))
      env.world.target = "nameplate2"
      env.world.plates.target = plate
      env.fire("PLAYER_TARGET_CHANGED")
      env.slash("debug")
      assert.is_true(printedContains(env,
        "debug: class MAGE, class colour #00FFFF (classcolor on), name colour: class #00FFFF"))
      assert.is_true(printedContains(env, "debug: mode class"))
      env.slash("classcolor off")
      env.slash("debug")
      assert.is_true(printedContains(env,
        "debug: class MAGE, class colour #00FFFF (classcolor off), name colour: Blizzard's"))
      env.world.flist.nameplate2 = true
      env.slash("debug")
      assert.is_true(printedContains(env, "name colour: friend #3FA7FF"))
      env.world.classes.nameplate2 = "PIRATE"
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: class PIRATE, class colour none (classcolor off)"))
    end)
  end)

  describe("guild line", function()
    -- guildLine returns our second line on a plate (shown), or nil.
    local function guildLine(env, plate)
      local label, holder = env.label(plate)
      if not label or not holder.shown then
        return nil
      end
      for _, l in ipairs(holder.labels) do
        if l ~= label and l.shown ~= false and type(l.text) == "string" and l.text:sub(1, 1) == "<" then
          return l, label
        end
      end
      return nil
    end

    it("puts the guild on a second line under every friendly player's name, our name above it", function()
      local env = load()
      -- A group member, a compact friendly player and a friendly player's full plate (compact off).
      local member, other = newTreePlate("nameplate1"), newTreePlate("nameplate2")
      env.world.plates.nameplate1, env.world.plates.nameplate2 = member, other
      for _, u in ipairs({ "nameplate1", "nameplate2" }) do
        env.world.players[u], env.world.friends[u] = true, true
      end
      env.world.party.nameplate1 = true
      env.world.guilds.nameplate1, env.world.guilds.nameplate2 = "Les Gardiens", "Ordo"
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      local sub, label = guildLine(env, member)
      assert.are.equal("<Les Gardiens>", sub.text)
      assert.are.equal(member.UnitFrame.name, sub.points[1][2])
      assert.are.equal(sub, label.points[1][2])
      assert.are.equal("#FF4FD8", hex(sub.color)) -- the name's colour
      assert.are.equal("<Ordo>", (guildLine(env, other)).text)
      -- It stays through health updates of the compact plate.
      env.world.health.nameplate2 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate2")
      assert.are.equal("<Ordo>", (guildLine(env, other)).text)
      -- Compact off: the full plate gets our name (to carry the line) even at size 1, no gap.
      env.slash("compact off")
      assert.are.equal("<Ordo>", (guildLine(env, other)).text)
      -- Leaving the guild: no second line, our name back on Blizzard's.
      env.world.guilds.nameplate1 = nil
      env.fire("GROUP_ROSTER_UPDATE")
      assert.is_nil(guildLine(env, member))
      local l1 = env.label(member)
      assert.are.equal(member.UnitFrame.name, l1.points[1][2])
    end)

    it("draws nothing for players without a guild, or when it cannot be read", function()
      for _, overrides in ipairs({ {}, { GetGuildInfo = function() error("boom") end },
        { GetGuildInfo = function() return "secret" end, issecretvalue = function(v) return v == "secret" end } }) do
        local env = load({ overrides = overrides, saved = { compact = false } })
        local plate = newTreePlate("nameplate2")
        env.world.plates.nameplate2 = plate
        env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        assert.is_nil(guildLine(env, plate))
        -- Size 1, no gap, no guild: Blizzard's name stays.
        assert.are.equal(1, plate.UnitFrame.name:GetAlpha())
        assert.is_false(printedContains(env, "error in"))
      end
    end)
  end)

  describe("hostiles tied to a quest", function()
    -- questHostile sets up a unit that can be attacked and is tied to a quest on nameplate2.
    local function questHostile(env, plate)
      env.world.plates.nameplate2 = plate
      env.world.attackable.nameplate2, env.world.quests.nameplate2 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    end

    -- untouched checks that nothing of ours is on the plate.
    local function untouched(env, plate)
      local label, holder = env.label(plate)
      assert.is_true(label == nil or holder.shown == false)
      local ch = env.chevron(plate)
      assert.is_true(ch == nil or ch.shown == false)
      assert.are.equal("#0080FF", hex(plate.UnitFrame.name.color))
      assert.are.equal(1, plate.UnitFrame.name:GetAlpha())
    end

    it("puts a yellow name and a single chevron on a hostile unit tied to a quest", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      local uf = plate.UnitFrame
      local label, holder = env.label(plate)
      assert.is_true(holder.shown)
      assert.are.equal("#FFFF00", hex(label.color))
      assert.are.equal("#FFFF00", hex(uf.name.color))
      assert.are.equal(0, uf.name.alpha)
      -- One "V", fully opaque, in the hostile colour, anchored on our name.
      local ch = env.chevron(plate)
      assert.is_true(ch.shown)
      assert.are.equal(1, vcount(ch))
      assert.are.equal("Interface\\AddOns\\GroupChevron\\chevron.tga", ch.textures[1].texture)
      assert.are.equal("#FFFF00", hex(ch.textures[1].vertex))
      assert.are.equal(1, ch.textures[1].alpha)
      assert.are.equal(label, ch.points[1][2])
      assert.are.equal("BOTTOM", ch.points[1][1])
      assert.are.equal("TOP", ch.points[1][3])
      -- The rest of the plate is Blizzard's: nothing faded or scaled.
      assert.is_nil(uf.HealthBarsContainer.alpha)
      assert.is_nil(uf.castBar.alpha)
      assert.are.equal(1, uf.HealthBarsContainer:GetScale())
    end)

    it("leaves attackable units that are not tied to a quest alone", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      env.world.plates.nameplate2 = plate
      env.world.attackable.nameplate2 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      untouched(env, plate)
      assert.are.equal(1, env.world.questCalls)
    end)

    it("does not ask the quest API about a unit that cannot be attacked, and never marks it", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      env.world.plates.nameplate2 = plate
      env.world.quests.nameplate2 = true -- a friendly quest NPC, say
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      untouched(env, plate)
      assert.are.equal(0, env.world.questCalls)
    end)

    it("marks nothing when an API is missing, fails or answers a secret value", function()
      local cases = {
        { UnitCanAttack = false },
        { C_QuestLog = {} },
        { C_QuestLog = { UnitIsRelatedToActiveQuest = function() error("boom") end } },
        {
          issecretvalue = function(v) return v == "secret" end,
          C_QuestLog = { UnitIsRelatedToActiveQuest = function() return "secret" end },
        },
      }
      for _, overrides in ipairs(cases) do
        local env = load({ overrides = overrides })
        local plate = newTreePlate("nameplate2")
        questHostile(env, plate)
        untouched(env, plate)
        assert.is_false(printedContains(env, "error in"))
      end
    end)

    it("is off with the addon", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      env.slash("off")
      untouched(env, plate)
      env.slash("on")
      assert.are.equal("#FFFF00", hex(env.label(plate).color))
    end)

    it("applies hostilesize, hostilenamegap and hostilechevsize, independently of the other sizes", function()
      local env = load({ saved = { hostilesize = 2, hostilenamegap = 4, hostilechevsize = 3, textsize = 3,
        othersize = 3, othernamegap = 9, namegap = 9, chevsize = 5 } })
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      local label, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      -- (lift 0 + hostilenamegap 4) / hostilesize 2, in our frame's units.
      assert.are.same({ "BOTTOM", plate.UnitFrame.name, "BOTTOM", 0, 2 }, label.points[1])
      local ch = env.chevron(plate)
      assert.are.equal(30, ch.w) -- 10 x 3
      assert.are.equal(15, ch.h) -- a single "V": 5 x 3
      assert.are.equal(30, ch.textures[1].w)
      assert.are.equal(15, ch.textures[1].h)
      env.slash("hostilechevsize 1.5")
      assert.are.equal(15, env.chevron(plate).w)
      assert.are.equal(7.5, env.chevron(plate).h)
      env.slash("hostilesize 1")
      env.slash("hostilenamegap -3")
      label, holder = env.label(plate)
      assert.are.equal(1, holder.scale)
      assert.are.equal(-3, label.points[1][5])
    end)

    it("draws a black outline under the chevron, per kind, with its own thickness", function()
      local env = load()
      local plate = newPlate("nameplate1", "Orc", BLUE)
      env.world.plates.nameplate1 = plate
      env.world.attackable.nameplate1, env.world.quests.nameplate1 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      local function outlines(ch)
        local out = {}
        for _, t in ipairs(ch.textures) do
          if t.owner then
            out[#out + 1] = t
          end
        end
        return out
      end
      local ch = env.chevron(plate)
      assert.are.equal(8, #outlines(ch))
      assert.are.equal("#000000", hex(outlines(ch)[1].vertex))
      assert.is_true(outlines(ch)[1].shown)
      -- Default thickness 2: 0.1875 * 2 * the chevron size (1 in these specs), to the right for the first copy.
      assert.are.equal(0.375, outlines(ch)[1].points[1][4])
      env.slash("hostileoutlinesize 4")
      assert.are.equal(4, env.GroupChevronDB.hostileoutlinesize)
      assert.are.equal(0.75, outlines(env.chevron(plate))[1].points[1][4])
      env.slash("hostileoutlinesize 0")
      assert.are.equal(0, env.GroupChevronDB.hostileoutlinesize)
      assert.is_false(outlines(env.chevron(plate))[1].shown)
      env.slash("hostileoutlinesize 1")
      assert.is_true(outlines(env.chevron(plate))[1].shown)
    end)

    it("sizes the chevron of a friend and of a guildmate by their own settings, not by chevsize", function()
      local env = load()
      local plate = newPlate("nameplate1", "Friend", BLUE)
      env.world.plates.nameplate1 = plate
      env.world.players.nameplate1, env.world.friends.nameplate1, env.world.flist.nameplate1 = true, true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      assert.are.equal(10, env.chevron(plate).w) -- friendchevsize is 1 in these specs
      env.slash("chevsize 4")
      assert.are.equal(10, env.chevron(plate).w)
      env.slash("friendchevsize 2.5")
      assert.are.equal(25, env.chevron(plate).w)
      env.slash("guildchevsize 4")
      assert.are.equal(4, env.GroupChevronDB.guildchevsize)
      assert.are.equal(25, env.chevron(plate).w)
    end)

    it("takes the hostile colour for the name and the chevron, from /gchev hostilecolor", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      env.slash("hostilecolor #FF8000")
      assert.are.equal("#FF8000", hex(env.GroupChevronDB.hostilecolor))
      assert.are.equal("#FF8000", hex(env.label(plate).color))
      assert.are.equal("#FF8000", hex(plate.UnitFrame.name.color))
      assert.are.equal("#FF8000", hex(env.chevron(plate).textures[1].vertex))
      env.slash("hostilecolor nonsense")
      assert.is_true(printedContains(env, "invalid hostilecolor"))
      assert.are.equal("#FF8000", hex(env.GroupChevronDB.hostilecolor))
      env.slash("hostilecolor")
      assert.is_true(printedContains(env, "hostilecolor #FF8000 (default #FFFF00)"))
      -- The other colours are untouched.
      assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))
      assert.are.equal("#3FA7FF", hex(env.GroupChevronDB.friendcolor))
    end)

    it("checks the hostile sizes from the slash commands", function()
      local env = load()
      env.slash("hostilechevsize")
      assert.is_true(printedContains(env, "hostilechevsize 1 (1 to 5, default 3)"))
      env.slash("hostilechevsize 5")
      assert.are.equal(5, env.GroupChevronDB.hostilechevsize)
      env.slash("hostilechevsize 5.5")
      assert.is_true(printedContains(env, "invalid hostilechevsize"))
      assert.are.equal(5, env.GroupChevronDB.hostilechevsize)
      env.slash("hostilesize 3")
      assert.are.equal(3, env.GroupChevronDB.hostilesize)
      env.slash("hostilesize 4")
      assert.is_true(printedContains(env, "invalid hostilesize"))
      assert.are.equal(3, env.GroupChevronDB.hostilesize)
      env.slash("hostilenamegap")
      assert.is_true(printedContains(env, "hostilenamegap 0 (-10 to 40, default 5)"))
      env.slash("hostilenamegap 40")
      assert.are.equal(40, env.GroupChevronDB.hostilenamegap)
      env.slash("hostilenamegap 41")
      env.slash("hostilenamegap 2.5")
      assert.are.equal(40, env.GroupChevronDB.hostilenamegap)
    end)

    it("keeps the look on name updates, and gives Blizzard's name and colour back when the quest ends", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      -- Blizzard recolours its name: ours stays.
      plate.UnitFrame.name:SetTextColor(1, 0, 0)
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      assert.are.equal("#FFFF00", hex(env.label(plate).color))
      assert.are.equal("#FFFF00", hex(plate.UnitFrame.name.color))

      -- Blizzard colours its name again, then the objective is done: the quest log changes, and the
      -- plates are re-checked once, later.
      plate.UnitFrame.name:SetTextColor(unpack(BLUE))
      env.hooks.CompactUnitFrame_UpdateName(plate.UnitFrame)
      env.world.quests.nameplate2 = nil
      env.fire("QUEST_LOG_UPDATE")
      env.fire("UNIT_QUEST_LOG_CHANGED", "player")
      assert.are.equal(1, #env.world.timers)
      assert.are.equal("#FFFF00", hex(env.label(plate).color)) -- not yet
      env.runTimers()
      local _, holder = env.label(plate)
      assert.is_false(holder.shown)
      assert.is_false(env.chevron(plate).shown)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
      assert.are.equal("#0080FF", hex(plate.UnitFrame.name.color))

      -- A new quest ties it again.
      env.world.quests.nameplate2 = true
      env.fire("QUEST_ACCEPTED", 1234)
      env.runTimers()
      assert.are.equal("#FFFF00", hex(env.label(plate).color))
      assert.is_true(env.chevron(plate).shown)
      assert.are.equal(0, plate.UnitFrame.name.alpha)
    end)

    it("shows the quest chevron on the target too, and nothing is left when the plate is released", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      env.world.target = "nameplate2"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal("#FFFF00", hex(env.label(plate).color))
      assert.is_true(env.chevron(plate).shown)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
      assert.is_false(env.chevron(plate).shown)
      assert.are.equal(1, plate.UnitFrame.name.alpha)
      assert.are.equal("#0080FF", hex(plate.UnitFrame.name.color))
    end)

    it("swaps the double chevron of a friend and the single one of a quest hostile on a pooled UnitFrame", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      local frames = function()
        local out = {}
        for _, f in ipairs(env.frames) do
          if f.parent == plate.UnitFrame and #f.textures > 0 then
            out[#out + 1] = f
          end
        end
        return out
      end
      -- A friend: the double chevron.
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2, env.world.flist.nameplate2 = true, true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal(1, #frames())
      assert.are.equal(2, vcount(frames()[1]))
      assert.is_true(frames()[1].shown)

      -- The UnitFrame now shows a hostile quest unit: the single "V" only.
      env.world.players.nameplate2, env.world.friends.nameplate2, env.world.flist.nameplate2 = nil, nil, nil
      env.world.attackable.nameplate2, env.world.quests.nameplate2 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal(2, #frames())
      assert.is_false(frames()[1].shown)
      assert.is_true(frames()[2].shown)
      assert.are.equal(1, vcount(frames()[2]))
      assert.are.equal("#FFFF00", hex(env.label(plate).color))

      -- And back to the friend: the double chevron again, the single one hidden.
      env.world.attackable.nameplate2, env.world.quests.nameplate2 = nil, nil
      env.world.players.nameplate2, env.world.friends.nameplate2, env.world.flist.nameplate2 = true, true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.equal(2, #frames())
      assert.is_true(frames()[1].shown)
      assert.is_false(frames()[2].shown)
      assert.are.equal("#3FA7FF", hex(env.label(plate).color))
    end)

    it("draws a single chevron out of rotated rectangles when the texture cannot be loaded", function()
      textureMissing = true
      local ok, err = pcall(function()
        local env = load()
        local plate = newTreePlate("nameplate2")
        questHostile(env, plate)
        local ch = env.chevron(plate)
        assert.is_true(ch.shown)
        -- Two arms (one "V"), not four.
        local arms = 0
        for _, t in ipairs(ch.textures) do
          if t.color then
            arms = arms + 1
            assert.are.equal("#FFFF00", hex(t.color))
          end
        end
        assert.are.equal(2, arms)
        assert.is_true(printedContains(env, "chevron texture not found"))
      end)
      textureMissing = false
      assert.is_true(ok, err)
    end)

    it("is listed in /gchev and /gchev debug", function()
      local env = load()
      local plate = newTreePlate("nameplate2")
      questHostile(env, plate)
      env.world.plates.target = plate
      env.world.attackable.target, env.world.quests.target = true, true -- /gchev asks about "target"
      env.slash("")
      assert.is_true(printedContains(env, "hostiles (quest): colour #FFFF00, hostilechevsize 1, hostilesize 1, "
        .. "hostilenamegap 0, 1 plate(s) marked; target quest hostile: yes (UnitIsRelatedToActiveQuest, "
        .. "attackable true)"))
      assert.is_true(printedContains(env, "hostilecolor #RRGGBB | hostilechevsize 1-5 | hostilesize 1-3"))
      assert.is_true(printedContains(env, "reset | options | debug"))
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target quest hostile: yes (UnitIsRelatedToActiveQuest"))
      env.world.quests.nameplate2 = nil
      env.slash("debug")
      assert.is_true(printedContains(env, "debug: target quest hostile: no (none, attackable true)"))
    end)
  end)

  describe("service NPCs", function()
    local NPC_GUID = "Creature-0-4372-0-1-352-0000ABCDEF"

    -- npcClient returns load options for a client where nameplate5 is a friendly NPC (creature
    -- 352) whose tooltip subtitle is npc.subtitle, the "npc" unit (an open window) is the same
    -- creature, CanMerchantRepair answers npc.repair and the friendly NPC plates setting is
    -- npc.cvar ("1", "0" or nil: missing).
    local function npcClient(npc, saved)
      local overrides = {
        UnitGUID = function(unit)
          if unit == "nameplate5" or unit == "npc" then
            return NPC_GUID
          end
          return "Player-" .. tostring(unit)
        end,
        GetLocale = function() return npc.locale or "enUS" end,
        C_TooltipInfo = {
          GetUnit = function(unit)
            if unit ~= "nameplate5" then
              return nil
            end
            return { lines = { { leftText = "Thor" }, npc.subtitle and { leftText = npc.subtitle } or nil } }
          end,
        },
        CanMerchantRepair = function() return npc.repair end,
        IsTradeskillTrainer = function() return npc.tradeskill end,
        InCombatLockdown = function() return npc.combat == true end,
        C_CVar = {
          GetCVar = function(name)
            if name == "nameplateShowFriendlyNPCs" then
              return npc.cvar
            end
            return name == "nameplateShowFriends" and "1" or nil
          end,
          SetCVar = function(name, v)
            if name == "nameplateShowFriendlyNPCs" and npc.cvar ~= nil and not npc.refuse then
              npc.cvar = v
            end
          end,
        },
        Enum = { PlayerInteractionType = { Merchant = 5, TaxiNode = 6 } },
        -- The atlases of the Forever build (1.60.1.70959) the defaults use, plus "FlightMaster".
        C_Texture = {
          GetAtlasInfo = function(name)
            local known = { FlightMaster = true, flightmaster = true, innkeeper = true, banker = true,
              auctioneer = true, stablemaster = true, class = true, profession = true, repair = true,
              ["levelup-icon-bag"] = true }
            return known[name] and { width = 32 } or nil
          end,
        },
      }
      -- The friendly NPC options start from their defaults (compact on, icon size 5).
      saved = saved or {}
      if saved.npccompact == nil then
        saved.npccompact = true
      end
      return { overrides = overrides, saved = saved }
    end

    -- showNPC puts the friendly NPC on nameplate5.
    local function showNPC(env, plate)
      env.world.plates.nameplate5 = plate
      env.world.friends.nameplate5 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
    end

    -- icon returns the role icon frame on a plate's UnitFrame and its texture, if any.
    local function icon(env, plate)
      for _, f in ipairs(env.frames) do
        if f.parent == plate.UnitFrame and f.tex then
          return f, f.tex.atlas or f.tex.texture
        end
      end
      return nil
    end

    it("puts the role icon above a flight master's name and shows its name only", function()
      local env = load(npcClient({ subtitle = "Gryphon Master" }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local uf = plate.UnitFrame
      local frame, texture = icon(env, plate)
      assert.is_true(frame.shown)
      assert.are.equal("flightmaster", texture)
      assert.are.equal(30, frame.w) -- 6 x the default npciconsize 5
      -- An atlas of the client's point-of-interest icons.
      assert.are.equal("flightmaster", frame.tex.atlas)
      -- Above our own name, in the default green: this client has no UnitSelectionColor.
      local label = env.label(plate)
      assert.are.equal(label, frame.points[1][2])
      assert.are.equal("#1AFF1A", hex(label.color))
      -- Name only (npccompact): the health bar and cast bar are faded, the icon is kept.
      assert.are.equal(0, uf.HealthBarsContainer.alpha)
      assert.are.equal(0, uf.castBar.alpha)
      assert.is_nil(frame.alpha)
      assert.is_false(printedContains(env, "error in"))
    end)

    it("reads a French client's subtitle as the game spells it", function()
      local env = load(npcClient({ subtitle = "Maître des gryphons", locale = "frFR" }, { npccompact = false }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local frame, texture = icon(env, plate)
      assert.is_true(frame.shown)
      assert.are.equal("flightmaster", texture)
    end)

    it("shows the roles shipped with the addon, and lets learned roles improve them", function()
      local opts = npcClient({ repair = true })
      opts.shipped = { [352] = "vendor", [7] = "bogus" }
      local env = load(opts)
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      assert.are.equal("levelup-icon-bag", select(2, icon(env, plate)))
      -- The same merchant opens its window: it repairs, the better role wins.
      env.fire("MERCHANT_SHOW")
      env.runTimers()
      assert.are.equal("repair", select(2, icon(env, plate)))
      env.slash("")
      assert.is_true(printedContains(env, "1 role(s) learned, 1 shipped"))
      env.world.target = "nameplate5"
      env.world.plates.target = plate
      env.GroupChevronDB.npcroles[352] = nil
      env.slash("debug")
      assert.is_true(printedContains(env, "(shipped with the addon;"))
    end)

    it("lets the player pick a role's icon: an atlas the client has, or a texture path", function()
      local env = load(npcClient({ subtitle = "Gryphon Master" }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local frame = icon(env, plate)
      env.slash("icon flight FlightMaster")
      assert.are.equal("FlightMaster", env.GroupChevronDB.roleicons.flight)
      assert.are.equal("FlightMaster", frame.tex.atlas)
      assert.is_true(frame.shown)
      -- An atlas the client does not have, an unknown role or a bad name: refused.
      env.slash("icon flight NoSuchAtlas")
      assert.is_true(printedContains(env, "no atlas \"NoSuchAtlas\""))
      env.slash("icon wizard FlightMaster")
      assert.is_true(printedContains(env, "unknown role"))
      env.slash("icon flight bad name!")
      assert.are.equal("FlightMaster", env.GroupChevronDB.roleicons.flight)
      -- A texture path, shown whole unless it is an Interface\Icons one.
      env.slash("icon flight Interface\\Minimap\\Tracking\\FlightMaster")
      assert.are.equal("Interface\\Minimap\\Tracking\\FlightMaster", frame.tex.texture)
      assert.are.same({ 0, 1, 0, 1 }, frame.tex.texcoord)
      -- Back to the default; /gchev icon lists them all.
      env.slash("icon flight default")
      assert.is_nil(env.GroupChevronDB.roleicons.flight)
      assert.are.equal("flightmaster", frame.tex.atlas)
      env.slash("icon")
      assert.is_true(printedContains(env, "icon vendor: levelup-icon-bag"))
      assert.is_false(printedContains(env, "error in"))
    end)

    it("shows the health bar only while hurt, the target included, and never scales it", function()
      local env = load(npcClient({ subtitle = "Gryphon Master" }, { otherbarsize = 2 }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local uf = plate.UnitFrame
      assert.are.equal(0, uf.HealthBarsContainer.alpha)
      env.world.target = "nameplate5"
      env.fire("PLAYER_TARGET_CHANGED")
      assert.are.equal(0, uf.HealthBarsContainer.alpha)
      assert.is_true(icon(env, plate).shown)
      -- Hurt: the bar shows, target or not.
      env.world.health.nameplate5 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate5")
      assert.are.equal(1, uf.HealthBarsContainer.alpha)
      env.world.health.nameplate5 = { 100, 100 }
      env.fire("UNIT_HEALTH", "nameplate5")
      assert.are.equal(0, uf.HealthBarsContainer.alpha)
      assert.are.equal(1, uf.HealthBarsContainer:GetScale())
    end)

    it("shows \"<name> (<level>)\" with the subtitle below it, the level even while hurt", function()
      local env = load(npcClient({ subtitle = "Maître des gryphons", locale = "frFR" }, { npcnamegap = 3 }))
      local plate = newTreePlate("nameplate5")
      env.world.levels.nameplate5 = 55
      showNPC(env, plate)
      local uf = plate.UnitFrame
      local label, holder = env.label(plate)
      assert.are.equal("Farbatosz Marokbar (55)", label.text)
      -- The subtitle: the last FontString of our frame, where Blizzard's name was (+ npcnamegap),
      -- our name right above it, the icon above our name.
      local sub = holder.labels[#holder.labels]
      assert.are.equal("<Maître des gryphons>", sub.text)
      assert.is_true(sub.shown)
      assert.are.equal(uf.name, sub.points[1][2])
      assert.are.equal(3, sub.points[1][5])
      assert.are.equal(sub, label.points[1][2])
      assert.are.equal("TOP", label.points[1][3])
      assert.are.equal(label, icon(env, plate).points[1][2])
      assert.are.equal(label.color[1], sub.color[1])
      -- Hurt: the bar shows and the level stays.
      env.world.health.nameplate5 = { 50, 100 }
      env.fire("UNIT_HEALTH", "nameplate5")
      assert.are.equal("Farbatosz Marokbar (55)", label.text)
      assert.are.equal(1, label.alpha)
    end)

    it("takes the game's reaction colour for the name, and gives Blizzard's back afterwards", function()
      local npc = { subtitle = "Gryphon Master" }
      local opts = npcClient(npc)
      opts.overrides.UnitSelectionColor = function() return 1, 1, 0, 1 end -- neutral: yellow
      local env = load(opts)
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local label, holder = env.label(plate)
      assert.are.equal("#FFFF00", hex(label.color))
      assert.are.equal("#FFFF00", hex(holder.labels[#holder.labels].color))
      -- The plate stops being a friendly NPC: Blizzard's own colour comes back.
      env.world.friends.nameplate5 = false
      env.world.attackable.nameplate5 = true
      env.fire("UNIT_LEVEL", "nameplate5")
      assert.are.equal("#0080FF", hex(plate.UnitFrame.name.color))
      -- A failing or secret colour: the default green.
      for _, fn in ipairs({ function() error("boom") end, function() return "secret", 1, 1 end }) do
        opts = npcClient({ subtitle = "Gryphon Master" })
        opts.overrides.UnitSelectionColor = fn
        opts.overrides.issecretvalue = function(v) return v == "secret" end
        env = load(opts)
        plate = newTreePlate("nameplate5")
        showNPC(env, plate)
        assert.are.equal("#1AFF1A", hex(env.label(plate).color))
        assert.is_false(printedContains(env, "error in"))
      end
    end)

    it("shows no subtitle line when the tooltip's second line is the level line", function()
      local env = load(npcClient({ subtitle = "Level 12 Humanoid" }))
      local plate = newTreePlate("nameplate5")
      env.world.levels.nameplate5 = 12
      showNPC(env, plate)
      local label, holder = env.label(plate)
      assert.are.equal("Farbatosz Marokbar (12)", label.text)
      for _, l in ipairs(holder.labels) do
        assert.is_true(l == label or l.text ~= "Level 12 Humanoid" or l.shown == false)
      end
      assert.are.equal(plate.UnitFrame.name, label.points[1][2])
    end)

    it("keeps Blizzard's full plate with npccompact off, and sizes the icon", function()
      local env = load(npcClient({ subtitle = "Innkeeper" }, { npccompact = false, npciconsize = 2 }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local frame, texture = icon(env, plate)
      assert.are.equal("innkeeper", texture)
      assert.are.equal(12, frame.w)
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.alpha)
      env.slash("npciconsize 4")
      assert.are.equal(24, frame.w)
    end)

    it("shows every friendly NPC's name only, role or not, with the icons off too", function()
      -- No role: name only, no icon.
      local env = load(npcClient({ subtitle = "Level 12" }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local frame = icon(env, plate)
      assert.is_true(frame == nil or frame.shown == false)
      assert.are.equal(0, plate.UnitFrame.HealthBarsContainer.alpha)

      -- Icons off, compact on (seen in game: the health bar stayed): name only, no icon.
      env = load(npcClient({ subtitle = "Gryphon Master", repair = true }, { npcicons = false }))
      plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      frame = icon(env, plate)
      assert.is_true(frame == nil or frame.shown == false)
      assert.are.equal(0, plate.UnitFrame.HealthBarsContainer.alpha)
      assert.is_not_nil(env.label(plate))
      -- Nothing is learned while the icons are off.
      env.fire("MERCHANT_SHOW")
      assert.are.same({}, env.GroupChevronDB.npcroles)
    end)

    it("leaves friendly NPCs alone with every option off, and sizes their names", function()
      local env = load(npcClient({ subtitle = "Gryphon Master" }, { npcicons = false, npccompact = false }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      assert.is_nil(icon(env, plate))
      assert.is_nil(env.label(plate))
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.alpha)
      assert.are.equal(1, plate.UnitFrame.name:GetAlpha())
      -- A text size other than 1 is enough: our name at that size, the rest of the plate Blizzard's.
      env.slash("npcsize 2")
      local _, holder = env.label(plate)
      assert.are.equal(2, holder.scale)
      assert.is_nil(plate.UnitFrame.HealthBarsContainer.alpha)
      env.slash("npcsize 1")
      assert.is_false(holder.shown)
      assert.are.equal(1, plate.UnitFrame.name:GetAlpha())
    end)

    it("learns the role from the windows an NPC opens, and shows it at once", function()
      local npc = { repair = false }
      local env = load(npcClient(npc))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      assert.is_nil(icon(env, plate))
      env.fire("MERCHANT_SHOW")
      assert.are.equal("vendor", env.GroupChevronDB.npcroles[352])
      env.runTimers()
      local frame, texture = icon(env, plate)
      assert.is_true(frame.shown)
      assert.are.equal("levelup-icon-bag", texture)
      -- The same merchant can repair: the better role wins.
      npc.repair = true
      env.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
      env.runTimers()
      assert.are.equal("repair", env.GroupChevronDB.npcroles[352])
      assert.are.equal("repair", select(2, icon(env, plate)))
      -- The interaction manager's taxi window: a flight master.
      env.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 6)
      assert.are.equal("flight", env.GroupChevronDB.npcroles[352])
      -- An unknown window teaches nothing.
      env.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 99)
      assert.are.equal("flight", env.GroupChevronDB.npcroles[352])
      -- Trainers: a profession trainer and a class trainer are two roles.
      env.GroupChevronDB.npcroles[352] = nil
      npc.tradeskill = true
      env.fire("TRAINER_SHOW")
      env.runTimers()
      assert.are.equal("profession", env.GroupChevronDB.npcroles[352])
      assert.are.equal("profession", select(2, icon(env, plate)))
      env.GroupChevronDB.npcroles[352] = nil
      npc.tradeskill = false
      env.fire("TRAINER_SHOW")
      env.runTimers()
      assert.are.equal("trainer", env.GroupChevronDB.npcroles[352])
      assert.are.equal("class", select(2, icon(env, plate)))
      env.GroupChevronDB.npcroles[352] = "flight"
      env.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 99)
      assert.are.equal("flight", env.GroupChevronDB.npcroles[352])
      assert.is_false(printedContains(env, "error in"))
    end)

    it("gives everything back when the UnitFrame shows an enemy or the plate goes", function()
      local npc = { subtitle = "Gryphon Master" }
      local env = load(npcClient(npc))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      local uf = plate.UnitFrame
      local frame = icon(env, plate)
      assert.is_true(frame.shown)
      -- The pooled UnitFrame now shows an enemy without a subtitle.
      npc.subtitle = nil
      env.world.friends.nameplate5 = false
      env.world.attackable.nameplate5 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
      assert.is_false(frame.shown)
      assert.are.equal(1, uf.HealthBarsContainer.alpha)
      assert.are.equal(1, uf.name:GetAlpha())
      -- Back to the flight master, then the plate is removed.
      npc.subtitle = "Gryphon Master"
      env.world.friends.nameplate5, env.world.attackable.nameplate5 = true, false
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
      assert.is_true(frame.shown)
      env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
      assert.is_false(frame.shown)
      assert.are.equal(1, uf.name:GetAlpha())
    end)

    it("is off with the addon, and comes back with it", function()
      local env = load(npcClient({ subtitle = "Gryphon Master" }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      env.slash("off")
      assert.is_false(icon(env, plate).shown)
      env.slash("on")
      assert.is_true(icon(env, plate).shown)
      env.slash("npcicons off")
      assert.is_false(icon(env, plate).shown)
      assert.is_false(env.GroupChevronDB.npcicons)
    end)

    it("turns the friendly NPC nameplates on or off only when asked, never in combat", function()
      local npc = { cvar = "0" }
      local env = load(npcClient(npc))
      env.fire("PLAYER_ENTERING_WORLD")
      assert.are.equal("0", npc.cvar) -- never changed by itself
      assert.is_true(printedContains(env, "/gchev npcplates on"))
      assert.is_true(env.GroupChevronDB.npcplatesnoticed)
      env.slash("npcplates on")
      assert.are.equal("1", npc.cvar)
      assert.is_true(printedContains(env, "npcplates on"))
      npc.combat = true
      env.slash("npcplates off")
      assert.are.equal("1", npc.cvar)
      assert.is_true(printedContains(env, "not allow it in combat"))
      npc.combat = false
      env.slash("npcplates maybe")
      assert.are.equal("1", npc.cvar)
      env.slash("npcplates off")
      assert.are.equal("0", npc.cvar)
      npc.refuse = true
      env.slash("npcplates on")
      assert.is_true(printedContains(env, "refused the change"))

      -- Said once per install only.
      local saved = { npcplatesnoticed = true }
      env = load(npcClient({ cvar = "0" }, saved))
      env.fire("PLAYER_ENTERING_WORLD")
      assert.is_false(printedContains(env, "/gchev npcplates on"))

      -- A client without the setting.
      env = load(npcClient({}))
      env.slash("npcplates on")
      assert.is_true(printedContains(env, "no friendly NPC nameplates setting"))
      assert.is_false(printedContains(env, "error in"))
    end)

    it("prints the service NPC state in /gchev and /gchev debug", function()
      local env = load(npcClient({ subtitle = "Gryphon Master", cvar = "1" }))
      local plate = newTreePlate("nameplate5")
      showNPC(env, plate)
      env.slash("")
      assert.is_true(printedContains(env,
        "friendly NPCs: icons on, compact on, npcsize 1, npcnamegap 5, npciconsize 5, friendly NPC nameplates on"))
      assert.is_true(printedContains(env, "1 plate(s) marked"))
      env.world.target = "nameplate5"
      env.world.plates.target = plate
      env.slash("debug")
      assert.is_true(printedContains(env, "target service NPC: yes, flight (subtitle"))
      assert.is_false(printedContains(env, "error in"))
    end)
  end)

  describe("settings and options panel", function()
    -- widgetClient returns load() overrides: a Settings API stub (recording the registered
    -- category and what was opened) and CreateFrame making plain widgets for the panel.
    local function widgetClient(opts)
      opts = opts or {}
      local rec = { opened = {}, picker = nil }
      local overrides = {}
      -- overrides.decorate is passed to load() as opts.decorate by the callers below.
      overrides.decorate = function(f, kind, parent, template)
        if kind == "ScrollFrame" then
          function f:SetScrollChild(child) self.scrollChild = child end
        end
        if kind ~= "Frame" or parent == nil then
          function f:SetChecked(v) self.checked = v end
          function f:GetChecked() return self.checked end
          function f:SetValue(v) self.value = v end
          function f:GetValue() return self.value end
          function f:SetText(t) self.text = t end
          function f:CreateFontString()
            local fs = newFrame(self)
            fs.SetText = function(o, t) o.text = t end
            return fs
          end
          setmetatable(f, { __index = function() return function() end end })
        end
        rec.created = rec.created or {}
        rec.created[#rec.created + 1] = { kind = kind, f = f, parent = parent, template = template }
        return f
      end
      if not opts.noSettings then
        overrides.Settings = {
          -- rec.frame / rec.name: the first category registered (GroupChevron's own); rec.pages:
          -- name -> frame of every page, sub-categories included; rec.subs: sub-category names.
          RegisterCanvasLayoutCategory = function(frame, name)
            if not rec.frame then
              rec.frame, rec.name = frame, name
            end
            rec.pages = rec.pages or {}
            rec.pages[name] = frame
            return { GetID = function() return 42 end, name = name }
          end,
          RegisterCanvasLayoutSubcategory = not opts.noSubcategories and function(cat, frame, name)
            assert(cat.name == "GroupChevron")
            rec.subs = rec.subs or {}
            rec.subs[#rec.subs + 1] = name
            rec.pages = rec.pages or {}
            rec.pages[name] = frame
            return { GetID = function() return 43 end }
          end or nil,
          RegisterAddOnCategory = function(cat) rec.category = cat end,
          OpenToCategory = function(id)
            if opts.openFails then
              error("protected")
            end
            rec.opened[#rec.opened + 1] = id
          end,
        }
      end
      overrides.ColorPickerFrame = {
        SetupColorPickerAndShow = function(_, info) rec.picker = info end,
        GetColorRGB = function() return rec.rgb[1], rec.rgb[2], rec.rgb[3] end,
      }
      return overrides, rec
    end

    local function widget(rec, kind, n)
      local i = 0
      for _, c in ipairs(rec.created) do
        if c.kind == kind then
          i = i + 1
          if i == n then
            return c.f
          end
        end
      end
    end

    -- page returns the content frame (the scroll child) of the options page called name.
    local function page(rec, name)
      for _, c in ipairs(rec.created) do
        if c.kind == "ScrollFrame" and c.parent == rec.pages[name] then
          return c.f.scrollChild
        end
      end
    end

    -- resetButton returns the Reset button of the options page called name.
    local function resetButton(rec, name)
      local content = page(rec, name)
      for _, c in ipairs(rec.created) do
        if c.kind == "Button" and c.parent == content and c.f.text == "Reset to defaults" then
          return c.f
        end
      end
    end

    -- labelY returns the y of the first label of content whose text starts with prefix.
    local function labelY(content, prefix)
      for _, l in ipairs(content.labels) do
        if l.text and l.text:sub(1, #prefix) == prefix then
          return l.points[1][5]
        end
      end
    end

    it("registers the panel and opens it with /gchev options", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      assert.are.equal("GroupChevron", rec.name)
      assert.is_table(rec.category)
      -- Its pages are sub-categories, in this order.
      assert.are.same({ "Main", "Friendly players", "Quest mobs", "NPCs" }, rec.subs)
      env.slash("options")
      assert.are.same({ 42 }, rec.opened)
      env.slash("")
      assert.is_true(printedContains(env, "reset | options | debug"))
    end)

    local function panelTexts(rec)
      local texts = {}
      for _, c in ipairs(rec.created) do
        if c.kind == "ScrollFrame" then
          -- the labels of the scroll child (every label of the panel is created on it)
          for _, fs in ipairs(c.f.scrollChild.labels) do
            texts[#texts + 1] = fs.text
          end
        elseif c.kind == "CheckButton" or c.kind == "Button" then
          -- checkbox texts are labels of the child; buttons carry their own text
          if c.f.text then
            texts[#texts + 1] = c.f.text
          end
        end
      end
      return texts
    end

    local function has(list, s)
      for _, v in ipairs(list) do
        if v == s then
          return true
        end
      end
      return false
    end

    it("shows the panel in French on a frFR client, keeping the addon name", function()
      local overrides, rec = widgetClient()
      overrides.GetLocale = function() return "frFR" end
      load({ overrides = overrides })
      local texts = panelTexts(rec)
      for _, s in ipairs({ "GroupChevron", "Activé", "Membres du groupe", "Couleur du nom",
        "Taille du chevron", "Réinitialiser", "Afficher le niveau" }) do
        assert.is_true(has(texts, s), s)
      end
      assert.is_false(has(texts, "Enabled"))
      assert.is_false(has(texts, "Reset to defaults"))
    end)

    it("shows the panel in German on a deDE client", function()
      local overrides, rec = widgetClient()
      overrides.GetLocale = function() return "deDE" end
      load({ overrides = overrides })
      local texts = panelTexts(rec)
      for _, s in ipairs({ "GroupChevron", "Aktiviert", "Gruppenmitglieder", "Namensfarbe", "Zurücksetzen" }) do
        assert.is_true(has(texts, s), s)
      end
      assert.is_false(has(texts, "Enabled"))
    end)

    it("keeps the English panel on enUS, an unknown locale or a failing GetLocale", function()
      for _, getLocale in ipairs({
        function() return "enUS" end,
        function() return "xxXX" end,
        function() error("boom") end,
      }) do
        local overrides, rec = widgetClient()
        overrides.GetLocale = getLocale
        load({ overrides = overrides })
        local texts = panelTexts(rec)
        for _, s in ipairs({ "GroupChevron", "Enabled", "Group members", "Name colour",
          "Chevron size", "Reset to defaults", "Show level" }) do
          assert.is_true(has(texts, s), s)
        end
      end
    end)

    it("gives each page a scroll frame whose child holds its widgets", function()
      local overrides, rec = widgetClient()
      load({ overrides = overrides })
      local contents = {}
      for _, name in ipairs({ "GroupChevron", "Main", "Friendly players", "Quest mobs", "NPCs" }) do
        local content = page(rec, name)
        assert.is_table(content, name)
        assert.are_not.equal(rec.pages[name], content)
        contents[content] = name
      end
      for _, kind in ipairs({ "CheckButton", "Slider", "Button" }) do
        for _, c in ipairs(rec.created) do
          if c.kind == kind then
            assert.is_string(contents[c.parent])
          end
        end
      end
      -- Main: Enabled, the name font and Reset; the category itself only says where to go.
      assert.are.equal(page(rec, "Main"), widget(rec, "CheckButton", 1).parent)
      assert.are.equal(page(rec, "Main"), widget(rec, "Button", 2).parent)
      assert.is_number(labelY(page(rec, "Main"), "Name font"))
      assert.is_number(labelY(page(rec, "GroupChevron"), "Choose a section"))
      assert.are.equal("GroupChevron - Quest mobs", page(rec, "Quest mobs").labels[1].text)
    end)

    it("anchors each chevron preview on its own page, even once the panel is built", function()
      local overrides, rec = widgetClient()
      load({ overrides = overrides })
      rec.frame.scripts.OnShow(rec.frame)
      for name, count in pairs({ ["Friendly players"] = 3, ["Quest mobs"] = 1 }) do
        local content = page(rec, name)
        local vs = 0
        for _, t in ipairs(content.textures) do
          if t.texture == "Interface\\AddOns\\GroupChevron\\chevron.tga" and t.vertex and t.vertex[1] ~= 0 then
            vs = vs + 1
            assert.are.equal(content, t.points[1][2], name)
          end
        end
        -- A double chevron per section on the players' page, a single one for the quest mobs.
        assert.are.equal(name == "Quest mobs" and 1 or 2 * count, vs, name)
      end
    end)

    it("falls back to one category per page without sub-categories", function()
      local overrides, rec = widgetClient({ noSubcategories = true })
      local env = load({ overrides = overrides })
      assert.are.equal("GroupChevron", rec.name)
      for _, name in ipairs({ "Main", "Friendly players", "Quest mobs", "NPCs" }) do
        assert.is_table(rec.pages["GroupChevron - " .. name], name)
      end
      assert.is_false(printedContains(env, "error in"))
    end)

    it("orders the sections of each page from the top down", function()
      local overrides, rec = widgetClient()
      load({ overrides = overrides })
      -- Friendly players: Members, Friends, Guildmates, Friendlies.
      local players = page(rec, "Friendly players")
      local members, friends = labelY(players, "Group members"), labelY(players, "Friends")
      local guild, friendlies = labelY(players, "Guildmates"), labelY(players, "Friendlies")
      assert.is_number(members)
      assert.is_true(members > friends and friends > guild and guild > friendlies)
      assert.is_number(labelY(page(rec, "Quest mobs"), "Quest hostiles"))
      -- NPCs: the nameplates setting first, alone on its row.
      local npcs = page(rec, "NPCs")
      local services = labelY(npcs, "Friendly NPCs")
      local plates = labelY(npcs, "Friendly NPC nameplates")
      local icons = labelY(npcs, "Show role icons (Beta)")
      assert.is_true(services > plates and plates > icons)
      local onRow = 0
      for _, l in ipairs(npcs.labels) do
        if l.points[1][5] == plates then
          onRow = onRow + 1
        end
      end
      assert.are.equal(1, onRow)
    end)

    it("draws one bordered frame per option group, without overlap on its page", function()
      local overrides, rec = widgetClient()
      load({ overrides = overrides })
      local total = 0
      for name, count in pairs({ ["Friendly players"] = 4, ["Quest mobs"] = 1, NPCs = 1 }) do
        local content = page(rec, name)
        local boxes = {}
        for _, c in ipairs(rec.created) do
          if c.kind == "Frame" and c.parent == content then
            boxes[#boxes + 1] = c.f
          end
        end
        assert.are.equal(count, #boxes, name)
        total = total + #boxes
        -- Created in a different order than they are laid out: from the top down.
        table.sort(boxes, function(a, b) return a.points[1][5] > b.points[1][5] end)
        for i, b in ipairs(boxes) do
          -- No SetBackdrop in the fake client: the four texture lines are the border.
          assert.are.equal(4, #b.textures)
          if i > 1 then
            local prev = boxes[i - 1]
            assert.is_true(prev.points[1][5] - prev.h > b.points[1][5])
          end
        end
        -- Each page's own Reset button sits below its last section.
        local last, reset = boxes[#boxes], resetButton(rec, name)
        assert.is_true(last.points[1][5] - last.h > reset.points[1][5], name)
      end
      assert.are.equal(6, total)
      assert.is_table(resetButton(rec, "Main"))
    end)

    it("uses SetBackdrop for the frame border when the client has it", function()
      local overrides, rec = widgetClient()
      local seen = {}
      local decorate = overrides.decorate
      overrides.decorate = function(f, kind, parent, template)
        if kind == "Frame" and parent ~= nil then
          f.SetBackdrop = function(_, t) seen[#seen + 1] = t end
          f.SetBackdropBorderColor = function() end
        end
        return decorate(f, kind, parent, template)
      end
      load({ overrides = overrides })
      assert.are.equal(6, #seen)
      assert.are.equal(1, seen[1].edgeSize)
      assert.is_not_nil(rec.created)
    end)

    it("lists options in the help and never errors without the Settings API", function()
      local overrides, rec = widgetClient({ noSettings = true })
      local env = load({ overrides = overrides })
      assert.is_nil(rec.frame)
      env.slash("options")
      assert.is_true(printedContains(env, "not available"))
      env.slash("on")
      assert.is_true(env.GroupChevronDB.enabled)
    end)

    it("does not error when opening the category is refused", function()
      local overrides = widgetClient({ openFails = true })
      local env = load({ overrides = overrides })
      env.slash("options")
      assert.is_true(printedContains(env, "could not open"))
      assert.is_false(printedContains(env, "error in"))
    end)

    it("reports a panel build failure once and keeps the slash commands", function()
      local overrides = widgetClient()
      overrides.Settings.RegisterAddOnCategory = function() error("boom") end
      local env = load({ overrides = overrides })
      assert.is_true(printedContains(env, "error in options panel"))
      env.slash("off")
      assert.is_false(env.GroupChevronDB.enabled)
    end)

    it("shares the setters between the commands and the panel", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local plate = newPlate("nameplate1", "name", BLUE)
      env.world.plates.nameplate1 = plate
      env.world.players.nameplate1, env.world.party.nameplate1 = true, true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      local enabledBox = widget(rec, "CheckButton", 1)
      local compactBox = widget(rec, "CheckButton", 2)

      -- Panel -> saved value and plates, at once.
      enabledBox.checked = false
      enabledBox.scripts.OnClick(enabledBox)
      assert.is_false(env.GroupChevronDB.enabled)
      assert.are.same(BLUE, plate.UnitFrame.name.color)
      enabledBox.checked = true
      enabledBox.scripts.OnClick(enabledBox)
      assert.are.equal("#FF4FD8", hex(plate.UnitFrame.name.color))
      compactBox.checked = false
      compactBox.scripts.OnClick(compactBox)
      assert.is_false(env.GroupChevronDB.compact)

      -- Command -> shown when the panel opens.
      env.slash("compact on")
      env.slash("off")
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_true(compactBox.checked)
      assert.is_false(enabledBox.checked)
    end)

    it("applies a slider on release, not on every drag step", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local slider = widget(rec, "Slider", 1)
      slider.scripts.OnMouseDown(slider)
      slider.scripts.OnValueChanged(slider, 1.5)
      slider.scripts.OnValueChanged(slider, 1.7000000001)
      assert.are.equal(1, env.GroupChevronDB.chevsize)
      slider.value = 1.7000000001
      slider.scripts.OnMouseUp(slider)
      assert.are.equal(1.7, env.GroupChevronDB.chevsize)
      -- Changed without dragging (mouse wheel): applied at once, on the other slider.
      local text = widget(rec, "Slider", 2)
      text.scripts.OnValueChanged(text, 2.25)
      assert.are.equal(2.25, env.GroupChevronDB.textsize)
      -- Values outside 1..3 are refused.
      text.scripts.OnValueChanged(text, 3.5)
      assert.are.equal(2.25, env.GroupChevronDB.textsize)
      -- The third slider is the others' text size, then bar, buffs, others' bar.
      local other = widget(rec, "Slider", 3)
      other.scripts.OnValueChanged(other, 1.5)
      assert.are.equal(1.5, env.GroupChevronDB.othersize)
      for i, key in ipairs({ "barsize", "buffsize", "otherbarsize" }) do
        local sl = widget(rec, "Slider", 3 + i)
        sl.scripts.OnValueChanged(sl, 2)
        assert.are.equal(2, env.GroupChevronDB[key])
      end
      -- Then the members' name gap and the friendlies' one: whole points, -10..40.
      local gap, otherGap = widget(rec, "Slider", 7), widget(rec, "Slider", 8)
      gap.scripts.OnValueChanged(gap, 3.6)
      assert.are.equal(4, env.GroupChevronDB.namegap)
      assert.are.equal(0, env.GroupChevronDB.othernamegap)
      otherGap.scripts.OnValueChanged(otherGap, -5)
      assert.are.equal(-5, env.GroupChevronDB.othernamegap)
      assert.are.equal(4, env.GroupChevronDB.namegap)
      gap.scripts.OnValueChanged(gap, 50)
      assert.are.equal(4, env.GroupChevronDB.namegap)
      gap.scripts.OnMouseDown(gap)
      gap.scripts.OnValueChanged(gap, 12)
      assert.are.equal(4, env.GroupChevronDB.namegap)
      gap.value = 12
      gap.scripts.OnMouseUp(gap)
      assert.are.equal(12, env.GroupChevronDB.namegap)
      -- Then the hostiles' chevron size (1..5), text size (1..3) and name gap (-10..40).
      local hostileChev, hostileText = widget(rec, "Slider", 12), widget(rec, "Slider", 13)
      local hostileGap = widget(rec, "Slider", 14)
      hostileChev.scripts.OnValueChanged(hostileChev, 4.5)
      assert.are.equal(4.5, env.GroupChevronDB.hostilechevsize)
      hostileChev.scripts.OnValueChanged(hostileChev, 5.5)
      assert.are.equal(4.5, env.GroupChevronDB.hostilechevsize)
      hostileText.scripts.OnValueChanged(hostileText, 2.5)
      assert.are.equal(2.5, env.GroupChevronDB.hostilesize)
      hostileText.scripts.OnValueChanged(hostileText, 3.5)
      assert.are.equal(2.5, env.GroupChevronDB.hostilesize)
      hostileGap.scripts.OnValueChanged(hostileGap, 7.4)
      assert.are.equal(7, env.GroupChevronDB.hostilenamegap)
      hostileGap.scripts.OnValueChanged(hostileGap, 41)
      assert.are.equal(7, env.GroupChevronDB.hostilenamegap)
      -- The last ones are the friendly NPCs' text size (1..3) and icon size (1..15).
      local npcText, iconSize = widget(rec, "Slider", 18), widget(rec, "Slider", 19)
      npcText.scripts.OnValueChanged(npcText, 2)
      assert.are.equal(2, env.GroupChevronDB.npcsize)
      npcText.scripts.OnValueChanged(npcText, 3.5)
      assert.are.equal(2, env.GroupChevronDB.npcsize)
      iconSize.scripts.OnValueChanged(iconSize, 12)
      assert.are.equal(12, env.GroupChevronDB.npciconsize)
      iconSize.scripts.OnValueChanged(iconSize, 15.5)
      assert.are.equal(12, env.GroupChevronDB.npciconsize)
      -- Then the friendly NPCs' name height (-10..40).
      local npcGap = widget(rec, "Slider", 20)
      npcGap.scripts.OnValueChanged(npcGap, 8)
      assert.are.equal(8, env.GroupChevronDB.npcnamegap)
      -- Then the friends' and guildmates' text sizes (1..3).
      local friendText, guildText = widget(rec, "Slider", 21), widget(rec, "Slider", 22)
      friendText.scripts.OnValueChanged(friendText, 2.5)
      assert.are.equal(2.5, env.GroupChevronDB.friendsize)
      guildText.scripts.OnValueChanged(guildText, 1.25)
      assert.are.equal(1.25, env.GroupChevronDB.guildsize)
      assert.is_nil(widget(rec, "Slider", 23))
      assert.are.equal(2.25, env.GroupChevronDB.textsize)

      -- The panel shows the saved gaps when it opens.
      env.slash("othernamegap 7")
      rec.frame.scripts.OnShow(rec.frame)
      assert.are.equal(12, gap.value)
      assert.are.equal(7, otherGap.value)
    end)

    it("applies the colour live and restores the old one on Cancel", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      env.slash("color #00ff00")
      local swatch = widget(rec, "Button", 1)
      swatch.scripts.OnClick(swatch)
      assert.is_false(rec.picker.hasOpacity)
      assert.are.equal("#00FF00", hex({ rec.picker.r, rec.picker.g, rec.picker.b }))
      rec.rgb = { 0, 0, 1 }
      rec.picker.swatchFunc()
      assert.are.equal("#0000FF", hex(env.GroupChevronDB.color))
      rec.picker.cancelFunc()
      assert.are.equal("#00FF00", hex(env.GroupChevronDB.color))
    end)

    it("resets each page with its own button, and /gchev reset only the colour", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      env.slash("color #00ff00")
      env.slash("chevsize 2")
      env.slash("textsize 3")
      env.slash("othersize 2")
      env.slash("barsize 2")
      env.slash("buffsize 2")
      env.slash("otherbarsize 2")
      env.slash("namegap 7")
      env.slash("othernamegap -2")
      env.slash("hostilecolor #00ff00")
      env.slash("hostilechevsize 2")
      env.slash("hostilesize 2")
      env.slash("hostilenamegap -2")
      env.slash("compact off")
      env.slash("off")
      env.slash("reset")
      assert.are.equal(7, env.GroupChevronDB.namegap)
      assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))
      assert.are.equal(2, env.GroupChevronDB.chevsize)
      assert.is_false(env.GroupChevronDB.compact)
      assert.is_false(env.GroupChevronDB.enabled)

      env.slash("color #00ff00")
      env.slash("font chat")
      -- Friendly players: only that page's settings.
      local button = resetButton(rec, "Friendly players")
      button.scripts.OnClick(button)
      local db = env.GroupChevronDB
      assert.are.equal(2, db.hostilechevsize)
      assert.are.equal("chat", db.font)
      assert.is_false(db.enabled)
      assert.is_true(db.compact)
      button = resetButton(rec, "Quest mobs")
      button.scripts.OnClick(button)
      button = resetButton(rec, "Main")
      button.scripts.OnClick(button)
      assert.are.equal("#FF4FD8", hex(db.color))
      assert.are.equal(3, db.chevsize)
      assert.are.equal(1.75, db.textsize)
      assert.are.equal(1.5, db.othersize)
      assert.are.equal(1, db.barsize)
      assert.are.equal(1.1, db.buffsize)
      assert.are.equal(1, db.otherbarsize)
      assert.are.equal(5, db.namegap)
      assert.are.equal(5, db.othernamegap)
      assert.are.equal("#FFFF00", hex(db.hostilecolor))
      assert.are.equal(3, db.hostilechevsize)
      assert.are.equal(1.5, db.hostilesize)
      assert.are.equal(5, db.hostilenamegap)
      assert.are.equal("outline", db.font)
      assert.is_true(db.classcolor)
      assert.is_true(db.enabled)
      assert.is_true(db.compact)
    end)

    it("has a Hostiles section with a colour swatch and shows the saved values when it opens", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local swatch = widget(rec, "Button", 5)
      swatch.scripts.OnClick(swatch)
      assert.are.equal("#FFFF00", hex({ rec.picker.r, rec.picker.g, rec.picker.b }))
      rec.rgb = { 0, 1, 0 }
      rec.picker.swatchFunc()
      assert.are.equal("#00FF00", hex(env.GroupChevronDB.hostilecolor))
      rec.picker.cancelFunc()
      assert.are.equal("#FFFF00", hex(env.GroupChevronDB.hostilecolor))
      -- The member colour is untouched, and the other swatches keep their order.
      assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))
      assert.are.equal("#3FA7FF", hex(env.GroupChevronDB.friendcolor))

      env.slash("hostilechevsize 4")
      env.slash("hostilesize 2")
      env.slash("hostilenamegap 9")
      rec.frame.scripts.OnShow(rec.frame)
      assert.are.equal(4, widget(rec, "Slider", 12).value)
      assert.are.equal(2, widget(rec, "Slider", 13).value)
      assert.are.equal(9, widget(rec, "Slider", 14).value)
    end)

    it("has a Friends section with a colour swatch and two checkboxes", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local swatch = widget(rec, "Button", 3)
      local chevronBox = widget(rec, "CheckButton", 3)
      local bnetBox = widget(rec, "CheckButton", 4)
      swatch.scripts.OnClick(swatch)
      assert.are.equal("#3FA7FF", hex({ rec.picker.r, rec.picker.g, rec.picker.b }))
      rec.rgb = { 0, 1, 0 }
      rec.picker.swatchFunc()
      assert.are.equal("#00FF00", hex(env.GroupChevronDB.friendcolor))
      rec.picker.cancelFunc()
      assert.are.equal("#3FA7FF", hex(env.GroupChevronDB.friendcolor))
      assert.are.equal("#FF4FD8", hex(env.GroupChevronDB.color))

      chevronBox.checked = false
      chevronBox.scripts.OnClick(chevronBox)
      assert.is_false(env.GroupChevronDB.friendchevron)
      bnetBox.checked = false
      bnetBox.scripts.OnClick(bnetBox)
      assert.is_false(env.GroupChevronDB.bnetfriends)
      env.slash("friendchevron on")
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_true(chevronBox.checked)
      assert.is_false(bnetBox.checked)

      -- Reset to defaults covers the friend settings too.
      env.slash("friendcolor #00ff00")
      env.slash("friendchevron off")
      local button = resetButton(rec, "Friendly players")
      button.scripts.OnClick(button)
      local db = env.GroupChevronDB
      assert.are.equal("#3FA7FF", hex(db.friendcolor))
      assert.is_true(db.friendchevron)
      assert.is_true(db.bnetfriends)
    end)

    it("has a Guildmates section after Friends, covered by Reset to defaults", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local swatch = widget(rec, "Button", 4)
      local chevronBox = widget(rec, "CheckButton", 5)
      swatch.scripts.OnClick(swatch)
      assert.are.equal("#40FF40", hex({ rec.picker.r, rec.picker.g, rec.picker.b }))
      rec.rgb = { 1, 0, 0 }
      rec.picker.swatchFunc()
      assert.are.equal("#FF0000", hex(env.GroupChevronDB.guildcolor))
      rec.picker.cancelFunc()
      assert.are.equal("#40FF40", hex(env.GroupChevronDB.guildcolor))
      chevronBox.checked = false
      chevronBox.scripts.OnClick(chevronBox)
      assert.is_false(env.GroupChevronDB.guildchevron)
      env.slash("guildchevron on")
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_true(chevronBox.checked)
      env.slash("guildcolor #ff0000")
      env.slash("guildchevron off")
      local button = resetButton(rec, "Friendly players")
      button.scripts.OnClick(button)
      assert.are.equal("#40FF40", hex(env.GroupChevronDB.guildcolor))
      assert.is_true(env.GroupChevronDB.guildchevron)
    end)

    it("has a Class colour checkbox in the Friendlies section, reset to on", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local classBox = widget(rec, "CheckButton", 6)
      assert.truthy(widget(rec, "CheckButton", 7)) -- the Show level checkbox, see below
      local plate = newTreePlate("nameplate2")
      env.world.plates.nameplate2 = plate
      env.world.players.nameplate2, env.world.friends.nameplate2 = true, true
      env.world.classes.nameplate2 = "MAGE"
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      assert.are.same(BLUE, plate.UnitFrame.name.color)

      classBox.checked = true
      classBox.scripts.OnClick(classBox)
      assert.is_true(env.GroupChevronDB.classcolor)
      assert.are.equal("#00FFFF", hex(plate.UnitFrame.name.color))
      env.slash("classcolor off")
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_false(classBox.checked)
      assert.are.same(BLUE, plate.UnitFrame.name.color)

      local button = resetButton(rec, "Friendly players")
      button.scripts.OnClick(button)
      assert.is_true(env.GroupChevronDB.classcolor)
      assert.is_true(classBox.checked)
      assert.are.equal("#00FFFF", hex(plate.UnitFrame.name.color))
    end)

    it("redraws the chevron previews with the outline thickness while its slider is dragged", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      rec.frame.scripts.OnShow(rec.frame)
      local owned = {}
      for _, c in ipairs(rec.created) do
        for _, t in ipairs(c.f.textures or {}) do
          if t.owner then
            owned[#owned + 1] = t
          end
        end
      end
      -- Members, friends and guildmates: two "V"s of eight copies each; hostiles: one "V".
      assert.are.equal(3 * 16 + 8, #owned)
      local hostile = {}
      for i = #owned - 7, #owned do
        hostile[#hostile + 1] = owned[i]
      end
      assert.is_true(hostile[1].shown)
      -- Thickness 2 at chevron size 1 (these specs): 0.1875 * 2 * 1 points to the right for the first copy.
      assert.is_true(math.abs(hostile[1].points[1][4] - 0.375) < 1e-9)
      local slider = widget(rec, "Slider", 15)
      slider.scripts.OnMouseDown(slider)
      slider.scripts.OnValueChanged(slider, 3)
      assert.is_true(math.abs(hostile[1].points[1][4] - 0.5625) < 1e-9)
      assert.are.equal(2, env.GroupChevronDB.hostileoutlinesize) -- not saved before the release
      -- The chevron size slider resizes the preview too (the square is 72 wide, the "V" 10 * size).
      assert.are.equal(10, hostile[1].w)
      local size = widget(rec, "Slider", 12)
      size.scripts.OnValueChanged(size, 5)
      assert.are.equal(50, hostile[1].w)
      assert.are.equal(25, hostile[1].owner.h)
      size.scripts.OnValueChanged(size, 1)
      assert.are.equal(10, hostile[1].w)
      slider.scripts.OnValueChanged(slider, 0)
      assert.is_false(hostile[1].shown)
      slider.scripts.OnValueChanged(slider, 4)
      assert.is_true(hostile[1].shown)
    end)

    it("has a Show level checkbox in the Friendlies section, reset by Reset to defaults", function()
      local overrides, rec = widgetClient()
      local env = load({ overrides = overrides })
      local levelBox = widget(rec, "CheckButton", 7)
      assert.is_nil(widget(rec, "CheckButton", 12))
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_true(levelBox.checked)
      levelBox.checked = false
      levelBox.scripts.OnClick(levelBox)
      assert.is_false(env.GroupChevronDB.showlevel)
      env.slash("level on")
      rec.frame.scripts.OnShow(rec.frame)
      assert.is_true(levelBox.checked)
      env.slash("level off")
      local button = resetButton(rec, "Friendly players")
      button.scripts.OnClick(button)
      assert.is_true(env.GroupChevronDB.showlevel)
      assert.is_true(levelBox.checked)
    end)

    it("chooses the font of our name labels with /gchev font and the options button", function()
      local OUTLINE, CHAT = { name = "outline" }, { name = "chat" }
      local overrides, rec = widgetClient()
      overrides.SystemFont_Outline, overrides.ChatFontNormal = OUTLINE, CHAT
      local env = load({ overrides = overrides })
      local plate = newPlate("nameplate1", "name", BLUE)
      env.world.plates.nameplate1 = plate
      env.world.players.nameplate1 = true
      env.world.party.nameplate1 = true
      env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      local label = env.label(plate)
      assert.are.equal("default", env.GroupChevronDB.font)
      assert.are.equal(NAMEPLATE_FONT, label.fontObject)

      env.slash("font outline")
      assert.are.equal("outline", env.GroupChevronDB.font)
      assert.are.equal(OUTLINE, label.fontObject)
      assert.are.equal(NAMEPLATE_FONT, plate.UnitFrame.name.fontObject) -- Blizzard's name untouched

      -- The options button cycles to the next font.
      rec.frame.scripts.OnShow(rec.frame)
      local button = widget(rec, "Button", 6)
      button.scripts.OnClick(button)
      assert.are.equal("chat", env.GroupChevronDB.font)
      assert.are.equal(CHAT, label.fontObject)

      -- A font whose global is missing falls back to Blizzard's font; invalid input changes nothing.
      env.slash("font large")
      assert.are.equal(NAMEPLATE_FONT, label.fontObject)
      env.slash("font nonsense")
      assert.are.equal("large", env.GroupChevronDB.font)

      local reset = resetButton(rec, "Main")
      reset.scripts.OnClick(reset)
      assert.are.equal("outline", env.GroupChevronDB.font)
      assert.are.equal(OUTLINE, label.fontObject)
    end)

    it("chooses the font in a drop-down listing every font", function()
      local Core = dofile("GroupChevron/Core.lua")
      local overrides, rec = widgetClient()
      local added, texts, init = {}, {}, nil
      overrides.UIDropDownMenu_Initialize = function(_, fn) init = fn end
      overrides.UIDropDownMenu_AddButton = function(info) added[#added + 1] = info end
      overrides.UIDropDownMenu_SetText = function(_, t) texts[#texts + 1] = t end
      local env = load({ overrides = overrides })
      rec.frame.scripts.OnShow(rec.frame)
      assert.are.equal(Core.FONTS[1].label, texts[#texts])
      -- No fallback font button (Buttons 1 to 5 are the swatches and Main's Reset; the other pages'
      -- Reset buttons come after).
      for _, c in ipairs(rec.created) do
        if c.kind == "Button" then
          assert.are_not.equal(Core.FONTS[1].label, c.f.text)
        end
      end

      init()
      assert.are.equal(#Core.FONTS, #added)
      for i, f in ipairs(Core.FONTS) do
        assert.are.equal(f.label, added[i].text)
      end
      assert.is_true(added[1].checked)

      added[3].func()
      assert.are.equal("chat", env.GroupChevronDB.font)
      assert.are.equal(Core.FONTS[3].label, texts[#texts])

      -- /gchev font and reset show up when the panel is shown again.
      env.slash("font outline")
      rec.frame.scripts.OnShow(rec.frame)
      assert.are.equal(Core.FONTS[2].label, texts[#texts])
      local reset = resetButton(rec, "Main")
      reset.scripts.OnClick(reset)
      rec.frame.scripts.OnShow(rec.frame)
      assert.are.equal(Core.FONTS[2].label, texts[#texts]) -- the default font is "outline"
    end)

    it("falls back to the cycling button when the drop-down fails", function()
      local overrides, rec = widgetClient()
      overrides.UIDropDownMenu_Initialize = function() error("boom") end
      overrides.UIDropDownMenu_AddButton = function() end
      overrides.UIDropDownMenu_SetText = function() end
      local env = load({ overrides = overrides })
      rec.frame.scripts.OnShow(rec.frame)
      local button = widget(rec, "Button", 6)
      button.scripts.OnClick(button)
      assert.are.equal("outline", env.GroupChevronDB.font)
    end)

    it("refuses invalid values without changing anything", function()
      local env = load()
      env.slash("compact maybe")
      env.slash("chevsize 9")
      env.slash("color #12")
      local db = env.GroupChevronDB
      assert.is_true(db.compact)
      assert.are.equal(1, db.chevsize)
      assert.are.equal("#FF4FD8", hex(db.color))
    end)
  end)
end)

-- A model of Blizzard's Mainline nameplate driver (Blizzard_NamePlates, 12.1.5 UI source):
-- plates tied to tokens, UnitFrames pooled apart from them (OnNamePlateAdded acquires and sets
-- the unit, OnNamePlateRemoved clears it and releases), ADDED / REMOVED dispatched to the
-- driver and to the addon in either order, plus target, roster, health, level, friend list and
-- settings changes. After every step (outside combat), every plate must show a name (Blizzard's
-- or ours) and an enemy's must be Blizzard's. With flaky, SetAlpha(1) on a name fails half the
-- time in combat (how 0.12.0 lost names for good); combat ends with PLAYER_REGEN_ENABLED.
local function run(seed, variant)
  math.randomseed(seed)
  local driverObj = { ReleaseUnitFrame = function() end, OnNamePlateAdded = function() end }
  local env = load({ overrides = variant.hooks and { NamePlateDriverFrame = driverObj } or {} })
  local w = env.world
  local N = 6
  local plates, active, pool, allUF = {}, {}, {}, {}
  local kinds = { "enemy", "enemyplayer", "stranger", "member", "friend", "guild" }
  w.inGuild = true
  for i = 1, N do
    local p = newPart("Frame", nil)
    plates["nameplate" .. i] = p
  end
  local log = {}
  local function L(s) log[#log + 1] = s end
  local function acquire()
    local uf = table.remove(pool)
    if not uf then
      uf = newTreePlate("x", variant.nested).UnitFrame
      uf.LevelFrame = newPart("Frame", uf)
      uf.id = #allUF + 1
      allUF[#allUF + 1] = uf
    end
    uf.pooled = false
    if variant.flaky and not uf.flakyWrapped then
      uf.flakyWrapped = true
      local set = uf.name.SetAlpha
      uf.name.SetAlpha = function(self, a)
        if a == 1 and w.combat and math.random() < 0.5 then
          error("blocked")
        end
        set(self, a)
      end
    end
    return uf
  end
  local function identity(token, kind)
    w.players[token] = kind ~= "enemy"
    w.friends[token] = kind == "stranger" or kind == "member" or kind == "friend" or kind == "guild"
    w.party[token] = kind == "member" or nil
    w.flist[token] = kind == "friend" or nil
    w.guild[token] = kind == "guild" or nil
    w.levels[token] = math.random(1, 60)
    w.classes[token] = ({ "MAGE", "PRIEST", "WARLOCK" })[math.random(3)]
    w.health[token] = math.random() < 0.5 and { 50, 100 } or nil
  end
  local function blizzColor(uf, token)
    if w.friends[token] then
      uf.name:SetTextColor(0, 0.5, 1, 1)
    else
      uf.name:SetTextColor(1, 0, 0, 1)
    end
  end
  local function blizzAdd(token)
    local plate = plates[token]
    local uf = acquire()
    plate.UnitFrame, uf.parent = uf, plate
    uf.unit = token
    plate.namePlateUnitToken = token
    uf.name.text = "Name of " .. token
    blizzColor(uf, token)
    if variant.updateOnSet then
      env.hooks.CompactUnitFrame_UpdateName(uf)
    end
    if variant.hooks then
      env.hooks.OnNamePlateAdded(driverObj, token)
    end
  end
  local function blizzRemove(token)
    local plate = plates[token]
    local uf = plate.UnitFrame
    uf.unit = nil
    uf.pooled = true
    pool[#pool + 1] = uf
    if variant.hooks then
      env.hooks.ReleaseUnitFrame(driverObj, plate)
    end
    plate.UnitFrame = nil
  end
  local function add(token)
    local kind = kinds[math.random(#kinds)]
    identity(token, kind)
    active[token] = kind
    w.plates[token] = plates[token]
    L("add " .. token .. " " .. kind)
    if math.random() < 0.5 then
      blizzAdd(token); env.fire("NAME_PLATE_UNIT_ADDED", token)
    else
      env.fire("NAME_PLATE_UNIT_ADDED", token); blizzAdd(token)
    end
  end
  local function remove(token)
    L("remove " .. token)
    if math.random() < 0.5 then
      blizzRemove(token); env.fire("NAME_PLATE_UNIT_REMOVED", token)
    else
      env.fire("NAME_PLATE_UNIT_REMOVED", token); blizzRemove(token)
    end
    w.plates[token] = nil
    active[token] = nil
    if w.target == token then
      w.target = nil
      env.fire("PLAYER_TARGET_CHANGED")
    end
  end
  local function randomActive()
    local list = {}
    for t in pairs(active) do list[#list + 1] = t end
    table.sort(list)
    return list[math.random(math.max(#list, 1))]
  end
  local function visibleName(uf)
    local bliz = uf.name.alpha ~= 0
    local label, holder
    for _, f in ipairs(env.frames) do
      if f.parent == uf and #f.labels > 0 then label, holder = f.labels[1], f end
    end
    local ours = holder and holder.shown and label.text and label.text ~= ""
      and (holder.alpha == nil or holder.alpha ~= 0)
    return bliz, ours
  end
  local function check(step)
    if w.combat then
      return nil
    end
    for token, kind in pairs(active) do
      local uf = plates[token].UnitFrame
      local bliz, ours = visibleName(uf)
      if not bliz and not ours then
        return string.format("step %d: %s (%s) uf#%d has no visible name", step, token, kind, uf.id)
      end
      if (kind == "enemy" or kind == "enemyplayer") and not bliz then
        return string.format("step %d: enemy %s uf#%d Blizzard name alpha 0", step, token, uf.id)
      end
    end
    for _, uf in ipairs(variant.hooks and pool or {}) do
      if uf.name.alpha == 0 then
        return string.format("step %d: pooled uf#%d name alpha 0", step, uf.id)
      end
    end
  end
  for step = 1, 300 do
    local r = math.random(100)
    local token = "nameplate" .. math.random(N)
    if r <= 30 then
      if active[token] then remove(token) else add(token) end
    elseif r <= 40 then
      w.target = math.random() < 0.3 and nil or randomActive()
      L("target " .. tostring(w.target))
      env.fire("PLAYER_TARGET_CHANGED")
    elseif r <= 50 then
      local t = randomActive()
      if t and w.players[t] and w.friends[t] then
        w.party[t] = not w.party[t] or nil
        active[t] = w.party[t] and "member" or (w.flist[t] and "friend" or (w.guild[t] and "guild" or "stranger"))
        L("roster " .. t)
        env.fire("GROUP_ROSTER_UPDATE")
      end
    elseif r <= 60 then
      local t = randomActive()
      if t then
        w.health[t] = math.random() < 0.5 and { 50, 100 } or nil
        L("health " .. t)
        env.fire("UNIT_HEALTH", t)
      end
    elseif r <= 72 then
      local t = randomActive()
      if t then
        L("updatename " .. t)
        blizzColor(plates[t].UnitFrame, t)
        env.hooks.CompactUnitFrame_UpdateName(plates[t].UnitFrame)
      end
    elseif r <= 77 then
      local t = randomActive()
      if t then
        w.levels[t] = math.random(1, 60)
        L("level " .. t)
        env.fire("UNIT_LEVEL", t)
      end
    elseif r <= 82 then
      local t = randomActive()
      if t and w.players[t] and w.friends[t] and not w.party[t] then
        w.flist[t] = not w.flist[t] or nil
        active[t] = w.flist[t] and "friend" or (w.guild[t] and "guild" or "stranger")
        L("flist " .. t)
        env.fire("FRIENDLIST_UPDATE")
      end
    elseif r <= 86 then
      L("timers"); env.runTimers()
    elseif r <= 90 then
      local cmd = ({ "compact on", "compact off", "classcolor on", "classcolor off", "level on", "level off",
        "off", "on", "barsize 2", "barsize 1", "othersize 2", "textsize 2" })[math.random(12)]
      L("slash " .. cmd)
      env.slash(cmd)
    elseif r <= 95 then
      local t = randomActive()
      if t then
        L("castbar show " .. t)
        local cb = plates[t].UnitFrame.castBar
        cb.alpha = cb.alpha -- Show() keeps the alpha; OnShow hooks run
        for _, h in ipairs(cb.hooks) do if h[1] == "OnShow" then h[2](cb) end end
      end
    elseif r <= 97 and variant.flaky then
      w.combat = not w.combat
      L(w.combat and "combat" or "combat end")
      if not w.combat then
        env.fire("PLAYER_REGEN_ENABLED")
      end
    else
      L("enteringworld"); env.fire("PLAYER_ENTERING_WORLD")
    end
    local err = check(step)
    if err then
      return err, log
    end
  end
  return nil
end


describe("GroupChevron nameplate pooling model", function()
  for _, flaky in ipairs({ false, true }) do
    for _, nested in ipairs({ false, true }) do
      it(string.format("never leaves a plate without a name (flaky %s, nested %s)", tostring(flaky),
        tostring(nested)), function()
        for _, updateOnSet in ipairs({ true, false }) do
          local variant = { hooks = true, updateOnSet = updateOnSet, nested = nested, flaky = flaky }
          for seed = 1, 15 do
            local err, log = run(seed, variant)
            if err then
              local tail = {}
              for i = math.max(1, #log - 12), #log do
                tail[#tail + 1] = log[i]
              end
              error(string.format("updateOnSet=%s seed=%d: %s\n    %s", tostring(updateOnSet), seed, err,
                table.concat(tail, "\n    ")))
            end
          end
        end
      end)
    end
  end
end)
