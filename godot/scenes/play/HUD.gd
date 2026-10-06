class_name PlayHud
extends Control

const HEALTH_RECT := Rect2(115.0, 670.0, 1050.0, 22.0)
const HEALTH_INSET := 3.0
const HEALTH_FRAME_COLOR := Color8(245, 245, 250)
const HEALTH_LOSS_COLOR := Color8(220, 50, 70)
const HEALTH_GAIN_COLOR := Color8(45, 205, 95)

@onready var _opponent_icon: TextureRect = $OpponentIcon
@onready var _player_icon: TextureRect = $PlayerIcon
@onready var _accuracy: Label = $Accuracy
@onready var _rating: Label = $Rating
@onready var _botplay: Panel = $Botplay
@onready var _botplay_label: Label = $Botplay/Label

var _frame_box := _rounded_box(HEALTH_FRAME_COLOR, 10)
var _loss_box := _rounded_box(HEALTH_LOSS_COLOR, 8)
var _gain_box := _rounded_box(HEALTH_GAIN_COLOR, 8)
var _health := -1.0
var _shown_judged := -1
var _shown_misses := -1
var _shown_rating := ""


func setup(song: SongMeta) -> void:
	_show_icon(_opponent_icon, TextureCache.get_texture(song.opponent_icon))
	_show_icon(_player_icon, TextureCache.get_texture(song.player_icon))
	_apply_accent(Ui.accent)
	ModHost.accent_changed.connect(_apply_accent)


func _apply_accent(accent: Color) -> void:
	var panel := _rounded_box(Color8(20, 23, 52), 12)
	panel.border_color = accent
	panel.set_border_width_all(2)
	_botplay.add_theme_stylebox_override(&"panel", panel)
	_botplay_label.add_theme_color_override(&"font_color", accent)


## Fits the icon inside its slot, keeping aspect and resting on the slot's bottom edge.
static func _show_icon(icon: TextureRect, texture: Texture2D) -> void:
	icon.texture = texture
	if texture == null:
		return
	var slot := icon.get_rect()
	var size := texture.get_size()
	var fitted := size * minf(slot.size.x / size.x, slot.size.y / size.y)
	icon.position = Vector2(slot.position.x + (slot.size.x - fitted.x) * 0.5, slot.end.y - fitted.y)
	icon.size = fitted


func refresh(play: Gameplay) -> void:
	if play.health != _health:
		_health = play.health
		queue_redraw()
	if play.judged_count != _shown_judged or play.misses != _shown_misses:
		_shown_judged = play.judged_count
		_shown_misses = play.misses
		_accuracy.text = "ACCURACY  %d%%    MISSES  %d" % [roundi(play.accuracy() * 100.0), play.misses]
	_rating.visible = play.rating_life > 0.0
	if play.last_rating != _shown_rating:
		_shown_rating = play.last_rating
		_rating.text = play.last_rating
	_botplay.visible = play.botplay


func _draw() -> void:
	draw_style_box(_frame_box, HEALTH_RECT)
	var inner := HEALTH_RECT.grow(-HEALTH_INSET)
	draw_style_box(_loss_box, inner)
	var gain_width := inner.size.x * clampf(_health, 0.0, 1.0)
	if gain_width > 0.0:
		draw_style_box(_gain_box, Rect2(inner.end.x - gain_width, inner.position.y, gain_width, inner.size.y))


static func _rounded_box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
