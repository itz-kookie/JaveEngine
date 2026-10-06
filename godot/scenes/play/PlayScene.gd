class_name PlayScene
extends Node2D

signal finished(play: Gameplay)
signal failed(message: String)

enum State { LOADING, PLAYING, DONE }

var song: SongMeta
var botplay := false
var gameplay: Gameplay
var state := State.LOADING

var _assets: SongAssets

@onready var _stage: PlayStage = $Stage
@onready var _strumline: Strumline = $Overlay/Strumline
@onready var _hud: PlayHud = $Overlay/HUD


func _ready() -> void:
	Content.reload_stage(song)
	var chart := Content.load_chart(song)
	if chart == null:
		_fail(ChartData.load_error)
		return
	gameplay = Gameplay.new(chart, song)
	gameplay.botplay = botplay
	_assets = SongAssets.new(song)
	_assets.start_loading()


func _process(delta: float) -> void:
	match state:
		State.LOADING:
			if _assets != null and _assets.is_loaded():
				_start()
		State.PLAYING:
			_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.PLAYING and event.is_action_pressed(LaneInput.TOGGLE_BOTPLAY):
		gameplay.botplay = not gameplay.botplay
		Log.info("Botplay " + ("enabled" if gameplay.botplay else "disabled"))
		get_viewport().set_input_as_handled()


func _start() -> void:
	_assets.finish_loading()
	_stage.setup(song, _assets)
	_strumline.setup(Settings.downscroll, Settings.note_speed)
	_hud.setup(song)
	Log.info("Stage layout applied: %s revision=%d from %s" % [song.stage, JsonRead.integer(song.stage_layout, "revision"), song.stage_config_path])
	if not Conductor.start(_assets.stream, Settings.master_volume):
		_fail("Could not play song audio")
		return
	gameplay.song_end_ms = Conductor.duration_ms if Conductor.duration_ms > 0.0 else gameplay.chart.duration_ms
	Log.info("Song timeline: %s audioEndMs=%f chartEndMs=%f" % [song.id, gameplay.song_end_ms, gameplay.chart.duration_ms])
	LaneInput.clear()
	state = State.PLAYING
	_render()


func _step(delta: float) -> void:
	gameplay.begin_frame(delta, Conductor.song_time_ms)
	_judge_presses()
	gameplay.end_frame(delta, LaneInput.held_mask)
	_render()
	if gameplay.is_finished():
		_finish()


func _judge_presses() -> void:
	while LaneInput.has_press():
		if not gameplay.botplay:
			gameplay.judge_lane(LaneInput.press_lane(), LaneInput.press_time_ms())
		LaneInput.consume_press()


func _render() -> void:
	_stage.update_view(gameplay)
	_strumline.render(gameplay, LaneInput.held_mask)
	_hud.refresh(gameplay)


func _finish() -> void:
	Conductor.stop()
	state = State.DONE
	Log.info("Song finished: %s score=%d sick=%d good=%d bad=%d miss=%d maxCombo=%d" % [
		song.id, gameplay.score, gameplay.sick_count, gameplay.good_count, gameplay.bad_count,
		gameplay.miss_count, gameplay.max_combo])
	finished.emit(gameplay)


func _fail(message: String) -> void:
	Conductor.stop()
	state = State.DONE
	Log.info("Could not start song: " + message)
	failed.emit(message)


func _exit_tree() -> void:
	if _assets != null and state == State.LOADING:
		_assets.finish_loading()
	if state == State.PLAYING:
		Conductor.stop()
