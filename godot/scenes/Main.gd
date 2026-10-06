extends Node

enum Screen { PLAY }

const PLAY_SCENE: PackedScene = preload("res://scenes/play/PlayScene.tscn")
const START_SONG := "neon-steps"

var screen := Screen.PLAY

var _current: Node
var _botplay := false
var _shown_fps := -1

@onready var _fps_label: Label = $FpsLayer/Fps


func _ready() -> void:
	_botplay = OS.get_cmdline_user_args().has("--botplay")
	if Settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_fps_label.visible = Settings.show_fps
	start_song(START_SONG)


func _process(_delta: float) -> void:
	var fps := int(Engine.get_frames_per_second())
	if _fps_label.visible and fps != _shown_fps:
		_shown_fps = fps
		_fps_label.text = "%d FPS" % fps


func start_song(song_id: String) -> void:
	var song := Content.find_song(song_id)
	if song == null:
		Log.info("Could not start song: unknown song " + song_id)
		return
	var play: PlayScene = PLAY_SCENE.instantiate()
	play.song = song
	play.botplay = _botplay
	play.finished.connect(_on_song_finished)
	_switch_to(Screen.PLAY, play)


func _switch_to(next: Screen, node: Node) -> void:
	if _current != null:
		_current.queue_free()
	screen = next
	_current = node
	add_child(node)
	move_child(node, 0)


func _on_song_finished(play: Gameplay) -> void:
	_botplay = play.botplay
	start_song.call_deferred(play.song.id)
