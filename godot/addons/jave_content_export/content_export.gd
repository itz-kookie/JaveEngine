## res://content is .gdignore'd so the importer never touches it, which also hides it from the exporter.
## This adds its files to the pack verbatim, selected by the preset's own include and exclude filters.
@tool
extends EditorExportPlugin

const CONTENT_ROOT := "res://content"


func _get_name() -> String:
	return "JaveContentExport"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not DirAccess.dir_exists_absolute(CONTENT_ROOT):
		push_warning("Jave content export: %s is missing, no content packed" % CONTENT_ROOT)
		return
	var preset := get_export_preset()
	var include := _filters(preset.get_include_filter())
	var exclude := _filters(preset.get_exclude_filter())
	var count := 0
	for path in content_files(CONTENT_ROOT):
		if matches(path, include) and not matches(path, exclude):
			add_file(path, FileAccess.get_file_as_bytes(path), false)
			count += 1
	print("Jave content export: packed %d files from %s" % [count, CONTENT_ROOT])


## Follows the content/ symlinks; hidden entries such as .gdignore are skipped.
static func content_files(root: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(root):
		files.append(root.path_join(file))
	for folder in DirAccess.get_directories_at(root):
		files.append_array(content_files(root.path_join(folder)))
	return files


## Same matching the exporter uses for its own filters: against the path with and without res://.
static func matches(path: String, filters: PackedStringArray) -> bool:
	var relative := path.trim_prefix("res://")
	for filter in filters:
		if path.matchn(filter) or relative.matchn(filter):
			return true
	return false


static func _filters(text: String) -> PackedStringArray:
	var filters := PackedStringArray()
	for filter in text.split(",", false):
		if not filter.strip_edges().is_empty():
			filters.append(filter.strip_edges())
	return filters
