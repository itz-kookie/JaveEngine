## Reads data/cutscenes.json: { "<songId>": { "before": "rel/path", "after": "rel/path" } }.
class_name CutsceneManifest
extends RefCounted


static func relative_path(manifest: Variant, song_id: String, outro: bool) -> String:
	var item: Variant = JsonRead.object(manifest, song_id).get("after" if outro else "before")
	return item if item is String else ""


## Empty when the path stays inside the content root, otherwise the reason it is rejected.
static func rejection(relative: String) -> String:
	var normalized := relative.replace("\\", "/")
	if normalized.begins_with("/") or normalized.contains(":"):
		return "Absolute cutscene path rejected"
	if normalized.split("/").has(".."):
		return "Cutscene path traversal rejected"
	return ""
