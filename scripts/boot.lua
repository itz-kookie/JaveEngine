-- Jave Engine sample startup script (MIT/CC0-friendly example).
jave_log("boot.lua loaded in " .. jave_engine_name())

local pulse = 0

function on_update(dt)
  pulse = pulse + dt
  if pulse > 8 then
    pulse = 0
    jave_log("Lua is alive")
  end
end

function on_song_start(song_id)
  jave_log("Starting song from Lua: " .. song_id)
end

function on_note_hit(lane, rating)
  -- A mod can react here. Keep expensive work out of per-frame callbacks.
end

