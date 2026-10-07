class_name Strumline
extends Node2D

const SCREEN_HEIGHT := 720.0
const LANE_WIDTH := 112.0
const GROUP_WIDTH := LANE_WIDTH * 4.0
const OPPONENT_X := 32.0
const PLAYER_X := 1280.0 - OPPONENT_X - GROUP_WIDTH
const UPSCROLL_RECEPTOR_Y := 90.0
const DOWNSCROLL_RECEPTOR_Y := SCREEN_HEIGHT - 135.0
const CULL_MARGIN := 100.0
const PIXELS_PER_MS := 0.36
const HEAD_SIZE := LANE_WIDTH * 0.98
const CONFIRM_SIZE := LANE_WIDTH * 1.34
const HOLD_WIDTH := LANE_WIDTH * 0.24
const HOLD_END_SIZE := LANE_WIDTH * 0.34
const LANE_NAMES: PackedStringArray = ["left", "down", "up", "right"]
const IMPORTED_NOTES := "assets/imported/notes"
const DEMO_NOTES := "assets/demo/notes"

var downscroll := false
var note_speed := 1.0
var receptor_y := UPSCROLL_RECEPTOR_Y

var _receptor_textures: Array[Texture2D] = []
var _press_textures: Array[Texture2D] = []
var _confirm_textures: Array[Texture2D] = []
var _note_textures: Array[Texture2D] = []
var _hold_textures: Array[Texture2D] = []
var _hold_end_textures: Array[Texture2D] = []

var _opponent_receptors: Array[Sprite2D] = []
var _player_receptors: Array[Sprite2D] = []
var _tails: SpritePool
var _ends: SpritePool
var _heads: SpritePool


func setup(scroll_down: bool, speed: float, package_root := "") -> void:
	downscroll = scroll_down
	note_speed = speed
	receptor_y = DOWNSCROLL_RECEPTOR_Y if downscroll else UPSCROLL_RECEPTOR_Y
	var dirs := note_dirs(package_root)
	_receptor_textures = _lane_textures(dirs, "receptor")
	_press_textures = _lane_textures(dirs, "press")
	_confirm_textures = _lane_textures(dirs, "confirm")
	_note_textures = _lane_textures(dirs, "note")
	_hold_textures = _lane_textures(dirs, "hold")
	_hold_end_textures = _lane_textures(dirs, "hold_end")
	_opponent_receptors = _make_receptors()
	_player_receptors = _make_receptors()
	_tails = SpritePool.new(self)
	_ends = SpritePool.new(self)
	_heads = SpritePool.new(self)


static func note_image_path(kind: String, lane: int, package_root := "") -> String:
	return pick_note_image(note_dirs(package_root), kind, lane)


## Where note art is looked for, best first: the song's mod, user://content, the base content, then the demo arrows.
static func note_dirs(package_root: String) -> PackedStringArray:
	var dirs := PackedStringArray()
	if not package_root.is_empty() and package_root != Paths.CONTENT_ROOT:
		dirs.append(package_root.path_join(IMPORTED_NOTES))
	dirs.append(Paths.user_mirror(Paths.content(IMPORTED_NOTES)))
	dirs.append(Paths.content(IMPORTED_NOTES))
	dirs.append(Paths.content(DEMO_NOTES))
	return dirs


## The first folder holding the file wins, and the last folder is the fallback. Chosen per file, so a partial set still draws every piece.
static func pick_note_image(dirs: PackedStringArray, kind: String, lane: int) -> String:
	var file_name := "%s_%s.png" % [kind, LANE_NAMES[clampi(lane, 0, 3)]]
	for index in dirs.size() - 1:
		var candidate := dirs[index].path_join(file_name)
		if FileAccess.file_exists(candidate):
			return candidate
	return dirs[dirs.size() - 1].path_join(file_name)


static func _lane_textures(dirs: PackedStringArray, kind: String) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for lane in 4:
		textures.append(TextureCache.get_texture(pick_note_image(dirs, kind, lane)))
	return textures


func _make_receptors() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	for lane in 4:
		var sprite := Sprite2D.new()
		add_child(sprite)
		sprites.append(sprite)
	return sprites


## Song-time spans that can appear on screen ahead of and behind the receptors.
func visible_span_ms() -> Vector2:
	var pixels_per_ms := PIXELS_PER_MS * note_speed
	var toward_bottom := SCREEN_HEIGHT + CULL_MARGIN - receptor_y
	var toward_top := receptor_y + CULL_MARGIN
	var ahead := toward_top if downscroll else toward_bottom
	var behind := toward_bottom if downscroll else toward_top
	return Vector2(ahead / pixels_per_ms + 1.0, behind / pixels_per_ms + 1.0)


func render(play: Gameplay, held_mask: int) -> void:
	_render_receptors(play, held_mask)
	_render_notes(play)


func _render_receptors(play: Gameplay, held_mask: int) -> void:
	for lane in 4:
		var opponent_confirmed := play.opponent_flash[lane] > 0.0
		var player_confirmed := play.player_flash[lane] > 0.0
		var held := (held_mask >> lane) & 1 != 0
		var opponent_texture := _confirm_textures[lane] if opponent_confirmed else _receptor_textures[lane]
		var player_texture := _confirm_textures[lane] if player_confirmed else (_press_textures[lane] if held else _receptor_textures[lane])
		_place_receptor(_opponent_receptors[lane], opponent_texture, OPPONENT_X + (lane + 0.5) * LANE_WIDTH, CONFIRM_SIZE if opponent_confirmed else HEAD_SIZE)
		_place_receptor(_player_receptors[lane], player_texture, PLAYER_X + (lane + 0.5) * LANE_WIDTH, CONFIRM_SIZE if player_confirmed else HEAD_SIZE)


func _place_receptor(sprite: Sprite2D, texture: Texture2D, center_x: float, size: float) -> void:
	sprite.texture = texture
	SpritePool.fit(sprite, Rect2(center_x - size * 0.5, receptor_y - size * 0.5, size, size))


func is_note_on_screen(play: Gameplay, index: int) -> bool:
	if play.chart.has_flag(index, ChartData.JUDGED):
		return false
	var y := _head_y(play, index)
	return y >= -CULL_MARGIN and y <= SCREEN_HEIGHT + CULL_MARGIN


func _head_y(play: Gameplay, index: int) -> float:
	var now := play.song_time_ms
	var start := now if play.chart.has_flag(index, ChartData.HEAD_HIT) else play.chart.times[index]
	var distance := (start - now) * PIXELS_PER_MS * note_speed
	return receptor_y - distance if downscroll else receptor_y + distance


func _render_notes(play: Gameplay) -> void:
	var chart := play.chart
	var span := visible_span_ms()
	play.cursors.advance_visible(chart, play.song_time_ms, span.x, span.y)
	_tails.begin()
	_ends.begin()
	_heads.begin()
	for index in range(play.cursors.first_visible, play.cursors.last_visible):
		if is_note_on_screen(play, index):
			_render_note(play, index)
	_tails.end()
	_ends.end()
	_heads.end()


func _render_note(play: Gameplay, index: int) -> void:
	var chart := play.chart
	var lane := chart.lanes[index]
	var head_hit := chart.has_flag(index, ChartData.HEAD_HIT)
	var y := _head_y(play, index)
	var center_x := (PLAYER_X if chart.is_player(index) else OPPONENT_X) + (lane + 0.5) * LANE_WIDTH
	if chart.lengths[index] > 0.0:
		var start := play.song_time_ms if head_hit else chart.times[index]
		var sustain := maxf(0.0, chart.times[index] + chart.lengths[index] - start) * PIXELS_PER_MS * note_speed
		if sustain > 0.0:
			_render_hold(lane, center_x, y, sustain)
	if not head_hit:
		var head := _heads.next(_note_textures[lane])
		SpritePool.fit(head, Rect2(center_x - HEAD_SIZE * 0.5, y - HEAD_SIZE * 0.5, HEAD_SIZE, HEAD_SIZE))


func _render_hold(lane: int, center_x: float, head_y: float, sustain: float) -> void:
	var tail_y := head_y - sustain if downscroll else head_y
	var tail := _tails.next(_hold_textures[lane])
	SpritePool.stretch(tail, Rect2(center_x - HOLD_WIDTH * 0.5, tail_y, HOLD_WIDTH, sustain))
	var end_y := tail_y - HOLD_END_SIZE * 0.5 if downscroll else tail_y + sustain - HOLD_END_SIZE * 0.5
	var end_cap := _ends.next(_hold_end_textures[lane])
	SpritePool.fit(end_cap, Rect2(center_x - HOLD_END_SIZE * 0.5, end_y, HOLD_END_SIZE, HOLD_END_SIZE))
