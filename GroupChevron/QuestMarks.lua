-- GroupChevron: the quest hostiles' icons (QuestMarks).
--
-- A sword ("kill it"), a sack ("loot a quest item from it") or, when neither is known, an open book
-- ("tied to a quest"), each above a small chevron, in place of the single chevron. Loaded after
-- Core.lua and before GroupChevron.lua, which hands it what it needs from the main chunk with
-- QuestMarks.Setup (the settings, the outline constants, the helpers): this file reads no addon
-- state of its own and no settings.

local _, ns = ...

-- deps holds what Setup received: Factor(key), Method(obj, name, ...), NoticeOnce(key, msg),
-- HostileColor() and PartyColor() (each: r, g, b), OUTLINE_DIRS, OUTLINE_UNIT and GAP.
local deps = {}

-- Quest hostiles' icons: a sword ("kill it") and / or a sack ("loot a quest item from it"), each
-- above a small chevron, in place of the single chevron. Each icon is a white texture
-- (tools/quest_icons_tga.py, 32 x 64) tinted
-- with the hostile colour, ICON_W x ICON_H UI units at hostilechevsize 1, with the chevron's
-- black outline (OUTLINE_DIRS copies moved by OUTLINE_UNIT x hostileoutlinesize x the size) and,
-- for the sack, its tie in black on top. Both: side by side, kill first, SPACING apart. A frame
-- per plate (frames), a child of its UnitFrame like the chevron.
local QuestMarks = {
  frames = setmetatable({}, { __mode = "k" }),
  KINDS = { "kill", "loot", "generic" },
  TEXTURES = {
    kill = "Interface\\AddOns\\GroupChevron\\quest_kill.tga",
    loot = "Interface\\AddOns\\GroupChevron\\quest_loot.tga",
    generic = "Interface\\AddOns\\GroupChevron\\quest_generic.tga",
  },
  DETAILS = {
    loot = "Interface\\AddOns\\GroupChevron\\quest_loot_detail.tga",
    generic = "Interface\\AddOns\\GroupChevron\\quest_generic_detail.tga",
  },
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
    deps.Method(tex, "Hide")
    return nil
  end
  deps.Method(tex, "SetSnapToPixelGrid", false)
  deps.Method(tex, "SetTexelSnappingBias", 0)
  return tex
end

-- QuestMarks.AddIcon builds one icon of frame: { tex, outlines, detail } (nil: texture missing).
function QuestMarks.AddIcon(frame, kind)
  local tex = QuestMarks.Texture(frame, QuestMarks.TEXTURES[kind], "OVERLAY", 0)
  if not tex then
    return nil
  end
  local icon = { tex = tex, outlines = {} }
  for _, dir in ipairs(deps.OUTLINE_DIRS) do
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
  if not (frame.icons.kill and frame.icons.loot and frame.icons.generic) then
    deps.NoticeOnce("noquesticon", "quest icon textures not found (restart the game after an update): "
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
  local offset = deps.OUTLINE_UNIT * thickness * f
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
-- or nil, loot = ..., generic = ... }), or nil for the single chevron (no info). The player's own
-- objectives come first, in the hostile colour; a kind only a party member still has to do gets the
-- party quest colour (a kill objective of the player's and a loot one of a party member's: a yellow
-- sword and a white sack). party: the unit is tied to a party member's quest only (mode
-- partyquest): its kinds, in the party quest colour. When no kind is known (an object or event
-- objective, an unreadable tooltip), the generic quest icon, an open book, in the hostile colour
-- (yellow) or, for a party quest, the party quest colour (white).
function QuestMarks.Colors(party, info)
  if type(info) ~= "table" then
    return nil
  end
  local mine = { deps.HostileColor() }
  local theirs = { deps.PartyColor() }
  local out = {}
  if party then
    out.kill = info.partyKill == true and theirs or nil
    out.loot = info.partyLoot == true and theirs or nil
  elseif info.questKill == true or info.questLoot == true then
    out.kill = (info.questKill == true and mine) or (info.partyKill == true and theirs) or nil
    out.loot = (info.questLoot == true and mine) or (info.partyLoot == true and theirs) or nil
  end
  if not out.kill and not out.loot then
    -- Tied to a quest, but nothing told whether to kill or loot (an object or event objective, an
    -- unreadable tooltip as in dungeons): the generic quest icon, the player's colour first.
    out.generic = party and theirs or mine
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
  local f = deps.Factor(style.chevsize)
  local width = QuestMarks.Place(frame.icons, style.quest, f, style.outlinesize or 0, frame, "BOTTOMLEFT", 0, 0)
  if width <= 0 then
    frame:Hide()
    return nil
  end
  frame:SetSize(width, QuestMarks.ICON_H * f)
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", anchor or uf, "TOP", 0, deps.GAP)
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

-- QuestMarks.Setup gives the module what it needs from GroupChevron.lua (see deps above).
function QuestMarks.Setup(d)
  for k, v in pairs(d) do
    deps[k] = v
  end
end

if ns then
  ns.QuestMarks = QuestMarks
end

return QuestMarks
