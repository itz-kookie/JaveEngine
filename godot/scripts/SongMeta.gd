class_name SongMeta
extends RefCounted

var id := ""
var title := ""
var artist := ""
var description := ""
var license := ""
var bpm := 120.0
var order := 100000
var week_id := ""
var stage := "stage"
var player_character := "bf"
var opponent_character := "dad"
var girlfriend_character := "gf"
var audio_path := ""
var chart_path := ""
var stage_image := ""
var player_visual := ""
var opponent_visual := ""
var girlfriend_visual := ""
var player_icon := ""
var opponent_icon := ""
var player_position := Vector2(770.0, 100.0)
var opponent_position := Vector2(100.0, 100.0)
var girlfriend_position := Vector2(400.0, 130.0)
var camera_player := Vector2.ZERO
var camera_opponent := Vector2.ZERO
var camera_girlfriend := Vector2.ZERO
var stage_zoom := 0.9
var camera_speed := 1.0
var hide_girlfriend := false
var stage_layout: Dictionary = {}
var stage_config_path := ""


static func from_json(json: Dictionary, package_root: String, folder_name: String) -> SongMeta:
	var song := SongMeta.new()
	song.id = JsonRead.string(json, "id", folder_name)
	song.title = JsonRead.string(json, "title", song.id)
	song.artist = JsonRead.string(json, "artist", "Unknown artist")
	song.description = JsonRead.string(json, "description")
	song.license = JsonRead.string(json, "license", "Unspecified")
	song.bpm = JsonRead.number(json, "bpm", 120.0)
	song.order = JsonRead.integer(json, "order", 100000)
	song.week_id = JsonRead.string(json, "week")
	song.stage = JsonRead.string(json, "stage", "stage")
	song.player_character = JsonRead.string(json, "playerCharacter", "bf")
	song.opponent_character = JsonRead.string(json, "opponentCharacter", "dad")
	song.girlfriend_character = JsonRead.string(json, "girlfriendCharacter", "gf")
	song._read_paths(json, package_root)
	song._read_placement(json)
	song.stage_config_path = package_root.path_join("data/stages").path_join(song.stage + ".json")
	return song


func _read_paths(json: Dictionary, package_root: String) -> void:
	audio_path = _package_path(package_root, JsonRead.string(json, "audio"))
	chart_path = _package_path(package_root, JsonRead.string(json, "chart"))
	stage_image = _package_path(package_root, JsonRead.string(json, "stageImage"))
	player_visual = _package_path(package_root, JsonRead.string(json, "playerVisual"))
	opponent_visual = _package_path(package_root, JsonRead.string(json, "opponentVisual"))
	girlfriend_visual = _package_path(package_root, JsonRead.string(json, "girlfriendVisual"))
	player_icon = _package_path(package_root, JsonRead.string(json, "playerIcon"))
	opponent_icon = _package_path(package_root, JsonRead.string(json, "opponentIcon"))


func _read_placement(json: Dictionary) -> void:
	player_position = JsonRead.point(json, "boyfriendPosition", player_position)
	opponent_position = JsonRead.point(json, "opponentPosition", opponent_position)
	girlfriend_position = JsonRead.point(json, "girlfriendPosition", girlfriend_position)
	camera_player = JsonRead.point(json, "cameraBoyfriend", camera_player)
	camera_opponent = JsonRead.point(json, "cameraOpponent", camera_opponent)
	camera_girlfriend = JsonRead.point(json, "cameraGirlfriend", camera_girlfriend)
	stage_zoom = JsonRead.number(json, "defaultZoom", 0.9)
	camera_speed = JsonRead.number(json, "cameraSpeed", 1.0)
	hide_girlfriend = JsonRead.boolean(json, "hideGirlfriend", false)


func apply_stage(stage: Dictionary) -> void:
	player_position = JsonRead.point(stage, "boyfriend", player_position)
	opponent_position = JsonRead.point(stage, "opponent", opponent_position)
	girlfriend_position = JsonRead.point(stage, "girlfriend", girlfriend_position)
	camera_player = JsonRead.point(stage, "cameraBoyfriend", camera_player)
	camera_opponent = JsonRead.point(stage, "cameraOpponent", camera_opponent)
	camera_girlfriend = JsonRead.point(stage, "cameraGirlfriend", camera_girlfriend)
	stage_zoom = JsonRead.number(stage, "defaultZoom", stage_zoom)
	camera_speed = JsonRead.number(stage, "cameraSpeed", camera_speed)
	hide_girlfriend = JsonRead.boolean(stage, "hideGirlfriend", hide_girlfriend)
	stage_layout = JsonRead.object(stage, "layout")


static func _package_path(package_root: String, relative: String) -> String:
	return package_root.path_join(relative) if not relative.is_empty() else ""
