# Lua scripting

Jave runs mod scripts in plain Lua 5.4 through the lua-gdextension addon. All scripts share one Lua state with the Lua standard libraries opened (including `io` and `os`); no Godot APIs are exposed to them. Only run scripts you trust.

## Load order

Scripts load once, at startup:

1. `scripts/boot.lua`
2. Other `scripts/*.lua`, sorted by path
3. `scripts/*.lua` of every enabled mod, sorted by path as one list

Enabling or disabling a mod in the Mods screen updates its songs and weeks immediately, but its scripts are loaded or dropped only after restarting the game.

A script error is written to the log (`user://saves/jave.log`) and does not stop the game or the other scripts. A leading UTF-8 BOM and a first line starting with `#` are ignored.

## Global API

```lua
jave_log(message)           -- write a line to the log
jave_engine_name()          -- returns "Jave Engine"
jave_set_accent(r, g, b)    -- menu and HUD accent colour, integers clamped to 0..255
jave_set_player_flip(flip)  -- mirror the player character horizontally (any truthy value)
```

Wrong argument types raise a normal Lua error, for example `bad argument #1 to 'jave_set_accent' (number expected, got nil)`.

## Hooks

Define any of these as globals:

```lua
function on_update(dt) end              -- every frame (menus included) except while paused, editing or in a cutscene; dt in seconds, capped at 0.05
function jave_core_song_start(song_id) end
function on_song_start(song_id) end
function on_note_hit(lane, rating) end
```

- At each song start the player flip is reset to off, then `jave_core_song_start` runs, then `on_song_start`. Core scripts use `jave_core_song_start` for rules that apply to every song.
- `on_note_hit` runs for each judged player note. `lane` is 0–3, left to right. `rating` is `"sick"`, `"good"`, `"bad"` or `"miss"`; a missed note and a broken hold both report `"miss"`.
- Because all scripts share globals, a later script's hook replaces an earlier one with the same name.

Keep per-frame work small and avoid file access in `on_update`.

## Mods

```text
mods/color-pulse/
  mod.json
  scripts/color.lua
```

```json
{
  "id": "color-pulse",
  "name": "Color Pulse",
  "version": "1.0.0",
  "author": "You",
  "description": "Pink accent on song start.",
  "enabled": true
}
```

```lua
function on_song_start(id)
  jave_set_accent(255, 90, 190)
end
```

- Mods are found in the repository's `mods/` and in `user://mods/`. Each needs a `mod.json`; `id` defaults to the folder name and `enabled` to `true`.
- The Mods screen toggles a mod with Enter. The choice is stored in `user://config/mods.json` (`{"enabled": {"<mod-id>": true}}`) and overrides `enabled` in `mod.json`.
- A mod may also add songs, charts, stages and weeks; see [Content import](CONTENT_IMPORT.md#mods).
