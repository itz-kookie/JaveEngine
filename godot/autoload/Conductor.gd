extends Node

const MUSIC_BUS := &"Music"
const SNAP_THRESHOLD_SECONDS := 0.05
const CORRECTION_RATE := 0.1

var song_time_ms := 0.0
var duration_ms := 0.0
var running := false
var paused := false

var _player: AudioStreamPlayer
var _estimate := 0.0
var _resync := false
var _last_update_usec := 0


func _ready() -> void:
	process_priority = -100
	_ensure_music_bus()
	_player = AudioStreamPlayer.new()
	_player.bus = MUSIC_BUS
	add_child(_player)


func start(stream: AudioStream, volume: float) -> bool:
	stop()
	_estimate = 0.0
	song_time_ms = Settings.audio_offset_ms
	duration_ms = stream.get_length() * 1000.0 if stream != null else 0.0
	running = true
	_last_update_usec = Time.get_ticks_usec()
	if stream == null:
		return false
	_player.stream = stream
	_player.volume_db = linear_to_db(volume)
	_player.play()
	return true


func stop() -> void:
	_player.stop()
	_player.stream = null
	running = false
	paused = false


func pause() -> void:
	paused = true
	_player.stream_paused = true


func resume() -> void:
	paused = false
	_player.stream_paused = false
	_resync = true
	_last_update_usec = Time.get_ticks_usec()


## Song time at this instant, extrapolated from the last frame's estimate.
func now_ms() -> float:
	if not running or paused:
		return song_time_ms
	return song_time_ms + (Time.get_ticks_usec() - _last_update_usec) / 1000.0


func beat_ms(bpm: float) -> float:
	return 60000.0 / maxf(1.0, bpm)


func _process(delta: float) -> void:
	if not running or paused:
		return
	_last_update_usec = Time.get_ticks_usec()
	_advance_estimate(delta)
	song_time_ms = _estimate * 1000.0 + Settings.audio_offset_ms


func _advance_estimate(delta: float) -> void:
	if not _player.playing:
		_estimate += delta
		return
	var raw := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	if _resync:
		_resync = false
		_estimate = raw
		return
	var previous := _estimate
	_estimate += delta
	var error := raw - _estimate
	var target := raw if absf(error) > SNAP_THRESHOLD_SECONDS else _estimate + error * CORRECTION_RATE
	# When the audio position lags, hold the clock instead of stepping it backwards.
	_estimate = maxf(previous, target)


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, MUSIC_BUS)
	AudioServer.set_bus_send(index, &"Master")


func _exit_tree() -> void:
	stop()
