class_name PlayScene
extends Node2D

signal finished(play: Gameplay)
signal game_over(play: Gameplay)
signal failed(message: String)

enum State { LOADING, PLAYING, DYING, DONE }

var song: SongMeta
var botplay := false
var gameplay: Gameplay
var state := State.LOADING

var _assets: SongAssets
var _death_elapsed := 0.0
var _death_duration := 0.0

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
	gameplay.fail_on_zero = true
	gameplay.note_judged.connect(ModHost.note_hit)
	_assets = SongAssets.new(song)
	_assets.start_loading()


func _process(delta: float) -> void:
	match state:
		State.LOADING:
			if _assets != null and _assets.is_loaded():
				_start()
		State.PLAYING:
			_step(delta)
		State.DYING:
			_step_death(delta)


func _input(event: InputEvent) -> void:
	if not is_dying():
		return
	var touch := event as InputEventScreenTouch
	var key := MenuInput.key_of(event)
	if (touch != null and touch.pressed) or MenuInput.is_confirm(key) or MenuInput.is_back(key):
		get_viewport().set_input_as_handled()
		skip_death()


func is_playing() -> bool:
	return state == State.PLAYING


func is_dying() -> bool:
	return state == State.DYING


func refresh() -> void:
	if state == State.PLAYING:
		_render()


func _start() -> void:
	_assets.finish_loading()
	_stage.setup(song, _assets)
	TextureCache.prune_frames()
	_strumline.setup(Settings.downscroll, Settings.note_speed, song.package_root)
	_hud.setup(song)
	if TouchControls.enabled():
		$Overlay.add_child(TouchControls.make_lanes())
	Log.info("Stage layout applied: %s revision=%d from %s" % [song.stage, JsonRead.integer(song.stage_layout, "revision"), song.stage_config_path])
	if not Conductor.start(_assets.stream):
		_fail("Could not play song audio")
		return
	gameplay.song_end_ms = Conductor.duration_ms if Conductor.duration_ms > 0.0 else gameplay.chart.duration_ms
	Log.info("Song timeline: %s audioEndMs=%f chartEndMs=%f" % [song.id, gameplay.song_end_ms, gameplay.chart.duration_ms])
	ModHost.player_flip = false
	ModHost.song_start(song.id)
	LaneInput.clear()
	state = State.PLAYING
	_render()


func _step(delta: float) -> void:
	gameplay.begin_frame(delta, Conductor.song_time_ms)
	_judge_presses()
	gameplay.end_frame(delta, LaneInput.held_mask)
	_render()
	if gameplay.failed:
		_begin_death()
		return
	if gameplay.is_finished():
		_finish()


func _begin_death() -> void:
	if state != State.PLAYING:
		return
	Conductor.stop()
	LaneInput.clear()
	state = State.DYING
	_death_elapsed = 0.0
	_death_duration = _stage.death_animation_duration()
	_stage.show_death(_death_elapsed, gameplay)


func _step_death(delta: float) -> void:
	_death_elapsed += delta
	_stage.show_death(_death_elapsed, gameplay)
	if _death_elapsed >= _death_duration:
		_finish_game_over()


func skip_death() -> void:
	if is_dying():
		_finish_game_over()


func _finish_game_over() -> void:
	if state != State.DYING:
		return
	state = State.DONE
	game_over.emit(gameplay)


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
