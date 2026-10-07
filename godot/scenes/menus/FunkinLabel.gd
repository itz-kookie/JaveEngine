## Text drawn with the imported alphabet glyphs, or a plain bold Label when they are not installed.
## The glyph images are read from the folder of whichever alphabet/glyphs.json the menu art lookup finds.
class_name FunkinLabel
extends Control

const GLYPHS_FILE := "alphabet/glyphs.json"
const SPACE_WIDTH := 36.0
const GLYPH_GAP := 7.0
const GLYPH_HEIGHT := 80.0
const DEFAULT_GLYPH_SIZE := Vector2(40.0, 65.0)
const TEXT_SCALE := 0.7
const OUTLINE_COLOR := Color8(22, 18, 31)

static var _glyphs: Dictionary = {}
static var _glyphs_folder := ""
static var _glyphs_loaded := false

var drawn_width := 0.0

var _text := ""
var _keys := PackedStringArray()
var _nodes: Array[Control] = []
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_text(value: String, max_width: float, height: float) -> void:
	if value != _text or (_label == null and _nodes.is_empty()):
		_text = value
		_rebuild()
	if _label != null:
		_fit_label(max_width, height)
	else:
		_layout_glyphs(max_width, height)
	size = Vector2(drawn_width, height)


static func glyphs() -> Dictionary:
	if not _glyphs_loaded:
		_glyphs_loaded = true
		var path := Ui.menu_asset(GLYPHS_FILE)
		var json: Variant = JsonRead.load_file(path)
		if json is Dictionary:
			_glyphs = json
			_glyphs_folder = path.get_base_dir()
	return _glyphs


## Folder of the loaded glyphs.json; empty when no alphabet is installed.
static func glyphs_folder() -> String:
	glyphs()
	return _glyphs_folder


## Makes the next label read the alphabet afresh, as after a mod is imported, enabled or disabled.
static func forget_glyphs() -> void:
	_glyphs = {}
	_glyphs_folder = ""
	_glyphs_loaded = false


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_nodes.clear()
	_keys.clear()
	_label = null
	if glyphs().is_empty():
		_label = _make_label(_text)
		return
	for letter in _text:
		var key := letter.to_upper() if letter.unicode_at(0) < 128 else "?"
		_keys.append(key)
		_nodes.append(null if key == " " else _make_glyph(key, letter))


func _make_glyph(key: String, letter: String) -> Control:
	var file := JsonRead.string(JsonRead.object(_glyphs, key), "file")
	if file.is_empty():
		var label := _make_label(letter)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return label
	var image := TextureRect.new()
	image.texture = TextureCache.get_texture(_glyphs_folder.path_join(file))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	return image


func _make_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", Ui.bold_font())
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", OUTLINE_COLOR)
	add_child(label)
	return label


func _fit_label(max_width: float, height: float) -> void:
	var font_size := maxi(1, int(height * TEXT_SCALE))
	var width := Ui.bold_font().get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width > max_width and width > 0.0:
		font_size = maxi(1, int(font_size * max_width / width))
		width = Ui.bold_font().get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label.add_theme_font_size_override(&"font_size", font_size)
	_label.add_theme_constant_override(&"outline_size", maxi(2, font_size / 8))
	_label.position = Vector2.ZERO
	_label.size = Vector2(width, height)
	drawn_width = width


func _layout_glyphs(max_width: float, height: float) -> void:
	var natural := 0.0
	for key in _keys:
		natural += SPACE_WIDTH if key == " " else _glyph_size(key).x + GLYPH_GAP
	var scale_factor := minf(height / GLYPH_HEIGHT, max_width / maxf(1.0, natural))
	var x := 0.0
	for index in _keys.size():
		var node := _nodes[index]
		if node == null:
			x += SPACE_WIDTH * scale_factor
			continue
		var glyph_size := _glyph_size(_keys[index]) * scale_factor
		if node is Label:
			(node as Label).add_theme_font_size_override(&"font_size", maxi(1, int(height * TEXT_SCALE)))
			node.position = Vector2(x, 0.0)
			node.size = Vector2(glyph_size.x, height)
		else:
			node.position = Vector2(x, height - glyph_size.y)
			node.size = glyph_size
		x += glyph_size.x + GLYPH_GAP * scale_factor
	drawn_width = x


static func _glyph_size(key: String) -> Vector2:
	var glyph := JsonRead.object(_glyphs, key)
	return Vector2(JsonRead.number(glyph, "width", DEFAULT_GLYPH_SIZE.x), JsonRead.number(glyph, "height", DEFAULT_GLYPH_SIZE.y))
