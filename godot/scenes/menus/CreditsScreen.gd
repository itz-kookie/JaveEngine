class_name CreditsScreen
extends MenuScreen


func _build() -> void:
	Ui.menu_header(self, "CREDITS", "Built cleanly, from the first beat.")
	Ui.box(self, Rect2(64.0, 205.0, Ui.SCREEN_SIZE.x - 128.0, 360.0), Ui.BAR_COLOR)
	Ui.text(self, "JAVE ENGINE", Rect2(105.0, 235.0, 450.0, 48.0), 29, Ui.accent, true)
	Ui.text(self, "Original C++ engine; imported media retains its authors' rights", Rect2(105.0, 285.0, 850.0, 38.0), 18, Color8(220, 224, 240))
	Ui.text(self, "Lua 5.4.8", Rect2(105.0, 355.0, 330.0, 40.0), 24, Ui.WHITE, true)
	Ui.text(self, "Lua.org, PUC-Rio  •  MIT License", Rect2(105.0, 394.0, 650.0, 30.0), 17, Color8(156, 166, 198))
	Ui.text(self, "Independent project — not affiliated with The Funkin' Crew, Psych Engine, or V-Slice.", Rect2(105.0, 465.0, 950.0, 35.0), 17, Color8(184, 192, 216))
	Ui.text(self, "Source license: MIT  •  Demo song/chart: CC0", Rect2(105.0, 510.0, 750.0, 30.0), 16, Ui.accent2)
