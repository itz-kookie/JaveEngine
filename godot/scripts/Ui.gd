class_name Ui
extends RefCounted

const SCREEN_SIZE := Vector2(1280.0, 720.0)
const BAR_COLOR := Color8(22, 18, 31)
const BAR_TEXT_COLOR := Color8(245, 235, 255)
const WHITE := Color8(250, 250, 255)
const MENUS_ROOT := "res://content/assets/imported/menus"

static var accent := Color8(95, 227, 255)
static var accent2 := Color8(255, 81, 170)
static var _bold_font: SystemFont


static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = SystemFont.new()
		_bold_font.font_weight = 700
	return _bold_font


static func text(parent: Control, value: String, rect: Rect2, size: int, color: Color, bold := false,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	if bold:
		label.add_theme_font_override(&"font", bold_font())
	parent.add_child(label)
	return label


static func wrapped_text(parent: Control, value: String, rect: Rect2, size: int, color: Color) -> Label:
	var label := text(parent, value, rect, size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func box(parent: Control, rect: Rect2, color: Color, radius := 0, border_color := Color.TRANSPARENT,
		border := 0) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", style(color, radius, border_color, border))
	parent.add_child(panel)
	return panel


static func style(color: Color, radius := 0, border_color := Color.TRANSPARENT, border := 0) -> StyleBoxFlat:
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = color
	box_style.set_corner_radius_all(radius)
	box_style.border_color = border_color
	box_style.set_border_width_all(border)
	box_style.anti_aliasing = radius > 0
	return box_style


## Fits a texture inside rect keeping aspect, centred horizontally and resting on the bottom edge.
static func fitted_image(parent: Control, texture: Texture2D, rect: Rect2, flip := false) -> TextureRect:
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.flip_h = flip
	parent.add_child(image)
	fit_image(image, texture, rect)
	return image


static func fit_image(image: TextureRect, texture: Texture2D, rect: Rect2) -> void:
	image.texture = texture
	image.visible = texture != null
	if texture == null:
		return
	var source := texture.get_size()
	var fitted := source * minf(rect.size.x / source.x, rect.size.y / source.y)
	image.position = Vector2(rect.position.x + (rect.size.x - fitted.x) * 0.5, rect.end.y - fitted.y)
	image.size = fitted


static func menu_texture(relative: String) -> Texture2D:
	return TextureCache.get_texture(MENUS_ROOT.path_join(relative))


## Header used by the main menu family: dark bar, alphabet title and a subtitle line.
static func menu_header(parent: Control, title: String, subtitle: String) -> Label:
	box(parent, Rect2(0.0, 0.0, SCREEN_SIZE.x, 115.0), BAR_COLOR)
	var heading := FunkinLabel.new()
	heading.position = Vector2(35.0, 18.0)
	parent.add_child(heading)
	heading.show_text(title, SCREEN_SIZE.x - 70.0, 59.0)
	return text(parent, subtitle, Rect2(40.0, 82.0, SCREEN_SIZE.x - 80.0, 25.0), 15, BAR_TEXT_COLOR)


static func plain_header(parent: Control, eyebrow: String, title: String, subtitle: String) -> void:
	text(parent, eyebrow, Rect2(64.0, 42.0, 700.0, 30.0), 15, accent, true)
	text(parent, title, Rect2(60.0, 70.0, 1000.0, 68.0), 46, Color8(245, 247, 255), true)
	if not subtitle.is_empty():
		text(parent, subtitle, Rect2(64.0, 132.0, 950.0, 36.0), 18, Color8(152, 162, 195))


static func footer(parent: Control, value: String, height: float, text_size: int, text_x: float) -> void:
	box(parent, Rect2(0.0, SCREEN_SIZE.y - height, SCREEN_SIZE.x, height), BAR_COLOR)
	text(parent, value, Rect2(text_x, SCREEN_SIZE.y - height + 4.0, SCREEN_SIZE.x - text_x * 2.0, 30.0), text_size, BAR_TEXT_COLOR)
