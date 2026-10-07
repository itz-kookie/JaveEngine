class_name StageCharacter
extends Node2D

const STAGE_SIZE := Vector2(1280.0, 720.0)
const DANCE_RIGHT_POSE := 4
const DEATH_POSE := SpriteFramesBuilder.DEATH_POSE

@onready var _speaker: AnimatedSprite2D = $Speaker
@onready var _body: AnimatedSprite2D = $Body

var _asset: CharacterAsset
var _base_flip := false
var _has_dance_right := false
var _pose_rects: Array[Rect2] = []
var _pose_fps := PackedFloat64Array()
var _pose_loops: Array[bool] = []
var _pose_frame_counts := PackedInt32Array()
var _speaker_fps := 24.0
var _speaker_loops := true
var _speaker_frame_count := 0
var _current_slot := -1
var _speaker_rect := Rect2()
var _body_size := Vector2.ZERO
var _speaker_size := Vector2.ZERO


func setup(asset: CharacterAsset, layout: Dictionary, role: String, source_position: Vector2, is_player: bool) -> void:
	_asset = asset
	_base_flip = JsonRead.boolean(asset.meta, "flipX", false) != is_player
	_has_dance_right = JsonRead.number(asset.pose_metadata("danceRight"), "frames") > 0.0
	_body.sprite_frames = asset.frames
	_layout(layout, role, source_position)


func _layout(layout: Dictionary, role: String, source_position: Vector2) -> void:
	var meta := _asset.meta
	var idle := _asset.pose_metadata("idle")
	var idle_size := Vector2(maxf(1.0, JsonRead.number(idle, "width", 420.0)), maxf(1.0, JsonRead.number(idle, "height", 500.0)))
	var speaker_size := Vector2.ZERO
	var overlap := 0.0
	if _asset.speaker != null:
		var speaker_idle := _asset.speaker.pose_metadata("idle")
		speaker_size = Vector2(JsonRead.number(speaker_idle, "width"), JsonRead.number(speaker_idle, "height"))
		overlap = clampf(JsonRead.number(JsonRead.object(meta, "speaker"), "overlap"), 0.0, speaker_size.y)
	var combined := Vector2(maxf(idle_size.x, speaker_size.x), idle_size.y + speaker_size.y - overlap)
	var placement := JsonRead.object(JsonRead.object(layout, "placements"), role)
	var source_scale := clampf(JsonRead.number(meta, "scale", 1.0) * JsonRead.number(placement, "scale", 1.0), 0.05, 10.0)
	var width_share := 0.42 if _asset.speaker != null else 0.36
	var scale_factor := minf(STAGE_SIZE.y / 720.0 * 0.72 * source_scale,
		minf(STAGE_SIZE.x * width_share / combined.x, STAGE_SIZE.y * 0.62 / combined.y))
	var box := StageLayout.character_box(layout, placement, source_position, combined * scale_factor, STAGE_SIZE)
	var lift := (speaker_size.y - overlap) * scale_factor
	_layout_poses(idle_size, scale_factor, box, lift)
	_layout_speaker(speaker_size * scale_factor, box)


func _layout_poses(idle_size: Vector2, scale_factor: float, box: Rect2, lift: float) -> void:
	_pose_rects.clear()
	_pose_loops.clear()
	_pose_fps.clear()
	_pose_frame_counts.clear()
	for pose_name in SpriteFramesBuilder.POSE_NAMES:
		var pose_meta := _asset.pose_metadata(pose_name)
		var size := Vector2(JsonRead.number(pose_meta, "width", idle_size.x), JsonRead.number(pose_meta, "height", idle_size.y)) * scale_factor
		var origin := Vector2(box.position.x + (box.size.x - size.x) * 0.5, box.end.y - size.y - lift)
		_pose_rects.append(Rect2(origin, size))
		_pose_fps.append(SpriteFramesBuilder.animation_fps(_asset.meta, pose_name))
		_pose_loops.append(SpriteFramesBuilder.animation_loops(_asset.meta, pose_name))
		_pose_frame_counts.append(_asset.frames.get_frame_count(pose_name))


func _layout_speaker(size: Vector2, box: Rect2) -> void:
	var speaker := _asset.speaker
	_speaker.visible = speaker != null
	if speaker == null:
		return
	var idle_name: StringName = SpriteFramesBuilder.POSE_NAMES[0]
	_speaker.sprite_frames = speaker.frames
	_speaker.animation = idle_name
	_speaker_fps = SpriteFramesBuilder.animation_fps(speaker.meta, idle_name)
	_speaker_loops = SpriteFramesBuilder.animation_loops(speaker.meta, idle_name)
	_speaker_frame_count = speaker.frames.get_frame_count(idle_name)
	_speaker_rect = Rect2(Vector2(box.position.x + (box.size.x - size.x) * 0.5, box.end.y - size.y), size)
	_speaker_size = _fit(_speaker, _speaker_rect)


func show_pose(pose: int, animation_seconds: float, song_ms: float, beat_ms: float, extra_flip: bool) -> void:
	if pose < 0 and _has_dance_right:
		pose = DANCE_RIGHT_POSE if int(song_ms / beat_ms) % 2 != 0 else -1
		animation_seconds = fmod(song_ms, beat_ms) / 1000.0
	var slot := SpriteFramesBuilder.pose_slot(pose)
	if slot != _current_slot:
		_switch_slot(slot)
	var count := _pose_frame_counts[slot]
	_body.visible = count > 0
	if count > 0:
		var frame := _frame_index(animation_seconds, _pose_fps[slot], _pose_loops[slot], count)
		if frame != _body.frame:
			_body.frame = frame
			_body_size = _refit_if_resized(_body, _pose_rects[slot], _body_size)
	_body.flip_h = _base_flip != extra_flip
	if _speaker_frame_count > 0:
		var speaker_frame := _frame_index(fmod(song_ms, beat_ms) / 1000.0, _speaker_fps, _speaker_loops, _speaker_frame_count)
		if speaker_frame != _speaker.frame:
			_speaker.frame = speaker_frame
			_speaker_size = _refit_if_resized(_speaker, _speaker_rect, _speaker_size)


func has_death_animation() -> bool:
	var slot := SpriteFramesBuilder.pose_slot(DEATH_POSE)
	return _pose_frame_counts.size() > slot and _pose_frame_counts[slot] > 0


func death_animation_duration() -> float:
	var slot := SpriteFramesBuilder.pose_slot(DEATH_POSE)
	return float(_pose_frame_counts[slot]) / _pose_fps[slot] if has_death_animation() else 0.0


func _switch_slot(slot: int) -> void:
	_current_slot = slot
	_body.animation = SpriteFramesBuilder.POSE_NAMES[slot]
	if _pose_frame_counts[slot] > 0:
		_body_size = _fit(_body, _pose_rects[slot])


static func _frame_index(seconds: float, fps: float, loops: bool, count: int) -> int:
	var frame := int(maxf(0.0, seconds) * fps)
	return frame % count if loops else mini(frame, count - 1)


## Returns the texture size the sprite was fitted for.
static func _fit(sprite: AnimatedSprite2D, rect: Rect2) -> Vector2:
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return Vector2.ZERO
	SpritePool.place_fitted(sprite, texture.get_size(), rect)
	return texture.get_size()


## Each frame is fitted into its pose's box on its own, so frames of differing sizes stay anchored.
static func _refit_if_resized(sprite: AnimatedSprite2D, rect: Rect2, fitted_size: Vector2) -> Vector2:
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null or texture.get_size() == fitted_size:
		return fitted_size
	return _fit(sprite, rect)
