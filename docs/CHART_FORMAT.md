# Jave chart format v1

Charts are UTF-8 JSON files. Times are milliseconds from the start of the instrumental.

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

- `format`: must be `jave-chart-v1`
- `song`: song identifier matching its metadata
- `difficulty`: display label
- `bpm`: positive tempo used by presentation and tooling
- `offsetMs`: global chart shift; positive values make notes occur later
- `notes`: note objects sorted by `timeMs`
- `lane`: integer 0–3, left to right
- `owner`: `player` or `opponent` (defaults to `player` for older Jave charts)
- `lengthMs`: optional hold duration
- `cameraEvents`: optional focus, forced-position, and zoom changes

Sustain heads are judged normally. Keep the matching lane key held until `timeMs + lengthMs`; releasing for more than 100 ms breaks the hold.

Camera event types are `focus` (`player`/`opponent`), `position`, `zoom`, and `setZoom`. Imported Psych charts generate focus events from section ownership and retain supported camera events from `events.json`.

The loader validates types, lane bounds, negative times, and ordering. Unknown fields are ignored so future tools can add editor metadata.

## Timing windows

- Sick: ±45 ms
- Good: ±90 ms
- Bad: ±135 ms
- Miss: past ±180 ms

Accuracy weights are 100%, 75%, 40%, and 0% respectively.

## In-game chart editor

Press `7` while a song is playing. The editor pauses the song and works on a temporary chart copy.

- Move the pointer over the chart and use the mouse wheel to scroll through time.
- Left-click a lane/time position to place a snapped note.
- Right-click a displayed note to delete it.
- The Add, Delete, Save Chart, and Exit buttons can be clicked.
- `Q` / `E`: move the time cursor by one sixteenth-note snap
- `Page Up` / `Page Down`: move by sixteen snaps
- Left / Right: select lane 1–4
- `Tab`: switch Player/Opponent ownership
- `A` / `D`: shorten or lengthen the new note's sustain
- `Space`: add or update a note at the cursor
- Up / Down and Enter: use Add Note, Delete Nearest, Save Chart, or Exit Without Saving

There is no automatic saving. The chart file is written only when **Save Chart** is selected. Pressing `7`, Escape, or Exit Without Saving returns to the song without writing unsaved editor changes.
