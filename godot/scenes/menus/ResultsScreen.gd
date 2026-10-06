class_name ResultsScreen
extends MenuScreen

signal continue_requested

const PANEL_COLOR := Color8(20, 23, 52)
const CAPTION_COLOR := Color8(150, 160, 192)
const STAT_COLOR := Color8(220, 224, 240)
const GRADES: PackedStringArray = ["S", "A", "B", "C", "D"]
const GRADE_THRESHOLDS: PackedFloat64Array = [0.95, 0.88, 0.75, 0.60]

var result: Gameplay
var action_text := "Enter Continue"


static func accuracy_of(play: Gameplay) -> float:
	return play.accuracy_points / play.judged_count if play.judged_count > 0 else 0.0


static func grade_for(accuracy: float) -> String:
	for index in GRADE_THRESHOLDS.size():
		if accuracy >= GRADE_THRESHOLDS[index]:
			return GRADES[index]
	return GRADES[GRADES.size() - 1]


func _build() -> void:
	Ui.plain_header(self, "SONG COMPLETE", "RESULTS", result.song.title)
	var accuracy := accuracy_of(result)
	Ui.box(self, Rect2(64.0, 210.0, Ui.SCREEN_SIZE.x - 128.0, 350.0), PANEL_COLOR, 28)
	Ui.text(self, grade_for(accuracy), Rect2(105.0, 245.0, 250.0, 230.0), 150, Ui.accent, true, HORIZONTAL_ALIGNMENT_CENTER)
	Ui.box(self, Rect2(115.0, 260.0, 230.0, 200.0), Color.TRANSPARENT, 55, Ui.accent2, 4)
	var x := 410.0
	Ui.text(self, "Score", Rect2(x, 245.0, 220.0, 30.0), 16, CAPTION_COLOR)
	Ui.text(self, str(result.score), Rect2(x, 275.0, 350.0, 52.0), 34, Ui.WHITE, true)
	Ui.text(self, "Accuracy  %d%%" % roundi(accuracy * 100.0), Rect2(x, 340.0, 330.0, 35.0), 20, STAT_COLOR)
	Ui.text(self, "Max combo  %d" % result.max_combo, Rect2(x, 380.0, 330.0, 35.0), 20, STAT_COLOR)
	Ui.text(self, "Sick %d    Good %d    Bad %d    Miss %d" % [result.sick_count, result.good_count, result.bad_count, result.miss_count],
		Rect2(x, 435.0, 650.0, 40.0), 18, Ui.accent2)
	Ui.text(self, action_text, Rect2(x, 495.0, 300.0, 35.0), 17, CAPTION_COLOR)


func _confirm() -> void:
	continue_requested.emit()
