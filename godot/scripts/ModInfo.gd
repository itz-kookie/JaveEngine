class_name ModInfo
extends RefCounted

var id := ""
var name := ""
var version := ""
var author := ""
var description := ""
var enabled := true
var root := ""


static func from_json(json: Dictionary, mod_root: String) -> ModInfo:
	var mod := ModInfo.new()
	mod.root = mod_root
	mod.id = JsonRead.string(json, "id", mod_root.get_file())
	mod.name = JsonRead.string(json, "name", mod.id)
	mod.version = JsonRead.string(json, "version", "0.0.0")
	mod.author = JsonRead.string(json, "author", "Unknown")
	mod.description = JsonRead.string(json, "description")
	mod.enabled = JsonRead.boolean(json, "enabled", true)
	return mod
