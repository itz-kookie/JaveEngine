class_name WeekMeta
extends RefCounted

var id := ""
var name := ""
var story_name := ""
var song_ids := PackedStringArray()
var color := Color8(95, 227, 255)


static func from_json(json: Dictionary) -> WeekMeta:
	var week := WeekMeta.new()
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


static func _channel(value: Variant, fallback: int) -> int:
	return clampi(int(JsonRead.as_number(value, fallback)), 0, 255)
