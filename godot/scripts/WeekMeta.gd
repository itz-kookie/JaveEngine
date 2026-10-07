class_name WeekMeta
extends RefCounted

const BANNER_FOLDER := "assets/imported/menus"

var id := ""
var name := ""
var story_name := ""
var song_ids := PackedStringArray()
var color := Color8(95, 227, 255)
## Root of the package (base content or mod folder) the week was read from; empty when unknown.
var package_root := ""


static func from_json(json: Dictionary, package_root := "") -> WeekMeta:
	var week := WeekMeta.new()
	week.package_root = package_root
	week.id = JsonRead.string(json, "id")
	week.name = JsonRead.string(json, "name", week.id)
	week.story_name = JsonRead.string(json, "storyName")
	for song: Variant in JsonRead.array(json, "songs"):
		if song is String:
			week.song_ids.append(song)
	var rgb := JsonRead.array(json, "color")
	if rgb.size() == 3:
		week.color = Color8(_channel(rgb[0], 95), _channel(rgb[1], 227), _channel(rgb[2], 255))
	return week


## The week's own banner when its package has one, otherwise the shared menu art.
func banner_path() -> String:
	var relative := "weeks/%s.png" % id
	if not package_root.is_empty():
		var own := package_root.path_join(BANNER_FOLDER).path_join(relative)
		if FileAccess.file_exists(own):
			return own
	return Ui.MENUS_ROOT.path_join(relative)


static func _channel(value: Variant, fallback: int) -> int:
	return clampi(int(JsonRead.as_number(value, fallback)), 0, 255)
