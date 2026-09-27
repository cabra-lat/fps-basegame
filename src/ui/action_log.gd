class_name ActionLog
extends RefCounted

## The timestamped action record (f5cac6).
##
## WHY TWO PHASES. A click fails two ways that look identical from the player's
## side: it never reached the control, or it reached the control and the handler
## did nothing. A log that records only receipt cannot tell those apart -- which is
## why one report tonight said the gunsmith route was closed and another said three
## signals had zero handlers: both true, both describing a different half of the
## same silence. So REACHED and RESULT are SEPARATE entries:
##
##   REACHED with no RESULT  -> the handler ran and did not settle. A stuck or
##                              crashed handler, not a missing wiring.
##   RESULT with no REACHED  -> impossible by construction, and the harness checks
##                              that pairing too.
##   neither                 -> the click never got here.
##
## NOT A UI SURFACE, and deliberately not one. No panel, no colours, no overlay
## the player can see. The RECORD is the permanent typed contract; anything drawn
## on top of it is a debug consumer and is not what a future game consumes. Same
## split as the impact-result card: signals are permanent and typed, presentation
## is a debug consumer of them. If a readout ever grows to be the thing people
## depend on, the split has been broken.
##
## BOUNDED, in memory, global, and reachable with no file and no debugger. An
## unbounded log is a memory leak that eventually takes the process down, and a log
## you can only read by attaching a debugger is no help to the person reporting
## "nothing happened" -- which is the entire reason this exists.

## What happened to the action. Deliberately only three values: the middle ground
## between "worked" and "did not" is a bug report, not a category.
enum Result { OK, NO_OP, REFUSED }

## Why a NO_OP is different from an absent entry. Absent means nobody knows; a
## NO_OP means the click arrived and was understood and there was a reason it did
## not apply, and that reason is a fixable thing with an owner.
enum Phase { REACHED, RESULT }

const DEFAULT_CAPACITY := 256

static var _entries: Array[Dictionary] = []
static var _capacity := 256
static var _next_seq := 1


## Bound the buffer. Called from a project setting or by the harness; anything
## that raises the buffer pays for it at record time, so this is not free.
static func configure(capacity: int) -> void:
	_capacity = maxi(1, capacity)
	_trim()


## Drop every entry. Test affordance ONLY -- a build that calls this at runtime
## destroys the one thing a bug report needs.
static func clear() -> void:
	_entries.clear()


static func size() -> int:
	return _entries.size()


static func capacity() -> int:
	return _capacity


## Oldest first, so a pasted dump reads in the order the player clicked.
static func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## The control was activated. Call this at the TOP of a handler, before the work,
## because a REACHED recorded after the work has already happened cannot prove the
## click arrived first.
##
## Returns a handle for settle(), so a result pairs with the reach that caused it
## even if two controls are clicked between the two calls.
static func reached(control: String, action: String, target: String = "") -> int:
	var seq := _next_seq
	_next_seq += 1
	_append({
		"seq": seq,
		"at": _stamp(),
		"phase": Phase.REACHED,
		"control": control,
		"action": action,
		"target": target,
		"result": -1,
		"reason": "",
	})
	return seq


## The handler finished. `handle` is the value reached() returned; -1 settles
## without pairing, which is legal but worth avoiding because it is how a result
## gets attached to the wrong click.
static func settle(handle: int, result: Result, reason: String = "", target: String = "") -> void:
	var control := ""
	var action := ""
	if handle > 0:
		for entry in _entries:
			if int(entry.get("seq", -1)) == handle:
				control = String(entry.get("control", ""))
				action = String(entry.get("action", ""))
				break
	_append({
		"seq": handle,
		"at": _stamp(),
		"phase": Phase.RESULT,
		"control": control,
		"action": action,
		"target": target,
		"result": int(result),
		"reason": reason,
	})


## Convenience for a handler that has nothing to refuse on.
static func ok(handle: int, target: String = "") -> void:
	settle(handle, Result.OK, "", target)


## A refusal or a deliberate no-op MUST carry a reason. An empty reason is a
## defect in the caller, so it is not quietly accepted: the entry is still written
## (so the click is accounted for) and the gap is visible in the dump.
static func no_op(handle: int, reason: String, target: String = "") -> void:
	settle(handle, Result.NO_OP, reason, target)


static func refused(handle: int, reason: String, target: String = "") -> void:
	settle(handle, Result.REFUSED, reason, target)


static func result_name(value: int) -> String:
	match value:
		Result.OK: return "OK"
		Result.NO_OP: return "NO_OP"
		Result.REFUSED: return "REFUSED"
	return "INVALID"


static func phase_name(value: int) -> String:
	return "REACHED" if value == Phase.REACHED else "RESULT"


## One line per entry, greppable and diffable. A dump nobody can grep is a
## screenshot with extra steps.
static func format_line(entry: Dictionary) -> String:
	var parts: Array[String] = [
		String(entry.get("at", "")),
		"seq=%d" % int(entry.get("seq", -1)),
		phase_name(int(entry.get("phase", -1))),
		"control=%s" % String(entry.get("control", "")),
		"action=%s" % String(entry.get("action", "")),
	]
	var target := String(entry.get("target", ""))
	if not target.is_empty():
		parts.append("target=%s" % target)
	var result := int(entry.get("result", -1))
	if int(entry.get("phase", -1)) == Phase.RESULT:
		parts.append("result=%s" % result_name(result))
		var reason := String(entry.get("reason", ""))
		if not reason.is_empty():
			parts.append("reason=%s" % reason)
	return " ".join(parts)


## The pasteable answer to "nothing happened".
static func dump() -> String:
	var lines: Array[String] = ["action-log %d/%d" % [_entries.size(), _capacity]]
	for entry in _entries:
		lines.append(format_line(entry))
	return "\n".join(lines)


static func dump_to_stdout() -> void:
	print(dump())


static func _append(entry: Dictionary) -> void:
	_entries.append(entry)
	_trim()


## Oldest first, bounded. Dropping the FRONT is the right direction: a bug report
## is about what just happened, so the newest entries are the ones worth keeping.
static func _trim() -> void:
	while _entries.size() > _capacity:
		_entries.pop_front()


## ISO-8601 UTC with milliseconds.
##
## Built by hand rather than from Time.get_datetime_string_from_system() because
## that returns seconds and truncates the millisecond field, and a log that
## resolves two rapid clicks to the same timestamp cannot show that two clicks
## happened -- which is the case this log exists for.
static func _stamp() -> String:
	var now := Time.get_unix_time_from_system()
	var whole := int(now)
	var ms := int(round((now - float(whole)) * 1000.0))
	# A rounding artefact at the boundary can produce 1000ms; carry it.
	if ms >= 1000:
		whole += 1
		ms = 0
	var d := Time.get_datetime_dict_from_unix_time(whole)
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [
		d.year, d.month, d.day, d.hour, d.minute, d.second, ms,
	]
