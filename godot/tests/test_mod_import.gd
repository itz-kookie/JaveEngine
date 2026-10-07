extends "res://tests/test_base.gd"

## Content pack import from zips built here with ZIPPacker, plus the download completion path and the Mods screen rows.
const TEMP_DIR := "user://test_mod_import"
const MODS := TEMP_DIR + "/mods"
const ZIPS := TEMP_DIR + "/zips"
const STAGING := TEMP_DIR + "/staging"
const SCREEN_MOD_ID := "zz-import-screen-test"

var _ran := false


## The Mods screen part needs the autoloads, which exist from the first frame.
func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_all()
	return false


func _run_all() -> void:
	var had_cache := DirAccess.dir_exists_absolute(ModPackImporter.CACHE_DIR)
	ModPackImporter.remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(ZIPS)
	run()
	await _test_mods_screen()
	ModPackImporter.remove_tree(TEMP_DIR)
	check(not DirAccess.dir_exists_absolute(TEMP_DIR), "temporary directory removed")
	check(not DirAccess.dir_exists_absolute(ModPackImporter.STAGING_DIR), "no staging folder left behind")
	if not had_cache:
		DirAccess.remove_absolute(ModPackImporter.CACHE_DIR)
	print("%s: %d checks, %d failures" % [get_script().resource_path.get_file(), _checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func run() -> void:
	_test_validation_helpers()
	_test_root_level_pack()
	_test_nested_pack()
	_test_replace()
	_test_rejections()
	_test_entry_normalisation()
	_test_archive_limits()
	_test_download_completion()
	_test_texture_cache_forget()


func _test_validation_helpers() -> void:
	for good: String in ["my-mod", "Mod_2", "a.b", "x"]:
		check(ModPackImporter.id_rejection(good).is_empty(), "id accepted: " + good)
	for bad: Variant in ["", "bad id", "../evil", ".hidden", "-dash", "a/b", "a\\b", "C:x", 5, null, "x".repeat(65)]:
		check(not ModPackImporter.id_rejection(bad).is_empty(), "id rejected: %s" % [bad])
	check(ModPackImporter.url_rejection("https://example.com/p.zip").is_empty(), "https link accepted")
	check(ModPackImporter.url_rejection("  http://example.com/p.zip ").is_empty(), "http link with spaces accepted")
	check(not ModPackImporter.url_rejection("").is_empty(), "empty link rejected")
	check(not ModPackImporter.url_rejection("file:///etc/passwd").is_empty(), "file link rejected")
	check(ModPackImporter.download_path("https://x.test/packs/My Pack.zip?dl=1#top", "user://cache") == "user://cache/My-Pack.zip",
		"download named after the link (got %s)" % ModPackImporter.download_path("https://x.test/packs/My Pack.zip?dl=1#top", "user://cache"))
	check(ModPackImporter.download_path("https://x.test/", "user://cache") == "user://cache/download.zip", "download without a file name")
	check(ModPackImporter.download_path("https://x.test/..%2f..zip", "user://cache").get_base_dir() == "user://cache", "download stays in the cache")


func _test_root_level_pack() -> void:
	var zip := _zip("root.zip", {
		"mod.json": JSON.stringify({"id": "zz-root", "name": "Root Pack"}),
		"songs/a/song.json": "{\"id\": \"a\"}",
		"data/weeks.json": "{\"weeks\": []}",
		".gitignore": "*.tmp",
	})
	var result := ModPackImporter.import_zip(zip, MODS, false, STAGING)
	check(result.ok() and result.error.is_empty(), "root-level pack imports: " + result.summary())
	check(result.mod_id == "zz-root" and result.mod_name == "Root Pack" and result.files == 4, "root-level pack counts (got %d files)" % result.files)
	check(result.target == MODS.path_join("zz-root"), "pack goes to mods/<id>")
	check(FileAccess.get_file_as_string(MODS.path_join("zz-root/songs/a/song.json")) == "{\"id\": \"a\"}", "nested file contents kept")
	check(FileAccess.file_exists(MODS.path_join("zz-root/.gitignore")), "hidden files kept")
	check(FileAccess.file_exists(MODS.path_join("zz-root/mod.json")), "manifest extracted")
	check(not DirAccess.dir_exists_absolute(STAGING.path_join("zz-root")), "staging folder removed")
	check(result.summary().begins_with("Installed Root Pack: 4 files"), "summary: " + result.summary())


func _test_nested_pack() -> void:
	var zip := _zip("nested.zip", {
		"Folder Name/mod.json": JSON.stringify({"id": "zz-nested"}),
		"Folder Name/assets/imported/notes/note_up.png": "png",
		"Folder Name/scripts/x.lua": "jave_log('x')",
		"README.txt": "outside the pack folder",
		"__MACOSX/Folder Name/._mod.json": "fork",
	}, ["Folder Name/", "Folder Name/assets/"])
	var result := ModPackImporter.import_zip(zip, MODS, false, STAGING)
	check(result.ok(), "nested pack imports: " + result.summary())
	check(result.mod_id == "zz-nested" and result.mod_name == "zz-nested", "folder named by the manifest id, name defaults to id")
	check(result.files == 3 and result.skipped == 1, "nested counts (files %d, skipped %d)" % [result.files, result.skipped])
	check(FileAccess.file_exists(MODS.path_join("zz-nested/assets/imported/notes/note_up.png")), "nested file lands under mods/<id>")
	check(not FileAccess.file_exists(MODS.path_join("zz-nested/README.txt")), "files outside the pack folder ignored")
	check(not DirAccess.dir_exists_absolute(MODS.path_join("zz-nested/__MACOSX")), "macOS resource forks ignored")
	var backslashes := _zip("backslash.zip", {"pack\\mod.json": JSON.stringify({"id": "zz-backslash"}), "pack\\data\\weeks.json": "{}"})
	var windows := ModPackImporter.import_zip(backslashes, MODS, false, STAGING)
	check(windows.ok() and FileAccess.file_exists(MODS.path_join("zz-backslash/data/weeks.json")), "backslash separators understood: " + windows.summary())


func _test_replace() -> void:
	var marker := MODS.path_join("zz-root/marker.txt")
	_write(marker, "old")
	var zip := ZIPS.path_join("root.zip")
	var again := ModPackImporter.import_zip(zip, MODS, false, STAGING)
	check(again.needs_replace and not again.ok() and again.error.is_empty(), "existing mod asks before replacing")
	check(again.files == 0 and FileAccess.file_exists(marker), "nothing written without replace")
	var replaced := ModPackImporter.import_zip(zip, MODS, true, STAGING)
	check(replaced.ok() and replaced.files == 4, "replace imports: " + replaced.summary())
	check(not FileAccess.file_exists(marker), "replace removes files the pack does not have")
	var broken := _zip("broken-replace.zip", {"mod.json": "{\"id\": \"zz-root\"}", "../x": "x"})
	ModPackImporter.import_zip(broken, MODS, true, STAGING)
	check(FileAccess.file_exists(MODS.path_join("zz-root/songs/a/song.json")), "a rejected pack leaves the installed mod alone")


func _test_rejections() -> void:
	var cases := {
		"traversal": [{"mod.json": "{\"id\": \"zz-bad\"}", "../x": "x"}, "unsafe path in archive: .."],
		"nested-traversal": [{"p/mod.json": "{\"id\": \"zz-bad\"}", "p/a/../../../x": "x"}, "unsafe path"],
		"backslash-traversal": [{"mod.json": "{\"id\": \"zz-bad\"}", "a\\..\\..\\x": "x"}, "unsafe path"],
		"absolute": [{"mod.json": "{\"id\": \"zz-bad\"}", "/etc/x": "x"}, "unsafe path"],
		"drive": [{"mod.json": "{\"id\": \"zz-bad\"}", "C:/x": "x"}, "unsafe path"],
		"no-manifest": [{"songs/a/song.json": "{}"}, "no mod.json"],
		"too-deep": [{"a/b/mod.json": "{\"id\": \"zz-bad\"}"}, "no mod.json"],
		"two-folders": [{"a/mod.json": "{\"id\": \"zz-a\"}", "b/mod.json": "{\"id\": \"zz-b\"}"}, "no mod.json"],
		"invalid-id": [{"mod.json": "{\"id\": \"../evil\"}"}, "may only use"],
		"missing-id": [{"mod.json": "{\"name\": \"x\"}"}, "needs a string \"id\""],
		"number-id": [{"mod.json": "{\"id\": 3}"}, "needs a string \"id\""],
		"bad-json": [{"mod.json": "not json"}, "not a JSON object"],
	}
	for name: String in cases:
		var result := ModPackImporter.import_zip(_zip(name + ".zip", cases[name][0]), MODS, false, STAGING)
		check(not result.ok() and result.error.contains(cases[name][1]), "%s rejected (got \"%s\")" % [name, result.error])
		check(result.files == 0, name + " writes nothing")
	check(not DirAccess.dir_exists_absolute(MODS.path_join("zz-bad")) and not FileAccess.file_exists(TEMP_DIR.path_join("x")), "rejected packs leave no files")
	_write(ZIPS.path_join("fake.zip"), "not a zip")
	check(ModPackImporter.import_zip(ZIPS.path_join("fake.zip"), MODS, false, STAGING).error.contains("not a readable"), "non-zip rejected")
	check(ModPackImporter.import_zip(ZIPS.path_join("missing.zip"), MODS, false, STAGING).error.contains("not a readable"), "missing file rejected")


func _test_entry_normalisation() -> void:
	var kept := {"./a//b/./c.png": "a/b/c.png", "a\\b": "a/b", "folder/": "folder", "a%20b.png": "a%20b.png"}
	for entry: String in kept:
		check(ModPackImporter.normalized_entry(entry) == kept[entry], "%s normalised to %s (got %s)" % [entry, kept[entry], ModPackImporter.normalized_entry(entry)])
	for entry: String in ["/x", "\\x", "//x", "C:/x", "c:x", "a/b:stream", "..", "a/..", "./../x", "a/./../../x", "%2e%2e/x",
			"a/%2E%2e/x", "a%2f..%2fx", "a%5c..", "a\nb", "a%00b", "a\u0001b"]:
		check(ModPackImporter.normalized_entry(entry).is_empty(), "unsafe entry rejected: " + entry.c_escape())
	var dotted := _zip("dotted.zip", {
		"./pack/mod.json": JSON.stringify({"id": "zz-dotted"}),
		"./pack//songs/./a/song.json": "{}",
		"pack\\data\\weeks.json": "{}",
	})
	var result := ModPackImporter.import_zip(dotted, MODS, false, STAGING)
	check(result.ok() and result.files == 3, "'./' and repeated slashes are read as plain paths: " + result.summary())
	check(FileAccess.file_exists(MODS.path_join("zz-dotted/songs/a/song.json")) and FileAccess.file_exists(MODS.path_join("zz-dotted/data/weeks.json")),
		"normalised entries land under mods/<id>")
	var cases := {
		"encoded-traversal": [{"mod.json": "{\"id\": \"zz-bad\"}", "%2e%2e/x": "x"}, "unsafe path"],
		"dot-slash-traversal": [{"mod.json": "{\"id\": \"zz-bad\"}", "./../x": "x"}, "unsafe path"],
		"root-folder-traversal": [{"p/mod.json": "{\"id\": \"zz-bad\"}", "p/../../x": "x"}, "unsafe path"],
		"control-character": [{"mod.json": "{\"id\": \"zz-bad\"}", "a\u0001b": "x"}, "unsafe path"],
		"stream-name": [{"mod.json": "{\"id\": \"zz-bad\"}", "a.png:evil": "x"}, "unsafe path"],
	}
	for name: String in cases:
		var rejected := ModPackImporter.import_zip(_zip(name + ".zip", cases[name][0]), MODS, false, STAGING)
		check(not rejected.ok() and rejected.error.contains(cases[name][1]) and rejected.files == 0, "%s rejected (got \"%s\")" % [name, rejected.error])
	check(not DirAccess.dir_exists_absolute(MODS.path_join("zz-bad")) and not FileAccess.file_exists(TEMP_DIR.path_join("x")), "rejected packs leave no files")


## Zips whose central directory is edited after packing: the importer must refuse them before unpacking anything.
func _test_archive_limits() -> void:
	var files := {"mod.json": JSON.stringify({"id": "zz-limits"}), "a.bin": "a", "b.bin": "b", "c.bin": "c", "d.bin": "d", "e.bin": "e"}
	var symlink := _zip("symlink.zip", files)
	_patch_entries(symlink, func(bytes: PackedByteArray, at: int, index: int) -> void:
		if index == 1:
			bytes[at + 5] = ModPackImporter.UNIX_HOST
			bytes.encode_u32(at + 38, (ModPackImporter.SYMLINK_TYPE | 0x1FF) << 16))
	_expect_rejected(symlink, "symbolic link", "symlink entry")
	var large := _zip("large.zip", files)
	_patch_entries(large, func(bytes: PackedByteArray, at: int, index: int) -> void:
		if index == 2:
			bytes.encode_u32(at + 24, ModPackImporter.MAX_ENTRY_BYTES + 1))
	_expect_rejected(large, "is larger than", "oversized entry")
	var zip64 := _zip("zip64.zip", files)
	_patch_entries(zip64, func(bytes: PackedByteArray, at: int, index: int) -> void:
		if index == 2:
			bytes.encode_u32(at + 24, ModPackImporter.ZIP64_MARKER))
	_expect_rejected(zip64, "is larger than", "zip64 entry")
	var bomb := _zip("bomb.zip", files)
	_patch_entries(bomb, func(bytes: PackedByteArray, at: int, index: int) -> void:
		if index > 0:
			bytes.encode_u32(at + 24, ModPackImporter.MAX_ENTRY_BYTES))
	_expect_rejected(bomb, "unpacks to more than", "total size over the limit")
	var crowded := _zip("crowded.zip", files)
	var bytes := FileAccess.get_file_as_bytes(crowded)
	var end := bytes.size() - ModPackImporter.END_RECORD_SIZE
	bytes.encode_u16(end + 8, ModPackImporter.MAX_ENTRIES + 1)
	bytes.encode_u16(end + 10, ModPackImporter.MAX_ENTRIES + 1)
	_write_bytes(crowded, bytes)
	_expect_rejected(crowded, "more than %d files" % ModPackImporter.MAX_ENTRIES, "entry count over the limit")
	var prefixed := ZIPS.path_join("prefixed.zip")
	var with_stub := "stub".to_utf8_buffer()
	with_stub.append_array(FileAccess.get_file_as_bytes(_zip("plain.zip", files)))
	_write_bytes(prefixed, with_stub)
	check(ModPackImporter.archive_rejection(prefixed).is_empty(), "data before the archive does not hide its directory: " + ModPackImporter.archive_rejection(prefixed))
	check(ModPackImporter.archive_rejection(ZIPS.path_join("plain.zip")).is_empty(), "an ordinary zip passes the limits")


func _expect_rejected(zip: String, reason: String, label: String) -> void:
	var result := ModPackImporter.import_zip(zip, MODS, false, STAGING)
	check(not result.ok() and result.error.contains(reason), "%s rejected (got \"%s\")" % [label, result.error])
	check(result.files == 0 and not DirAccess.dir_exists_absolute(MODS.path_join("zz-limits")), label + " writes nothing")
	check(not DirAccess.dir_exists_absolute(STAGING.path_join("zz-limits")), label + " leaves no staging folder")


## Calls patch with the bytes, the offset of each central directory record and its index, then saves the file.
func _patch_entries(zip: String, patch: Callable) -> void:
	var bytes := FileAccess.get_file_as_bytes(zip)
	var end := bytes.size() - ModPackImporter.END_RECORD_SIZE
	check(bytes.decode_u32(end) == ModPackImporter.END_RECORD_SIGNATURE, "test zip has no trailing comment")
	var at := bytes.decode_u32(end + 16)
	for index in bytes.decode_u16(end + 10):
		patch.call(bytes, at, index)
		at += ModPackImporter.ENTRY_HEADER_SIZE + bytes.decode_u16(at + 28) + bytes.decode_u16(at + 30) + bytes.decode_u16(at + 32)
	_write_bytes(zip, bytes)


## A reinstalled mod's files must not come back as the old textures, while identical frames still share one texture.
func _test_texture_cache_forget() -> void:
	var folder := MODS.path_join("zz-textures")
	var path := folder.path_join("note.png")
	var twin := folder.path_join("twin.png")
	DirAccess.make_dir_recursive_absolute(folder)
	Image.create(2, 2, false, Image.FORMAT_RGBA8).save_png(path)
	var old_texture := TextureCache.get_texture(path)
	var old_hash := TextureCache.content_hash(path)
	Image.create(4, 4, false, Image.FORMAT_RGBA8).save_png(path)
	DirAccess.copy_absolute(path, twin)
	TextureCache.forget_under(folder + "/")
	var new_texture := TextureCache.get_texture(path)
	check(new_texture != old_texture and new_texture.get_width() == 4, "replaced file loads fresh after forget_under")
	var new_hash := TextureCache.content_hash(path)
	check(new_hash != old_hash, "replaced file is hashed again after forget_under")
	var frame := TextureCache.frame(new_hash, null, path)
	check(frame != null and TextureCache.frame(TextureCache.content_hash(twin), null, twin) == frame, "identical frames still share one texture")
	TextureCache.forget_under(folder)
	TextureCache.prune_frames()
	ModPackImporter.remove_tree(folder)


func _test_download_completion() -> void:
	var zip := _zip("download.zip", {"mod.json": JSON.stringify({"id": "zz-download"}), "data/weeks.json": "{}"})
	var ok := ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 200, zip, MODS, false, STAGING)
	check(ok.ok() and FileAccess.file_exists(MODS.path_join("zz-download/data/weeks.json")), "completed download imports: " + ok.summary())
	var not_found := ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 404, zip, MODS, true, STAGING)
	check(not_found.error.contains("HTTP 404"), "HTTP error reported: " + not_found.error)
	var partial := ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 206, zip, MODS, true, STAGING)
	check(partial.error.contains("HTTP 206"), "only HTTP 200 is accepted: " + partial.error)
	var too_big := ModPackImporter.import_download(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, 200, zip, MODS, true, STAGING)
	check(too_big.error.contains("larger than"), "oversized download reported: " + too_big.error)
	var unresolved := ModPackImporter.import_download(HTTPRequest.RESULT_CANT_RESOLVE, 0, zip, MODS, true, STAGING)
	check(unresolved.error.contains("unknown host"), "network error reported: " + unresolved.error)


## Drives the real Mods screen: import rows, the URL field, and a finished download installed into the mods folder.
func _test_mods_screen() -> void:
	var content: Node = root.get_node("/root/Content")
	var saved_overrides: String = content.get("mod_overrides_path")
	content.set("mod_overrides_path", TEMP_DIR.path_join("mods.json"))
	content.call("scan")
	# Loaded at runtime because the screen references autoloads, which -s scripts cannot see at compile time.
	var screens: GDScript = load("res://scenes/menus/ModsScreen.gd")
	check(screens.progress_text(512, 1024).contains("50%") and screens.progress_text(10, -1).begins_with("Downloading"), "progress text")
	var screen: Variant = screens.new()
	root.add_child(screen)
	await process_frame
	var mod_count: int = content.get("mods").size()
	check(screen.item_count() == mod_count + 1 and screen.row(mod_count).text == screens.IMPORT_ROW, "import row after the mods")
	screen.select(mod_count)
	_press(KEY_ENTER)
	check(screen.mode == screens.Mode.SOURCE, "import row opens the source choice")
	check(screen.row(screen.item_count() - 1).text == screens.FROM_URL_ROW, "From URL offered")
	check(screen.item_count() == (2 if screens.file_picker_available() else 1), "From file shown only with a native file dialog")
	screen.select(screen.item_count() - 1)
	_press(KEY_ENTER)
	var edit: LineEdit = _find_line_edit(screen)
	check(screen.mode == screens.Mode.URL and edit != null and edit.visible and edit.has_focus(), "From URL shows a focused text field")
	_press(KEY_ENTER)
	check(screen.mode == screens.Mode.URL, "an empty link does not start a download")
	_press(KEY_ESCAPE)
	check(screen.mode == screens.Mode.SOURCE and not edit.visible, "Escape leaves the text field")
	_press(KEY_ESCAPE)
	check(screen.mode == screens.Mode.LIST and screen.selection == mod_count, "Escape returns to the list on the import row")
	var downloaded := _cache_copy(_zip("screen.zip", {"mod.json": JSON.stringify({"id": SCREEN_MOD_ID, "name": "ZZ Screen Pack"})}))
	var target: String = screen.mods_dir.path_join(SCREEN_MOD_ID)
	screen.finish_import(ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 200, downloaded, screen.mods_dir), downloaded, true)
	check(DirAccess.dir_exists_absolute(target) and not FileAccess.file_exists(downloaded), "download installed into the mods folder and its zip deleted")
	check(screen.mode == screens.Mode.LIST and screen.item_count() == mod_count + 2, "list refreshed with the new mod")
	check(screen.row(screen.selection).text.ends_with("ZZ Screen Pack"), "the new mod is selected")
	downloaded = _cache_copy(ZIPS.path_join("screen.zip"))
	screen.finish_import(ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 200, downloaded, screen.mods_dir), downloaded, true)
	check(screen.mode == screens.Mode.REPLACE and screen.row(0).text == "Replace " + SCREEN_MOD_ID, "reinstall asks yes/no")
	screen.select(1)
	_press(KEY_ENTER)
	check(screen.mode == screens.Mode.LIST and not FileAccess.file_exists(downloaded), "keeping the installed mod discards the download")
	screen.select(screen.item_count() - 1)
	_press(KEY_ENTER)
	_press(KEY_ESCAPE)
	check(screen.mode == screens.Mode.LIST and screen.get("_message").text.is_empty(), "stepping back clears the last result")
	downloaded = _cache_copy(ZIPS.path_join("screen.zip"))
	screen.finish_import(ModPackImporter.import_download(HTTPRequest.RESULT_SUCCESS, 200, downloaded, screen.mods_dir), downloaded, true)
	check(screen.mode == screens.Mode.REPLACE, "reinstall asks again")
	root.remove_child(screen)
	screen.free()
	check(not FileAccess.file_exists(downloaded), "leaving the screen at the replace prompt discards the download")
	ModPackImporter.remove_tree(target)
	content.set("mod_overrides_path", saved_overrides)
	content.call("scan")
	await process_frame


func _cache_copy(source: String) -> String:
	var path := ModPackImporter.download_path("https://example.test/screen-pack.zip")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.copy_absolute(source, path)
	return path


func _find_line_edit(node: Node) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit:
			return child
	return null


func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		root.push_input(event)


func _zip(file_name: String, files: Dictionary, folders: PackedStringArray = []) -> String:
	var path := ZIPS.path_join(file_name)
	var packer := ZIPPacker.new()
	packer.open(path)
	for folder in folders:
		packer.add_directory(folder)
	for entry: String in files:
		packer.start_file(entry)
		packer.write_file((files[entry] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()
	return path


static func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
