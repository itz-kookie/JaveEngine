-- Imported sprite frames stay in their original atlas orientation.
-- Character metadata and player role determine facing; this script supplies no extra mirror.
jave_set_player_flip(false)

function jave_core_song_start(song_id)
  jave_set_player_flip(false)
  jave_log("Source character facing applied: " .. song_id)
end
