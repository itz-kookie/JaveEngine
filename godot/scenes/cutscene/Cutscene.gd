class_name Cutscene
extends Control

## Reason is one of &"cancel", &"skip", &"ended", &"timeout" or &"failed".
signal finished(reason: StringName)

@export var start_timeout_s := 15.0

var file_name := ""

var _waited_s := 0.0
var _done := false

@onready var _frame: AspectRatioContainer = $Frame
@onready var _player: VideoStreamPlayer = $Frame/Player


func _ready() -> void:
	_player.finished.connect(_on_player_finished)


## Must be called once the cutscene is in the tree; false when the file cannot be opened at all.
func open(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var stream := VideoStreamTheora.new()
	stream.file = path
	_player.stream = stream
	_player.volume = Settings.master_volume
	_player.play()
	if not _player.is_playing():
		_player.stream = null
		return false
	file_name = path.get_file()
	return true


## Only watches for the first frame; once playback starts the player's finished signal ends the cutscene.
func _process(delta: float) -> void:
	if not _player.is_playing():
		_finish(&"failed")
	elif _player.stream_position > 0.0:
		set_process(false)
		_fit_frame()
		Log.info("Cutscene playback started: " + file_name)
	else:
		# A stream that never produces a frame (corrupt file, missing decoder) is abandoned.
		_waited_s += delta
		if _waited_s >= start_timeout_s:
			_finish(&"timeout")


func _fit_frame() -> void:
	var texture := _player.get_video_texture()
	if texture != null and texture.get_height() > 0:
		_frame.ratio = float(texture.get_width()) / texture.get_height()


func _unhandled_input(event: InputEvent) -> void:
	var key := MenuInput.key_of(event)
	if MenuInput.is_back(key):
		get_viewport().set_input_as_handled()
		_finish(&"cancel")
	elif MenuInput.is_confirm(key) or key == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_finish(&"skip")


func _on_player_finished() -> void:
	_finish(&"ended")


func _finish(reason: StringName) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_player.stop()
	match reason:
		&"cancel":
			Log.info("Cutscene cancelled: " + file_name)
		&"skip":
			Log.info("Cutscene skipped: " + file_name)
		&"ended":
			Log.info("Cutscene playback ended: " + file_name)
		_:
			Log.info("Cutscene playback error (%s): %s" % [reason, file_name])
	finished.emit(reason)
