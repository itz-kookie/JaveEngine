extends "res://tests/test_base.gd"

## Unwindowed reference: every scan walks the whole chart, as the original engine did.
class BruteForce:
	var chart: ChartData
	var score := 0
	var combo := 0
	var misses := 0
	var health := 0.5

	func _init(source: ChartData) -> void:
		chart = source

	func judge_target(lane: int, at_ms: float) -> int:
		var best := -1
		var best_delta := 181.0
		for index in chart.note_count():
			if not chart.is_player(index) or chart.has_flag(index, ChartData.HEAD_HIT) \
					or chart.has_flag(index, ChartData.JUDGED) or chart.lanes[index] != lane:
				continue
			var delta := absf(chart.times[index] - at_ms)
			if delta < best_delta:
				best_delta = delta
				best = index
			if chart.times[index] - at_ms > 180.0:
				break
		return best

	func judge(lane: int, at_ms: float) -> void:
		var index := judge_target(lane, at_ms)
		if index < 0:
			return
		var has_hold := chart.lengths[index] > 0.0
		chart.set_flag(index, ChartData.HEAD_HIT | ChartData.HIT)
		chart.set_flag(index, ChartData.JUDGED, not has_hold)
		chart.set_flag(index, ChartData.HOLDING, has_hold)
		combo += 1
		var delta := absf(chart.times[index] - at_ms)
		score += 350 if delta <= 45.0 else (200 if delta <= 90.0 else 100)
		health = clampf(health + (0.025 if delta <= 45.0 else (0.015 if delta <= 90.0 else 0.005)), 0.0, 1.0)

	func update(dt: float, now: float, held_mask: int) -> void:
		for index in chart.note_count():
			var lane := chart.lanes[index]
			if not chart.is_player(index):
				_update_opponent(index, now)
			elif chart.has_flag(index, ChartData.HEAD_HIT) and not chart.has_flag(index, ChartData.JUDGED):
				_update_hold(index, dt, now, (held_mask >> lane) & 1 != 0)
			elif not chart.has_flag(index, ChartData.HEAD_HIT) and not chart.has_flag(index, ChartData.JUDGED) \
					and now - chart.times[index] > 180.0:
				chart.set_flag(index, ChartData.JUDGED)
				_miss(0.075)

	func _update_opponent(index: int, now: float) -> void:
		if not chart.has_flag(index, ChartData.HEAD_HIT) and now >= chart.times[index]:
			chart.set_flag(index, ChartData.HEAD_HIT | ChartData.HIT)
			if chart.lengths[index] <= 0.0:
				chart.set_flag(index, ChartData.JUDGED)
		if chart.has_flag(index, ChartData.HEAD_HIT) and not chart.has_flag(index, ChartData.JUDGED) \
				and now >= chart.times[index] + chart.lengths[index]:
			chart.set_flag(index, ChartData.JUDGED)

	func _update_hold(index: int, dt: float, now: float, held: bool) -> void:
		if held:
			chart.set_flag(index, ChartData.HOLDING)
			chart.hold_release_ms[index] = 0.0
			health = minf(1.0, health + dt * 0.008)
		else:
			chart.set_flag(index, ChartData.HOLDING, false)
			chart.hold_release_ms[index] += dt * 1000.0
		var hold_end := chart.times[index] + chart.lengths[index]
		if chart.hold_release_ms[index] > 100.0 and now < hold_end:
			chart.set_flag(index, ChartData.JUDGED)
			_miss(0.09)
		elif now >= hold_end:
			chart.set_flag(index, ChartData.JUDGED)
			score += 100
			health = minf(1.0, health + 0.015)

	func _miss(loss: float) -> void:
		misses += 1
		combo = 0
		health = maxf(0.0, health - loss)


func run() -> void:
	# Loaded at runtime because Strumline references autoloads, which -s scripts cannot see at compile time.
	var strumline: Node2D = load("res://scenes/play/Strumline.gd").new()
	for seed_value in [7, 1234, 99991]:
		for downscroll in [false, true]:
			for speed in [0.5, 1.0, 2.5]:
				_simulate(strumline, seed_value, downscroll, speed)
	strumline.free()


func _random_chart_json(rng: RandomNumberGenerator) -> Dictionary:
	var notes: Array[Dictionary] = []
	for i in 400:
		var note := {"timeMs": snappedf(rng.randf_range(0.0, 60000.0), 5.0), "lane": rng.randi_range(0, 3)}
		if rng.randf() < 0.3:
			note["owner"] = "opponent"
		if rng.randf() < 0.15:
			note["lengthMs"] = rng.randf_range(50.0, 1500.0)
		notes.append(note)
	return {"format": "jave-chart-v1", "bpm": 120, "notes": notes}


func _simulate(strumline: Node2D, seed_value: int, downscroll: bool, speed: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var json := _random_chart_json(rng)
	var play := Gameplay.new(ChartData.from_json(json, "a", 120.0), SongMeta.new())
	var reference := BruteForce.new(ChartData.from_json(json, "b", 120.0))
	strumline.downscroll = downscroll
	strumline.note_speed = speed
	strumline.receptor_y = strumline.DOWNSCROLL_RECEPTOR_Y if downscroll else strumline.UPSCROLL_RECEPTOR_Y
	var label := "seed %d downscroll %s speed %.1f" % [seed_value, downscroll, speed]
	var now := 0.0
	var held_mask := 0
	var mismatches := 0
	while now < 62000.0 and mismatches == 0:
		var dt := rng.randf_range(0.004, 0.045)
		now += dt * 1000.0
		play.begin_frame(dt, now)
		for lane in 4:
			if rng.randf() < 0.12:
				var at_ms := now - rng.randf_range(0.0, 10.0)
				if play.find_judge_target(lane, at_ms) != reference.judge_target(lane, at_ms):
					mismatches += 1
				play.judge_lane(lane, at_ms)
				reference.judge(lane, at_ms)
			if rng.randf() < 0.1:
				held_mask ^= 1 << lane
		play.end_frame(dt, held_mask)
		reference.update(dt, now, held_mask)
		if not _states_match(play, reference) or not _visible_sets_match(strumline, play):
			mismatches += 1
	check(mismatches == 0, "windowed scans match brute force until %.0f ms (%s)" % [now, label])
	check(play.chart.flags == reference.chart.flags, "final note states match (%s)" % label)
	check(play.cursors.first_unjudged == play.chart.note_count(), "every note judged by the end (%s)" % label)


func _states_match(play: Gameplay, reference: BruteForce) -> bool:
	return play.chart.flags == reference.chart.flags and play.score == reference.score \
		and play.combo == reference.combo and play.misses == reference.misses \
		and is_equal_approx(play.health, reference.health)


func _visible_sets_match(strumline: Node2D, play: Gameplay) -> bool:
	var span: Vector2 = strumline.visible_span_ms()
	play.cursors.advance_visible(play.chart, play.song_time_ms, span.x, span.y)
	var windowed := PackedInt32Array()
	for index in range(play.cursors.first_visible, play.cursors.last_visible):
		if strumline.is_note_on_screen(play, index):
			windowed.append(index)
	var brute := PackedInt32Array()
	for index in play.chart.note_count():
		if strumline.is_note_on_screen(play, index):
			brute.append(index)
	return windowed == brute
