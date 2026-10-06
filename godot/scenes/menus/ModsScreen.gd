class_name ModsScreen
extends MenuScreen

const EMPTY_COLOR := Color8(190, 198, 225)
const DESCRIPTION_COLOR := Color8(160, 170, 201)
const ENABLED_COLOR := Color8(105, 235, 176)
const DISABLED_COLOR := Color8(255, 135, 160)

var _name: Label
var _byline: Label
var _description: Label
var _status: Label


func _build() -> void:
	Ui.menu_header(self, "MODS", "Enter toggles a package. Restart to reload its scripts.")
	if Content.mods.is_empty():
		Ui.text(self, "Drop packages into mods/<mod-id>/", Rect2(64.0, 240.0, 800.0, 50.0), 24, EMPTY_COLOR)
		return
	var labels := PackedStringArray()
	for mod in Content.mods:
		labels.append(row_label(mod))
	build_list(labels, 205.0, Ui.SCREEN_SIZE.x * 0.42)
	var x := Ui.SCREEN_SIZE.x - 515.0
	Ui.box(self, Rect2(x, 205.0, 450.0, 260.0), Ui.BAR_COLOR)
	_name = Ui.text(self, "", Rect2(x + 30.0, 230.0, 390.0, 48.0), 29, Ui.WHITE, true)
	_byline = Ui.text(self, "", Rect2(x + 30.0, 280.0, 390.0, 30.0), 16, Ui.accent)
	_description = Ui.wrapped_text(self, "", Rect2(x + 30.0, 325.0, 390.0, 75.0), 17, DESCRIPTION_COLOR)
	_status = Ui.text(self, "", Rect2(x + 30.0, 410.0, 180.0, 30.0), 16, ENABLED_COLOR, true)
	_selection_changed()


static func row_label(mod: ModInfo) -> String:
	return ("●  " if mod.enabled else "○  ") + mod.name


func _selection_changed() -> void:
	var mod := Content.mods[selection]
	_name.text = mod.name
	_byline.text = "v%s  •  %s" % [mod.version, mod.author]
	_description.text = mod.description
	_status.text = "ENABLED" if mod.enabled else "DISABLED"
	_status.add_theme_color_override(&"font_color", ENABLED_COLOR if mod.enabled else DISABLED_COLOR)


func _confirm() -> void:
	if selection >= Content.mods.size():
		return
	Content.toggle_mod(selection)
	refresh_row(selection, row_label(Content.mods[selection]))
	_selection_changed()
