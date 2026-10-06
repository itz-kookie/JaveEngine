# Nene and the attached speaker

Any character can carry a prop drawn beneath it, declared in its `animation.json`. The Weekend 1 importer uses this for Nene sitting on the A-Bot speaker.

```json
"speaker": {
  "assetPath": "../nene-large-speaker",
  "overlap": 140
}
```

- `assetPath`: the prop's character folder, relative to the character's folder. Only its `idle` pose is used.
- `overlap`: how many source pixels of the prop's top the character overlaps (clamped to the prop's height).

The character and prop are scaled together as one box (prop below, character lifted by the prop's height minus `overlap`) and placed at the role's anchor (see [Stage placement](STAGE_PLACEMENT.md)). The prop is drawn behind the character and moves with the camera. Its `idle` animation restarts on every beat at its own `fps`, so it pulses with the song. The prop appears wherever that character is used; other characters are unaffected.

## Nene's frames

Nene's Sparrow atlas packs some frames with `rotated="true"`; the importer rotates those crops back before restoring their frame offsets. Her `danceLeft` and `danceRight` animations are imported as the `idle` and `danceRight` poses, and the engine alternates them on successive beats.

## Rebuilding from local files

```sh
python tools/import_psych_library.py /path/to/PsychEngine . --characters-only --character nene
python tools/import_nene_speaker.py /path/to/PsychEngine .
```

`import_nene_speaker.py` bakes the Adobe Animate A-Bot system atlas (nested symbols, keyframe durations, mirroring and affine transforms) together with the stereo background, visualiser bars and eyes into `assets/imported/characters/nene-large-speaker/` (16 frames at 24 FPS for the standard atlas), then adds the `speaker` entry to Nene's `animation.json`. The visualiser is baked into the frames and does not follow the audio. Screen and eye positions are fixed for this atlas; a different atlas may need adjustments in the script.

These files are made from the user's own copy of the game, keep their authors' rights, and are gitignored. Source files are not modified.
