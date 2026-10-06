# Building Jave Engine on Windows

## Requirements

- Windows 10 or 11 (64-bit)
- Visual Studio 2022 17.4 or newer
- The **Desktop development with C++** workload
- A Windows 10 or 11 SDK
- CMake 3.25 or newer for the supplied presets
- Internet access during the first Lua-enabled configure

## Visual Studio

Open the `JaveEngine` folder with **File > Open > Folder**. Visual Studio recognizes `CMakePresets.json`. Select `windows-x64-release`, allow configuration to finish, choose `JaveEngine.exe`, and build.

Lua is downloaded directly from `lua.org` and verified against the hash in `CMakeLists.txt`. No package manager is required.

## Command line

In **Developer PowerShell for VS 2022**:

```powershell
cmake --preset windows-x64-release
cmake --build --preset release
```

The runnable folder is normally:

```text
build/release/Release/
  JaveEngine.exe
  assets/
  songs/
  data/
  mods/
  scripts/
  config/
  saves/
```

## Offline build

Disable Lua if the machine cannot fetch the pinned source archive:

```powershell
cmake -S . -B build/offline -G "Visual Studio 17 2022" -A x64 -DJAVE_ENABLE_LUA=OFF
cmake --build build/offline --config Release
```

The rest of the engine remains functional. Lua scripts are simply not loaded.

## Packaging

Build Release, then zip the contents of `build/release/Release`, not the directory above it. Keep every runtime folder beside the executable.

## Troubleshooting

- **No C/C++ compiler found:** modify Visual Studio and add Desktop development with C++.
- **Lua download failed:** check TLS/proxy settings, or use the offline build above.
- **No songs appear:** launch from the built output folder and confirm `songs/*/song.json` exists.
- **No audio:** Jave Engine v0.1 supports PCM and Microsoft ADPCM WAV through the Windows multimedia service. Test the file in Windows Media Player and confirm its path in `song.json`.

## Godot build

The Godot 4.7 port lives in `godot/`. `godot/content` links to the repository's `songs`, `data`, `assets`, `scripts`, `config` and `mods` folders and carries a `.gdignore`, so the editor never imports them; the game reads them at runtime with `FileAccess` and `Image.load_from_file`.

### Run and test

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # or godot / Godot_v4.7.1-stable_win64.exe
$GODOT --path godot                                  # play
$GODOT --path godot -- --touch                       # play with the touch controls forced on
$GODOT --headless --path godot --import              # first import / parse check
$GODOT --headless --path godot -s res://tests/test_chart.gd
```

Every `godot/tests/test_*.gd` except `test_base.gd` is a runnable test and exits non-zero on failure.

### Export

Install the 4.7.1 export templates (**Editor > Manage Export Templates**). Presets for macOS, Windows, Linux, Android and iOS are in `godot/export_presets.cfg` and write to `build/godot/<platform>/`.

```sh
mkdir -p build/godot/linux
$GODOT --headless --path godot --export-release Linux build/godot/linux/JaveEngine.x86_64
```

Shipped content is packed by the `jave_content_export` editor plugin, which adds the `content/` files matching each preset's include filter (`content/*.json, *.png, *.wav, *.ogg, *.lua, *.ogv`) to the pack and honours the exclude filter (a local `config/settings.json` is never shipped). Any optional content present in the source folders when exporting is shipped too. Exported builds keep settings, edited charts and enabled-mod state under `user://` (created on first run: `config`, `mods`, `saves`). Defaults always come from the shipped `config/default.json`; `user://config/settings.json` overrides them.

### Android

- Android SDK (build-tools and platform-tools) and a JDK 17; set both paths in **Editor Settings > Export > Android**.
- Debug builds use the editor's debug keystore. For release, create a keystore (`keytool -genkeypair -v -keystore jave.keystore -alias jave -keyalg RSA -validity 10000`) and fill `keystore/release*` in the Android preset locally; do not commit passwords.
- The preset targets arm64 only, landscape, package `com.javeengine.game` (placeholder), no permissions, min SDK 24 (the prebuilt template's minimum; changing it needs a Gradle build).
- WAVs make a large APK. `python tools/convert_audio.py` writes a sibling `.ogg` (Vorbis q6) for each song WAV; mobile builds play the `.ogg` when it exists, and any build falls back to it when the WAV is missing. WAVs stay in git.

### iOS

- macOS with Xcode, an Apple developer team and a provisioning profile. Fill `application/app_store_team_id` and the provisioning profile UUIDs in the iOS preset locally, or export with **Export Project Only** and sign in Xcode.
- lua-gdextension's maintainers note its iOS binaries are not code-signed. The vendored release ships static `.xcframework` archives (`.a` libraries) that are linked into the app binary, so the app signature covers them. iOS export has not been verified end to end. If an update ships dynamic frameworks instead, sign each one before archiving (`codesign --force --timestamp --sign "<identity>" <file>.framework`) or set them to **Embed & Sign** in Xcode.

### Audio latency

Bluetooth headphones and many Android devices report output latency poorly. Adjust **Options > Audio Offset** (`audioOffsetMs` in `user://config/settings.json`, 5 ms steps, ±1000 ms) until hits on a steady beat judge as Sick. The offset is added to the song clock, so if hits judge late, lower it.
