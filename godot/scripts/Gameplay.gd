class_name Gameplay
extends RefCounted

signal note_judged(lane: int, rating: String)

const JUDGE_WINDOW_MS := 180.0
const SICK_WINDOW_MS := 45.0
const GOOD_WINDOW_MS := 90.0
const HOLD_RELEASE_GRACE_MS := 100.0
const FLASH_SECONDS := 0.14
const HOLD_FLASH_SECONDS := 0.08
const POSE_SECONDS := 0.45
const HOLD_POSE_SECONDS := 0.10
const RATING_SECONDS := 0.45
const STAGE_WIDTH := 1280.0
const STAGE_HEIGHT := 720.0
## Heads can be hit up to the judge window early, so holds that far ahead still need updates.
const NOTE_UPDATE_AHEAD_MS := JUDGE_WINDOW_MS + 50.0
const RATINGS: PackedStringArray = ["sick", "good", "bad"]
const RATING_LABELS: PackedStringArray = ["SICK", "GOOD", "BAD"]
const RATING_SCORES: PackedInt32Array = [350, 200, 100]
const RATING_ACCURACY: PackedFloat64Array = [1.0, 0.75, 0.4]
const RATING_HEALTH: PackedFloat64Array = [0.025, 0.015, 0.005]

var chart: ChartData
var song: SongMeta
var cursors := NoteCursors.new()

var score := 0
var combo := 0
var max_combo := 0
var misses := 0
var health := 0.5
var accuracy_points := 0.0
var judged_count := 0
var sick_count := 0
var good_count := 0
var bad_count := 0
var miss_count := 0
var last_rating := ""
var rating_life := 0.0

var song_time_ms := 0.0
var song_end_ms := 0.0
var player_animation_ms := 0.0
var opponent_animation_ms := 0.0
var player_flash := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var opponent_flash := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var player_pose := -1
var opponent_pose := -1
var player_pose_life := 0.0
var opponent_pose_life := 0.0

var next_camera_event := 0
var camera_focus := "opponent"
var camera_forced := false
var camera_manual := Vector2.ZERO
var camera_pan := Vector2.ZERO
var camera_zoom_base := 0.9
var camera_zoom_pulse := 0.0

var botplay := false


func _init(song_chart: ChartData, song_meta: SongMeta) -> void:
	chart = song_chart
	song = song_meta
	camera_zoom_base = song.stage_zoom
	song_end_ms = chart.duration_ms


## Swaps in an edited chart; note indices change, so the cursors restart from the beginning.
func replace_chart(edited: ChartData) -> void:
	chart = edited
	cursors = NoteCursors.new()
	cursors.advance_unjudged(chart)


func accuracy() -> float:
	return accuracy_points / judged_count if judged_count > 0 else 1.0


func camera_scale() -> float:
	return clampf(1.0 + (camera_zoom_base - 0.9) * 0.22 + camera_zoom_pulse, 0.88, 1.22)


func is_finished() -> bool:
	return song_time_ms >= song_end_ms


## Advances the clock and timers; when botplay is on, also hits due notes.
func begin_frame(dt: float, now_ms: float) -> void:
	song_time_ms = now_ms
	rating_life = maxf(0.0, rating_life - dt)
	player_pose_life = maxf(0.0, player_pose_life - dt)
	opponent_pose_life = maxf(0.0, opponent_pose_life - dt)
	if player_pose_life <= 0.0:
		player_pose = -1
	if opponent_pose_life <= 0.0:
		opponent_pose = -1
	for lane in 4:
		player_flash[lane] = maxf(0.0, player_flash[lane] - dt)
		opponent_flash[lane] = maxf(0.0, opponent_flash[lane] - dt)
	cursors.advance_unjudged(chart)
	if botplay:
		_auto_hit_player_notes()


func end_frame(dt: float, held_mask: int) -> void:
	_apply_camera_events()
	_ease_camera(dt)
	_update_notes(dt, held_mask)
	cursors.advance_unjudged(chart)


func _auto_hit_player_notes() -> void:
	var index := cursors.first_unjudged
	var count := chart.note_count()
	while index < count and chart.times[index] <= song_time_ms:
		if chart.is_player(index) and chart.flags[index] & (ChartData.HEAD_HIT | ChartData.JUDGED) == 0:
			judge_lane(chart.lanes[index], song_time_ms)
		index += 1


func find_judge_target(lane: int, at_ms: float) -> int:
	var best := -1
	var best_delta := JUDGE_WINDOW_MS + 1.0
	var index := cursors.first_unjudged
	var count := chart.note_count()
	while index < count and chart.times[index] - at_ms < JUDGE_WINDOW_MS + 1.0:
		if chart.lanes[index] == lane and chart.is_player(index) \
				and chart.flags[index] & (ChartData.HEAD_HIT | ChartData.JUDGED) == 0:
			var delta := absf(chart.times[index] - at_ms)
			if delta < best_delta:
				best_delta = delta
				best = index
		index += 1
	return best


func judge_lane(lane: int, at_ms: float) -> void:
	var index := find_judge_target(lane, at_ms)
	if index < 0:
		return
	var has_hold := chart.lengths[index] > 0.0
	chart.set_flag(index, ChartData.HEAD_HIT | ChartData.HIT)
	chart.set_flag(index, ChartData.JUDGED, not has_hold)
	chart.set_flag(index, ChartData.HOLDING, has_hold)
	judged_count += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	var rating := _rating_for(absf(chart.times[index] - at_ms))
	_count_rating(rating)
	score += RATING_SCORES[rating]
	accuracy_points += RATING_ACCURACY[rating]
	health = clampf(health + RATING_HEALTH[rating], 0.0, 1.0)
	last_rating = RATING_LABELS[rating]
	rating_life = RATING_SECONDS
	player_flash[lane] = FLASH_SECONDS
	player_pose = lane
	player_pose_life = POSE_SECONDS
	player_animation_ms = at_ms
	note_judged.emit(lane, RATINGS[rating])


static func _rating_for(delta: float) -> int:
	if delta <= SICK_WINDOW_MS:
		return 0
	if delta <= GOOD_WINDOW_MS:
		return 1
	return 2


func _count_rating(rating: int) -> void:
	match rating:
		0: sick_count += 1
		1: good_count += 1
		_: bad_count += 1


func _apply_camera_events() -> void:
	var count := chart.camera_times.size()
	while next_camera_event < count and chart.camera_times[next_camera_event] <= song_time_ms:
		_apply_camera_event(next_camera_event)
		next_camera_event += 1


func _apply_camera_event(index: int) -> void:
	match chart.camera_types[index]:
		"focus":
			camera_focus = chart.camera_targets[index]
			camera_forced = false
		"position":
			camera_forced = true
			camera_manual = Vector2(chart.camera_x[index], chart.camera_y[index])
		"zoom":
			camera_zoom_pulse = clampf(camera_zoom_pulse + absf(chart.camera_amounts[index]) * 3.0, 0.0, 0.18)
		"setZoom":
			camera_zoom_base = clampf(chart.camera_amounts[index], 0.55, 1.5)


func _ease_camera(dt: float) -> void:
	var target := _camera_target()
	var ease_amount := minf(1.0, dt * clampf(song.camera_speed, 0.25, 8.0) * 5.0)
	camera_pan += (target - camera_pan) * ease_amount
	camera_zoom_pulse = maxf(0.0, camera_zoom_pulse - dt * 0.24)


func _camera_target() -> Vector2:
	var focus_player := camera_focus == "player"
	if camera_forced:
		var minimum_x := minf(song.player_position.x, minf(song.opponent_position.x, song.girlfriend_position.x))
		var maximum_x := maxf(song.player_position.x, maxf(song.opponent_position.x, song.girlfriend_position.x))
		var world_center := (minimum_x + maximum_x) * 0.5
		return Vector2(
			-(camera_manual.x - world_center) / maxf(500.0, maximum_x - minimum_x) * STAGE_WIDTH * 0.12,
			-camera_manual.y / 720.0 * STAGE_HEIGHT * 0.08)
	var offset := song.camera_player if focus_player else song.camera_opponent
	return Vector2(
		(-STAGE_WIDTH if focus_player else STAGE_WIDTH) * 0.045 - offset.x / 1280.0 * STAGE_WIDTH * 0.18,
		-offset.y / 720.0 * STAGE_HEIGHT * 0.18)


func _update_notes(dt: float, held_mask: int) -> void:
	var index := cursors.first_unjudged
	var count := chart.note_count()
	while index < count and chart.times[index] - song_time_ms < NOTE_UPDATE_AHEAD_MS:
		if not chart.has_flag(index, ChartData.JUDGED):
			if chart.is_player(index):
				_update_player_note(index, dt, held_mask)
			else:
				_update_opponent_note(index)
		index += 1


func _update_opponent_note(index: int) -> void:
	var lane := chart.lanes[index]
	if not chart.has_flag(index, ChartData.HEAD_HIT) and song_time_ms >= chart.times[index]:
		chart.set_flag(index, ChartData.HEAD_HIT | ChartData.HIT)
		opponent_flash[lane] = FLASH_SECONDS
		opponent_pose = lane
		opponent_pose_life = POSE_SECONDS
		opponent_animation_ms = song_time_ms
		if chart.lengths[index] <= 0.0:
			chart.set_flag(index, ChartData.JUDGED)
	if chart.flags[index] & (ChartData.HEAD_HIT | ChartData.JUDGED) != ChartData.HEAD_HIT:
		return
	if song_time_ms >= chart.times[index] + chart.lengths[index]:
		chart.set_flag(index, ChartData.JUDGED)
	else:
		opponent_pose = lane
		opponent_pose_life = HOLD_POSE_SECONDS


func _update_player_note(index: int, dt: float, held_mask: int) -> void:
	if chart.has_flag(index, ChartData.HEAD_HIT):
		_update_player_hold(index, dt, botplay or (held_mask >> chart.lanes[index]) & 1 != 0)
	elif song_time_ms - chart.times[index] > JUDGE_WINDOW_MS:
		chart.set_flag(index, ChartData.JUDGED)
		_register_miss("MISS", 0.075, chart.lanes[index])


func _update_player_hold(index: int, dt: float, held: bool) -> void:
	var lane := chart.lanes[index]
	if held:
		chart.set_flag(index, ChartData.HOLDING)
		chart.hold_release_ms[index] = 0.0
		health = minf(1.0, health + dt * 0.008)
		player_flash[lane] = HOLD_FLASH_SECONDS
		player_pose = lane
		player_pose_life = HOLD_POSE_SECONDS
	else:
		chart.set_flag(index, ChartData.HOLDING, false)
		chart.hold_release_ms[index] += dt * 1000.0
	var hold_end := chart.times[index] + chart.lengths[index]
	if chart.hold_release_ms[index] > HOLD_RELEASE_GRACE_MS and song_time_ms < hold_end:
		chart.set_flag(index, ChartData.JUDGED)
		_register_miss("HOLD BREAK", 0.09, lane)
	elif song_time_ms >= hold_end:
		chart.set_flag(index, ChartData.JUDGED)
		score += 100
		health = minf(1.0, health + 0.015)


func _register_miss(label: String, health_loss: float, lane: int) -> void:
	misses += 1
	miss_count += 1
	judged_count += 1
	combo = 0
	health = maxf(0.0, health - health_loss)
	last_rating = label
	rating_life = RATING_SECONDS
	note_judged.emit(lane, "miss")
