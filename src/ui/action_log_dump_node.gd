class_name ActionLogDumpNode
extends Node

## The debug key. Dumps the action record to stdout and nothing else.
##
## WHY IT EXISTS AS A NODE rather than a static helper: a log that can only be
## read by attaching a debugger is no use to the person who has to answer "I
## clicked Modify and nothing happened", and an instrument that is never
## installed catches nothing. One node, one key, one line on stdout.
##
## WHAT IT DELIBERATELY IS NOT: not a panel, not an overlay, not a readout, and
## not anything the player can see. The RECORD is the permanent typed contract.
## Anything drawn on top of it is a debug consumer of the record, and the day a
## consumer becomes what people depend on, the split has been broken and the
## presentation needs to be rebuilt as a first-class thing rather than quietly
## promoted.
##
## F8 because it is not bound to anything the game uses. If it ever collides, the
## fix is to pick another key -- not to start arbitrating gameplay input here.

const DUMP_KEY := KEY_F8

signal dumped(text: String)


## The key that was actually pressed, as a KEYCODE_ name, for the banner line.
static func key_name() -> String:
	return OS.get_keycode_string(DUMP_KEY)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode != DUMP_KEY:
		return
	# consume(), so the debug key does not also reach the game's own input and
	# quietly do something. A debug instrument that perturbs what it measures is
	# not a debug instrument.
	get_viewport().set_input_as_handled()
	flush()


## Print the record. Split from the key handler so the harness can call the same
## function a player would trigger -- a dump path exercised only through a
## synthesised key event is a different code path from the one that ships.
func flush() -> String:
	var text := "action-log dump via %s\n%s" % [key_name(), ActionLog.dump()]
	print(text)
	dumped.emit(text)
	return text
