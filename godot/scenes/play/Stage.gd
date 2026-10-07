class_name PlayStage
extends Node2D

const STAGE_SIZE := Vector2(1280.0, 720.0)
const STAGE_CENTER := STAGE_SIZE * 0.5
const DEATH_FADE_SECONDS := 0.7

@onready var _background: Sprite2D = $Background
@onready var _girlfriend: StageCharacter = $Girlfriend
@onready var _opponent: StageCharacter = $Opponent
@onready var _player: StageCharacter = $Player
@onready var _camera: Camera2D = $Camera


func setup(song: SongMeta, assets: SongAssets) -> void:
	_show_background(assets.stage_texture if assets.stage_texture != null else TextureCache.get_texture(song.stage_image))
	var layout := song.stage_layout
	_girlfriend.visible = assets.girlfriend != null and not song.hide_girlfriend
	if _girlfriend.visible:
		_girlfriend.setup(assets.girlfriend, layout, "girlfriend", song.girlfriend_position, false)
	_opponent.visible = assets.opponent != null
	if _opponent.visible:
		_opponent.setup(assets.opponent, layout, "opponent", song.opponent_position, false)
	_player.visible = assets.player != null
	if _player.visible:
		_player.setup(assets.player, layout, "player", song.player_position, true)
	_camera.make_current()


func _show_background(texture: Texture2D) -> void:
	_background.texture = texture
	if texture == null:
		return
	var size := texture.get_size()
	var fit := minf(STAGE_SIZE.x / size.x, STAGE_SIZE.y / size.y)
	_background.centered = true
	_background.scale = Vector2(fit, fit)
	_background.position = Vector2(STAGE_CENTER.x, STAGE_SIZE.y - size.y * fit * 0.5)


func update_view(play: Gameplay) -> void:
	var song_ms := play.song_time_ms
	var beat_ms := Conductor.beat_ms(play.chart.bpm)
	var idle_seconds := fmod(song_ms, beat_ms * 2.0) / 1000.0
	if _girlfriend.visible:
		_girlfriend.show_pose(-1, idle_seconds, song_ms, beat_ms, false)
	if _opponent.visible:
		var opponent_seconds := idle_seconds if play.opponent_pose < 0 else (song_ms - play.opponent_animation_ms) / 1000.0
		_opponent.show_pose(play.opponent_pose, opponent_seconds, song_ms, beat_ms, false)
	if _player.visible:
		var player_seconds := idle_seconds if play.player_pose < 0 else (song_ms - play.player_animation_ms) / 1000.0
		_player.show_pose(play.player_pose, player_seconds, song_ms, beat_ms, ModHost.player_flip)
	_update_camera(play)


func death_animation_duration() -> float:
	if _player.visible and _player.has_death_animation():
		return clampf(_player.death_animation_duration(), 0.7, 4.0)
	return DEATH_FADE_SECONDS


func show_death(seconds: float, play: Gameplay) -> void:
	if not _player.visible:
		return
	if _player.has_death_animation():
		var beat_ms := Conductor.beat_ms(play.chart.bpm)
		_player.show_pose(StageCharacter.DEATH_POSE, seconds, play.song_time_ms, beat_ms, ModHost.player_flip)
	else:
		var color := _player.modulate
		color.a = clampf(1.0 - seconds / DEATH_FADE_SECONDS, 0.0, 1.0)
		_player.modulate = color


## Matches screen = (world - centre) * zoom + centre + pan.
func _update_camera(play: Gameplay) -> void:
	var zoom := play.camera_scale()
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = STAGE_CENTER - play.camera_pan / zoom
