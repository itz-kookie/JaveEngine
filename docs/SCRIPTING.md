# Lua scripting

Jave Engine embeds Lua 5.4.8 when built with `JAVE_ENABLE_LUA=ON`. The core engine stays in C++; Lua is intended for mod reactions, lightweight events, and content-specific behavior.

Scripts load in this order:

1. `scripts/boot.lua`
2. Other `scripts/*.lua`, alphabetically
3. `mods/<enabled-mod>/scripts/*.lua`, alphabetically

All scripts currently share one Lua state. A script error is written to `saves/jave.log` and does not close the game.

## Global API

```lua
jave_log(message)
jave_engine_name()        -- returns "Jave Engine"
jave_set_accent(r, g, b)  -- values 0..255
jave_set_player_flip(bool) -- flip/unflip the player sprite horizontally
```

## Optional callbacks

```lua
function on_update(dt_seconds) end
function on_song_start(song_id) end
function on_note_hit(lane, rating) end
```

Core scripts may also define `jave_core_song_start(song_id)`. Jave calls it before the regular mod callback so engine-wide presentation rules can run for every song. A flip script can use this hook while leaving source sprite frames unchanged; imported characters are not bundled here.

`rating` is one of `sick`, `good`, `bad`, or `miss`. Scripts should avoid file access on each frame. Lua's standard libraries are available in v0.1; only run mods you trust.

## Mod example

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
  "enabled": true
}
```

```lua
function on_song_start(id)
  jave_set_accent(255, 90, 190)
end
```
