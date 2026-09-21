# res://src/meta/validate_util.gd
class_name ValidateUtil
extends RefCounted
## Shared assertion/reporting scaffolding for the headless meta harnesses, so
## each validate_meta_*.gd only carries its scenarios.

var title: String
var passed: int = 0
var failed: int = 0

func _init(p_title: String = "validate") -> void:
	title = p_title

func begin() -> void:
	print("=== %s ===" % title)

func section(name: String) -> void:
	print("\n%s" % name)

func check(cond: bool, msg: String) -> bool:
	if cond:
		passed += 1
		print("  PASS  %s" % msg)
	else:
		failed += 1
		print("  FAIL  %s" % msg)
	return cond

## Prints the summary and returns the process exit code (0 = pass).
func finish() -> int:
	print("")
	print("=== summary ===")
	print("  passed  %d" % passed)
	print("  failed  %d" % failed)
	if failed > 0:
		print("RESULT: FAIL")
		return 1
	print("RESULT: PASS")
	return 0
