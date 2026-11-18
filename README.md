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
- Every chevron has a black outline (one **Outline** slider per section: group members, friends, guildmates, quest hostiles; default 2, from 0 = no outline to 5) and the options page shows a live preview of the chevron (chosen colour, size and outline), beside each colour swatch.
- Changes the nameplate font
- Colors names by class
- Displays friendlies' (non-grouped players') health bars only when below 100%
- Friendly NPCs (**Friendly NPCs** section of the options): a role icon above flight masters, innkeepers, bankers, auctioneers, stable masters, class and profession trainers, repairers and vendors (`/gchev npcicons on|off`, `/gchev npciconsize 1-15`, default 5), "<name> (<level>)" in the game's reaction colour (green friendly, yellow neutral) with the NPC's subtitle on a line below it ("<Maître des gryphons>"), every friendly NPC's plate down to that, with the health bar only while hurt, the target included (`/gchev npccompact on|off`, on by default), their name's text size (`/gchev npcsize 1-3`) and height (`/gchev npcnamegap -10-40`, default 5). All of it needs the game's friendly NPC nameplates: `/gchev npcplates on` (or the first checkbox of that section) turns them on; the addon never changes that setting by itself. The role comes from the windows an NPC opens for you (learned once, then shown on every visit) and, on English and French clients, from its subtitle ("<Gryphon Master>", "<Maître des gryphons>"). `/gchev icon` lists the icon of each role, and `/gchev icon <role> <texture or atlas>` changes one (an atlas name is checked against the client; `default` gives the role its own icon back)

## Layout

| Path | Content |
|---|---|
| `GroupChevron/` | the addon: `Core.lua` (pure, unit-tested logic), `GroupChevron.lua` (WoW glue), `.toc`, `chevron.tga`, `icon.tga` |
| `assets/` | CurseForge project icon (`curseforge-icon.png`, 400×400) |
| `docs/` | implementation notes |
| `spec/` | [busted](https://lunarmodules.github.io/busted/) tests (`Core.lua` and a smoke test of the glue against a stubbed WoW API) |
| `tools/` | generators for `chevron.tga` and `icon.tga` (Python 3, no dependencies) |
| `.luacheckrc` | luacheck configuration (Lua 5.1, WoW globals) |

## Development

Lua 5.1, as in the WoW client. Keep logic that does not need the WoW API in `Core.lua`, with tests in `spec/`.

```bash
luacheck . && busted --lua=lua5.1 spec
```

Regenerate the textures from the repository root:

```bash
python3 tools/chevron_tga.py GroupChevron/chevron.tga
python3 tools/groupchevron_icon_tga.py GroupChevron/icon.tga
python3 tools/curseforge_icon_png.py assets/curseforge-icon.png
python3 tools/preview_backdrop_tga.py GroupChevron/backdrop.tga
```

Bump `## Version` in `GroupChevron/GroupChevron.toc` with every change to the addon (patch for fixes, minor for features).

To release, run **Actions -> Release -> Run workflow** on main: it releases the `## Version` already committed in the `.toc` (nothing to choose) and fails if that version has already been released. "Dry run" only checks and tests.

## Disclaimer

This is a personal project, and its real purpose is to experiment with AI-assisted coding. The WoW addon is mostly a harmless playground for that: small, low-stakes and easy to test. It was built with AI on purpose, and that's the point of it. Use it if it's useful to you; if it isn't, no hard feelings.

## License

[MIT](LICENSE)
