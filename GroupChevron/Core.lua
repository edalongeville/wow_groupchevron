-- GroupChevron: pure logic (no WoW API).
--
-- This file must not touch any WoW global so it can be unit-tested with busted outside the
-- game (spec/groupchevron_core_spec.lua). In game, it is loaded first by the .toc and
-- publishes itself on the addon's private namespace; outside the game, loading the file
-- returns the module.
--
-- GroupChevron is independent of My Forever Journey: it records nothing and reads nothing of
-- the collector.

local _, ns = ...

local Core = {}

-- DEFAULT_COLOR is #FF4FD8 (magenta pink), as r, g, b in 0..1.
Core.DEFAULT_COLOR = { 255 / 255, 79 / 255, 216 / 255 }
-- DEFAULT_FRIEND_COLOR is #3FA7FF (blue): friends outside the group.
Core.DEFAULT_FRIEND_COLOR = { 63 / 255, 167 / 255, 255 / 255 }
-- DEFAULT_GUILD_COLOR is #40FF40 (guild chat green): guildmates outside the group.
Core.DEFAULT_GUILD_COLOR = { 64 / 255, 255 / 255, 64 / 255 }
-- DEFAULT_HOSTILE_COLOR is #FFFF00 (yellow): hostile units tied to one of the player's quests.
Core.DEFAULT_HOSTILE_COLOR = { 255 / 255, 255 / 255, 0 / 255 }

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isUnit(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- ParseColor parses "#RRGGBB" or "RRGGBB" (hex digits, any case, surrounding spaces ignored)
-- and returns r, g, b in 0..1, or nil for anything else.
function Core.ParseColor(s)
  if type(s) ~= "string" then
    return nil
  end
  local hex = s:match("^%s*#?(%x%x%x%x%x%x)%s*$")
  if not hex then
    return nil
  end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function byte(v)
  if type(v) ~= "number" or v ~= v then
    v = 0
  end
  local n = math.floor(v * 255 + 0.5)
  if n < 0 then
    n = 0
  elseif n > 255 then
    n = 255
  end
  return n
end

-- FormatColor returns "#RRGGBB" (upper case) for r, g, b in 0..1 (clamped; non-numbers count
-- as 0).
function Core.FormatColor(r, g, b)
  return string.format("#%02X%02X%02X", byte(r), byte(g), byte(b))
end

-- CopyDefaultColor returns a new table holding the default colour.
function Core.CopyDefaultColor()
  return { Core.DEFAULT_COLOR[1], Core.DEFAULT_COLOR[2], Core.DEFAULT_COLOR[3] }
end

-- CopyDefaultFriendColor returns a new table holding the default friend colour.
function Core.CopyDefaultFriendColor()
  return { Core.DEFAULT_FRIEND_COLOR[1], Core.DEFAULT_FRIEND_COLOR[2], Core.DEFAULT_FRIEND_COLOR[3] }
end

-- CopyDefaultGuildColor returns a new table holding the default guild colour.
function Core.CopyDefaultGuildColor()
  return { Core.DEFAULT_GUILD_COLOR[1], Core.DEFAULT_GUILD_COLOR[2], Core.DEFAULT_GUILD_COLOR[3] }
end

-- CopyDefaultHostileColor returns a new table holding the default hostile (quest) colour.
function Core.CopyDefaultHostileColor()
  return { Core.DEFAULT_HOSTILE_COLOR[1], Core.DEFAULT_HOSTILE_COLOR[2], Core.DEFAULT_HOSTILE_COLOR[3] }
end

-- ValidColor is true for a table { r, g, b } of numbers in 0..1.
function Core.ValidColor(c)
  return type(c) == "table" and isUnit(c[1]) and isUnit(c[2]) and isUnit(c[3])
end

-- Size factors of the chevron and of the name text: 1 (default) to 3, except the chevron sizes
-- (chevsize, and hostilechevsize for the single chevron of the hostiles), which go up to 5.
Core.MIN_FACTOR = 1
-- The outline thicknesses (memberoutlinesize, friendoutlinesize, guildoutlinesize, hostileoutlinesize)
-- start at 0: no outline.
Core.MIN_FACTORS = { memberoutlinesize = 0, friendoutlinesize = 0, guildoutlinesize = 0, hostileoutlinesize = 0 }
Core.DEFAULT_MAX_FACTOR = 3
Core.MAX_FACTORS = { chevsize = 5, hostilechevsize = 5, memberoutlinesize = 5, friendoutlinesize = 5,
  guildoutlinesize = 5, hostileoutlinesize = 5 }
Core.DEFAULT_FACTOR = 1
-- DEFAULT_FACTORS are the defaults of the kinds that do not start at DEFAULT_FACTOR (1, which
-- also stays the "no scaling" value the plates compare against). The hostiles start where the
-- friendlies do: the chevron at the size the friends' chevron has (chevsize), the text at 1.
Core.DEFAULT_FACTORS = { chevsize = 3, textsize = 1.75, buffsize = 1.1, hostilechevsize = 3, memberoutlinesize = 2,
  friendoutlinesize = 2, guildoutlinesize = 2, hostileoutlinesize = 2 }

-- DefaultFactor is the default of a factor kind: its DEFAULT_FACTORS entry, else DEFAULT_FACTOR.
function Core.DefaultFactor(kind)
  return Core.DEFAULT_FACTORS[kind] or Core.DEFAULT_FACTOR
end

-- MaxFactor is the largest accepted value of a factor kind (3 for every other or nil kind).
function Core.MaxFactor(kind)
  return Core.MAX_FACTORS[kind] or Core.DEFAULT_MAX_FACTOR
end

-- MinFactor is the smallest accepted value of a factor kind (MIN_FACTOR for every other or nil kind).
function Core.MinFactor(kind)
  return Core.MIN_FACTORS[kind] or Core.MIN_FACTOR
end

-- ValidFactor is true for a finite number from MinFactor(kind) to MaxFactor(kind).
function Core.ValidFactor(v, kind)
  return type(v) == "number" and v == v and v >= Core.MinFactor(kind) and v <= Core.MaxFactor(kind)
end

-- ParseFactor parses a decimal number such as "1", "3" or "1.25" (surrounding spaces ignored)
-- and returns it when it is within MinFactor(kind)..MaxFactor(kind). Anything else (text, empty, hex,
-- exponent, out of range) returns nil: there is no clamping.
function Core.ParseFactor(s, kind)
  if type(s) ~= "string" then
    return nil
  end
  local text = s:match("^%s*(%d+%.?%d*)%s*$")
  local n = text and tonumber(text)
  if Core.ValidFactor(n, kind) then
    return n
  end
  return nil
end

-- SnapFactor rounds a slider value to the 0.05 step and returns it when it is a valid factor,
-- else nil (so float noise such as 1.2000000001 is saved as 1.2).
function Core.SnapFactor(v, kind)
  if type(v) ~= "number" or v ~= v then
    return nil
  end
  local snapped = math.floor(v * 20 + 0.5) / 20
  if Core.ValidFactor(snapped, kind) then
    return snapped
  end
  return nil
end

-- Name gaps: how far up (positive) or down (negative) our name label sits from where Blizzard
-- puts its name above the health bar, in whole UI points (the parent's units, not scaled by the
-- text size): "namegap" for group members, "othernamegap" for other friendly players (compact
-- or not, the target included, like othersize), "hostilenamegap" for the hostiles tied to a
-- quest. 0 is the layout without a gap (NO_GAP); the default of every kind is DEFAULT_GAP.
Core.MIN_GAP = -10
Core.MAX_GAP = 40
Core.NO_GAP = 0
Core.DEFAULT_GAP = 5
Core.GAP_KINDS = { namegap = true, othernamegap = true, hostilenamegap = true }

-- DefaultGap is the default of a gap kind.
function Core.DefaultGap(_)
  return Core.DEFAULT_GAP
end

-- ValidGap is true for a whole number from MIN_GAP to MAX_GAP.
function Core.ValidGap(v)
  return type(v) == "number" and v == v and v == math.floor(v) and v >= Core.MIN_GAP and v <= Core.MAX_GAP
end

-- ParseGap parses a whole number such as "4", "-3" or "+2" (surrounding spaces ignored) and
-- returns it when it is within MIN_GAP..MAX_GAP. Anything else (decimals, text, empty, out of
-- range) returns nil: there is no clamping.
function Core.ParseGap(s)
  if type(s) ~= "string" then
    return nil
  end
  local text = s:match("^%s*([+-]?%d+)%s*$")
  local n = text and tonumber((text:gsub("^%+", "")))
  if Core.ValidGap(n) then
    return n
  end
  return nil
end

-- SnapGap rounds a slider value to the nearest whole point and returns it when it is a valid
-- gap, else nil.
function Core.SnapGap(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    return nil
  end
  local snapped = math.floor(v + 0.5)
  if Core.ValidGap(snapped) then
    return snapped
  end
  return nil
end

-- NameOffset returns the y offset of our name label's anchor, in its own frame's units (the
-- frame is scaled by size): (lift + gap) / size, lift and gap in the parent's units. A lift or
-- gap that is not a finite number counts as 0, a size that is not a positive finite number as 1.
function Core.NameOffset(lift, gap, size)
  if not finite(lift) then
    lift = 0
  end
  if not finite(gap) then
    gap = 0
  end
  if not finite(size) or size <= 0 then
    size = 1
  end
  return (lift + gap) / size
end

-- FONTS are the fonts offered for the addon's own name labels, in menu order: key (saved in
-- db.font and used by /gchev font), label, and the name of a global font object of the client
-- (nil for "default": Blizzard's own name font, as before). Font objects, not file paths, so
-- the client's alphabet fallbacks (Cyrillic, Korean, Chinese) stay on our label.
Core.DEFAULT_FONT = "outline"
Core.FONTS = {
  { key = "default", label = "Blizzard's name font" },
  { key = "outline", label = "System (outline)", object = "SystemFont_Outline" },
  { key = "chat", label = "Chat", object = "ChatFontNormal" },
  { key = "large", label = "Large", object = "GameFontNormalLarge" },
  { key = "game13", label = "Game 13 (outline)", object = "Game13Font_o1" },
}

-- FindFont returns the FONTS entry of key, or nil.
function Core.FindFont(key)
  if type(key) == "string" then
    for _, f in ipairs(Core.FONTS) do
      if f.key == key then
        return f
      end
    end
  end
  return nil
end

-- ValidFont is true for the key of one of FONTS.
function Core.ValidFont(key)
  return Core.FindFont(key) ~= nil
end

-- ParseFont returns the key typed by the player (case and surrounding spaces ignored) when it
-- is one of FONTS, else nil.
function Core.ParseFont(s)
  if type(s) ~= "string" then
    return nil
  end
  local key = s:match("^%s*(%S+)%s*$")
  key = key and key:lower()
  return Core.ValidFont(key) and key or nil
end

-- NextFont returns the key after key in FONTS (the first after the last or an unknown key).
function Core.NextFont(key)
  for i, f in ipairs(Core.FONTS) do
    if f.key == key then
      return Core.FONTS[i % #Core.FONTS + 1].key
    end
  end
  return Core.FONTS[1].key
end

-- Locales are the texts of the options panel by client locale (GetLocale()). enUS is the
-- reference and the fallback: a key missing from another locale shows the English text. The
-- addon name "GroupChevron" and the font names are not translated.
Core.Locales = {
  enUS = {
    enabled = "Enabled",
    group_members = "Group members",
    friendlies = "Friendlies (friendly players outside your group)",
    friends = "Friends (on your friends list, outside your group)",
    guildmates = "Guildmates (in your guild, outside your group)",
    hostiles = "Quest hostiles (enemies tied to your quests)",
    outline_size = "Outline",
    compact = "Compact plates (name only)",
    name_colour = "Name colour",
    name_font = "Name font",
    chevron_size = "Chevron size",
    text_size = "Text size",
    bar_size = "Health bar size",
    buffs_size = "Buffs size",
    name_gap = "Name height",
    reset = "Reset to defaults",
    show_chevron = "Show chevron",
    bnet_friends = "Include Battle.net friends",
    class_colour = "Class colour",
    show_level = "Show level",
  },
  frFR = {
    enabled = "Activé",
    group_members = "Membres du groupe",
    friendlies = "Joueurs amicaux (hors de votre groupe)",
    friends = "Amis (sur votre liste d'amis, hors de votre groupe)",
    guildmates = "Membres de la guilde (hors de votre groupe)",
    hostiles = "Ennemis de quête (liés à vos quêtes)",
    outline_size = "Contour",
    compact = "Plaques compactes (nom seul)",
    name_colour = "Couleur du nom",
    name_font = "Police du nom",
    chevron_size = "Taille du chevron",
    text_size = "Taille du texte",
    bar_size = "Taille barre de vie",
    buffs_size = "Taille des effets",
    name_gap = "Hauteur du nom",
    reset = "Réinitialiser",
    show_chevron = "Afficher chevron",
    bnet_friends = "Inclure les amis Battle.net",
    class_colour = "Couleur de classe",
    show_level = "Afficher le niveau",
  },
}
Core.Locales.enGB = Core.Locales.enUS

-- Translate returns the text of key in locale, else its English text, else key itself. It
-- never errors, whatever locale and key are.
function Core.Translate(locale, key)
  local set = type(locale) == "string" and Core.Locales[locale] or nil
  local text = set and set[key]
  if type(text) ~= "string" then
    text = Core.Locales.enUS[key]
  end
  if type(text) ~= "string" then
    return tostring(key)
  end
  return text
end

-- DEFAULT_CLASSCOLOR is the default of the class colour setting (on).
Core.DEFAULT_CLASSCOLOR = true

-- InitDB fills the defaults of the saved settings in place and returns db (a new table when
-- db is not a table). Invalid values are replaced by their default.
function Core.InitDB(db)
  if type(db) ~= "table" then
    db = {}
  end
  for _, key in ipairs({ "chevsize", "textsize", "othersize", "barsize", "buffsize", "otherbarsize",
    "hostilechevsize", "hostilesize", "memberoutlinesize", "friendoutlinesize", "guildoutlinesize",
    "hostileoutlinesize" }) do
    if not Core.ValidFactor(db[key], key) then
      db[key] = Core.DefaultFactor(key)
    end
  end
  for _, key in ipairs({ "namegap", "othernamegap", "hostilenamegap" }) do
    if not Core.ValidGap(db[key]) then
      db[key] = Core.DefaultGap(key)
    end
  end
  if not Core.ValidFont(db.font) then
    db.font = Core.DEFAULT_FONT
  end
  if type(db.enabled) ~= "boolean" then
    db.enabled = true
  end
  if type(db.compact) ~= "boolean" then
    db.compact = true
  end
  if not Core.ValidColor(db.color) then
    db.color = Core.CopyDefaultColor()
  else
    db.color = { db.color[1], db.color[2], db.color[3] }
  end
  if not Core.ValidColor(db.friendcolor) then
    db.friendcolor = Core.CopyDefaultFriendColor()
  else
    db.friendcolor = { db.friendcolor[1], db.friendcolor[2], db.friendcolor[3] }
  end
  if not Core.ValidColor(db.guildcolor) then
    db.guildcolor = Core.CopyDefaultGuildColor()
  else
    db.guildcolor = { db.guildcolor[1], db.guildcolor[2], db.guildcolor[3] }
  end
  if not Core.ValidColor(db.hostilecolor) then
    db.hostilecolor = Core.CopyDefaultHostileColor()
  else
    db.hostilecolor = { db.hostilecolor[1], db.hostilecolor[2], db.hostilecolor[3] }
  end
  for _, key in ipairs({ "friendchevron", "bnetfriends", "guildchevron", "showlevel" }) do
    if type(db[key]) ~= "boolean" then
      db[key] = true
    end
  end
  if type(db.classcolor) ~= "boolean" then
    db.classcolor = Core.DEFAULT_CLASSCOLOR
  end
  return db
end

-- isSecret is true when api.issecretvalue flags v (or fails on it).
local function isSecret(api, v)
  local check = api.issecretvalue
  if type(check) ~= "function" then
    return false
  end
  local ok, secret = pcall(check, v)
  return not ok or secret and true or false
end

-- call runs api[name](...) under pcall. It returns the first result, or nil when the
-- function is missing, raises an error or returns a secret value.
local function call(api, name, ...)
  local fn = api[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(api, v) then
    return nil
  end
  return v
end

-- IsGroupMember is true when unit is another player in the player's party or raid. api
-- holds the injected WoW functions UnitIsPlayer, UnitInParty, UnitInRaid, UnitIsUnit and,
-- optionally, issecretvalue. A missing function, an error or a secret value counts as "no",
-- so the plate keeps its default look.
function Core.IsGroupMember(api, unit)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return false
  end
  if not call(api, "UnitIsPlayer", unit) then
    return false
  end
  -- Without UnitIsUnit the player cannot be told apart: no.
  if type(api.UnitIsUnit) ~= "function" then
    return false
  end
  local ok, self = pcall(api.UnitIsUnit, unit, "player")
  if not ok or isSecret(api, self) or self then
    return false
  end
  if call(api, "UnitInParty", unit) or call(api, "UnitInRaid", unit) then
    return true
  end
  return false
end

-- ParseOnOff parses "on" or "off" (any case, surrounding spaces ignored) and returns true or
-- false; anything else returns nil.
function Core.ParseOnOff(s)
  if type(s) ~= "string" then
    return nil
  end
  local word = s:match("^%s*(%a+)%s*$")
  word = word and word:lower()
  if word == "on" then
    return true
  elseif word == "off" then
    return false
  end
  return nil
end

-- known calls api[name](...) under pcall. It returns true and the truthiness of the first
-- result, or false when the function is missing, raises an error or returns a secret value
-- (the answer is unknown).
local function known(api, name, ...)
  local fn = api[name]
  if type(fn) ~= "function" then
    return false
  end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(api, v) then
    return false
  end
  return true, v and true or false
end

-- FriendLookup tells whether guid is a friend of the player: on the character friends list
-- (api.IsFriend(guid) == true, i.e. C_FriendList.IsFriend) or, only when bnet is true, the
-- character of a Battle.net friend (api.GetAccountInfoByGUID(guid) is a table whose isFriend
-- is true). It returns the answer and its source:
--   "list"    : on the character friends list;
--   "bnet"    : a Battle.net friend's character;
--   "none"    : not a friend (also when an API raises an error or returns a secret value);
--   "noguid"  : no readable GUID (not a friend);
--   "missing" : none of the APIs to ask exists on this client (not a friend).
-- Anything unknown counts as "not a friend".
function Core.FriendLookup(api, guid, bnet)
  if type(api) ~= "table" then
    return false, "missing"
  end
  local hasList = type(api.IsFriend) == "function"
  local hasBNet = bnet == true and type(api.GetAccountInfoByGUID) == "function"
  if not hasList and not hasBNet then
    return false, "missing"
  end
  if type(guid) ~= "string" or isSecret(api, guid) or guid == "" then
    return false, "noguid"
  end
  if hasList and call(api, "IsFriend", guid) == true then
    return true, "list"
  end
  if hasBNet then
    local account = call(api, "GetAccountInfoByGUID", guid)
    if type(account) == "table" then
      local ok, v = pcall(function() return account.isFriend end)
      if ok and not isSecret(api, v) and v == true then
        return true, "bnet"
      end
    end
  end
  return false, "none"
end

-- GuildLookup tells whether unit is in the player's guild. Only when api.IsInGuild() is true
-- (otherwise no guild API is called) it asks api.UnitIsInMyGuild(unit) and, when that function
-- does not exist, api.IsPlayerInGuildFromGUID(guid). It returns the answer and its source:
--   "unit"    : UnitIsInMyGuild answered;
--   "guid"    : IsPlayerInGuildFromGUID answered;
--   "none"    : not a guildmate (also when an API raises an error or returns a secret value);
--   "noguild" : the player is not in a guild (or that is unknown): nobody is a guildmate;
--   "noguid"  : only the GUID API exists and there is no readable GUID;
--   "missing" : none of the APIs to ask exists on this client.
-- Anything unknown counts as "not a guildmate".
function Core.GuildLookup(api, unit, guid)
  if type(api) ~= "table" then
    return false, "missing"
  end
  if call(api, "IsInGuild") ~= true then
    return false, "noguild"
  end
  if type(api.UnitIsInMyGuild) == "function" then
    if type(unit) == "string" and unit ~= "" and not isSecret(api, unit)
      and call(api, "UnitIsInMyGuild", unit) == true then
      return true, "unit"
    end
    return false, "none"
  end
  if type(api.IsPlayerInGuildFromGUID) == "function" then
    if type(guid) ~= "string" or isSecret(api, guid) or guid == "" then
      return false, "noguid"
    end
    if call(api, "IsPlayerInGuildFromGUID", guid) == true then
      return true, "guid"
    end
    return false, "none"
  end
  return false, "missing"
end

-- QuestLookup tells whether unit is tied to one of the player's active quests (an enemy to kill,
-- one that drops a quest item, an object to use, ...): api.IsRelatedToActiveQuest(unit), i.e.
-- C_QuestLog.UnitIsRelatedToActiveQuest. It returns the answer and its source:
--   "unit"    : the API answered true;
--   "none"    : not tied to a quest (also when the API raises an error or returns a secret value);
--   "missing" : the API does not exist on this client.
-- Anything unknown counts as "not tied to a quest".
function Core.QuestLookup(api, unit)
  if type(api) ~= "table" or type(api.IsRelatedToActiveQuest) ~= "function" then
    return false, "missing"
  end
  if type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return false, "none"
  end
  if call(api, "IsRelatedToActiveQuest", unit) == true then
    return true, "unit"
  end
  return false, "none"
end

-- readRGB returns the r, g, b (numbers in 0..1, none secret) of a class colour c: a ColorMixin
-- (c:GetRGB()) or a table with fields r, g, b (RAID_CLASS_COLORS), or nil.
local function readRGB(api, c)
  if type(c) ~= "table" then
    return nil
  end
  local function valid(ok, r, g, b)
    if ok and isUnit(r) and isUnit(g) and isUnit(b) and not isSecret(api, r) and not isSecret(api, g)
      and not isSecret(api, b) then
      return r, g, b
    end
    return nil
  end
  local r, g, b = valid(pcall(function() return c:GetRGB() end))
  if r then
    return r, g, b
  end
  return valid(pcall(function() return c.r, c.g, c.b end))
end

-- ClassColor returns the class token of unit (the second result of api.UnitClass, e.g.
-- "MAGE") and its colour r, g, b in 0..1: api.GetClassColor(token) (C_ClassColor, a
-- ColorMixin), else api.RAID_CLASS_COLORS[token] (.r/.g/.b). The token is nil when it cannot
-- be read; r, g, b are nil when no colour is known (missing function or table, error, secret
-- value, unknown token). The colours are always the client's own, never a table of ours.
function Core.ClassColor(api, unit)
  if type(api) ~= "table" or type(unit) ~= "string" or isSecret(api, unit) or unit == "" then
    return nil
  end
  local fn = api.UnitClass
  if type(fn) ~= "function" then
    return nil
  end
  local ok, _, token = pcall(fn, unit)
  if not ok or type(token) ~= "string" or isSecret(api, token) or token == "" then
    return nil
  end
  local r, g, b = readRGB(api, call(api, "GetClassColor", token))
  if r then
    return token, r, g, b
  end
  local colors = api.RAID_CLASS_COLORS
  if type(colors) == "table" then
    local okColor, c = pcall(function() return colors[token] end)
    if okColor and not isSecret(api, c) then
      r, g, b = readRGB(api, c)
      if r then
        return token, r, g, b
      end
    end
  end
  return token
end

-- UnitInfo gathers what PlateMode needs about unit. api holds the injected WoW functions of
-- IsGroupMember plus UnitIsFriend, UnitCanAttack, UnitGUID and those of FriendLookup,
-- GuildLookup, QuestLookup and ClassColor. Each of member, player, self (the unit is the player),
-- friend (UnitIsFriend("player", unit)), attackable (UnitCanAttack("player", unit): hostile and
-- neutral units alike) and target (UnitIsUnit(unit, "target")) is true, false or nil (unknown:
-- missing function, error or secret value). quest is true only for an attackable unit that
-- QuestLookup says is tied to an active quest, and questSource is its source ("skipped" when the
-- unit is not known to be attackable: the quest API is then not asked). listed is true only when FriendLookup says
-- the unit's GUID is a friend (Battle.net friends only with settings.bnetfriends), and source is
-- its source; guild and guildSource are GuildLookup's answer and source. Only with
-- settings.classcolor: class is the class token and classColor { r, g, b } its colour (nil
-- when unknown); without the setting the class is never asked.
function Core.UnitInfo(api, unit, settings)
  local info = { listed = false, source = "missing", guild = false, guildSource = "missing", quest = false,
    questSource = "skipped" }
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return info
  end
  local ok, v = known(api, "UnitIsPlayer", unit)
  if ok then
    info.player = v
  end
  ok, v = known(api, "UnitIsUnit", unit, "player")
  if ok then
    info.self = v
  end
  ok, v = known(api, "UnitIsUnit", unit, "target")
  if ok then
    info.target = v
  end
  ok, v = known(api, "UnitIsFriend", "player", unit)
  if ok then
    info.friend = v
  end
  ok, v = known(api, "UnitCanAttack", "player", unit)
  if ok then
    info.attackable = v
  end
  if info.attackable == true then
    info.quest, info.questSource = Core.QuestLookup(api, unit)
  end
  if Core.IsGroupMember(api, unit) then
    info.member = true
  else
    -- "Not a member" only when every answer behind it is known; an unknown membership must
    -- never make a member's plate compact.
    local okParty = known(api, "UnitInParty", unit)
    local okRaid = known(api, "UnitInRaid", unit)
    local allKnown = info.player ~= nil and info.self ~= nil and okParty and okRaid
    if info.player == false or info.self == true or allKnown then
      info.member = false
    end
  end
  local bnet = type(settings) == "table" and settings.bnetfriends == true
  local guid = call(api, "UnitGUID", unit)
  info.listed, info.source = Core.FriendLookup(api, guid, bnet)
  info.guild, info.guildSource = Core.GuildLookup(api, unit, guid)
  if type(settings) == "table" and settings.classcolor == true then
    local token, r, g, b = Core.ClassColor(api, unit)
    info.class = token
    if r then
      info.classColor = { r, g, b }
    end
  end
  return info
end

-- friendly is true when info (see UnitInfo) is known to be a friendly player who is neither a
-- group member nor the player (exact booleans only).
local function friendly(info)
  return info.member == false and info.player == true and info.self == false and info.friend == true
end

-- QuestHostile is true when the plate of the unit described by info (see UnitInfo) is a unit the
-- player can attack that is tied to one of the player's active quests, and the addon is on
-- (settings.enabled). Only exact boolean answers count.
function Core.QuestHostile(info, settings)
  if type(info) ~= "table" or type(settings) ~= "table" or settings.enabled ~= true then
    return false
  end
  return info.attackable == true and info.self ~= true and info.quest == true
end

-- Relation returns how the player relates to the unit described by info (see UnitInfo), in
-- priority order: "member" (group member), "friend" (a friendly player on the friends list,
-- not a member, not the player; a Battle.net friend only with settings.bnetfriends), or nil.
-- Only exact boolean answers count. A lower relation (e.g. guildmates) goes after "friend".
function Core.Relation(info, settings)
  if type(info) ~= "table" then
    return nil
  end
  if info.member == true then
    return "member"
  end
  local bnetOK = info.source ~= "bnet" or (type(settings) == "table" and settings.bnetfriends == true)
  if friendly(info) and info.listed == true and bnetOK then
    return "friend"
  end
  if info.member == false and info.player == true and info.self == false and info.friend == true
    and info.guild == true then
    return "guild"
  end
  return nil
end

-- NameColor returns which colour the name of the plate described by info (see UnitInfo) gets,
-- from its relation (see Relation) and settings, in priority order:
--   "member" : the member colour (relation "member"; the class colour never applies);
--   "friend" : the friend colour (relation "friend");
--   "guild"  : the guild colour (relation "guild": a guildmate who is not a friend);
--   "class"  : the class colour info.classColor: settings.enabled and settings.classcolor
--              are on, the unit is a friendly player who is neither a member nor the player
--              (target or not, compact or not), and its class colour is known;
--   nil      : Blizzard's colour.
function Core.NameColor(info, settings, relation)
  if relation == "member" or relation == "friend" or relation == "guild" then
    return relation
  end
  if type(info) == "table" and type(settings) == "table" and settings.enabled == true
    and settings.classcolor == true and friendly(info) and Core.ValidColor(info.classColor) then
    return "class"
  end
  return nil
end

-- PlateMode decides how a nameplate is drawn, from info (see UnitInfo) and settings (the
-- saved db: enabled, compact, bnetfriends, classcolor). It returns the mode and the relation
-- (see Relation; nil when the plate is not marked):
--   "member"  : a group member: pink name and chevron, full plate (relation "member");
--   "friend"  : a friend outside the group who is the target, or any friend with compact off:
--               full plate, name in the friend colour, optional chevron (relation "friend");
--   "compact" : a friendly player who is not a member, not the player and not the current
--               target, with compact on: name only (relation "friend" for a friend: the name
--               in the friend colour with the optional chevron, else nil: the name in the
--               class colour when NameColor says "class", else in Blizzard's);
--   "class"   : another friendly player (not a friend) who is the target, or any with compact
--               off, whose name gets the class colour (NameColor "class"): full plate, name in
--               the class colour, no chevron (relation nil);
--   "quest"   : a hostile (attackable) unit tied to one of the player's active quests
--               (QuestHostile): full plate, name in the hostile colour, single chevron; no
--               relation (nil). Such a unit is never a member, friend or friendly player.
--   "default" : everything else (addon off, compact off, other enemies, NPCs, the target,
--               anything unknown): the plate as the game draws it.
-- Only the exact boolean answers count, so an unknown or secret value gives "default" (or, for
-- a friend whose target state is unknown, the full "friend" plate: never compact).
function Core.PlateMode(info, settings)
  if type(info) ~= "table" or type(settings) ~= "table" or settings.enabled ~= true then
    return "default", nil
  end
  if Core.QuestHostile(info, settings) then
    return "quest", nil
  end
  local relation = Core.Relation(info, settings)
  if relation == "member" then
    return "member", relation
  end
  if relation == "friend" or relation == "guild" then
    if settings.compact == true and info.target == false then
      return "compact", relation
    end
    return "friend", relation
  end
  if not friendly(info) then
    return "default", nil
  end
  if settings.compact == true and info.target == false then
    return "compact", nil
  end
  if Core.NameColor(info, settings, nil) == "class" then
    return "class", nil
  end
  return "default", nil
end

-- ShowsLevel is true when the plate of the unit described by info (see UnitInfo) shows the
-- unit's level after its name: the addon is on, settings.showlevel is not false, and the unit is
-- a friendly player (friends included) who is known not to be a group member and not the
-- player. Only exact boolean answers count. The caller shows it on compact plates only, and only
-- while their health bar is hidden (LevelSuffix): a full plate's bar shows Blizzard's level.
function Core.ShowsLevel(info, settings)
  if type(info) ~= "table" or type(settings) ~= "table" or settings.enabled ~= true
    or settings.showlevel == false then
    return false
  end
  return info.member == false and info.player == true and info.self == false and info.friend == true
end

-- OtherSizes is true when the friendlies' sizes (othersize for the name, otherbarsize for the
-- health bar) apply to the plate of the unit described by info (see UnitInfo): the addon is on
-- and the unit is a friendly player (friends, guildmates and class-coloured players included)
-- who is known not to be a group member and not the player. Compact mode and the target state
-- do not matter, so the name keeps its size when the player is targeted or untargeted. Only
-- exact boolean answers count.
function Core.OtherSizes(info, settings)
  if type(info) ~= "table" or type(settings) ~= "table" or settings.enabled ~= true then
    return false
  end
  return friendly(info)
end

-- UnitLevel returns api.UnitLevel(unit) when it is a readable integer number other than 0, else
-- nil (missing function, error, secret value, non-number, NaN, fraction or 0: the level is not
-- readable). -1 or less means "unknown to the client" (e.g. a much higher level) and is kept.
function Core.UnitLevel(api, unit)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return nil
  end
  local level = call(api, "UnitLevel", unit)
  if not finite(level) or level == 0 or level ~= math.floor(level) then
    return nil
  end
  return level
end

-- NameWithLevel returns "<name> (<level>)" for a level of 1 or more, "<name> (??)" for -1 or
-- less (unknown to the client), and name alone for anything else (nil, non-number, NaN, 0,
-- fraction: not readable). A name that is not a non-empty string is returned as it is.
function Core.NameWithLevel(name, level)
  if type(name) ~= "string" or name == "" or not finite(level) or level ~= math.floor(level) then
    return name
  end
  if level >= 1 then
    return string.format("%s (%d)", name, level)
  elseif level <= -1 then
    return name .. " (??)"
  end
  return name
end

-- HealthMissing is true when unit's health is known to be below its maximum
-- (UnitHealth < UnitHealthMax, both readable numbers, max > 0). Full health, a dead unit
-- (health 0 still counts as missing), a missing function, an error or a secret value give
-- false: an unknown health keeps compact mode's name-only plate.
function Core.HealthMissing(api, unit)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return false
  end
  local hp, max = call(api, "UnitHealth", unit), call(api, "UnitHealthMax", unit)
  if type(hp) ~= "number" or type(max) ~= "number" or hp ~= hp or max ~= max or max <= 0 then
    return false
  end
  return hp < max
end

-- HEALTH_CURVE_POINTS are the points (health fraction, alpha) of the colour curve that turns a
-- unit's health into the alpha of its health bar: 1 (shown) below full health, 0 at full health.
Core.HEALTH_CURVE_POINTS = { { 0, 1 }, { 0.999, 1 }, { 1, 0 } }

-- FULL_HEALTH_CURVE_POINTS are the opposite curve: alpha 0 below full health, 1 at full health.
-- It drives the name with the "(level)" suffix on a compact plate, which is shown only while the
-- health bar (and Blizzard's level beside it) is hidden.
Core.FULL_HEALTH_CURVE_POINTS = { { 0, 0 }, { 0.999, 0 }, { 1, 1 } }

-- HealthCurve builds the colour curve of points (default HEALTH_CURVE_POINTS; white, the alpha
-- of each point) with api.CreateColorCurve() (C_CurveUtil.CreateColorCurve) and
-- api.CreateColor(r, g, b, a), and returns it, or nil when either function is missing, raises an
-- error or returns nothing usable.
function Core.HealthCurve(api, points)
  points = points or Core.HEALTH_CURVE_POINTS
  if type(api) ~= "table" or type(api.CreateColorCurve) ~= "function" or type(api.CreateColor) ~= "function" then
    return nil
  end
  local ok, curve = pcall(api.CreateColorCurve)
  if not ok or isSecret(api, curve) then
    return nil
  end
  local kind = type(curve)
  if kind ~= "table" and kind ~= "userdata" then
    return nil
  end
  for _, p in ipairs(points) do
    local okColor, color = pcall(api.CreateColor, 1, 1, 1, p[2])
    if not okColor or color == nil or isSecret(api, color) then
      return nil
    end
    if not pcall(function() curve:AddPoint(p[1], color) end) then
      return nil
    end
  end
  return curve
end

-- HealthAlpha evaluates curve (see HealthCurve) at unit's health with
-- api.UnitHealthPercent(unit, false, curve) and returns true and the colour's alpha (GetRGBA's
-- 4th value), or false when the function is missing, raises an error or returns no colour. The
-- alpha may be a secret value: it is never read, compared, used in arithmetic or as a key here,
-- only returned, for the caller to hand straight to SetAlpha (under pcall).
function Core.HealthAlpha(api, unit, curve)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) or curve == nil
    or type(api.UnitHealthPercent) ~= "function" then
    return false
  end
  local ok, color = pcall(api.UnitHealthPercent, unit, false, curve)
  if not ok or isSecret(api, color) then
    return false
  end
  local kind = type(color)
  if kind ~= "table" and kind ~= "userdata" then
    return false
  end
  local okRGBA, _, _, _, alpha = pcall(function() return color:GetRGBA() end)
  if not okRGBA then
    return false
  end
  return true, alpha
end

-- LevelSuffix says how the "(level)" after the name of a compact plate follows its health bar
-- (Blizzard's bar shows the level beside it, so the suffix is dropped while the bar is shown):
--   "curve" : the bar's alpha comes from the health curve (curve true) and was applied to every
--             health bar part (barDriven true): the alpha may be secret, so the name with the
--             level and the name alone are both drawn and driven by the client's curves;
--   "hide"  : no curve, and the bar is known shown (hurt true, Core.HealthMissing): name alone;
--   "show"  : anything else (the bar is hidden, or its state is unknown): in doubt the suffix
--             stays.
-- Full plates never get the suffix: their bar is always shown (not asked here).
function Core.LevelSuffix(curve, barDriven, hurt)
  if curve == true then
    return barDriven == true and "curve" or "show"
  end
  if hurt == true then
    return "hide"
  end
  return "show"
end

if type(ns) == "table" then
  ns.Core = Core
end

-- BarOffsets returns the anchor offsets (x of the left anchor, x of the right anchor, y of both)
-- that make Blizzard's health bar f times its size about its centre, its bottom where Blizzard
-- put it. Blizzard stretches the bar between the left and right top corners of the cast bar
-- container (y = spacing), so SetScale alone only made it taller: width is the content width
-- (nameplate width minus both insets, the parent's units), scale the bar's own scale before
-- ours. Offsets are in the bar's own units once its scale is scale x f, hence the division.
-- nil for invalid input.
function Core.BarOffsets(width, spacing, scale, f)
  if not finite(width) or width <= 0 or not finite(spacing) or not finite(scale) or scale <= 0
    or not finite(f) or f <= 0 then
    return nil
  end
  local s = scale * f
  local dx = width * (f - 1) / 2
  return -dx / s, dx / s, spacing / f
end

-- BuffLift returns how far up (the parent's units) the name must move so the buffs, grown f
-- times about their middle on the left of the bar, do not reach it: half of what one icon
-- gains (itemHeight x itemScale x baseScale is its height before). 0 when f <= 1 or the input
-- is invalid.
function Core.BuffLift(itemHeight, itemScale, baseScale, f)
  if not finite(itemHeight) or itemHeight <= 0 or not finite(itemScale) or itemScale <= 0
    or not finite(baseScale) or baseScale <= 0 or not finite(f) or f <= 1 then
    return 0
  end
  return itemHeight * itemScale * baseScale * (f - 1) / 2
end

return Core
