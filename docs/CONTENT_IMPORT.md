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
data/cutscenes.json           Story Mode videos (optional)
assets/                       images, characters, note art, videos
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

A week plays the listed song ids that are installed, in order, and skips the rest; a week with none of its songs installed is hidden. In the base package, weeks from `user://content/data/weeks.imported.json` are listed first, then `data/weeks.imported.json` (written by the Psych importer, gitignored), then the shipped `data/weeks.json`; when several define the same id, the first one is used. Weeks from enabled mods are added after the base package's weeks, in Mods screen order, and a week whose id is already listed is skipped. A week plays each song from its own package when that package has a song with that id, otherwise the first installed one.

## Cutscenes

Cutscenes play in Story Mode only, before or after a song. They are Ogg Theora (`.ogv`) files listed in `data/cutscenes.json`, an optional file in any package (the demo has no cutscenes, so the base package ships none, and its path is gitignored):

```json
{ "my-song": { "before": "assets/videos/intro.ogv", "after": "assets/videos/outro.ogv" } }
```

Paths are relative to the root of the package whose manifest lists them; absolute paths and `..` are rejected. For each song the manifests are read in this order, and the first one with an entry for that side decides:

1. the package the song comes from (its mod, for a mod's song);
2. the base package, where `user://content/data/cutscenes.json` replaces `data/cutscenes.json` when present and files under `user://content/` take precedence over the files in the content folders;
3. the other enabled mods, in Mods screen order.

A missing or unplayable video is skipped.

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

A mod is a folder with a `mod.json` (see [Scripting](SCRIPTING.md#mods)) and the package layout above. Its songs, charts, stages, weeks, cutscenes, note art and scripts resolve from the mod folder. Validate a mod with:

```sh
python tools/validate_jave_mod.py mods/my-mod
```

Mods are loaded from the repository's `mods/` and from `user://mods/`.

## Content packs

A content pack is a mod folder. It is how content is added to an installed game on desktop, Android and iOS: copy the folder into `user://mods/<mod-id>/`, or import it as a `.zip` from the Mods screen. See [Building](BUILDING.md#user-data) for where `user://` is on each OS.

- Desktop: copy the folder in, or import a `.zip`.
- iOS: the game's folder is visible in the Files app (**On My iPhone > Jave Engine**) and in Finder file sharing, so a pack can be copied into its `mods/` folder; importing a `.zip` from a URL also works.
- Android: the game's folder is private to the app, so packs are imported as a `.zip` from a file or a URL.

```text
<mod-id>/
  mod.json                                 {"id": "<mod-id>", "name": "...", "version": "...", "author": "..."}
  songs/<song-id>/song.json                song manifest; paths in it are relative to <mod-id>/
  songs/<song-id>/Inst.ogg                 song audio
  data/charts/<song-id>.json               chart
  data/stages/<stage>.json                 stage layout named by the song's "stage"
  data/weeks.json                          Story Mode weeks
  data/cutscenes.json                      Story Mode videos, relative to <mod-id>/
  assets/characters/<name>/                character folders named by "playerVisual" and friends
  assets/icons/                            health icons named by "playerIcon" / "opponentIcon"
  assets/stages/                           stage images named by "stageImage"
  assets/imported/notes/<kind>_<lane>.png  note art for this pack's songs
  assets/imported/menus/weeks/<week-id>.png  Story Mode banner for this pack's week
  assets/videos/                           cutscene videos
  scripts/*.lua                            Lua scripts
```

Only `mod.json` is required. The `assets/` subfolders are a convention: `song.json` names every asset path, so any layout inside the pack works.

A pack's week plays its songs from the same pack when another package has songs with the same ids, and a week id already listed by the base content or by a mod earlier in Mods screen order is skipped.

### Packs from an imported library

`python tools/make_content_packs.py` turns each week of `data/weeks.imported.json` (not the demo week) into a pack at `build/packs/<week-id>.zip`, holding a `fnf-<week-id>/` mod folder with the week's songs, charts, stages, character folders (with any attached speaker), icons, stage images, all 24 note images, the week banner and the week's cutscene entries and videos. Characters shared between weeks, such as bf and gf, are copied into each pack. Every mod folder is checked with `tools/validate_jave_mod.py` before it is zipped. `--weeks week1 weekend1` builds only those weeks, `--out DIR` writes elsewhere, and `--dry-run` lists each pack without writing. The packs hold the user's own imported content, for the user's own devices; they grant no redistribution rights.

### Zip layout

The zip holds the pack either at its root (`mod.json` next to `songs/`) or inside one top-level folder (`my-pack/mod.json`). Any other placement of `mod.json`, or more than one top-level folder with one, is rejected. The pack is installed into `user://mods/<id>/`, where `<id>` comes from `mod.json`, not from the zip or folder name.

- `id` must be a string of letters, digits, `.`, `_` and `-`, starting with a letter or digit, at most 64 characters.
- Entry paths are read with `\` as `/`, and empty and `.` segments are dropped (`./pack//songs` is `pack/songs`). A zip with an absolute entry path, a `:` (drive letter or stream name), a `..` segment (also percent-encoded, as in `%2e%2e`), an encoded `/` or `\`, a control character, or a symbolic link entry is rejected whole.
- Limits, checked from the zip's directory before anything is unpacked: at most 50,000 entries, 512 MiB per file, and 2 GiB for the `.zip` itself and for everything it unpacks to. Zip64 archives are rejected, since they only exist to exceed these limits. Free storage is not checked; a full disk fails the import like any other write error.
- Files outside the pack folder (for example a `README.txt` beside it) and `__MACOSX/` folders are skipped.
- Entries are extracted one at a time into `user://cache/mod-import/<id>/`, which replaces `user://mods/<id>/` only after every file is written, so a failed import leaves an installed mod untouched. The installed copy is moved aside, the new one moved in, and the old one deleted; if the new one cannot be moved in, the old one is moved back (or, if even that fails, left in `user://cache/mod-import/<id>.previous` and named in the error).

### Mods screen importer

**Import content pack** is the last row of the Mods screen:

- **From file** opens the system file picker filtered to `.zip`. It is shown only where Godot reports a native file dialog (`DisplayServer.FEATURE_NATIVE_DIALOG_FILE`); elsewhere the row is hidden, and packs come from **From URL** or are copied into `user://mods/`.
- **From URL** shows a text field for an `http://` or `https://` link. Enter (or the **Download** row) downloads it to `user://cache/<name>.zip` with a progress line, imports it and deletes the download, whether the import succeeds or not. Up to 5 redirects are followed; any final status other than 200, a body over 2 GiB, or 30 seconds without receiving data fails the download. Escape or **Cancel download** stops it and deletes the partial file.

When a mod with the same id is installed, the screen asks **Replace <id>** or **Keep installed version** before writing anything; leaving the screen at that prompt keeps the installed version. After an import the mod list, Story Mode weeks and Freeplay songs refresh at once, the mod keeps its enabled or disabled state, and images from the replaced copy are reloaded from disk. Its Lua scripts load at the next start: scripts already running keep the old copy until then. The result, or the reason a pack was rejected, is shown under the mod details. Importing runs on the main thread, so the screen pauses while a large pack is unpacked.

Web builds have no importer and no Import content pack row.

## Images and animation

Images are PNG. Character folders hold one subfolder of `frame_*.png` files per pose plus an `animation.json`; see `assets/demo/neon/` and [Stage placement](STAGE_PLACEMENT.md#character-folders). Menu art and the title font are read from `assets/imported/menus/`; menus fall back to plain text when it is missing. A week banner (`weeks/<week-id>.png`) is read from the week's mod first, then from the base content. Note art (`<kind>_<lane>.png`, where kind is `receptor`, `press`, `confirm`, `note`, `hold` or `hold_end` and lane is `left`, `down`, `up` or `right`) is looked up per file, in this order: the song's mod `assets/imported/notes/` (for a mod's song), `user://content/assets/imported/notes/`, the base package's `assets/imported/notes/`, then the demo arrows in `assets/demo/notes/`.

## Checklist

- Confirm you own the content or its license allows redistribution.
- Credit every creator and keep license files.
- Test audio sync, lane ownership, holds and difficulty naming.
- Treat third-party Lua as code: read scripts before running them.
- Run `python tools/validate_content.py` after importing.
