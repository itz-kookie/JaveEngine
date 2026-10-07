# Jave chart format v1

Charts are UTF-8 JSON files. Times are milliseconds from the start of the song audio. A song's `song.json` names its chart with the `chart` field (see [Content import](CONTENT_IMPORT.md)).

```json
{
  "format": "jave-chart-v1",
  "song": "my-song",
  "difficulty": "normal",
  "bpm": 120,
  "offsetMs": 0,
  "notes": [
    { "timeMs": 1000, "lane": 0, "owner": "opponent" },
    { "timeMs": 1500, "lane": 1, "owner": "player", "lengthMs": 500 }
  ],
  "cameraEvents": [
    { "timeMs": 0, "type": "focus", "target": "opponent" },
    { "timeMs": 2400, "type": "focus", "target": "player" },
    { "timeMs": 4800, "type": "zoom", "amount": 0.015 }
  ]
}
```

## Fields

- `format`: must be `jave-chart-v1`.
- `song`: song id (defaults to the id from `song.json`).
- `difficulty`: label, default `normal`.
- `bpm`: tempo, greater than 0 and at most 1000 (defaults to the `song.json` BPM). Drives idle animation timing and the chart editor's snap.
- `offsetMs`: added to every note and camera event time; positive values make them later.
- `notes`: at least one note. Notes are sorted by time on load, so file order does not matter.
  - `timeMs`: required; must be 0 or more after `offsetMs` is applied.
  - `lane`: required, 0–3, left to right.
  - `owner`: `player` or `opponent`; anything else counts as `player`.
  - `lengthMs`: optional hold length.
- `cameraEvents`: optional; events without a `type` are skipped.
  - `focus` with `target` `player` or `opponent`: pan toward that side.
  - `position` with `x`, `y`: hold the camera at a stage position until the next `focus`.
  - `zoom` with `amount`: a short zoom pulse.
  - `setZoom` with `amount`: set the base zoom (clamped 0.55–1.5).

A chart is rejected if the format, BPM, a note's lane or a note's time is invalid, or if it has no notes. Unknown fields are ignored. The song ends when its audio ends.

## Judging

Only player notes are judged; opponent notes play automatically.

| Rating | Window | Score | Accuracy |
| --- | --- | --- | --- |
| Sick | ±45 ms | 350 | 100% |
| Good | ±90 ms | 200 | 75% |
| Bad | ±180 ms | 100 | 40% |
| Miss | later than 180 ms | 0 | 0% |

For a hold, hit the head normally and keep the lane held until `timeMs + lengthMs`. Releasing for more than 100 ms before the end breaks the hold and counts as a miss; completing it adds 100 points.

## In-game chart editor

Press `7` while a song is playing. The song pauses and the editor works on a copy of the chart. The grid shows opponent lanes on the left and player lanes on the right; snap is a sixteenth note at the chart's BPM.

- Mouse wheel over the grid: scroll through time.
- Left-click the grid: add a note there (or update the hold length of a note already there).
- Right-click the grid: delete the nearest note in that lane.
- Click Add Note, Delete Nearest, Save Chart or Exit Without Saving.
- `Q` / `E`: move the time cursor one snap; `Page Up` / `Page Down`: sixteen snaps.
- Left / Right: select lane; `Tab`: switch Player/Opponent.
- `A` / `D`: shorten or lengthen the hold for new notes.
- `Space`: add or update a note at the cursor.
- Up / Down and Enter: choose and use the action buttons.
- `7` or Escape: leave the editor.

Nothing is written until **Save Chart**. Leaving without saving discards the edits. A chart with no notes cannot be saved.

Saving writes to the user data folder at the mirror of the chart's path, for example `user://content/mods/jave-demo/data/charts/neon-steps.json`, and the running song continues with the saved chart. From then on that file is loaded instead of the shipped chart. To return to the shipped chart, delete the file (see [Building](BUILDING.md#user-data) for the folder location). To keep an edit in the repository, copy the file back into the same mod-relative path. Charts of mods installed in `user://mods/` are saved in place.
