# Importing legally owned rhythm-game content

Jave Engine does not include Friday Night Funkin' songs, characters, or source code. You may import content only when its license permits it or you have permission from its owner.

## Jave package layout

```text
songs/<song-id>/
  song.json
  Inst.wav
data/charts/
  <song-id>.json
assets/images/
mods/<mod-id>/
  mod.json
  songs/
  data/charts/
  data/weeks.json
  assets/
  scripts/
scripts/
config/
saves/
```

Create `songs/my-song/song.json`:

```json
{
  "id": "my-song",
  "title": "My Song",
  "artist": "Artist Name",
  "bpm": 120,
  "audio": "songs/my-song/Inst.wav",
  "chart": "data/charts/my-song.json",
  "description": "Used with permission",
  "license": "Your license or permission note"
}
```

Convert the instrumental to 16-bit PCM WAV or Microsoft ADPCM WAV. Jave Engine v0.1 uses one mixed song file; split vocal stems should be mixed with the instrumental during import.

## Psych-style charts

Psych-style song folders commonly contain a chart JSON under `mods/<mod>/data/<song>/` and `Inst.ogg`/`Voices.ogg` under `mods/<mod>/songs/<song>/`. Jave Engine does not execute Psych Lua directly and does not silently copy assets.

To convert a chart you have rights to:

1. Read its section notes, usually `[strumTime, noteData, sustainLength, ...]`.
2. Set `timeMs` to `strumTime`.
3. Normalize `lane` to `noteData % 4`. `mustHitSection` chooses the base player/opponent side; Psych note values 4–7 flip ownership to the other side.
4. Set `lengthMs` to `sustainLength` when positive.
5. Apply any source chart offset deliberately and test sync.
6. Export the result using `jave-chart-v1` from [CHART_FORMAT.md](CHART_FORMAT.md).

The included helper performs this timing conversion and preserves both streams by default:

```powershell
python tools/convert_psych_chart.py path\to\source.json data\charts\my-song.json
```

The converter preserves both sides by default and writes `owner: player` or `owner: opponent`. Pass `--player-only` only when deliberately discarding the opponent performance.

To import an entire local Psych installation, including mixed instrumental and voice stems:

```powershell
python tools/import_psych_library.py C:\path\to\PsychEngine . --ffmpeg C:\path\to\ffmpeg.exe
```

The batch importer preserves unsupported difficulty/event JSON under `migration/source-unconverted/` and writes `PSYCH_IMPORT_REPORT.md`.

For a self-contained Jave mod, create `mods/<mod-id>/mod.json` and use the package layout above. Convert charts individually, prepare legally usable WAV audio and graphics, then validate the package:

```powershell
python tools/validate_jave_mod.py mods\my-mod
```

Enabled Jave mod packages may contribute their own `songs/*/song.json` files and `data/weeks.json`; all paths inside those song manifests resolve from the mod folder. Keep source backups separately and migrate unsupported scripts and events manually.

Because engine forks vary, conversion should be reviewed by a human. Preserve the source license and credits.

## V-Slice-style charts

V-Slice packages commonly keep metadata and chart files under `data/songs/<song-id>/`, with audio in `songs/<song-id>/`. V-Slice chart data can contain multiple difficulties, variations, events, and separate note streams. Select one difficulty, flatten its playable notes into milliseconds and lanes 0–3, then create a Jave metadata file. Unsupported events should be documented rather than guessed.

## Images and animation

The renderer supports PNG frames with `animation.json` metadata, cached GDI+ images, frame durations and looping. See the original demo's `assets/demo/neon/animation.json` and its pose folders for a working example. Import helpers can bake supported source atlases into PNG frames. Describe asset licenses in the mod README.

## Safety checklist

- Confirm you own the content or its license allows redistribution.
- Credit every creator and keep license files.
- Do not package the original commercial/fan-game assets merely because they are easy to find online.
- Test audio sync, lane ownership, sustains, and difficulty naming.
- Treat third-party Lua mods as code: inspect scripts before running them.
