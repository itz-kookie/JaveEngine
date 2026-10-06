extends Node

enum Screen { TITLE, STORY, FREEPLAY, MODS, OPTIONS, CREDITS, PLAY, PAUSED, RESULTS }

const PLAY_SCENE: PackedScene = preload("res://scenes/play/PlayScene.tscn")
const TITLE_DESTINATIONS: Array[Screen] = [Screen.STORY, Screen.FREEPLAY, Screen.MODS, Screen.OPTIONS, Screen.CREDITS]

var screen := Screen.TITLE
var playing_story := false
var story_queue: Array[SongMeta] = []
var story_position := 0
var last_result: Gameplay

var _menu: MenuScreen
var _play: PlayScene
var _default_botplay := false
var _shown_fps := -1

@onready var _backdrop: MenuBackdrop = $Backdrop
@onready var _pause: PauseMenu = $PauseMenu
@onready var _fps_label: Label = $FpsLayer/Fps


func _ready() -> void:
	_default_botplay = OS.get_cmdline_user_args().has("--botplay")
	Settings.apply_window_mode()
	_pause.resume_requested.connect(resume_song)
	_pause.restart_requested.connect(restart_song)
	_pause.botplay_toggled.connect(toggle_botplay)
	switch_screen(Screen.TITLE)


func screen_name() -> String:
	return Screen.keys()[screen]


func current_play() -> PlayScene:
	return _play


func _process(_delta: float) -> void:
	_fps_label.visible = Settings.show_fps
	var fps := int(Engine.get_frames_per_second())
	if _fps_label.visible and fps != _shown_fps:
		_shown_fps = fps
		_fps_label.text = "%d FPS" % fps


func switch_screen(next: Screen) -> void:
	_close_play()
	_close_menu()
	screen = next
	_menu = _create_menu(next)
	_backdrop.visible = true
	_backdrop.show_style(_backdrop_art(next))
	add_child(_menu)
	move_child(_menu, _backdrop.get_index() + 1)


func start_song(song: SongMeta, botplay := _default_botplay) -> void:
	_close_play()
	_close_menu()
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
	start_song(story_queue[0])


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


func toggle_botplay() -> void:
	var gameplay := _play.gameplay
	gameplay.botplay = not gameplay.botplay
	_pause.set_botplay(gameplay.botplay)
	_play.refresh()
	Log.info("Botplay " + ("enabled" if gameplay.botplay else "disabled"))


func _unhandled_input(event: InputEvent) -> void:
	if screen != Screen.PLAY:
		return
	var key := MenuInput.key_of(event)
	if MenuInput.is_confirm(key) and _play.is_playing():
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
	if _is_current_play(play_id):
		last_result = result
		switch_screen(Screen.RESULTS)


func _on_song_failed(_message: String, play_id: int) -> void:
	if _is_current_play(play_id):
		_leave_song()


func _continue_from_results() -> void:
	if playing_story and story_position + 1 < story_queue.size():
		story_position += 1
		start_song(story_queue[story_position])
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
	if _play == null:
		return
	remove_child(_play)
	_play.queue_free()
	_play = null
