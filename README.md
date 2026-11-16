# GroupChevron

A World of Warcraft addon (Interface 16001, WoW: Forever client) that makes the members of your party or raid easy to spot in a crowd. Standalone: no dependency on any other addon, nothing recorded or uploaded.

## Features

GroupChevron helps you quickly identify your group members, friends and guildmates in a crowd.
The addon achieves this by acting on the nameplates.
The addon is still being tested.

- Adds a pink chevron above group members
- Adds a blue chevron above friends (and Battle.net friends)
- Adds a green chevron above guildmates
- Changes the nameplate font
- Colors names by class
- Displays friendlies' (non-grouped players') health bars only when below 100%

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
```

Bump `## Version` in `GroupChevron/GroupChevron.toc` with every change to the addon (patch for fixes, minor for features).

To release, run **Actions -> Release -> Run workflow** on main: it releases the `## Version` already committed in the `.toc` (nothing to choose) and fails if that version has already been released. "Dry run" only checks and tests.

## Disclaimer

This is a personal project, and its real purpose is to experiment with AI-assisted coding. The WoW addon is mostly a harmless playground for that: small, low-stakes and easy to test. It was built with AI on purpose, and that's the point of it. Use it if it's useful to you; if it isn't, no hard feelings.

## License

[MIT](LICENSE)
