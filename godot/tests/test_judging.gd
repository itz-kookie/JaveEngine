extends "res://tests/test_base.gd"

const FRAME := 1.0 / 60.0


func run() -> void:
	_test_hit_ratings()
	_test_window_edges()
	_test_late_miss()
	_test_completed_hold()
	_test_hold_break()
	_test_health_clamps()
	_test_opponent_auto_hit()
	_test_botplay()


func _make_play(notes: Array) -> Gameplay:
	var chart := ChartData.from_json({"format": "jave-chart-v1", "bpm": 120, "notes": notes}, "test", 120.0)
	return Gameplay.new(chart, SongMeta.new())


func _press(play: Gameplay, lane: int, at_ms: float) -> void:
	play.begin_frame(FRAME, at_ms)
	play.judge_lane(lane, at_ms)
	play.end_frame(FRAME, 1 << lane)


func _test_hit_ratings() -> void:
	var play := _make_play([
		{"timeMs": 1000, "lane": 0}, {"timeMs": 2000, "lane": 0}, {"timeMs": 3000, "lane": 0},
	])
	var ratings: Array[String] = []
	play.note_judged.connect(func(_lane: int, rating: String) -> void: ratings.append(rating))
	_press(play, 0, 1000.0 + 45.0)
	check(play.score == 350 and play.sick_count == 1, "45 ms is sick for 350")
	check_near(play.health, 0.525, "sick adds 0.025 health")
	check(play.last_rating == "SICK" and is_equal_approx(play.rating_life, 0.45), "sick popup")
	check_near(play.player_flash[0], 0.14, "hit flashes the receptor")
	check(play.player_pose == 0 and is_equal_approx(play.player_pose_life, 0.45), "hit sets the pose")
	_press(play, 0, 2000.0 - 90.0)
	check(play.score == 550 and play.good_count == 1, "90 ms early is good for 200")
	check_near(play.health, 0.54, "good adds 0.015 health")
	_press(play, 0, 3000.0 + 135.0)
	check(play.score == 650 and play.bad_count == 1, "135 ms is bad for 100")
	check_near(play.health, 0.545, "bad adds 0.005 health")
	check_near(play.accuracy(), (1.0 + 0.75 + 0.4) / 3.0, "accuracy weights")
	check(play.combo == 3 and play.max_combo == 3, "combo counts hits")
	check(ratings == ["sick", "good", "bad"], "note_judged reports ratings")


func _test_window_edges() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 1}, {"timeMs": 5000, "lane": 1}])
	play.begin_frame(FRAME, 820.0)
	play.judge_lane(1, 1000.0 - 181.0)
	check(play.judged_count == 0, "181 ms early is outside the window")
	play.judge_lane(1, 1000.0 - 180.5)
	check(play.bad_count == 1, "180.5 ms early is still a bad hit")
	play.judge_lane(2, 5000.0)
	check(play.judged_count == 1, "pressing an empty lane does nothing")


func _test_late_miss() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 2}])
	play.begin_frame(FRAME, 1180.0)
	play.end_frame(FRAME, 0)
	check(play.misses == 0, "exactly 180 ms late is not yet a miss")
	play.begin_frame(FRAME, 1181.0)
	play.end_frame(FRAME, 0)
	check(play.misses == 1 and play.miss_count == 1 and play.combo == 0, "past 180 ms is a miss")
	check_near(play.health, 0.425, "miss costs 0.075 health")
	check(play.last_rating == "MISS", "miss popup")


func _test_completed_hold() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 3, "lengthMs": 500}])
	_press(play, 3, 1000.0)
	check(play.chart.has_flag(0, ChartData.HOLDING) and not play.chart.has_flag(0, ChartData.JUDGED), "hold head starts holding")
	var now := 1000.0
	var held_frames := 0
	while not play.chart.has_flag(0, ChartData.JUDGED):
		now += 10.0
		play.begin_frame(0.01, now)
		play.end_frame(0.01, 1 << 3)
		held_frames += 1
	check(play.score == 350 + 100, "completed hold adds 100")
	var expected_health := 0.525 + (FRAME + 0.01 * held_frames) * 0.008 + 0.015
	check_near(play.health, expected_health, "holding adds 0.008/s and completion adds 0.015")


func _test_hold_break() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 0, "lengthMs": 1000}])
	_press(play, 0, 1000.0)
	var now := 1000.0
	for frame in 10:
		now += 10.0
		play.begin_frame(0.01, now)
		play.end_frame(0.01, 0)
	check(not play.chart.has_flag(0, ChartData.JUDGED), "100 ms of release is within grace")
	now += 10.0
	play.begin_frame(0.01, now)
	play.end_frame(0.01, 0)
	check(play.chart.has_flag(0, ChartData.JUDGED), "releasing past 100 ms breaks the hold")
	check(play.last_rating == "HOLD BREAK" and play.misses == 1 and play.combo == 0, "hold break counts as a miss")
	check_near(play.health, 0.525 + FRAME * 0.008 - 0.09, "hold break costs 0.09 health")


func _test_health_clamps() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 0}, {"timeMs": 2000, "lane": 1}])
	play.health = 0.99
	_press(play, 0, 1000.0)
	check_near(play.health, 1.0, "health clamps at 1")
	play.health = 0.05
	play.begin_frame(FRAME, 2200.0)
	play.end_frame(FRAME, 0)
	check_near(play.health, 0.0, "health clamps at 0")


func _test_opponent_auto_hit() -> void:
	var play := _make_play([
		{"timeMs": 1000, "lane": 1, "owner": "opponent"},
		{"timeMs": 1000, "lane": 2, "owner": "opponent", "lengthMs": 300},
	])
	play.begin_frame(FRAME, 1000.0)
	play.end_frame(FRAME, 0)
	check(play.chart.has_flag(0, ChartData.JUDGED), "opponent tap is judged on time")
	check(not play.chart.has_flag(1, ChartData.JUDGED) and play.chart.has_flag(1, ChartData.HEAD_HIT), "opponent hold stays active")
	check(play.score == 0 and play.judged_count == 0, "opponent notes never score")
	check_near(play.opponent_flash[1], 0.14, "opponent receptor flashes")
	play.begin_frame(FRAME, 1300.0)
	play.end_frame(FRAME, 0)
	check(play.chart.has_flag(1, ChartData.JUDGED), "opponent hold ends at its length")


func _test_botplay() -> void:
	var play := _make_play([{"timeMs": 1000, "lane": 0}, {"timeMs": 1000, "lane": 3, "lengthMs": 200}])
	play.botplay = true
	var now := 0.0
	while now < 1400.0:
		now += 1000.0 / 60.0
		play.begin_frame(FRAME, now)
		play.end_frame(FRAME, 0)
	check(play.sick_count == 2 and play.score == 350 * 2 + 100, "botplay hits everything sick and completes holds")
