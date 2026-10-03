# Nene and the large A-Bot speaker

Nene's Sparrow atlas uses `rotated="true"` for packed frames. The importer rotates those crops counterclockwise before restoring their original frame offsets. Her `danceLeft` and `danceRight` index sequences are imported separately; Jave alternates them on successive beats without cycling through unrelated atlas poses.

The large speaker is a separate character-attached prop at `assets/imported/characters/nene-large-speaker/`. Its `animation.json` describes 16 baked frames at 24 FPS. Nene's `animation.json` links it through:

```json
"speaker": {
  "assetPath": "../nene-large-speaker",
  "overlap": 140
}
```

`Engine.cpp` draws the attached speaker first, then the seated character, using one common scale and a shared stage floor. The attachment follows camera movement and appears wherever the Nene character is used, including Darnell, Lit Up, 2Hot and Blazin. Other characters are unchanged.

## Rebuild from the user's local files

```powershell
python tools/import_psych_library.py "C:/path/to/PsychEngine" . --characters-only --character nene
python tools/import_nene_speaker.py "C:/path/to/PsychEngine" .
```

The speaker importer composes the supplied Adobe Animate system atlas using nested symbols, keyframe durations, mirroring and affine transforms. It adds the supplied stereo background, visualization pieces and eyes. Speaker cones and display pulse on the song beat; the display is decorative, not a real-time audio-frequency analyser. The screen and eyes use fixed placement tuned for this atlas; custom replacement atlases may need placement adjustments in the importer.

No placeholder art is used. These are user-supplied assets and retain their original rights. Original source files are not modified.
