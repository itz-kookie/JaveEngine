class_name StageLayout
extends RefCounted

const FALLBACK_CENTER_X := 170.0
const FALLBACK_FLOOR_Y := 535.0


## Bottom-centre box for a character, in stage space, from the stage's baked-image layout.
static func character_box(layout: Dictionary, placement: Dictionary, source_position: Vector2, box_size: Vector2, stage_size: Vector2) -> Rect2:
	var foot := Vector2(FALLBACK_CENTER_X + source_position.x * 0.9, FALLBACK_FLOOR_Y + source_position.y * 0.25)
	var anchor := JsonRead.array(placement, "anchor")
	if anchor.size() == 2:
		foot = Vector2(JsonRead.as_number(anchor[0]), JsonRead.as_number(anchor[1]))
		var source_anchor := JsonRead.array(placement, "sourceAnchor")
		if source_anchor.size() == 2:
			var units := JsonRead.number(layout, "positionScale", 0.5)
			foot += (source_position - Vector2(JsonRead.as_number(source_anchor[0]), JsonRead.as_number(source_anchor[1]))) * units
	var reference := Vector2(maxf(1.0, JsonRead.number(layout, "width", 1280.0)), maxf(1.0, JsonRead.number(layout, "height", 720.0)))
	var origin := Vector2(foot.x / reference.x * stage_size.x - box_size.x * 0.5, foot.y / reference.y * stage_size.y - box_size.y)
	return Rect2(origin, box_size)
