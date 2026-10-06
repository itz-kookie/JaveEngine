# Content and importing

Import content only when its license allows it or its owner has given permission. Imported media keeps its authors' rights and must not be committed or redistributed without them.

## Package layout

The repository root is the base package. The game sees it through `godot/content/` (`res://content/`). Mods use the same layout inside their own folder.

```text
songs/<song-id>/song.json     song manifest
songs/<song-id>/Inst.ogg      song audio (any path named by song.json)
data/charts/<song-id>.json    chart, see CHART_FORMAT.md
data/stages/<stage>.json      stage camera and layout, see STAGE_PLACEMENT.md
data/weeks.json               Story Mode weeks
data/weeks.imported.json      imported Story Mode weeks (base package only, optional, not tracked)
data/cutscenes.json           Story Mode videos (base package only, optional, not tracked)
assets/                       images, characters, videos
scripts/                      Lua scripts, see SCRIPTING.md
config/default.json           default settings
mods/<mod-id>/                mod packages
```

## song.json

```json
{
  "id": "my-song",
  "title": "My Song",
  "artist": "Artist Name",
  "bpm": 120,
  "previewMs": 2000,
  "order": 10,
  "audio": "songs/my-song/Inst.ogg",
  "chart": "data/charts/my-song.json",
  "stage": "neon",
  "stageImage": "assets/my-stage.png",
  "playerVisual": "assets/characters/hero",
  "opponentVisual": "assets/characters/rival",
  "girlfriendVisual": "",
  "playerIcon": "assets/characters/hero/icon.png",
  "opponentIcon": "assets/characters/rival/icon.png",
  "hideGirlfriend": true,
  "description": "Used with permission",
  "license": "Your license or permission note"
}
```

- Paths are relative to the package root (the repository root, or the mod folder for a mod's songs).
- A song is listed only if its `chart` file exists. Freeplay sorts by `order`, then title; `previewMs` is where the Freeplay preview starts.
- `stage` selects `data/stages/<stage>.json` in the same package. Placement and camera fields (`boyfriendPosition`, `opponentPosition`, `girlfriendPosition`, `cameraBoyfriend`, `cameraOpponent`, `cameraGirlfriend`, `defaultZoom`, `cameraSpeed`, `hideGirlfriend`) may also be set here; the stage file overrides them.
- `*Visual` fields name character folders (see [Stage placement](STAGE_PLACEMENT.md#character-folders)).

## Audio

Song audio is a single mixed file: vocals must be mixed into the instrumental. Ogg Vorbis (`.ogg`) is the recommended format; the demo song and the Psych importer use it. The engine also accepts:

- WAV: PCM, float, and Microsoft ADPCM (decoded by the engine).
- MP3 (`.mp3`).

When `audio` names a `.wav` and a sibling `.ogg` with the same name exists, the engine plays the `.ogg`; otherwise it plays the WAV.

`python tools/convert_audio.py` converts song WAVs to Ogg Vorbis (quality 6). It writes a sibling `.ogg` for every `songs/*/Inst.wav` and every `.wav` named by a `song.json`, in the content root and in each mod, and skips WAVs that already have one:

- `--update-manifests` rewrites each `song.json` `audio` field from the `.wav` to its `.ogg`.
- `--delete-wav` deletes each converted WAV that no `song.json` names; use it with `--update-manifests` to leave only Ogg files. WAVs in a folder whose `song.json` cannot be read are kept.
- `--dry-run` prints what would change.

It needs an FFmpeg with `libvorbis` (see [Cutscenes](#cutscenes) for one that has it):

```sh
python tools/convert_audio.py --update-manifests --delete-wav --ffmpeg /path/to/ffmpeg
```

## Weeks

`data/weeks.json`:

```json
{ "format": "jave-weeks-v1", "weeks": [
  { "id": "demo", "name": "Demo Week", "storyName": "First Beat", "songs": ["neon-steps"], "color": [95, 227, 255] }
] }
```

A week plays the listed song ids that are installed, in order, and skips the rest; a week with none of its songs installed is hidden. In the base package, weeks from `data/weeks.imported.json` (written by the Psych importer, gitignored) are listed first, then the shipped `data/weeks.json`; if both define the same id, the imported week is used. Weeks from enabled mods are added after the base package's weeks.

## Cutscenes

Cutscenes play in Story Mode only, before or after a song. They are Ogg Theora (`.ogv`) files listed in `data/cutscenes.json`, an optional local file (the demo has no cutscenes, so none is shipped, and the path is gitignored):

```json
{ "my-song": { "before": "assets/videos/intro.ogv", "after": "assets/videos/outro.ogv" } }
```

Paths are relative to the content root; absolute paths and `..` are rejected. A missing or unplayable video is skipped. `user://content/data/cutscenes.json` and files under `user://content/` take precedence over the files in the content folders.

`python tools/convert_cutscenes.py` converts each listed video (for example MP4) to a sibling `.ogv` and rewrites the manifest entry. It needs an FFmpeg with the `libtheora` and `libvorbis` encoders. Homebrew's `ffmpeg` lacks both; the practical route is the binary bundled with the `imageio-ffmpeg` pip package:

```sh
python -m pip install imageio-ffmpeg
python tools/convert_cutscenes.py --ffmpeg "$(python -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')"
```

Use `--dry-run` to preview. Local video files under `assets/videos/` are gitignored.

## Psych-style content

Jave does not run Psych Lua scripts or events.

Convert one chart you have rights to:

```sh
python tools/convert_psych_chart.py path/to/source.json data/charts/my-song.json
```

It keeps both sides: `mustHitSection` selects the base side and note values 4–7 flip it. `lane` is `noteData % 4`, `lengthMs` is the sustain length. `--player-only` drops opponent notes; `--difficulty` sets the label. Review sync and apply any source offset by hand.

Import a whole local Psych Engine installation (songs, normal-difficulty charts, stages, characters, icons, note skins, weeks):

```sh
python tools/import_psych_library.py /path/to/PsychEngine . --ffmpeg /path/to/ffmpeg
python tools/import_menu_art.py /path/to/PsychEngine .
python tools/configure_stage_layouts.py
```

- Instrumental and voice stems are mixed into one Ogg Vorbis file per song (`songs/<id>/Song.ogg`). `--ffmpeg` must name an FFmpeg with `libvorbis`.
- Ownership follows `mustHitSection` for each section.
- Unconverted JSON is kept under `migration/source-unconverted/` and summarised in `PSYCH_IMPORT_REPORT.md`.
- `--characters-only [--character ID]` and `--notes-only` rebuild just those parts.

Everything the importer writes is gitignored: songs, charts, stages, `assets/imported/`, `data/weeks.imported.json`, `migration/` and `PSYCH_IMPORT_REPORT.md`. It does not touch the shipped `data/weeks.json`. Check `git status` and do not commit imported media.

## Mods

A mod is a folder with a `mod.json` (see [Scripting](SCRIPTING.md#mods)) and the package layout above. Its songs, charts, stages, weeks and scripts resolve from the mod folder. Validate a mod with:

```sh
python tools/validate_jave_mod.py mods/my-mod
```

Mods are loaded from the repository's `mods/` and from `user://mods/`.

## Images and animation

Images are PNG. Character folders hold one subfolder of `frame_*.png` files per pose plus an `animation.json`; see `assets/demo/neon/` and [Stage placement](STAGE_PLACEMENT.md#character-folders). Menu art and the title font are read from `assets/imported/menus/`; menus fall back to plain text when it is missing. Note art (`<kind>_<lane>.png`, where kind is `receptor`, `press`, `confirm`, `note`, `hold` or `hold_end` and lane is `left`, `down`, `up` or `right`) is read from `assets/imported/notes/`, and each file missing there falls back to the demo arrows in `assets/demo/notes/`.

## Checklist

- Confirm you own the content or its license allows redistribution.
- Credit every creator and keep license files.
- Test audio sync, lane ownership, holds and difficulty naming.
- Treat third-party Lua as code: read scripts before running them.
- Run `python tools/validate_content.py` after importing.
