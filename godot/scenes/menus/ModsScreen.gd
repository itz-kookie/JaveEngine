class_name ModsScreen
extends MenuScreen

## LIST shows the mods plus the import row; the other modes are the steps of an import.
enum Mode { LIST, SOURCE, URL, DOWNLOADING, REPLACE }

const HINT := "Enter toggles a package. Import adds a .zip content pack. Restart to reload mod scripts."
const EMPTY_HINT := "No mods installed. Drop a mod folder into user://mods/<mod-id>/, or import a .zip content pack."
const IMPORT_ROW := "Import content pack"
const FROM_FILE_ROW := "From file"
const FROM_URL_ROW := "From URL"
const DOWNLOAD_ROW := "Download"
const CANCEL_DOWNLOAD_ROW := "Cancel download"
const KEEP_ROW := "Keep installed version"
const ZIP_FILTER := "*.zip;ZIP archives;application/zip"
const URL_PLACEHOLDER := "https://example.com/my-pack.zip"
const MAX_REDIRECTS := 5
## A download that receives nothing for this long is abandoned.
const STALL_TIMEOUT_MS := 30000
const EMPTY_COLOR := Color8(190, 198, 225)
const DESCRIPTION_COLOR := Color8(160, 170, 201)
const ENABLED_COLOR := Color8(105, 235, 176)
const DISABLED_COLOR := Color8(255, 135, 160)

var mode := Mode.LIST
var mods_dir := Paths.user("mods")

var _name: Label
var _byline: Label
var _description: Label
var _status: Label
var _message: Label
var _url_edit: LineEdit
var _http: HTTPRequest
## Zip waiting for the replace answer, and whether it is a download to delete afterwards.
var _pending_zip := ""
var _pending_is_download := false
var _pending_mod_id := ""
var _shown_bytes := -1
var _last_progress_ms := 0


static func importer_available() -> bool:
	return not OS.has_feature("web")


static func file_picker_available() -> bool:
	return importer_available() and DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


static func row_label(mod: ModInfo) -> String:
	return ("●  " if mod.enabled else "○  ") + mod.name


static func progress_text(done: int, total: int) -> String:
	if total > 0:
		return "Downloading %s of %s (%d%%)" % [String.humanize_size(done), String.humanize_size(total), done * 100 / total]
	return "Downloading %s" % String.humanize_size(done)


func labels_for(next: Mode) -> PackedStringArray:
	match next:
		Mode.SOURCE:
			return PackedStringArray([FROM_FILE_ROW, FROM_URL_ROW]) if file_picker_available() else PackedStringArray([FROM_URL_ROW])
		Mode.URL:
			return PackedStringArray([DOWNLOAD_ROW])
		Mode.DOWNLOADING:
			return PackedStringArray([CANCEL_DOWNLOAD_ROW])
		Mode.REPLACE:
			return PackedStringArray(["Replace " + _pending_mod_id, KEEP_ROW])
	var labels := PackedStringArray()
	for mod in Content.mods:
		labels.append(row_label(mod))
	if importer_available():
		labels.append(IMPORT_ROW)
	return labels


func _build() -> void:
	Ui.menu_header(self, "MODS", HINT)
	build_list(labels_for(Mode.LIST), 205.0, Ui.SCREEN_SIZE.x * 0.42)
	var x := Ui.SCREEN_SIZE.x - 515.0
	Ui.box(self, Rect2(x, 205.0, 450.0, 345.0), Ui.BAR_COLOR)
	_name = Ui.text(self, "", Rect2(x + 30.0, 230.0, 390.0, 48.0), 29, Ui.WHITE, true)
	_byline = Ui.text(self, "", Rect2(x + 30.0, 280.0, 390.0, 30.0), 16, Ui.accent)
	_description = Ui.wrapped_text(self, "", Rect2(x + 30.0, 325.0, 390.0, 75.0), 17, DESCRIPTION_COLOR)
	_status = Ui.text(self, "", Rect2(x + 30.0, 410.0, 180.0, 30.0), 16, ENABLED_COLOR, true)
	_url_edit = _make_url_edit(Rect2(x + 30.0, 405.0, 390.0, 40.0))
	_message = Ui.wrapped_text(self, "", Rect2(x + 30.0, 460.0, 390.0, 75.0), 16, EMPTY_COLOR)
	_selection_changed()


func _make_url_edit(rect: Rect2) -> LineEdit:
	var edit := LineEdit.new()
	edit.position = rect.position
	edit.size = rect.size
	edit.placeholder_text = URL_PLACEHOLDER
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	edit.add_theme_font_size_override(&"font_size", 16)
	edit.visible = false
	edit.text_submitted.connect(_start_download)
	edit.gui_input.connect(_on_url_input)
	add_child(edit)
	return edit


func _selection_changed() -> void:
	if mode == Mode.LIST and selection < Content.mods.size():
		_show_mod(Content.mods[selection])
		return
	_show_panel("Import content pack", ".zip holding a mod folder", _import_description())
	_status.visible = false


func _show_mod(mod: ModInfo) -> void:
	_show_panel(mod.name, "v%s  •  %s" % [mod.version, mod.author], mod.description)
	_status.visible = true
	_status.text = "ENABLED" if mod.enabled else "DISABLED"
	_status.add_theme_color_override(&"font_color", ENABLED_COLOR if mod.enabled else DISABLED_COLOR)


func _show_panel(title: String, byline: String, description: String) -> void:
	_name.text = title
	_byline.text = byline
	_description.text = description


func _import_description() -> String:
	match mode:
		Mode.SOURCE:
			return "From file opens the system file picker. From URL downloads a link to a .zip." if file_picker_available() \
				else "From URL downloads a link to a .zip."
		Mode.URL:
			return "Type or paste a link to a .zip file, then press Enter."
		Mode.DOWNLOADING:
			return "The pack is installed as soon as the download finishes."
		Mode.REPLACE:
			return "%s is already installed. Replace it with the files from this pack?" % _pending_mod_id
	if Content.mods.is_empty():
		return EMPTY_HINT
	return "Installs a .zip content pack into the mods folder." if importer_available() else EMPTY_HINT


func show_message(text: String, color := EMPTY_COLOR) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", color)


func set_mode(next: Mode, index := 0) -> void:
	mode = next
	replace_list(labels_for(next), index)
	_url_edit.visible = next == Mode.URL
	if next == Mode.URL:
		_url_edit.grab_focus()
		_url_edit.edit()
	elif _url_edit.has_focus():
		_url_edit.release_focus()
	_selection_changed()


func _on_key(key: Key) -> void:
	if MenuInput.is_back(key) and mode != Mode.LIST:
		_step_back()
		return
	super._on_key(key)


## Escape inside the URL field leaves it, like Escape anywhere else on this screen.
func _on_url_input(event: InputEvent) -> void:
	if MenuInput.is_back(MenuInput.key_of(event)):
		_url_edit.accept_event()
		_step_back()


func _step_back() -> void:
	show_message("")
	match mode:
		Mode.SOURCE:
			set_mode(Mode.LIST, Content.mods.size())
		Mode.URL:
			set_mode(Mode.SOURCE, labels_for(Mode.SOURCE).find(FROM_URL_ROW))
		Mode.DOWNLOADING:
			cancel_download()
		Mode.REPLACE:
			_keep_installed()


func _confirm() -> void:
	match mode:
		Mode.LIST:
			if selection < Content.mods.size():
				_toggle_selected()
			elif importer_available():
				show_message("")
				set_mode(Mode.SOURCE)
		Mode.SOURCE:
			if labels_for(Mode.SOURCE)[selection] == FROM_FILE_ROW:
				_open_file_picker()
			else:
				set_mode(Mode.URL)
		Mode.URL:
			_start_download(_url_edit.text)
		Mode.DOWNLOADING:
			cancel_download()
		Mode.REPLACE:
			if selection == 0:
				import_pack(_pending_zip, true, _pending_is_download)
			else:
				_keep_installed()


func _toggle_selected() -> void:
	Content.toggle_mod(selection)
	refresh_row(selection, row_label(Content.mods[selection]))
	_selection_changed()


func _open_file_picker() -> void:
	var error := DisplayServer.file_dialog_show("Import content pack", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), "",
		false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray([ZIP_FILTER]), _on_file_chosen)
	if error != OK:
		show_message("Could not open the file picker (%s)." % error_string(error), DISABLED_COLOR)


func _on_file_chosen(chosen: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if chosen and not paths.is_empty():
		import_pack.call_deferred(paths[0], false, false)


## Installs the pack at zip_path, asking first when its mod id is already installed.
func import_pack(zip_path: String, replace: bool, is_download: bool) -> void:
	finish_import(ModPackImporter.import_zip(zip_path, mods_dir, replace), zip_path, is_download)


func finish_import(result: ModPackImporter.Result, zip_path: String, is_download: bool) -> void:
	if result.needs_replace:
		_pending_zip = zip_path
		_pending_is_download = is_download
		_pending_mod_id = result.mod_id
		set_mode(Mode.REPLACE)
		show_message(result.summary())
		return
	_pending_zip = ""
	if is_download:
		DirAccess.remove_absolute(zip_path)
	Log.info("Content pack: " + result.summary())
	if not result.ok():
		set_mode(Mode.URL if is_download else Mode.SOURCE)
		show_message(result.summary(), DISABLED_COLOR)
		return
	TextureCache.forget_under(result.target)
	Content.scan()
	set_mode(Mode.LIST, _mod_index(result.target))
	show_message(result.summary() + " Restart to load its scripts.", ENABLED_COLOR)


func _keep_installed() -> void:
	if _pending_is_download:
		DirAccess.remove_absolute(_pending_zip)
	_pending_zip = ""
	set_mode(Mode.LIST, _mod_index(mods_dir.path_join(_pending_mod_id)))
	show_message("Kept the installed %s." % _pending_mod_id)


func _mod_index(root: String) -> int:
	for index in Content.mods.size():
		if Content.mods[index].root == root:
			return index
	return Content.mods.size()


func _start_download(url: String) -> void:
	var rejection := ModPackImporter.url_rejection(url)
	if not rejection.is_empty():
		show_message(rejection, DISABLED_COLOR)
		return
	DirAccess.make_dir_recursive_absolute(ModPackImporter.CACHE_DIR)
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.max_redirects = MAX_REDIRECTS
	_http.body_size_limit = ModPackImporter.MAX_TOTAL_BYTES
	_http.download_file = ModPackImporter.download_path(url)
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	var error := _http.request(url.strip_edges())
	if error != OK:
		_free_http()
		show_message("Could not start the download (%s)." % error_string(error), DISABLED_COLOR)
		return
	set_mode(Mode.DOWNLOADING)
	_shown_bytes = 0
	_last_progress_ms = Time.get_ticks_msec()
	show_message(progress_text(0, -1))


func _on_download_completed(http_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var path := _http.download_file
	_free_http()
	finish_import(ModPackImporter.import_download(http_result, response_code, path, mods_dir), path, true)


func cancel_download() -> void:
	_abandon_download("Download cancelled.", EMPTY_COLOR)


func _abandon_download(message: String, color: Color) -> void:
	if _http == null:
		return
	_http.cancel_request()
	var path := _http.download_file
	_free_http()
	DirAccess.remove_absolute(path)
	set_mode(Mode.URL)
	show_message(message, color)


func _free_http() -> void:
	remove_child(_http)
	_http.queue_free()
	_http = null


func _process(delta: float) -> void:
	super._process(delta)
	if _http == null or mode != Mode.DOWNLOADING:
		return
	var downloaded := _http.get_downloaded_bytes()
	var now := Time.get_ticks_msec()
	if downloaded != _shown_bytes:
		_shown_bytes = downloaded
		_last_progress_ms = now
		_message.text = progress_text(downloaded, _http.get_body_size())
	elif now - _last_progress_ms > STALL_TIMEOUT_MS:
		_abandon_download("Import failed: download failed (no response).", DISABLED_COLOR)


func _exit_tree() -> void:
	if _http != null:
		_http.cancel_request()
		DirAccess.remove_absolute(_http.download_file)
	if _pending_is_download and not _pending_zip.is_empty():
		DirAccess.remove_absolute(_pending_zip)
