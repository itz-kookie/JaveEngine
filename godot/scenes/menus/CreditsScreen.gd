class_name CreditsScreen
extends MenuScreen

const ROW_TOP := 160.0
const ROW_SPACING := 64.0
const DETAIL_COLOR := Color8(156, 166, 198)
const NOTE_COLOR := Color8(184, 192, 216)


func _build() -> void:
	Ui.menu_header(self, "CREDITS", "Code, libraries and content licenses.")
	Ui.box(self, Rect2(64.0, 140.0, Ui.SCREEN_SIZE.x - 128.0, 450.0), Ui.BAR_COLOR)
	var entries: Array[PackedStringArray] = [
		PackedStringArray(["Jave Engine " + Ui.version(), "Engine code  •  MIT License"]),
		PackedStringArray(["Godot Engine", "Godot Engine contributors  •  MIT License"]),
		PackedStringArray(["lua-gdextension", "gilzoide  •  MIT License"]),
		PackedStringArray(["Lua 5.4", "Lua.org, PUC-Rio  •  MIT License"]),
		PackedStringArray(["Neon Steps demo", "Song, chart and graphics  •  CC0 1.0"]),
	]
	for index in entries.size():
		var y := ROW_TOP + index * ROW_SPACING
		Ui.text(self, entries[index][0], Rect2(105.0, y, 600.0, 32.0), 22, Ui.accent if index == 0 else Ui.WHITE, true)
		Ui.text(self, entries[index][1], Rect2(105.0, y + 30.0, 900.0, 26.0), 16, DETAIL_COLOR)
	Ui.text(self, "Imported songs, art and videos keep their authors' rights.", Rect2(105.0, 495.0, 1000.0, 30.0), 17, Ui.accent2)
	Ui.text(self, "Independent project — not affiliated with The Funkin' Crew, Psych Engine, or V-Slice.", Rect2(105.0, 530.0, 1000.0, 30.0), 17, NOTE_COLOR)
