class_name GameOverScreen
extends MenuScreen

signal retry_requested
signal exit_requested

const CAPTION_COLOR := Color8(160, 170, 204)

var song_title := ""


func _build() -> void:
	Ui.plain_header(self, "GAME OVER", "TRY AGAIN?", song_title)
	Ui.text(self, "Your health ran out.", Rect2(80.0, 260.0, 1120.0, 36.0), 20, CAPTION_COLOR,
		false, HORIZONTAL_ALIGNMENT_CENTER)
	build_list(PackedStringArray(["Retry", "Exit to Song Select"]), 330.0, 640.0, 66.0)


func _confirm() -> void:
	if selection == 0:
		retry_requested.emit()
	else:
		exit_requested.emit()
