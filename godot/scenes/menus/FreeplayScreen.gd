class_name FreeplayScreen
extends MenuScreen

signal song_chosen(song: SongMeta)

const EMPTY_COLOR := Color8(255, 150, 170)
const ARTIST_COLOR := Color8(225, 220, 240)

var _bpm: Label
var _artist: Label
var _player_icon: TextureRect
var _player_icon_box := Rect2()
var _preview: FreeplayPreview


func _build() -> void:
	var screen := Ui.SCREEN_SIZE
	Ui.menu_header(self, "FREEPLAY", "Pick any installed chart.")
	if Content.songs.is_empty():
		Ui.text(self, "No valid songs found", Rect2(64.0, 240.0, 700.0, 50.0), 26, EMPTY_COLOR, true)
		return
	var titles := PackedStringArray()
	for song in Content.songs:
		titles.append(song.title)
	build_list(titles, 145.0, screen.x * 0.64)
	for index in Content.songs.size():
		row(index).set_icon(TextureCache.get_texture(Content.songs[index].opponent_icon))
	_build_panel(screen.x * 0.70, screen.x * 0.27)
	_preview = FreeplayPreview.new()
	add_child(_preview)
	_selection_changed()


func _build_panel(x: float, width: float) -> void:
	Ui.box(self, Rect2(x, 145.0, width, 135.0), Ui.BAR_COLOR)
	var difficulty := FunkinLabel.new()
	difficulty.position = Vector2(x + 20.0, 160.0)
	add_child(difficulty)
	difficulty.show_text("NORMAL", width - 40.0, 39.0)
	_bpm = Ui.text(self, "", Rect2(x + 20.0, 212.0, width - 40.0, 30.0), 22, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_artist = Ui.text(self, "", Rect2(x + 10.0, 248.0, width - 20.0, 25.0), 13, ARTIST_COLOR, false, HORIZONTAL_ALIGNMENT_CENTER)
	_player_icon_box = Rect2(x + width * 0.25, 340.0, width * 0.5, 150.0)
	_player_icon = Ui.fitted_image(self, null, _player_icon_box)


func _selection_changed() -> void:
	var song := Content.songs[selection]
	_bpm.text = "%d BPM" % int(song.bpm)
	_artist.text = song.artist
	Ui.fit_image(_player_icon, TextureCache.get_texture(song.player_icon), _player_icon_box)
	_preview.request(song)


func _confirm() -> void:
	if selection < Content.songs.size():
		song_chosen.emit(Content.songs[selection])
