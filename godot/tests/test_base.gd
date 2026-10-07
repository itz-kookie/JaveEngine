extends SceneTree

const PATHS_SCRIPT := preload("res://autoload/Paths.gd")
## Stands in for user:// while a test runs: the mods folder, mod states, settings and user://content overrides.
const TEST_HOME := "user://test-home"

var _failures := 0
var _checks := 0


## Runs before the autoloads are created, so Settings, Content and ModHost start from the empty test home.
func _init() -> void:
	isolate_user_content()


func _finalize() -> void:
	restore_user_content()


## Points Paths at a fresh TEST_HOME; anything the player installed or saved under user:// is left unread.
static func isolate_user_content() -> void:
	ModPackImporter.remove_tree(TEST_HOME)
	PATHS_SCRIPT.user_root = TEST_HOME
	PATHS_SCRIPT.prepare_user_root(TEST_HOME)


static func restore_user_content() -> void:
	PATHS_SCRIPT.user_root = PATHS_SCRIPT.USER_ROOT
	ModPackImporter.remove_tree(TEST_HOME)


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
