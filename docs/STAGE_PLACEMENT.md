# Stage placement

A song's `stage` field selects `data/stages/<stage>.json` in the same mod folder. The stage file is re-read every time a song starts or restarts, so **Restart Song** in the pause menu applies edits without restarting the game.

## Stage file

```json
{
  "boyfriend": [770, 100],
  "opponent": [100, 100],
  "girlfriend": [400, 130],
  "cameraBoyfriend": [0, 0],
  "cameraOpponent": [0, 0],
  "defaultZoom": 0.9,
  "cameraSpeed": 1,
  "hideGirlfriend": false,
  "layout": {
    "revision": 1,
    "width": 1280,
    "height": 720,
    "positionScale": 0.5,
    "placements": {
      "player": { "anchor": [1020, 590], "sourceAnchor": [770, 100], "scale": 0.95 },
      "opponent": { "anchor": [270, 580], "sourceAnchor": [100, 100], "scale": 0.9 },
      "girlfriend": { "anchor": [640, 590], "sourceAnchor": [400, 130], "scale": 0.85 }
    }
  }
}
```

Every field is optional. Values in the stage file override the same values in `song.json`.

- `boyfriend`, `opponent`, `girlfriend`: source positions of each role (Psych-style stage coordinates). The song.json equivalents are `boyfriendPosition`, `opponentPosition`, `girlfriendPosition`.
- `cameraBoyfriend`, `cameraOpponent`: camera offsets used when a `focus` event targets that side.
- `defaultZoom`: base zoom; `cameraSpeed`: how fast the camera eases to its target.
- `hideGirlfriend`: hide the girlfriend role.
- `layout.revision`: written to the log at song start, to confirm which layout was used.

## Layout

`layout` places characters on the stage's background image (`stageImage` in `song.json`), which is scaled to fit the 1280x720 stage and aligned to its bottom edge.

- `width`, `height`: size of the reference image the anchors are measured in (default 1280x720). Anchors scale from it to the stage.
- `placements.<role>` for `player`, `opponent`, `girlfriend`:
  - `anchor`: horizontal centre and floor (feet) position. Larger X moves right; larger Y moves down.
  - `sourceAnchor`: the source position that corresponds to `anchor`. When set, the difference between the role's source position and `sourceAnchor`, multiplied by `positionScale` (default 0.5), is added to `anchor`. Editing `boyfriend`/`opponent`/`girlfriend` then nudges that role.
  - `scale`: multiplies the character's own `scale`. The result is still limited so the character fits the screen.
- Without an `anchor`, a role is placed directly from its source position (centre X `170 + x × 0.9`, floor Y `535 + y × 0.25` in reference coordinates). Provide a layout for reliable alignment with a custom image.

Each role is placed independently; moving, hiding or replacing one character never moves the others. Characters use the same camera transform as the background.

## Character folders

`playerVisual`, `opponentVisual` and `girlfriendVisual` in `song.json` name a folder:

```text
<character>/
  animation.json
  idle/frame_0000.png ...
  left/  down/  up/  right/
  danceRight/        optional
  death/             optional; played when health reaches zero
```

Each pose is a folder of `frame_*.png` files (played in name order) or a single `<pose>.png`. `animation.json`:

```json
{
  "scale": 1,
  "flipX": false,
  "idle": { "width": 220, "height": 310, "fps": 24, "loop": true, "frames": 15 },
  "left": { "width": 220, "height": 310, "fps": 24, "loop": false }
}
```

- `scale`: character size multiplier (combined with the placement `scale`).
- `flipX`: the art faces the other way. The player role is mirrored relative to the other roles, and `flipX` inverts that; Lua's `jave_set_player_flip` mirrors the player again.
- Per pose: `width`, `height` (layout box; default to the idle size, 420x500 if missing), `fps` (default 24, 1–120), `loop` (default true for `idle` only).
- If `danceRight` has `"frames"` greater than 0, idle alternates between `idle` and `danceRight` on successive beats.
- If `death` has frames, it plays when the player runs out of health. Its `loop` setting defaults to `false`; without it, the player fades out.
- `speaker`: attaches a prop below the character; see [Nene and the attached speaker](NENE_SPEAKER.md).

When the opponent and girlfriend use the same folder, the frames are loaded once and shared by both roles; set `hideGirlfriend` to show only the opponent.
