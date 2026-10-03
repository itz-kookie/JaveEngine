# Per-stage character placement

Stage layouts live in `data/stages/<stage>.json`, or a mod's own `data/stages/` folder. The active package's stage file overrides the stage positions and camera settings copied into individual song manifests. This repository includes only the original Neon demo stage.

The `layout` section maps the original stage coordinates onto Jave's baked background image. Example:

```json
"layout": {
  "width": 1280,
  "height": 720,
  "positionScale": 0.5,
  "placements": {
    "player": { "anchor": [1020, 590], "sourceAnchor": [770, 100], "scale": 0.95 },
    "opponent": { "anchor": [270, 580], "sourceAnchor": [100, 100], "scale": 0.9 },
    "girlfriend": { "anchor": [640, 590], "sourceAnchor": [400, 130], "scale": 0.85 }
  }
}
```

- `anchor`: horizontal center and floor/feet position in the reference image. Increasing X moves right; increasing Y moves down.
- `scale`: stage-specific multiplier on that character's source scale, still bounded to fit the screen.
- `sourceAnchor`: source coordinate corresponding to the presentation anchor; normally leave it unchanged.
- Editing the top-level `boyfriend`, `opponent` or `girlfriend` coordinates also moves that role. The change from `sourceAnchor`, multiplied by `positionScale`, is added to its presentation anchor.

Coordinates scale with the window and use the same camera transform as the background. Nene and A-Bot share the girlfriend anchor; hidden girlfriends do not affect other roles. Moving or replacing one character never re-spaces the other characters.

Stage files are reloaded when starting or restarting a song. After editing a layout, select Restart Song to apply it; no complete engine restart is required. New stages without a layout use a stable direct source-coordinate fallback rather than min/max character normalization. For reliable alignment with a custom baked image, provide its own layout.

The window title is `Jave Engine`. The log records the selected stage file and its layout revision for every song start.

Import-tool presets are tuned for baked static backgrounds, not pixel-identical recreations of other engines' world cameras. Animated stage layers and source-specific stage scripts require additional implementation.
