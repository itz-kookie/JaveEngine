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
