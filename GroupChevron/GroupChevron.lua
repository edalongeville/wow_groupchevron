-- GroupChevron: marks the members of your party or raid on their nameplate (WoW API side).
--
-- A group member's nameplate name is coloured (default #FF4FD8) and a discreet double
-- down-chevron sits just above it. Friends outside the group (character friends list, and
-- Battle.net friends' characters unless bnetfriends is off) get their name in the friend
-- colour (default #3FA7FF) and, unless friendchevron is off, the same chevron in that colour.
-- With compact on (default), other friendly players (friends included) who are not the
-- current target show only their name; everyone else's plate is left as Blizzard draws it.
-- With classcolor on (default on), the other friendly players (not members, not friends,
-- target or not, compact or not) get their name in their class colour, the client's own.
-- Unless showlevel is off, friendly players outside the group (friends included) get their
-- level after the name on compact plates while their health bar is hidden, "Name (19)"
-- ("Name (??)" when the client does not know it), drawn by our own name FontString. A shown
-- health bar (full plates, the target, a hurt compact plate) has Blizzard's level beside it, so
-- the suffix is left out there; when the bar's state cannot be told, the suffix stays.
-- A hostile (attackable) unit tied to one of the player's active quests (C_QuestLog.UnitIsRelatedToActiveQuest:
-- kill, item drop, ...) gets its name in the hostile colour (default #FFFF00) and a single "V"
-- chevron above it, in that colour; the rest of its plate is left as Blizzard draws it.
-- A hostile unit not tied to the player's quests but to an objective a party member still has
-- to do (read from the unit's tooltip data, C_TooltipInfo.GetUnit: the lines the mouseover
-- tooltip shows) gets the same look in the party quest colour (default #FFFFFF).
-- Friendly NPCs: with npcicons on (default), one with a role (flight master, innkeeper, banker,
-- auctioneer, stable master, trainer, repairer, vendor) gets the role's icon above its name; with
-- npccompact on (default) every friendly NPC's plate shows the name only; npcsize sizes their
-- name. The role comes from the windows the NPC opened for you (learned by creature ID, kept in
-- GroupChevronDB.npcroles) and, on enUS and frFR clients, from its subtitle ("<Gryphon Master>").
-- Friendly NPC plates are a game setting (/gchev npcplates on|off sets it; the addon never changes
-- it by itself).
--
-- Robustness rules (fully independent of any other addon):
--   * Every event handler, hook and slash command runs through SafeCall (pcall): an error
--     never reaches the UI; the first error of each handler is reported once in chat.
--   * Every WoW global is checked before use (the Forever client's API may differ), and
--     values the client marks as "secret" are never used.
--   * Nameplates are recycled: a plate that stops showing a group member loses its chevron,
--     and its name gets back the colour it had before we changed it; a plate that leaves
--     compact mode gets back every part we faded out.
--   * Forbidden plates (friendly plates in instances) are left alone without any message.
--   * Blizzard's name FontString is as wide as the health bar, so long (or enlarged) names end
--     in "...". On the plates this addon handles (members, friends, compact non-members, and
--     friendly players in the class colour) the name is
--     drawn by our own FontString, anchored on Blizzard's but free to grow, and Blizzard's is
--     faded out (alpha 0, restored when the plate is released). If the name text cannot be
--     read, Blizzard's name is left visible as before.

local addonName, ns = ...
local Core = ns.Core

local PREFIX = "|cffff4fd8GChev|r: "

-- Chevron geometry, in UI units at chevsize 1 (scaled by chevsize). Each "V" is the
-- anti-aliased white texture chevron.tga (64x32, coloured with SetVertexColor), V_WIDTH x
-- V_HEIGHT; the upper "V" is fully opaque, the lower one sits STEP below it at LOWER_ALPHA.
-- A texture scales smoothly, unlike the rotated solid rectangles used before 0.4.1, which
-- looked pixelated when enlarged. Those rectangles (ARM) remain the fallback when the
-- texture cannot be loaded.
local CHEVRON_TEXTURE = "Interface\\AddOns\\GroupChevron\\chevron.tga"
-- The rounded square behind the chevron previews of the options page (tinted grey).
local BACKDROP_TEXTURE = "Interface\\AddOns\\GroupChevron\\backdrop.tga"
-- The black outline: OUTLINE_DIRS black copies of each "V" (same texture), each moved by the thickness in
-- one of eight directions (the diagonals scaled to the same distance), drawn below the "V". The
-- thickness is OUTLINE_UNIT * the section's factor (memberoutlinesize, friendoutlinesize,
-- guildoutlinesize, hostileoutlinesize: 1 to 5, default 2) * the chevron size, so the outline
-- grows with the chevron. The fallback rectangles (texture not found) have no outline.
local OUTLINE_UNIT = 0.1875
local OUTLINE_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 0.7071, 0.7071 }, { -0.7071, 0.7071 }, { 0.7071, -0.7071 }, { -0.7071, -0.7071 },
}
local V_WIDTH = 10
local V_HEIGHT = 5
local STEP = 4
local LOWER_ALPHA = 0.5
local GAP = 2 -- between the top of the name and the bottom of the chevron
local SUBTITLE_GAP = 1 -- between the top of a friendly NPC's subtitle and the bottom of its name
local CHEVRON_WIDTH = V_WIDTH
local CHEVRON_HEIGHT = V_HEIGHT + STEP
-- The hostiles' chevron is a single "V" (the upper one of the double chevron, fully opaque), as
-- tall as one "V".
local SINGLE_HEIGHT = V_HEIGHT
-- The fallback rectangles' arm length, thickness and angle (one table: the main chunk is at Lua's
-- limit of 200 locals).
local ARM = { LENGTH = 6, THICKNESS = 1.5, ANGLE = 40 }

-- Fields of the nameplate's UnitFrame that may hold the name FontString, in order.
local NAME_FIELDS = { "name", "Name", "unitName" }

local db -- GroupChevronDB once ADDON_LOADED ran
local reportedErrors = {} -- where -> true, once per session
local noticeShown = {} -- message key -> true, once per session
local lastNameField -- the field name found on the last marked plate ("" = none found)

-- Every per-plate record below is keyed by the plate's UnitFrame, not by the nameplate frame.
-- Blizzard pools UnitFrames apart from the plates (NamePlateBaseMixin:AcquireUnitFrame on
-- NAME_PLATE_UNIT_ADDED, ReleaseUnitFrame on removal), so the UnitFrame a plate shows changes
-- every time it is reused, and what we changed (a faded name, faded parts, scales, our name
-- and chevron frames, created as its children) lives on the UnitFrame. Keyed by plate (up to
-- 0.6.1), a UnitFrame could come back from the pool under another plate, an enemy's say,
-- with Blizzard's name still faded: enemies without a name.

-- chevrons: UnitFrame -> chevron frame (its child, created once, lazily). singles is the same for
-- the hostiles' single chevron: a pooled UnitFrame may show either shape in turn, so each shape
-- has its own frame and the other one is hidden.
local chevrons = setmetatable({}, { __mode = "k" })
local singles = setmetatable({}, { __mode = "k" })
-- iconCaches.high: UnitFrame -> the service NPC role icon frame (its child, created once,
-- lazily); iconCaches.low: the same for the low copy of a compact NPC plate (see FollowBar).
-- One table for both: the main chunk is at Lua's limit of 200 locals.
local iconCaches = { high = setmetatable({}, { __mode = "k" }), low = setmetatable({}, { __mode = "k" }) }
-- marks: UnitFrame -> { fs = name FontString or nil, orig = Blizzard's { r, g, b, a } or nil,
-- applied = our last { r, g, b } } while its plate is marked.
local marks = setmetatable({}, { __mode = "k" })
-- labels: UnitFrame -> { frame, text = our FontString, name = Blizzard's name FontString our
-- name covers right now (faded; nil when none) } (frame created once, lazily, as its child).
local labels = setmetatable({}, { __mode = "k" })
-- nameFails: UnitFrame -> why ShowFullName last left Blizzard's name in place (Blizzard's size,
-- not textsize / othersize), nil once our own name was drawn; for /gchev debug and names.
local nameFails = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------------------
-- Helpers

local function Print(msg)
  if type(print) == "function" then
    print(PREFIX .. tostring(msg))
  end
end

local function NoticeOnce(key, msg)
  if not noticeShown[key] then
    noticeShown[key] = true
    Print(msg)
  end
end

-- SafeCall runs fn(...) under pcall, never re-raises, and reports the first error of each
-- `where` once per session.
local function SafeCall(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reportedErrors[where] then
    reportedErrors[where] = true
    pcall(Print, "error in " .. tostring(where) .. " (reported once): " .. tostring(err))
  end
end

-- Readable returns v, or nil if the client marks it as a secret value.
local function Readable(v)
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then
      return nil
    end
  end
  return v
end

-- Try calls fn(...) if it is a function and returns its first result if readable, else nil.
local function Try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, v = pcall(fn, ...)
  if not ok then
    return nil
  end
  return Readable(v)
end

-- Field returns t[k] if it can be read (a forbidden frame raises on any access) and is not
-- secret, else nil.
local function Field(t, k)
  if type(t) ~= "table" then
    return nil
  end
  local ok, v = pcall(function() return t[k] end)
  if not ok then
    return nil
  end
  return Readable(v)
end

local function Pack(ok, ...)
  if not ok then
    return nil
  end
  local out = { n = select("#", ...) }
  for i = 1, out.n do
    out[i] = Readable((select(i, ...)))
  end
  return out
end

-- Results returns obj:method(...)'s results as { n = count, ... } (secret values replaced by
-- nil), or nil when the method is missing or raises an error (e.g. a forbidden frame).
local function Results(obj, method, ...)
  local fn = Field(obj, method)
  if type(fn) ~= "function" then
    return nil
  end
  return Pack(pcall(fn, obj, ...))
end

-- Method calls obj:method(...) safely and returns its first readable result, or nil.
local function Method(obj, method, ...)
  local out = Results(obj, method, ...)
  return out and out[1]
end

-- Friends: C_FriendList.IsFriend(guid) (character friends list) and
-- C_BattleNet.GetAccountInfoByGUID(guid) (Battle.net friends), unverified on the Forever client;
-- missing (nil) when the client does not have them, so every plate counts as "not a friend".
local unitAPI = {
  UnitIsPlayer = UnitIsPlayer,
  UnitInParty = UnitInParty,
  UnitInRaid = UnitInRaid,
  UnitIsUnit = UnitIsUnit,
  UnitIsFriend = UnitIsFriend,
  -- Hostiles: UnitCanAttack("player", unit), then C_QuestLog.UnitIsRelatedToActiveQuest(unit)
  -- (a boolean, documented for the Forever client 1.60.1); missing = no hostile is ever marked.
  UnitCanAttack = UnitCanAttack,
  IsRelatedToActiveQuest = Field(C_QuestLog, "UnitIsRelatedToActiveQuest"),
  -- Party members' quests: the unit's tooltip data (GetTooltipUnit, below with the service NPCs)
  -- and its line types (Enum.TooltipDataLineType: QuestTitle, QuestPlayer, QuestObjective), read
  -- only in a group (IsInGroup); unverified on the Forever client, missing = no party quest
  -- hostile is marked.
  TooltipLineTypes = Field(Enum, "TooltipDataLineType"),
  -- Kill or loot (the quest hostiles' icons): the type of the objectives the unit's tooltip lists,
  -- from the quest log; missing = the single chevron, as before.
  GetQuestObjectives = Field(C_QuestLog, "GetQuestObjectives"),
  -- /gchev debug's quest log summary (Core.QuestLogSummary).
  GetNumQuestLogEntries = Field(C_QuestLog, "GetNumQuestLogEntries"),
  GetQuestLogInfo = Field(C_QuestLog, "GetInfo"),
  IsInGroup = IsInGroup,
  UnitName = UnitName,
  UnitGUID = UnitGUID,
  UnitHealth = UnitHealth,
  UnitHealthMax = UnitHealthMax,
  -- Secret-safe health (compact plates' health bar): UnitHealthPercent(unit, false, curve) with a
  -- C_CurveUtil colour curve; checked in game on the Forever client, missing = the
  -- UnitHealth / UnitHealthMax fallback.
  UnitHealthPercent = UnitHealthPercent,
  CreateColorCurve = Field(C_CurveUtil, "CreateColorCurve"),
  CreateColor = CreateColor,
  UnitLevel = UnitLevel,
  IsFriend = Field(C_FriendList, "IsFriend"),
  GetAccountInfoByGUID = Field(C_BattleNet, "GetAccountInfoByGUID"),
  -- Guild: IsInGuild, UnitIsInMyGuild(unit), else IsPlayerInGuildFromGUID(guid) (global or
  -- C_PlayerInfo); unverified on the Forever client, missing = nobody is a guildmate.
  IsInGuild = IsInGuild,
  UnitIsInMyGuild = UnitIsInMyGuild,
  IsPlayerInGuildFromGUID = IsPlayerInGuildFromGUID or Field(C_PlayerInfo, "IsPlayerInGuildFromGUID"),
  -- Class colours (classcolor): UnitClass's token, then C_ClassColor.GetClassColor(token), else
  -- RAID_CLASS_COLORS[token]; unverified on the Forever client, missing = no class colour.
  UnitClass = UnitClass,
  GetClassColor = Field(C_ClassColor, "GetClassColor"),
  RAID_CLASS_COLORS = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS or nil,
  -- Service NPCs: C_TooltipInfo.GetUnit(unit) (the subtitle is its second line) and GetLocale
  -- (which subtitle words apply); unverified on the Forever client, missing = only the roles
  -- learned from the windows NPCs open count.
  GetTooltipUnit = Field(C_TooltipInfo, "GetUnit"),
  GetLocale = GetLocale,
  -- Friendly NPCs' name colour (green friendly, yellow neutral); unverified on the Forever client,
  -- missing = Core.DEFAULT_NPC_COLOR.
  UnitSelectionColor = UnitSelectionColor,
  -- Players' guild line: GetGuildInfo(unit)'s guild name; missing = no guild line.
  GetGuildInfo = GetGuildInfo,
  issecretvalue = issecretvalue,
}

local function IsMember(unit)
  return Core.IsGroupMember(unitAPI, unit)
end

local function Enabled()
  return type(db) == "table" and db.enabled == true
end

local function Color()
  if type(db) == "table" and Core.ValidColor(db.color) then
    return db.color[1], db.color[2], db.color[3]
  end
  local c = Core.DEFAULT_COLOR
  return c[1], c[2], c[3]
end

-- FriendColor returns the friend colour (friends outside the group).
local function FriendColor()
  if type(db) == "table" and Core.ValidColor(db.friendcolor) then
    return db.friendcolor[1], db.friendcolor[2], db.friendcolor[3]
  end
  local c = Core.DEFAULT_FRIEND_COLOR
  return c[1], c[2], c[3]
end

-- GuildColor returns the guild colour (guildmates outside the group).
local function GuildColor()
  if type(db) == "table" and Core.ValidColor(db.guildcolor) then
    return db.guildcolor[1], db.guildcolor[2], db.guildcolor[3]
  end
  local c = Core.DEFAULT_GUILD_COLOR
  return c[1], c[2], c[3]
end

-- HostileColor returns the hostile colour (hostile units tied to a quest).
local function HostileColor()
  if type(db) == "table" and Core.ValidColor(db.hostilecolor) then
    return db.hostilecolor[1], db.hostilecolor[2], db.hostilecolor[3]
  end
  local c = Core.DEFAULT_HOSTILE_COLOR
  return c[1], c[2], c[3]
end

-- PartyQuest holds the helpers of the hostile units tied to a party member's quest (one table, not
-- top-level locals: the main chunk is close to Lua 5.1's limit of 200 locals). Color returns
-- their colour.
local PartyQuest = {}
function PartyQuest.Color()
  if type(db) == "table" and Core.ValidColor(db.partyquestcolor) then
    return db.partyquestcolor[1], db.partyquestcolor[2], db.partyquestcolor[3]
  end
  local c = Core.DEFAULT_PARTYQUEST_COLOR
  return c[1], c[2], c[3]
end

-- FLAG_DEFAULTS are the saved on/off settings (besides enabled and compact) and their default.
local FLAG_DEFAULTS = {
  friendchevron = true, bnetfriends = true, guildchevron = true, classcolor = Core.DEFAULT_CLASSCOLOR, showlevel = true,
  npcicons = true, npccompact = true,
}

-- Flag returns a saved boolean setting of FLAG_DEFAULTS (its default when missing or invalid).
local function Flag(key)
  if type(db) == "table" and type(db[key]) == "boolean" then
    return db[key]
  end
  return FLAG_DEFAULTS[key] == true
end

-- Factor returns a saved size factor (Core.DefaultFactor when missing or invalid): "chevsize"; for group
-- members "textsize", "barsize" (health bar), "buffsize" (auras); for other friendly players
-- (compact or not, the target included, see Core.OtherSizes) "othersize" (name) and
-- "otherbarsize" (health bar, shown while hurt when compact); for the hostiles tied to a quest
-- "hostilechevsize" (their single chevron) and "hostilesize" (name); for the hostiles tied to a
-- party member's quest "partyquestchevsize" and "partyquestsize".
local function Factor(key)
  if type(db) == "table" and Core.ValidFactor(db[key], key) then
    return db[key]
  end
  return Core.DefaultFactor(key)
end

-- Gap returns a saved name gap (Core.DefaultGap when missing or invalid, see Core.ValidGap):
-- "namegap" for group members, "othernamegap" for other friendly players (wherever othersize applies),
-- "hostilenamegap" for the hostiles tied to a quest, "partyquestnamegap" for those tied to a party
-- member's quest.
local function Gap(key)
  if type(db) == "table" and Core.ValidGap(db[key]) then
    return db[key]
  end
  return Core.DefaultGap(key)
end

-- ChosenFontObject returns the client's font object the player chose for our own name labels
-- (db.font), or nil for "default" and when the global is missing or not a table (the caller
-- then keeps Blizzard's name font).
local function ChosenFontObject()
  local f = type(db) == "table" and Core.FindFont(db.font)
  if not f or not f.object then
    return nil
  end
  local obj = _G[f.object]
  if type(obj) ~= "table" then
    return nil
  end
  return obj
end

-- baseFonts: name FontString ->{ path, size, flags } as Blizzard had set it, cached the first
-- time we read it (plates are recycled, so it is weak-keyed). Only used for our own name when
-- Blizzard's has no font object. Blizzard's name is never given a font with SetFont: that
-- would replace its font object, whose alphabet fallbacks draw Cyrillic, Korean and Chinese
-- names (0.4.0 did, so those names showed as boxes, even on recycled plates).
local baseFonts = setmetatable({}, { __mode = "k" })

-- BaseFont returns { path, size, flags } of the name as Blizzard set it (cached the first
-- time), or nil when it cannot be read.
local function BaseFont(fs)
  if type(fs) ~= "table" or type(fs.GetFont) ~= "function" then
    return nil
  end
  local base = baseFonts[fs]
  if not base then
    local ok, path, size, flags = pcall(fs.GetFont, fs)
    path, size, flags = Readable(path), Readable(size), Readable(flags)
    if not ok or type(path) ~= "string" or type(size) ~= "number" then
      return nil
    end
    base = { path, size, flags }
    baseFonts[fs] = base
  end
  return base
end

local function IsNameplateUnit(unit)
  return type(unit) == "string" and unit:sub(1, 9) == "nameplate"
end

local function PlateForUnit(unit)
  if type(C_NamePlate) ~= "table" then
    return nil
  end
  return Try(C_NamePlate.GetNamePlateForUnit, unit)
end

-- UnitFrameOf returns plate.UnitFrame, or nil (also for a forbidden plate, silently).
local function UnitFrameOf(plate)
  local uf = Field(plate, "UnitFrame")
  if type(uf) == "table" then
    return uf
  end
  return nil
end

-- PlateUnit returns the unit token ("nameplateN") a plate shows, or nil.
local function PlateUnit(plate)
  if type(plate) ~= "table" then
    return nil
  end
  local candidates = { Field(plate, "namePlateUnitToken"), Field(plate, "unitToken") }
  candidates[#candidates + 1] = Method(plate, "GetUnit")
  local uf = UnitFrameOf(plate)
  if uf then
    candidates[#candidates + 1] = Field(uf, "unit")
  end
  for i = 1, 4 do
    if IsNameplateUnit(candidates[i]) then
      return candidates[i]
    end
  end
  return nil
end

-- FindName returns the name FontString of a nameplate's UnitFrame and its field name.
local function FindName(uf)
  for _, field in ipairs(NAME_FIELDS) do
    local fs = Field(uf, field)
    if type(fs) == "table" and type(Field(fs, "SetTextColor")) == "function" then
      return fs, field
    end
  end
  return nil, nil
end

-- ---------------------------------------------------------------------------------------
-- Chevron

-- LayoutArm sizes and places one arm of a "V" (fallback drawing) for the size factor f.
local function LayoutArm(frame, tex, f)
  local a = math.rad(ARM.ANGLE)
  local length = ARM.LENGTH * f
  tex:SetSize(length, ARM.THICKNESS * f)
  tex:ClearAllPoints()
  local cx = tex.side * (length / 2) * math.cos(a)
  local cy = tex.baseY * f + (length / 2) * math.sin(a)
  tex:SetPoint("CENTER", frame, "BOTTOM", cx, cy)
  if type(tex.SetRotation) == "function" then
    tex:SetRotation(tex.side * a)
  end
end

-- LayoutChevron (re)sizes the whole chevron for the saved size factor sizeKind (chevsize, friendchevsize,
-- guildchevsize or hostilechevsize) and outline thickness; a no-op when unchanged.
-- The GAP above the name is not scaled (it is the frame's anchor offset).
local function LayoutChevron(frame, thickness, sizeKind)
  local f = Factor(sizeKind or (frame.single and "hostilechevsize" or "chevsize"))
  if frame.factor == f and frame.thickness == thickness then
    return
  end
  frame.factor, frame.thickness = f, thickness
  frame:SetSize(CHEVRON_WIDTH * f, (frame.single and SINGLE_HEIGHT or CHEVRON_HEIGHT) * f)
  for _, tex in ipairs(frame.vs) do
    tex:SetSize(V_WIDTH * f, V_HEIGHT * f)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOM", frame, "BOTTOM", 0, tex.baseY * f)
  end
  local offset = OUTLINE_UNIT * (thickness or Core.DEFAULT_FACTOR) * f
  for _, outline in ipairs(frame.outlines) do
    outline:SetSize(V_WIDTH * f, V_HEIGHT * f)
    outline:ClearAllPoints()
    outline:SetPoint("CENTER", outline.owner, "CENTER", outline.dx * offset, outline.dy * offset)
  end
  for _, tex in ipairs(frame.arms) do
    LayoutArm(frame, tex, f)
  end
end

-- AddV adds one textured "V" whose bottom is baseY above the frame's bottom. It returns false
-- (and adds nothing) when the client cannot load the texture.
local function AddV(frame, baseY, alpha)
  local tex = frame:CreateTexture(nil, "OVERLAY")
  local ok, loaded = pcall(tex.SetTexture, tex, CHEVRON_TEXTURE)
  if not ok or loaded == false then
    Method(tex, "Hide")
    return false
  end
  -- Free positioning and bilinear filtering: smooth at every size.
  Method(tex, "SetSnapToPixelGrid", false)
  Method(tex, "SetTexelSnappingBias", 0)
  tex.baseY, tex.baseAlpha = baseY, alpha
  tex:SetAlpha(alpha)
  frame.vs[#frame.vs + 1] = tex
  return true
end

-- AddOutlines adds, below each "V" of the frame, its black copies (same alpha), hidden until
-- SetOutline. If the texture cannot be loaded there is no outline (the "V"s have already said so).
local function AddOutlines(frame)
  for _, tex in ipairs(frame.vs) do
    for _, dir in ipairs(OUTLINE_DIRS) do
      local outline = frame:CreateTexture(nil, "ARTWORK")
      outline:SetTexture(CHEVRON_TEXTURE)
      Method(outline, "SetSnapToPixelGrid", false)
      Method(outline, "SetTexelSnappingBias", 0)
      outline.owner, outline.dx, outline.dy = tex, dir[1], dir[2]
      outline:SetVertexColor(0, 0, 0, 1)
      outline:SetAlpha(tex.baseAlpha)
      outline:Hide()
      frame.outlines[#frame.outlines + 1] = outline
    end
  end
end

-- SetOutline shows or hides the black outline of a chevron frame.
local function SetOutline(frame, on)
  for _, outline in ipairs(frame.outlines) do
    if on then
      outline:Show()
    else
      outline:Hide()
    end
  end
end

-- AddArm adds one arm of a "V" (fallback drawing) whose bottom point is baseY pixels above the
-- frame's bottom centre. side is -1 (left arm) or 1 (right arm).
local function AddArm(frame, side, baseY, alpha)
  local tex = frame:CreateTexture(nil, "OVERLAY")
  tex.side, tex.baseY = side, baseY
  tex:SetAlpha(alpha)
  frame.arms[#frame.arms + 1] = tex
end

local function ColorChevron(frame, r, g, b)
  for _, tex in ipairs(frame.vs) do
    tex:SetVertexColor(r, g, b, 1)
  end
  for _, tex in ipairs(frame.arms) do
    tex:SetColorTexture(r, g, b, 1)
  end
end

-- GetChevron returns the plate's chevron frame, creating it on first use: the double chevron
-- of members, friends and guildmates, or with single the hostiles' single "V". It is a child of
-- the plate's UnitFrame, so it fades and hides with the plate.
local function GetChevron(plate, uf, single)
  local cache = single and singles or chevrons
  local frame = cache[plate]
  if frame then
    return frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  frame = CreateFrame("Frame", nil, uf)
  frame.vs, frame.arms, frame.outlines = {}, {}, {}
  frame.single = single and true or false
  local drawn
  if single then
    drawn = AddV(frame, 0, 1)
  else
    drawn = AddV(frame, STEP, 1) and AddV(frame, 0, LOWER_ALPHA)
  end
  if drawn then
    AddOutlines(frame)
  else
    frame.vs = {}
    NoticeOnce("notexture", "chevron texture not found (restart the game after an update): drawing a simpler chevron")
    local bottom = ARM.THICKNESS / 2
    if single then
      AddArm(frame, -1, bottom, 1)
      AddArm(frame, 1, bottom, 1)
    else
      AddArm(frame, -1, bottom + STEP, 1)
      AddArm(frame, 1, bottom + STEP, 1)
      AddArm(frame, -1, bottom, LOWER_ALPHA)
      AddArm(frame, 1, bottom, LOWER_ALPHA)
    end
  end
  LayoutChevron(frame)
  frame:Hide()
  cache[plate] = frame
  return frame
end

-- HideChevrons hides the plate's chevrons, except keep (the one a style shows, or nil).
local function HideChevrons(plate, keep)
  for _, cache in ipairs({ chevrons, singles }) do
    local frame = cache[plate]
    if frame and frame ~= keep then
      frame:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------------------
-- Quest hostiles' icons: a sword ("kill it") and / or a sack ("loot a quest item from it"), each
-- above a small chevron, in place of the single chevron (one table: the main chunk is at Lua's
-- limit of 200 locals). Each icon is a white texture (tools/quest_icons_tga.py, 32 x 64) tinted
-- with the hostile colour, ICON_W x ICON_H UI units at hostilechevsize 1, with the chevron's
-- black outline (OUTLINE_DIRS copies moved by OUTLINE_UNIT x hostileoutlinesize x the size) and,
-- for the sack, its tie in black on top. Both: side by side, kill first, SPACING apart. A frame
-- per plate (frames), a child of its UnitFrame like the chevron.
local QuestMarks = {
  frames = setmetatable({}, { __mode = "k" }),
  KINDS = { "kill", "loot" },
  TEXTURES = {
    kill = "Interface\\AddOns\\GroupChevron\\quest_kill.tga",
    loot = "Interface\\AddOns\\GroupChevron\\quest_loot.tga",
  },
  DETAILS = { loot = "Interface\\AddOns\\GroupChevron\\quest_loot_detail.tga" },
  ICON_W = 4.5,
  ICON_H = 9,
  SPACING = 0.5,
}

-- QuestMarks.Texture puts path on a new texture of frame (layer, sublevel) and returns it, or nil
-- when the client cannot load it. Free positioning and bilinear filtering, like the chevron's.
function QuestMarks.Texture(frame, path, layer, sublevel)
  local tex = frame:CreateTexture(nil, layer, nil, sublevel)
  local ok, loaded = pcall(tex.SetTexture, tex, path)
  if not ok or loaded == false then
    Method(tex, "Hide")
    return nil
  end
  Method(tex, "SetSnapToPixelGrid", false)
  Method(tex, "SetTexelSnappingBias", 0)
  return tex
end

-- QuestMarks.AddIcon builds one icon of frame: { tex, outlines, detail } (nil: texture missing).
function QuestMarks.AddIcon(frame, kind)
  local tex = QuestMarks.Texture(frame, QuestMarks.TEXTURES[kind], "OVERLAY", 0)
  if not tex then
    return nil
  end
  local icon = { tex = tex, outlines = {} }
  for _, dir in ipairs(OUTLINE_DIRS) do
    local outline = QuestMarks.Texture(frame, QuestMarks.TEXTURES[kind], "ARTWORK", 0)
    if outline then
      outline:SetVertexColor(0, 0, 0, 1)
      outline.dx, outline.dy = dir[1], dir[2]
      outline:Hide()
      icon.outlines[#icon.outlines + 1] = outline
    end
  end
  if QuestMarks.DETAILS[kind] then
    icon.detail = QuestMarks.Texture(frame, QuestMarks.DETAILS[kind], "OVERLAY", 1)
    if icon.detail then
      icon.detail:SetVertexColor(0, 0, 0, 1)
    end
  end
  return icon
end

-- QuestMarks.Get returns the plate's icon frame, created on first use (nil without CreateFrame).
function QuestMarks.Get(plate, uf)
  local frame = QuestMarks.frames[plate]
  if frame then
    return frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  frame = CreateFrame("Frame", nil, uf)
  frame.icons = {}
  for _, kind in ipairs(QuestMarks.KINDS) do
    frame.icons[kind] = QuestMarks.AddIcon(frame, kind)
  end
  if not (frame.icons.kill and frame.icons.loot) then
    NoticeOnce("noquesticon", "quest icon textures not found (restart the game after an update): "
      .. "the single chevron is shown instead")
  end
  frame:Hide()
  QuestMarks.frames[plate] = frame
  return frame
end

-- QuestMarks.Place lays out the icons of the kinds which gives a colour to (which: { kill =
-- { r, g, b } or nil, loot = ... }), each in its colour, side by side in a fixed order (kill
-- first, at the left), at size factor f with the outline thickness factor thickness (0: none);
-- icons is { kill = icon, loot = icon } as AddIcon builds them. The first icon's bottom left
-- corner goes on anchorTo's anchorPoint at x, y. It returns the width used (0: nothing shown).
function QuestMarks.Place(icons, which, f, thickness, anchorTo, anchorPoint, x, y)
  local w, h = QuestMarks.ICON_W * f, QuestMarks.ICON_H * f
  local offset = OUTLINE_UNIT * thickness * f
  local left = 0
  for _, kind in ipairs(QuestMarks.KINDS) do
    local icon = icons[kind]
    local color = which[kind]
    local shown = icon ~= nil and type(color) == "table"
    if icon then
      local parts = { icon.tex, icon.detail }
      for _, outline in ipairs(icon.outlines) do
        parts[#parts + 1] = outline
      end
      for _, part in ipairs(parts) do
        if shown then
          part:SetSize(w, h)
          part:ClearAllPoints()
        else
          part:Hide()
        end
      end
    end
    if shown then
      icon.tex:SetPoint("BOTTOMLEFT", anchorTo, anchorPoint, (x or 0) + left, y or 0)
      icon.tex:SetVertexColor(color[1], color[2], color[3], 1)
      icon.tex:Show()
      if icon.detail then
        icon.detail:SetPoint("CENTER", icon.tex, "CENTER", 0, 0)
        icon.detail:Show()
      end
      for _, outline in ipairs(icon.outlines) do
        outline:SetPoint("CENTER", icon.tex, "CENTER", outline.dx * offset, outline.dy * offset)
        if thickness > 0 then
          outline:Show()
        else
          outline:Hide()
        end
      end
      left = left + w + QuestMarks.SPACING * f
    end
  end
  return left > 0 and left - QuestMarks.SPACING * f or 0
end

-- QuestMarks.Colors returns the colour of each icon a quest hostile shows ({ kill = { r, g, b }
-- or nil, loot = ... }), or nil for the single chevron. The player's own objectives come first, in
-- the hostile colour; a kind only a party member still has to do gets the party quest colour (a
-- kill objective of the player's and a loot one of a party member's: a yellow sword and a white
-- sack). party: the unit is tied to a party member's quest only (mode partyquest): its kinds, in
-- the party quest colour. Without a kind of the player's own on a unit of the player's quests, the
-- single chevron stays (the player's quest wins, even unknown).
function QuestMarks.Colors(party, info)
  if type(info) ~= "table" then
    return nil
  end
  local mine = { HostileColor() }
  local theirs = { PartyQuest.Color() }
  local out = {}
  if party then
    out.kill = info.partyKill == true and theirs or nil
    out.loot = info.partyLoot == true and theirs or nil
  elseif info.questKill == true or info.questLoot == true then
    out.kill = (info.questKill == true and mine) or (info.partyKill == true and theirs) or nil
    out.loot = (info.questLoot == true and mine) or (info.partyLoot == true and theirs) or nil
  end
  if not out.kill and not out.loot then
    return nil
  end
  return out
end

-- QuestMarks.Show shows the quest icons of style (style.quest: { kill = colour, loot = colour },
-- see HostileStyle) on the plate, GAP above anchor (else above uf), at the style's chevron size
-- and outline. It
-- returns the frame, or nil (and hides it) when no icon can be shown: the caller then draws the
-- single chevron.
function QuestMarks.Show(plate, uf, anchor, style)
  local frame = QuestMarks.Get(plate, uf)
  if not frame then
    return nil
  end
  local f = Factor(style.chevsize)
  local width = QuestMarks.Place(frame.icons, style.quest, f, style.outlinesize or 0, frame, "BOTTOMLEFT", 0, 0)
  if width <= 0 then
    frame:Hide()
    return nil
  end
  frame:SetSize(width, QuestMarks.ICON_H * f)
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", anchor or uf, "TOP", 0, GAP)
  frame:Show()
  return frame
end

-- QuestMarks.Hide hides the plate's quest icons.
function QuestMarks.Hide(plate)
  local frame = QuestMarks.frames[plate]
  if frame then
    frame:Hide()
  end
end

-- ---------------------------------------------------------------------------------------
-- Service NPC role icon: one texture in its own frame, a child of the plate's UnitFrame (it fades
-- and hides with the plate), ICON_SIZE x ICON_SIZE UI units at npciconsize 1.

local ICON_SIZE = 6

-- GetIcon returns the plate's role icon frame, creating it on first use (nil without CreateFrame).
local function GetIcon(plate, uf, cache)
  cache = cache or iconCaches.high
  local frame = cache[plate]
  if frame then
    return frame
  end
  if type(CreateFrame) ~= "function" then
    return nil
  end
  frame = CreateFrame("Frame", nil, uf)
  frame.tex = frame:CreateTexture(nil, "OVERLAY")
  Method(frame.tex, "SetAllPoints", frame)
  frame:Hide()
  cache[plate] = frame
  return frame
end

-- IconName returns the icon of role: the player's choice (db.roleicons), else Core.RoleIcon.
local function IconName(role)
  local chosen = type(db) == "table" and type(db.roleicons) == "table" and db.roleicons[role]
  if Core.ValidIconName(chosen) then
    return chosen
  end
  return Core.RoleIcon(role)
end

-- AtlasKnown returns true or false when the client says whether it has the atlas name
-- (C_Texture.GetAtlasInfo), or nil when it cannot tell.
local function AtlasKnown(name)
  local get = Field(C_Texture, "GetAtlasInfo")
  if type(get) ~= "function" then
    return nil
  end
  local ok, info = pcall(get, name)
  if not ok then
    return nil
  end
  return Readable(info) ~= nil
end

-- SetIconTexture puts the icon name (a texture path or an atlas name) on tex. It returns false
-- when the client cannot load it (an unknown atlas, a texture that does not load).
local function SetIconTexture(tex, name)
  if Core.IsTexturePath(name) then
    local ok, loaded = pcall(tex.SetTexture, tex, name)
    if not ok or loaded == false then
      return false
    end
    local crop = Core.IconCrop(name)
    Method(tex, "SetTexCoord", crop[1], crop[2], crop[3], crop[4])
    return true
  end
  if AtlasKnown(name) == false or type(Field(tex, "SetAtlas")) ~= "function" then
    return false
  end
  local ok, loaded = pcall(tex.SetAtlas, tex, name)
  return ok and loaded ~= false
end

-- ShowIcon shows role's icon on the plate, its bottom GAP above anchor (else above uf), at alpha 1.
-- It returns false (and hides the icon) when the role has no icon or the client cannot load its
-- texture. cache is iconCaches.high (default) or iconCaches.low.
local function ShowIcon(plate, uf, anchor, role, cache)
  local path = IconName(role)
  local frame = path and GetIcon(plate, uf, cache)
  if not frame then
    return false
  end
  if frame.path ~= path then
    if not SetIconTexture(frame.tex, path) then
      frame.path = nil
      frame:Hide()
      NoticeOnce("noicon:" .. path, "friendly NPC icon not found (" .. path .. "): no icon is shown; "
        .. "/gchev icon " .. tostring(role) .. " <texture or atlas> picks another one")
      return false
    end
    frame.path = path
  end
  local size = ICON_SIZE * Factor("npciconsize")
  frame:SetSize(size, size)
  -- The opacity (npciconalpha) goes on the texture: the frame's own alpha picks the copy of the name
  -- shown (FollowBar), and the two multiply.
  Method(frame.tex, "SetAlpha", Factor("npciconalpha"))
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", anchor or uf, "TOP", 0, GAP)
  frame.role = role
  Method(frame, "SetAlpha", 1)
  frame:Show()
  return true
end

-- HideIcon hides the plate's role icon; with lowOnly, only the low copy's.
local function HideIcon(plate, lowOnly)
  for _, cache in ipairs(lowOnly and { iconCaches.low } or { iconCaches.high, iconCaches.low }) do
    local frame = cache[plate]
    if frame then
      frame.role = nil
      frame:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------------------
-- Full name: our own FontString over Blizzard's, so the name is never cut to the bar width.

-- Blizzard's name FontString lives on a pooled UnitFrame, so a name we faded travels to the
-- next unit (an enemy, say) unless it is given back. Up to 0.12.0 the alpha to give back was
-- read with GetAlpha when the name was faded, and the record of the fade was dropped whatever
-- the SetAlpha that gave it back did (Method swallows errors). A name that was ever faded
-- without being given back (one silent failure, or any path we never saw) was then read as
-- "originally 0" the next time and given back as 0: the name stayed invisible for good, even
-- on a plate refreshed as the target (enemies without a name, a third time).
-- Since 0.12.1:
--   * Blizzard's nameplate code never sets the name's alpha (Blizzard_NamePlates and
--     CompactUnitFrame, 12.1.5 UI source: only Show/Hide, SetText and colours), so a name
--     we do not cover is always given alpha 1, never a value read back;
--   * fadedNames remembers every name we faded until a SetAlpha(1) is known to have worked;
--   * every refresh of a plate ends with SyncName, which gives Blizzard's name alpha 1 unless
--     our own name covers it right now, whatever the records say (see Refresh).

-- fadedNames: Blizzard's name FontString -> true while we may have left it at alpha 0.
local fadedNames = setmetatable({}, { __mode = "k" })
local restoreFailures = 0 -- names whose SetAlpha(1) failed (retried later), for /gchev

-- FadeName fades Blizzard's name out under ours.
local function FadeName(fs)
  fadedNames[fs] = true
  Method(fs, "SetAlpha", 0)
end

-- RestoreName gives Blizzard's name alpha 1. It returns true when that is known to have
-- worked (the call did not fail, and the alpha reads 1 when it can be read); otherwise the name
-- stays in fadedNames, to be retried by the next SyncName or RefreshAll.
local function RestoreName(fs)
  if not Results(fs, "SetAlpha", 1) then
    restoreFailures = restoreFailures + 1
    NoticeOnce("restorefail", "could not give a nameplate name back (retried on the next refresh)")
    return false
  end
  local a = Method(fs, "GetAlpha")
  if type(a) == "number" and a < 0.99 then
    restoreFailures = restoreFailures + 1
    NoticeOnce("restorefail", "could not give a nameplate name back (retried on the next refresh)")
    return false
  end
  fadedNames[fs] = nil
  return true
end

-- HideFullName hides our name on the plate and gives Blizzard's its alpha back.
local function HideFullName(plate)
  local rec = labels[plate]
  if not rec then
    return
  end
  Method(rec.frame, "Hide")
  if rec.name then
    local fs = rec.name
    rec.name = nil
    RestoreName(fs)
  end
end

-- Covered returns true when our own name covers fs on the UnitFrame uf right now (then
-- Blizzard's name is meant to be faded).
local function Covered(uf, fs)
  local rec = labels[uf]
  return rec ~= nil and rec.name == fs
end

-- SyncName makes Blizzard's name on uf visible unless our own name covers it. It reads no
-- record of what was there before: alpha 1 is the only value Blizzard ever uses.
local function SyncName(uf)
  local fs = FindName(uf)
  if not fs or Covered(uf, fs) then
    return
  end
  local a = Method(fs, "GetAlpha")
  if fadedNames[fs] or (type(a) == "number" and a < 0.99) then
    RestoreName(fs)
  end
end

-- NameText returns the name text of fs, or nil when it cannot be read (or is secret).
local function NameText(fs)
  local text = Method(fs, "GetText")
  if type(text) ~= "string" or text == "" then
    return nil
  end
  return text
end

-- ShowFullName draws fs's text with our own FontString, in fs's font object (so the same
-- alphabets) scaled by size (its frame's scale), in r, g, b, anchored on fs's bottom centre
-- and free to grow both ways, lifted by lift + gap (Core.NameOffset), and fades fs out. With a
-- level (Core.UnitLevel; compact plates only), the text is "<name> (<level>)"
-- (Core.NameWithLevel); FollowBar may then drop the suffix while the health bar is shown, with
-- a second FontString (rec.short, the name alone, created only for a level) drawn over the same
-- spot. Here the suffix is always shown (rec.short at alpha 0). Blizzard's text itself is never
-- changed. With low (a region: the health bar of a compact friendly NPC plate), a second copy of
-- the name and subtitle (rec.lowtext, rec.lowsub) is drawn with its bottom on low's bottom
-- (+ lift + gap), where the faded health bar is, at alpha 0: FollowBar then shows one copy
-- or the other. It returns our FontString (the chevron's anchor) and the low copy's name (nil
-- without low), or nil when the name stays Blizzard's (text or font unreadable, no CreateFrame,
-- or fs not shown).
local function ShowFullName(plate, uf, fs, size, r, g, b, lift, gap, level, subtitle, low)
  local plain = NameText(fs)
  local text = plain
  if text and level then
    text = Core.NameWithLevel(text, level)
  end
  local fontObject = ChosenFontObject() or Method(fs, "GetFontObject")
  if type(fontObject) ~= "table" then
    fontObject = nil
  end
  local base = not fontObject and BaseFont(fs)
  local fail
  if not text then
    fail = "name text unreadable (secret or empty)"
  elseif not (fontObject or base) then
    fail = "name font unreadable"
  elseif type(CreateFrame) ~= "function" then
    fail = "no CreateFrame"
  elseif Method(fs, "IsShown") == false then
    fail = "Blizzard's name hidden"
  end
  nameFails[plate] = fail
  if fail then
    HideFullName(plate)
    return nil
  end
  local rec = labels[plate]
  if not rec then
    local frame = CreateFrame("Frame", nil, uf)
    Method(frame, "SetAllPoints", uf)
    local label = frame:CreateFontString(nil, "OVERLAY")
    Method(label, "SetWordWrap", false)
    Method(label, "SetJustifyH", "CENTER")
    rec = { frame = frame, text = label }
    labels[plate] = rec
  end
  if rec.name and rec.name ~= fs then
    HideFullName(plate) -- the plate's name FontString changed: give the old one back
  end
  if text ~= plain and not rec.short then
    local short = rec.frame:CreateFontString(nil, "OVERLAY")
    Method(short, "SetWordWrap", false)
    Method(short, "SetJustifyH", "CENTER")
    rec.short = short
  end
  -- textsize scales the frame, not the font: the font object (and its fallbacks) stays whole.
  Method(rec.frame, "SetScale", size)
  local offset = Results(fs, "GetShadowOffset")
  local sc = Results(fs, "GetShadowColor")
  for _, label in ipairs({ rec.text, rec.short }) do
    if fontObject then
      label:SetFontObject(fontObject)
    else
      label:SetFont(base[1], base[2], base[3])
    end
    -- Same shadow as Blizzard's name (the outline comes with the font flags).
    if offset and type(offset[1]) == "number" and type(offset[2]) == "number" then
      Method(label, "SetShadowOffset", offset[1], offset[2])
      if sc and type(sc[1]) == "number" and type(sc[2]) == "number" and type(sc[3]) == "number" then
        Method(label, "SetShadowColor", sc[1], sc[2], sc[3], type(sc[4]) == "number" and sc[4] or 1)
      end
    end
    label:SetTextColor(r, g, b, 1)
    label:ClearAllPoints()
    -- lift (buffs) and gap (namegap / othernamegap) are in the parent's units; our frame is
    -- scaled by size.
    label:SetPoint("BOTTOM", fs, "BOTTOM", 0, Core.NameOffset(lift, gap, size))
  end
  local label = rec.text
  label:SetText(text)
  Method(label, "SetAlpha", 1)
  if rec.short then
    rec.short:SetText(plain)
    Method(rec.short, "SetAlpha", 0)
  end
  -- FollowBar's texts: the name with the level (nil without a level) and the name alone.
  rec.full, rec.plain = text ~= plain and text or nil, plain
  -- A second line below the name (a friendly NPC's "<subtitle>", a player's "<guild>"), where
  -- Blizzard's name was, with our name moved on top of it; nil: none, the name where it was.
  if subtitle then
    if not rec.sub then
      rec.sub = rec.frame:CreateFontString(nil, "OVERLAY")
      Method(rec.sub, "SetWordWrap", false)
      Method(rec.sub, "SetJustifyH", "CENTER")
    end
    local sub = rec.sub
    if fontObject then
      sub:SetFontObject(fontObject)
    else
      sub:SetFont(base[1], base[2], base[3])
    end
    sub:SetTextColor(r, g, b, 1)
    sub:SetText(subtitle)
    sub:ClearAllPoints()
    sub:SetPoint("BOTTOM", fs, "BOTTOM", 0, Core.NameOffset(lift, gap, size))
    for _, l in ipairs({ rec.text, rec.short }) do
      l:ClearAllPoints()
      l:SetPoint("BOTTOM", sub, "TOP", 0, SUBTITLE_GAP)
    end
    Method(sub, "SetAlpha", 1)
    sub:Show()
  elseif rec.sub then
    rec.sub:Hide()
  end
  -- The low copy (compact friendly NPCs): same font, shadow, colour and text, at the bar's place.
  local lowLabel
  if low then
    local function dress(l)
      if fontObject then
        l:SetFontObject(fontObject)
      else
        l:SetFont(base[1], base[2], base[3])
      end
      if offset and type(offset[1]) == "number" and type(offset[2]) == "number" then
        Method(l, "SetShadowOffset", offset[1], offset[2])
        if sc and type(sc[1]) == "number" and type(sc[2]) == "number" and type(sc[3]) == "number" then
          Method(l, "SetShadowColor", sc[1], sc[2], sc[3], type(sc[4]) == "number" and sc[4] or 1)
        end
      end
      l:SetTextColor(r, g, b, 1)
      l:ClearAllPoints()
      Method(l, "SetAlpha", 0)
    end
    for _, key in ipairs({ "lowtext", "lowsub" }) do
      if not rec[key] then
        rec[key] = rec.frame:CreateFontString(nil, "OVERLAY")
        Method(rec[key], "SetWordWrap", false)
        Method(rec[key], "SetJustifyH", "CENTER")
      end
    end
    lowLabel = rec.lowtext
    dress(lowLabel)
    lowLabel:SetText(text)
    local y = Core.NameOffset(lift, gap, size)
    if subtitle then
      local lowsub = rec.lowsub
      dress(lowsub)
      lowsub:SetText(subtitle)
      lowsub:SetPoint("BOTTOM", low, "BOTTOM", 0, y)
      lowLabel:SetPoint("BOTTOM", lowsub, "TOP", 0, SUBTITLE_GAP)
      lowsub:Show()
    else
      lowLabel:SetPoint("BOTTOM", low, "BOTTOM", 0, y)
      rec.lowsub:Hide()
    end
    lowLabel:Show()
    rec.low = true
  else
    rec.low = nil
    for _, key in ipairs({ "lowtext", "lowsub" }) do
      if rec[key] then
        Method(rec[key], "SetAlpha", 0)
        rec[key]:Hide()
      end
    end
  end
  rec.name = fs
  FadeName(fs)
  rec.frame:Show()
  return label, lowLabel
end

-- ---------------------------------------------------------------------------------------
-- Bar and buff sizes: SetScale on Blizzard's health bar container and aura frame, the original
-- scale recorded per plate and given back when the plate leaves the mode that scaled it.

-- scaled: plate -> { [part] = its scale before we changed it }.
local scaled = setmetatable({}, { __mode = "k" })

-- BarPart returns the plate's health bar part to scale (HealthBarsContainer, else healthBar).
local function BarPart(uf)
  local part = Field(uf, "HealthBarsContainer")
  if type(part) ~= "table" then
    part = Field(uf, "healthBar")
  end
  return type(part) == "table" and part or nil
end

-- AuraPart returns the plate's aura (buff/debuff) frame, or nil.
local function AuraPart(uf)
  local part = Field(uf, "AurasFrame")
  return type(part) == "table" and part or nil
end

-- ScalePart sets part's scale to its original scale x f (no-op without SetScale).
local function ScalePart(plate, part, f)
  if not part or type(Field(part, "SetScale")) ~= "function" then
    return
  end
  local rec = scaled[plate]
  if not rec then
    rec = {}
    scaled[plate] = rec
  end
  if rec[part] == nil then
    local orig = Method(part, "GetScale")
    rec[part] = (type(orig) == "number" and orig > 0) and orig or 1
  end
  Method(part, "SetScale", rec[part] * f)
end

-- The health bar is stretched by Blizzard between the top corners of the cast bar container,
-- so SetScale alone only made it taller. Nameplate regions cannot be measured (GetPoint,
-- GetWidth: "Can't measure restricted regions"), so the bar is laid out again from what
-- Blizzard's own layout uses (NamePlateUnitFrameMixin: BOTTOMLEFT / BOTTOMRIGHT on
-- CastBarsContainer's TOPLEFT / TOPRIGHT, y = NamePlateSetupOptions.castBarToHealthBarSpacing)
-- and the content width it computes (nameplate width minus both insets). When any of it is
-- missing, the bar is only scaled, as in 0.6.0.

-- bars: plate -> { part, scale, moved }: the bar's scale before ours, and whether we laid it out
-- (then its Blizzard layout is set back by RestoreBar).
local bars = setmetatable({}, { __mode = "k" })

-- BlizzardNumber returns a number Blizzard keeps in a global table (t[key]), or nil.
local function BlizzardNumber(t, key)
  local v = Field(t, key)
  return type(v) == "number" and v or nil
end

-- ContentWidth returns the width of the plate's content (cast bar and health bar) as Blizzard
-- computes it, or nil.
local function ContentWidth()
  local driver = _G.NamePlateDriverFrame
  local consts, opts = _G.NamePlateConstants, _G.NamePlateSetupOptions
  local cvar = Field(consts, "STYLE_CVAR")
  if type(driver) ~= "table" or type(cvar) ~= "string" then
    return nil
  end
  local style
  if type(C_CVar) == "table" then
    style = tonumber(Try(C_CVar.GetCVar, cvar))
  end
  local scale = Method(driver, "GetNamePlateScale", style)
  local width = Method(driver, "GetNamePlateWidth", style, scale)
  local inset = BlizzardNumber(opts, "insetWidth")
  if type(width) ~= "number" or not inset then
    return nil
  end
  return width - 2 * inset
end

-- LayBar anchors bar on uf's cast bar container like Blizzard does, widened for factor f with
-- the bar's own scale being scale x f. It returns false (nothing changed) when Blizzard's
-- layout cannot be known.
local function LayBar(uf, bar, scale, f)
  local cast = Field(uf, "CastBarsContainer")
  local spacing = BlizzardNumber(_G.NamePlateSetupOptions, "castBarToHealthBarSpacing")
  if type(cast) ~= "table" or not spacing then
    return false
  end
  local left, right, y = Core.BarOffsets(ContentWidth(), spacing, scale, f)
  if not left then
    return false
  end
  Method(bar, "ClearAllPoints")
  Method(bar, "SetPoint", "BOTTOMLEFT", cast, "TOPLEFT", left, y)
  Method(bar, "SetPoint", "BOTTOMRIGHT", cast, "TOPRIGHT", right, y)
  return true
end

-- RestoreBar gives the plate's health bar its original scale and, if we moved it, Blizzard's
-- layout back.
local function RestoreBar(plate)
  local rec = bars[plate]
  if not rec then
    return
  end
  bars[plate] = nil
  Method(rec.part, "SetScale", rec.scale)
  if rec.moved and not LayBar(rec.uf, rec.part, rec.scale, 1) then
    NoticeOnce("barlayout", "could not give a health bar Blizzard's layout back: /reload fixes it")
  end
end

-- ScaleBar makes the plate's health bar part f times Blizzard's size (no-op without SetScale).
local function ScaleBar(plate, uf, part, f)
  if not part or type(Field(part, "SetScale")) ~= "function" then
    return
  end
  local rec = bars[plate]
  if rec and rec.part ~= part then
    RestoreBar(plate)
    rec = nil
  end
  if not rec then
    local orig = Method(part, "GetScale")
    rec = { part = part, uf = uf, scale = (type(orig) == "number" and orig > 0) and orig or 1 }
    bars[plate] = rec
  end
  Method(part, "SetScale", rec.scale * f)
  -- Only the HealthBarsContainer is laid out by Blizzard as above.
  if part == Field(uf, "HealthBarsContainer") and (f ~= 1 or rec.moved) then
    if LayBar(uf, part, rec.scale, f) then
      rec.moved = true
    else
      NoticeOnce("barwidth", "nameplate layout not found: health bar size changes the height only")
    end
  end
end

-- RestoreScales gives every part we scaled on the plate its original scale (and the health
-- bar its anchors) back.
local function RestoreScales(plate)
  RestoreBar(plate)
  local rec = scaled[plate]
  if not rec then
    return
  end
  scaled[plate] = nil
  for part, orig in pairs(rec) do
    Method(part, "SetScale", orig)
  end
end

-- BuffLift returns how far up the name of a member's plate goes so the buffs, scaled by
-- buffsize about their middle on the left of the bar, never reach it (Core.BuffLift, from
-- Blizzard's NamePlateConstants.AURA_ITEM_HEIGHT and the aura frame's auraItemScale; 0 when
-- they are unknown or buffsize is 1).
local function BuffLift(plate, uf)
  local aura = AuraPart(uf)
  local height = BlizzardNumber(_G.NamePlateConstants, "AURA_ITEM_HEIGHT")
  if not aura or not height then
    return 0
  end
  local base = scaled[plate] and scaled[plate][aura] or Method(aura, "GetScale")
  return Core.BuffLift(height, BlizzardNumber(aura, "auraItemScale") or 1, type(base) == "number" and base or 1,
    Factor("buffsize"))
end

-- ---------------------------------------------------------------------------------------
-- Marking

local function ApplyColor(fs, r, g, b)
  fs:SetTextColor(r, g, b)
  if type(fs.SetVertexColor) == "function" then
    fs:SetVertexColor(r, g, b)
  end
end

local function SameColor(r1, g1, b1, r2, g2, b2)
  local function near(x, y)
    return type(x) == "number" and type(y) == "number" and math.abs(x - y) < 0.01
  end
  return near(r1, r2) and near(g1, g2) and near(b1, b2)
end

-- ReadColor returns the FontString's current colour as { r, g, b, a }, or nil.
local function ReadColor(fs)
  if type(fs.GetTextColor) ~= "function" then
    return nil
  end
  local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
  r, g, b, a = Readable(r), Readable(g), Readable(b), Readable(a)
  if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    return nil
  end
  return { r, g, b, type(a) == "number" and a or 1 }
end

-- Styles of a marked plate (see Mark):
--   kind    : "member", "friend" / "class" (full plate) or "friendcompact" / "classcompact"
--             (with compact mode), "quest" (a hostile unit tied to a quest);
--   r, g, b : the name and chevron colour;
--   chevron : whether the chevron is shown (single: the hostiles' single "V", not the double one);
--   outlinesize : the thickness of the chevron's black outline (memberoutlinesize, friendoutlinesize,
--             guildoutlinesize, hostileoutlinesize; 0 = none);
--   size    : the scale of our name frame;
--   scales  : whether the member sizes (barsize, buffsize, and the name lift) apply;
--   bar     : the health bar scale (otherbarsize) of another friendly player's full plate, or nil
--             (members use barsize; compact plates are scaled by Compact);
--   level   : the level shown after the name (friendly non-members on compact plates only, see
--             Level and FollowBar), or nil;
--   gap     : the name's gap above Blizzard's name position (namegap for members, othernamegap
--             for everyone else), added to the buff lift.
-- A friend's full plate is Blizzard's default plate plus the colour and the chevron: its name
-- uses othersize and its health bar otherbarsize (the member sizes never apply). A compact
-- friend's name and health bar use them too (set by Compact). The class colour (classcolor)
-- gives other friendly players the same look as a friend, without the chevron.

-- OtherFactor is the size of another friendly player's plate: othersize / otherbarsize, compact
-- or full, compact on or off, target or not (Core.OtherSizes), so the name keeps its size when
-- the player is targeted or untargeted.
local function OtherFactor(key)
  return Factor(key)
end

local function MemberStyle()
  local r, g, b = Color()
  return {
    kind = "member", r = r, g = g, b = b, chevron = true, size = Factor("textsize"), scales = true,
    gap = Gap("namegap"), outlinesize = Factor("memberoutlinesize"), chevsize = "chevsize",
  }
end

local function FriendStyle(compact, level)
  local r, g, b = FriendColor()
  return {
    kind = compact and "friendcompact" or "friend",
    r = r, g = g, b = b,
    chevron = Flag("friendchevron"),
    outlinesize = Factor("friendoutlinesize"), chevsize = "friendchevsize",
    size = Factor("friendsize"),
    bar = not compact and OtherFactor("otherbarsize") or nil,
    scales = false,
    level = level,
    gap = Gap("othernamegap"),
  }
end

-- A guildmate is styled like a friend, in the guild colour (guildchevron).
local function GuildStyle(compact, level)
  local r, g, b = GuildColor()
  return {
    kind = compact and "guildcompact" or "guild",
    r = r, g = g, b = b,
    chevron = Flag("guildchevron"), outlinesize = Factor("guildoutlinesize"), chevsize = "guildchevsize",
    size = Factor("guildsize"),
    bar = not compact and OtherFactor("otherbarsize") or nil,
    scales = false,
    level = level,
    gap = Gap("othernamegap"),
  }
end

-- ClassStyle is the look of a friendly player's name in the class colour c ({ r, g, b }):
-- like a friend's, without the chevron.
local function ClassStyle(c, compact, level)
  return {
    kind = compact and "classcompact" or "class",
    r = c[1], g = c[2], b = c[3],
    chevron = false,
    size = OtherFactor("othersize"),
    bar = not compact and OtherFactor("otherbarsize") or nil,
    scales = false,
    level = level,
    gap = Gap("othernamegap"),
  }
end

-- HostileStyle is the look of a hostile unit tied to a quest: its full plate as Blizzard draws it,
-- with our name in the hostile colour at hostilesize and hostilenamegap and a single chevron
-- (hostilechevsize) in the same colour. With party (a unit tied to a party member's quest): the
-- same look in the party quest colour at partyquestsize, partyquestnamegap and partyquestchevsize.
-- info (Core.UnitInfo) says what is left to do to the unit (QuestMarks.Colors): the chevron gives
-- way to the kill and / or loot icons (QuestMarks) at the same size and outline; neither known (an
-- object or event objective, an unreadable tooltip, combat): the single chevron, as before.
local function HostileStyle(party, info)
  local prefix = party and "partyquest" or "hostile"
  local r, g, b
  if party then
    r, g, b = PartyQuest.Color()
  else
    r, g, b = HostileColor()
  end
  return {
    kind = party and "partyquest" or "quest", r = r, g = g, b = b, chevron = true, single = true,
    size = Factor(prefix .. "size"), scales = false, gap = Gap(prefix .. "namegap"),
    outlinesize = Factor(prefix .. "outlinesize"), chevsize = prefix .. "chevsize",
    quest = QuestMarks.Colors(party, info),
  }
end

-- NpcStyle is the look of a friendly NPC: "<name> (<level>)" in the colour c ({ r, g, b }: the
-- game's reaction colour, Core.ReactionColor), at npcsize and npcnamegap, the level always shown
-- (keeplevel; level nil: not readable, the name alone), its subtitle on a line below the name, in
-- angle brackets like the game's own ("<Maître des gryphons>"; nil: none), and, when it has a role
-- (nil: none), the role's icon above the name (npciconsize).
local function NpcStyle(role, compact, level, subtitle, c)
  return {
    kind = compact and "npccompact" or "npc", r = c[1], g = c[2], b = c[3], chevron = false, icon = role,
    size = Factor("npcsize"), scales = false, gap = Gap("npcnamegap"), level = level, keeplevel = true,
    subtitle = subtitle and ("<" .. subtitle .. ">") or nil, low = compact,
  }
end

-- RelationStyle returns the style of a friend or guildmate plate.
local function RelationStyle(relation, compact, level)
  if relation == "guild" then
    return GuildStyle(compact, level)
  end
  return FriendStyle(compact, level)
end

-- Mark colours the plate's name and shows the chevron in style (see above). marks[plate]
-- remembers Blizzard's colour across style changes (member <-> friend), so leaving every
-- marked mode gives Blizzard's colour back, never one of ours; on a style change the sizes of
-- the previous style are given back first.
local function Mark(plate, uf, style)
  local fs, field = FindName(uf)
  lastNameField = field or ""
  local m = marks[plate]
  if m and m.kind ~= style.kind then
    RestoreScales(plate)
  end
  if not m or m.fs ~= fs then
    m = { fs = fs }
    marks[plate] = m
  end
  m.kind = style.kind
  local r, g, b = style.r, style.g, style.b
  if fs and style.keepcolor then
    -- The name keeps Blizzard's colour (service NPCs): a colour we applied for an earlier style is
    -- given back first, and our own name is drawn in Blizzard's colour.
    local cur = ReadColor(fs)
    local mine = m.applied and cur and SameColor(cur[1], cur[2], cur[3], m.applied[1], m.applied[2], m.applied[3])
    if mine and m.orig then
      ApplyColor(fs, m.orig[1], m.orig[2], m.orig[3])
      cur = m.orig
    end
    m.applied = nil
    if cur then
      r, g, b = cur[1], cur[2], cur[3]
    end
  elseif fs then
    -- The colour to restore later is Blizzard's: a colour that is still the one we applied
    -- last is ours, not Blizzard's.
    local cur = ReadColor(fs)
    local mine = m.applied and cur and SameColor(cur[1], cur[2], cur[3], m.applied[1], m.applied[2], m.applied[3])
    if cur and not mine then
      m.orig = cur
    end
    m.applied = { r, g, b }
    ApplyColor(fs, r, g, b)
  elseif style.chevron or style.icon then
    NoticeOnce("noname", "name text not found on the nameplate (tried UnitFrame.name, .Name, .unitName): "
      .. "only the chevron is shown")
  end
  local anchor, lowAnchor = fs, nil
  if fs and type(r) == "number" then
    local lift = style.scales and BuffLift(plate, uf) or 0
    -- Compact friendly NPCs: a second copy of the name where the faded health bar is (FollowBar).
    local low = style.low and BarPart(uf) or nil
    local shown
    shown, lowAnchor = ShowFullName(plate, uf, fs, style.size, r, g, b, lift, style.gap, style.level,
      style.subtitle, low)
    anchor = shown or fs
  elseif fs then
    -- Blizzard's colour cannot be read: Blizzard's name stays as it is.
    HideFullName(plate)
  end
  local rec = labels[plate]
  if rec then
    rec.keepLevel = style.keeplevel and true or nil
  end
  -- A quest hostile's kill / loot icons replace its chevron (QuestMarks.Show: nil when they
  -- cannot be shown, then the chevron is drawn).
  local questMarks = style.quest and QuestMarks.Show(plate, uf, anchor, style) or nil
  if not questMarks then
    QuestMarks.Hide(plate)
  end
  local chevron = not questMarks and style.chevron and GetChevron(plate, uf, style.single) or nil
  if chevron then
    chevron:ClearAllPoints()
    if anchor then
      chevron:SetPoint("BOTTOM", anchor, "TOP", 0, GAP)
    else
      chevron:SetPoint("BOTTOM", uf, "TOP", 0, GAP)
    end
    LayoutChevron(chevron, style.outlinesize, style.chevsize)
    ColorChevron(chevron, r, g, b)
    SetOutline(chevron, (style.outlinesize or 0) > 0)
    chevron:Show()
  end
  -- A pooled UnitFrame may carry the other shape from its previous plate.
  HideChevrons(plate, chevron)
  -- The service NPCs' role icon, above the name like a chevron (never both).
  if not (style.icon and ShowIcon(plate, uf, anchor, style.icon)) then
    HideIcon(plate)
  elseif lowAnchor and ShowIcon(plate, uf, lowAnchor, style.icon, iconCaches.low) then
    Method(iconCaches.low[plate], "SetAlpha", 0) -- FollowBar shows it
  else
    HideIcon(plate, true)
  end
  if style.scales then
    ScaleBar(plate, uf, BarPart(uf), Factor("barsize"))
    ScalePart(plate, AuraPart(uf), Factor("buffsize"))
  elseif style.bar then
    -- Another friendly player's full plate: only the health bar (otherbarsize); compact plates
    -- are scaled by Compact.
    ScaleBar(plate, uf, BarPart(uf), style.bar)
  end
end

-- Unmark hides the plate's chevron. With restore, a name we coloured gets back the colour it
-- had before; without it (the plate now shows another unit, which Blizzard has coloured or
-- will colour), the colour is left alone.
local function Unmark(plate, restore)
  HideChevrons(plate, nil)
  QuestMarks.Hide(plate)
  HideIcon(plate)
  HideFullName(plate)
  if marks[plate] then
    RestoreScales(plate)
  end
  local m = marks[plate]
  marks[plate] = nil
  if restore and m and m.fs and m.orig then
    local o = m.orig
    m.fs:SetTextColor(o[1], o[2], o[3], o[4])
    if type(m.fs.SetVertexColor) == "function" then
      m.fs:SetVertexColor(o[1], o[2], o[3], o[4])
    end
  end
end

-- ---------------------------------------------------------------------------------------
-- Compact mode: name only on friendly non-member players
--
-- There is no per-plate "show only the name" setter, so the parts of the plate are faded out
-- with SetAlpha(0) (the game calls Show() on them all the time). Nothing is ever hidden on the
-- plate itself, on UnitFrame, on the name FontString or its ancestors, or on our chevron.

-- MAX_DEPTH bounds the walk from the name FontString up to UnitFrame.
local MAX_DEPTH = 10

-- hidden: plate -> { set = part -> true, list = { parts in order }, drive = part -> true (the
-- health bar parts driven by the health curve's alpha, a subset of set), curve = the curve
-- answered, hurt = the fallback's answer, unit } while the plate is in compact mode; absent
-- otherwise (so "hidden[plate] ~= nil" means "compact").
local hidden = setmetatable({}, { __mode = "k" })
-- owners: part -> the plate whose record holds it (for the OnShow hook).
local owners = setmetatable({}, { __mode = "k" })
-- hooked: frame -> true once its OnShow is hooked (never hooked twice).
local hooked = setmetatable({}, { __mode = "k" })

-- healthCurve: the colour curve of Core.HealthCurve, built once (curveBuilt), nil if it cannot be.
local healthCurve, curveBuilt = nil, false

-- HealthAlpha returns true and the alpha unit's health bar should have (1 while hurt, 0 at full
-- health; a secret value on clients where health is secret: never read it, only pass it to
-- SetAlpha), or false when the client cannot give it (no curve API, an error).
local function HealthAlpha(unit)
  if not curveBuilt then
    curveBuilt = true
    healthCurve = Core.HealthCurve(unitAPI)
  end
  if healthCurve == nil then
    return false
  end
  return Core.HealthAlpha(unitAPI, unit, healthCurve)
end

-- DriveAlpha hands alpha (possibly secret) straight to part:SetAlpha under pcall; if that
-- fails, the part is faded (name-only). True when alpha was applied.
local function DriveAlpha(part, alpha)
  local fn = Field(part, "SetAlpha")
  if type(fn) == "function" and pcall(fn, part, alpha) then
    return true
  end
  Method(part, "SetAlpha", 0)
  return false
end

-- fullCurve: the opposite curve (Core.FULL_HEALTH_CURVE_POINTS), built once (fullBuilt) and only
-- when a compact plate first shows a level with the health curve; nil if it cannot be.
local fullCurve, fullBuilt = nil, false

-- FullHealthAlpha returns true and the alpha the name with the level should have (0 while hurt,
-- 1 at full health; secret where health is secret), or false when the client cannot give it.
local function FullHealthAlpha(unit)
  if not fullBuilt then
    fullBuilt = true
    fullCurve = Core.HealthCurve(unitAPI, Core.FULL_HEALTH_CURVE_POINTS)
  end
  if fullCurve == nil then
    return false
  end
  return Core.HealthAlpha(unitAPI, unit, fullCurve)
end

-- FollowBar makes the compact plate's own name follow its health bar. Nameplate regions cannot be
-- measured and, with the health curve, whether the bar is shown cannot be read (its alpha may be
-- secret), so every text it switches is drawn beforehand and only alphas change: with the curve
-- they get the bar's alpha or FullHealthAlpha, both possibly secret, applied, never compared.
--
-- Friendly NPCs (ShowFullName's low copy, rec.low): the name and subtitle (and role icon) are shown
-- either above the health bar, where Blizzard puts its name (rec.text, rec.sub, iconCaches.high),
-- or in the faded bar's place (rec.lowtext, rec.lowsub, iconCaches.low): low while the bar is
-- hidden, high while it is shown, so the name never covers the bar. With the curve the high copy
-- gets the bar's alpha and the low copy FullHealthAlpha. In doubt (an alpha that cannot be
-- applied) the name stays above the bar, as before 0.24.0. NPCs always keep "(level)" (keepLevel).
--
-- Other compact plates: the "(level)" after the name (Core.LevelSuffix; nothing to do when
-- ShowFullName drew no level there): Blizzard's bar shows the level beside it, so the suffix goes
-- while the bar is shown and comes back at full health. With the curve, the name with the level
-- gets FullHealthAlpha and the name alone (rec.short) the bar's alpha; if either cannot be
-- applied, the suffix stays (name with the level at 1, the name alone at 0). Without the curve,
-- the text is chosen from hurt. Only our own FontStrings are touched, never Blizzard's name.
local function FollowBar(plate, unit, curve, alpha, barDriven, hurt)
  local rec = labels[plate]
  local mode = Core.LevelSuffix(curve and true or false, barDriven, hurt)
  if rec and rec.low and rec.lowtext then
    local high, low = { rec.text }, { rec.lowtext }
    if rec.sub then
      high[#high + 1] = rec.sub
    end
    if rec.lowsub then
      low[#low + 1] = rec.lowsub
    end
    if iconCaches.high[plate] then
      high[#high + 1] = iconCaches.high[plate]
    end
    if iconCaches.low[plate] then
      low[#low + 1] = iconCaches.low[plate]
    end
    if mode == "curve" then
      local ok, full = FullHealthAlpha(unit)
      local done = ok
      if ok then
        for _, part in ipairs(high) do
          done = DriveAlpha(part, alpha) and done
        end
        for _, part in ipairs(low) do
          done = DriveAlpha(part, full) and done
        end
      end
      if done then
        rec.place = "curve"
        return
      end
      mode = "hide"
    end
    -- "hide": the bar is known shown, so the name goes above it.
    local up = mode == "hide"
    for _, part in ipairs(high) do
      Method(part, "SetAlpha", up and 1 or 0)
    end
    for _, part in ipairs(low) do
      Method(part, "SetAlpha", up and 0 or 1)
    end
    rec.place = up and "high" or "low"
    return
  end
  if not rec or not rec.full or not rec.short or rec.keepLevel then
    -- Friendly NPCs (keepLevel) always show "<name> (<level>)", as ShowFullName drew it.
    return
  end
  if mode == "curve" then
    local ok, full = FullHealthAlpha(unit)
    rec.text:SetText(rec.full)
    if ok and DriveAlpha(rec.text, full) and DriveAlpha(rec.short, alpha) then
      return
    end
    mode = "show"
  end
  rec.text:SetText(mode == "hide" and rec.plain or rec.full)
  Method(rec.text, "SetAlpha", 1)
  Method(rec.short, "SetAlpha", 0)
end

-- HealthBarParts returns UnitFrame's health bar parts (HealthBarsContainer, healthBar), the
-- ones compact mode shows while the unit is hurt.
local function HealthBarParts(uf)
  local out = {}
  for _, key in ipairs({ "HealthBarsContainer", "healthBar" }) do
    local part = Field(uf, key)
    if type(part) == "table" then
      out[#out + 1] = part
    end
  end
  return out
end

-- CompactParts returns the parts compact mode hides on a plate: for each ancestor of the name
-- FontString up to UnitFrame, its other child frames and regions, except the health bar when
-- showHealth (the unit is hurt). nil when there is no name, or the name is not inside
-- UnitFrame (then nothing is hidden).
local function CompactParts(plate, uf, showHealth)
  local fs = FindName(uf)
  if not fs then
    return nil
  end
  local keep = { [fs] = true }
  if showHealth then
    for _, part in ipairs(HealthBarParts(uf)) do
      keep[part] = true
    end
  end
  local chain = {}
  local node = fs
  for _ = 1, MAX_DEPTH do
    local parent = Method(node, "GetParent")
    if type(parent) ~= "table" then
      return nil
    end
    chain[#chain + 1] = parent
    keep[parent] = true
    if parent == uf then
      break
    end
    node = parent
  end
  if chain[#chain] ~= uf then
    return nil
  end
  for _, cache in ipairs({ chevrons, singles, iconCaches.high, iconCaches.low, QuestMarks.frames }) do
    if cache[plate] then
      keep[cache[plate]] = true
    end
  end
  if labels[plate] then
    keep[labels[plate].frame] = true
  end
  local parts = {}
  for _, ancestor in ipairs(chain) do
    for _, getter in ipairs({ "GetChildren", "GetRegions" }) do
      local list = Results(ancestor, getter)
      if list then
        for i = 1, list.n do
          local part = list[i]
          if type(part) == "table" and not keep[part] then
            keep[part] = true
            parts[#parts + 1] = part
          end
        end
      end
    end
  end
  return parts
end

-- OnPartShown fades a part out again when the game shows it, only while its plate is still
-- in compact mode; a health bar part driven by the health curve gets the curve's alpha again.
local function OnPartShown(part)
  local plate = owners[part]
  local rec = plate and hidden[plate]
  if not rec or not rec.set[part] then
    return
  end
  if rec.drive[part] then
    local ok, alpha = HealthAlpha(rec.unit)
    if ok then
      DriveAlpha(part, alpha)
      return
    end
  end
  Method(part, "SetAlpha", 0)
end

local function HookPart(part)
  if hooked[part] or type(Field(part, "HookScript")) ~= "function" then
    return
  end
  local ok = Results(part, "HookScript", "OnShow", function(self)
    SafeCall("OnShow hook", OnPartShown, self)
  end)
  if ok then
    hooked[part] = true
  end
end

-- Uncompact gives every part this addon faded on the plate its alpha back and forgets them.
local function Uncompact(plate)
  local rec = hidden[plate]
  if not rec then
    return
  end
  if not marks[plate] then
    HideFullName(plate)
    RestoreScales(plate)
  end
  hidden[plate] = nil
  for _, part in ipairs(rec.list) do
    owners[part] = nil
    Method(part, "SetAlpha", 1)
  end
end

-- Compact fades out every part of the plate but the name, and the health bar while unit is
-- hurt (again on each call, so parts that appeared since, or whose alpha the game reset, are
-- caught; a part no longer to hide, e.g. the health bar once hurt, gets its alpha back).
-- The health bar's alpha comes from the health curve when the client has it (HealthAlpha: the
-- alpha may be secret, so it is applied, never compared); else from Core.HealthMissing (the
-- readable-health fallback: an unknown health keeps the plate name-only).
-- Without a usable name, the plate keeps its default look.
-- A friend's plate is marked (Mark, friend colour and chevron) before it is compacted: its name
-- is then already ours, and stays so (the plate keeps the friend look) when compact cannot
-- apply. level is the level shown after the name of an unmarked plate (see Level), or nil; on
-- any compact plate, FollowBar then drops the suffix while the health bar is shown. bar is the
-- health bar's size (default otherbarsize, the friendlies'; service NPCs keep Blizzard's).
-- subtitle is the second line of an unmarked plate's name (a player's "<guild>"), or nil.
local function Compact(plate, uf, unit, level, bar, subtitle)
  local curve, alpha = HealthAlpha(unit)
  local hurt = not curve and Core.HealthMissing(unitAPI, unit)
  local marked = marks[plate] ~= nil
  -- The full name first, so its frame exists when the parts to fade are listed (it is kept).
  local fs = FindName(uf)
  if fs and not marked then
    local c = ReadColor(fs)
    if c then
      ShowFullName(plate, uf, fs, Factor("othersize"), c[1], c[2], c[3], 0, Gap("othernamegap"), level, subtitle)
    else
      HideFullName(plate)
    end
  end
  local parts = CompactParts(plate, uf, hurt)
  if not parts then
    Uncompact(plate)
    if marked then
      RestoreScales(plate)
    else
      HideFullName(plate)
    end
    return
  end
  ScaleBar(plate, uf, BarPart(uf), bar or Factor("otherbarsize"))
  local rec = hidden[plate]
  if not rec then
    rec = { set = {}, list = {}, drive = {} }
    hidden[plate] = rec
  end
  rec.hurt, rec.curve, rec.unit = hurt, curve, unit
  -- With the curve, the health bar parts compact would hide are driven by its alpha instead.
  local drive = {}
  if curve then
    for _, part in ipairs(HealthBarParts(uf)) do
      drive[part] = true
    end
  end
  local wanted = {}
  for _, part in ipairs(parts) do
    wanted[part] = true
  end
  local list = {}
  for _, part in ipairs(rec.list) do
    if wanted[part] then
      list[#list + 1] = part
    else
      rec.set[part], owners[part] = nil, nil
      Method(part, "SetAlpha", 1)
    end
  end
  rec.list = list
  rec.drive = {}
  -- barDriven: the curve's alpha reached every health bar part it was given (at least one), so
  -- the bar is shown exactly while hurt (FollowBar).
  local driven, barDriven = false, curve and true or false
  for _, part in ipairs(parts) do
    if not rec.set[part] then
      rec.set[part] = true
      rec.list[#rec.list + 1] = part
      owners[part] = plate
      HookPart(part)
    end
    if drive[part] then
      rec.drive[part] = true
      driven = true
      if not DriveAlpha(part, alpha) then
        barDriven = false
      end
    else
      Method(part, "SetAlpha", 0)
    end
  end
  FollowBar(plate, unit, curve, alpha, barDriven and driven, hurt)
end

-- ModeSettings is the saved settings the plate mode reads (not Blizzard's global `Settings`,
-- which the options panel below uses).
local function ModeSettings()
  return type(db) == "table" and db or nil
end

-- Info returns Core.UnitInfo for unit.
local function Info(unit)
  return Core.UnitInfo(unitAPI, unit, ModeSettings())
end

-- Mode returns the plate mode of unit ("member", "quest", "partyquest", "friend", "class", "compact" or
-- "default"),
-- its relation ("member", "friend" or nil), see Core.PlateMode, and the info it was read from.
local function Mode(unit)
  local info = Info(unit)
  local mode, relation = Core.PlateMode(info, ModeSettings())
  return mode, relation, info
end

-- Level returns the level to show after unit's name (Core.UnitLevel: -1 or less for "??"), or
-- nil when none is shown: showlevel off, not a friendly non-member player (Core.ShowsLevel,
-- from info, see Info), or the level is not readable (then the name stays alone). Apply passes
-- it to compact plates only.
local function Level(unit, info)
  if not Core.ShowsLevel(info, ModeSettings()) then
    return nil
  end
  return Core.UnitLevel(unitAPI, unit)
end

-- ShowOtherName draws the name of an unmarked full plate (Blizzard's colour, at size) with our
-- own FontString so it can be sized and moved; the rest of the plate stays Blizzard's. No level:
-- the full plate's health bar shows Blizzard's. Without a readable colour, Blizzard's name stays
-- as it is (size 1).
local function ShowOtherName(uf, size, subtitle)
  local fs = FindName(uf)
  local c = fs and ReadColor(fs)
  if c then
    ShowFullName(uf, uf, fs, size, c[1], c[2], c[3], 0, Gap("othernamegap"), nil, subtitle)
  else
    HideFullName(uf)
  end
end

-- DefaultFullPlate sizes the unmarked full plate of another friendly player (compact off, or
-- the target with compact on; Core.OtherSizes): our name at othersize and othernamegap (drawn
-- only when the size is not 1 or the gap is not 0, else Blizzard's name stays; never with the
-- level, which Blizzard's health bar shows), the health bar at
-- otherbarsize. Any other plate (enemies, NPCs, unknown) gets its original scales back, so a
-- pooled UnitFrame never keeps a friendly's bar size. subtitle (the player's "<guild>") is drawn
-- below the name, which then is always ours.
local function DefaultFullPlate(uf, info, subtitle)
  if not Core.OtherSizes(info, ModeSettings()) then
    RestoreScales(uf)
    return
  end
  local size = OtherFactor("othersize")
  if size ~= Core.DEFAULT_FACTOR or Gap("othernamegap") ~= Core.NO_GAP or subtitle then
    ShowOtherName(uf, size, subtitle)
  end
  local bar = OtherFactor("otherbarsize")
  if bar ~= Core.DEFAULT_FACTOR then
    ScaleBar(uf, uf, BarPart(uf), bar)
  else
    RestoreScales(uf)
  end
end

-- GuildLine returns "<guild>", the second line of a player's name (Core.GuildName), or nil (not
-- a player, no guild, or the guild cannot be read).
local function GuildLine(unit, info)
  if type(info) ~= "table" or info.player ~= true then
    return nil
  end
  local name = Core.GuildName(unitAPI, unit)
  return name and ("<" .. name .. ">") or nil
end

-- WithGuild sets style's second line to guild ("<guild>" or nil) and returns style.
local function WithGuild(style, guild)
  style.subtitle = guild
  return style
end

-- Apply gives the UnitFrame uf (both the key of the records and the frame) the mode of unit.
-- restore is passed to Unmark: false when uf may now show another unit, whose colour Blizzard
-- has set or will set (never restore an older colour over it).
local function Apply(uf, unit, restore)
  local mode, relation, info = Mode(unit)
  local class = Core.NameColor(info, ModeSettings(), relation) == "class"
  local level = Level(unit, info)
  -- Players get their guild on a second line, whatever their look.
  local guild = GuildLine(unit, info)
  if mode == "member" then
    Uncompact(uf)
    Mark(uf, uf, WithGuild(MemberStyle(), guild))
  elseif mode == "quest" then
    -- A hostile unit tied to a quest: full plate, our name and single chevron in the hostile colour.
    Uncompact(uf)
    Mark(uf, uf, HostileStyle(false, info))
  elseif mode == "partyquest" then
    -- A hostile unit tied to a party member's quest: the same, in the party quest colour.
    Uncompact(uf)
    Mark(uf, uf, HostileStyle(true, info))
  elseif mode == "npc" then
    -- A friendly NPC: "<name> (<level>)", its subtitle below, the role icon above when it has one
    -- (and npcicons is on); with npccompact, the health bar only while hurt, the target included.
    local compact = Flag("npccompact")
    local role = Core.ServiceNPC(info, ModeSettings()) and info.service or nil
    local npcLevel = Core.UnitLevel(unitAPI, unit)
    local subtitle = Core.SubtitleLine(Core.TooltipSubtitle(unitAPI, unit), npcLevel)
    local r, g, b = Core.ReactionColor(unitAPI, unit)
    Mark(uf, uf, NpcStyle(role, compact, npcLevel, subtitle, r and { r, g, b } or Core.DEFAULT_NPC_COLOR))
    if compact then
      Compact(uf, uf, unit, nil, Core.DEFAULT_FACTOR)
    else
      Uncompact(uf)
    end
  elseif mode == "friend" then
    -- Full plates never get the level: Blizzard's health bar shows it.
    Uncompact(uf)
    Mark(uf, uf, WithGuild(RelationStyle(relation, false), guild))
  elseif mode == "class" then
    Uncompact(uf)
    Mark(uf, uf, WithGuild(ClassStyle(info.classColor, false), guild))
  elseif mode == "compact" and (relation == "friend" or relation == "guild") then
    -- Compact plates: the level, which Compact (FollowBar) drops while the health bar shows.
    Mark(uf, uf, WithGuild(RelationStyle(relation, true, level), guild))
    Compact(uf, uf, unit)
  elseif mode == "compact" and class then
    Mark(uf, uf, WithGuild(ClassStyle(info.classColor, true, level), guild))
    Compact(uf, uf, unit)
  elseif mode == "compact" then
    Unmark(uf, restore)
    Compact(uf, uf, unit, level, nil, guild)
  else
    Unmark(uf, restore)
    Uncompact(uf)
    -- A friendly non-member's full plate (compact off, or the target): our name for othersize
    -- and othernamegap, otherbarsize on the health bar, never the level.
    DefaultFullPlate(uf, info, guild)
  end
end

-- Refresh applies the mode of unit to one plate. restore is passed to Unmark. A plate without
-- a readable UnitFrame (forbidden) is left in its default look, silently.
-- The records are keyed by UnitFrame (see chevrons above): uf is both the key and the frame.
-- ApplyAndSync applies the mode, then SyncName, which runs even when Apply raised an error
-- (the error is raised again afterwards for SafeCall to report): Blizzard's name never stays
-- faded on a plate we have just looked at unless our own name covers it.
local function ApplyAndSync(uf, unit, restore)
  local ok, err = pcall(Apply, uf, unit, restore)
  SyncName(uf)
  if not ok then
    error(err, 0)
  end
end

local function Refresh(plate, unit, restore)
  local uf = type(plate) == "table" and UnitFrameOf(plate)
  if not uf then
    -- No UnitFrame (not acquired yet, or forbidden): nothing of ours can be on it. A pooled
    -- UnitFrame is cleaned when it shows a unit again (OnUpdateName) or by RefreshAll.
    return
  end
  ApplyAndSync(uf, unit, restore)
end

-- Forget unmarks and uncompacts a UnitFrame that no longer shows anything of ours.
local function Forget(uf)
  local ok, err = pcall(function()
    Unmark(uf, true)
    Uncompact(uf)
    RestoreScales(uf)
  end)
  SyncName(uf)
  if not ok then
    error(err, 0)
  end
end

-- PendingNames returns how many names are in fadedNames (covered or waiting for a retry).
local function PendingNames()
  local n = 0
  for _ in pairs(fadedNames) do
    n = n + 1
  end
  return n
end

-- RestoreFadedNames gives alpha 1 back to every name still in fadedNames that our own name does
-- not cover (a failed SetAlpha(1) earlier, or a UnitFrame no longer on any plate).
local function RestoreFadedNames()
  local covered = {}
  for _, rec in pairs(labels) do
    if rec.name then
      covered[rec.name] = true
    end
  end
  local pending = {}
  for fs in pairs(fadedNames) do
    if not covered[fs] then
      pending[#pending + 1] = fs
    end
  end
  for _, fs in ipairs(pending) do
    RestoreName(fs)
  end
end

-- RefreshAll refreshes every visible plate, and resets the plates no longer visible.
local function RefreshAll()
  local seen = {}
  if type(C_NamePlate) == "table" then
    local plates = Try(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local uf = UnitFrameOf(plate)
        if uf then
          seen[uf] = true
        end
        SafeCall("refresh plate", Refresh, plate, PlateUnit(plate), true)
      end
    end
  end
  -- UnitFrames not shown by any plate (back in Blizzard's pool) lose everything of ours.
  local stale = {}
  for _, tracked in ipairs({ marks, hidden, labels, bars, scaled }) do
    for uf in pairs(tracked) do
      if not seen[uf] then
        seen[uf] = true
        stale[#stale + 1] = uf
      end
    end
  end
  for _, uf in ipairs(stale) do
    SafeCall("unmark plate", Forget, uf)
  end
  SafeCall("restore names", RestoreFadedNames)
end

-- OnUpdateName re-applies the colour after Blizzard recoloured a group member's name, and
-- re-checks compact mode (parts may have appeared or been reset).
local function OnUpdateName(frame)
  if not Enabled() or type(frame) ~= "table" then
    return
  end
  local unit = Field(frame, "unit")
  if not IsNameplateUnit(unit) then
    return
  end
  local plate = PlateForUnit(unit)
  if type(plate) ~= "table" or UnitFrameOf(plate) ~= frame then
    return
  end
  -- Blizzard has just coloured this name: a marked plate gets our colour back, an unmarked
  -- one drops a leftover mark without restoring an older colour over it. Also what this
  -- UnitFrame may carry from its previous plate (it comes from a pool): Blizzard's name faded
  -- under our own, our chevron. The colour is Blizzard's new one.
  ApplyAndSync(frame, unit, false)
end

local function FriendlyPlatesOff()
  local value
  if type(C_CVar) == "table" then
    value = Try(C_CVar.GetCVar, "nameplateShowFriends")
  end
  if value == nil then
    value = Try(GetCVar, "nameplateShowFriends")
  end
  return value == "0"
end

-- ---------------------------------------------------------------------------------------
-- Settings: the one place that validates (through Core), saves and refreshes. Both the slash
-- commands and the options panel call these. Each returns true when it changed the setting,
-- false (nothing changed) when the value is invalid.

local RefreshPanel -- set once the options panel exists

local function Changed()
  RefreshAll()
  if RefreshPanel then
    SafeCall("options panel refresh", RefreshPanel)
  end
end

-- SetEnabled takes true/false or the text "on"/"off".
local function SetEnabled(value)
  if type(db) ~= "table" then
    return false
  end
  if type(value) == "string" then
    value = Core.ParseOnOff(value)
  end
  if type(value) ~= "boolean" then
    return false
  end
  db.enabled = value
  Changed()
  return true
end

-- SetCompact takes true/false or the text "on"/"off".
local function SetCompact(value)
  if type(db) ~= "table" then
    return false
  end
  if type(value) == "string" then
    value = Core.ParseOnOff(value)
  end
  if type(value) ~= "boolean" then
    return false
  end
  db.compact = value
  Changed()
  return true
end

-- SetColor takes r, g, b in 0..1.
local function SetColor(r, g, b)
  if type(db) ~= "table" or not Core.ValidColor({ r, g, b }) then
    return false
  end
  db.color = { r, g, b }
  Changed()
  return true
end

-- SetFriendColor takes r, g, b in 0..1.
local function SetFriendColor(r, g, b)
  if type(db) ~= "table" or not Core.ValidColor({ r, g, b }) then
    return false
  end
  db.friendcolor = { r, g, b }
  Changed()
  return true
end

-- SetGuildColor takes r, g, b in 0..1.
local function SetGuildColor(r, g, b)
  if type(db) ~= "table" or not Core.ValidColor({ r, g, b }) then
    return false
  end
  db.guildcolor = { r, g, b }
  Changed()
  return true
end

-- SetHostileColor takes r, g, b in 0..1.
local function SetHostileColor(r, g, b)
  if type(db) ~= "table" or not Core.ValidColor({ r, g, b }) then
    return false
  end
  db.hostilecolor = { r, g, b }
  Changed()
  return true
end

-- PartyQuest.SetColor takes r, g, b in 0..1.
function PartyQuest.SetColor(r, g, b)
  if type(db) ~= "table" or not Core.ValidColor({ r, g, b }) then
    return false
  end
  db.partyquestcolor = { r, g, b }
  Changed()
  return true
end

-- SetFlag sets one of FLAG_DEFAULTS from true/false or the text "on"/"off".
local function SetFlag(kind, value)
  if type(db) ~= "table" or FLAG_DEFAULTS[kind] == nil then
    return false
  end
  if type(value) == "string" then
    value = Core.ParseOnOff(value)
  end
  if type(value) ~= "boolean" then
    return false
  end
  db[kind] = value
  Changed()
  return true
end

-- FACTOR_KINDS are the size settings SetFactor accepts.
local FACTOR_KINDS = {
  chevsize = true, textsize = true, othersize = true, barsize = true, buffsize = true, otherbarsize = true,
  hostilechevsize = true, hostilesize = true, friendchevsize = true, guildchevsize = true,
  memberoutlinesize = true, friendoutlinesize = true, guildoutlinesize = true, hostileoutlinesize = true,
  npciconsize = true, npcsize = true, friendsize = true, guildsize = true, npciconalpha = true,
  partyquestchevsize = true, partyquestsize = true, partyquestoutlinesize = true,
}

-- SetFactor sets one of FACTOR_KINDS from a number (the panel's slider) or a
-- text (the slash command).
local function SetFactor(kind, value)
  if type(db) ~= "table" or not FACTOR_KINDS[kind] then
    return false
  end
  local f
  if type(value) == "string" then
    f = Core.ParseFactor(value, kind)
  else
    f = Core.SnapFactor(value, kind)
  end
  if not f then
    return false
  end
  db[kind] = f
  Changed()
  return true
end

-- SetGap sets one of Core.GAP_KINDS (namegap, othernamegap, hostilenamegap, partyquestnamegap) from a
-- number (the panel's slider,
-- rounded to a whole point) or a text (the slash command, a whole number). Out of range or
-- invalid: refused, nothing changes.
local function SetGap(kind, value)
  if type(db) ~= "table" or not Core.GAP_KINDS[kind] then
    return false
  end
  local n
  if type(value) == "string" then
    n = Core.ParseGap(value)
  else
    n = Core.SnapGap(value)
  end
  if not n then
    return false
  end
  db[kind] = n
  Changed()
  return true
end

-- SetFont sets the font of our own name labels from a key of Core.FONTS (the panel's button,
-- /gchev font). Anything else is refused and changes nothing.
local function SetNameFont(key)
  if type(db) ~= "table" or not Core.ValidFont(key) then
    return false
  end
  db.font = key
  Changed()
  return true
end

-- ResetColor puts the default colour back (/gchev reset).
local function ResetColor()
  if type(db) ~= "table" then
    return false
  end
  db.color = Core.CopyDefaultColor()
  Changed()
  return true
end

-- ResetPage puts the settings of one options page back to their defaults (its Reset button;
-- Core.PAGE_KEYS: "main", "players", "quests" or "npcs"), and nothing else.
local function ResetPage(page)
  if not Core.ResetPage(db, page) then
    return false
  end
  Changed()
  return true
end

-- Friendly NPC nameplates: a game setting (the CVar below, unverified on the Forever client). The
-- service NPC icons need it on, but the addon only changes it when asked (/gchev npcplates, the
-- options panel), never by itself; it is not saved in GroupChevronDB.
local NPC_PLATES_CVAR = "nameplateShowFriendlyNPCs"

-- NpcPlates returns true or false for the friendly NPC nameplates setting, or nil when the client
-- does not have it (or it cannot be read).
local function NpcPlates()
  local value
  if type(C_CVar) == "table" then
    value = Try(C_CVar.GetCVar, NPC_PLATES_CVAR)
  end
  if value == nil then
    value = Try(GetCVar, NPC_PLATES_CVAR)
  end
  if value == "1" then
    return true
  elseif value == "0" then
    return false
  end
  return nil
end

-- SetNpcPlates turns the friendly NPC nameplates on or off (true/false or "on"/"off"). It returns
-- true, or false and why: "invalid", "combat" (the game refuses it in combat), "missing" (no such
-- setting on this client) or "failed" (the client refused the change).
local function SetNpcPlates(value)
  if type(value) == "string" then
    value = Core.ParseOnOff(value)
  end
  if type(value) ~= "boolean" then
    return false, "invalid"
  end
  if Try(InCombatLockdown) == true then
    return false, "combat"
  end
  if NpcPlates() == nil then
    return false, "missing"
  end
  local set = Field(C_CVar, "SetCVar")
  if type(set) ~= "function" then
    set = SetCVar
  end
  if type(set) ~= "function" or not pcall(set, NPC_PLATES_CVAR, value and "1" or "0") or NpcPlates() ~= value then
    return false, "failed"
  end
  Changed()
  return true
end

-- NPC_PLATES_REFUSED are the messages of SetNpcPlates's refusals.
local NPC_PLATES_REFUSED = {
  invalid = "use /gchev npcplates on or /gchev npcplates off",
  combat = "the game does not allow it in combat: try again out of combat",
  missing = "this client has no friendly NPC nameplates setting (" .. NPC_PLATES_CVAR .. ")",
  failed = "the client refused the change",
}

-- SoftInteract is the game's interaction soft target (CVar SoftTargetInteract, 0 to 3; 0 = off):
-- with a gamepad the NPC right in front of the player becomes its interaction target, and the game
-- shows that NPC's plate at the target's size, so friendly NPC names jump between two sizes as the
-- player moves. Like the friendly NPC plates, a game setting the addon only changes when asked
-- (/gchev softinteract, the NPCs page), not saved in GroupChevronDB. One table, not top-level
-- locals: the main chunk is close to Lua 5.1's limit of 200 locals.
local SoftInteract = { cvar = "SoftTargetInteract", default = "3" }

-- SoftInteract.Get returns true (on: any value but "0"), false ("0") or nil (no such setting, or
-- unreadable), and the raw value.
function SoftInteract.Get()
  local value
  if type(C_CVar) == "table" then
    value = Try(C_CVar.GetCVar, SoftInteract.cvar)
  end
  if value == nil then
    value = Try(GetCVar, SoftInteract.cvar)
  end
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value ~= "0", value
end

-- SoftInteract.Set turns the interaction soft target on or off (true/false or "on"/"off"). Off
-- writes "0" and remembers the value it had (for this session); on writes that value back, else
-- the game's default "3". It returns true, or false and why (as SetNpcPlates: "invalid",
-- "combat", "missing" or "failed").
function SoftInteract.Set(value)
  if type(value) == "string" then
    value = Core.ParseOnOff(value)
  end
  if type(value) ~= "boolean" then
    return false, "invalid"
  end
  if Try(InCombatLockdown) == true then
    return false, "combat"
  end
  local on, raw = SoftInteract.Get()
  if on == nil then
    return false, "missing"
  end
  if on == value then
    return true
  end
  if on then
    SoftInteract.last = raw
  end
  local set = Field(C_CVar, "SetCVar")
  if type(set) ~= "function" then
    set = SetCVar
  end
  local target = value and (SoftInteract.last or SoftInteract.default) or "0"
  if type(set) ~= "function" or not pcall(set, SoftInteract.cvar, target) or SoftInteract.Get() ~= value then
    return false, "failed"
  end
  return true
end

-- SoftInteract.Refused gives the message of a Set refusal.
function SoftInteract.Refused(why)
  if why == "invalid" then
    return "use /gchev softinteract on or /gchev softinteract off"
  elseif why == "missing" then
    return "this client has no interaction soft target setting (" .. SoftInteract.cvar .. ")"
  end
  return NPC_PLATES_REFUSED[why] or tostring(why)
end

-- ---------------------------------------------------------------------------------------
-- Options panel (Options -> AddOns -> GroupChevron). Plain widgets on our own canvas, shown
-- only when the client has the Settings canvas API; otherwise the slash commands are all there
-- is, silently.

local category -- the registered Settings category, to open it with /gchev options

-- L returns the options text of key in the client's language (English for any other locale
-- or key missing from it; never an error, also without GetLocale).
local function L(key)
  local locale
  if type(GetLocale) == "function" then
    local ok, v = pcall(GetLocale)
    if ok then
      locale = v
    end
  end
  return Core.Translate(locale, key)
end

local function BuildPanel()
  if type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
    or type(Settings.RegisterAddOnCategory) ~= "function" or type(CreateFrame) ~= "function" then
    return
  end
  local refreshing = false -- true while the controls are set from the saved values

  -- The options are split into pages, like the Settings sub-categories of other addons: the
  -- GroupChevron category itself (a title and a hint) and its sub-categories Main, Friendly
  -- players, Quest mobs and NPCs. Each page is a scroll frame (scroll bar on the right, 28 px
  -- margin) whose child frame holds its widgets; `content` is the page the widgets below are
  -- created on (the helpers read it when they are called), switched before each section. Every
  -- page refreshes all the controls when it is shown.
  local content
  local function NewPage(title, height)
    local panel = CreateFrame("Frame", nil, nil)
    panel.name = title
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(600, height)
    scroll:SetScrollChild(child)
    panel:SetScript("OnShow", function()
      SafeCall("options panel show", RefreshPanel)
    end)
    return { panel = panel, content = child, title = title }
  end
  local pages = {
    root = NewPage("GroupChevron", 120),
    main = NewPage(L("page_main"), 140),
    players = NewPage(L("page_players"), 1090),
    quests = NewPage(L("page_quests"), 580),
    npcs = NewPage(L("page_npcs"), 340),
  }

  local function Label(text, x, y, template)
    local fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end

  -- The category's title carries the addon's version (the .toc's "## Version", read with
  -- C_AddOns.GetAddOnMetadata, else the older global GetAddOnMetadata; none: the name alone).
  local rootTitle = "GroupChevron"
  local getMeta = Field(C_AddOns, "GetAddOnMetadata")
  if type(getMeta) ~= "function" then
    getMeta = GetAddOnMetadata
  end
  local version = type(getMeta) == "function" and Try(getMeta, "GroupChevron", "Version") or nil
  if type(version) == "string" and version ~= "" then
    rootTitle = rootTitle .. " " .. version
  end
  -- Page titles: "GroupChevron" on the category, "GroupChevron - <page>" on each sub-category.
  for _, key in ipairs({ "root", "main", "players", "quests", "npcs" }) do
    content = pages[key].content
    Label(key == "root" and rootTitle or ("GroupChevron - " .. pages[key].title), 16, -16, "GameFontNormalLarge")
  end
  content = pages.root.content
  Label(L("choose_section"), 16, -52)

  local function Checkbox(text, y, onClick, x)
    x = x or 16
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    Label(text, x + 32, y - 6)
    cb:SetScript("OnClick", function(self)
      if refreshing then
        return
      end
      SafeCall("options checkbox", function()
        onClick(self:GetChecked() and true or false)
      end)
    end)
    return cb
  end

  -- Swatch adds a colour swatch at y that opens the colour picker on get()'s colour (live
  -- apply through set, Cancel restores the previous colour) and returns its fill texture.
  local function Swatch(y, get, set, command)
    local swatch = CreateFrame("Button", nil, content)
    swatch:SetSize(24, 24)
    swatch:SetPoint("TOPLEFT", content, "TOPLEFT", 160, y)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(swatch)
    border:SetColorTexture(1, 1, 1, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    swatch:SetScript("OnClick", function()
      SafeCall("options colour picker", function()
        if type(ColorPickerFrame) ~= "table" or type(ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
          Print("the colour picker is not available: use /gchev " .. command .. " #RRGGBB")
          return
        end
        local pr, pg, pb = get()
        ColorPickerFrame:SetupColorPickerAndShow({
          r = pr,
          g = pg,
          b = pb,
          hasOpacity = false,
          swatchFunc = function()
            SafeCall("options colour apply", function()
              local r, g, b = ColorPickerFrame:GetColorRGB()
              set(r, g, b)
            end)
          end,
          cancelFunc = function()
            SafeCall("options colour cancel", set, pr, pg, pb)
          end,
        })
      end)
    end)
    return fill
  end

  -- Group draws a thin titled frame (x 8..592) from y (its top edge) down `height` px, under
  -- the widgets of one option group, and puts the group's title just inside its top edge. It
  -- is created before the group's controls so they sit on top. A client without
  -- BackdropTemplate / SetBackdrop gets four 1 px texture lines instead; nothing here errors.
  local BORDER = { 0.5, 0.5, 0.5, 0.8 }
  local function Group(title, y, height)
    local ok, box = pcall(CreateFrame, "Frame", nil, content, "BackdropTemplate")
    if not ok or type(box) ~= "table" then
      ok, box = pcall(CreateFrame, "Frame", nil, content)
    end
    if ok and type(box) == "table" then
      box:SetSize(584, height)
      box:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
      local done = false
      if type(box.SetBackdrop) == "function" and type(box.SetBackdropBorderColor) == "function" then
        done = pcall(function()
          box:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
          box:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
        end)
      end
      if not done and type(box.CreateTexture) == "function" then
        local function Line(p1, p2, w, h)
          local t = box:CreateTexture(nil, "BORDER")
          t:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
          t:SetPoint(p1, box, p1, 0, 0)
          t:SetPoint(p2, box, p2, 0, 0)
          if w then
            t:SetWidth(w)
          end
          if h then
            t:SetHeight(h)
          end
        end
        Line("TOPLEFT", "TOPRIGHT", nil, 1)
        Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        Line("TOPLEFT", "BOTTOMLEFT", 1, nil)
        Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
      end
    end
    return Label(title, 16, y - 8, "GameFontNormal")
  end

  content = pages.players.content
  Group(L("group_members"), -48, 312)
  Group(L("friendlies"), -840, 190)
  Group(L("friends"), -370, 222)
  Group(L("guildmates"), -602, 222)

  -- Layout: Enabled, then the "Group members" settings, then the "Friends" ones (friends list,
  -- outside the group), then the "Guildmates" ones (in your guild, outside the group), then the
  -- "Quest hostiles" ones (enemies tied to a quest), then the "Friendlies" ones (friendly players
  -- outside the group; the only section without a chevron), then Reset.
  -- The specs find widgets by creation order, so the
  -- Friends widgets, then the guild chevron checkbox, then the class colour checkbox, then the
  -- Hostiles group and finally the name font control are created last.
  content = pages.main.content
  local enabledBox = Checkbox(L("enabled"), -48, SetEnabled)
  content = pages.players.content
  local compactBox = Checkbox(L("compact"), -872, SetCompact)

  -- Name colour: a swatch that opens the colour picker (live apply, Cancel restores).
  Label(L("name_colour"), 16, -88)
  local fill = Swatch(-82, Color, SetColor, "color")

  -- Sliders: the value label follows the drag, the setting is applied on release (or at once
  -- when changed without dragging, e.g. the mouse wheel), so a drag does not spam RefreshAll.
  -- A size slider (Core factors, 0.05 steps, SetFactor) or, for a kind of Core.GAP_KINDS, a
  -- name gap slider (whole points, SetGap).
  -- The chevron previews (filled below, { thicknessKind, sizeKind, update }): a slider of the outline
  -- thickness or of the chevron size of a preview redraws it while it is dragged, before the value
  -- is saved.
  local previews = {}
  -- The outline thickness sliders sit right below the colour swatch, left of the chevron preview.
  local OUTLINE_GEOMETRY = { 16, 90, 140, 240 }
  local function Slider(text, y, kind, geometry)
    local isGap = Core.GAP_KINDS[kind] == true
    local min, max, step = Core.MinFactor(kind), Core.MaxFactor(kind), 0.05
    local fmt, default, set = "%.2f", Core.DefaultFactor(kind), SetFactor
    local function snap(v)
      return Core.SnapFactor(v, kind)
    end
    if isGap then
      min, max, step = Core.MIN_GAP, Core.MAX_GAP, 1
      fmt, default, set, snap = "%d", Core.DefaultGap(kind), SetGap, Core.SnapGap
    end
    -- geometry (the outline thickness sliders, beside the colour swatch): label, slider and value x, width.
    geometry = geometry or { 16, 160, 220, 392 }
    Label(text, geometry[1], y)
    local s = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", content, "TOPLEFT", geometry[2], y - 4)
    s:SetWidth(geometry[3])
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if type(s.SetObeyStepOnDrag) == "function" then
      s:SetObeyStepOnDrag(true)
    end
    local valueText = Label("", geometry[4], y)
    local dragging = false
    local function Show(v)
      valueText:SetText(string.format(fmt, snap(v) or default))
      for _, preview in ipairs(previews) do
        if preview.thicknessKind == kind or preview.sizeKind == kind then
          preview.update(kind, snap(v))
        end
      end
    end
    s:SetScript("OnValueChanged", function(_, v)
      if refreshing then
        return
      end
      SafeCall("options slider", function()
        Show(v)
        if not dragging then
          set(kind, v)
        end
      end)
    end)
    s:SetScript("OnMouseDown", function()
      dragging = true
    end)
    s:SetScript("OnMouseUp", function()
      dragging = false
      SafeCall("options slider release", function()
        set(kind, s:GetValue())
      end)
    end)
    return s, Show
  end

  -- Created in this order (the specs find sliders by creation order); placed by section.
  local sliders = {
    { "chevsize", Slider(L("chevron_size"), -168, "chevsize") },
    { "textsize", Slider(L("text_size"), -208, "textsize") },
    { "othersize", Slider(L("text_size"), -914, "othersize") },
    { "barsize", Slider(L("bar_size"), -248, "barsize") },
    { "buffsize", Slider(L("buffs_size"), -288, "buffsize") },
    { "otherbarsize", Slider(L("bar_size"), -954, "otherbarsize") },
    { "namegap", Slider(L("name_gap"), -328, "namegap") },
    { "othernamegap", Slider(L("name_gap"), -994, "othernamegap") },
    { "memberoutlinesize", Slider(L("outline_size"), -128, "memberoutlinesize", OUTLINE_GEOMETRY) },
    { "friendoutlinesize", Slider(L("outline_size"), -450, "friendoutlinesize", OUTLINE_GEOMETRY) },
    { "guildoutlinesize", Slider(L("outline_size"), -682, "guildoutlinesize", OUTLINE_GEOMETRY) },
  }

  -- ResetButton adds, at y on the current page, a Reset button that resets that page only.
  local function ResetButton(y, key)
    local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    button:SetSize(160, 24)
    button:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
    button:SetText(L("reset"))
    button:SetScript("OnClick", function()
      SafeCall("options reset", ResetPage, key)
    end)
    return button
  end
  content = pages.main.content
  ResetButton(-96, "main")

  -- Friends (on your friends list, outside your group).
  content = pages.players.content
  Label(L("name_colour"), 16, -410)
  local friendFill = Swatch(-404, FriendColor, SetFriendColor, "friendcolor")
  local friendChevronBox = Checkbox(L("show_chevron"), -552, function(v) SetFlag("friendchevron", v) end)
  local bnetBox = Checkbox(L("bnet_friends"), -552, function(v) SetFlag("bnetfriends", v) end, 200)

  -- Guildmates (in your guild, outside your group, not on your friends list).
  Label(L("name_colour"), 16, -642)
  local guildFill = Swatch(-636, GuildColor, SetGuildColor, "guildcolor")
  local guildChevronBox = Checkbox(L("show_chevron"), -784, function(v) SetFlag("guildchevron", v) end)

  -- Friendlies: the class colour, beside "Compact plates".
  local classBox = Checkbox(L("class_colour"), -872, function(v) SetFlag("classcolor", v) end, 260)
  -- Friendlies: show level, beside "Class colour" (created last, see above).
  local levelBox = Checkbox(L("show_level"), -872, function(v) SetFlag("showlevel", v) end, 440)

  -- Live chevron previews beside the colour swatches: the same texture, tinted with the chosen colour,
  -- with the black outline of the section's thickness (none at 0). Textures of the content frame (no
  -- frames of their own), updated by RefreshPanel, and by the thickness slider while it is dragged.

  local PREVIEW_X, PREVIEW_SIZE = 290, 72 -- the grey rounded square: left edge, side
  -- Preview draws a chevron (single: one "V", else the double chevron) in a grey rounded square to
  -- the right of the section's colour and outline rows (the colour swatch is at swatchY), at the size
  -- of the plates' chevron (sizeKind: 1 to 5 points per chevron unit) with its outline (thicknessKind).
  -- It adds { thicknessKind, sizeKind, update } to previews; update(kind, value) redraws it, with the
  -- value being dragged for that kind, else the saved ones, and colours it with get().
  -- With questIcons, the preview shows the quest hostiles' kill and loot icons side by side
  -- (QuestMarks) in place of the chevron, scaled down if needed to fit the square; the chevron
  -- when their textures cannot be loaded.
  local function Preview(swatchY, single, get, thicknessKind, sizeKind, questIcons)
    local items = {}
    local squareTop = swatchY + 6
    -- A grey rounded square, so that the colour and the black outline both stand out (a plain
    -- square when the client cannot load the texture).
    -- The page this preview is on: `content` moves on to other pages before Update runs.
    local page = content
    local backdrop = page:CreateTexture(nil, "BACKGROUND")
    local ok, loaded = pcall(backdrop.SetTexture, backdrop, BACKDROP_TEXTURE)
    if ok and loaded ~= false then
      backdrop:SetVertexColor(0.62, 0.62, 0.62, 1)
    else
      backdrop:SetColorTexture(0.62, 0.62, 0.62, 1)
    end
    backdrop:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
    backdrop:SetPoint("TOPLEFT", page, "TOPLEFT", PREVIEW_X, squareTop)
    local quest = questIcons and { kill = QuestMarks.AddIcon(page, "kill"), loot = QuestMarks.AddIcon(page, "loot") }
    if quest and quest.kill and quest.loot then
      local function UpdateIcons(kind, value)
        local color = { get() }
        local thickness = kind == thicknessKind and value or Factor(thicknessKind)
        local f = kind == sizeKind and value or Factor(sizeKind)
        -- Both icons and the outline inside the square, with a 4-unit margin.
        local fit = (PREVIEW_SIZE - 8) / (2 * QuestMarks.ICON_W + QuestMarks.SPACING + 2 * OUTLINE_UNIT * 5)
        f = math.min(f, fit, (PREVIEW_SIZE - 8) / QuestMarks.ICON_H)
        local w = (2 * QuestMarks.ICON_W + QuestMarks.SPACING) * f
        local h = QuestMarks.ICON_H * f
        QuestMarks.Place(quest, { kill = color, loot = color }, f, thickness, page, "TOPLEFT",
          PREVIEW_X + (PREVIEW_SIZE - w) / 2, squareTop - (PREVIEW_SIZE - h) / 2 - h)
      end
      previews[#previews + 1] = { thicknessKind = thicknessKind, sizeKind = sizeKind, update = UpdateIcons }
      return
    end
    local function Add(step, alpha)
      local v = page:CreateTexture(nil, "OVERLAY")
      local vok, vloaded = pcall(v.SetTexture, v, CHEVRON_TEXTURE)
      if not vok or vloaded == false then
        Method(v, "Hide")
        return
      end
      v:SetAlpha(alpha)
      local outlines = {}
      for _, dir in ipairs(OUTLINE_DIRS) do
        local outline = page:CreateTexture(nil, "ARTWORK")
        outline:SetTexture(CHEVRON_TEXTURE)
        outline:SetVertexColor(0, 0, 0, 1)
        outline:SetAlpha(alpha)
        outline.dx, outline.dy, outline.owner = dir[1], dir[2], v
        outlines[#outlines + 1] = outline
      end
      items[#items + 1] = { v = v, outlines = outlines, step = step }
    end
    Add(0, 1)
    if not single then
      Add(STEP, LOWER_ALPHA)
    end
    local function Update(kind, value)
      local r, g, b = get()
      local thickness = kind == thicknessKind and value or Factor(thicknessKind)
      local f = kind == sizeKind and value or Factor(sizeKind)
      local top = squareTop - (PREVIEW_SIZE - (single and SINGLE_HEIGHT or CHEVRON_HEIGHT) * f) / 2
      local left = PREVIEW_X + (PREVIEW_SIZE - V_WIDTH * f) / 2
      local offset = OUTLINE_UNIT * thickness * f
      for _, item in ipairs(items) do
        item.v:SetVertexColor(r, g, b, 1)
        item.v:SetSize(V_WIDTH * f, V_HEIGHT * f)
        item.v:ClearAllPoints()
        item.v:SetPoint("TOPLEFT", page, "TOPLEFT", left, top - item.step * f)
        for _, outline in ipairs(item.outlines) do
          outline:SetSize(V_WIDTH * f, V_HEIGHT * f)
          outline:ClearAllPoints()
          outline:SetPoint("CENTER", item.v, "CENTER", outline.dx * offset, outline.dy * offset)
          if thickness > 0 then
            outline:Show()
          else
            outline:Hide()
          end
        end
      end
    end
    previews[#previews + 1] = { thicknessKind = thicknessKind, sizeKind = sizeKind, update = Update }
  end
  Preview(-82, false, Color, "memberoutlinesize", "chevsize")
  Preview(-404, false, FriendColor, "friendoutlinesize", "friendchevsize")
  Preview(-636, false, GuildColor, "guildoutlinesize", "guildchevsize")

  -- Hostiles (enemies tied to one of your quests): name colour (name and chevron), then the
  -- chevron size, text size and name height sliders. Created after the other sections and
  -- before the font control, so the existing widgets keep their creation order.
  content = pages.quests.content
  Group(L("hostiles"), -48, 232)
  Label(L("name_colour"), 16, -88)
  local hostileFill = Swatch(-82, HostileColor, SetHostileColor, "hostilecolor")
  -- The quest hostiles' kill / loot icons take the chevron's size (hostilechevsize): "Icon size".
  sliders[#sliders + 1] = { "hostilechevsize", Slider(L("icon_size"), -168, "hostilechevsize") }
  sliders[#sliders + 1] = { "hostilesize", Slider(L("text_size"), -208, "hostilesize") }
  sliders[#sliders + 1] = { "hostilenamegap", Slider(L("name_gap"), -248, "hostilenamegap") }
  sliders[#sliders + 1] = {
    "hostileoutlinesize", Slider(L("outline_size"), -128, "hostileoutlinesize", OUTLINE_GEOMETRY),
  }
  -- The chevron sizes of the friends and of the guildmates (created last: the specs find sliders by
  -- creation order), right below their outline rows.
  content = pages.players.content
  sliders[#sliders + 1] = { "friendchevsize", Slider(L("chevron_size"), -490, "friendchevsize") }
  sliders[#sliders + 1] = { "guildchevsize", Slider(L("chevron_size"), -722, "guildchevsize") }
  content = pages.quests.content
  Preview(-82, true, HostileColor, "hostileoutlinesize", "hostilechevsize", true)

  -- Party quest hostiles (enemies tied to a party member's quest): the same controls as the
  -- hostiles, in their own group right below them on the Quest mobs page. Created after every
  -- other slider and swatch and before the font control, so the existing widgets keep their
  -- creation order.
  Group(L("party_hostiles"), -290, 232)
  Label(L("name_colour"), 16, -330)
  local partyQuestFill = Swatch(-324, PartyQuest.Color, PartyQuest.SetColor, "partyquestcolor")
  sliders[#sliders + 1] = { "partyquestchevsize", Slider(L("icon_size"), -410, "partyquestchevsize") }
  sliders[#sliders + 1] = { "partyquestsize", Slider(L("text_size"), -450, "partyquestsize") }
  sliders[#sliders + 1] = { "partyquestnamegap", Slider(L("name_gap"), -490, "partyquestnamegap") }
  sliders[#sliders + 1] = {
    "partyquestoutlinesize", Slider(L("outline_size"), -370, "partyquestoutlinesize", OUTLINE_GEOMETRY),
  }
  Preview(-324, true, PartyQuest.Color, "partyquestoutlinesize", "partyquestchevsize", true)

  -- Name font: a drop-down listing Core.FONTS, beside the name colour of the group members.
  -- Without the client's UIDropDownMenu API it falls back to a button that cycles through them.
  -- Created last: the specs find buttons by creation order.
  content = pages.main.content
  Label(L("name_font"), 260, -54)
  local function CurrentFont()
    return Core.FindFont(type(db) == "table" and db.font) or Core.FONTS[1]
  end
  local ShowFont
  local dropOk = pcall(function()
    if type(UIDropDownMenu_Initialize) ~= "function" or type(UIDropDownMenu_AddButton) ~= "function"
      or type(UIDropDownMenu_SetText) ~= "function" then
      error("no drop-down API")
    end
    local drop = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    drop:SetPoint("TOPLEFT", content, "TOPLEFT", 340, -48)
    if type(UIDropDownMenu_SetWidth) == "function" then
      UIDropDownMenu_SetWidth(drop, 160)
    end
    UIDropDownMenu_Initialize(drop, function()
      local current = CurrentFont()
      for _, f in ipairs(Core.FONTS) do
        local info = type(UIDropDownMenu_CreateInfo) == "function" and UIDropDownMenu_CreateInfo() or {}
        info.text = f.label
        info.checked = f == current
        info.func = function()
          SafeCall("options font", function()
            SetNameFont(f.key)
            ShowFont()
          end)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    ShowFont = function()
      UIDropDownMenu_SetText(drop, CurrentFont().label)
    end
  end)
  if not dropOk then
    local fontButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    fontButton:SetSize(200, 24)
    fontButton:SetPoint("TOPLEFT", content, "TOPLEFT", 360, -48)
    ShowFont = function()
      fontButton:SetText(CurrentFont().label)
    end
    fontButton:SetScript("OnClick", function()
      SafeCall("options font", function()
        SetNameFont(Core.NextFont(type(db) == "table" and db.font))
        ShowFont()
      end)
    end)
  end

  -- Friendly NPCs: the game's friendly NPC nameplates setting (alone on the first row), then role
  -- icons and name only, then the name's text size and the icon size. Created last: the specs
  -- find widgets by creation order.
  content = pages.npcs.content
  local NPC_Y = -48
  Group(L("services"), NPC_Y, 270)
  local npcPlatesBox = Checkbox(L("npc_plates"), NPC_Y - 32, function(v)
    local ok, why = SetNpcPlates(v)
    if not ok then
      Print("friendly NPC nameplates not changed: " .. (NPC_PLATES_REFUSED[why] or tostring(why)))
      if RefreshPanel then
        RefreshPanel()
      end
    end
  end)
  -- "(Beta)": the role detection is still being developed (shipped list, subtitles, learning).
  local servicesBox = Checkbox(L("show_icons") .. " (Beta)", NPC_Y - 72, function(v) SetFlag("npcicons", v) end)
  local serviceCompactBox = Checkbox(L("compact"), NPC_Y - 72, function(v) SetFlag("npccompact", v) end, 260)
  sliders[#sliders + 1] = { "npcsize", Slider(L("text_size"), NPC_Y - 114, "npcsize") }
  sliders[#sliders + 1] = { "npciconsize", Slider(L("icon_size"), NPC_Y - 194, "npciconsize") }
  sliders[#sliders + 1] = { "npcnamegap", Slider(L("name_gap"), NPC_Y - 154, "npcnamegap") }
  -- The friends' and guildmates' text sizes, below their chevron sizes (created last: the specs find
  -- sliders by creation order).
  content = pages.players.content
  sliders[#sliders + 1] = { "friendsize", Slider(L("text_size"), -530, "friendsize") }
  sliders[#sliders + 1] = { "guildsize", Slider(L("text_size"), -762, "guildsize") }
  -- The game's interaction soft target (gamepad), beside the friendly NPC plates setting on the
  -- NPCs page (created last: the specs find widgets by creation order).
  content = pages.npcs.content
  local softInteractBox = Checkbox(L("soft_interact"), NPC_Y - 32, function(v)
    local ok, why = SoftInteract.Set(v)
    if not ok then
      Print("interaction soft target not changed: " .. SoftInteract.Refused(why))
      if RefreshPanel then
        RefreshPanel()
      end
    end
  end, 260)
  -- The role icon's opacity, below the icon size (created last: the specs find sliders by creation
  -- order; the Friendly NPCs group is 270 high for it).
  sliders[#sliders + 1] = { "npciconalpha", Slider(L("icon_alpha"), NPC_Y - 234, "npciconalpha") }

  -- Reads the saved settings into the controls.
  RefreshPanel = function()
    refreshing = true
    local ok, err = pcall(function()
      ShowFont()
      enabledBox:SetChecked(Enabled())
      compactBox:SetChecked(type(db) == "table" and db.compact == true)
      fill:SetColorTexture(Color())
      friendFill:SetColorTexture(FriendColor())
      friendChevronBox:SetChecked(Flag("friendchevron"))
      bnetBox:SetChecked(Flag("bnetfriends"))
      guildFill:SetColorTexture(GuildColor())
      guildChevronBox:SetChecked(Flag("guildchevron"))
      hostileFill:SetColorTexture(HostileColor())
      partyQuestFill:SetColorTexture(PartyQuest.Color())
      for _, preview in ipairs(previews) do
        preview.update()
      end
      classBox:SetChecked(Flag("classcolor"))
      levelBox:SetChecked(Flag("showlevel"))
      servicesBox:SetChecked(Flag("npcicons"))
      serviceCompactBox:SetChecked(Flag("npccompact"))
      npcPlatesBox:SetChecked(NpcPlates() == true)
      softInteractBox:SetChecked(SoftInteract.Get() == true)
      for _, sl in ipairs(sliders) do
        local v = Core.GAP_KINDS[sl[1]] and Gap(sl[1]) or Factor(sl[1])
        sl[2]:SetValue(v)
        sl[3](v)
      end
    end)
    refreshing = false
    if not ok then
      error(err, 0)
    end
  end
  -- The other pages' Reset buttons, below their sections (created last: the specs find buttons
  -- by creation order).
  content = pages.players.content
  ResetButton(-1046, "players")
  content = pages.quests.content
  ResetButton(-538, "quests")
  content = pages.npcs.content
  ResetButton(-334, "npcs")

  -- The GroupChevron category and its sub-categories. A client without sub-categories gets one
  -- category per page instead ("GroupChevron - <page>").
  local cat = Settings.RegisterCanvasLayoutCategory(pages.root.panel, "GroupChevron")
  Settings.RegisterAddOnCategory(cat)
  category = cat
  for _, key in ipairs({ "main", "players", "quests", "npcs" }) do
    local page = pages[key]
    local sub = Settings.RegisterCanvasLayoutSubcategory
    if type(sub) ~= "function" or not pcall(sub, cat, page.panel, page.title) then
      Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page.panel,
        "GroupChevron - " .. page.title))
    end
  end
end

-- OpenOptions opens the panel (/gchev options). It may be refused in combat: never an error.
local function OpenOptions()
  if not category or type(Settings) ~= "table" or type(Settings.OpenToCategory) ~= "function" then
    Print("the options panel is not available on this client: use the /gchev commands")
    return
  end
  local id = Method(category, "GetID")
  if id == nil or not pcall(Settings.OpenToCategory, id) then
    Print("could not open the options panel (in combat?): try again out of combat")
  end
end

-- The game's add-on menu under the minimap's calendar (the "Addon Compartment", patch 10.1.0 and
-- the Forever client): `## AddonCompartmentFunc` in the .toc names this global, called on a click
-- on GroupChevron's entry (its icon is the .toc's IconTexture). It opens the options, like
-- /gchev options. A global, not a local: the .toc can only name globals.
function GroupChevron_OnAddonCompartmentClick()
  SafeCall("addon compartment", OpenOptions)
end

-- ---------------------------------------------------------------------------------------
-- Blizzard's nameplate driver
--
-- The NAME_PLATE_UNIT_ADDED / REMOVED handlers alone cannot follow the pooled UnitFrames:
-- they run before or after Blizzard's own (event order between frames is not guaranteed), so
-- at REMOVED the plate may have already given its UnitFrame back (nothing to clean: it goes to
-- the pool with Blizzard's name still faded) and at ADDED it may not have one yet. And
-- Blizzard does not call CompactUnitFrame_UpdateName when it gives a UnitFrame a unit
-- (CompactUnitFrame_UpdateAll skips it for units), so the 0.6.2 clean-up in that hook did not
-- always run: enemies without a name again, until the next RefreshAll. Post-hooks on the
-- driver run at the right moment:
--   - ReleaseUnitFrame(base): the driver gives base.UnitFrame back to the pool (base keeps it
--     until the driver returns): everything of ours on it is undone first;
--   - OnNamePlateAdded(token): the plate has acquired its UnitFrame and set the unit: its mode
--     is applied, which also undoes anything left on that UnitFrame.

local function OnUnitFrameReleased(base)
  local uf = UnitFrameOf(base)
  if uf then
    Forget(uf)
  end
end

local function OnNamePlateAdded(token)
  token = Readable(token)
  if IsNameplateUnit(token) then
    Refresh(PlateForUnit(token), token, false)
  end
end

-- driverHooks: which driver hooks are installed, and how often each ran (for /gchev debug: if
-- a name goes missing again, this tells whether they run on the Forever client at all).
local driverHooks = { release = false, added = false, releaseCalls = 0, addedCalls = 0 }

local function HookDriver()
  local driver = _G.NamePlateDriverFrame
  if type(hooksecurefunc) ~= "function" or type(driver) ~= "table" then
    return
  end
  if type(Field(driver, "ReleaseUnitFrame")) == "function" then
    hooksecurefunc(driver, "ReleaseUnitFrame", function(_, base)
      driverHooks.releaseCalls = driverHooks.releaseCalls + 1
      SafeCall("ReleaseUnitFrame hook", OnUnitFrameReleased, base)
    end)
    driverHooks.release = true
  end
  if type(Field(driver, "OnNamePlateAdded")) == "function" then
    hooksecurefunc(driver, "OnNamePlateAdded", function(_, token)
      driverHooks.addedCalls = driverHooks.addedCalls + 1
      SafeCall("OnNamePlateAdded hook", OnNamePlateAdded, token)
    end)
    driverHooks.added = true
  end
end

-- ---------------------------------------------------------------------------------------
-- Events

local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= addonName then
    return
  end
  GroupChevronDB = Core.InitDB(GroupChevronDB)
  db = GroupChevronDB
  SafeCall("options panel", BuildPanel)
  if type(hooksecurefunc) == "function" and type(CompactUnitFrame_UpdateName) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
      SafeCall("CompactUnitFrame_UpdateName hook", OnUpdateName, frame)
    end)
  end
  SafeCall("nameplate driver hooks", HookDriver)
end

function handlers.PLAYER_ENTERING_WORLD()
  if FriendlyPlatesOff() then
    NoticeOnce("friendsoff", "friendly player nameplates are off (V / Shift+V): group members cannot be marked")
  end
  -- Said once per install (the setting is the player's): the friendly NPC options need NPC plates.
  if type(db) == "table" and (Flag("npcicons") or Flag("npccompact")) and NpcPlates() == false
    and not db.npcplatesnoticed then
    db.npcplatesnoticed = true
    Print("the friendly NPC options (role icons above flight masters, vendors...) need friendly NPC nameplates, "
      .. "which are off: /gchev npcplates on")
  end
  RefreshAll()
end

function handlers.GROUP_ROSTER_UPDATE()
  RefreshAll()
end

-- Leaving combat: one more chance for any name whose SetAlpha(1) failed (see RestoreName).
function handlers.PLAYER_REGEN_ENABLED()
  RefreshAll()
end

-- The old and the new target both change mode (a non-member target shows its full plate).
function handlers.PLAYER_TARGET_CHANGED()
  RefreshAll()
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
  unit = Readable(unit)
  -- A recycled plate may still be marked for the unit it showed before: never restore that
  -- unit's colour over the new one.
  Refresh(PlateForUnit(unit), unit, false)
end

-- A compact plate shows its health bar while the unit is hurt. With the health curve, its
-- alpha (which may be secret, so it cannot be compared with the last one) is applied again on
-- every health event, and so are the alphas of the name with and without the "(level)" suffix
-- (FollowBar); if the curve fails now, the plate is compacted again (fallback). With the
-- readable-health fallback, the plate is re-checked when the health crosses "full" either way
-- (nothing to do for other plates, or no change), which also switches the suffix (Compact).
local function OnHealth(unit)
  unit = Readable(unit)
  if not Enabled() or not IsNameplateUnit(unit) then
    return
  end
  local plate = PlateForUnit(unit)
  local uf = type(plate) == "table" and UnitFrameOf(plate)
  local rec = uf and hidden[uf]
  if not rec then
    return
  end
  if rec.curve then
    local ok, alpha = HealthAlpha(unit)
    if ok and rec.unit == unit then
      local driven, barDriven = false, true
      for _, part in ipairs(rec.list) do
        if rec.drive[part] then
          driven = true
          if not DriveAlpha(part, alpha) then
            barDriven = false
          end
        end
      end
      -- The "(level)" suffix follows the bar (its alpha cannot be compared with the last one).
      FollowBar(uf, unit, true, alpha, barDriven and driven, false)
      return
    end
  elseif rec.hurt == Core.HealthMissing(unitAPI, unit) then
    return
  end
  local info = Info(unit)
  local mode = Core.PlateMode(info, ModeSettings())
  if mode == "compact" then
    Compact(uf, uf, unit, Level(unit, info), nil, GuildLine(unit, info))
  elseif mode == "npc" and Flag("npccompact") and marks[uf] then
    Compact(uf, uf, unit, nil, Core.DEFAULT_FACTOR)
  end
end

handlers.UNIT_HEALTH = OnHealth
handlers.UNIT_MAXHEALTH = OnHealth

-- The level shown after a friendly player's name: re-applied when it changes (a level-up, or
-- the client learning a level it reported as unknown).
function handlers.UNIT_LEVEL(unit)
  unit = Readable(unit)
  if not Enabled() or not IsNameplateUnit(unit) then
    return
  end
  Refresh(PlateForUnit(unit), unit, true)
end

-- Friend lists: the plates are re-checked when the character or Battle.net friends list
-- changes. BN_FRIEND_INFO_CHANGED can fire often, so a burst gives one RefreshAll, at most
-- every FRIEND_REFRESH_DELAY seconds (C_Timer.After; without it, at once).
local FRIEND_REFRESH_DELAY = 0.2
local friendRefreshPending = false

local function FriendRefreshNow()
  friendRefreshPending = false
  SafeCall("friend list refresh", RefreshAll)
end

local function ScheduleFriendRefresh()
  if friendRefreshPending then
    return
  end
  local after = Field(C_Timer, "After")
  if type(after) == "function" then
    friendRefreshPending = true
    if pcall(after, FRIEND_REFRESH_DELAY, FriendRefreshNow) then
      return
    end
    friendRefreshPending = false
  end
  RefreshAll()
end

for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
  "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" }) do
  handlers[event] = ScheduleFriendRefresh
end

-- Guild changes (joined, left, roster) use the same coalesced refresh. GUILD_ROSTER_UPDATE can
-- fire often; a client without one of these events just fails its pcall RegisterEvent below.
for _, event in ipairs({ "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" }) do
  handlers[event] = ScheduleFriendRefresh
end

-- Quest log changes (an objective progressing or completing, a quest accepted or removed) change
-- which hostile units are tied to a quest: same coalesced refresh. QUEST_LOG_UPDATE and
-- UNIT_QUEST_LOG_CHANGED can fire in bursts; a client without one of these events just fails its
-- pcall RegisterEvent below.
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
  handlers[event] = ScheduleFriendRefresh
end

-- Service NPCs: the windows an NPC opens tell its role for sure (a merchant who repairs, a flight
-- master...). The role is learned by creature ID (the "npc" unit's GUID, readable during the
-- interaction) into GroupChevronDB.npcroles, only while the feature is on, and the plates are
-- re-checked (same coalesced refresh). Both the classic events and the interaction manager's are
-- listened to (whichever the client has; an unknown event just fails its pcall RegisterEvent).
local function LearnFromNPC(kind)
  if type(db) ~= "table" or not Enabled() or not Flag("npcicons") then
    return
  end
  local id = Core.NpcID(Try(UnitGUID, "npc"))
  -- A merchant who repairs, a trainer who teaches a profession (unverified on the Forever client:
  -- without the function, every trainer counts as a class trainer).
  local more = false
  if kind == "merchant" then
    more = Try(CanMerchantRepair) == true
  elseif kind == "trainer" then
    more = Try(IsTradeskillTrainer) == true
  end
  if Core.LearnRole(db.npcroles, id, Core.InteractionRole(kind, more)) then
    ScheduleFriendRefresh()
  end
end

for event, kind in pairs({ MERCHANT_SHOW = "merchant", TAXIMAP_OPENED = "taxi", BANKFRAME_OPENED = "banker",
  AUCTION_HOUSE_SHOW = "auctioneer", TRAINER_SHOW = "trainer", PET_STABLE_SHOW = "stable",
  CONFIRM_BINDER = "binder" }) do
  handlers[event] = function()
    LearnFromNPC(kind)
  end
end

-- INTERACTION_TYPES: the names in Enum.PlayerInteractionType of the windows above.
local INTERACTION_TYPES = {
  Merchant = "merchant", TaxiNode = "taxi", Banker = "banker", Auctioneer = "auctioneer", Trainer = "trainer",
  StableMaster = "stable", Binder = "binder",
}

function handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(interaction)
  interaction = Readable(interaction)
  local types = Field(_G.Enum, "PlayerInteractionType")
  if interaction == nil or type(types) ~= "table" then
    return
  end
  for name, kind in pairs(INTERACTION_TYPES) do
    local v = Field(types, name)
    if v ~= nil and v == interaction then
      LearnFromNPC(kind)
      return
    end
  end
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
  local plate = PlateForUnit(Readable(unit))
  local uf = type(plate) == "table" and UnitFrameOf(plate)
  if uf then
    Forget(uf)
  end
end

if type(CreateFrame) == "function" then
  local frame = CreateFrame("Frame")
  for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
      SafeCall(event, handler, ...)
    end
  end)
end

-- ---------------------------------------------------------------------------------------
-- /gchev

-- SOURCE_NAMES are the friend sources of Core.FriendLookup, as /gchev prints them.
local SOURCE_NAMES = {
  list = "character list",
  bnet = "Battle.net",
  none = "none",
  noguid = "no readable GUID",
  missing = "API missing",
}

-- FriendText says whether unit counts as a friend outside the group, and which source
-- answered, e.g. "target friend: yes (character list)".
local function FriendText(unit, what)
  local info = Info(unit)
  local yes = Core.Relation(info, ModeSettings()) == "friend"
  return string.format("%s friend: %s (%s)", what, yes and "yes" or "no",
    SOURCE_NAMES[info.source] or tostring(info.source))
end

-- GUILD_SOURCE_NAMES are the sources of Core.GuildLookup, as /gchev prints them.
local GUILD_SOURCE_NAMES = {
  unit = "UnitIsInMyGuild",
  guid = "IsPlayerInGuildFromGUID",
  none = "none",
  noguild = "not in a guild",
  noguid = "no readable GUID",
  missing = "API missing",
}

-- GuildText says whether unit counts as a guildmate (outside the group, not a friend), and
-- which API answered, e.g. "target guildmate: yes (UnitIsInMyGuild)".
local function GuildText(unit, what)
  local info = Info(unit)
  local yes = Core.Relation(info, ModeSettings()) == "guild"
  return string.format("%s guildmate: %s (%s)", what, yes and "yes" or "no",
    GUILD_SOURCE_NAMES[info.guildSource] or tostring(info.guildSource))
end

-- QUEST_SOURCE_NAMES are the sources of Core.QuestLookup, as /gchev prints them.
local QUEST_SOURCE_NAMES = {
  unit = "UnitIsRelatedToActiveQuest",
  tooltip = "an open objective of yours in the unit's tooltip",
  none = "none",
  missing = "API missing",
  skipped = "not asked: not known to be attackable",
}

-- PartyQuest.Text says whether unit counts as a hostile unit tied to a party member's quest, and
-- which answer it comes from, e.g. "target party quest hostile: yes (C_TooltipInfo.GetUnit)".
function PartyQuest.Text(unit, what)
  local sources = {
    tooltip = "C_TooltipInfo.GetUnit",
    none = "none",
    nogroup = "not in a group",
    missing = "API missing",
    skipped = "not asked: not known to be attackable, or tied to your own quests",
  }
  local info = Info(unit)
  return string.format("%s party quest hostile: %s (%s)", what,
    Core.PartyQuestHostile(info, ModeSettings()) and "yes" or "no",
    sources[info.partyQuestSource] or tostring(info.partyQuestSource))
end

-- QuestText says whether unit counts as a hostile unit tied to a quest, and which answer it comes
-- from, e.g. "target quest hostile: yes (UnitIsRelatedToActiveQuest, attackable true); kill yes,
-- loot no (tooltip)": what is left to do to it (Core.QuestKindLookup), asked only for a quest hostile.
local function QuestText(unit, what)
  local info = Info(unit)
  local kinds = ""
  if info.questKindSource ~= nil then
    kinds = string.format("; kill %s, loot %s, party kill %s, party loot %s (%s)", info.questKill and "yes" or "no",
      info.questLoot and "yes" or "no", info.partyKill and "yes" or "no", info.partyLoot and "yes" or "no",
      tostring(info.questKindSource))
  end
  return string.format("%s quest hostile: %s (%s, attackable %s)%s", what,
    Core.QuestHostile(info, ModeSettings()) and "yes" or "no",
    QUEST_SOURCE_NAMES[info.questSource] or tostring(info.questSource), tostring(info.attackable), kinds)
end

-- SERVICE_SOURCE_NAMES are the sources of Core.ServiceLookup, as /gchev prints them.
local SERVICE_SOURCE_NAMES = {
  learned = "learned from its window",
  shipped = "shipped with the addon",
  subtitle = "subtitle",
  none = "none",
}

-- ServiceText says whether unit counts as a service NPC, its role and where the role comes from,
-- e.g. "target service NPC: yes, flight (subtitle)".
local function ServiceText(unit, what)
  local info = Info(unit)
  local yes = Core.ServiceNPC(info, ModeSettings())
  return string.format("%s service NPC: %s, %s (%s; subtitle %q)", what, yes and "yes" or "no",
    tostring(info.service or "no role"), SERVICE_SOURCE_NAMES[info.serviceSource] or "not asked",
    tostring(Core.TooltipSubtitle(unitAPI, unit) or ""))
end

-- ClassText gives unit's class token and class colour, and the colour its name gets, e.g.
-- "class MAGE, class colour #3FC7EB (classcolor on), name colour: class #3FC7EB".
local function ClassText(unit)
  local token, r, g, b = Core.ClassColor(unitAPI, unit)
  local info = Info(unit)
  local settings = ModeSettings()
  local _, relation = Core.PlateMode(info, settings)
  local which = Core.NameColor(info, settings, relation)
  local name = "Blizzard's"
  if which == "member" then
    name = "member " .. Core.FormatColor(Color())
  elseif which == "friend" then
    name = "friend " .. Core.FormatColor(FriendColor())
  elseif which == "guild" then
    name = "guild " .. Core.FormatColor(GuildColor())
  elseif which == "class" then
    name = "class " .. Core.FormatColor(unpack(info.classColor))
  end
  return string.format("class %s, class colour %s (classcolor %s), name colour: %s", token or "unknown",
    r and Core.FormatColor(r, g, b) or "none", Flag("classcolor") and "on" or "off", name)
end

local function SlashStatus()
  if not db then
    Print("not initialised yet")
    return
  end
  local field = "not checked yet (no group member's plate seen)"
  if lastNameField == "" then
    field = "not found (chevron only)"
  elseif lastNameField then
    field = "UnitFrame." .. lastNameField
  end
  local n, friends, guildmates, classes, quests, services, partyQuests = 0, 0, 0, 0, 0, 0, 0
  for _, m in pairs(marks) do
    if m.kind == "member" then
      n = n + 1
    elseif m.kind == "quest" then
      quests = quests + 1
    elseif m.kind == "partyquest" then
      partyQuests = partyQuests + 1
    elseif m.kind == "npc" or m.kind == "npccompact" then
      services = services + 1
    elseif m.kind == "guild" or m.kind == "guildcompact" then
      guildmates = guildmates + 1
    elseif m.kind == "class" or m.kind == "classcompact" then
      classes = classes + 1
    else
      friends = friends + 1
    end
  end
  Print(string.format("%s, colour %s, name field: %s, %d plate(s) marked", db.enabled and "on" or "off",
    Core.FormatColor(Color()), field, n))
  Print(string.format("friends: colour %s, friendsize %s, chevron %s, Battle.net friends %s, %d plate(s) marked; %s",
    Core.FormatColor(FriendColor()), tostring(Factor("friendsize")), Flag("friendchevron") and "on" or "off",
    Flag("bnetfriends") and "on" or "off", friends, FriendText("target", "target")))
  Print(string.format("guildmates: colour %s, guildsize %s, chevron %s, %d plate(s) marked; %s",
    Core.FormatColor(GuildColor()), tostring(Factor("guildsize")), Flag("guildchevron") and "on" or "off", guildmates,
    GuildText("target", "target")))
  Print(string.format("group members: chevsize %s, textsize %s, barsize %s, buffsize %s, namegap %d",
    tostring(Factor("chevsize")), tostring(Factor("textsize")), tostring(Factor("barsize")),
    tostring(Factor("buffsize")), Gap("namegap")))
  Print(string.format("friendlies: level %s; othersize %s, otherbarsize %s, othernamegap %d",
    Flag("showlevel") and "on" or "off", tostring(Factor("othersize")), tostring(Factor("otherbarsize")),
    Gap("othernamegap")))
  Print(string.format("hostiles (quest): colour %s, hostilechevsize %s, hostilesize %s, hostilenamegap %d, "
    .. "%d plate(s) marked; %s", Core.FormatColor(HostileColor()), tostring(Factor("hostilechevsize")),
    tostring(Factor("hostilesize")), Gap("hostilenamegap"), quests, QuestText("target", "target")))
  Print(string.format("party quest hostiles: colour %s, partyquestchevsize %s, partyquestsize %s, "
    .. "partyquestnamegap %d, %d plate(s) marked; %s", Core.FormatColor(PartyQuest.Color()),
    tostring(Factor("partyquestchevsize")), tostring(Factor("partyquestsize")), Gap("partyquestnamegap"),
    partyQuests, PartyQuest.Text("target", "target")))
  local learned = 0
  for _ in pairs(type(db.npcroles) == "table" and db.npcroles or {}) do
    learned = learned + 1
  end
  local shipped = 0
  for _ in pairs(Core.SHIPPED_ROLES) do
    shipped = shipped + 1
  end
  local plates = NpcPlates()
  Print(string.format("friendly NPCs: icons %s, compact %s, npcsize %s, npcnamegap %d, npciconsize %s, "
    .. "npciconalpha %s, friendly NPC nameplates %s, interaction soft target %s, %d role(s) learned, "
    .. "%d shipped, %d plate(s) marked; %s",
    Flag("npcicons") and "on" or "off",
    Flag("npccompact") and "on" or "off", tostring(Factor("npcsize")), Gap("npcnamegap"),
    tostring(Factor("npciconsize")), tostring(Factor("npciconalpha")),
    plates == nil and "unknown" or (plates and "on" or "off"),
    SoftInteract.Get() == nil and "unknown" or (SoftInteract.Get() and "on" or "off"), learned, shipped, services,
    ServiceText("target", "target")))
  Print(string.format("name font: %s", tostring(db.font)))
  local c = 0
  for _ in pairs(hidden) do
    c = c + 1
  end
  Print(string.format("compact %s (other friendly players: name only), %d plate(s) compact",
    db.compact and "on" or "off", c))
  Print(string.format("class colour %s (other friendly players' names), %d plate(s) coloured",
    Flag("classcolor") and "on" or "off", classes))
  Print("/gchev on | off | color #RRGGBB | chevsize 1-5 | textsize 1-3 | barsize 1-3 | buffsize 1-3"
    .. " | namegap -40-40 | friendcolor #RRGGBB | friendchevron on|off | bnetfriends on|off"
    .. " | guildcolor #RRGGBB | guildchevron on|off"
    .. " | friendchevsize 1-5 | guildchevsize 1-5 | friendsize 1-3 | guildsize 1-3 | hostilecolor #RRGGBB"
    .. " | hostilechevsize 1-5"
    .. " | hostilesize 1-3 | hostilenamegap -40-40"
    .. " | partyquestcolor #RRGGBB | partyquestchevsize 1-5 | partyquestsize 1-3 | partyquestnamegap -40-40"
    .. " | memberoutlinesize|friendoutlinesize|guildoutlinesize|hostileoutlinesize|partyquestoutlinesize 0-5"
    .. " | othersize 1-3 | otherbarsize 1-3 | othernamegap -40-40 | level on|off | compact on|off | classcolor on|off"
    .. " | font default|outline|chat|large|game13"
    .. " | npcplates on|off | softinteract on|off | npcicons on|off | npccompact on|off | npcsize 1-3"
    .. " | npcnamegap -40-40 | npciconsize 1-15 | npciconalpha 0.1-1"
    .. " | icon [<role> <texture or atlas>|default]"
    .. " | reset | options | debug [all]")
end

-- PartLabel names a plate part for /gchev debug: its frame name, else the field that holds it
-- on one of tables (UnitFrame and the name's ancestors), else "(anonymous)".
local function PartLabel(part, tables)
  local name = Method(part, "GetName")
  if type(name) == "string" and name ~= "" then
    return name
  end
  for _, t in ipairs(tables) do
    local ok, key = pcall(function()
      for k, v in pairs(t) do
        if v == part and type(k) == "string" then
          return k
        end
      end
      return nil
    end)
    if ok and type(key) == "string" then
      return key
    end
  end
  return "(anonymous)"
end

-- SlashNames (/gchev names) lists, without changing anything or needing a target, every
-- visible plate whose Blizzard name is not visible (alpha below 1, or hidden) and not covered by
-- ours: its unit, the unit's name, the alpha, the shown state, and whether the addon still
-- remembers fading it. Then the driver hook counts and the failed restores.
local function SlashNames()
  local plates = type(C_NamePlate) == "table" and Try(C_NamePlate.GetNamePlates)
  if type(plates) ~= "table" then
    Print("names: no nameplates")
    return
  end
  local seen, missing, unsized = 0, 0, 0
  for _, plate in ipairs(plates) do
    local uf = UnitFrameOf(plate)
    local fs = uf and FindName(uf)
    if fs then
      seen = seen + 1
      local a, shown = Method(fs, "GetAlpha"), Method(fs, "IsShown")
      if not Covered(uf, fs) and ((type(a) == "number" and a < 0.99) or shown == false) then
        missing = missing + 1
        local unit = PlateUnit(plate)
        Print(string.format("names: %s %q alpha %s shown %s, remembered faded: %s", tostring(unit),
          tostring(unit and Try(UnitName, unit) or "?"), tostring(a), tostring(shown),
          fadedNames[fs] and "yes" or "no"))
      elseif marks[uf] and not Covered(uf, fs) then
        -- Coloured and chevroned, but Blizzard's name at Blizzard's size (not textsize).
        unsized = unsized + 1
        local unit = PlateUnit(plate)
        Print(string.format("names: %s %q marked, our own name not drawn: %s", tostring(unit),
          tostring(unit and Try(UnitName, unit) or "?"), nameFails[uf] or "reason unknown"))
      end
    end
  end
  Print(string.format("names: %d plate(s), %d without a visible name, %d marked at Blizzard's size; driver hooks: "
    .. "release %s (%d calls), added %s (%d calls); failed name restores: %d", seen, missing, unsized,
    driverHooks.release and "on" or "off",
    driverHooks.releaseCalls, driverHooks.added and "on" or "off", driverHooks.addedCalls, restoreFailures))
end

-- IsSecret is true when the client marks v as a secret value (or issecretvalue fails on it).
local function IsSecret(v)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, secret = pcall(issecretvalue, v)
  return not ok or secret == true
end

-- ValueText gives v for /gchev debug: "secret" for a secret value (never read: printing it could
-- raise an error), else tostring(v).
local function ValueText(v)
  if IsSecret(v) then
    return "secret"
  end
  local ok, s = pcall(tostring, v)
  return ok and type(s) == "string" and s or "?"
end

-- Raw calls fn(...) under pcall and returns ValueText of its first result ("error" when it
-- raises one, "missing" when fn is not a function), secret or not.
local function Raw(fn, ...)
  if type(fn) ~= "function" then
    return "missing"
  end
  local ok, v = pcall(fn, ...)
  if not ok then
    return "error"
  end
  return ValueText(v)
end

-- HealthDebug prints, for /gchev debug, unit's health as the client gives it (and whether each
-- value is secret), whether the health curve works, and the shown state and alpha of uf's
-- health bar parts. Nothing it prints is ever compared.
local function HealthDebug(unit, uf)
  Print(string.format("debug: UnitHealth %s, UnitHealthMax %s, UnitHealthPercent %s", Raw(UnitHealth, unit),
    Raw(UnitHealthMax, unit), Raw(UnitHealthPercent, unit)))
  local ok, alpha = HealthAlpha(unit)
  Print(string.format("debug: health curve: UnitHealthPercent %s, C_CurveUtil.CreateColorCurve %s, CreateColor %s, "
    .. "curve %s, alpha %s", type(unitAPI.UnitHealthPercent) == "function" and "yes" or "no",
    type(unitAPI.CreateColorCurve) == "function" and "yes" or "no",
    type(unitAPI.CreateColor) == "function" and "yes" or "no", healthCurve ~= nil and "built" or "not built",
    ok and ValueText(alpha) or "unavailable (fallback: UnitHealth / UnitHealthMax)"))
  local tables, barParts = { uf }, HealthBarParts(uf)
  if #barParts == 0 then
    Print("debug: no health bar part (HealthBarsContainer, healthBar) on this plate")
  end
  for _, part in ipairs(barParts) do
    Print(string.format("debug: health bar part %s: shown %s, alpha %s", PartLabel(part, tables),
      Raw(Field(part, "IsShown"), part), Raw(Field(part, "GetAlpha"), part)))
  end
end

local function SlashDebug(arg)
  -- ScaleDebug prints, for /gchev debug, the scales of the target's plate, its UnitFrame,
  -- Blizzard's name and our own name frame ("scale S eff E", plus "ignores parent" when it ignores
  -- its parent's scale), and both names' font object and size: run it near and far from the same
  -- unit to see which one changes with distance. Nothing it prints is ever compared.
  local function ScaleDebug(plate, uf, fs)
    local function ScaleText(obj)
      if type(obj) ~= "table" then
        return "-"
      end
      local out = string.format("scale %s eff %s", ValueText(Method(obj, "GetScale")),
        ValueText(Method(obj, "GetEffectiveScale")))
      if Method(obj, "IsIgnoringParentScale") == true then
        out = out .. " ignores parent"
      end
      return out
    end
    local function FontText(f)
      if type(f) ~= "table" then
        return "-"
      end
      local obj = Method(f, "GetFontObject")
      local objName = type(obj) == "table" and Method(obj, "GetName") or nil
      local font = Results(f, "GetFont")
      return string.format("font %s size %s", ValueText(objName), ValueText(font and font[2]))
    end
    local rec = labels[uf]
    Print(string.format("debug: scales: plate %s; UnitFrame %s; Blizzard name %s, %s", ScaleText(plate),
      ScaleText(uf), ScaleText(fs), FontText(fs)))
    Print(string.format("debug: scales: our name frame %s, %s", ScaleText(rec and rec.frame),
      FontText(rec and rec.text)))
  end
  -- /gchev debug all: the same lines for every visible plate the addon marked (not only the
  -- target: some changes only show on plates that are not targeted), with the mark's kind, the
  -- alpha and shown state of Blizzard's name and of each of our labels (name with level, name
  -- alone, subtitle line), to tell a font or scale change from two labels drawn over each other.
  if type(arg) == "string" and arg:lower() == "all" then
    local plates = type(C_NamePlate) == "table" and Try(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then
      Print("debug all: no nameplates")
      return
    end
    local function Look(obj)
      if type(obj) ~= "table" then
        return "-"
      end
      return string.format("alpha %s shown %s", ValueText(Method(obj, "GetAlpha")), ValueText(Method(obj, "IsShown")))
    end
    local n = 0
    for _, p in ipairs(plates) do
      local u = UnitFrameOf(p)
      if u and marks[u] then
        n = n + 1
        local unit = PlateUnit(p)
        local rec = labels[u]
        local fs = FindName(u)
        Print(string.format("debug all: %s %q (%s), target %s", tostring(unit),
          tostring(unit and Try(UnitName, unit) or "?"), tostring(marks[u].kind),
          ValueText(unit and Try(UnitIsUnit, unit, "target"))))
        ScaleDebug(p, u, fs)
        Print(string.format("debug all: Blizzard name %s; ours: name %s, short %s, subtitle %s; frame %s",
          Look(fs), Look(rec and rec.text), Look(rec and rec.short), Look(rec and rec.sub), Look(rec and rec.frame)))
      end
    end
    Print(string.format("debug all: %d marked plate(s)", n))
    return
  end
  local plate = PlateForUnit("target")
  if type(plate) ~= "table" then
    Print("debug: no nameplate for the current target")
    return
  end
  local uf = UnitFrameOf(plate)
  if not uf then
    Print("debug: the target's nameplate has no UnitFrame")
    return
  end
  local fs0, field = FindName(uf)
  local unit = PlateUnit(plate)
  Print(string.format("debug: target plate unit %s, name field %s, group member: %s", tostring(unit),
    field and ("UnitFrame." .. field) or "not found", IsMember(unit) and "yes" or "no"))
  Print("debug: " .. FriendText(unit, "target"))
  Print("debug: " .. GuildText(unit, "target"))
  Print("debug: " .. QuestText(unit, "target"))
  -- A quest hostile whose icons could not be told (single chevron): say what its tooltip gave.
  local questInfo = Info(unit)
  if questInfo.questKindSource == "none" or questInfo.questKindSource == "missing"
    or questInfo.questKindSource == "guessed from the quest log" then
    for _, text in ipairs(Core.QuestKindTrace(unitAPI, unit)) do
      Print("debug: " .. text)
    end
    Print("debug: " .. Core.QuestLogSummary(unitAPI))
  end
  Print("debug: " .. PartyQuest.Text(unit, "target"))
  ScaleDebug(plate, uf, fs0)
  Print("debug: " .. ServiceText(unit, "target"))
  Print("debug: " .. ClassText(unit))
  -- Blizzard's name on this plate, and whether ours covers it (enemies without a name: Blizzard's
  -- alpha 0 and "covered: no" would be a fade we failed to give back).
  if fs0 then
    Print(string.format("debug: Blizzard name alpha %s, shown %s, covered by ours: %s, faded names pending: %d",
      tostring(Method(fs0, "GetAlpha")), tostring(Method(fs0, "IsShown")), Covered(uf, fs0) and "yes" or "no",
      PendingNames()))
    if marks[uf] and not Covered(uf, fs0) then
      Print(string.format("debug: marked, but our own name is not drawn: %s (text %s)",
        nameFails[uf] or "reason unknown", Raw(Field(fs0, "GetText"), fs0)))
    end
  end
  Print(string.format("debug: driver hooks: release %s (%d calls), added %s (%d calls); failed name restores: %d",
    driverHooks.release and "on" or "off", driverHooks.releaseCalls, driverHooks.added and "on" or "off",
    driverHooks.addedCalls, restoreFailures))
  HealthDebug(type(unit) == "string" and unit or "target", uf)
  -- The target itself is never compact, so also list what compact mode would hide on it:
  -- that is how the plate's parts on this client can be checked in game.
  local rec = hidden[uf]
  local parts, verb = rec and rec.list, "hidden"
  if not parts then
    parts, verb = CompactParts(uf, uf), "compact would hide"
  end
  Print(string.format("debug: mode %s", Mode(unit)))
  local label = labels[uf]
  if label and label.low then
    -- Compact friendly NPC: which copy of the name FollowBar shows (curve: the client decides).
    Print(string.format("debug: NPC name place %s (low: the health bar's place, high: above it)",
      tostring(label.place or "not set")))
  end
  if not parts then
    Print("debug: compact cannot apply here (no name, or the name is not inside UnitFrame)")
    return
  end
  local tables = { uf }
  local fs = FindName(uf)
  local node = fs and Method(fs, "GetParent")
  for _ = 1, MAX_DEPTH do
    if type(node) ~= "table" or node == uf then
      break
    end
    tables[#tables + 1] = node
    node = Method(node, "GetParent")
  end
  Print(string.format("debug: %s %d part(s)", verb, #parts))
  for _, part in ipairs(parts) do
    Print(string.format("debug:   %s (%s)", PartLabel(part, tables), tostring(Method(part, "GetObjectType") or "?")))
  end
end

-- SlashIcon (/gchev icon [role [name|default]]) lists the role icons, or sets one: a texture path
-- (Interface\Icons\...) or an atlas name the client has; "default" gives the role its own back.
local function SlashIcon(arg)
  local role, name = arg:match("^(%S*)%s*(.-)%s*$")
  role = (role or ""):lower()
  if role == "" then
    for _, r in ipairs(Core.ROLES) do
      local chosen = db.roleicons[r.key]
      Print(string.format("icon %s: %s%s", r.key, IconName(r.key), chosen and " (yours)" or ""))
    end
    Print("/gchev icon <role> <texture or atlas> | /gchev icon <role> default")
    return
  end
  if not Core.ValidRole(role) then
    local keys = {}
    for _, r in ipairs(Core.ROLES) do
      keys[#keys + 1] = r.key
    end
    Print(string.format("unknown role %q: use %s; nothing changed", role, table.concat(keys, " | ")))
    return
  end
  if name == "" then
    Print(string.format("icon %s: %s", role, IconName(role)))
    return
  end
  if name:lower() == "default" then
    db.roleicons[role] = nil
    Changed()
    Print(string.format("icon %s: %s (default)", role, IconName(role)))
    return
  end
  if not Core.ValidIconName(name) then
    Print(string.format("invalid icon %q: use a texture path (Interface\\Icons\\...) or an atlas name; "
      .. "nothing changed", name))
    return
  end
  if not Core.IsTexturePath(name) then
    local known = AtlasKnown(name)
    if known == false then
      Print(string.format("this client has no atlas %q; nothing changed", name))
      return
    elseif known == nil then
      Print("this client cannot check atlas names: use a texture path; nothing changed")
      return
    end
  end
  db.roleicons[role] = name
  Changed()
  Print(string.format("icon %s: %s", role, name))
end

local function Slash(msg)
  msg = type(msg) == "string" and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "classcolour" then
    cmd = "classcolor"
  end
  if cmd == "debug" then
    SlashDebug(arg)
    return
  end
  if cmd == "names" then
    SlashNames()
    return
  end
  if not db then
    Print("not initialised yet")
    return
  end
  if cmd == "options" then
    OpenOptions()
  elseif cmd == "on" or cmd == "off" then
    SetEnabled(cmd)
    Print(db.enabled and "on" or "off")
  elseif cmd == "color" or cmd == "colour" then
    local r, g, b = Core.ParseColor(arg)
    if not r or not SetColor(r, g, b) then
      Print(string.format("invalid colour %q: use #RRGGBB, e.g. /gchev color #FF4FD8; nothing changed", arg or ""))
      return
    end
    Print("colour " .. Core.FormatColor(r, g, b))
  elseif FACTOR_KINDS[cmd] then
    if arg == "" then
      Print(string.format("%s %s (%s to %s, default %s)", cmd, tostring(Factor(cmd)),
        tostring(Core.MinFactor(cmd)), tostring(Core.MaxFactor(cmd)), tostring(Core.DefaultFactor(cmd))))
      return
    end
    if not SetFactor(cmd, arg) then
      Print(string.format("invalid %s %q: use a number from %s to %s, e.g. /gchev %s %s; nothing changed", cmd,
        arg, tostring(Core.MinFactor(cmd)), tostring(Core.MaxFactor(cmd)), cmd,
        Core.MaxFactor(cmd) > 1 and "1.5" or "0.5"))
      return
    end
    Print(string.format("%s %s", cmd, tostring(Factor(cmd))))
  elseif Core.GAP_KINDS[cmd] then
    if arg == "" then
      Print(string.format("%s %d (%d to %d, default %d)", cmd, Gap(cmd), Core.MIN_GAP, Core.MAX_GAP,
        Core.DefaultGap(cmd)))
      return
    end
    if not SetGap(cmd, arg) then
      Print(string.format("invalid %s %q: use a whole number from %d to %d, e.g. /gchev %s 4; nothing changed", cmd,
        arg, Core.MIN_GAP, Core.MAX_GAP, cmd))
      return
    end
    Print(string.format("%s %d", cmd, Gap(cmd)))
  elseif cmd == "font" then
    local keys = {}
    for _, f in ipairs(Core.FONTS) do
      keys[#keys + 1] = f.key
    end
    if arg == "" then
      Print(string.format("font %s (%s)", tostring(db.font), table.concat(keys, " | ")))
      return
    end
    local key = Core.ParseFont(arg)
    if not key or not SetNameFont(key) then
      Print(string.format("invalid font %q: use %s; nothing changed", arg, table.concat(keys, " | ")))
      return
    end
    Print("font " .. key)
  elseif cmd == "friendcolor" or cmd == "friendcolour" then
    if arg == "" then
      Print(string.format("friendcolor %s (default %s)", Core.FormatColor(FriendColor()),
        Core.FormatColor(unpack(Core.DEFAULT_FRIEND_COLOR))))
      return
    end
    local r, g, b = Core.ParseColor(arg)
    if not r or not SetFriendColor(r, g, b) then
      Print(string.format("invalid friendcolor %q: use #RRGGBB, e.g. /gchev friendcolor #3FA7FF; nothing changed", arg))
      return
    end
    Print("friendcolor " .. Core.FormatColor(r, g, b))
  elseif cmd == "guildcolor" or cmd == "guildcolour" then
    if arg == "" then
      Print(string.format("guildcolor %s (default %s)", Core.FormatColor(GuildColor()),
        Core.FormatColor(unpack(Core.DEFAULT_GUILD_COLOR))))
      return
    end
    local r, g, b = Core.ParseColor(arg)
    if not r or not SetGuildColor(r, g, b) then
      Print(string.format("invalid guildcolor %q: use #RRGGBB, e.g. /gchev guildcolor #40FF40; nothing changed", arg))
      return
    end
    Print("guildcolor " .. Core.FormatColor(r, g, b))
  elseif cmd == "hostilecolor" or cmd == "hostilecolour" then
    if arg == "" then
      Print(string.format("hostilecolor %s (default %s)", Core.FormatColor(HostileColor()),
        Core.FormatColor(unpack(Core.DEFAULT_HOSTILE_COLOR))))
      return
    end
    local r, g, b = Core.ParseColor(arg)
    if not r or not SetHostileColor(r, g, b) then
      Print(string.format("invalid hostilecolor %q: use #RRGGBB, e.g. /gchev hostilecolor #FFFF00; nothing changed",
        arg))
      return
    end
    Print("hostilecolor " .. Core.FormatColor(r, g, b))
  elseif cmd == "partyquestcolor" or cmd == "partyquestcolour" then
    if arg == "" then
      Print(string.format("partyquestcolor %s (default %s)", Core.FormatColor(PartyQuest.Color()),
        Core.FormatColor(unpack(Core.DEFAULT_PARTYQUEST_COLOR))))
      return
    end
    local r, g, b = Core.ParseColor(arg)
    if not r or not PartyQuest.SetColor(r, g, b) then
      Print(string.format(
        "invalid partyquestcolor %q: use #RRGGBB, e.g. /gchev partyquestcolor #FFFFFF; nothing changed", arg))
      return
    end
    Print("partyquestcolor " .. Core.FormatColor(r, g, b))
  elseif FLAG_DEFAULTS[cmd] ~= nil then
    if arg == "" then
      Print(string.format("%s %s (on or off, default %s)", cmd, Flag(cmd) and "on" or "off",
        FLAG_DEFAULTS[cmd] and "on" or "off"))
      return
    end
    if not SetFlag(cmd, arg) then
      Print(string.format("invalid %s %q: use /gchev %s on or /gchev %s off; nothing changed", cmd, arg, cmd, cmd))
      return
    end
    Print(string.format("%s %s", cmd, Flag(cmd) and "on" or "off"))
  elseif cmd == "level" then
    if arg == "" then
      Print(string.format("level %s (on or off, default on)", Flag("showlevel") and "on" or "off"))
      return
    end
    if not SetFlag("showlevel", arg) then
      Print(string.format("invalid level %q: use /gchev level on or /gchev level off; nothing changed", arg))
      return
    end
    Print("level " .. (Flag("showlevel") and "on" or "off"))
  elseif cmd == "compact" then
    if arg == "" then
      Print(string.format("compact %s (on or off, default on)", db.compact and "on" or "off"))
      return
    end
    if not SetCompact(arg) then
      Print(string.format("invalid compact %q: use /gchev compact on or /gchev compact off; nothing changed", arg))
      return
    end
    Print("compact " .. (db.compact and "on" or "off"))
  elseif cmd == "icon" or cmd == "icons" then
    SlashIcon(arg)
  elseif cmd == "npcplates" then
    if arg == "" then
      local on = NpcPlates()
      Print(string.format("npcplates %s (the game's friendly NPC nameplates setting)",
        on == nil and "unknown" or (on and "on" or "off")))
      return
    end
    local ok, why = SetNpcPlates(arg)
    if not ok then
      Print(string.format("npcplates %q: %s; nothing changed", arg, NPC_PLATES_REFUSED[why] or tostring(why)))
      return
    end
    Print("npcplates " .. (NpcPlates() and "on" or "off"))
  elseif cmd == "softinteract" then
    if arg == "" then
      local on, raw = SoftInteract.Get()
      Print(string.format("softinteract %s (the game's interaction soft target, %s %s)",
        on == nil and "unknown" or (on and "on" or "off"), SoftInteract.cvar, tostring(raw)))
      return
    end
    local ok, why = SoftInteract.Set(arg)
    if not ok then
      Print(string.format("softinteract %q: %s; nothing changed", arg, SoftInteract.Refused(why)))
      return
    end
    Print("softinteract " .. (SoftInteract.Get() and "on" or "off"))
  elseif cmd == "reset" then
    ResetColor()
    Print("colour reset to " .. Core.FormatColor(Color()))
  else
    SlashStatus()
  end
end

SLASH_GROUPCHEVRON1 = "/gchev"
if type(SlashCmdList) == "table" then
  SlashCmdList.GROUPCHEVRON = function(msg)
    SafeCall("/gchev", Slash, msg)
  end
end
