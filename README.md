# Jave Engine

An independent C++20 rhythm-game engine with embedded Lua 5.4.8, currently for Windows 10/11 x64. Inspired by the folder-oriented workflow of FNF engines, not a fork of Psych Engine or V-Slice.

## Features

- Story Mode, Freeplay, Mods, Options, Credits and Exit menus.
- JSON song/chart loading, player/opponent ownership, judgements, scoring and hold notes.
- Animated PNG sprites, stage placements, health icons and camera events.
- Audio playback, optional imported cutscene playback, configurable controls and saved settings.
- Enter pause menu with Resume, Restart and Botplay.
- In-song chart editor (`7`): scroll with the mouse wheel, left-click to add notes, right-click to remove notes. Changes are written only with Save Chart.
- Lua hooks and mod folders. Psych import helpers are included, but arbitrary Psych Lua scripts are not drop-in compatible.
- Fixed 1280x720 rendering scaled proportionally to the window or fullscreen display.

This public source package includes **Neon Steps**, an original demo song/chart and simple original graphics. FNF songs, characters, menu artwork and videos are not bundled. **Arcade Showdown is not included.** Your own legally usable content can be imported locally.

## Build

Install Visual Studio 2022 with Desktop development with C++, a Windows SDK, and CMake 3.25 or newer. In the project folder:

```powershell
cmake --preset windows-x64-release
cmake --build --preset release
```

See `CMakePresets.json` for the exact presets and [building guide](docs/BUILDING.md) for alternatives. The first configure downloads a checksum-pinned Lua release. For an offline build without scripting, configure with `-DJAVE_ENABLE_LUA=OFF`.

Run the built `JaveEngine.exe` alongside its copied `assets`, `songs`, `data`, `mods`, `scripts`, `config`, `saves` and `licenses` folders. These files are required; the executable is not a standalone asset bundle.

For Python content tools:

```powershell
python -m pip install -r requirements-tools.txt
python tools/validate_content.py
```

Some audio import helpers also require FFmpeg; it is not needed to play the included demo.

## Controls and content

Use the arrow keys to navigate menus, Enter to select, Escape to go back. Lane bindings can be changed in Options. Enter pauses during a song; `7` opens the chart editor.

- [Chart format](docs/CHART_FORMAT.md)
- [Content import](docs/CONTENT_IMPORT.md)
- [Lua scripting](docs/SCRIPTING.md)
- [Stage placement](docs/STAGE_PLACEMENT.md)

The current rendering/audio/video backend uses Windows APIs. macOS, Linux, Android and iOS would require platform backends and build work; they are not supported by this release.

## Licensing

Original engine code is covered by [LICENSE](LICENSE). The original demo content is dedicated under CC0; see [demo notice](licenses/DEMO.txt). Lua and toolchain notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `licenses/`.

Imported media retains its authors' rights. Owning a copy does not automatically grant redistribution rights. Keep imported songs, assets, mods, private saves and credentials out of public commits. The ignore rules exclude common local imports and build products; review every commit before uploading.
