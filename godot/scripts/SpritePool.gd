class_name SpritePool
extends RefCounted

var root: Node2D

var _sprites: Array[Sprite2D] = []
var _used := 0
var _shown_last_frame := 0


func _init(parent: Node) -> void:
	root = Node2D.new()
	parent.add_child(root)


func begin() -> void:
	_used = 0


func next(texture: Texture2D) -> Sprite2D:
	if _used == _sprites.size():
		var created := Sprite2D.new()
		root.add_child(created)
		_sprites.append(created)
	var sprite := _sprites[_used]
	_used += 1
	sprite.texture = texture
	sprite.visible = true
	return sprite


func end() -> void:
	for index in range(_used, _shown_last_frame):
		_sprites[index].visible = false
	_shown_last_frame = _used


## Fits the texture inside the rect, keeping aspect, centred horizontally and resting on the bottom edge.
static func fit(sprite: Sprite2D, rect: Rect2) -> void:
	if sprite.texture != null:
		place_fitted(sprite, sprite.texture.get_size(), rect)


## Expects a centred sprite.
static func place_fitted(node: Node2D, texture_size: Vector2, rect: Rect2) -> void:
	var scale := minf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	node.scale = Vector2(scale, scale)
	node.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y - texture_size.y * scale * 0.5)


static func stretch(sprite: Sprite2D, rect: Rect2) -> void:
	if sprite.texture == null:
		return
	sprite.scale = rect.size / sprite.texture.get_size()
	sprite.position = rect.get_center()
