## Installs a content pack: a .zip holding one mod folder (mod.json at the zip root or one folder down).
## Entries are read and written one at a time into a staging folder, which replaces mods/<id>/ only once complete.
class_name ModPackImporter
extends RefCounted

const MODS_DIR := "user://mods"
const CACHE_DIR := "user://cache"
const STAGING_DIR := "user://cache/mod-import"
const MANIFEST := "mod.json"
const MAX_ID_LENGTH := 64
const MAX_ENTRIES := 50000
const MAX_ENTRY_BYTES := 512 * 1024 * 1024
## Limit on both the .zip itself (and so a download) and everything it unpacks to.
const MAX_TOTAL_BYTES := 2 * 1024 * 1024 * 1024
## Resource-fork folders added by the macOS archiver.
const IGNORED_FOLDER := "__MACOSX/"

const END_RECORD_SIGNATURE := 0x06054b50
const END_RECORD_SIZE := 22
const MAX_COMMENT_SIZE := 0xFFFF
const ENTRY_SIGNATURE := 0x02014b50
const ENTRY_HEADER_SIZE := 46
const ZIP64_MARKER := 0xFFFFFFFF
const UNIX_HOST := 3
const FILE_TYPE_MASK := 0xF000
const SYMLINK_TYPE := 0xA000


class Result:
	extends RefCounted

	var mod_id := ""
	var mod_name := ""
	var target := ""
	var files := 0
	var skipped := 0
	var error := ""
	## The mod is already installed and replacing it was not requested; nothing was written.
	var needs_replace := false

	func ok() -> bool:
		return error.is_empty() and not needs_replace

	func fail(message: String) -> Result:
		error = message
		return self

	func summary() -> String:
		if not error.is_empty():
			return "Import failed: " + error
		if needs_replace:
			return "%s is already installed." % mod_id
		var extra := " (%d outside the pack folder ignored)" % skipped if skipped > 0 else ""
		return "Installed %s: %d file%s%s." % [mod_name, files, "" if files == 1 else "s", extra]


static func import_zip(zip_path: String, mods_dir := MODS_DIR, replace := false, staging_root := STAGING_DIR) -> Result:
	var result := Result.new()
	var rejection := archive_rejection(zip_path)
	if not rejection.is_empty():
		return result.fail(rejection)
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return result.fail("not a readable .zip file")
	_import(reader, mods_dir, replace, staging_root, result)
	reader.close()
	return result


## Completion of an HTTPRequest that downloaded a pack to zip_path.
static func import_download(http_result: int, response_code: int, zip_path: String, mods_dir := MODS_DIR,
		replace := false, staging_root := STAGING_DIR) -> Result:
	if http_result != HTTPRequest.RESULT_SUCCESS:
		return Result.new().fail("download failed (%s)" % download_error(http_result))
	if response_code != 200:
		return Result.new().fail("download failed (HTTP %d)" % response_code)
	return import_zip(zip_path, mods_dir, replace, staging_root)


static func download_error(http_result: int) -> String:
	match http_result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "could not connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "unknown host"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
		HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_NO_RESPONSE:
			return "no response"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "could not save the file"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "larger than " + String.humanize_size(MAX_TOTAL_BYTES)
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "too many redirects"
	return "error %d" % http_result


## Empty when the URL can be downloaded, otherwise why not.
static func url_rejection(url: String) -> String:
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return "Enter a link to a .zip file."
	var lower := trimmed.to_lower()
	if not (lower.begins_with("https://") or lower.begins_with("http://")):
		return "The link must start with https:// or http://."
	return ""


## Cache file a download is saved to, named after the URL's last path segment.
static func download_path(url: String, cache_dir := CACHE_DIR) -> String:
	var name := url.strip_edges().get_slice("#", 0).get_slice("?", 0).get_file().get_basename()
	name = slug(name)
	return cache_dir.path_join((name if not name.is_empty() else "download") + ".zip")


## Letters, digits, '.', '_' and '-' only, so the text is safe as a file or folder name.
static func slug(text: String) -> String:
	var regex := RegEx.create_from_string("[^A-Za-z0-9._-]+")
	return regex.sub(text, "-", true).lstrip(".-").left(MAX_ID_LENGTH)


## Empty when id can name a folder under mods/, otherwise why it is rejected.
static func id_rejection(id: Variant) -> String:
	if not id is String or (id as String).is_empty():
		return "mod.json needs a string \"id\""
	if (id as String).length() > MAX_ID_LENGTH:
		return "mod id is longer than %d characters" % MAX_ID_LENGTH
	if not RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9._-]*$").search(id):
		return "mod id \"%s\" may only use letters, digits, '.', '_' and '-'" % id
	return ""


## Reads the archive's central directory before anything is unpacked: empty when the entry count, sizes and
## entry types are acceptable, otherwise why not. ZIPReader allocates each file at its listed size, so this also bounds memory.
static func archive_rejection(zip_path: String) -> String:
	var file := FileAccess.open(zip_path, FileAccess.READ)
	if file == null:
		return "not a readable .zip file"
	var length := file.get_length()
	if length > MAX_TOTAL_BYTES:
		return "the .zip is larger than " + String.humanize_size(MAX_TOTAL_BYTES)
	var tail_size := mini(length, END_RECORD_SIZE + MAX_COMMENT_SIZE)
	file.seek(length - tail_size)
	var tail := file.get_buffer(tail_size)
	var end_record := -1
	for at in range(tail_size - END_RECORD_SIZE, -1, -1):
		if tail.decode_u32(at) == END_RECORD_SIGNATURE:
			end_record = at
			break
	if end_record < 0:
		return "not a readable .zip file"
	var count := tail.decode_u16(end_record + 10)
	var directory_size := tail.decode_u32(end_record + 12)
	if count == 0xFFFF or tail.decode_u32(end_record + 16) == ZIP64_MARKER:
		return "more than %d files or %s" % [MAX_ENTRIES, String.humanize_size(MAX_TOTAL_BYTES)]
	if count > MAX_ENTRIES:
		return "more than %d files" % MAX_ENTRIES
	# Located from the end record rather than its stored offset, which is wrong when data precedes the archive.
	var directory_start := length - tail_size + end_record - directory_size
	if directory_start < 0:
		return "not a readable .zip file"
	file.seek(directory_start)
	return _directory_rejection(file.get_buffer(directory_size), count)


static func _directory_rejection(directory: PackedByteArray, count: int) -> String:
	var total := 0
	var at := 0
	for _entry in count:
		if at + ENTRY_HEADER_SIZE > directory.size() or directory.decode_u32(at) != ENTRY_SIGNATURE:
			return "not a readable .zip file"
		var size := directory.decode_u32(at + 24)
		var name_length := directory.decode_u16(at + 28)
		var name := directory.slice(at + ENTRY_HEADER_SIZE, at + ENTRY_HEADER_SIZE + name_length).get_string_from_utf8()
		var unix_mode := directory.decode_u32(at + 38) >> 16
		if directory[at + 5] == UNIX_HOST and unix_mode & FILE_TYPE_MASK == SYMLINK_TYPE:
			return "symbolic link in archive: " + name
		if size == ZIP64_MARKER or size > MAX_ENTRY_BYTES:
			return "%s is larger than %s" % [name, String.humanize_size(MAX_ENTRY_BYTES)]
		total += size
		if total > MAX_TOTAL_BYTES:
			return "unpacks to more than " + String.humanize_size(MAX_TOTAL_BYTES)
		at += ENTRY_HEADER_SIZE + name_length + directory.decode_u16(at + 30) + directory.decode_u16(at + 32)
	return ""


## Empty when every archive entry stays inside the pack, otherwise the first entry that does not.
static func unsafe_entry(entries: PackedStringArray) -> String:
	for entry in entries:
		if normalized_entry(entry).is_empty():
			return entry
	return ""


## Entry path with backslashes read as '/' and empty or '.' segments dropped. Empty when the path is absolute, names a drive
## or stream (':'), climbs with '..' (also percent-encoded), or holds control characters such as NUL.
static func normalized_entry(entry: String) -> String:
	var path := entry.replace("\\", "/")
	if path.begins_with("/"):
		return ""
	var parts := PackedStringArray()
	for part in path.split("/"):
		if part.is_empty() or part == ".":
			continue
		var decoded := _percent_decoded(part)
		if part == ".." or decoded == ".." or decoded.contains("/") or decoded.contains("\\") \
				or part.contains(":") or _has_control_character(decoded):
			return ""
		parts.append(part)
	return "/".join(parts)


## String.uri_decode skips lowercase escapes such as %2e, so archive names are decoded here.
static func _percent_decoded(text: String) -> String:
	var pieces := text.split("%")
	var decoded := pieces[0]
	for index in range(1, pieces.size()):
		var piece := pieces[index]
		if piece.length() >= 2 and piece.left(2).is_valid_hex_number():
			# NUL cannot live in a String, so it becomes DEL, which is rejected the same way.
			var code := piece.left(2).hex_to_int()
			decoded += char(code if code > 0 else 0x7F) + piece.substr(2)
		else:
			decoded += "%" + piece
	return decoded


static func _has_control_character(text: String) -> bool:
	for index in text.length():
		if text.unicode_at(index) < 0x20 or text.unicode_at(index) == 0x7F:
			return true
	return false


static func _is_folder_entry(entry: String) -> bool:
	return entry.replace("\\", "/").ends_with("/")


## Folder prefix ("" or "<folder>/") holding mod.json, or null when there is none or more than one candidate.
static func pack_root(entries: PackedStringArray) -> Variant:
	var candidates := PackedStringArray()
	for entry in entries:
		var normalized := normalized_entry(entry)
		if normalized == MANIFEST:
			return ""
		var parts := normalized.split("/")
		if parts.size() == 2 and parts[1] == MANIFEST and not normalized.begins_with(IGNORED_FOLDER):
			candidates.append(parts[0] + "/")
	return candidates[0] if candidates.size() == 1 else null


static func _import(reader: ZIPReader, mods_dir: String, replace: bool, staging_root: String, result: Result) -> void:
	var entries := reader.get_files()
	var unsafe := unsafe_entry(entries)
	if not unsafe.is_empty():
		result.fail("unsafe path in archive: " + unsafe)
		return
	var prefix: Variant = pack_root(entries)
	if prefix == null:
		result.fail("no mod.json at the archive root or in a single top-level folder")
		return
	if not _read_manifest(reader, entries, prefix, result):
		return
	result.target = mods_dir.path_join(result.mod_id)
	if DirAccess.dir_exists_absolute(result.target) and not replace:
		result.needs_replace = true
		return
	var staging := staging_root.path_join(result.mod_id)
	remove_tree(staging)
	if _extract(reader, entries, prefix, staging, result):
		_install(staging, result)
	remove_tree(staging)
	# Only succeeds when empty, so a pack being staged elsewhere is never touched.
	DirAccess.remove_absolute(staging_root)


static func _read_manifest(reader: ZIPReader, entries: PackedStringArray, prefix: String, result: Result) -> bool:
	var json := JSON.new()
	var text := reader.read_file(_original_entry(entries, prefix + MANIFEST)).get_string_from_utf8()
	var manifest: Variant = json.data if json.parse(text) == OK else null
	if not manifest is Dictionary:
		result.fail("mod.json is not a JSON object")
		return false
	var id: Variant = (manifest as Dictionary).get("id")
	var rejection := id_rejection(id)
	if not rejection.is_empty():
		result.fail(rejection)
		return false
	result.mod_id = id
	result.mod_name = JsonRead.string(manifest, "name", result.mod_id)
	return true


static func _original_entry(entries: PackedStringArray, normalized: String) -> String:
	for entry in entries:
		if normalized_entry(entry) == normalized:
			return entry
	return normalized


static func _extract(reader: ZIPReader, entries: PackedStringArray, prefix: String, staging: String, result: Result) -> bool:
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		result.fail("could not create " + staging)
		return false
	for entry in entries:
		var normalized := normalized_entry(entry)
		if _is_folder_entry(entry) or normalized.begins_with(IGNORED_FOLDER):
			continue
		if not normalized.begins_with(prefix):
			result.skipped += 1
			continue
		if not _write_entry(reader, entry, staging.path_join(normalized.substr(prefix.length())), result):
			return false
	return true


static func _write_entry(reader: ZIPReader, entry: String, path: String, result: Result) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		result.fail("could not write %s (%s)" % [path.get_file(), error_string(FileAccess.get_open_error())])
		return false
	file.store_buffer(reader.read_file(entry))
	file.close()
	result.files += 1
	return true


## The installed copy is moved aside first and restored if the new one cannot be moved in.
static func _install(staging: String, result: Result) -> void:
	var previous := staging + ".previous"
	remove_tree(previous)
	var had_target := DirAccess.dir_exists_absolute(result.target)
	if had_target and DirAccess.rename_absolute(result.target, previous) != OK:
		result.fail("could not replace " + result.target)
		return
	DirAccess.make_dir_recursive_absolute(result.target.get_base_dir())
	var error := DirAccess.rename_absolute(staging, result.target)
	if error == OK:
		remove_tree(previous)
		return
	result.fail("could not move the pack into %s (%s)" % [result.target, error_string(error)])
	if had_target and DirAccess.rename_absolute(previous, result.target) != OK:
		result.error += "; the installed copy is kept at " + previous


## Includes hidden files, which packs often carry (.gitignore, .DS_Store).
static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for folder in dir.get_directories():
		remove_tree(path.path_join(folder))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
