class_name StoryScreen
extends MenuScreen

signal week_chosen(week: WeekMeta)

const BAND_COLOR := Color8(249, 202, 89)
const EMPTY_COLOR := Color8(255, 150, 170)
const TRACK_SPACING := 35.0

var _tracks: Control
var _previews: Array[AnimatedSprite2D] = []
var _assets: Dictionary[String, CharacterAsset] = {}


func _build() -> void:
	var screen := Ui.SCREEN_SIZE
	Ui.menu_header(self, "STORY MODE", "Choose a week - NORMAL difficulty")
	if Content.weeks.is_empty():
		Ui.text(self, "No weeks found. See data/weeks.json", Rect2(64.0, 250.0, 900.0, 50.0), 24, EMPTY_COLOR)
		return
	Ui.box(self, Rect2(0.0, 120.0, screen.x, screen.y * 0.37), BAND_COLOR)
	for slot in 3:
		var sprite := AnimatedSprite2D.new()
		sprite.centered = false
		add_child(sprite)
		_previews.append(sprite)
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
	_show_preview(Content.find_song(week.song_ids[0]))


func _show_tracks(week: WeekMeta) -> void:
	for child in _tracks.get_children():
		child.queue_free()
	var screen := Ui.SCREEN_SIZE
	var y := screen.y * 0.64
	for song_id in week.song_ids:
		var song := Content.find_song(song_id)
		var label := FunkinLabel.new()
		label.position = Vector2(screen.x * 0.58, y)
		_tracks.add_child(label)
		label.show_text(song.title if song != null else song_id, screen.x * 0.38, 29.0)
		y += TRACK_SPACING


func _show_preview(song: SongMeta) -> void:
	for sprite in _previews:
		sprite.visible = false
	if song == null:
		return
	var screen := Ui.SCREEN_SIZE
	if song.opponent_character != song.girlfriend_character:
		_place_preview(_previews[0], song.opponent_visual, screen.x * 0.22, screen.y * 0.30, false)
	if not song.hide_girlfriend:
		_place_preview(_previews[1], song.girlfriend_visual, screen.x * 0.49, screen.y * 0.29, false)
	_place_preview(_previews[2], song.player_visual, screen.x * 0.75, screen.y * 0.24, true)


func _place_preview(sprite: AnimatedSprite2D, visual: String, center: float, height: float, is_player: bool) -> void:
	var asset := _asset_for(visual)
	if asset == null:
		return
	var texture := asset.frames.get_frame_texture(&"idle", 0) if asset.frames.get_frame_count(&"idle") > 0 else null
	if texture == null:
		return
	var screen := Ui.SCREEN_SIZE
	var box := Rect2(center - screen.x * 0.12, 130.0 + screen.y * 0.34 - height, screen.x * 0.24, height)
	var source := texture.get_size()
	var fit := minf(box.size.x / source.x, box.size.y / source.y)
	sprite.sprite_frames = asset.frames
	sprite.flip_h = JsonRead.boolean(asset.meta, "flipX", false) != is_player
	sprite.scale = Vector2(fit, fit)
	sprite.position = Vector2(box.position.x + (box.size.x - source.x * fit) * 0.5, box.end.y - source.y * fit)
	sprite.visible = true
	sprite.play(&"idle")


func _asset_for(visual: String) -> CharacterAsset:
	if visual.is_empty():
		return null
	if not _assets.has(visual):
		var asset := CharacterAsset.new(visual)
		asset.load_from_disk()
		asset.build_frames()
		_assets[visual] = asset
	return _assets[visual]
