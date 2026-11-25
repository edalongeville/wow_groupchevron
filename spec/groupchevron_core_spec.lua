-- Unit tests for GroupChevron/Core.lua (run from the repo root: busted --lua=lua5.1 spec).

local Core = dofile("GroupChevron/Core.lua")

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

-- fakeAPI returns the injected unit API for a world where members[unit] is the group
-- membership ("party", "raid" or nil), players[unit] says whether unit is a player and
-- "player" is the user.
local function fakeAPI(players, members)
  return {
    UnitIsPlayer = function(unit) return players[unit] == true end,
    UnitInParty = function(unit) return members[unit] == "party" or unit == "player" end,
    UnitInRaid = function(unit)
      if members[unit] == "raid" then
        return 3
      end
      return nil
    end,
    UnitIsUnit = function(a, b) return a == b end,
    issecretvalue = function(v) return v == SECRET end,
  }
end

describe("GroupChevron Core", function()
  describe("ParseColor / FormatColor", function()
    it("parses #RRGGBB and RRGGBB in any case", function()
      local r, g, b = Core.ParseColor("#FF4FD8")
      assert.are.equal(1, r)
      assert.are.equal(79 / 255, g)
      assert.are.equal(216 / 255, b)
      assert.are.same({ Core.ParseColor("ff4fd8") }, { r, g, b })
      assert.are.same({ Core.ParseColor("  #Ff4fD8 ") }, { r, g, b })
      assert.are.same({ 0, 0, 0 }, { Core.ParseColor("#000000") })
    end)

    it("round-trips", function()
      for _, s in ipairs({ "#FF4FD8", "#000000", "#FFFFFF", "#0A1B2C", "#7F8081" }) do
        assert.are.equal(s, Core.FormatColor(Core.ParseColor(s)))
      end
      assert.are.equal("#FF4FD8", Core.FormatColor(Core.ParseColor("ff4fd8")))
    end)

    it("refuses bad inputs", function()
      for _, s in ipairs({ "", "#", "#FFF", "FF4FD", "#FF4FD8F", "#GG4FD8", "##FF4FD8", "pink", "FF 4F D8",
        "#FF4FD8;", "0xFF4FD8" }) do
        assert.is_nil(Core.ParseColor(s), s)
      end
      assert.is_nil(Core.ParseColor(nil))
      assert.is_nil(Core.ParseColor(0xFF4FD8))
      assert.is_nil(Core.ParseColor({}))
    end)

    it("formats clamped and rounded values", function()
      assert.are.equal("#FF0000", Core.FormatColor(2, -1, 0))
      assert.are.equal("#000000", Core.FormatColor(nil, "x", 0 / 0))
      assert.are.equal("#FF4FD8", Core.FormatColor(unpack(Core.DEFAULT_COLOR)))
    end)
  end)

  describe("SnapFactor", function()
    it("rounds to the 0.05 step and refuses invalid values", function()
      assert.are.equal(1.2, Core.SnapFactor(1.2000000001))
      assert.are.equal(1, Core.SnapFactor(1))
      assert.are.equal(3, Core.SnapFactor(3))
      assert.is_nil(Core.SnapFactor(3.2))
      assert.is_nil(Core.SnapFactor(0.9))
      assert.is_nil(Core.SnapFactor(0 / 0))
      assert.is_nil(Core.SnapFactor("2"))
    end)
  end)

  describe("per-kind maximum", function()
    it("lets only chevsize go up to 5", function()
      assert.are.equal(5, Core.MaxFactor("chevsize"))
      assert.are.equal(3, Core.MaxFactor("textsize"))
      assert.are.equal(3, Core.MaxFactor(nil))
      assert.is_true(Core.ValidFactor(5, "chevsize"))
      assert.is_false(Core.ValidFactor(5.05, "chevsize"))
      assert.is_false(Core.ValidFactor(4, "textsize"))
      assert.is_false(Core.ValidFactor(4))
      assert.are.equal(5, Core.SnapFactor(5, "chevsize"))
      assert.is_nil(Core.SnapFactor(5.05, "chevsize"))
      assert.is_nil(Core.SnapFactor(4, "textsize"))
      assert.are.equal(5, Core.ParseFactor("5", "chevsize"))
      assert.are.equal(4.5, Core.ParseFactor("4.5", "chevsize"))
      assert.is_nil(Core.ParseFactor("5.05", "chevsize"))
      assert.is_nil(Core.ParseFactor("4", "textsize"))
      for _, key in ipairs({ "othersize", "barsize", "buffsize", "otherbarsize" }) do
        assert.is_nil(Core.ParseFactor("3.1", key), key)
      end
    end)

    it("InitDB keeps a chevsize up to 5 and resets larger values", function()
      assert.are.equal(4.5, Core.InitDB({ chevsize = 4.5 }).chevsize)
      assert.are.equal(3, Core.InitDB({ chevsize = 6 }).chevsize)
      assert.are.equal(1.75, Core.InitDB({ textsize = 4 }).textsize)
      assert.are.equal(1, Core.InitDB({ barsize = 4 }).barsize)
    end)
  end)

  describe("ParseFactor", function()
    it("accepts numbers from 1 to 3", function()
      assert.are.equal(1, Core.ParseFactor("1"))
      assert.are.equal(3, Core.ParseFactor("3"))
      assert.are.equal(1.25, Core.ParseFactor("1.25"))
      assert.are.equal(2, Core.ParseFactor("  2 "))
    end)

    it("refuses everything else without clamping", function()
      for _, bad in ipairs({ "0.9", "3.1", "abc", "", "  ", "0x2", "1e0", "-2", "1,5", "2 3", "nan", "inf" }) do
        assert.is_nil(Core.ParseFactor(bad), bad)
      end
      assert.is_nil(Core.ParseFactor(nil))
      assert.is_nil(Core.ParseFactor(2))
    end)
  end)

  describe("name gaps", function()
    it("accepts whole numbers from -40 to 40, default 5", function()
      assert.are.equal(5, Core.DEFAULT_GAP)
      assert.are.equal(0, Core.NO_GAP)
      assert.are.equal(5, Core.DefaultGap("namegap"))
      assert.are.equal(5, Core.DefaultGap("othernamegap"))
      -- Friendly NPCs: lower by default (their name sits in the faded health bar's place).
      assert.are.equal(-20, Core.DEFAULT_NPC_GAP)
      -- The role icon's opacity: 0.1 to 1, default 0.8.
      assert.are.equal(0.8, Core.InitDB({}).npciconalpha)
      assert.are.equal(0.4, Core.InitDB({ npciconalpha = 0.4 }).npciconalpha)
      for _, bad in ipairs({ 0, 0.05, 1.2, "0.5", true }) do
        assert.are.equal(0.8, Core.InitDB({ npciconalpha = bad }).npciconalpha)
      end
      assert.are.equal(0.75, Core.ParseFactor("0.75", "npciconalpha"))
      assert.is_nil(Core.ParseFactor("2", "npciconalpha"))
      assert.are.equal(-20, Core.DefaultGap("npcnamegap"))
      assert.are.equal(-20, Core.InitDB({}).npcnamegap)
      assert.are.equal(-20, Core.InitDB({ npcnamegap = 41 }).npcnamegap)
      assert.are.equal(3, Core.InitDB({ npcnamegap = 3 }).npcnamegap)
      assert.is_true(Core.GAP_KINDS.namegap)
      assert.is_true(Core.GAP_KINDS.othernamegap)
      for _, v in ipairs({ -40, -10, -1, 0, 4, 40 }) do
        assert.is_true(Core.ValidGap(v), tostring(v))
      end
      for _, v in ipairs({ -41, 41, 2.5, 0 / 0, 1 / 0, -1 / 0, "4", true, {} }) do
        assert.is_false(Core.ValidGap(v), tostring(v))
      end
      assert.is_false(Core.ValidGap(nil))
    end)

    it("parses signed whole numbers and refuses everything else without clamping", function()
      assert.are.equal(4, Core.ParseGap("4"))
      assert.are.equal(-3, Core.ParseGap(" -3 "))
      assert.are.equal(2, Core.ParseGap("+2"))
      assert.are.equal(0, Core.ParseGap("0"))
      assert.are.equal(-40, Core.ParseGap("-40"))
      assert.are.equal(40, Core.ParseGap("40"))
      for _, bad in ipairs({ "-41", "41", "1.5", "abc", "", " ", "0x2", "1e1", "--2", "+-2", "2 3", "nan", "inf" }) do
        assert.is_nil(Core.ParseGap(bad), bad)
      end
      assert.is_nil(Core.ParseGap(nil))
      assert.is_nil(Core.ParseGap(4))
    end)

    it("snaps a slider value to a whole point", function()
      assert.are.equal(3, Core.SnapGap(2.6))
      assert.are.equal(-2, Core.SnapGap(-2.4))
      assert.are.equal(40, Core.SnapGap(40.2))
      assert.is_nil(Core.SnapGap(41))
      assert.is_nil(Core.SnapGap(-40.6))
      assert.is_nil(Core.SnapGap(0 / 0))
      assert.is_nil(Core.SnapGap(1 / 0))
      assert.is_nil(Core.SnapGap("3"))
    end)

    it("offsets the name by (lift + gap) / size, invalid parts as 0 or 1", function()
      assert.are.equal(0, Core.NameOffset(0, 0, 1))
      assert.are.equal(5, Core.NameOffset(10, 0, 2))
      assert.are.equal(7, Core.NameOffset(10, 4, 2))
      assert.are.equal(-3, Core.NameOffset(0, -3, 1))
      assert.are.equal(4, Core.NameOffset(nil, 4, nil))
      assert.are.equal(0, Core.NameOffset(0 / 0, "x", 0))
      assert.are.equal(6, Core.NameOffset(6, 0, -2))
    end)

    it("InitDB defaults and repairs both gaps, keeping valid ones", function()
      local db = Core.InitDB(nil)
      assert.are.equal(5, db.namegap)
      assert.are.equal(5, db.othernamegap)
      db = Core.InitDB({ namegap = 6, othernamegap = -4 })
      assert.are.equal(6, db.namegap)
      assert.are.equal(-4, db.othernamegap)
      for _, bad in ipairs({ 2.5, 41, -41, "3", 0 / 0, true, {} }) do
        db = Core.InitDB({ namegap = bad, othernamegap = bad })
        assert.are.equal(5, db.namegap)
        assert.are.equal(5, db.othernamegap)
      end
    end)
  end)

  describe("Translate", function()
    it("returns the French text for frFR", function()
      assert.are.equal("Activé", Core.Translate("frFR", "enabled"))
      assert.are.equal("Enabled", Core.Translate("enUS", "enabled"))
    end)

    it("falls back to English for a key missing from the locale", function()
      local saved = Core.Locales.frFR.enabled
      Core.Locales.frFR.enabled = nil
      assert.are.equal("Enabled", Core.Translate("frFR", "enabled"))
      Core.Locales.frFR.enabled = saved
    end)

    it("gives English for an unknown or missing locale, enGB included", function()
      assert.are.equal("Enabled", Core.Translate("xxXX", "enabled"))
      assert.are.equal("Enabled", Core.Translate(nil, "enabled"))
      assert.are.equal("Enabled", Core.Translate(42, "enabled"))
      assert.are.equal("Enabled", Core.Translate("enGB", "enabled"))
    end)

    it("returns the key itself for an unknown key, never erroring", function()
      assert.are.equal("nope", Core.Translate("frFR", "nope"))
      assert.are.equal("nil", Core.Translate("frFR", nil))
    end)

    it("defines every English key in every client locale, and no extra one", function()
      for _, locale in ipairs(Core.CLIENT_LOCALES) do
        local set = Core.Locales[locale]
        assert.is_table(set, locale)
        for key in pairs(Core.Locales.enUS) do
          assert.is_string(set[key], locale .. " " .. key)
          assert.is_true(#set[key] > 0, locale .. " " .. key)
        end
        for key in pairs(set) do
          assert.is_string(Core.Locales.enUS[key], locale .. " " .. key)
        end
      end
    end)

    it("covers every locale of the game client", function()
      local expected = { "enUS", "enGB", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR",
        "zhCN", "zhTW" }
      assert.are.same(expected, Core.CLIENT_LOCALES)
    end)

    it("translates every key in each non-English locale", function()
      for _, locale in ipairs({ "frFR", "deDE", "esES", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
        for key, english in pairs(Core.Locales.enUS) do
          assert.are_not.equal(english, Core.Translate(locale, key), locale .. " " .. key)
        end
      end
    end)

    it("shares the English texts with enGB and the Spanish ones with esMX", function()
      assert.are.equal(Core.Locales.enUS, Core.Locales.enGB)
      assert.are.equal(Core.Locales.esES, Core.Locales.esMX)
      assert.are.equal("Activado", Core.Translate("esMX", "enabled"))
    end)
  end)

  describe("fonts", function()
    it("lists Blizzard's font first, with no font object, and unique keys; the default is outline", function()
      assert.are.equal("default", Core.FONTS[1].key)
      assert.is_nil(Core.FONTS[1].object)
      assert.are.equal("outline", Core.DEFAULT_FONT)
      assert.are.equal("SystemFont_Outline", Core.FindFont(Core.DEFAULT_FONT).object)
      local seen = {}
      for i, f in ipairs(Core.FONTS) do
        assert.is_nil(seen[f.key])
        seen[f.key] = true
        assert.is_string(f.label)
        if i > 1 then
          assert.is_string(f.object)
        end
      end
    end)

    it("validates and parses keys", function()
      assert.is_true(Core.ValidFont("outline"))
      assert.is_false(Core.ValidFont("nope"))
      assert.is_false(Core.ValidFont(nil))
      assert.is_false(Core.ValidFont(3))
      assert.are.equal("chat", Core.ParseFont("  Chat "))
      assert.is_nil(Core.ParseFont("chat large"))
      assert.is_nil(Core.ParseFont(""))
      assert.is_nil(Core.ParseFont(nil))
    end)

    it("cycles and wraps", function()
      assert.are.equal(Core.FONTS[2].key, Core.NextFont("default"))
      assert.are.equal("default", Core.NextFont(Core.FONTS[#Core.FONTS].key))
      assert.are.equal("default", Core.NextFont("unknown"))
    end)

    it("InitDB defaults and repairs db.font", function()
      assert.are.equal("outline", Core.InitDB(nil).font)
      assert.are.equal("outline", Core.InitDB({ font = "nope" }).font)
      assert.are.equal("outline", Core.InitDB({ font = 5 }).font)
      assert.are.equal("chat", Core.InitDB({ font = "chat" }).font)
      assert.are.equal("default", Core.InitDB({ font = "default" }).font)
    end)
  end)

  describe("friend and guild text sizes", function()
    it("default to the members' 1.75 and keep valid saved values", function()
      local db = Core.InitDB({})
      assert.are.equal(1.75, db.friendsize)
      assert.are.equal(1.75, db.guildsize)
      db = Core.InitDB({ friendsize = 2.5, guildsize = 1, })
      assert.are.equal(2.5, db.friendsize)
      assert.are.equal(1, db.guildsize)
      db = Core.InitDB({ friendsize = 4, guildsize = "x" })
      assert.are.equal(1.75, db.friendsize)
      assert.are.equal(1.75, db.guildsize)
    end)
  end)

  describe("options pages", function()
    it("puts every setting on exactly one page, except the data the addon keeps", function()
      local seen = {}
      for page, keys in pairs(Core.PAGE_KEYS) do
        for _, key in ipairs(keys) do
          assert.is_nil(seen[key], key)
          seen[key] = page
        end
      end
      for key in pairs(Core.InitDB({})) do
        if key ~= "npcroles" and key ~= "roleicons" then
          assert.is_string(seen[key], key)
        end
      end
    end)

    it("resets one page only", function()
      local db = Core.InitDB({ textsize = 3, othersize = 2, hostilesize = 2, npcsize = 2, font = "chat",
        enabled = false, npcroles = { [9] = "flight" }, roleicons = { flight = "x" } })
      assert.is_true(Core.ResetPage(db, "players"))
      assert.are.equal(1.75, db.textsize)
      assert.are.equal(1.5, db.othersize)
      assert.are.equal(2, db.hostilesize)
      assert.are.equal(2, db.npcsize)
      assert.are.equal("chat", db.font)
      assert.is_true(Core.ResetPage(db, "main"))
      assert.are.equal("outline", db.font)
      assert.is_true(db.enabled)
      assert.is_true(Core.ResetPage(db, "quests"))
      assert.are.equal(1.5, db.hostilesize)
      assert.is_true(Core.ResetPage(db, "npcs"))
      assert.are.equal(1, db.npcsize)
      -- The learned roles and the icon choices stay.
      assert.are.same({ [9] = "flight" }, db.npcroles)
      assert.are.same({ flight = "x" }, db.roleicons)
      assert.is_false(Core.ResetPage(db, "nope"))
      assert.is_false(Core.ResetPage(nil, "main"))
    end)
  end)

  describe("InitDB", function()
    it("defaults and validates the size factors", function()
      local db = Core.InitDB(nil)
      assert.are.equal(3, db.chevsize)
      assert.are.equal(1.75, db.textsize)
      assert.are.equal(1.5, db.othersize)
      assert.are.equal(1.1, db.buffsize)
      db = Core.InitDB({ chevsize = 2.5, textsize = 3, othersize = 1.5 })
      assert.are.equal(2.5, db.chevsize)
      assert.are.equal(3, db.textsize)
      assert.are.equal(1.5, db.othersize)
      for _, key in ipairs({ "barsize", "otherbarsize" }) do
        assert.are.equal(1, Core.InitDB(nil)[key])
        assert.are.equal(2.5, Core.InitDB({ [key] = 2.5 })[key])
      end
      for _, bad in ipairs({ 0.5, 5.5, "2", 0 / 0, 1 / 0, true, {} }) do
        db = Core.InitDB({ chevsize = bad, textsize = bad, othersize = bad, barsize = bad, buffsize = bad,
          otherbarsize = bad })
        assert.are.equal(3, db.chevsize)
        assert.are.equal(1.75, db.textsize)
        assert.are.equal(1.5, db.othersize)
        assert.are.equal(1, db.barsize)
        assert.are.equal(1.1, db.buffsize)
        assert.are.equal(1, db.otherbarsize)
      end
    end)

    it("fills the defaults", function()
      local db = Core.InitDB(nil)
      assert.is_true(db.enabled)
      assert.are.same(Core.DEFAULT_COLOR, db.color)
      assert.are_not.equal(Core.DEFAULT_COLOR, db.color) -- a copy
      assert.are.equal("#FF4FD8", Core.FormatColor(unpack(db.color)))
      local t = {}
      assert.are.equal(t, Core.InitDB(t)) -- in place
      assert.is_true(t.enabled)
    end)

    it("keeps valid saved values", function()
      local db = Core.InitDB({ enabled = false, color = { 0, 0.5, 1 } })
      assert.is_false(db.enabled)
      assert.are.same({ 0, 0.5, 1 }, db.color)
    end)

    it("replaces invalid saved values", function()
      for _, bad in ipairs({
        { enabled = "yes", color = "#FF0000" },
        { enabled = 1, color = { 1, 2, 3 } },
        { color = { 1, 0.5 } },
        { color = { "1", 0, 0 } },
        { color = { 0 / 0, 0, 0 } },
        { color = { -0.1, 0, 0 } },
      }) do
        local db = Core.InitDB(bad)
        assert.is_true(db.enabled)
        assert.are.same(Core.DEFAULT_COLOR, db.color)
      end
      assert.is_true(Core.InitDB("garbage").enabled)
    end)
  end)

  describe("hostiles tied to a quest", function()
    it("defaults the hostile settings like the friendlies, in yellow", function()
      local db = Core.InitDB(nil)
      assert.are.same({ 1, 1, 0 }, db.hostilecolor)
      assert.are.equal(Core.DefaultFactor("chevsize"), db.hostilechevsize) -- the friends' chevron size
      assert.are.equal(1.5, db.hostilesize) -- the friendlies' othersize
      assert.are.equal(Core.DefaultGap("othernamegap"), db.hostilenamegap)
      assert.are_not.equal(Core.DEFAULT_HOSTILE_COLOR, Core.CopyDefaultHostileColor())
      assert.are.same(Core.DEFAULT_HOSTILE_COLOR, Core.CopyDefaultHostileColor())
    end)

    it("InitDB keeps valid hostile values, repairs invalid ones and copies the colour", function()
      local color = { 0.2, 0.4, 0.6 }
      local db = Core.InitDB({ hostilecolor = color, hostilechevsize = 4.5, hostilesize = 2, hostilenamegap = -4 })
      assert.are.same({ 0.2, 0.4, 0.6 }, db.hostilecolor)
      assert.are_not.equal(color, db.hostilecolor)
      assert.are.equal(4.5, db.hostilechevsize)
      assert.are.equal(2, db.hostilesize)
      assert.are.equal(-4, db.hostilenamegap)
      for _, bad in ipairs({ "x", 0, 9, -1, 0 / 0, true }) do
        db = Core.InitDB({ hostilecolor = bad, hostilechevsize = bad, hostilesize = bad })
        assert.are.same({ 1, 1, 0 }, db.hostilecolor)
        assert.are.equal(3, db.hostilechevsize)
        assert.are.equal(1.5, db.hostilesize)
      end
      for _, bad in ipairs({ "x", 41, -41, 2.5, 0 / 0, true }) do
        assert.are.equal(5, Core.InitDB({ hostilenamegap = bad }).hostilenamegap)
      end
    end)

    it("accepts a hostile chevron size up to 5, the text size up to 3 and the gap from -40 to 40", function()
      assert.is_true(Core.ValidFactor(5, "hostilechevsize"))
      assert.is_false(Core.ValidFactor(5.05, "hostilechevsize"))
      assert.is_true(Core.ValidFactor(3, "hostilesize"))
      assert.is_false(Core.ValidFactor(3.05, "hostilesize"))
      assert.are.equal(5, Core.MaxFactor("hostilechevsize"))
      assert.are.equal(4.5, Core.ParseFactor("4.5", "hostilechevsize"))
      assert.is_nil(Core.ParseFactor("6", "hostilechevsize"))
      assert.is_true(Core.GAP_KINDS.hostilenamegap)
      assert.are.equal(5, Core.DefaultGap("hostilenamegap"))
    end)

    it("has a title for the options group in every locale", function()
      assert.are.equal("Quest hostiles (enemies tied to your quests)", Core.Translate("enUS", "hostiles"))
      assert.are.equal("Ennemis de quête (liés à vos quêtes)", Core.Translate("frFR", "hostiles"))
      assert.are.equal("Quest-Gegner (mit aktiven Quests verknüpft)", Core.Translate("deDE", "hostiles"))
      assert.are.equal("Quest hostiles (enemies tied to your quests)", Core.Translate("xxXX", "hostiles"))
    end)

    -- questAPI: the injected functions for the hostile checks; quests[unit] is the quest answer.
    local function questAPI(attackable, quests)
      local api = fakeAPI({}, {})
      api.UnitIsFriend = function() return false end
      api.UnitCanAttack = function(_, unit) return attackable[unit] == true end
      api.IsRelatedToActiveQuest = function(unit)
        api.asked = (api.asked or 0) + 1
        return quests[unit] == true
      end
      return api
    end

    it("QuestLookup answers from the API, and false for anything unknown", function()
      local api = questAPI({}, { u = true, v = false })
      assert.are.same({ true, "unit" }, { Core.QuestLookup(api, "u") })
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, "v") })
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, "") })
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, nil) })
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, SECRET) })
      assert.are.same({ false, "missing" }, { Core.QuestLookup({}, "u") })
      assert.are.same({ false, "missing" }, { Core.QuestLookup(nil, "u") })
      -- A truthy answer that is not exactly true (a number, a table) does not count.
      api.IsRelatedToActiveQuest = function() return 1 end
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, "u") })
      api.IsRelatedToActiveQuest = function() error("boom") end
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, "u") })
      api.IsRelatedToActiveQuest = function() return SECRET end
      assert.are.same({ false, "none" }, { Core.QuestLookup(api, "u") })
    end)

    it("UnitInfo reads the quest only for a unit known to be attackable", function()
      local api = questAPI({ a = true }, { a = true, b = true })
      local info = Core.UnitInfo(api, "a", {})
      assert.is_true(info.attackable)
      assert.is_true(info.quest)
      assert.are.equal("unit", info.questSource)
      assert.are.equal(1, api.asked)
      info = Core.UnitInfo(api, "b", {}) -- tied to a quest but not attackable: not asked
      assert.is_false(info.attackable)
      assert.is_false(info.quest)
      assert.are.equal("skipped", info.questSource)
      assert.are.equal(1, api.asked)
      -- No UnitCanAttack: unknown, not asked.
      api.UnitCanAttack = nil
      info = Core.UnitInfo(api, "a", {})
      assert.is_nil(info.attackable)
      assert.is_false(info.quest)
      assert.are.equal(1, api.asked)
      -- UnitCanAttack answering a secret value: unknown.
      api.UnitCanAttack = function() return SECRET end
      assert.is_nil(Core.UnitInfo(api, "a", {}).attackable)
    end)

    it("QuestHostile needs the addon on, an attackable unit that is not the player and a quest", function()
      local on = { enabled = true }
      assert.is_true(Core.QuestHostile({ attackable = true, quest = true }, on))
      assert.is_true(Core.QuestHostile({ attackable = true, quest = true, self = false }, on))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = true, self = true }, on))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = false }, on))
      assert.is_false(Core.QuestHostile({ attackable = false, quest = true }, on))
      assert.is_false(Core.QuestHostile({ quest = true }, on))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = 1 }, on))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = true }, { enabled = false }))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = true }, {}))
      assert.is_false(Core.QuestHostile({ attackable = true, quest = true }, nil))
      assert.is_false(Core.QuestHostile(nil, on))
    end)

    it("PlateMode gives a quest hostile the quest mode, compact or not, and leaves the rest as it was", function()
      local quest = { attackable = true, quest = true, friend = false, player = false, member = false, self = false }
      for _, compact in ipairs({ true, false }) do
        local mode, relation = Core.PlateMode(quest, { enabled = true, compact = compact })
        assert.are.equal("quest", mode)
        assert.is_nil(relation)
      end
      assert.are.equal("default", (Core.PlateMode(quest, { enabled = false })))
      -- Not tied to a quest: the plate stays as the game draws it.
      assert.are.equal("default", (Core.PlateMode({ attackable = true, quest = false, friend = false, player = false },
        { enabled = true, compact = true })))
      -- A friendly player is never a quest hostile.
      local friend = { friend = true, player = true, member = false, self = false, target = false, attackable = false }
      assert.are.equal("compact", (Core.PlateMode(friend, { enabled = true, compact = true })))
    end)
  end)

  describe("hostiles tied to a party member's quest", function()
    local TYPES = { UnitName = 2, QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    -- tooltipAPI answers GetTooltipUnit with { lines = lines } for every unit; the player is "Me".
    local function tooltipAPI(lines, overrides)
      local api = {
        GetTooltipUnit = function() return { lines = lines } end,
        TooltipLineTypes = TYPES,
        IsInGroup = function() return true end,
        UnitName = function(unit) return unit == "player" and "Me" or nil end,
        issecretvalue = function(v) return v == SECRET end,
      }
      for k, v in pairs(overrides or {}) do
        api[k] = v
      end
      return api
    end
    local function title(t) return { type = 17, leftText = t } end
    local function who(name) return { type = 18, leftText = name } end
    local function objective(text, completed) return { type = 8, leftText = text, completed = completed } end

    it("defaults the party quest settings like the hostiles, in white", function()
      local db = Core.InitDB(nil)
      assert.are.same({ 1, 1, 1 }, db.partyquestcolor)
      assert.are.equal(db.hostilechevsize, db.partyquestchevsize)
      assert.are.equal(db.hostilesize, db.partyquestsize)
      assert.are.equal(db.hostilenamegap, db.partyquestnamegap)
      assert.are.equal(db.hostileoutlinesize, db.partyquestoutlinesize)
      assert.are.equal(5, Core.MaxFactor("partyquestchevsize"))
      assert.are.equal(3, Core.MaxFactor("partyquestsize"))
      assert.is_true(Core.GAP_KINDS.partyquestnamegap)
      db = Core.InitDB({ partyquestcolor = { 2, 0, 0 }, partyquestchevsize = 9, partyquestnamegap = 1.5 })
      assert.are.same({ 1, 1, 1 }, db.partyquestcolor)
      assert.are.equal(3, db.partyquestchevsize)
      assert.are.equal(5, db.partyquestnamegap)
    end)

    it("ObjectiveType links a tooltip line to its quest log objective, whatever the language", function()
      local api = tooltipAPI({})
      local objectives = {
        { text = "Croc de goule : 0/10", type = "item", finished = false },
        { text = "Démon squelette : 13/15 personnages tués", type = "monster", finished = false },
      }
      -- The same text: its type.
      assert.are.equal("monster", Core.ObjectiveType(api, objectives, "Démon squelette : 13/15 personnages tués"))
      -- Counts a step apart (the log updated first): the text without its counts.
      assert.are.equal("item", Core.ObjectiveType(api, objectives, "Croc de goule : 1/10"))
      assert.are.equal("Croc de goule :", Core.StripCount("Croc de goule : 1/10"))
      -- No match, two types left: unknown; one type left: that one.
      assert.is_nil(Core.ObjectiveType(api, objectives, "Something else 0/1"))
      objectives[2].finished = true
      assert.are.equal("item", Core.ObjectiveType(api, objectives, "Something else 0/1"))
      -- Nothing to read.
      assert.is_nil(Core.ObjectiveType(api, nil, "x"))
      assert.is_nil(Core.ObjectiveType(api, objectives, SECRET))
      assert.is_nil(Core.ObjectiveType(api, { { text = "a", type = SECRET } }, "a"))
    end)

    it("QuestKindLookup reads the open objectives: the player's own and the party's, kill and loot", function()
      -- What the Forever client gave for a mob tied to three of the player's quests, in a group:
      -- the player's own name, then a party member's, under the first quest.
      local lines = {
        { type = 2, leftText = "Démon squelette" },
        { type = 17, leftText = "Les Veilleurs", id = 57 }, who("Me"),
        objective("Démon squelette : 13/15 personnages tués"), who("Gonald"),
        objective("Démon squelette : 15/15 personnages tués"),
        { type = 17, leftText = "Le Totem d'affliction", id = 101 }, who("Me"), objective("Doigt de squelette : 10/10"),
        { type = 17, leftText = "Bouclier de Grant", id = 79362 }, who("Me"), objective("Masse de Grant : 1/1"),
      }
      local log = {
        [57] = { { text = "Démon squelette : 13/15 personnages tués", type = "monster", finished = false } },
        [101] = { { text = "Doigt de squelette : 10/10", type = "item", finished = true } },
        [79362] = { { text = "Masse de Grant : 1/1", type = "item", finished = true } },
      }
      local asked = 0
      local function objectivesOf(id)
        asked = asked + 1
        return log[id]
      end
      local api = tooltipAPI(lines, { GetQuestObjectives = objectivesOf })
      -- The item objectives are done, the party member's kill one too: the player's kill only.
      assert.are.same({ true, false, "tooltip", false, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
      assert.are.equal(1, asked) -- only the quest with an open objective is looked up
      -- One of them open again: kill and loot.
      lines[9] = objective("Doigt de squelette : 4/10")
      log[101][1] = { text = "Doigt de squelette : 4/10", type = "item", finished = false }
      assert.are.same({ true, true, "tooltip", false, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
      -- The party member still has kills to do on the same quest (counts differ from the player's:
      -- matched without them): a party kill.
      lines[6] = objective("Démon squelette : 9/15 personnages tués")
      assert.are.same({ true, true, "tooltip", true, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
      -- A party member's open objective alone: party only, never the player's.
      api = tooltipAPI({ { type = 17, leftText = "Q", id = 5 }, who("Gonald"), objective("Crate: 0/4") },
        { GetQuestObjectives = function() return { { text = "Crate: 2/4", type = "item" } } end })
      assert.are.same({ false, false, "tooltip", false, true, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- An unreadable player name: nobody's.
      api = tooltipAPI({ { type = 17, leftText = "Q", id = 5 }, who(SECRET), objective("Crate: 0/4") },
        { GetQuestObjectives = function() return { { text = "Crate: 0/4", type = "item" } } end })
      assert.are.same({ false, false, "none", false, false, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- Other objective types count as neither.
      api = tooltipAPI({ { type = 17, leftText = "Q", id = 5 }, objective("Plan détruit : 0/1") },
        { GetQuestObjectives = function() return { { text = "Plan détruit : 0/1", type = "object" } } end })
      assert.are.same({ false, false, "none", false, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
      -- A secret or missing quest ID: nothing is looked up.
      api = tooltipAPI({ { type = 17, leftText = "Q", id = SECRET }, objective("Crate: 0/4") },
        { GetQuestObjectives = function() error("never asked") end })
      assert.are.same({ false, false, "none", false, false, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- Missing APIs.
      assert.are.same({ false, false, "missing", false, false, false },
        { Core.QuestKindLookup(tooltipAPI(lines), "nameplate1") })
      assert.are.same({ false, false, "missing", false, false, false },
        { Core.QuestKindLookup(tooltipAPI(lines, { GetQuestObjectives = objectivesOf, TooltipLineTypes = false }),
          "nameplate1") })
      -- The quest log failing: every open objective is guessed from the unit's name (the
      -- tooltip's first line): "Démon squelette : …" a kill, "Doigt de squelette : 4/10" a loot.
      api = tooltipAPI(lines, { GetQuestObjectives = function() error("boom") end })
      assert.are.same({ true, true, "guessed", true, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
      -- And without the unit's name either: "none".
      table.remove(lines, 1)
      assert.are.same({ false, false, "none", false, false, true }, { Core.QuestKindLookup(api, "nameplate1") })
    end)

    it("QuestKindTrace says what the tooltip gave, and what could not be read", function()
      local lines = {
        { type = 2, leftText = "Captif défias" },
        { type = 17, leftText = "La couleur du Sang", id = 57 },
        who("Me Boutefeu"), objective("Foulard en laine rouge : 0/10"),
        who("Gonald"), objective("Foulard en laine rouge : 1/10", true),
      }
      local trace = Core.QuestKindTrace(tooltipAPI(lines), "nameplate1")
      assert.are.equal(7, #trace)
      assert.is_truthy(trace[1]:find("data readable", 1, true))
      assert.is_truthy(trace[1]:find('player name "Me"', 1, true))
      assert.is_truthy(trace[3]:find('type 17, id 57, text "La couleur du Sang"', 1, true))
      assert.is_truthy(trace[4]:find("(the player)", 1, true))
      assert.is_truthy(trace[5]:find("(open)", 1, true))
      assert.is_truthy(trace[6]:find("(other)", 1, true))
      assert.is_truthy(trace[7]:find("(not open)", 1, true))
      -- Secret fields are shown as such.
      trace = Core.QuestKindTrace(tooltipAPI({ { type = 17, leftText = SECRET, id = SECRET } }), "nameplate1")
      assert.is_truthy(trace[2]:find("id secret, text secret", 1, true))
      -- Nothing readable: the reason, in one line.
      assert.are.same({ "tooltip: GetUnit returned a secret value" },
        Core.QuestKindTrace(tooltipAPI(nil, { GetTooltipUnit = function() return SECRET end }), "nameplate1"))
      assert.are.same({ "tooltip: data.lines is secret" },
        Core.QuestKindTrace(tooltipAPI(SECRET), "nameplate1"))
      assert.are.same({ "tooltip: GetUnit raised an error: boom" },
        Core.QuestKindTrace(tooltipAPI(nil, { GetTooltipUnit = function() error("boom", 0) end }), "nameplate1"))
      assert.are.same({ "tooltip: C_TooltipInfo.GetUnit is missing" },
        Core.QuestKindTrace({}, "nameplate1"))
      assert.are.same({ "tooltip: unit token unreadable" }, Core.QuestKindTrace(tooltipAPI(lines), SECRET))
    end)

    it("IsSelfName: the tooltip's full name (with the last name) is the player's", function()
      assert.is_true(Core.IsSelfName("Brom", "Brom"))
      assert.is_true(Core.IsSelfName("Brom Boutefeu", "Brom"))
      assert.is_false(Core.IsSelfName("Bromwell", "Brom"))
      assert.is_false(Core.IsSelfName("Sara Cetamol", "Brom"))
      assert.is_false(Core.IsSelfName("Brom Boutefeu", nil))
      assert.is_false(Core.IsSelfName(nil, "Brom"))
    end)

    it("QuestKindLookup: the player's full name in a group is the player's (Forever's last names)", function()
      -- The lines of "Côtes de sanglier à la bière", the player Brom Boutefeu with Sara Cetamol.
      local lines = {
        { type = 2, leftText = "Sanglier des rochers" },
        { type = 17, leftText = "Côtes de sanglier à la bière", id = 384 },
        who("Me Boutefeu"), objective("Côtes de sanglier des rochers : 0/6"),
        who("Sara Cetamol"), objective("Côtes de sanglier des rochers : 0/6"),
      }
      local api = tooltipAPI(lines, { GetQuestObjectives = function()
        return { { text = "Côtes de sanglier des rochers : 0/6", type = "item", finished = false } }
      end })
      -- The player's loot (yellow), and Sara's too.
      assert.are.same({ false, true, "tooltip", false, true, true }, { Core.QuestKindLookup(api, "nameplate1") })
      -- PartyQuestLookup: Sara's objective is still a party member's.
      assert.are.same({ true, "tooltip" }, { Core.PartyQuestLookup(api, "nameplate1") })
      lines[5] = who("Me Boutefeu")
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(api, "nameplate1") })
    end)

    it("GuessKind: an objective naming the unit is a kill, any other one a loot", function()
      assert.are.equal("monster", Core.GuessKind("Petit sanglier des rochers : 3/8", "Petit sanglier des rochers"))
      assert.are.equal("monster", Core.GuessKind("Kobold Vermin slain: 3/10", "Kobold Vermin"))
      assert.are.equal("monster", Core.GuessKind("kobold vermin slain: 3/10", "Kobold Vermin"))
      assert.are.equal("item", Core.GuessKind("Défense de sanglier : 2/6", "Petit sanglier des rochers"))
      assert.is_nil(Core.GuessKind("Défense de sanglier : 2/6", nil))
      assert.is_nil(Core.GuessKind(nil, "Boar"))
      assert.is_nil(Core.GuessKind("3/8", "Boar"))
    end)

    it("QuestKindLookup guesses a party member's objective that the quest log cannot type", function()
      -- A party member's quest the player does not have: GetQuestObjectives gives nothing.
      local lines = {
        { type = 2, leftText = "Petit sanglier des rochers" },
        { type = 17, leftText = "Q", id = 5 }, who("Gonald"), objective("Petit sanglier des rochers : 3/8"),
        { type = 17, leftText = "R", id = 6 }, who("Gonald"), objective("Défense de sanglier : 2/6"),
      }
      local api = tooltipAPI(lines, { GetQuestObjectives = function() return nil end })
      assert.are.same({ false, false, "guessed", true, true, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- Without the tooltip's name line, UnitName(unit).
      table.remove(lines, 1)
      api = tooltipAPI(lines, { GetQuestObjectives = function() return nil end,
        UnitName = function(unit) return unit == "player" and "Me" or "Petit sanglier des rochers" end })
      assert.are.same({ false, false, "guessed", true, true, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- No name at all: nothing guessed.
      api = tooltipAPI(lines, { GetQuestObjectives = function() return nil end })
      assert.are.same({ false, false, "none", false, false, false }, { Core.QuestKindLookup(api, "nameplate1") })
      -- A logged kind and a guessed one: "tooltip".
      lines = {
        { type = 2, leftText = "Petit sanglier des rochers" },
        { type = 17, leftText = "Q", id = 5 }, objective("Petit sanglier des rochers : 3/8"),
        { type = 17, leftText = "R", id = 6 }, who("Gonald"), objective("Défense de sanglier : 2/6"),
      }
      api = tooltipAPI(lines, { GetQuestObjectives = function(id)
        return id == 5 and { { text = "Petit sanglier des rochers : 3/8", type = "monster" } } or nil
      end })
      assert.are.same({ true, false, "tooltip", false, true, true }, { Core.QuestKindLookup(api, "nameplate1") })
    end)

    it("ObjectiveOpen reads completed, else a n/m count", function()
      local api = tooltipAPI({})
      assert.is_true(Core.ObjectiveOpen(api, objective("Kobold slain: 3/8", false)))
      assert.is_false(Core.ObjectiveOpen(api, objective("Kobold slain: 3/8", true)))
      assert.is_true(Core.ObjectiveOpen(api, objective("- 3/8 Kobold slain")))
      assert.is_true(Core.ObjectiveOpen(api, objective("0 / 1 Red Bandana")))
      assert.is_false(Core.ObjectiveOpen(api, objective("8/8 Kobold slain")))
      assert.is_false(Core.ObjectiveOpen(api, objective("Slay the kobolds")))
      assert.is_false(Core.ObjectiveOpen(api, objective(SECRET, SECRET)))
      assert.is_false(Core.ObjectiveOpen(api, nil))
    end)

    it("PartyQuestLookup finds a party member's open objective, never the player's own", function()
      local lines = { { type = 2, leftText = "Kobold Vermin" }, title("Kobold Camp Cleanup"),
        objective("Kobold Vermin slain: 10/10", true), who("Laure"), objective("Kobold Vermin slain: 4/10", false) }
      assert.are.same({ true, "tooltip" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
      -- Only the player's own objectives (open or not): not a party quest.
      lines = { title("Kobold Camp Cleanup"), objective("Kobold Vermin slain: 4/10", false) }
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
      -- The player's own name on a QuestPlayer line is the player's own objectives.
      lines = { title("Q"), who("Me"), objective("1/10", false) }
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
      -- A party member who is done: not open.
      lines = { title("Q"), who("Laure"), objective("10/10", true) }
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
      -- A new QuestTitle line goes back to the player's own objectives.
      lines = { title("Q1"), who("Laure"), objective("10/10", true), title("Q2"), objective("1/5", false) }
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
      -- An unreadable name skips that player's objectives.
      lines = { title("Q"), who(SECRET), objective("1/10", false) }
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "nameplate1") })
    end)

    it("PartyQuestLookup answers false for anything missing, failing or secret", function()
      local lines = { title("Q"), who("Laure"), objective("1/10", false) }
      assert.are.same({ false, "missing" }, { Core.PartyQuestLookup(nil, "u") })
      assert.are.same({ false, "missing" }, { Core.PartyQuestLookup({}, "u") })
      assert.are.same({ false, "missing" },
        { Core.PartyQuestLookup(tooltipAPI(lines, { TooltipLineTypes = false }), "u") })
      assert.are.same({ false, "missing" },
        { Core.PartyQuestLookup(tooltipAPI(lines, { TooltipLineTypes = { QuestTitle = 17 } }), "u") })
      assert.are.same({ false, "nogroup" },
        { Core.PartyQuestLookup(tooltipAPI(lines, { IsInGroup = function() return false end }), "u") })
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), "") })
      assert.are.same({ false, "none" }, { Core.PartyQuestLookup(tooltipAPI(lines), SECRET) })
      for _, get in ipairs({ function() error("boom") end, function() return SECRET end,
        function() return nil end, function() return { lines = SECRET } end }) do
        assert.are.same({ false, "none" },
          { Core.PartyQuestLookup(tooltipAPI(lines, { GetTooltipUnit = get }), "u") })
      end
      -- A line that raises on index is skipped without an error; the next lines still count.
      local bad = setmetatable({}, { __index = function() error("protected") end })
      assert.are.same({ true, "tooltip" },
        { Core.PartyQuestLookup(tooltipAPI({ title("Q"), bad, who("Laure"), objective("1/2") }), "u") })
    end)

    it("UnitInfo asks only for an attackable unit not tied to the player's own quests", function()
      local asked = 0
      local api = tooltipAPI({ title("Q"), who("Laure"), objective("1/10", false) }, {
        UnitCanAttack = function(_, unit) return unit ~= "friendly" end,
        IsRelatedToActiveQuest = function(unit) return unit == "mine" end,
      })
      local get = api.GetTooltipUnit
      api.GetTooltipUnit = function(...)
        asked = asked + 1
        return get(...)
      end
      local info = Core.UnitInfo(api, "theirs", {})
      assert.is_true(info.partyQuest)
      assert.are.equal("tooltip", info.partyQuestSource)
      assert.are.equal(1, asked)
      info = Core.UnitInfo(api, "mine", {})
      assert.is_false(info.partyQuest)
      assert.are.equal("skipped", info.partyQuestSource)
      info = Core.UnitInfo(api, "friendly", {})
      assert.are.equal("skipped", info.partyQuestSource)
      assert.are.equal(1, asked)
    end)

    it("PlateMode: the player's own quest wins, then the party quest", function()
      local on = { enabled = true, compact = true }
      local base = { attackable = true, friend = false, player = false, member = false, self = false }
      local function with(t)
        local out = {}
        for k, v in pairs(base) do
          out[k] = v
        end
        for k, v in pairs(t) do
          out[k] = v
        end
        return out
      end
      assert.are.equal("partyquest", (Core.PlateMode(with({ partyQuest = true }), on)))
      assert.are.equal("quest", (Core.PlateMode(with({ quest = true, partyQuest = true }), on)))
      assert.are.equal("default", (Core.PlateMode(with({ partyQuest = true }), { enabled = false })))
      assert.are.equal("default", (Core.PlateMode(with({ partyQuest = 1 }), on)))
      assert.are.equal("default", (Core.PlateMode(with({ partyQuest = true, attackable = false }), on)))
      assert.are.equal("default", (Core.PlateMode(with({ partyQuest = true, self = true }), on)))
    end)
  end)

  describe("IsGroupMember", function()
    local players = { party1 = true, raid5 = true, nameplate1 = true, nameplate2 = true, nameplate3 = true,
      nameplate4 = true, player = true }
    local members = { party1 = "party", raid5 = "raid", nameplate1 = "party", nameplate2 = "raid",
      nameplate4 = "party" }
    local api = fakeAPI(players, members)

    it("is true for a party member", function()
      assert.is_true(Core.IsGroupMember(api, "party1"))
      assert.is_true(Core.IsGroupMember(api, "nameplate1"))
    end)

    it("is true for a raid member", function()
      assert.is_true(Core.IsGroupMember(api, "raid5"))
      assert.is_true(Core.IsGroupMember(api, "nameplate2"))
    end)

    it("is false for a non-player", function()
      local w = fakeAPI({}, { nameplate9 = "party" })
      assert.is_false(Core.IsGroupMember(w, "nameplate9"))
    end)

    it("is false for the player", function()
      assert.is_false(Core.IsGroupMember(api, "player"))
    end)

    it("is false for a player who is not grouped", function()
      assert.is_false(Core.IsGroupMember(api, "nameplate3"))
    end)

    it("is false for bad units", function()
      assert.is_false(Core.IsGroupMember(api, nil))
      assert.is_false(Core.IsGroupMember(api, ""))
      assert.is_false(Core.IsGroupMember(api, 4))
      assert.is_false(Core.IsGroupMember(nil, "nameplate1"))
      assert.is_false(Core.IsGroupMember(api, SECRET))
    end)

    it("is false when an API raises an error or is missing", function()
      for _, name in ipairs({ "UnitIsPlayer", "UnitIsUnit" }) do
        local w = fakeAPI(players, members)
        w[name] = function() error("boom") end
        assert.is_false(Core.IsGroupMember(w, "nameplate1"), name)
        w[name] = nil
        assert.is_false(Core.IsGroupMember(w, "nameplate1"), name .. " missing")
      end
      local w = fakeAPI(players, members)
      w.UnitInParty = function() error("boom") end
      w.UnitInRaid = function() error("boom") end
      assert.is_false(Core.IsGroupMember(w, "nameplate1"))
      -- One failing membership API does not hide the other one's answer.
      w.UnitInRaid = fakeAPI(players, members).UnitInRaid
      assert.is_true(Core.IsGroupMember(w, "nameplate2"))
      assert.is_false(Core.IsGroupMember(w, "nameplate1"))
    end)

    it("is false for secret values", function()
      for _, name in ipairs({ "UnitIsPlayer", "UnitIsUnit", "UnitInParty" }) do
        local w = fakeAPI(players, members)
        w[name] = function() return SECRET end
        assert.is_false(Core.IsGroupMember(w, "nameplate1"), name)
      end
      local w = fakeAPI(players, members)
      w.issecretvalue = function() error("boom") end
      assert.is_false(Core.IsGroupMember(w, "nameplate1"))
    end)

    it("works without issecretvalue", function()
      local w = fakeAPI(players, members)
      w.issecretvalue = nil
      assert.is_true(Core.IsGroupMember(w, "nameplate4"))
    end)
  end)

  describe("compact setting", function()
    it("defaults to on and replaces invalid saved values", function()
      assert.is_true(Core.InitDB(nil).compact)
      assert.is_true(Core.InitDB({}).compact)
      assert.is_false(Core.InitDB({ compact = false }).compact)
      assert.is_true(Core.InitDB({ compact = true }).compact)
      for _, bad in ipairs({ "off", 0, 1, {}, "true" }) do
        assert.is_true(Core.InitDB({ compact = bad }).compact, tostring(bad))
      end
    end)

    it("parses on and off", function()
      assert.is_true(Core.ParseOnOff("on"))
      assert.is_true(Core.ParseOnOff(" ON "))
      assert.is_false(Core.ParseOnOff("off"))
      assert.is_false(Core.ParseOnOff("Off"))
      for _, bad in ipairs({ "", " ", "yes", "1", "true", "on off", "onn", "of" }) do
        assert.is_nil(Core.ParseOnOff(bad), bad)
      end
      assert.is_nil(Core.ParseOnOff(nil))
      assert.is_nil(Core.ParseOnOff(true))
    end)
  end)

  describe("PlateMode", function()
    local on = { enabled = true, compact = true }

    -- world: nameplate1 member, nameplate2 friendly non-member, nameplate3 enemy player,
    -- nameplate4 friendly NPC, nameplate5 enemy NPC, nameplate6 the player, plus `target`.
    local function world(target)
      local players = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate6 = true }
      local friends = { nameplate1 = true, nameplate2 = true, nameplate4 = true, nameplate6 = true }
      local api = fakeAPI(players, { nameplate1 = "party" })
      api.UnitIsFriend = function(a, b) return a == "player" and friends[b] == true end
      api.UnitIsUnit = function(a, b)
        if b == "target" then
          return a == target
        end
        if b == "player" then
          return a == "nameplate6"
        end
        return a == b
      end
      return api
    end

    local function mode(api, unit, settings)
      return Core.PlateMode(Core.UnitInfo(api, unit), settings or on)
    end

    it("decides each case", function()
      local api = world(nil)
      for unit, want in pairs({
        nameplate1 = "member",
        nameplate2 = "compact",
        nameplate3 = "default",
        nameplate4 = "default",
        nameplate5 = "default",
        nameplate6 = "default",
      }) do
        assert.are.equal(want, mode(api, unit), unit)
      end
    end)

    it("shows the target's full plate, but keeps a member target marked", function()
      assert.are.equal("default", mode(world("nameplate2"), "nameplate2"))
      assert.are.equal("compact", mode(world("nameplate1"), "nameplate2"))
      assert.are.equal("member", mode(world("nameplate1"), "nameplate1"))
    end)

    it("follows compact off and addon off", function()
      local api = world(nil)
      local compactOff = { enabled = true, compact = false }
      assert.are.equal("default", mode(api, "nameplate2", compactOff))
      assert.are.equal("member", mode(api, "nameplate1", compactOff))
      local off = { enabled = false, compact = true }
      assert.are.equal("default", mode(api, "nameplate2", off))
      assert.are.equal("default", mode(api, "nameplate1", off))
      assert.are.equal("default", mode(api, "nameplate2", {}))
      assert.are.equal("default", Core.PlateMode(Core.UnitInfo(api, "nameplate2"), nil))
      assert.are.equal("default", Core.PlateMode(nil, on))
    end)

    it("gives default for any unknown answer", function()
      for _, name in ipairs({ "UnitIsPlayer", "UnitIsUnit", "UnitIsFriend", "UnitInParty", "UnitInRaid" }) do
        local api = world(nil)
        api[name] = function() error("boom") end
        assert.are.equal("default", mode(api, "nameplate2"), name .. " error")
        api[name] = function() return SECRET end
        assert.are.equal("default", mode(api, "nameplate2"), name .. " secret")
        api[name] = nil
        assert.are.equal("default", mode(api, "nameplate2"), name .. " missing")
      end
      local api = world(nil)
      api.issecretvalue = function() error("boom") end
      assert.are.equal("default", mode(api, "nameplate2"))
      assert.are.equal("default", mode(world(nil), SECRET))
      assert.are.equal("default", mode(world(nil), nil))
      assert.are.equal("default", mode(nil, "nameplate2"))
    end)

    it("never makes a member compact when a membership answer is unknown", function()
      local api = world(nil)
      api.UnitInParty = function() error("boom") end
      assert.are.equal("default", mode(api, "nameplate1"))
    end)

    it("only counts exact booleans", function()
      local info = { member = false, player = true, self = false, friend = true, target = false }
      assert.are.equal("compact", Core.PlateMode(info, on))
      for _, k in ipairs({ "member", "player", "self", "friend", "target" }) do
        local copy = {}
        for kk, v in pairs(info) do
          copy[kk] = v
        end
        copy[k] = SECRET
        assert.are.equal("default", Core.PlateMode(copy, on), k)
        copy[k] = nil
        assert.are.equal("default", Core.PlateMode(copy, on), k .. " nil")
      end
      assert.are.equal("member", Core.PlateMode({ member = true }, on))
    end)
  end)

  describe("friend settings", function()
    it("fills the defaults", function()
      local db = Core.InitDB(nil)
      assert.are.equal("#3FA7FF", Core.FormatColor(unpack(db.friendcolor)))
      assert.are_not.equal(Core.DEFAULT_FRIEND_COLOR, db.friendcolor) -- a copy
      assert.is_true(db.friendchevron)
      assert.is_true(db.bnetfriends)
    end)

    it("defaults the chevron size of the friends and of the guildmates to 3 (1 to 5)", function()
      local db = Core.InitDB({ friendchevsize = 4.5, guildchevsize = 9 })
      assert.are.equal(4.5, db.friendchevsize)
      assert.are.equal(3, db.guildchevsize)
    end)

    it("defaults the outline thickness to 2 (0 to 5) for every kind, 0 meaning no outline", function()
      local db = Core.InitDB({ guildoutlinesize = 4, hostileoutlinesize = 9, friendoutlinesize = 0 })
      assert.are.equal(0, db.friendoutlinesize)
      assert.is_nil(Core.ParseFactor("-1", "friendoutlinesize"))
      assert.are.equal(0, Core.ParseFactor("0", "friendoutlinesize"))
      assert.is_nil(Core.ParseFactor("0", "chevsize"))
      assert.are.equal(2, db.memberoutlinesize)
      assert.are.equal(4, db.guildoutlinesize)
      assert.are.equal(2, db.hostileoutlinesize)
    end)

    it("keeps valid saved values", function()
      local db = Core.InitDB({ friendcolor = { 0, 1, 0 }, friendchevron = false, bnetfriends = false })
      assert.are.same({ 0, 1, 0 }, db.friendcolor)
      assert.is_false(db.friendchevron)
      assert.is_false(db.bnetfriends)
    end)

    it("replaces invalid saved values", function()
      for _, bad in ipairs({ "#00FF00", { 1, 2, 3 }, { 1, 0.5 }, { "1", 0, 0 }, { 0 / 0, 0, 0 }, true, 3 }) do
        local db = Core.InitDB({ friendcolor = bad, friendchevron = bad, bnetfriends = bad })
        assert.are.same(Core.DEFAULT_FRIEND_COLOR, db.friendcolor)
        assert.is_true(db.friendchevron)
        assert.is_true(db.bnetfriends)
      end
      for _, bad in ipairs({ "off", 0, {}, "false" }) do
        assert.is_true(Core.InitDB({ friendchevron = bad }).friendchevron, tostring(bad))
        assert.is_true(Core.InitDB({ bnetfriends = bad }).bnetfriends, tostring(bad))
      end
    end)
  end)

  describe("FriendLookup", function()
    local function api(list, bnet)
      return {
        IsFriend = function(guid) return list[guid] end,
        GetAccountInfoByGUID = function(guid) return bnet[guid] end,
        issecretvalue = function(v) return v == SECRET end,
      }
    end

    it("finds the character list first, then Battle.net", function()
      local a = api({ G1 = true, G2 = true }, { G2 = { isFriend = true }, G3 = { isFriend = true } })
      assert.are.same({ true, "list" }, { Core.FriendLookup(a, "G1", true) })
      assert.are.same({ true, "list" }, { Core.FriendLookup(a, "G2", true) })
      assert.are.same({ true, "bnet" }, { Core.FriendLookup(a, "G3", true) })
      assert.are.same({ false, "none" }, { Core.FriendLookup(a, "G4", true) })
    end)

    it("asks Battle.net only when bnet is on", function()
      local called = false
      local a = api({}, {})
      a.GetAccountInfoByGUID = function()
        called = true
        return { isFriend = true }
      end
      assert.are.same({ false, "none" }, { Core.FriendLookup(a, "G3", false) })
      assert.is_false(called)
      a.IsFriend = nil
      assert.are.same({ false, "missing" }, { Core.FriendLookup(a, "G3", false) })
      assert.is_false(called)
    end)

    it("counts every unknown answer as not a friend", function()
      local list = { G1 = SECRET, G2 = 1, G3 = "yes" }
      local bnet = { G1 = { isFriend = SECRET }, G2 = { isFriend = 1 }, G3 = SECRET, G4 = { isFriend = false },
        G5 = setmetatable({}, { __index = function() error("forbidden") end }), G6 = "x" }
      local a = api(list, bnet)
      for _, g in ipairs({ "G1", "G2", "G3", "G4", "G5", "G6" }) do
        assert.are.same({ false, "none" }, { Core.FriendLookup(a, g, true) }, g)
      end
      a.IsFriend = function() error("boom") end
      a.GetAccountInfoByGUID = function() error("boom") end
      assert.are.same({ false, "none" }, { Core.FriendLookup(a, "G1", true) })
      a.issecretvalue = function() error("boom") end
      a.IsFriend = function() return true end
      assert.are.same({ false, "noguid" }, { Core.FriendLookup(a, "G1", true) })
    end)

    it("needs a readable GUID and an API", function()
      local a = api({ G1 = true }, {})
      for _, g in ipairs({ nil, "", 12, SECRET }) do
        assert.are.same({ false, "noguid" }, { Core.FriendLookup(a, g, true) }, tostring(g))
      end
      assert.are.same({ false, "missing" }, { Core.FriendLookup({}, "G1", true) })
      assert.are.same({ false, "missing" }, { Core.FriendLookup(nil, "G1", true) })
      assert.are.same({ false, "missing" }, { Core.FriendLookup({ IsFriend = true }, "G1", true) })
    end)
  end)

  describe("guild settings", function()
    it("fills the defaults and keeps valid values", function()
      local db = Core.InitDB(nil)
      assert.are.equal("#40FF40", Core.FormatColor(unpack(db.guildcolor)))
      assert.are_not.equal(Core.DEFAULT_GUILD_COLOR, db.guildcolor) -- a copy
      assert.is_true(db.guildchevron)
      db = Core.InitDB({ guildcolor = { 1, 0, 0 }, guildchevron = false })
      assert.are.same({ 1, 0, 0 }, db.guildcolor)
      assert.is_false(db.guildchevron)
    end)

    it("replaces invalid saved values", function()
      for _, bad in ipairs({ "#00FF00", { 1, 2, 3 }, { 1, 0.5 }, { 0 / 0, 0, 0 }, true, 3 }) do
        local db = Core.InitDB({ guildcolor = bad, guildchevron = bad })
        assert.are.same(Core.DEFAULT_GUILD_COLOR, db.guildcolor)
        assert.is_true(db.guildchevron)
      end
    end)
  end)

  describe("GuildLookup", function()
    local function api(inGuild, byUnit, byGUID)
      return {
        IsInGuild = function() return inGuild end,
        UnitIsInMyGuild = byUnit and function(u) return byUnit[u] end or nil,
        IsPlayerInGuildFromGUID = byGUID and function(g) return byGUID[g] end or nil,
        issecretvalue = function(v) return v == SECRET end,
      }
    end

    it("asks UnitIsInMyGuild first", function()
      local a = api(true, { u1 = true }, { G2 = true })
      assert.are.same({ true, "unit" }, { Core.GuildLookup(a, "u1", "G1") })
      -- The GUID API is only the fallback of a missing function, not of a "no".
      assert.are.same({ false, "none" }, { Core.GuildLookup(a, "u2", "G2") })
    end)

    it("falls back to IsPlayerInGuildFromGUID when UnitIsInMyGuild is missing", function()
      local a = api(true, nil, { G2 = true })
      assert.are.same({ true, "guid" }, { Core.GuildLookup(a, "u2", "G2") })
      assert.are.same({ false, "none" }, { Core.GuildLookup(a, "u3", "G3") })
      for _, g in ipairs({ "", 12, SECRET }) do
        assert.are.same({ false, "noguid" }, { Core.GuildLookup(a, "u2", g) }, tostring(g))
      end
      assert.are.same({ false, "noguid" }, { Core.GuildLookup(a, "u2", nil) })
    end)

    it("asks no guild API when not in a guild", function()
      local called = false
      local a = api(false, {}, {})
      a.UnitIsInMyGuild = function() called = true return true end
      a.IsPlayerInGuildFromGUID = a.UnitIsInMyGuild
      assert.are.same({ false, "noguild" }, { Core.GuildLookup(a, "u1", "G1") })
      for _, v in ipairs({ SECRET, 1, "yes" }) do
        a.IsInGuild = function() return v end
        assert.are.same({ false, "noguild" }, { Core.GuildLookup(a, "u1", "G1") }, tostring(v))
      end
      a.IsInGuild = nil
      assert.are.same({ false, "noguild" }, { Core.GuildLookup(a, "u1", "G1") })
      assert.is_false(called)
    end)

    it("counts every unknown answer as not a guildmate", function()
      local a = api(true, { u1 = SECRET, u2 = 1, u3 = "yes" })
      for _, u in ipairs({ "u1", "u2", "u3", "u4" }) do
        assert.are.same({ false, "none" }, { Core.GuildLookup(a, u, "G") }, u)
      end
      a.UnitIsInMyGuild = function() error("boom") end
      assert.are.same({ false, "none" }, { Core.GuildLookup(a, "u1", "G") })
      a.UnitIsInMyGuild = function() return true end
      for _, u in ipairs({ "", 5, SECRET }) do
        assert.are.same({ false, "none" }, { Core.GuildLookup(a, u, "G") }, tostring(u))
      end
      a.IsInGuild = function() error("boom") end
      assert.are.same({ false, "noguild" }, { Core.GuildLookup(a, "u1", "G") })
      assert.are.same({ false, "missing" }, { Core.GuildLookup({ IsInGuild = function() return true end }, "u", "G") })
      assert.are.same({ false, "missing" }, { Core.GuildLookup(nil, "u", "G") })
    end)
  end)

  describe("PlateMode with guildmates", function()
    local on = { enabled = true, compact = true, bnetfriends = true }

    -- nameplate1 member (also guild), nameplate2 guildmate, nameplate3 guildmate who is also a
    -- friend, nameplate4 friendly player outside the guild, nameplate5 an enemy in the guild.
    local function world(target, inGuild)
      local players = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate4 = true,
        nameplate5 = true }
      local friendly = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate4 = true }
      local guild = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate5 = true }
      local api = fakeAPI(players, { nameplate1 = "party" })
      api.UnitIsFriend = function(a, b) return a == "player" and friendly[b] == true end
      api.UnitGUID = function(unit) return "G-" .. unit end
      api.IsFriend = function(guid) return guid == "G-nameplate3" end
      api.IsInGuild = function() return inGuild ~= false end
      api.UnitIsInMyGuild = function(unit) return guild[unit] == true end
      api.UnitIsUnit = function(a, b)
        if b == "target" then
          return a == target
        end
        if b == "player" then
          return false
        end
        return a == b
      end
      return api
    end

    local function mode(api, unit, settings)
      return { Core.PlateMode(Core.UnitInfo(api, unit, settings or on), settings or on) }
    end

    it("decides each case: member > friend > guildmate", function()
      local api = world(nil)
      assert.are.same({ "member", "member" }, mode(api, "nameplate1"))
      assert.are.same({ "compact", "guild" }, mode(api, "nameplate2"))
      assert.are.same({ "compact", "friend" }, mode(api, "nameplate3"))
      assert.are.same({ "compact" }, mode(api, "nameplate4"))
      assert.are.same({ "default" }, mode(api, "nameplate5"))
      local info = Core.UnitInfo(api, "nameplate2", on)
      assert.is_true(info.guild)
      assert.are.equal("unit", info.guildSource)
    end)

    it("keeps the mark on a targeted guildmate, with the full plate", function()
      assert.are.same({ "friend", "guild" }, mode(world("nameplate2"), "nameplate2"))
      assert.are.same({ "friend", "friend" }, mode(world("nameplate3"), "nameplate3"))
      assert.are.same({ "member", "member" }, mode(world("nameplate1"), "nameplate1"))
    end)

    it("follows compact off", function()
      local off = { enabled = true, compact = false, bnetfriends = true }
      local api = world(nil)
      assert.are.same({ "friend", "guild" }, mode(api, "nameplate2", off))
      assert.are.same({ "default" }, mode(api, "nameplate4", off))
    end)

    it("is off with the addon off, and nobody is a guildmate outside a guild", function()
      assert.are.same({ "default" }, mode(world(nil), "nameplate2", { enabled = false, compact = true }))
      local api = world(nil, false)
      assert.are.same({ "compact" }, mode(api, "nameplate2"))
      assert.are.equal("noguild", Core.UnitInfo(api, "nameplate2", on).guildSource)
    end)

    it("treats unknown, secret or missing guild answers as not a guildmate", function()
      local api = world(nil)
      api.UnitIsInMyGuild = function() error("boom") end
      assert.are.same({ "compact" }, mode(api, "nameplate2"))
      api.UnitIsInMyGuild = function() return SECRET end
      assert.are.same({ "compact" }, mode(api, "nameplate2"))
      api.UnitIsInMyGuild = nil
      assert.are.same({ "compact" }, mode(api, "nameplate2"))
      -- An unknown target keeps a guildmate's full plate (never compact).
      api = world(nil)
      local isUnit = api.UnitIsUnit
      api.UnitIsUnit = function(a, b)
        if b == "target" then
          return SECRET
        end
        return isUnit(a, b)
      end
      assert.are.same({ "friend", "guild" }, mode(api, "nameplate2"))
    end)
  end)

  describe("PlateMode with friends", function()
    local on = { enabled = true, compact = true, bnetfriends = true }

    -- world: nameplate1 member (also on the friends list), nameplate2 friendly player on the
    -- friends list, nameplate3 a Battle.net friend's character, nameplate4 a friendly player
    -- who is no friend, nameplate5 an enemy player on the friends list, nameplate6 the player.
    local function world(target)
      local players = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate4 = true,
        nameplate5 = true, nameplate6 = true }
      local friendly = { nameplate1 = true, nameplate2 = true, nameplate3 = true, nameplate4 = true,
        nameplate6 = true }
      local list = { ["G-nameplate1"] = true, ["G-nameplate2"] = true, ["G-nameplate5"] = true,
        ["G-nameplate6"] = true }
      local bnet = { ["G-nameplate3"] = { isFriend = true } }
      local api = fakeAPI(players, { nameplate1 = "party" })
      api.UnitIsFriend = function(a, b) return a == "player" and friendly[b] == true end
      api.UnitGUID = function(unit) return "G-" .. unit end
      api.IsFriend = function(guid) return list[guid] == true end
      api.GetAccountInfoByGUID = function(guid) return bnet[guid] end
      api.UnitIsUnit = function(a, b)
        if b == "target" then
          return a == target
        end
        if b == "player" then
          return a == "nameplate6"
        end
        return a == b
      end
      return api
    end

    local function mode(api, unit, settings)
      return { Core.PlateMode(Core.UnitInfo(api, unit, settings or on), settings or on) }
    end

    it("decides each case, a member never being a friend", function()
      local api = world(nil)
      assert.are.same({ "member", "member" }, mode(api, "nameplate1"))
      assert.are.same({ "compact", "friend" }, mode(api, "nameplate2"))
      assert.are.same({ "compact", "friend" }, mode(api, "nameplate3"))
      assert.are.same({ "compact" }, mode(api, "nameplate4"))
      assert.are.same({ "default" }, mode(api, "nameplate5"))
      assert.are.same({ "default" }, mode(api, "nameplate6"))
      local info = Core.UnitInfo(api, "nameplate2", on)
      assert.is_true(info.listed)
      assert.are.equal("list", info.source)
      assert.are.equal("bnet", Core.UnitInfo(api, "nameplate3", on).source)
    end)

    it("keeps the colour on a friend who is the target, with the full plate", function()
      assert.are.same({ "friend", "friend" }, mode(world("nameplate2"), "nameplate2"))
      assert.are.same({ "friend", "friend" }, mode(world("nameplate3"), "nameplate3"))
      assert.are.same({ "member", "member" }, mode(world("nameplate1"), "nameplate1"))
      assert.are.same({ "default" }, mode(world("nameplate4"), "nameplate4"))
    end)

    it("follows compact off", function()
      local off = { enabled = true, compact = false, bnetfriends = true }
      local api = world(nil)
      assert.are.same({ "friend", "friend" }, mode(api, "nameplate2", off))
      assert.are.same({ "default" }, mode(api, "nameplate4", off))
      assert.are.same({ "member", "member" }, mode(api, "nameplate1", off))
    end)

    it("counts Battle.net friends only with bnetfriends on", function()
      local noBNet = { enabled = true, compact = true, bnetfriends = false }
      local api = world(nil)
      assert.are.same({ "compact" }, mode(api, "nameplate3", noBNet))
      assert.are.equal("none", Core.UnitInfo(api, "nameplate3", noBNet).source)
      assert.are.same({ "compact", "friend" }, mode(api, "nameplate2", noBNet))
      -- An info claiming Battle.net while the setting is off is no friend either.
      local info = { member = false, player = true, self = false, friend = true, target = false, listed = true,
        source = "bnet" }
      assert.are.same({ "compact" }, { Core.PlateMode(info, noBNet) })
      assert.are.same({ "compact", "friend" }, { Core.PlateMode(info, on) })
    end)

    it("treats unknown or secret friend answers as not a friend", function()
      for _, name in ipairs({ "UnitGUID", "IsFriend", "GetAccountInfoByGUID" }) do
        local api = world(nil)
        api[name] = function() error("boom") end
        if name ~= "GetAccountInfoByGUID" then
          assert.are.same({ "compact" }, mode(api, "nameplate2"), name .. " error")
        end
        api[name] = function() return SECRET end
        assert.are.same({ "compact" }, mode(api, name == "IsFriend" and "nameplate2" or "nameplate3"),
          name .. " secret")
        api[name] = nil
        assert.are.same({ "compact" }, mode(api, name == "IsFriend" and "nameplate2" or "nameplate3"),
          name .. " missing")
      end
      -- Without both friend APIs: "missing".
      local api = world(nil)
      api.IsFriend, api.GetAccountInfoByGUID = nil, nil
      assert.are.equal("missing", Core.UnitInfo(api, "nameplate2", on).source)
      -- An unknown target keeps a friend's full plate (never compact).
      api = world(nil)
      local isUnit = api.UnitIsUnit
      api.UnitIsUnit = function(a, b)
        if b == "target" then
          return SECRET
        end
        return isUnit(a, b)
      end
      assert.are.same({ "friend", "friend" }, mode(api, "nameplate2"))
      -- An unknown membership is never a friend.
      api = world(nil)
      api.UnitInParty = function() error("boom") end
      assert.are.same({ "default" }, mode(api, "nameplate2"))
    end)

    it("leaves every plate alone with the addon off", function()
      local off = { enabled = false, compact = true, bnetfriends = true }
      local api = world(nil)
      for _, unit in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do
        assert.are.same({ "default" }, mode(api, unit, off), unit)
      end
      assert.is_nil(Core.Relation(nil, on))
    end)

    it("shows the level of friendly non-members only, compact or not, target or not", function()
      local shows = function(api, unit, settings)
        settings = settings or on
        return Core.ShowsLevel(Core.UnitInfo(api, unit, settings), settings)
      end
      local api = world(nil)
      assert.is_false(shows(api, "nameplate1")) -- member (also a friend)
      assert.is_true(shows(api, "nameplate2")) -- friend
      assert.is_true(shows(api, "nameplate3")) -- Battle.net friend
      assert.is_true(shows(api, "nameplate4")) -- friendly player
      assert.is_false(shows(api, "nameplate5")) -- enemy player
      assert.is_false(shows(api, "nameplate6")) -- the player
      assert.is_true(shows(world("nameplate4"), "nameplate4")) -- the target
      assert.is_true(shows(world("nameplate2"), "nameplate2"))
      local compactOff = { enabled = true, compact = false, bnetfriends = true }
      assert.is_true(shows(api, "nameplate4", compactOff))
      assert.is_true(shows(api, "nameplate2", compactOff))
      assert.is_false(shows(api, "nameplate1", compactOff))
      -- showlevel off, the addon off, or an unknown membership: no level.
      assert.is_false(shows(api, "nameplate4", { enabled = true, compact = true, showlevel = false }))
      assert.is_false(shows(api, "nameplate4", { enabled = false, compact = true }))
      local unknown = world(nil)
      unknown.UnitInParty = function() error("boom") end
      assert.is_false(shows(unknown, "nameplate4"))
      assert.is_false(Core.ShowsLevel(nil, on))
      assert.is_false(Core.ShowsLevel({ member = false, player = true, self = false, friend = true }, nil))
    end)

    it("gives the friendlies' sizes to friendly non-members, full plate or compact, target or not", function()
      local sizes = function(api, unit, settings)
        settings = settings or on
        return Core.OtherSizes(Core.UnitInfo(api, unit, settings), settings)
      end
      local api = world(nil)
      assert.is_false(sizes(api, "nameplate1")) -- member: textsize / barsize
      assert.is_true(sizes(api, "nameplate2")) -- friend
      assert.is_true(sizes(api, "nameplate3")) -- Battle.net friend
      assert.is_true(sizes(api, "nameplate4")) -- friendly player
      assert.is_false(sizes(api, "nameplate5")) -- enemy player
      assert.is_false(sizes(api, "nameplate6")) -- the player
      -- The target is a full plate with compact on: still the friendlies' sizes.
      local target = world("nameplate4")
      assert.are.same({ "default" }, mode(target, "nameplate4"))
      assert.is_true(sizes(target, "nameplate4"))
      assert.is_true(sizes(world("nameplate2"), "nameplate2"))
      local compactOff = { enabled = true, compact = false, bnetfriends = true }
      assert.is_true(sizes(api, "nameplate4", compactOff))
      assert.is_true(sizes(target, "nameplate4", compactOff))
      assert.is_false(sizes(api, "nameplate1", compactOff))
      -- showlevel does not matter; the addon off or an unknown membership: no sizes.
      assert.is_true(sizes(api, "nameplate4", { enabled = true, compact = true, showlevel = false }))
      assert.is_false(sizes(api, "nameplate4", { enabled = false, compact = true }))
      local unknown = world(nil)
      unknown.UnitInParty = function() error("boom") end
      assert.is_false(sizes(unknown, "nameplate4"))
      assert.is_false(Core.OtherSizes(nil, on))
      assert.is_false(Core.OtherSizes({ member = false, player = true, self = false, friend = true }, nil))
    end)
  end)

  describe("showlevel setting", function()
    it("defaults to on and keeps a saved boolean", function()
      assert.is_true(Core.InitDB(nil).showlevel)
      assert.is_true(Core.InitDB({}).showlevel)
      assert.is_false(Core.InitDB({ showlevel = false }).showlevel)
      assert.is_true(Core.InitDB({ showlevel = true }).showlevel)
    end)

    it("replaces an invalid value by on", function()
      for _, bad in ipairs({ "off", 0, 1, {}, "false" }) do
        assert.is_true(Core.InitDB({ showlevel = bad }).showlevel, tostring(bad))
      end
    end)
  end)

  describe("UnitLevel", function()
    local function api(level)
      return {
        UnitLevel = function() return level end,
        issecretvalue = function(v) return v == SECRET end,
      }
    end

    it("returns a readable level, -1 or less included", function()
      assert.are.equal(19, Core.UnitLevel(api(19), "nameplate2"))
      assert.are.equal(1, Core.UnitLevel(api(1), "nameplate2"))
      assert.are.equal(-1, Core.UnitLevel(api(-1), "nameplate2"))
      assert.are.equal(-2, Core.UnitLevel(api(-2), "nameplate2"))
    end)

    it("returns nil for a level that cannot be read", function()
      assert.is_nil(Core.UnitLevel(api(SECRET), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(nil), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api("19"), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(0), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(19.5), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(0 / 0), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(math.huge), "nameplate2"))
      assert.is_nil(Core.UnitLevel(api(19), SECRET))
      assert.is_nil(Core.UnitLevel(api(19), ""))
      assert.is_nil(Core.UnitLevel(api(19), nil))
      assert.is_nil(Core.UnitLevel({}, "nameplate2"))
      assert.is_nil(Core.UnitLevel(nil, "nameplate2"))
      local boom = api(19)
      boom.UnitLevel = function() error("restricted") end
      assert.is_nil(Core.UnitLevel(boom, "nameplate2"))
    end)
  end)

  describe("NameWithLevel", function()
    it("puts the level in brackets after the name", function()
      local cases = {
        { "Garzak", 19, "Garzak (19)" },
        { "Garzak", 1, "Garzak (1)" },
        { "Garzak", 60, "Garzak (60)" },
        { "Фарбатос", 7, "Фарбатос (7)" },
        { "Garzak", -1, "Garzak (??)" },
        { "Garzak", -5, "Garzak (??)" },
        -- Not readable: the name alone.
        { "Garzak", nil, "Garzak" },
        { "Garzak", "19", "Garzak" },
        { "Garzak", {}, "Garzak" },
        { "Garzak", 0, "Garzak" },
        { "Garzak", 2.5, "Garzak" },
        { "Garzak", 0 / 0, "Garzak" },
        { "Garzak", math.huge, "Garzak" },
        -- No name: returned as it is.
        { "", 19, "" },
      }
      for _, c in ipairs(cases) do
        assert.are.equal(c[3], Core.NameWithLevel(c[1], c[2]), tostring(c[1]) .. " " .. tostring(c[2]))
      end
      assert.is_nil(Core.NameWithLevel(nil, 19))
      assert.are.equal(5, Core.NameWithLevel(5, 19))
    end)
  end)

  describe("class colour setting", function()
    it("defaults to on and replaces invalid saved values", function()
      assert.is_true(Core.InitDB(nil).classcolor)
      assert.is_true(Core.InitDB({ classcolor = true }).classcolor)
      assert.is_false(Core.InitDB({ classcolor = false }).classcolor)
      for _, bad in ipairs({ "on", 1, {}, "true", 0 / 0 }) do
        assert.is_true(Core.InitDB({ classcolor = bad }).classcolor, tostring(bad))
      end
    end)
  end)

  describe("ClassColor", function()
    local MAGE = { 0.25, 0.78, 0.92 }
    local function color(c)
      return { GetRGB = function() return c[1], c[2], c[3] end }
    end
    local function api(classes, modern, raid)
      return {
        UnitClass = function(unit)
          local token = classes[unit]
          return token and ("Localised " .. tostring(token)), token, 8
        end,
        GetClassColor = modern and function(token) return modern[token] end or nil,
        RAID_CLASS_COLORS = raid,
        issecretvalue = function(v) return v == SECRET end,
      }
    end

    it("reads the token and C_ClassColor's colour first", function()
      local a = api({ u = "MAGE" }, { MAGE = color(MAGE) }, { MAGE = { r = 1, g = 0, b = 0 } })
      assert.are.same({ "MAGE", MAGE[1], MAGE[2], MAGE[3] }, { Core.ClassColor(a, "u") })
    end)

    it("falls back to RAID_CLASS_COLORS", function()
      local raid = { WARLOCK = { r = 0.53, g = 0.53, b = 0.93 } }
      local a = api({ u = "WARLOCK" }, nil, raid)
      assert.are.same({ "WARLOCK", 0.53, 0.53, 0.93 }, { Core.ClassColor(a, "u") })
      -- C_ClassColor knows nothing, errors, or answers garbage: the table answers.
      for _, modern in ipairs({ {}, { WARLOCK = SECRET }, { WARLOCK = "x" }, { WARLOCK = color({ 2, 0, 0 }) },
        { WARLOCK = color({ SECRET, 0, 0 }) }, { WARLOCK = { GetRGB = function() error("boom") end } } }) do
        assert.are.same({ "WARLOCK", 0.53, 0.53, 0.93 }, { Core.ClassColor(api({ u = "WARLOCK" }, modern, raid), "u") })
      end
      a = api({ u = "WARLOCK" }, nil, raid)
      a.GetClassColor = function() error("boom") end
      assert.are.same({ "WARLOCK", 0.53, 0.53, 0.93 }, { Core.ClassColor(a, "u") })
      -- A ColorMixin without GetRGB is read by its fields.
      assert.are.same({ "WARLOCK", 0.1, 0.2, 0.3 },
        { Core.ClassColor(api({ u = "WARLOCK" }, { WARLOCK = { r = 0.1, g = 0.2, b = 0.3 } }), "u") })
    end)

    it("gives the token without a colour when none is known", function()
      local raid = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, BAD = { r = 1, g = "0", b = 0 }, SEC = SECRET,
        BIG = { r = 1.5, g = 0, b = 0 } }
      for _, token in ipairs({ "PIRATE", "BAD", "SEC", "BIG" }) do
        assert.are.same({ token }, { Core.ClassColor(api({ u = token }, {}, raid), "u") }, token)
      end
      assert.are.same({ "MAGE" }, { Core.ClassColor(api({ u = "MAGE" }), "u") })
      local forbidden = setmetatable({}, { __index = function() error("forbidden") end })
      assert.are.same({ "MAGE" }, { Core.ClassColor(api({ u = "MAGE" }, nil, forbidden), "u") })
    end)

    it("gives nothing without a readable token", function()
      local good = { MAGE = color(MAGE) }
      for _, token in ipairs({ SECRET, "", 12 }) do
        assert.are.same({}, { Core.ClassColor(api({ u = token }, good), "u") }, tostring(token))
      end
      assert.are.same({}, { Core.ClassColor(api({}, good), "u") })
      local a = api({ u = "MAGE" }, good)
      a.UnitClass = function() error("restricted") end
      assert.are.same({}, { Core.ClassColor(a, "u") })
      a.UnitClass = nil
      assert.are.same({}, { Core.ClassColor(a, "u") })
      a = api({ u = "MAGE" }, good)
      for _, unit in ipairs({ SECRET, "", 3 }) do
        assert.are.same({}, { Core.ClassColor(a, unit) }, tostring(unit))
      end
      assert.are.same({}, { Core.ClassColor(nil, "u") })
    end)
  end)

  describe("NameColor and PlateMode with the class colour", function()
    local MAGE = { 0.25, 0.78, 0.92 }
    local function settings(over)
      local s = { enabled = true, compact = true, bnetfriends = true, classcolor = true }
      for k, v in pairs(over or {}) do
        s[k] = v
      end
      return s
    end
    -- other is a friendly player who is not a member, not a friend and not the player; over
    -- changes fields, the keys listed in unset are removed (unknown).
    local function other(over, unset)
      local info = { member = false, player = true, self = false, friend = true, target = false, listed = false,
        source = "none", class = "MAGE", classColor = MAGE }
      for k, v in pairs(over or {}) do
        info[k] = v
      end
      for _, k in ipairs(unset or {}) do
        info[k] = nil
      end
      return info
    end
    local function decide(info, s)
      local mode, relation = Core.PlateMode(info, s)
      return { mode, relation, Core.NameColor(info, s, relation) }
    end

    it("colours other friendlies, compact on or off, target or not", function()
      assert.are.same({ "compact", nil, "class" }, decide(other(), settings()))
      assert.are.same({ "class", nil, "class" }, decide(other({ target = true }), settings()))
      assert.are.same({ "class", nil, "class" }, decide(other(), settings({ compact = false })))
      assert.are.same({ "class", nil, "class" }, decide(other({ target = true }), settings({ compact = false })))
      -- An unknown target is never compact: the full plate, in the class colour.
      assert.are.same({ "class", nil, "class" }, decide(other(nil, { "target" }), settings()))
    end)

    it("never applies to members, and friends keep the friend colour", function()
      local member = other({ member = true, listed = true, source = "list" })
      assert.are.same({ "member", "member", "member" }, decide(member, settings()))
      assert.are.same({ "member", "member", "member" }, decide(member, settings({ compact = false })))
      local friend = other({ listed = true, source = "list" })
      assert.are.same({ "compact", "friend", "friend" }, decide(friend, settings()))
      assert.are.same({ "friend", "friend", "friend" }, decide(friend, settings({ compact = false })))
      assert.are.same({ "friend", "friend", "friend" }, decide(other({ listed = true, source = "list", target = true }),
        settings()))
      -- A Battle.net friend with bnetfriends off is just another friendly: the class colour.
      local bnet = other({ listed = true, source = "bnet" })
      assert.are.same({ "compact", nil, "class" }, decide(bnet, settings({ bnetfriends = false })))
    end)

    it("keeps the colour the name would have without the setting", function()
      for _, s in ipairs({ settings({ classcolor = false }), settings({ classcolor = "on" }) }) do
        assert.are.same({ "compact" }, decide(other(), s))
        assert.are.same({ "default" }, decide(other({ target = true }), s))
        assert.are.same({ "default" }, decide(other(), settings({ compact = false, classcolor = s.classcolor })))
      end
      -- Unknown class or colour.
      for _, c in ipairs({ false, { 1, 2, 3 }, { 0.5, 0.5 }, "blue" }) do
        local unset = c == false and { "classColor" } or nil
        local over = c ~= false and { classColor = c } or nil
        local info = other(over, unset)
        info.target = true
        assert.are.same({ "default" }, decide(info, settings()), tostring(c))
        assert.are.same({ "compact" }, decide(other(over, unset), settings()), tostring(c))
      end
      -- Addon off.
      assert.are.same({ "default" }, decide(other({ target = true }), settings({ enabled = false })))
      assert.is_nil(Core.NameColor(other(), settings({ enabled = false }), nil))
    end)

    it("never colours enemies, NPCs, the player or unknown answers", function()
      for _, over in ipairs({ { friend = false }, { player = false }, { self = true }, { member = "no" } }) do
        local info = other(over)
        info.target = true
        assert.are.same({ "default" }, decide(info, settings()))
      end
      for _, key in ipairs({ "friend", "player", "self", "member" }) do
        local info = other({ target = true }, { key })
        assert.are.same({ "default" }, decide(info, settings()), key)
      end
      assert.is_nil(Core.NameColor(nil, settings(), nil))
      assert.is_nil(Core.NameColor(other(), nil, nil))
    end)

    it("is read by UnitInfo only with the setting on", function()
      local calls = 0
      local api = fakeAPI({ nameplate4 = true }, {})
      api.UnitIsFriend = function() return true end
      api.UnitClass = function()
        calls = calls + 1
        return "Mage", "MAGE", 8
      end
      api.RAID_CLASS_COLORS = { MAGE = { r = MAGE[1], g = MAGE[2], b = MAGE[3] } }
      local info = Core.UnitInfo(api, "nameplate4", settings({ classcolor = false }))
      assert.is_nil(info.class)
      assert.is_nil(info.classColor)
      assert.are.equal(0, calls)
      info = Core.UnitInfo(api, "nameplate4", settings())
      assert.are.equal("MAGE", info.class)
      assert.are.same(MAGE, info.classColor)
      assert.are.same({ "compact", nil, "class" }, decide(info, settings()))
      api.RAID_CLASS_COLORS = nil
      info = Core.UnitInfo(api, "nameplate4", settings())
      assert.are.equal("MAGE", info.class)
      assert.is_nil(info.classColor)
      assert.are.same({ "compact" }, decide(info, settings()))
    end)
  end)

  describe("HealthMissing", function()
    local function api(hp, max)
      return {
        UnitHealth = function() return hp end,
        UnitHealthMax = function() return max end,
        issecretvalue = function(v) return v == SECRET end,
      }
    end

    it("is true only for a known health below its maximum", function()
      assert.is_true(Core.HealthMissing(api(50, 100), "nameplate2"))
      assert.is_true(Core.HealthMissing(api(0, 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(100, 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(120, 100), "nameplate2"))
    end)

    it("treats unknown health as full", function()
      assert.is_false(Core.HealthMissing(api(SECRET, 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(50, SECRET), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(nil, 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api("50", 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(50, 0), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(0 / 0, 100), "nameplate2"))
      assert.is_false(Core.HealthMissing(api(50, 100), SECRET))
      assert.is_false(Core.HealthMissing(api(50, 100), ""))
      assert.is_false(Core.HealthMissing(nil, "nameplate2"))
      assert.is_false(Core.HealthMissing({}, "nameplate2"))
      local boom = api(50, 100)
      boom.UnitHealth = function() error("restricted") end
      assert.is_false(Core.HealthMissing(boom, "nameplate2"))
    end)
  end)

  describe("HealthCurve and HealthAlpha", function()
    -- poison is a value that raises an error on any read (arithmetic, comparison, concatenation,
    -- indexing, calling, tostring), as a secret value in game.
    local function poison()
      local p = newproxy(true)
      local mt = getmetatable(p)
      local function boom() error("secret value read") end
      for _, k in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len",
        "__eq", "__lt", "__le", "__index", "__newindex", "__call", "__tostring" }) do
        mt[k] = boom
      end
      return p
    end

    local function api()
      local a = { calls = {} }
      a.CreateColor = function(r, g, b, alpha) return { r, g, b, alpha } end
      a.CreateColorCurve = function()
        local curve = { points = {} }
        function curve:AddPoint(x, c) self.points[#self.points + 1] = { x, c } end
        return curve
      end
      a.alpha = poison()
      a.UnitHealthPercent = function(unit, predicted, curve)
        a.calls[#a.calls + 1] = { unit, predicted, curve }
        return { GetRGBA = function() return 1, 1, 1, a.alpha end }
      end
      a.issecretvalue = function(v) return v == SECRET or rawequal(v, a.alpha) end
      return a
    end

    it("builds a white curve: alpha 1 below full health, 0 at full health", function()
      local curve = Core.HealthCurve(api())
      assert.are.same({ { 0, { 1, 1, 1, 1 } }, { 0.999, { 1, 1, 1, 1 } }, { 1, { 1, 1, 1, 0 } } }, curve.points)
    end)

    it("builds the opposite curve for the name with the level: alpha 0 below full health, 1 at full", function()
      local curve = Core.HealthCurve(api(), Core.FULL_HEALTH_CURVE_POINTS)
      assert.are.same({ { 0, { 1, 1, 1, 0 } }, { 0.999, { 1, 1, 1, 0 } }, { 1, { 1, 1, 1, 1 } } }, curve.points)
    end)

    it("refuses to build the curve without a working API", function()
      assert.is_nil(Core.HealthCurve(nil))
      assert.is_nil(Core.HealthCurve({}))
      for _, broken in ipairs({
        function(a) a.CreateColorCurve = nil end,
        function(a) a.CreateColor = nil end,
        function(a) a.CreateColorCurve = function() error("boom") end end,
        function(a) a.CreateColorCurve = function() return nil end end,
        function(a) a.CreateColorCurve = function() return SECRET end end,
        function(a) a.CreateColorCurve = function() return 1 end end,
        function(a) a.CreateColorCurve = function() return {} end end, -- no AddPoint
        function(a) a.CreateColor = function() error("boom") end end,
        function(a) a.CreateColor = function() return nil end end,
      }) do
        local a = api()
        broken(a)
        assert.is_nil(Core.HealthCurve(a))
      end
    end)

    it("returns the curve's alpha untouched, even a secret one", function()
      local a = api()
      local curve = Core.HealthCurve(a)
      local ok, alpha = Core.HealthAlpha(a, "nameplate2", curve)
      assert.is_true(ok)
      assert.is_true(rawequal(a.alpha, alpha))
      assert.are.equal(1, #a.calls)
      assert.are.equal("nameplate2", a.calls[1][1])
      assert.is_false(a.calls[1][2]) -- not the predicted health
      assert.are.equal(curve, a.calls[1][3])
      -- A plain alpha (no secret values on this client) too.
      a.alpha = 0
      assert.are.same({ true, 0 }, { Core.HealthAlpha(a, "nameplate2", curve) })
    end)

    it("is false when the alpha cannot be had", function()
      local a = api()
      local curve = Core.HealthCurve(a)
      assert.is_false(Core.HealthAlpha(nil, "nameplate2", curve))
      assert.is_false(Core.HealthAlpha(a, "nameplate2", nil))
      assert.is_false(Core.HealthAlpha(a, "", curve))
      assert.is_false(Core.HealthAlpha(a, nil, curve))
      assert.is_false(Core.HealthAlpha(a, SECRET, curve))
      for _, broken in ipairs({
        function(b) b.UnitHealthPercent = nil end,
        function(b) b.UnitHealthPercent = function() error("refused") end end,
        function(b) b.UnitHealthPercent = function() return nil end end,
        function(b) b.UnitHealthPercent = function() return 0.5 end end, -- the curve was ignored
        function(b) b.UnitHealthPercent = function() return SECRET end end,
        function(b) b.UnitHealthPercent = function() return {} end end, -- no GetRGBA
        function(b) b.UnitHealthPercent = function() return { GetRGBA = function() error("boom") end } end end,
      }) do
        local b = api()
        broken(b)
        assert.is_false(Core.HealthAlpha(b, "nameplate2", curve))
      end
    end)
  end)

  describe("LevelSuffix", function()
    it("drives both names by the curves only when the bar's alpha was applied", function()
      assert.are.equal("curve", Core.LevelSuffix(true, true, false))
      assert.are.equal("curve", Core.LevelSuffix(true, true, nil))
    end)

    it("keeps the suffix when the curve's alpha could not reach the bar (in doubt)", function()
      assert.are.equal("show", Core.LevelSuffix(true, false, false))
      assert.are.equal("show", Core.LevelSuffix(true, nil, true))
    end)

    it("follows the readable health without the curve", function()
      assert.are.equal("hide", Core.LevelSuffix(false, false, true)) -- hurt: bar shown
      assert.are.equal("show", Core.LevelSuffix(false, false, false)) -- full or unknown: bar hidden
      assert.are.equal("show", Core.LevelSuffix(nil, nil, nil))
    end)

    it("counts only exact boolean answers", function()
      assert.are.equal("show", Core.LevelSuffix(1, true, false))
      assert.are.equal("show", Core.LevelSuffix(true, 1, false))
      assert.are.equal("show", Core.LevelSuffix(false, false, 1))
      assert.are.equal("show", Core.LevelSuffix(false, false, SECRET))
    end)
  end)
end)

describe("Core service NPCs", function()
  local GUID = "Creature-0-4372-0-1-352-0000ABCDEF"

  -- npcAPI is a world with one friendly NPC "nameplate5" (creature 352) whose tooltip's second
  -- line is subtitle, on a client in locale.
  local function npcAPI(subtitle, locale, overrides)
    local api = {
      UnitIsPlayer = function() return false end,
      UnitInParty = function() return false end,
      UnitInRaid = function() return nil end,
      UnitIsUnit = function(a, b) return a == b end,
      UnitIsFriend = function() return true end,
      UnitCanAttack = function() return false end,
      UnitGUID = function() return GUID end,
      GetLocale = function() return locale or "enUS" end,
      GetTooltipUnit = function()
        return { lines = { { leftText = "Thor" }, subtitle and { leftText = subtitle } or nil } }
      end,
    }
    for k, v in pairs(overrides or {}) do
      api[k] = v
    end
    return api
  end

  local ON = { enabled = true, npcicons = true, npcroles = {} }

  it("lists the roles in priority order, each with an icon", function()
    local keys = {}
    for _, r in ipairs(Core.ROLES) do
      keys[#keys + 1] = r.key
      assert.is_string(Core.RoleIcon(r.key))
    end
    assert.are.same({ "flight", "innkeeper", "banker", "auctioneer", "stable", "profession", "trainer", "repair",
      "vendor" }, keys)
    assert.is_nil(Core.RoleIcon("nope"))
    assert.is_false(Core.ValidRole("nope"))
    assert.is_false(Core.ValidRole(nil))
  end)

  it("keeps the better of two roles", function()
    assert.are.equal("repair", Core.BetterRole("vendor", "repair"))
    assert.are.equal("innkeeper", Core.BetterRole("innkeeper", "vendor"))
    assert.are.equal("flight", Core.BetterRole(nil, "flight"))
    assert.are.equal("flight", Core.BetterRole("flight", "bogus"))
    assert.is_nil(Core.BetterRole(nil, "bogus"))
  end)

  it("reads the creature ID of an NPC's GUID only", function()
    assert.are.equal(352, Core.NpcID(GUID))
    assert.are.equal(1234, Core.NpcID("Vehicle-0-1-2-3-1234-00AB"))
    assert.is_nil(Core.NpcID("Player-1085-0998E434"))
    assert.is_nil(Core.NpcID("Pet-0-4372-0-1-416-0100ABCDEF"))
    assert.is_nil(Core.NpcID("GameObject-0-1-2-3-55-00AB"))
    assert.is_nil(Core.NpcID("Creature-0-1-2-3-0-00AB"))
    assert.is_nil(Core.NpcID(""))
    assert.is_nil(Core.NpcID(nil))
  end)

  it("finds the role in an English or French subtitle", function()
    assert.are.equal("flight", Core.SubtitleRole("<Gryphon Master>", "enUS"))
    assert.are.equal("flight", Core.SubtitleRole("Wind Rider Master", "enGB"))
    assert.are.equal("innkeeper", Core.SubtitleRole("Innkeeper", "enUS"))
    assert.are.equal("repair", Core.SubtitleRole("Armorer & Shieldcrafter", "enUS"))
    assert.are.equal("vendor", Core.SubtitleRole("Trade Supplies", "enUS"))
    assert.are.equal("profession", Core.SubtitleRole("Blacksmithing Trainer", "enUS"))
    assert.are.equal("trainer", Core.SubtitleRole("Warrior Trainer", "enUS"))
    assert.are.equal("vendor", Core.SubtitleRole("Tailoring Supplies", "enUS"))
    assert.are.equal("stable", Core.SubtitleRole("Stable Master", "enUS"))
    assert.are.equal("flight", Core.SubtitleRole("Maître des griffons", "frFR"))
    -- As the Forever client spells it (seen in game), with or without the brackets.
    assert.are.equal("flight", Core.SubtitleRole("Maître des gryphons", "frFR"))
    assert.are.equal("flight", Core.SubtitleRole("<Maître des gryphons>", "frFR"))
    assert.are.equal("innkeeper", Core.SubtitleRole("Aubergiste", "frFR"))
    assert.are.equal("vendor", Core.SubtitleRole("Marchande de nourriture", "frFR"))
    -- French profession trainers, as the Forever client writes them (seen in game).
    assert.are.equal("profession", Core.SubtitleRole("Enchanteur - compagnon", "frFR"))
    assert.are.equal("profession", Core.SubtitleRole("<Travailleuse du cuir - artisan>", "frFR"))
    assert.are.equal("vendor", Core.SubtitleRole("Fournitures d'enchanteur", "frFR"))
    -- No subtitle (the level line), no words for the locale, nothing readable: no role.
    assert.is_nil(Core.SubtitleRole("Level 30", "enUS"))
    assert.is_nil(Core.SubtitleRole("Innkeeper", "deDE"))
    assert.is_nil(Core.SubtitleRole("Innkeeper", nil))
    assert.is_nil(Core.SubtitleRole(nil, "enUS"))
    assert.is_nil(Core.SubtitleRole("", "enUS"))
  end)

  it("maps the windows an NPC opens to its role, a merchant who repairs to repair", function()
    assert.are.equal("vendor", Core.InteractionRole("merchant", false))
    assert.are.equal("repair", Core.InteractionRole("merchant", true))
    assert.are.equal("flight", Core.InteractionRole("taxi"))
    assert.are.equal("innkeeper", Core.InteractionRole("binder"))
    assert.are.equal("stable", Core.InteractionRole("stable"))
    assert.are.equal("trainer", Core.InteractionRole("trainer", false))
    assert.are.equal("profession", Core.InteractionRole("trainer", true))
    assert.is_nil(Core.InteractionRole("mailbox"))
    assert.is_nil(Core.InteractionRole(nil))
  end)

  it("learns a role by creature ID, only upgrading it", function()
    local roles = {}
    assert.is_true(Core.LearnRole(roles, 352, "vendor"))
    assert.are.equal("vendor", roles[352])
    assert.is_false(Core.LearnRole(roles, 352, "vendor"))
    assert.is_true(Core.LearnRole(roles, 352, "repair"))
    assert.is_false(Core.LearnRole(roles, 352, "vendor"))
    assert.are.equal("repair", roles[352])
    assert.is_false(Core.LearnRole(roles, nil, "vendor"))
    assert.is_false(Core.LearnRole(roles, 1.5, "vendor"))
    assert.is_false(Core.LearnRole(roles, 7, "bogus"))
    assert.is_false(Core.LearnRole(nil, 7, "vendor"))
  end)

  it("tells texture paths from atlases, and crops only Interface\\Icons textures", function()
    assert.is_true(Core.IsTexturePath("Interface\\Icons\\INV_Misc_Coin_01"))
    assert.is_true(Core.IsTexturePath("interface/icons/inv_misc_coin_01"))
    assert.is_false(Core.IsTexturePath("FlightMaster"))
    assert.are.same(Core.ICON_CROP, Core.IconCrop("Interface\\Icons\\INV_Misc_Coin_01"))
    assert.are.same(Core.ICON_CROP, Core.IconCrop("interface/icons/inv_misc_coin_01"))
    assert.are.same(Core.FULL_CROP, Core.IconCrop("Interface\\Minimap\\Tracking\\Repair"))
    assert.are.same(Core.FULL_CROP, Core.IconCrop("FlightMaster"))
    assert.is_true(Core.ValidIconName("Crosshair_Taxi_32"))
    assert.is_false(Core.ValidIconName("bad name"))
    assert.is_false(Core.ValidIconName(""))
    assert.are.same({ flight = "FlightMaster" },
      Core.CleanRoleIcons({ flight = "FlightMaster", wizard = "X", vendor = "bad name" }))
    assert.are.same({}, Core.InitDB({}).roleicons)
  end)

  it("reads a unit's guild name, never a secret, an error or an empty name", function()
    assert.are.equal("Ordo", Core.GuildName({ GetGuildInfo = function() return "Ordo", "Officer", 1 end }, "u"))
    assert.is_nil(Core.GuildName({ GetGuildInfo = function() return nil end }, "u"))
    assert.is_nil(Core.GuildName({ GetGuildInfo = function() return "" end }, "u"))
    assert.is_nil(Core.GuildName({ GetGuildInfo = function() error("x") end }, "u"))
    assert.is_nil(Core.GuildName({}, "u"))
    assert.is_nil(Core.GuildName({ GetGuildInfo = function() return SECRET end,
      issecretvalue = function(v) return v == SECRET end }, "u"))
  end)

  it("reads the game's reaction colour, never a secret or a bad value", function()
    assert.are.same({ 0, 1, 0 }, { Core.ReactionColor({ UnitSelectionColor = function() return 0, 1, 0, 1 end }, "n") })
    assert.is_nil(Core.ReactionColor({}, "n"))
    assert.is_nil(Core.ReactionColor({ UnitSelectionColor = function() error("x") end }, "n"))
    assert.is_nil(Core.ReactionColor({ UnitSelectionColor = function() return 2, 0, 0 end }, "n"))
    assert.is_nil(Core.ReactionColor({ UnitSelectionColor = function() return SECRET, 0, 0 end,
      issecretvalue = function(v) return v == SECRET end }, "n"))
  end)

  it("tells an NPC's subtitle from the level line in its place", function()
    assert.are.equal("Maître des gryphons", Core.SubtitleLine("Maître des gryphons", 55))
    assert.are.equal("Trade Supplies", Core.SubtitleLine("Trade Supplies", 30))
    assert.is_nil(Core.SubtitleLine("Level 12 Humanoid", 12))
    assert.is_nil(Core.SubtitleLine("Niveau 30 Humanoïde (Élite)", 30))
    assert.is_nil(Core.SubtitleLine("Level ?? Elite", -1))
    -- Another number is not the level: "Level 30" when the NPC is level 3 still counts as a subtitle.
    assert.are.equal("Level 30", Core.SubtitleLine("Level 30", 3))
    assert.is_nil(Core.SubtitleLine("", 3))
    assert.is_nil(Core.SubtitleLine(nil, 3))
  end)

  it("cleans the saved roles", function()
    local roles = Core.CleanRoles({ [352] = "flight", [7] = "bogus", x = "vendor", [-1] = "vendor", [2.5] = "vendor" })
    assert.are.same({ [352] = "flight" }, roles)
    assert.are.same({}, Core.CleanRoles("junk"))
  end)

  it("reads the subtitle from the tooltip's second line, never a secret or an error", function()
    assert.are.equal("Gryphon Master", Core.TooltipSubtitle(npcAPI("Gryphon Master"), "nameplate5"))
    assert.is_nil(Core.TooltipSubtitle(npcAPI(nil), "nameplate5"))
    assert.is_nil(Core.TooltipSubtitle(npcAPI("x", "enUS", { GetTooltipUnit = false }), "nameplate5"))
    assert.is_nil(Core.TooltipSubtitle(npcAPI("x", "enUS", { GetTooltipUnit = function() error("boom") end }),
      "nameplate5"))
    assert.is_nil(Core.TooltipSubtitle(npcAPI("x", "enUS", { GetTooltipUnit = function() return {} end }),
      "nameplate5"))
    local secret = npcAPI(SECRET, "enUS", { issecretvalue = function(v) return v == SECRET end })
    assert.is_nil(Core.TooltipSubtitle(secret, "nameplate5"))
  end)

  it("takes the better of the learned role and the subtitle's, and says which", function()
    assert.are.same({ "flight", "subtitle" }, { Core.ServiceLookup(npcAPI("Gryphon Master"), "nameplate5", {}) })
    assert.are.same({ "repair", "learned" },
      { Core.ServiceLookup(npcAPI("General Goods"), "nameplate5", { [352] = "repair" }) })
    assert.are.same({ "innkeeper", "subtitle" },
      { Core.ServiceLookup(npcAPI("Innkeeper"), "nameplate5", { [352] = "vendor" }) })
    -- A German client has no subtitle words: only the learned roles count.
    assert.are.same({ "banker", "learned" },
      { Core.ServiceLookup(npcAPI("Bankier", "deDE"), "nameplate5", { [352] = "banker" }) })
    assert.are.same({ nil, "none" }, { Core.ServiceLookup(npcAPI("Bankier", "deDE"), "nameplate5", {}) })
    -- A secret GUID or subtitle: nothing learned or read.
    local secret = npcAPI(SECRET, "enUS", {
      issecretvalue = function(v) return v == SECRET end,
      UnitGUID = function() return SECRET end,
    })
    assert.are.same({ nil, "none" }, { Core.ServiceLookup(secret, "nameplate5", { [352] = "flight" }) })
    assert.are.same({ nil, "none" }, { Core.ServiceLookup(nil, "nameplate5", {}) })
  end)

  it("merges the roles shipped with the addon, learned ones first on a tie", function()
    local saved = Core.SHIPPED_ROLES
    Core.SHIPPED_ROLES = { [352] = "innkeeper" }
    assert.are.same({ "innkeeper", "shipped" }, { Core.ServiceLookup(npcAPI(nil), "nameplate5", {}) })
    assert.are.same({ "innkeeper", "shipped" },
      { Core.ServiceLookup(npcAPI(nil), "nameplate5", { [352] = "vendor" }) })
    assert.are.same({ "flight", "learned" }, { Core.ServiceLookup(npcAPI(nil), "nameplate5", { [352] = "flight" }) })
    assert.are.same({ "innkeeper", "learned" },
      { Core.ServiceLookup(npcAPI(nil), "nameplate5", { [352] = "innkeeper" }) })
    assert.are.same({ "flight", "subtitle" },
      { Core.ServiceLookup(npcAPI("Gryphon Master"), "nameplate5", {}) })
    Core.SHIPPED_ROLES = saved
    assert.are.same({}, Core.SHIPPED_ROLES)
  end)

  it("asks for the role of friendly NPCs only, with the setting on", function()
    local info = Core.UnitInfo(npcAPI("Gryphon Master"), "nameplate5", ON)
    assert.are.equal("flight", info.service)
    assert.are.equal("subtitle", info.serviceSource)
    assert.is_nil(Core.UnitInfo(npcAPI("Gryphon Master"), "nameplate5", { npcicons = false }).service)
    local players = npcAPI("Gryphon Master", "enUS", { UnitIsPlayer = function() return true end })
    assert.is_nil(Core.UnitInfo(players, "nameplate5", ON).service)
    local enemy = npcAPI("Gryphon Master", "enUS", { UnitCanAttack = function() return true end })
    assert.is_nil(Core.UnitInfo(enemy, "nameplate5", ON).service)
    local unknown = npcAPI("Gryphon Master", "enUS", { UnitIsFriend = false })
    assert.is_nil(Core.UnitInfo(unknown, "nameplate5", ON).service)
  end)

  it("gives a friendly NPC with a role the service mode, before any other", function()
    local info = Core.UnitInfo(npcAPI("Gryphon Master"), "nameplate5", ON)
    assert.are.same({ "npc" }, { Core.PlateMode(info, ON) })
    assert.is_true(Core.ServiceNPC(info, ON))
    assert.are.equal("default", Core.PlateMode(info, { enabled = false, npcicons = true }))
    assert.are.equal("default", Core.PlateMode(info, { enabled = true, npcicons = false }))
    assert.is_false(Core.ServiceNPC({ player = false, friend = true, attackable = false, service = "nope" }, ON))
    assert.is_false(Core.ServiceNPC({ player = false, friend = true, service = "flight" }, ON))
    -- A friendly NPC without a role stays Blizzard's.
    local plain = Core.UnitInfo(npcAPI("Level 12"), "nameplate5", ON)
    assert.are.equal("default", Core.PlateMode(plain, ON))
  end)

  it("defaults the service settings and keeps the saved ones", function()
    local db = Core.InitDB({})
    assert.is_true(db.npcicons)
    assert.is_true(db.npccompact)
    assert.are.equal(5, db.npciconsize)
    assert.are.equal(1, db.npcsize)
    assert.are.same({}, db.npcroles)
    db = Core.InitDB({ npcicons = false, npccompact = false, npciconsize = 12, npcsize = 2,
      npcroles = { [9] = "flight" } })
    assert.is_false(db.npcicons)
    assert.is_false(db.npccompact)
    assert.are.equal(12, db.npciconsize)
    assert.are.equal(2, db.npcsize)
    assert.are.same({ [9] = "flight" }, db.npcroles)
    assert.are.equal(5, Core.InitDB({ npciconsize = 16 }).npciconsize)
    assert.are.equal(1, Core.InitDB({ npcsize = 4 }).npcsize)
  end)
end)

describe("Core.BarOffsets", function()
  it("widens the bar about its centre and keeps its bottom", function()
    -- 200 wide, factor 2: 200 more, 100 per side; offsets in the doubled bar's units.
    assert.are.same({ -50, 50, 1 }, { Core.BarOffsets(200, 2, 1, 2) })
    -- Blizzard's own scale 0.5: the bar's units are 0.5 x 2 = 1.
    assert.are.same({ -100, 100, 1 }, { Core.BarOffsets(200, 2, 0.5, 2) })
  end)

  it("gives Blizzard's layout back at factor 1", function()
    assert.are.same({ 0, 0, 2 }, { Core.BarOffsets(200, 2, 1, 1) })
  end)

  it("refuses invalid input", function()
    assert.is_nil(Core.BarOffsets(nil, 2, 1, 2))
    assert.is_nil(Core.BarOffsets(0, 2, 1, 2))
    assert.is_nil(Core.BarOffsets(200, nil, 1, 2))
    assert.is_nil(Core.BarOffsets(200, 2, 0, 2))
    assert.is_nil(Core.BarOffsets(200, 2, 1, 0 / 0))
  end)
end)

describe("Core.BuffLift", function()
  it("is half of what an icon gains", function()
    assert.are.equal(12.5, Core.BuffLift(25, 1, 1, 2))
    assert.are.equal(5, Core.BuffLift(25, 0.8, 1, 1.5))
  end)

  it("is 0 at factor 1 or below and for invalid input", function()
    assert.are.equal(0, Core.BuffLift(25, 1, 1, 1))
    assert.are.equal(0, Core.BuffLift(25, 1, 1, 0.5))
    assert.are.equal(0, Core.BuffLift(nil, 1, 1, 2))
    assert.are.equal(0, Core.BuffLift(25, "x", 1, 2))
  end)
end)
