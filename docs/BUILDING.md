# Building Jave Engine

The game is the Godot 4.7 project in `godot/`. The last section covers the C++ reference build.

## Requirements

- Godot 4.7 (the project is tested with 4.7.1). No compile step is needed; the scripts are GDScript.
- For exports: the matching export templates (**Editor > Manage Export Templates**).
- For the Python tools: Python 3 and `pip install -r requirements-tools.txt` (Pillow). FFmpeg with `libvorbis` (and `libtheora` for cutscenes) for the audio and cutscene converters, the Psych importer and `tools/generate_neon_steps.py`.

## Project structure

- `godot/autoload/`: `Paths`, `Log`, `Settings`, `Content`, `ModHost`, `Conductor`, `LaneInput`.
- `godot/scenes/`: `Main` (screen flow), menus, play scene, chart editor, cutscene player.
- `godot/scripts/`: data and helper classes (charts, songs, weeks, mods, WAV decoding, touch input).
- `godot/tests/`: headless test scripts.
- `godot/addons/lua-gdextension/`: Lua 5.4 runtime (lua-gdextension 0.8.2, prebuilt for every export platform).
- `godot/addons/jave_content_export/`: editor plugin that packs content into exports.
- `godot/content/`: symlinks to the repository's `songs`, `data`, `assets`, `scripts`, `config` and `mods` folders, with a `.gdignore` so the editor never imports them. The game reads them at runtime from `res://content/` with `FileAccess` and `Image.load_from_file`.

On Windows, clone with symlinks enabled (`git clone -c core.symlinks=true`, with Developer Mode or an elevated shell) or the `godot/content` links arrive as plain text files.

## Run and test

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # or godot / Godot_v4.7.1-stable_win64.exe
$GODOT --path godot                                  # play
$GODOT --path godot -- --touch                       # touch controls forced on (mouse emulates touch)
$GODOT --path godot -- --botplay                     # songs start with Botplay on
$GODOT --headless --path godot --import              # first import / parse check
$GODOT --headless --path godot -s res://tests/test_chart.gd
```

Each `godot/tests/test_*.gd` except `test_base.gd` (the shared harness) is a runnable test that prints a summary and exits non-zero on failure:

`test_assets`, `test_audio`, `test_chart`, `test_chart_editor`, `test_content_pack`, `test_cursors`, `test_cutscene`, `test_judging`, `test_lua`, `test_menu_flow`, `test_mod_import`, `test_paths`, `test_play_scene`, `test_settings`, `test_touch`.

`test_play_scene` plays Neon Steps under Botplay in real time and takes about 30 seconds.

## User data

Writable data lives in Godot's `user://` folder:

| OS | Location |
| --- | --- |
| macOS | `~/Library/Application Support/Godot/app_userdata/Jave Engine/` |
| Windows | `%APPDATA%\Godot\app_userdata\Jave Engine\` |
| Linux | `~/.local/share/godot/app_userdata/Jave Engine/` |
| Android | the app's private storage (reached through the Mods screen importer) |
| iOS | the app's Documents folder, shown in the Files app under **On My iPhone > Jave Engine** |

Contents:

- `config/settings.json`: options. Defaults come from the shipped `config/default.json`; this file overrides them. Keys: `masterVolume` (0–1), `noteSpeed` (0.5–2.5), `downscroll`, `fullscreen`, `showFps`, `audioOffsetMs` (−1000 to 1000), `keybinds` (four Windows virtual-key codes, left to right; default `[68, 70, 74, 75]` = D F J K).
- `config/mods.json`: enabled/disabled state chosen in the Mods screen.
- `mods/<mod-id>/`: mods and content packs installed by the user (copied in or imported from the Mods screen), loaded alongside the shipped `mods/`. See [Content packs](CONTENT_IMPORT.md#content-packs).
- `cache/`: downloads and staging folders used while importing a content pack; safe to delete.
- `saves/jave.log`: the game log, including Lua errors.
- `content/...`: overrides that mirror shipped paths. A chart saved in the chart editor is written here (for example `user://content/data/charts/neon-steps.json`) and is loaded instead of the shipped chart. `user://content/data/cutscenes.json` and videos under `user://content/` override the cutscene manifest and videos in the content folders the same way. `user://content/data/weeks.imported.json` lists weeks before the content folders' weeks, and note art in `user://content/assets/imported/notes/` is used before the content folders' note art. Delete the file to return to the shipped version.

## Export

Presets for macOS, Windows Desktop, Linux, Android and iOS are in `godot/export_presets.cfg` and write to `build/godot/<platform>/`.

The version shown in the game and stamped into exports is `application/config/version` in `godot/project.godot`; the presets leave their version fields empty so they use it. Android's integer `version/code` is set separately in its preset.

```sh
mkdir -p build/godot/linux
$GODOT --headless --path godot --export-release Linux build/godot/linux/JaveEngine.x86_64
```

The `jave_content_export` plugin adds every file under `godot/content/` that matches the preset's include filter (`content/*.json, *.png, *.wav, *.ogg, *.mp3, *.lua, *.ogv`) and not its exclude filter (a local `content/config/settings.json` is never packed).

Song WAVs in the content folders are packed as they are and make builds large. Run `python tools/convert_audio.py --update-manifests --delete-wav` before exporting to convert them to Ogg Vorbis; see [Content import](CONTENT_IMPORT.md#audio).

**The export packs everything present in the content folders, including locally imported and gitignored songs, art and videos.** An export made from a working copy with imported FNF or other third-party media contains that media. Export from a clean checkout, or remove the imported files first, before distributing a build.

Exported builds do not include `LICENSE`, `THIRD_PARTY_NOTICES.md` or `licenses/`; ship them alongside the build.

### Android

- Android SDK (build-tools and platform-tools) and JDK 17; set both paths in **Editor Settings > Export > Android**.
- Debug builds use the editor's debug keystore. For release, create a keystore (`keytool -genkeypair -v -keystore jave.keystore -alias jave -keyalg RSA -validity 10000`) and fill `keystore/release*` in the Android preset locally. Do not commit keystores or passwords.
- The preset targets arm64 only, uses the prebuilt template (no Gradle build), immersive landscape, package `com.javeengine.game` (placeholder), and the Internet permission only, used by the Mods screen's **From URL** importer.

### iOS

- macOS with Xcode, an Apple developer team and a provisioning profile. Fill `application/app_store_team_id` and the provisioning profile UUIDs in the iOS preset locally, or enable **Export Project Only** and sign in Xcode.
- The lua-gdextension and godot-cpp iOS libraries are static `.xcframework` archives (`.a`), linked into the app binary and covered by its signature. If they are replaced with dynamic frameworks, sign each one or set it to **Embed & Sign** in Xcode.
- The preset exposes the app's Documents folder (`user://`) in the Files app and Finder file sharing, so content packs can be copied into `mods/`.
- iOS export has not been verified end to end.

### Audio latency

Bluetooth headphones and many Android devices report output latency poorly. Adjust **Options > Audio Offset** (5 ms steps) until hits on a steady beat judge as Sick. The offset is added to the song clock: if hits judge late, lower it.

## Troubleshooting

- **No songs appear:** confirm `godot/content/songs` resolves to the repository's `songs/` folder and that each song has `songs/<id>/song.json` with an existing chart.
- **No audio:** check the `audio` path in `song.json` and that the file is Ogg Vorbis, WAV (PCM, float or Microsoft ADPCM) or MP3. Errors are written to `user://saves/jave.log`.
- **A chart edit will not go away:** delete its file under `user://content/data/charts/`.

## C++ reference build (Windows)

`src/`, `include/`, `CMakeLists.txt` and `CMakePresets.json` hold the C++20 reference implementation. It uses Win32, GDI+ and Windows multimedia APIs, reads the same content folders, and keeps `config/settings.json` and `saves/jave.log` beside the executable.

Requirements: Windows 10/11 x64, Visual Studio 2022 with **Desktop development with C++** and a Windows SDK, CMake 3.25 or newer, and internet access on the first configure (Lua 5.4.8 is downloaded from lua.org and checked against the hash in `CMakeLists.txt`).

```powershell
cmake --preset windows-x64-release
cmake --build --preset release
```

The runnable folder is `build/release/Release/`; the build copies `assets`, `songs`, `data`, `mods`, `scripts`, `config`, `saves` and `licenses` next to `JaveEngine.exe`. Configure with `-DJAVE_ENABLE_LUA=OFF` to build without Lua and without the download. `tools/package.ps1` builds and zips the runnable folder into `dist/`; like the Godot export, that zip contains whatever imported content is in those folders.
