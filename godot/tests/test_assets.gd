extends "res://tests/test_base.gd"

const TEMP_DIR := "user://test_assets_tmp"


func run() -> void:
	var base := TEMP_DIR.path_join("character")
	var red := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	DirAccess.make_dir_recursive_absolute(base.path_join("idle"))
	DirAccess.make_dir_recursive_absolute(base.path_join("left"))
	red.save_png(base.path_join("idle/frame_000.png"))
	red.save_png(base.path_join("idle/frame_001.png"))
	blue.save_png(base.path_join("idle/frame_002.png"))
	red.save_png(base.path_join("left/frame_000.png"))
	var json := FileAccess.open(base.path_join("animation.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify({"idle": {"fps": 12, "loop": true}}))
	json.close()
	_test_identical_frames_share_textures(base)
	_test_note_images_fall_back_to_demo()
	_remove_dir(TEMP_DIR)


func _test_identical_frames_share_textures(base: String) -> void:
	TextureCache.prune_frames()
	var cached_before := TextureCache.frame_count()
	var asset := CharacterAsset.new(base)
	asset.load_from_disk()
	asset.build_frames()
	var frames := asset.frames
	check(frames.get_frame_count(&"idle") == 3 and frames.get_frame_count(&"left") == 1, "every frame file becomes a frame")
	check(frames.get_frame_texture(&"idle", 0) == frames.get_frame_texture(&"idle", 1), "identical frames share one texture")
	check(frames.get_frame_texture(&"idle", 0) == frames.get_frame_texture(&"left", 0), "identical frames share across poses")
	check(frames.get_frame_texture(&"idle", 0) != frames.get_frame_texture(&"idle", 2), "different frames get their own texture")
	check(TextureCache.frame_count() == cached_before + 2, "two distinct images cached")
	check_near(frames.get_animation_speed(&"idle"), 12.0, "fps from animation.json")
	var again := CharacterAsset.new(base)
	again.load_from_disk()
	again.build_frames()
	check(again.frames.get_frame_texture(&"idle", 2) == frames.get_frame_texture(&"idle", 2), "a second load reuses cached textures")
	TextureCache.prune_frames()
	check(TextureCache.frame_count() == cached_before + 2, "prune keeps frames still in use")
	asset = null
	frames = null
	again = null
	TextureCache.prune_frames()
	check(TextureCache.frame_count() == cached_before, "prune releases frames nothing uses")


func _test_note_images_fall_back_to_demo() -> void:
	# Loaded at runtime because Strumline references autoloads, which -s scripts cannot see at compile time.
	var strumline: GDScript = load("res://scenes/play/Strumline.gd")
	var demo_dir := "res://content/assets/demo/notes"
	var missing := 0
	for kind: String in ["receptor", "press", "confirm", "note", "hold", "hold_end"]:
		for lane in 4:
			if TextureCache.get_texture(demo_dir.path_join("%s_%s.png" % [kind, strumline.LANE_NAMES[lane]])) == null:
				missing += 1
	check(missing == 0, "every demo note image loads")
	var imported_dir := TEMP_DIR.path_join("notes")
	DirAccess.make_dir_recursive_absolute(imported_dir)
	var dirs := PackedStringArray([imported_dir, demo_dir])
	check(strumline.pick_note_image(dirs, "note", 2) == demo_dir.path_join("note_up.png"), "missing imported note art falls back to the demo arrows")
	Image.create(2, 2, false, Image.FORMAT_RGBA8).save_png(imported_dir.path_join("note_up.png"))
	check(strumline.pick_note_image(dirs, "note", 2) == imported_dir.path_join("note_up.png"), "imported note art wins when present")
	check(strumline.pick_note_image(dirs, "note", 0) == demo_dir.path_join("note_left.png"), "fallback is chosen per file")
	_test_note_dir_order(strumline, demo_dir)


func _test_note_dir_order(strumline: GDScript, demo_dir: String) -> void:
	var user_dir := TEST_HOME + "/content/assets/imported/notes"
	var base_dirs: PackedStringArray = strumline.note_dirs("res://content")
	check(base_dirs == PackedStringArray([user_dir, demo_dir]),
		"songs use the user override then the engine-owned demo arrows (got %s)" % [base_dirs])
	check(strumline.note_dirs("") == base_dirs, "no package means the base lookup")
	var mod_root := TEMP_DIR.path_join("mod")
	var mod_dirs: PackedStringArray = strumline.note_dirs(mod_root)
	check(mod_dirs.size() == 3 and mod_dirs[0] == mod_root.path_join("assets/imported/notes") and mod_dirs[1] == user_dir,
		"a mod song looks in its own package first (got %s)" % [mod_dirs])
	var mod_notes := mod_dirs[0]
	DirAccess.make_dir_recursive_absolute(mod_notes)
	Image.create(2, 2, false, Image.FORMAT_RGBA8).save_png(mod_notes.path_join("hold_down.png"))
	check(strumline.note_image_path("hold", 1, mod_root) == mod_notes.path_join("hold_down.png"), "mod note art wins for its own songs")
	check(strumline.note_image_path("hold", 1, "res://content") != mod_notes.path_join("hold_down.png"), "mod note art is not used for other songs")
	var had_user_dir := DirAccess.dir_exists_absolute(user_dir)
	var user_file := user_dir.path_join("hold_end_right.png")
	if not FileAccess.file_exists(user_file):
		DirAccess.make_dir_recursive_absolute(user_dir)
		Image.create(2, 2, false, Image.FORMAT_RGBA8).save_png(user_file)
		check(strumline.note_image_path("hold_end", 3, "res://content") == user_file, "user://content note art wins over the content folder")
		check(strumline.note_image_path("hold_end", 3, mod_root) == user_file, "a mod without that file falls through to user://content")
		DirAccess.remove_absolute(user_file)
		if not had_user_dir:
			_remove_empty_parents(user_dir, TEST_HOME)


func _remove_empty_parents(path: String, stop: String) -> void:
	var dir := path
	while dir != stop and dir.begins_with(stop) and DirAccess.get_files_at(dir).is_empty() and DirAccess.get_directories_at(dir).is_empty():
		DirAccess.remove_absolute(dir)
		dir = dir.get_base_dir()


func _remove_dir(path: String) -> void:
	for folder in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
