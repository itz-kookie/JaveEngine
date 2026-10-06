## Enabled flags chosen in the Mods screen, kept outside the read-only mod folders.
class_name ModOverrides
extends RefCounted


static func load_file(path: String) -> Dictionary:
	var overrides: Dictionary = {}
	var enabled := JsonRead.object(JsonRead.load_file(path), "enabled")
	for id: Variant in enabled:
		if id is String and enabled[id] is bool:
			overrides[id] = enabled[id]
	return overrides


static func save_file(path: String, overrides: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"enabled": overrides}, "  "))
	return true


static func apply(mods: Array[ModInfo], overrides: Dictionary) -> void:
	for mod in mods:
		mod.enabled = overrides.get(mod.id, mod.enabled)
