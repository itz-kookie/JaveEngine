class_name NoteCursors
extends RefCounted

## Every note before first_unjudged is judged.
var first_unjudged := 0
## Notes before first_visible are judged or have scrolled past the trailing edge.
var first_visible := 0
## Exclusive end of the notes whose heads have reached the leading edge.
var last_visible := 0


func advance_unjudged(chart: ChartData) -> void:
	var count := chart.note_count()
	while first_unjudged < count and chart.has_flag(first_unjudged, ChartData.JUDGED):
		first_unjudged += 1


func advance_visible(chart: ChartData, now_ms: float, ahead_ms: float, behind_ms: float) -> void:
	var count := chart.note_count()
	first_visible = maxi(first_visible, first_unjudged)
	while first_visible < count and _scrolled_past(chart, first_visible, now_ms - behind_ms):
		first_visible += 1
	last_visible = maxi(last_visible, first_visible)
	while last_visible < count and chart.times[last_visible] <= now_ms + ahead_ms:
		last_visible += 1


static func _scrolled_past(chart: ChartData, index: int, trailing_ms: float) -> bool:
	if chart.has_flag(index, ChartData.JUDGED):
		return true
	return not chart.has_flag(index, ChartData.HEAD_HIT) and chart.times[index] < trailing_ms
