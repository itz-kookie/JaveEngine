extends SceneTree

var _failures := 0
var _checks := 0


func _initialize() -> void:
	run()
	print("%s: %d checks, %d failures" % [get_script().resource_path.get_file(), _checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func run() -> void:
	pass


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func check_near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s (expected %f, got %f)" % [message, expected, actual])
