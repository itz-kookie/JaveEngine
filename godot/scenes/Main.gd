extends Node

enum Screen { TITLE, STORY, FREEPLAY, MODS, OPTIONS, CREDITS, PLAY, PAUSED, RESULTS, CHART_EDITOR, CUTSCENE }

const PLAY_SCENE: PackedScene = preload("res://scenes/play/PlayScene.tscn")
const CHART_EDITOR_SCENE: PackedScene = preload("res://scenes/editor/ChartEditor.tscn")
const CUTSCENE_SCENE: PackedScene = preload("res://scenes/cutscene/Cutscene.tscn")
const TITLE_DESTINATIONS: Array[Screen] = [Screen.STORY, Screen.FREEPLAY, Screen.MODS, Screen.OPTIONS, Screen.CREDITS]

var screen := Screen.TITLE
var playing_story := false
var story_queue: Array[SongMeta] = []
var story_position := 0
var last_result: Gameplay

var _menu: MenuScreen
var _play: PlayScene
var _editor: ChartEditor
var _cutscene: Cutscene
var _cutscene_song: SongMeta
var _cutscene_outro := false
var _default_botplay := false
var _shown_fps := -1
var _touch_back: CanvasLayer

@onready var _backdrop: MenuBackdrop = $Backdrop
@onready var _pause: PauseMenu = $PauseMenu
@onready var _editor_layer: CanvasLayer = $EditorLayer
@onready var _fps_label: Label = $FpsLayer/Fps


func _ready() -> void:
	_default_botplay = OS.get_cmdline_user_args().has("--botplay")
	Settings.apply_window_mode()
	_setup_touch()
	_pause.resume_requested.connect(resume_song)
	_pause.restart_requested.connect(restart_song)
	_pause.botplay_toggled.connect(toggle_botplay)
	switch_screen(Screen.TITLE)


func _setup_touch() -> void:
	if not TouchControls.enabled():
		return
	TouchControls.prepare()
	_touch_back = TouchControls.make_back_button(_pause.layer + 1)
	add_child(_touch_back)


func screen_name() -> String:
	return Screen.keys()[screen]


func current_play() -> PlayScene:
	return _play


func current_editor() -> ChartEditor:
	return _editor


func current_cutscene() -> Cutscene:
	return _cutscene


func _process(delta: float) -> void:
	if _touch_back != null:
		_touch_back.visible = screen != Screen.TITLE
	if screen != Screen.PAUSED and screen != Screen.CHART_EDITOR and screen != Screen.CUTSCENE:
		ModHost.update(delta)
	_fps_label.visible = Settings.show_fps
	var fps := int(Engine.get_frames_per_second())
	if _fps_label.visible and fps != _shown_fps:
		_shown_fps = fps
		_fps_label.text = "%d FPS" % fps


func switch_screen(next: Screen) -> void:
	_close_play()
	_close_menu()
	_close_cutscene()
	screen = next
	_menu = _create_menu(next)
	_backdrop.visible = true
	_backdrop.show_style(_backdrop_art(next))
	add_child(_menu)
	move_child(_menu, _backdrop.get_index() + 1)


func start_song(song: SongMeta, botplay := _default_botplay) -> void:
	_close_play()
	_close_menu()
	_close_cutscene()
	_backdrop.visible = false
	var play: PlayScene = PLAY_SCENE.instantiate()
	play.song = song
	play.botplay = botplay
	play.finished.connect(_on_song_finished.bind(play.get_instance_id()), CONNECT_DEFERRED)
	play.failed.connect(_on_song_failed.bind(play.get_instance_id()), CONNECT_DEFERRED)
	_play = play
	screen = Screen.PLAY
	add_child(play)
	move_child(play, 0)


func start_week(week: WeekMeta) -> void:
	story_queue.clear()
	for song_id in week.song_ids:
		var song := Content.find_song(song_id)
		if song != null:
			story_queue.append(song)
	if story_queue.is_empty():
		return
	playing_story = true
	story_position = 0
	start_story_song(story_queue[0])


func start_story_song(song: SongMeta) -> void:
	if not _start_cutscene(song, false):
		start_song(song)


func pause_song() -> void:
	Conductor.pause()
	_play.process_mode = Node.PROCESS_MODE_DISABLED
	_pause.open(_play.song.title, _play.gameplay.botplay)
	screen = Screen.PAUSED
	Log.info("Game paused: " + _play.song.id)


func resume_song() -> void:
	_pause.close()
	LaneInput.discard_presses()
	_play.process_mode = Node.PROCESS_MODE_INHERIT
	Conductor.resume()
	screen = Screen.PLAY
	Log.info("Game resumed: " + _play.song.id)


func restart_song() -> void:
	var song := _play.song
	var botplay := _play.gameplay.botplay
	Log.info("Song restarted from pause menu: " + song.id)
	_pause.close()
	start_song(song, botplay)


func open_chart_editor() -> void:
	Conductor.pause()
	_play.process_mode = Node.PROCESS_MODE_DISABLED
	_editor = CHART_EDITOR_SCENE.instantiate()
	_editor.setup(_play.song, _play.gameplay.chart, _play.gameplay.song_time_ms)
	_editor.saved.connect(_play.gameplay.replace_chart)
	_editor.close_requested.connect(close_chart_editor)
	_editor_layer.add_child(_editor)
	screen = Screen.CHART_EDITOR
	Log.info("Chart editor opened: " + _play.song.id)


## Unsaved edits are dropped; a save has already handed its chart to the running song.
func close_chart_editor() -> void:
	Log.info("Chart editor closed %s%s" % ["without saving: " if _editor.state.dirty else "after save: ", _play.song.id])
	_close_editor()
	LaneInput.discard_presses()
	_play.process_mode = Node.PROCESS_MODE_INHERIT
	Conductor.resume()
	screen = Screen.PLAY


func toggle_botplay() -> void:
	var gameplay := _play.gameplay
	gameplay.botplay = not gameplay.botplay
	_pause.set_botplay(gameplay.botplay)
	_play.refresh()
	Log.info("Botplay " + ("enabled" if gameplay.botplay else "disabled"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		TouchControls.send_key(KEY_ESCAPE)


func _unhandled_input(event: InputEvent) -> void:
	if screen != Screen.PLAY:
		return
	var key := MenuInput.key_of(event)
	if (key == KEY_7 or key == KEY_KP_7) and _play.is_playing():
		get_viewport().set_input_as_handled()
		open_chart_editor()
	elif MenuInput.is_confirm(key) and _play.is_playing():
		get_viewport().set_input_as_handled()
		pause_song()
	elif MenuInput.is_back(key):
		get_viewport().set_input_as_handled()
		_leave_song()


func _leave_song() -> void:
	var destination := Screen.STORY if playing_story else Screen.FREEPLAY
	_end_story()
	switch_screen(destination)


func _end_story() -> void:
	playing_story = false
	story_queue.clear()


## Song signals arrive deferred, so one from a song the player already left or restarted is ignored.
func _is_current_play(play_id: int) -> bool:
	return _play != null and _play.get_instance_id() == play_id


func _on_song_finished(result: Gameplay, play_id: int) -> void:
	if not _is_current_play(play_id):
		return
	last_result = result
	if not _start_cutscene(_play.song, true):
		switch_screen(Screen.RESULTS)


## Cutscenes only play in story mode; false when the song has none or its video cannot be opened.
func _start_cutscene(song: SongMeta, outro: bool) -> bool:
	if not playing_story:
		return false
	var path := Content.cutscene_path(song.id, outro)
	if path.is_empty():
		return false
	Conductor.stop()
	_close_play()
	_close_menu()
	_close_cutscene()
	_backdrop.visible = false
	var cutscene: Cutscene = CUTSCENE_SCENE.instantiate()
	add_child(cutscene)
	if not cutscene.open(path):
		Log.info("Cutscene unavailable: " + path)
		remove_child(cutscene)
		cutscene.queue_free()
		return false
	cutscene.finished.connect(_on_cutscene_finished.bind(cutscene.get_instance_id()), CONNECT_DEFERRED)
	_cutscene = cutscene
	_cutscene_song = song
	_cutscene_outro = outro
	screen = Screen.CUTSCENE
	Log.info("Cutscene opened: %s %s %s" % [cutscene.file_name, "after" if outro else "before", song.id])
	return true


func _on_cutscene_finished(reason: StringName, cutscene_id: int) -> void:
	if _cutscene == null or _cutscene.get_instance_id() != cutscene_id:
		return
	_close_cutscene()
	# Drop lane presses made during the video so they cannot be judged in the next song.
	LaneInput.clear()
	if reason == &"cancel":
		_end_story()
		switch_screen(Screen.STORY)
	elif _cutscene_outro:
		switch_screen(Screen.RESULTS)
	else:
		start_song(_cutscene_song)


func _on_song_failed(_message: String, play_id: int) -> void:
	if _is_current_play(play_id):
		_leave_song()


func _continue_from_results() -> void:
	if playing_story and story_position + 1 < story_queue.size():
		story_position += 1
		start_story_song(story_queue[story_position])
	else:
		_leave_song()


func _on_title_chosen(index: int) -> void:
	if index < TITLE_DESTINATIONS.size():
		switch_screen(TITLE_DESTINATIONS[index])
	else:
		get_tree().quit()


func _on_freeplay_song(song: SongMeta) -> void:
	_end_story()
	start_song(song)


func _results_action() -> String:
	if not playing_story:
		return "Enter Continue"
	return "Enter Next Song" if story_position + 1 < story_queue.size() else "Enter Finish Week"


func _create_menu(next: Screen) -> MenuScreen:
	match next:
		Screen.TITLE:
			var title := TitleScreen.new()
			title.chosen.connect(_on_title_chosen)
			title.back_requested.connect(get_tree().quit)
			return title
		Screen.STORY:
			var story := StoryScreen.new()
			story.week_chosen.connect(start_week)
			return _with_back(story)
		Screen.FREEPLAY:
			var freeplay := FreeplayScreen.new()
			freeplay.song_chosen.connect(_on_freeplay_song)
			return _with_back(freeplay)
		Screen.MODS:
			return _with_back(ModsScreen.new())
		Screen.OPTIONS:
			return _with_back(OptionsScreen.new())
		Screen.RESULTS:
			var results := ResultsScreen.new()
			results.result = last_result
			results.action_text = _results_action()
			results.continue_requested.connect(_continue_from_results)
			return _with_back(results)
	return _with_back(CreditsScreen.new())


func _with_back(menu: MenuScreen) -> MenuScreen:
	menu.back_requested.connect(switch_screen.bind(Screen.TITLE))
	return menu


static func _backdrop_art(next: Screen) -> String:
	match next:
		Screen.TITLE, Screen.STORY:
			return "menuBG.png"
		Screen.FREEPLAY:
			return "menuPurple.png"
		Screen.RESULTS:
			return ""
	return "menuCool.png"


func _close_menu() -> void:
	if _menu == null:
		return
	remove_child(_menu)
	_menu.queue_free()
	_menu = null


## Detaches immediately so the old song's exit stops the clock before a new song can start it.
func _close_play() -> void:
	_pause.close()
	_close_editor()
	if _play == null:
		return
	remove_child(_play)
	_play.queue_free()
	_play = null


func _close_cutscene() -> void:
	if _cutscene == null:
		return
	remove_child(_cutscene)
	_cutscene.queue_free()
	_cutscene = null


func _close_editor() -> void:
	if _editor == null:
		return
	_editor_layer.remove_child(_editor)
	_editor.queue_free()
	_editor = null
