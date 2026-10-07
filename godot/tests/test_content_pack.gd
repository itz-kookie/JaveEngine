extends "res://tests/test_base.gd"

## Builds a full content pack in the mods folder from the Neon Steps demo files under a new song id, then plays it for 2 s under botplay.
const MOD_ID := "zz-content-pack-test"
const MOD_ROOT := TEST_HOME + "/mods/" + MOD_ID
const SONG_ID := "zz-pack-steps"
const WEEK_ID := "zz-pack-week"
const STAGE_ID := "zz-pack-stage"
const LOG_PATH := "user://saves/jave.log"
const START_TIMEOUT_MS := 15000
const PLAY_MS := 2000
## The menu art pack lives in a mod root of its own, so other installed mods cannot come before it.
const MENU_MODS := TEST_HOME + "/menu-pack-mods"
const MENU_MOD_ROOT := MENU_MODS + "/zz-menu-pack"
const MENU_ART := MENU_MOD_ROOT + "/assets/imported/menus"
const MENU_FILES: PackedStringArray = ["alphabet/glyphs.json", "alphabet/41.png", "buttons/story_mode/animation.json",
	"menuBG.png", "weeks/zz-menu-week.png"]

var _ran := false
var _content: Node
var _failed_message := ""


## Content and the scenes reference autoloads, which exist from the first frame.
func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_all()
	return false


func _run_all() -> void:
	_content = root.get_node("/root/Content")
	ModPackImporter.remove_tree(MOD_ROOT)
	_build_pack()
	_content.call("scan")
	var song: SongMeta = _content.call("find_song", SONG_ID)
	check(song != null, "pack song is listed")
	if song != null:
		_check_resolution(song)
		await _check_play(song)
	ModPackImporter.remove_tree(MOD_ROOT)
	_content.call("scan")
	check(_content.call("find_song", SONG_ID) == null and not DirAccess.dir_exists_absolute(MOD_ROOT), "pack removed")
	_check_menu_pack()
	# Let the audio server release stopped playbacks before quitting.
	await create_timer(0.2).timeout
	super._initialize()


func _build_pack() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/mods/jave-demo/songs/neon-steps/song.json"))
	manifest.merge({
		"id": SONG_ID, "title": "Pack Steps", "week": WEEK_ID, "stage": STAGE_ID,
		"audio": "songs/%s/Inst.ogg" % SONG_ID, "chart": "data/charts/%s.json" % SONG_ID,
		"stageImage": "assets/stages/pack.png",
		"playerVisual": "assets/characters/neon", "opponentVisual": "assets/characters/pulse",
		"playerIcon": "assets/icons/neon.png", "opponentIcon": "assets/icons/pulse.png",
	}, true)
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/mods/jave-demo/data/charts/neon-steps.json"))
	chart["song"] = SONG_ID
	_write(MOD_ROOT.path_join("mod.json"), JSON.stringify({"id": MOD_ID, "name": "ZZ Content Pack", "version": "1.0.0"}))
	_write(MOD_ROOT.path_join("songs/%s/song.json" % SONG_ID), JSON.stringify(manifest))
	_copy("res://content/mods/jave-demo/songs/neon-steps/Inst.ogg", MOD_ROOT.path_join("songs/%s/Inst.ogg" % SONG_ID))
	_write(MOD_ROOT.path_join("data/charts/%s.json" % SONG_ID), JSON.stringify(chart))
	_copy("res://content/mods/jave-demo/data/stages/neon.json", MOD_ROOT.path_join("data/stages/%s.json" % STAGE_ID))
	_write(MOD_ROOT.path_join("data/weeks.json"), JSON.stringify({"weeks": [{"id": WEEK_ID, "name": "Pack Week", "songs": [SONG_ID]}]}))
	_write(MOD_ROOT.path_join("data/cutscenes.json"), JSON.stringify({SONG_ID: {"before": "assets/videos/intro.ogv"}}))
	_copy_tree("res://content/mods/jave-demo/assets/demo/neon", MOD_ROOT.path_join("assets/characters/neon"))
	_copy_tree("res://content/mods/jave-demo/assets/demo/pulse", MOD_ROOT.path_join("assets/characters/pulse"))
	_copy("res://content/mods/jave-demo/assets/demo/neon/icon.png", MOD_ROOT.path_join("assets/icons/neon.png"))
	_copy("res://content/mods/jave-demo/assets/demo/pulse/icon.png", MOD_ROOT.path_join("assets/icons/pulse.png"))
	_copy("res://content/mods/jave-demo/assets/demo/stage.png", MOD_ROOT.path_join("assets/stages/pack.png"))
	_copy_tree("res://content/assets/demo/notes", MOD_ROOT.path_join("assets/imported/notes"))
	_copy("res://content/mods/jave-demo/assets/demo/stage.png", MOD_ROOT.path_join("assets/imported/menus/weeks/%s.png" % WEEK_ID))
	_write(MOD_ROOT.path_join("scripts/pack.lua"),
		"function on_song_start(id) if id == '%s' then jave_log('pack hook ' .. id) end end" % SONG_ID)


func _check_resolution(song: SongMeta) -> void:
	check(song.package_root == MOD_ROOT, "song remembers its package")
	for path: String in [song.audio_path, song.chart_path, song.stage_config_path, song.stage_image, song.player_visual,
			song.opponent_visual, song.player_icon, song.opponent_icon]:
		check(path.begins_with(MOD_ROOT + "/"), "resolves inside the pack: " + path)
	check(FileAccess.file_exists(_content.call("chart_path_for", song)), "chart found")
	check(not song.stage_layout.is_empty(), "pack stage layout applied")
	var week_ids := PackedStringArray()
	var pack_week: WeekMeta = null
	for week: WeekMeta in _content.get("weeks"):
		week_ids.append(week.id)
		if week.id == WEEK_ID:
			pack_week = week
	check(pack_week != null, "pack week is listed (got %s)" % [week_ids])
	if pack_week != null:
		check(pack_week.package_root == MOD_ROOT, "week remembers its package")
		check(pack_week.banner_path() == MOD_ROOT.path_join("assets/imported/menus/weeks/%s.png" % WEEK_ID), "pack week banner resolves inside the pack")
		check(_content.call("find_week_song", pack_week, SONG_ID) == song, "week song comes from the week's package")
		var shadow := SongMeta.new()
		shadow.id = SONG_ID
		shadow.package_root = Paths.CONTENT_ROOT
		var songs: Array[SongMeta] = _content.get("songs")
		var package_songs: Array[SongMeta] = _content.get("package_songs")
		songs.insert(0, shadow)
		package_songs.insert(0, shadow)
		check(_content.call("find_week_song", pack_week, SONG_ID) == song, "week song skips an earlier copy from another package")
		check(_content.call("find_week_song", WeekMeta.new(), SONG_ID) == shadow, "week without a package takes the first copy")
		songs.erase(shadow)
		package_songs.erase(shadow)
		var other_copy := SongMeta.new()
		other_copy.id = SONG_ID
		other_copy.package_root = Paths.CONTENT_ROOT
		package_songs.append(other_copy)
		var other_package_week := WeekMeta.new()
		other_package_week.package_root = Paths.CONTENT_ROOT
		check(_content.call("find_week_song", other_package_week, SONG_ID) == other_copy,
				"a week resolves a duplicate song from its own package")
		package_songs.erase(other_copy)
	var other_week := WeekMeta.from_json({"id": "zz-no-banner", "songs": [SONG_ID]}, MOD_ROOT)
	check(other_week.banner_path() == Ui.menu_asset("weeks/zz-no-banner.png"), "missing pack banner falls back to the menu art lookup")
	check(_content.call("cutscene_path", SONG_ID, false) == MOD_ROOT.path_join("assets/videos/intro.ogv"), "pack cutscene resolves inside the pack")
	check(_content.call("cutscene_path", SONG_ID, false, MOD_ROOT) == MOD_ROOT.path_join("assets/videos/intro.ogv"), "cutscene looked up from the given package")
	var strumline: GDScript = load("res://scenes/play/Strumline.gd")
	check(strumline.note_image_path("confirm", 3, song.package_root) == MOD_ROOT.path_join("assets/imported/notes/confirm_right.png"), "pack note art used")
	var host := root.get_node("/root/ModHost")
	var host_script: GDScript = load("res://autoload/ModHost.gd")
	var scripts: PackedStringArray = host_script.script_paths("res://content", host.call("enabled_mod_roots"))
	check(scripts.has(MOD_ROOT.path_join("scripts/pack.lua")), "pack script is loaded with the mods")
	# Scripts load at startup; this run started before the pack existed, so it is loaded by hand.
	host.call("load_scripts", PackedStringArray([MOD_ROOT.path_join("scripts/pack.lua")]))


func _check_play(song: SongMeta) -> void:
	var log_mark := _log_size()
	var play: Node = load("res://scenes/play/PlayScene.tscn").instantiate()
	play.set("song", song)
	play.set("botplay", true)
	play.connect("failed", func(message: String) -> void: _failed_message = message)
	root.add_child(play)
	var started := Time.get_ticks_msec()
	while not play.call("is_playing") and _failed_message.is_empty() and Time.get_ticks_msec() - started < START_TIMEOUT_MS:
		await process_frame
	check(play.call("is_playing"), "pack song starts (%s)" % _failed_message)
	var playing_since := Time.get_ticks_msec()
	while _failed_message.is_empty() and Time.get_ticks_msec() - playing_since < PLAY_MS:
		await process_frame
	var gameplay: Gameplay = play.get("gameplay")
	check(_failed_message.is_empty() and play.call("is_playing"), "pack song still playing after 2 s")
	check(gameplay != null and gameplay.song_time_ms > 1000.0, "song clock advanced")
	check(gameplay != null and gameplay.misses == 0, "botplay misses nothing")
	var assets: Object = play.get("_assets")
	check(assets.get("stream") != null and assets.get("stage_texture") != null and assets.get("player").get("frames") != null, "pack audio, stage image and characters loaded")
	var strumline: Node = play.get_node("Overlay/Strumline")
	var mod_note := TextureCache.get_texture(MOD_ROOT.path_join("assets/imported/notes/note_left.png"))
	check((strumline.get("_note_textures") as Array)[0] == mod_note, "strumline draws the pack's note art")
	var lines := _log_since(log_mark)
	check(lines.has("pack hook " + SONG_ID), "pack Lua hook ran on song start")
	var errors := lines.filter(func(line: String) -> bool: return line.contains("error") or line.contains("Could not"))
	check(errors.is_empty(), "no errors logged: %s" % [errors])
	play.queue_free()
	await process_frame


func _check_menu_pack() -> void:
	var saved_roots: PackedStringArray = _content.get("mod_roots")
	_content.set("mod_roots", PackedStringArray([MENU_MODS]))
	ModPackImporter.remove_tree(MENU_MODS)
	_build_menu_pack()
	_content.call("scan")
	for relative in MENU_FILES:
		check(Ui.menu_asset(relative) == MENU_ART.path_join(relative), "menu pack resolves " + relative)
	check(FunkinLabel.glyphs_folder() == MENU_ART.path_join("alphabet"), "alphabet read from the menu pack")
	var label := FunkinLabel.new()
	root.add_child(label)
	label.show_text("AB A", 400.0, 60.0)
	var images: Array[TextureRect] = []
	var labels := 0
	for child in label.get_children():
		if child is TextureRect:
			images.append(child)
		elif child is Label:
			labels += 1
	var glyph_a := TextureCache.get_texture(MENU_ART.path_join("alphabet/41.png"))
	check(labels == 0 and images.size() == 3, "alphabet text drawn with glyph images (%d images, %d labels)" % [images.size(), labels])
	check(images.size() == 3 and images[0].texture == glyph_a and images[2].texture == glyph_a
		and images[1].texture == TextureCache.get_texture(MENU_ART.path_join("alphabet/42.png")), "glyphs come from the pack's alphabet folder")
	label.free()
	var title_screen: GDScript = load("res://scenes/menus/TitleScreen.gd")
	var button: CharacterAsset = title_screen._load_button(0)
	check(button != null and button.base == MENU_ART.path_join("buttons/story_mode"), "title button read from the menu pack")
	check(Ui.menu_texture("menuBG.png") == TextureCache.get_texture(MENU_ART.path_join("menuBG.png")), "backdrop read from the menu pack")
	var backdrop: Control = load("res://scenes/menus/MenuBackdrop.gd").new()
	root.add_child(backdrop)
	backdrop.call("show_style", "menuBG.png")
	check((backdrop.get("_art") as TextureRect).texture == Ui.menu_texture("menuBG.png"), "backdrop draws the pack's art")
	backdrop.free()
	check(WeekMeta.from_json({"id": "zz-menu-week"}).banner_path() == MENU_ART.path_join("weeks/zz-menu-week.png"), "week banner falls back to the menu pack")
	check(WeekMeta.from_json({"id": "zz-menu-week"}, MOD_ROOT).banner_path() == MENU_ART.path_join("weeks/zz-menu-week.png"),
		"mod week without its own banner uses the menu pack")

	ModPackImporter.remove_tree(MENU_MODS)
	TextureCache.forget_under(MENU_MODS)
	_content.call("scan")
	var user_menus: String = root.get_node("/root/Paths").call("user_mirror", Ui.MENUS_ROOT)
	for relative in MENU_FILES:
		var expected := ""
		for candidate: String in [user_menus.path_join(relative)]:
			if FileAccess.file_exists(candidate):
				expected = candidate
				break
		check(Ui.menu_asset(relative) == expected, "after removal %s falls back to %s" % [relative, expected if not expected.is_empty() else "nothing"])
	check(not FunkinLabel.glyphs_folder().begins_with(MENU_MODS), "alphabet no longer read from the removed pack")
	var fallback: CharacterAsset = title_screen._load_button(0)
	check(fallback == null or not fallback.base.begins_with(MENU_MODS), "title button no longer read from the removed pack")
	_content.set("mod_roots", saved_roots)
	_content.call("scan")


func _build_menu_pack() -> void:
	_write(MENU_MOD_ROOT.path_join("mod.json"), JSON.stringify({"id": "zz-menu-pack", "name": "ZZ Menu Pack", "version": "1.0.0"}))
	_write(MENU_ART.path_join("alphabet/glyphs.json"), JSON.stringify({
		"A": {"file": "41.png", "width": 40, "height": 50}, "B": {"file": "42.png", "width": 36, "height": 50}}))
	_write_png(MENU_ART.path_join("alphabet/41.png"), Vector2i(40, 50), Color.RED)
	_write_png(MENU_ART.path_join("alphabet/42.png"), Vector2i(36, 50), Color.BLUE)
	_write(MENU_ART.path_join("buttons/story_mode/animation.json"), JSON.stringify({
		"idle": {"frames": 1, "fps": 24, "loop": true, "width": 60, "height": 12}}))
	_write_png(MENU_ART.path_join("buttons/story_mode/idle/frame_000.png"), Vector2i(60, 12), Color.GREEN)
	_write_png(MENU_ART.path_join("menuBG.png"), Vector2i(32, 18), Color.YELLOW)
	_write_png(MENU_ART.path_join("weeks/zz-menu-week.png"), Vector2i(48, 12), Color.WHITE)


static func _write_png(path: String, image_size: Vector2i, color: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(path)


func _log_size() -> int:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	return file.get_length() if file != null else 0


func _log_since(mark: int) -> Array:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return []
	file.seek(mark)
	return Array(file.get_buffer(file.get_length() - mark).get_string_from_utf8().split("\n", false))


func _copy_tree(from: String, to: String) -> void:
	for folder in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(folder), to.path_join(folder))
	for file in DirAccess.get_files_at(from):
		_copy(from.path_join(file), to.path_join(file))


func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var error := DirAccess.copy_absolute(from, to)
	check(error == OK, "copied %s (%s)" % [from.get_file(), error_string(error)])


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
