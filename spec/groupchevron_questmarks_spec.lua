-- Unit tests for GroupChevron/QuestMarks.lua, loaded on its own: its dependencies are injected
-- with QuestMarks.Setup, so no addon state or WoW API is needed (run from the repo root).

local YELLOW, WHITE = { 1, 1, 0 }, { 1, 1, 1 }

-- load returns a fresh QuestMarks with the given colours injected.
local function load(hostile, party)
  local ns = {}
  local chunk = assert(loadfile("GroupChevron/QuestMarks.lua"))
  local QuestMarks = chunk("GroupChevron", ns)
  assert.are.equal(QuestMarks, ns.QuestMarks)
  QuestMarks.Setup({
    HostileColor = function() return unpack(hostile or YELLOW) end,
    PartyColor = function() return unpack(party or WHITE) end,
    Factor = function() return 1 end,
    Method = function() end,
    NoticeOnce = function() end,
    OUTLINE_DIRS = {},
    OUTLINE_UNIT = 0.1875,
    GAP = 2,
  })
  return QuestMarks
end

describe("QuestMarks.Colors", function()
  it("gives the player's own kinds the hostile colour, in a fixed order", function()
    local QuestMarks = load()
    local out = QuestMarks.Colors(false, { questKill = true, questLoot = true })
    assert.are.same(YELLOW, out.kill)
    assert.are.same(YELLOW, out.loot)
    assert.is_nil(out.generic)
  end)

  it("gives a kind only a party member still has the party colour", function()
    local QuestMarks = load()
    local out = QuestMarks.Colors(false, { questKill = true, partyLoot = true })
    assert.are.same(YELLOW, out.kill)
    assert.are.same(WHITE, out.loot)
    out = QuestMarks.Colors(true, { partyKill = true, partyLoot = true })
    assert.are.same(WHITE, out.kill)
    assert.are.same(WHITE, out.loot)
  end)

  it("falls back to the generic icon when no kind is known: yellow for the player, white for a party quest", function()
    local QuestMarks = load()
    assert.are.same({ generic = YELLOW }, QuestMarks.Colors(false, {}))
    -- A party member's kind alone does not make a kill icon for the player's own quest.
    assert.are.same({ generic = YELLOW }, QuestMarks.Colors(false, { partyKill = true }))
    assert.are.same({ generic = WHITE }, QuestMarks.Colors(true, {}))
  end)

  it("follows the injected colours", function()
    local QuestMarks = load({ 0, 1, 0 }, { 0, 0, 1 })
    assert.are.same({ generic = { 0, 1, 0 } }, QuestMarks.Colors(false, {}))
    assert.are.same({ generic = { 0, 0, 1 } }, QuestMarks.Colors(true, {}))
  end)

  it("answers nil without information (the single chevron)", function()
    assert.is_nil(load().Colors(false, nil))
  end)
end)
