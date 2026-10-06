class_name TitleScreen
extends MenuScreen

signal chosen(index: int)

const EXIT_INDEX := 5
const BUTTON_IDS: PackedStringArray = ["story_mode", "freeplay", "mods", "options", "credits"]
const BUTTON_LABELS: PackedStringArray = ["STORY MODE", "FREEPLAY", "MODS", "OPTIONS", "CREDITS"]
const OPTIONS_INDEX := 3
const FOOTER_TEXT := "Jave Engine 0.1     UP / DOWN: SELECT     ENTER: CONFIRM"

var _labels: Array[FunkinLabel] = []
var _buttons: Array[AnimatedSprite2D] = []
var _button_assets: Array[CharacterAsset] = []


func item_count() -> int:
	return EXIT_INDEX + 1


func _build() -> void:
	var logo := FunkinLabel.new()
	logo.position = Vector2(Ui.SCREEN_SIZE.x * 0.61, Ui.SCREEN_SIZE.y * 0.065)
	add_child(logo)
	logo.show_text("JAVE ENGINE", Ui.SCREEN_SIZE.x * 0.36, Ui.SCREEN_SIZE.y * 0.075)
	for index in item_count():
		var label := FunkinLabel.new()
		add_child(label)
		_labels.append(label)
		_button_assets.append(_load_button(index))
		_buttons.append(_make_button_sprite(_button_assets[index]))
	Ui.footer(self, FOOTER_TEXT, 38.0, 15, 25.0)
	_selection_changed()


func _selection_changed() -> void:
	for index in item_count():
		_place_item(index, index == selection)


func _confirm() -> void:
	chosen.emit(selection)


func _place_item(index: int, selected: bool) -> void:
	var screen := Ui.SCREEN_SIZE
	var y := screen.y * (0.075 + index * 0.138)
	var x := screen.x * (0.105 if selected else 0.075)
	var height := screen.y * (0.113 if selected else 0.094)
	var label := _labels[index]
	if index == EXIT_INDEX:
		label.position = Vector2(x + 30.0, y)
		label.show_text("EXIT", screen.x * 0.35, height * 0.8)
		return
	var asset := _button_assets[index]
	if asset == null:
		label.position = Vector2(x, y)
		label.show_text(BUTTON_LABELS[index], screen.x * 0.5, height * 0.82)
		return
	_place_button(_buttons[index], asset, Rect2(x, y, 0.0, height), selected)
	label.visible = index == OPTIONS_INDEX
	if label.visible:
		label.position = Vector2(x + height * 1.18, y + 6.0)
		label.show_text("OPTIONS", screen.x * 0.36, height * 0.82)


func _place_button(sprite: AnimatedSprite2D, asset: CharacterAsset, box: Rect2, selected: bool) -> void:
	var pose := "left" if selected else "idle"
	var meta := asset.pose_metadata(pose)
	var native := Vector2(JsonRead.number(meta, "width", 600.0), maxf(1.0, JsonRead.number(meta, "height", 120.0)))
	box.size.x = minf(Ui.SCREEN_SIZE.x * 0.54, box.size.y * native.x / native.y)
	sprite.play(StringName(pose))
	var texture := sprite.sprite_frames.get_frame_texture(StringName(pose), 0)
	if texture == null:
		return
	var source := texture.get_size()
	var fit := minf(box.size.x / source.x, box.size.y / source.y)
	sprite.scale = Vector2(fit, fit)
	sprite.position = Vector2(box.position.x + (box.size.x - source.x * fit) * 0.5, box.end.y - source.y * fit)


## Imported button art is optional; without its idle metadata the label is drawn instead.
static func _load_button(index: int) -> CharacterAsset:
	if index >= BUTTON_IDS.size():
		return null
	var asset := CharacterAsset.new(Ui.MENUS_ROOT.path_join("buttons").path_join(BUTTON_IDS[index]))
	if not FileAccess.file_exists(asset.base.path_join("animation.json")):
		return null
	asset.load_from_disk()
	if asset.pose_metadata("idle").is_empty():
		return null
	asset.build_frames()
	return asset


func _make_button_sprite(asset: CharacterAsset) -> AnimatedSprite2D:
	if asset == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.centered = false
	sprite.sprite_frames = asset.frames
	add_child(sprite)
	return sprite
