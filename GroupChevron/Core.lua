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
Core.MAX_FACTORS = { chevsize = 5, hostilechevsize = 5, friendchevsize = 5, guildchevsize = 5,
  memberoutlinesize = 5, friendoutlinesize = 5, guildoutlinesize = 5, hostileoutlinesize = 5, npciconsize = 15 }
Core.DEFAULT_FACTOR = 1
-- DEFAULT_FACTORS are the defaults of the kinds that do not start at DEFAULT_FACTOR (1, which
-- also stays the "no scaling" value the plates compare against). The hostiles start where the
-- friendlies do: the chevron at the size the friends' chevron has (chevsize), the text at 1.
Core.DEFAULT_FACTORS = { chevsize = 3, textsize = 1.75, buffsize = 1.1, hostilechevsize = 3, friendchevsize = 3,
  guildchevsize = 3, memberoutlinesize = 2,
  friendoutlinesize = 2, guildoutlinesize = 2, hostileoutlinesize = 2, npciconsize = 5 }

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
    services = "Friendly NPCs",
    show_icons = "Show role icons",
    icon_size = "Icon size",
    npc_plates = "Friendly NPC nameplates",
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
    services = "PNJ amicaux",
    show_icons = "Afficher les icônes de rôle",
    icon_size = "Taille des icônes",
    npc_plates = "Plaques des PNJ amicaux",
  },
  deDE = {
    enabled = "Aktiviert",
    group_members = "Gruppenmitglieder",
    friendlies = "Freundliche Spieler (außerhalb der Gruppe)",
    friends = "Freunde (auf der Freundesliste, außerhalb der Gruppe)",
    guildmates = "Gildenmitglieder (außerhalb der Gruppe)",
    hostiles = "Quest-Gegner (mit aktiven Quests verknüpft)",
    outline_size = "Kontur",
    compact = "Kompakte Plaketten (nur Name)",
    name_colour = "Namensfarbe",
    name_font = "Schrift",
    chevron_size = "Chevrongröße",
    text_size = "Textgröße",
    bar_size = "Lebensbalken",
    buffs_size = "Buffgröße",
    name_gap = "Namenshöhe",
    reset = "Zurücksetzen",
    show_chevron = "Chevron anzeigen",
    bnet_friends = "Battle.net-Freunde einbeziehen",
    class_colour = "Klassenfarbe",
    show_level = "Stufe anzeigen",
    services = "Freundliche NSCs",
    show_icons = "Rollensymbole anzeigen",
    icon_size = "Symbolgröße",
    npc_plates = "Plaketten freundlicher NSCs",
  },
  esES = {
    enabled = "Activado",
    group_members = "Miembros del grupo",
    friendlies = "Jugadores amistosos (fuera de tu grupo)",
    friends = "Amigos (en tu lista de amigos, fuera de tu grupo)",
    guildmates = "Miembros de la hermandad (fuera de tu grupo)",
    hostiles = "Enemigos de misión (ligados a tus misiones)",
    outline_size = "Contorno",
    compact = "Placas compactas (solo nombre)",
    name_colour = "Color del nombre",
    name_font = "Fuente",
    chevron_size = "Tamaño del chevrón",
    text_size = "Tamaño del texto",
    bar_size = "Barra de salud",
    buffs_size = "Tamaño de efectos",
    name_gap = "Altura del nombre",
    reset = "Restablecer",
    show_chevron = "Mostrar chevrón",
    bnet_friends = "Incluir amigos de Battle.net",
    class_colour = "Color de clase",
    show_level = "Mostrar nivel",
    services = "PNJ amistosos",
    show_icons = "Mostrar iconos de función",
    icon_size = "Tamaño del icono",
    npc_plates = "Placas de PNJ amistosos",
  },
  itIT = {
    enabled = "Attivo",
    group_members = "Membri del gruppo",
    friendlies = "Giocatori amichevoli (fuori dal tuo gruppo)",
    friends = "Amici (nella tua lista amici, fuori dal gruppo)",
    guildmates = "Membri della gilda (fuori dal gruppo)",
    hostiles = "Nemici delle missioni (legati alle tue missioni)",
    outline_size = "Contorno",
    compact = "Targhette compatte (solo nome)",
    name_colour = "Colore nome",
    name_font = "Carattere",
    chevron_size = "Dimensione chevron",
    text_size = "Dimensione testo",
    bar_size = "Barra della salute",
    buffs_size = "Dimensione effetti",
    name_gap = "Altezza nome",
    reset = "Ripristina",
    show_chevron = "Mostra chevron",
    bnet_friends = "Includi amici Battle.net",
    class_colour = "Colore classe",
    show_level = "Mostra livello",
    services = "PNG amichevoli",
    show_icons = "Mostra icone del ruolo",
    icon_size = "Dimensione icona",
    npc_plates = "Targhette dei PNG amichevoli",
  },
  ptBR = {
    enabled = "Ativado",
    group_members = "Membros do grupo",
    friendlies = "Jogadores amistosos (fora do seu grupo)",
    friends = "Amigos (na sua lista de amigos, fora do grupo)",
    guildmates = "Membros da guilda (fora do grupo)",
    hostiles = "Inimigos de missão (ligados às suas missões)",
    outline_size = "Contorno",
    compact = "Placas compactas (só o nome)",
    name_colour = "Cor do nome",
    name_font = "Fonte",
    chevron_size = "Tamanho do chevron",
    text_size = "Tamanho do texto",
    bar_size = "Barra de vida",
    buffs_size = "Tamanho dos efeitos",
    name_gap = "Altura do nome",
    reset = "Redefinir",
    show_chevron = "Mostrar chevron",
    bnet_friends = "Incluir amigos do Battle.net",
    class_colour = "Cor da classe",
    show_level = "Mostrar nível",
    services = "PNJs amistosos",
    show_icons = "Mostrar ícones de função",
    icon_size = "Tamanho do ícone",
    npc_plates = "Placas de PNJs amistosos",
  },
  ruRU = {
    enabled = "Включено",
    group_members = "Участники группы",
    friendlies = "Дружественные игроки (вне группы)",
    friends = "Друзья (в списке друзей, вне группы)",
    guildmates = "Согильдийцы (вне группы)",
    hostiles = "Цели заданий (враги, связанные с вашими заданиями)",
    outline_size = "Контур",
    compact = "Компактный вид (только имя)",
    name_colour = "Цвет имени",
    name_font = "Шрифт",
    chevron_size = "Размер шеврона",
    text_size = "Размер текста",
    bar_size = "Полоса здоровья",
    buffs_size = "Размер эффектов",
    name_gap = "Высота имени",
    reset = "Сбросить",
    show_chevron = "Показать шеврон",
    bnet_friends = "Учитывать друзей Battle.net",
    class_colour = "Цвет класса",
    show_level = "Показать уровень",
    services = "Дружественные НИП",
    show_icons = "Показать значки ролей",
    icon_size = "Размер значка",
    npc_plates = "Индикаторы дружественных НИП",
  },
  koKR = {
    enabled = "사용",
    group_members = "파티원",
    friendlies = "우호적 플레이어 (파티 외)",
    friends = "친구 (친구 목록, 파티 외)",
    guildmates = "길드원 (파티 외)",
    hostiles = "퀘스트 적 (진행 중인 퀘스트 관련)",
    outline_size = "외곽선",
    compact = "간략한 이름표 (이름만)",
    name_colour = "이름 색상",
    name_font = "글꼴",
    chevron_size = "표식 크기",
    text_size = "글자 크기",
    bar_size = "생명력 바 크기",
    buffs_size = "강화 효과 크기",
    name_gap = "이름 높이",
    reset = "초기화",
    show_chevron = "표식 표시",
    bnet_friends = "Battle.net 친구 포함",
    class_colour = "직업 색상",
    show_level = "레벨 표시",
    services = "우호적 NPC",
    show_icons = "역할 아이콘 표시",
    icon_size = "아이콘 크기",
    npc_plates = "우호적 NPC 이름표",
  },
  zhCN = {
    enabled = "启用",
    group_members = "队伍成员",
    friendlies = "友方玩家（队伍外）",
    friends = "好友（好友名单中，队伍外）",
    guildmates = "公会成员（队伍外）",
    hostiles = "任务敌人（与你的任务相关）",
    outline_size = "描边",
    compact = "精简姓名板（仅名字）",
    name_colour = "名字颜色",
    name_font = "字体",
    chevron_size = "V形标记大小",
    text_size = "文字大小",
    bar_size = "血条大小",
    buffs_size = "增益效果大小",
    name_gap = "名字高度",
    reset = "恢复默认",
    show_chevron = "显示V形标记",
    bnet_friends = "包括战网好友",
    class_colour = "职业颜色",
    show_level = "显示等级",
    services = "友方NPC",
    show_icons = "显示职能图标",
    icon_size = "图标大小",
    npc_plates = "友方NPC姓名板",
  },
  zhTW = {
    enabled = "啟用",
    group_members = "隊伍成員",
    friendlies = "友方玩家（隊伍外）",
    friends = "好友（好友名單中，隊伍外）",
    guildmates = "公會成員（隊伍外）",
    hostiles = "任務敵人（與你的任務相關）",
    outline_size = "描邊",
    compact = "精簡名條（僅名字）",
    name_colour = "名字顏色",
    name_font = "字型",
    chevron_size = "V形標記大小",
    text_size = "文字大小",
    bar_size = "血條大小",
    buffs_size = "增益效果大小",
    name_gap = "名字高度",
    reset = "恢復預設",
    show_chevron = "顯示V形標記",
    bnet_friends = "包含Battle.net好友",
    class_colour = "職業顏色",
    show_level = "顯示等級",
    services = "友方NPC",
    show_icons = "顯示職能圖示",
    icon_size = "圖示大小",
    npc_plates = "友方NPC名條",
  },
}
-- Locales of the client that share another one's texts: enGB is English, esMX (Latin American
-- Spanish) uses the Spanish texts. ptPT clients report ptBR and enTW (old Taiwan English) is
-- gone, so neither needs an entry.
Core.Locales.enGB = Core.Locales.enUS
Core.Locales.esMX = Core.Locales.esES

-- CLIENT_LOCALES lists every locale GetLocale() can return on the game client; each one has
-- texts in Locales.
Core.CLIENT_LOCALES = {
  "enUS", "enGB", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW",
}

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
    "hostilechevsize", "hostilesize", "friendchevsize", "guildchevsize", "memberoutlinesize",
    "friendoutlinesize", "guildoutlinesize", "hostileoutlinesize", "npciconsize", "npcsize" }) do
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
  for _, key in ipairs({ "friendchevron", "bnetfriends", "guildchevron", "showlevel", "npcicons", "npccompact" }) do
    if type(db[key]) ~= "boolean" then
      db[key] = true
    end
  end
  if type(db.classcolor) ~= "boolean" then
    db.classcolor = Core.DEFAULT_CLASSCOLOR
  end
  db.npcroles = Core.CleanRoles(db.npcroles)
  db.roleicons = Core.CleanRoleIcons(db.roleicons)
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

-- ---------------------------------------------------------------------------------------
-- Service NPCs: friendly NPCs with a role (flight master, innkeeper, vendor, repairer...) get
-- a role icon above their name.
--
-- ROLES lists the roles in priority order (an NPC with two roles shows the first one: an
-- innkeeper who also sells food shows the innkeeper icon, a vendor who repairs the repair one),
-- with the client texture of each icon: 64 x 64 spell and item icons (Interface\Icons), whose
-- bevelled border the glue crops (ICON_CROP). Up to 0.23.0's first build these were the minimap
-- tracking icons, too small once enlarged. The names are the retail client's (the Forever client
-- is built on it) and are unverified on the Forever client: a texture that does not load shows no
-- icon.
Core.ROLES = {
  { key = "flight", icon = "Interface\\Icons\\Ability_Mount_Gryphon_01" },
  { key = "innkeeper", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
  { key = "banker", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
  { key = "auctioneer", icon = "Interface\\Icons\\INV_Scroll_03" },
  { key = "stable", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
  { key = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09" },
  { key = "repair", icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { key = "vendor", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
}

-- ICON_CROP is the part of an Interface\Icons texture kept (SetTexCoord left, right, top,
-- bottom): its bevelled border is cut off. Any other texture is shown whole (FULL_CROP).
Core.ICON_CROP = { 0.07, 0.93, 0.07, 0.93 }
Core.FULL_CROP = { 0, 1, 0, 1 }

-- An icon is either a texture path (it has a "\" or a "/", e.g. Interface\Icons\INV_Misc_Coin_01)
-- or the name of one of the client's atlases (e.g. FlightMaster). The player can choose the
-- icon of each role (/gchev icon <role> <name>, saved in db.roleicons).

-- IsTexturePath is true when name is a texture path rather than an atlas name.
function Core.IsTexturePath(name)
  return type(name) == "string" and name:find("[\\/]") ~= nil
end

-- ValidIconName is true for a texture path or atlas name: 1 to 200 letters, digits, "_", "-",
-- ".", "\" or "/".
function Core.ValidIconName(name)
  return type(name) == "string" and #name >= 1 and #name <= 200 and name:match("^[%w_%-%.\\/]+$") ~= nil
end

-- IconCrop returns the SetTexCoord values of an icon: ICON_CROP for an Interface\Icons texture,
-- else FULL_CROP.
function Core.IconCrop(name)
  if Core.IsTexturePath(name) and name:lower():gsub("/", "\\"):find("^interface\\icons\\") then
    return Core.ICON_CROP
  end
  return Core.FULL_CROP
end

local rolePriority = {}
for i, r in ipairs(Core.ROLES) do
  rolePriority[r.key] = i
end

-- ValidRole is true for the key of one of ROLES.
function Core.ValidRole(role)
  return type(role) == "string" and rolePriority[role] ~= nil
end

-- RoleIcon returns the texture of role's icon, or nil for an unknown role.
function Core.RoleIcon(role)
  local i = type(role) == "string" and rolePriority[role]
  return i and Core.ROLES[i].icon or nil
end

-- BetterRole returns whichever of a and b comes first in ROLES (an invalid one never wins; nil
-- when neither is valid).
function Core.BetterRole(a, b)
  if not Core.ValidRole(a) then
    return Core.ValidRole(b) and b or nil
  end
  if not Core.ValidRole(b) then
    return a
  end
  return rolePriority[a] <= rolePriority[b] and a or b
end

-- SUBTITLES are, by client locale, the words of an NPC's subtitle (the "<Gryphon Master>" line,
-- lower case, plain substrings) that give its role, in ROLES order. Only enUS (enGB shares it) and
-- frFR have words: on other clients only the roles learned from windows you open count. Of the
-- French words, only "Maître des gryphons" is checked in game.
Core.SUBTITLES = {
  enUS = {
    { "flight", { "gryphon master", "wind rider master", "hippogryph master", "bat handler", "flight master" } },
    { "innkeeper", { "innkeeper" } },
    { "banker", { "banker" } },
    { "auctioneer", { "auctioneer" } },
    { "stable", { "stable master" } },
    { "trainer", { "trainer" } },
    { "repair", { "armorer", "weaponsmith", "repair" } },
    { "vendor", { "vendor", "merchant", "supplies", "goods", "food & drink", "reagents", "provisioner",
      "bowyer", "gunsmith" } },
  },
  frFR = {
    -- The Forever client spells it "Maître des gryphons" (seen in game); the other spellings stay
    -- in case some NPCs use them.
    { "flight", { "gryphon", "griffon", "coursier du vent", "coursiers du vent", "hippogryphe", "hippogriffe",
      "chauves-souris", "maître de vol", "maîtresse de vol" } },
    { "innkeeper", { "aubergiste" } },
    { "banker", { "banquier", "banquière" } },
    { "auctioneer", { "commissaire-priseu" } },
    { "stable", { "écuries" } },
    { "trainer", { "entraîneu", "instructeur", "instructrice" } },
    { "repair", { "armurier", "armurière", "réparation" } },
    { "vendor", { "marchand", "vendeu", "fournitures", "provisions", "nourriture", "réactifs" } },
  },
}
Core.SUBTITLES.enGB = Core.SUBTITLES.enUS

-- SubtitleRole returns the role an NPC's subtitle gives in locale (see SUBTITLES), or nil (no
-- subtitle, no words for the locale, or no word found).
function Core.SubtitleRole(subtitle, locale)
  local words = type(locale) == "string" and Core.SUBTITLES[locale] or nil
  if type(subtitle) ~= "string" or subtitle == "" or not words then
    return nil
  end
  local text = subtitle:lower()
  for _, entry in ipairs(words) do
    for _, word in ipairs(entry[2]) do
      if text:find(word, 1, true) then
        return entry[1]
      end
    end
  end
  return nil
end

-- NpcID returns the creature ID of an NPC's GUID ("Creature-0-<server>-<instance>-<zone>-<id>-<spawn>",
-- also "Vehicle-"), or nil for any other GUID (players, pets, objects) or anything unreadable.
function Core.NpcID(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
  if kind ~= "Creature" and kind ~= "Vehicle" then
    return nil
  end
  id = tonumber(id)
  if not id or id <= 0 then
    return nil
  end
  return id
end

-- CleanRoleIcons returns the player's icon choices (role key -> icon name) with every invalid
-- entry dropped: a new table when icons is not a table.
function Core.CleanRoleIcons(icons)
  if type(icons) ~= "table" then
    return {}
  end
  local bad = {}
  for role, name in pairs(icons) do
    if not Core.ValidRole(role) or not Core.ValidIconName(name) then
      bad[#bad + 1] = role
    end
  end
  for _, role in ipairs(bad) do
    icons[role] = nil
  end
  return icons
end

-- CleanRoles returns the learned roles table (creature ID -> role key) with every invalid entry
-- dropped: a new table when roles is not a table.
function Core.CleanRoles(roles)
  if type(roles) ~= "table" then
    return {}
  end
  local bad = {}
  for id, role in pairs(roles) do
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or not Core.ValidRole(role) then
      bad[#bad + 1] = id
    end
  end
  for _, id in ipairs(bad) do
    roles[id] = nil
  end
  return roles
end

-- INTERACTIONS maps the windows an NPC opens (the interaction kinds the glue listens for) to the
-- role they show; "merchant" is "repair" when the merchant can repair (InteractionRole).
Core.INTERACTIONS = {
  merchant = "vendor", taxi = "flight", banker = "banker", auctioneer = "auctioneer", trainer = "trainer",
  stable = "stable", binder = "innkeeper",
}

-- InteractionRole returns the role an interaction of kind (see INTERACTIONS) shows, or nil.
function Core.InteractionRole(kind, canRepair)
  local role = type(kind) == "string" and Core.INTERACTIONS[kind] or nil
  if role == "vendor" and canRepair == true then
    return "repair"
  end
  return role
end

-- LearnRole records in roles (creature ID -> role key) that the NPC id has role, keeping the
-- better of the old and the new role (BetterRole). It returns true when the table changed.
function Core.LearnRole(roles, id, role)
  if type(roles) ~= "table" or type(id) ~= "number" or id <= 0 or id ~= math.floor(id)
    or not Core.ValidRole(role) then
    return false
  end
  local best = Core.BetterRole(roles[id], role)
  if best == roles[id] then
    return false
  end
  roles[id] = best
  return true
end

-- TooltipSubtitle returns the second line of unit's tooltip (api.GetTooltipUnit(unit), i.e.
-- C_TooltipInfo.GetUnit: { lines = { { leftText = name }, { leftText = subtitle or level } } }),
-- or nil when it cannot be read (missing function, error, secret value, not a string).
function Core.TooltipSubtitle(api, unit)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return nil
  end
  local data = call(api, "GetTooltipUnit", unit)
  if type(data) ~= "table" then
    return nil
  end
  local ok, text = pcall(function() return data.lines[2].leftText end)
  if not ok or isSecret(api, text) or type(text) ~= "string" or text == "" then
    return nil
  end
  return text
end

-- ServiceLookup tells which role the NPC unit has: the better (BetterRole) of the role learned
-- for its creature ID (learned: creature ID -> role, see LearnRole) and the role its subtitle
-- gives in the client's locale (api.GetLocale). It returns the role (nil for none) and its source:
--   "learned"  : the learned role won;
--   "subtitle" : the subtitle's role won;
--   "none"     : no role (also when an API raises an error or returns a secret value).
-- guid is the unit's GUID when the caller already read it (else it is asked here).
function Core.ServiceLookup(api, unit, learned, guid)
  if type(api) ~= "table" or type(unit) ~= "string" or unit == "" or isSecret(api, unit) then
    return nil, "none"
  end
  if guid == nil then
    guid = call(api, "UnitGUID", unit)
  end
  local id = not isSecret(api, guid) and Core.NpcID(guid) or nil
  local fromLearned = id and type(learned) == "table" and learned[id] or nil
  if not Core.ValidRole(fromLearned) then
    fromLearned = nil
  end
  local fromSubtitle = Core.SubtitleRole(Core.TooltipSubtitle(api, unit), call(api, "GetLocale"))
  local role = Core.BetterRole(fromLearned, fromSubtitle)
  if role == nil then
    return nil, "none"
  end
  return role, role == fromLearned and "learned" or "subtitle"
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
  if type(settings) == "table" and settings.npcicons == true and info.player == false and info.friend == true
    and info.attackable == false then
    info.service, info.serviceSource = Core.ServiceLookup(api, unit, settings.npcroles, guid)
  end
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

-- FriendlyNPC is true when info (see UnitInfo) is known to be a friendly NPC: not a player,
-- friendly, not attackable (exact booleans only).
function Core.FriendlyNPC(info)
  return type(info) == "table" and info.player == false and info.friend == true and info.attackable == false
end

-- ServiceNPC is true when the plate of the unit described by info (see UnitInfo) is a friendly
-- NPC (not a player, friendly, not attackable) with a known role (info.service, see
-- ServiceLookup), the addon is on and settings.npcicons is on. Only exact boolean answers count.
function Core.ServiceNPC(info, settings)
  if type(info) ~= "table" or type(settings) ~= "table" or settings.enabled ~= true or settings.npcicons ~= true then
    return false
  end
  return Core.FriendlyNPC(info) and Core.ValidRole(info.service)
end

-- NpcPlate is true when the addon has something to do on the plate of the friendly NPC described
-- by info (see FriendlyNPC): a role icon (ServiceNPC), compact plates (settings.npccompact) or a
-- name size other than 1 (settings.npcsize). Otherwise the plate stays Blizzard's.
function Core.NpcPlate(info, settings)
  if type(settings) ~= "table" or settings.enabled ~= true or not Core.FriendlyNPC(info) then
    return false
  end
  local size = settings.npcsize
  return Core.ServiceNPC(info, settings) or settings.npccompact == true
    or (Core.ValidFactor(size, "npcsize") and size ~= Core.DEFAULT_FACTOR)
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
--   "npc"     : a friendly NPC the addon has something to do on (NpcPlate): the name in
--               Blizzard's colour at npcsize, the role icon above it when it has a role
--               (ServiceNPC), name only when settings.npccompact is on (the glue decides); no
--               relation (nil). Such a unit is never a player.
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
  if Core.NpcPlate(info, settings) then
    return "npc", nil
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
