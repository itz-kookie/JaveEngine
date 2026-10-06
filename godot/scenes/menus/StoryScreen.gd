class_name StoryScreen
extends MenuScreen

signal week_chosen(week: WeekMeta)

const BAND_COLOR := Color8(249, 202, 89)
const EMPTY_COLOR := Color8(255, 150, 170)
const TRACK_SPACING := 35.0

const IDLE_POSE: Array[StringName] = [&"idle"]

var _tracks: Control
var _previews: Array[AnimatedSprite2D] = []
var _preview_boxes: Array[Rect2] = []
var _assets: Dictionary[String, CharacterAsset] = {}
var _loading: Dictionary[String, int] = {}
var _assets_in_flight: Dictionary[String, CharacterAsset] = {}
var _preview_time := 0.0


func _build() -> void:
	var screen := Ui.SCREEN_SIZE
	Ui.menu_header(self, "STORY MODE", "Choose a week - NORMAL difficulty")
	if Content.weeks.is_empty():
		Ui.text(self, "No weeks with installed songs. See data/weeks.json", Rect2(64.0, 250.0, 900.0, 50.0), 24, EMPTY_COLOR)
		return
	Ui.box(self, Rect2(0.0, 120.0, screen.x, screen.y * 0.37), BAND_COLOR)
	for slot in 3:
		var sprite := AnimatedSprite2D.new()
		sprite.centered = false
		add_child(sprite)
		_previews.append(sprite)
		_preview_boxes.append(Rect2())
	var names := PackedStringArray()
	for week in Content.weeks:
		names.append(week.name)
	build_list(names, screen.y * 0.57, screen.x * 0.46, 78.0)
	for index in Content.weeks.size():
		row(index).set_art(Ui.menu_texture("weeks/%s.png" % Content.weeks[index].id), 62.0, 48.0)
	var heading := FunkinLabel.new()
	heading.position = Vector2(screen.x * 0.58, screen.y * 0.57)
	add_child(heading)
	heading.show_text("TRACKS", screen.x * 0.36, 42.0)
	_tracks = Control.new()
	_tracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tracks)
	_selection_changed()


func _confirm() -> void:
	if selection < Content.weeks.size():
		week_chosen.emit(Content.weeks[selection])


func _selection_changed() -> void:
	var week := Content.weeks[selection]
	_show_tracks(week)
	_show_preview(_first_installed(week))


func _first_installed(week: WeekMeta) -> SongMeta:
	for song_id in week.song_ids:
		var song := Content.find_song(song_id)
		if song != null:
			return song
	return null


func _show_tracks(week: WeekMeta) -> void:
	for child in _tracks.get_children():
		child.queue_free()
	var screen := Ui.SCREEN_SIZE
	var y := screen.y * 0.64
	for song_id in week.song_ids:
		var song := Content.find_song(song_id)
		if song == null:
			continue
		var label := FunkinLabel.new()
		label.position = Vector2(screen.x * 0.58, y)
		_tracks.add_child(label)
		label.show_text(song.title, screen.x * 0.38, 29.0)
		y += TRACK_SPACING


func _show_preview(song: SongMeta) -> void:
	for sprite in _previews:
		sprite.visible = false
	if song == null:
		return
	var screen := Ui.SCREEN_SIZE
	if song.opponent_character != song.girlfriend_character:
		_place_preview(0, song.opponent_visual, screen.x * 0.22, screen.y * 0.30, false)
	if not song.hide_girlfriend:
		_place_preview(1, song.girlfriend_visual, screen.x * 0.49, screen.y * 0.29, false)
	_place_preview(2, song.player_visual, screen.x * 0.75, screen.y * 0.24, true)


func _place_preview(slot: int, visual: String, center: float, height: float, is_player: bool) -> void:
	var asset := _asset_for(visual)
	if asset == null or asset.frames.get_frame_count(&"idle") == 0:
		return
	var screen := Ui.SCREEN_SIZE
	var sprite := _previews[slot]
	_preview_boxes[slot] = Rect2(center - screen.x * 0.12, 130.0 + screen.y * 0.34 - height, screen.x * 0.24, height)
	sprite.sprite_frames = asset.frames
	sprite.animation = &"idle"
	sprite.flip_h = JsonRead.boolean(asset.meta, "flipX", false) != is_player
	sprite.visible = true
	_set_preview_frame(slot)


## The idle restarts every second; each frame is fitted to the box on its own.
func _set_preview_frame(slot: int) -> void:
	var sprite := _previews[slot]
	var count := sprite.sprite_frames.get_frame_count(&"idle")
	var index := int(_preview_time * sprite.sprite_frames.get_animation_speed(&"idle"))
	sprite.frame = index % count if sprite.sprite_frames.get_animation_loop(&"idle") else mini(index, count - 1)
	var source := sprite.sprite_frames.get_frame_texture(&"idle", sprite.frame).get_size()
	var box := _preview_boxes[slot]
	var fit := minf(box.size.x / source.x, box.size.y / source.y)
	sprite.scale = Vector2(fit, fit)
	sprite.position = Vector2(box.position.x + (box.size.x - source.x * fit) * 0.5, box.end.y - source.y * fit)


func _process(delta: float) -> void:
	super(delta)
	_preview_time = fmod(_preview_time + delta, 1.0)
	for slot in _previews.size():
		if _previews[slot].visible:
			_set_preview_frame(slot)
	if not _loading.is_empty():
		_collect_loaded()


## Null until the idle frames have loaded on a worker; the preview is redrawn when they arrive.
func _asset_for(visual: String) -> CharacterAsset:
	if visual.is_empty():
		return null
	if _assets.has(visual):
		return _assets[visual]
	if not _loading.has(visual):
		var asset := CharacterAsset.new(visual, IDLE_POSE)
		_assets_in_flight[visual] = asset
		_loading[visual] = WorkerThreadPool.add_task(asset.load_from_disk, false, "Load story preview")
	return null


func _collect_loaded() -> void:
	var arrived := false
	for visual: String in _loading.keys():
		if not WorkerThreadPool.is_task_completed(_loading[visual]):
			continue
		_finish(visual)
		arrived = true
	if arrived and not Content.weeks.is_empty():
		_show_preview(_first_installed(Content.weeks[selection]))


func _finish(visual: String) -> void:
	WorkerThreadPool.wait_for_task_completion(_loading[visual])
	_loading.erase(visual)
	var asset: CharacterAsset = _assets_in_flight[visual]
	_assets_in_flight.erase(visual)
	asset.build_frames()
	_assets[visual] = asset


func _exit_tree() -> void:
	for visual: String in _loading.keys():
		WorkerThreadPool.wait_for_task_completion(_loading[visual])
	_loading.clear()
	_assets_in_flight.clear()
