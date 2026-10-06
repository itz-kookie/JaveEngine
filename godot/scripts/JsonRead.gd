class_name JsonRead
extends RefCounted

const EMPTY_DICT: Dictionary = {}
const EMPTY_ARRAY: Array = []


static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func object(value: Variant, key: String) -> Dictionary:
	if value is Dictionary:
		var item: Variant = (value as Dictionary).get(key)
		if item is Dictionary:
			return item
	return EMPTY_DICT


static func array(value: Variant, key: String) -> Array:
	if value is Dictionary:
		var item: Variant = (value as Dictionary).get(key)
		if item is Array:
			return item
	return EMPTY_ARRAY


static func number(value: Variant, key: String, fallback: float = 0.0) -> float:
	return as_number(value.get(key) if value is Dictionary else null, fallback)


static func integer(value: Variant, key: String, fallback: int = 0) -> int:
	var item: Variant = value.get(key) if value is Dictionary else null
	return int(item) if item is float or item is int else fallback


static func boolean(value: Variant, key: String, fallback: bool = false) -> bool:
	var item: Variant = value.get(key) if value is Dictionary else null
	return item if item is bool else fallback


static func string(value: Variant, key: String, fallback: String = "") -> String:
	var item: Variant = value.get(key) if value is Dictionary else null
	return item if item is String else fallback


static func as_number(item: Variant, fallback: float = 0.0) -> float:
	return float(item) if item is float or item is int else fallback


static func point(value: Variant, key: String, fallback: Vector2) -> Vector2:
	var items := array(value, key)
	if items.size() != 2:
		return fallback
	return Vector2(as_number(items[0], fallback.x), as_number(items[1], fallback.y))
