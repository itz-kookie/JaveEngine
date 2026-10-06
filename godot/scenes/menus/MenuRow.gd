class_name MenuRow
extends Control

const MARKER_RECT := Rect2(-28.0, 0.0, 40.0, 55.0)
const ICON_SIZE := 50.0

var text := ""
var selected_height := 56.0
var unselected_height := 43.0

var _label := FunkinLabel.new()
var _marker: Label
var _icon: TextureRect
var _art: TextureRect
var _width := 0.0
var _selected := false
var _dirty := true


func _init(value: String, list_width: float) -> void:
	text = value
	_width = list_width
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker = Ui.text(self, ">", MARKER_RECT, 32, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_marker.visible = false
	add_child(_label)


func set_text(value: String) -> void:
	if value != text:
		text = value
		_dirty = true


## Small picture after the label, as Freeplay shows the opponent icon.
func set_icon(texture: Texture2D) -> void:
	if _icon == null:
		_icon = Ui.fitted_image(self, null, Rect2())
	_icon.texture = texture
	_dirty = true


## Replaces the label with a banner image, as Story does for weeks with imported art.
func set_art(texture: Texture2D, selected: float, unselected: float) -> void:
	if texture == null:
		return
	_art = Ui.fitted_image(self, null, Rect2())
	_art.texture = texture
	selected_height = selected
	unselected_height = unselected
	_label.visible = false
	_dirty = true


func place(menu_x: float, y: float, offset: float, selected: bool) -> void:
	position = Vector2(menu_x, y)
	if selected != _selected or _dirty:
		_selected = selected
		_dirty = false
		_marker.visible = selected
		_refresh_size()
	var height := selected_height if selected else unselected_height
	if _art != null:
		Ui.fit_image(_art, _art.texture, Rect2(offset, 0.0, _width - 85.0, height))
		return
	_label.position.x = offset
	if _icon != null:
		var icon_x := minf(_width - 45.0, offset + _label.drawn_width + 15.0)
		Ui.fit_image(_icon, _icon.texture, Rect2(icon_x, 7.0, ICON_SIZE, ICON_SIZE))


func _refresh_size() -> void:
	if _art == null:
		_label.show_text(text, _width - 70.0, selected_height if _selected else unselected_height)
