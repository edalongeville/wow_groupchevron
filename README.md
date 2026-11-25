# GroupChevron

A World of Warcraft addon (Interface 16001, WoW: Forever client) that makes the members of your party or raid easy to spot in a crowd. Standalone: no dependency on any other addon, nothing uploaded. Besides its settings, the only thing it saves is the role of the NPCs whose windows you open (see Service NPCs below).

## Features

GroupChevron helps you quickly identify your group members, friends and guildmates in a crowd.
The addon achieves this by acting on the nameplates.
The addon is still being tested.

- Adds a pink chevron above group members
- Adds a blue chevron above friends (and Battle.net friends)
- Adds a green chevron above guildmates
- Adds a yellow single chevron and a yellow name above hostile units tied to one of your quests (kill, item drop, ...), with its own colour, chevron size, text size and name height in the **Quest hostiles** section of the options
- Shows what is left to do to a quest mob instead of its chevron: a sword (kill it), a sack (loot a quest item from it), or both side by side (always the sword at the left), each above a small chevron. Your own objectives are in the quest hostiles' colour (yellow); a kind only a party member still needs is in the party quest colour (white): your kill quest and a party member's loot quest give a yellow sword and a white sack. A mob tied only to a party member's quest gets white icons. Each section's size slider is now **Icon size**, and its preview shows both icons. Read from the mob's tooltip and your quest log, in any client language (a party member's quest you don't have: a kill when its objective names the mob, else a loot); when it cannot be told (an object or event objective, combat, dungeons where the client hides the tooltip's texts), an open book above a small chevron shows instead: yellow for your own quests, white for a party member's
- Adds a white single chevron and a white name above hostile units tied to an objective a party member still has to do (the lines the mouseover tooltip shows, no addon needed on their side), with its own settings in the **Party quest hostiles** section of the **Quest mobs** options page; your own quest hostiles keep the yellow look
- Every chevron has a black outline (one **Outline** slider per section: group members, friends, guildmates, quest hostiles, party quest hostiles; default 2, from 0 = no outline to 5) and the options page shows a live preview of the chevron (chosen colour, size and outline), beside each colour swatch.
- Changes the nameplate font
- Colors names by class
- Displays friendlies' (non-grouped players') health bars only when below 100%
- Shows every friendly player's guild on a second line below the name ("<Guild name>"), in the name's colour
- Friendly NPCs (**Friendly NPCs** section of the options): a role icon above flight masters, innkeepers, bankers, auctioneers, stable masters, class and profession trainers, repairers and vendors (`/gchev npcicons on|off`, `/gchev npciconsize 1-15`, default 5; opacity `/gchev npciconalpha 0.1-1`, default 0.8), "<name> (<level>)" in the game's reaction colour (green friendly, yellow neutral) with the NPC's subtitle on a line below it ("<Maître des gryphons>"), every friendly NPC's plate down to that, with the health bar only while hurt, the target included, and the name moved down into the hidden health bar's place (back above the bar while it shows) (`/gchev npccompact on|off`, on by default), their name's text size (`/gchev npcsize 1-3`) and height (`/gchev npcnamegap -40-40`, default -20). All of it needs the game's friendly NPC nameplates: `/gchev npcplates on` (or the first checkbox of that section) turns them on; the addon never changes that setting by itself. The role comes from the windows an NPC opens for you (learned once, then shown on every visit) and, on English and French clients, from its subtitle ("<Gryphon Master>", "<Maître des gryphons>"). `/gchev icon` lists the icon of each role, and `/gchev icon <role> <texture or atlas>` changes one (an atlas name is checked against the client; `default` gives the role its own icon back)
- Opens its options from the game's add-on menu under the minimap's calendar (or with `/gchev options`)

## Layout

| Path | Content |
|---|---|
| `GroupChevron/` | the addon: `Core.lua` (pure, unit-tested logic), `QuestMarks.lua` (the quest hostiles' icons, its dependencies injected), `GroupChevron.lua` (WoW glue), `.toc`, `chevron.tga`, `icon.tga`, `quest_*.tga` |
| `assets/` | CurseForge project icon (`curseforge-icon.png`, 400×400) |
| `docs/` | implementation notes |
| `spec/` | [busted](https://lunarmodules.github.io/busted/) tests (`Core.lua` and a smoke test of the glue against a stubbed WoW API) |
| `tools/` | generators for `chevron.tga` and `icon.tga` (Python 3, no dependencies) |
| `.luacheckrc` | luacheck configuration (Lua 5.1, WoW globals) |

## Development

Lua 5.1, as in the WoW client. Keep logic that does not need the WoW API in `Core.lua`, with tests in `spec/`.

```bash
tools/check.sh
```

`tools/check.sh` runs what the CI runs (the shipped NPC roles in their generated form, luacheck, then the busted specs) and installs the Lua tooling first with apt if it is missing (`--no-install` to only check). Without the script: `luacheck . && busted --lua=lua5.1 spec`.

Regenerate the textures from the repository root:

```bash
python3 tools/chevron_tga.py GroupChevron/chevron.tga
python3 tools/groupchevron_icon_tga.py GroupChevron/icon.tga
python3 tools/curseforge_icon_png.py assets/curseforge-icon.png
python3 tools/preview_backdrop_tga.py GroupChevron/backdrop.tga
```

Bump `## Version` in `GroupChevron/GroupChevron.toc` with every change to the addon (patch for fixes, minor for features).

To release, run **Actions -> Release -> Run workflow** on main: it releases the `## Version` already committed in the `.toc` (nothing to choose) and fails if that version has already been released. "Dry run" only checks and tests.

## Shipped NPC roles

`GroupChevron/NpcRoles.lua` holds the friendly NPC roles shipped with the addon (creature ID -> role), so NPCs get their icon before anyone opens their window. To add the roles learned in game, close the game, then from the repository root:

```bash
python3 tools/npc_roles.py "<WoW>/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/GroupChevron.lua"
```

Several files can be given at once (other accounts, other players). Their roles are merged into `NpcRoles.lua`; when two disagree, the better role wins, in the order of `Core.ROLES`. Never edit `NpcRoles.lua` by hand: CI checks it is in the generated form (`python3 tools/npc_roles.py --check`). Commit it with a `## Version` bump like any change to the addon.

## Disclaimer

This is a personal project, and its real purpose is to experiment with AI-assisted coding. The WoW addon is mostly a harmless playground for that: small, low-stakes and easy to test. It was built with AI on purpose, and that's the point of it. Use it if it's useful to you; if it isn't, no hard feelings.

## License

[MIT](LICENSE)
