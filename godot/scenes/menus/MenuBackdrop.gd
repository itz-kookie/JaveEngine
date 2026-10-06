## Full-screen background behind menus: the warm menu gradient with optional art, or dark drifting circles.
class_name MenuBackdrop
extends Control

const MENU_TOP := Color8(252, 219, 92)
const MENU_BOTTOM := Color8(219, 141, 180)
const DARK_TOP := Color8(10, 13, 34)
const DARK_BOTTOM := Color8(25, 12, 43)
const CIRCLE_BASE := Color8(17, 20, 48)
const LINE_BASE := Color8(20, 24, 50)
const CIRCLE_COUNT := 11

var _time := 0.0
var _dark := false
var _menu_gradient := _gradient_texture(MENU_TOP, MENU_BOTTOM)
var _dark_gradient := _gradient_texture(DARK_TOP, DARK_BOTTOM)
var _gradient: Texture2D
var _art: TextureRect
var _circle_colors: Array[Color] = []
var _line_color: Color


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Ui.SCREEN_SIZE
	_gradient = _menu_gradient
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_cache_colors()
	ModHost.accent_changed.connect(_on_accent_changed)


## art_file names an image under assets/imported/menus; empty selects the dark style.
func show_style(art_file: String) -> void:
	_dark = art_file.is_empty()
	_gradient = _dark_gradient if _dark else _menu_gradient
	_art.texture = null if _dark else Ui.menu_texture(art_file)
	_art.visible = _art.texture != null
	_cache_colors()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if _dark:
		queue_redraw()
	elif _art.visible:
		var zoom := 1.025 + sin(_time * 1.7) * 0.004
		_art.position = Ui.SCREEN_SIZE * (1.0 - zoom) * 0.5
		_art.size = Ui.SCREEN_SIZE * zoom


func _draw() -> void:
	draw_texture_rect(_gradient, Rect2(Vector2.ZERO, Ui.SCREEN_SIZE), false)
	if not _dark:
		return
	for index in CIRCLE_COUNT:
		var phase := _time * (0.14 + index * 0.008) + index * 1.7
		var diameter := 110.0 + (index % 4) * 38.0
		var x := (sin(phase) * 0.45 + 0.5) * (Ui.SCREEN_SIZE.x + diameter) - diameter
		var y := (cos(phase * 0.73 + index) * 0.45 + 0.5) * (Ui.SCREEN_SIZE.y + diameter) - diameter
		var radius := diameter * 0.5
		draw_circle(Vector2(x + radius, y + radius), radius, _circle_colors[index])
	var line_y := Ui.SCREEN_SIZE.y * 0.82 + sin(_time * 0.8) * 8.0
	draw_rect(Rect2(0.0, line_y, Ui.SCREEN_SIZE.x, 2.0), _line_color)


func _on_accent_changed(_accent: Color) -> void:
	_cache_colors()
	queue_redraw()


func _cache_colors() -> void:
	_circle_colors.resize(CIRCLE_COUNT)
	for index in CIRCLE_COUNT:
		_circle_colors[index] = CIRCLE_BASE.lerp(Ui.accent if index % 2 == 1 else Ui.accent2, 0.10)
	_line_color = LINE_BASE.lerp(Ui.accent, 0.35)


static func _gradient_texture(top: Color, bottom: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([top, bottom])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 128
	texture.fill_to = Vector2(0.0, 1.0)
	return texture
