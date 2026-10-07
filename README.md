# Jave Engine

A four-lane rhythm game built with Godot 4.7 and GDScript, with Lua 5.4 mod scripting. It runs on macOS, Windows and Linux, and has Android and iOS export presets. Content is plain folders of JSON, PNG, Ogg and Lua files, in the style of FNF engines.

## Features

- Title, Story Mode, Freeplay, Mods, Options, Credits and Results screens.
- JSON songs and charts with player/opponent notes, holds, judgements, scoring, health and camera events.
- Animated PNG characters, stage layouts, health icons and an optional speaker prop attached to a character.
- Ogg Vorbis song audio, with WAV (PCM, float, Microsoft ADPCM) and MP3 also accepted; Ogg Theora cutscenes in Story Mode.
- Pause menu with Resume, Restart Song and Botplay.
- In-song chart editor (press `7`).
- Lua hooks and mod packages that can add songs, weeks, stages, cutscenes, note art and scripts; packs are dropped into the user mods folder or imported as a .zip from the Mods screen (from a file or a URL) on desktop and mobile.
- Basic touch controls.
- 1280x720 canvas scaled to the window, keeping its aspect ratio.

The repository ships one original demo song, **Neon Steps**, with its chart, stage and graphics. Other songs, characters, menu art and videos are imported locally by the user; see [Content import](docs/CONTENT_IMPORT.md).

## Run

Install [Godot 4.7](https://godotengine.org/download). Open `godot/project.godot` in the editor and press Play, or:

```sh
godot --path godot              # play
godot --path godot -- --touch   # force touch controls on a desktop
godot --path godot -- --botplay # start songs with Botplay on
```

`godot` stands for the Godot executable, for example `/Applications/Godot.app/Contents/MacOS/Godot` on macOS. Building, tests and exports are covered in [Building](docs/BUILDING.md).

## Controls

| Where | Keys |
| --- | --- |
| Menus | Up/Down or W/S to move, Left/Right to adjust, Enter to select, Escape to go back |
| Song | D F J K for the four lanes (rebindable in Options), Enter to pause, Escape to leave, `7` for the chart editor |
| Pause menu | Up/Down, Enter; Escape resumes |
| Cutscene | Enter or Space skips; Escape returns to Story Mode |

## Project layout

```text
godot/            Godot project (autoloads, scenes, scripts, tests, export presets, addons)
godot/content/    engine assets, scripts, config and the mods/ symlink
assets/ config/ scripts/ mods/                 engine defaults and playable mod packages
tools/            Python content tools
src/ include/ CMakeLists.txt                  C++ reference implementation (Windows)
```

Settings, enabled-mod state, edited charts and the log are stored in Godot's user data folder, not in the repository. See [Building](docs/BUILDING.md#user-data).

## Documentation

- [Building, testing and exporting](docs/BUILDING.md)
- [Chart format and chart editor](docs/CHART_FORMAT.md)
- [Content import](docs/CONTENT_IMPORT.md)
- [Lua scripting and mods](docs/SCRIPTING.md)
- [Stage placement](docs/STAGE_PLACEMENT.md)
- [Nene and the attached speaker](docs/NENE_SPEAKER.md)

## Python tools

```sh
python -m pip install -r requirements-tools.txt
python tools/validate_content.py
```

The Psych importer and the audio and cutscene converters also need FFmpeg; playing the demo does not.

## Legacy C++ implementation

`src/`, `include/` and `CMakeLists.txt` hold a C++20 Win32 implementation of the same game with an embedded Lua 5.4.8. It builds on Windows only and is kept as a reference. See [Building](docs/BUILDING.md#c-reference-build-windows).

## Licensing

The engine code is covered by [LICENSE](LICENSE). The Neon Steps demo (song, chart, stage and `assets/demo/` graphics) is dedicated under CC0; see [licenses/DEMO.txt](licenses/DEMO.txt). Third-party notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `licenses/`.

Jave Engine is an independent project, not affiliated with The Funkin' Crew, Psych Engine or V-Slice. Imported media, including anything under `assets/imported/`, keeps its authors' rights. Owning a copy does not grant redistribution rights. The ignore rules exclude most imported songs, charts, stages, art and videos, but they do not cover everything: review every commit and every export before publishing (exports pack all local content; see [Building](docs/BUILDING.md#export)).
