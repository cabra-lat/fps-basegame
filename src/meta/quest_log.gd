# res://src/meta/quest_log.gd
class_name QuestLog
extends RefCounted
## Quest definitions + live progress. Pure state: it never touches the profile.
## Progression subscribes to `quest_completed` to grant rewards, then calls
## mark_claimed(). This keeps the log testable without any save/player wiring.

signal quest_activated(quest: Quest)
signal quest_updated(quest: Quest, state: Dictionary)
signal quest_completed(quest: Quest)
signal changed

enum Status { LOCKED, ACTIVE, COMPLETE, CLAIMED }

var _quests: Dictionary = {} # id -> Quest
var _state: Dictionary = {} # id -> {"progress": Array[int], "status": int}

# ─── SETUP ──────────────────────────────────────────

func add_quest(q: Quest, activate: bool = true) -> void:
	if q == null or q.id == "":
		return
	_quests[q.id] = q
	if not _state.has(q.id):
		var prog: Array[int] = []
		prog.resize(q.objectives.size())
		prog.fill(0)
		_state[q.id] = {"progress": prog, "status": Status.LOCKED}
	_refresh_status(q.id, activate)
	changed.emit()

## Load every .tres in a directory (data-driven quest pack).
func load_dir(dir: String, activate: bool = true) -> int:
	var loaded := 0
	var d := DirAccess.open(dir)
	if d == null:
		return loaded
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var q := load(dir + "/" + f) as Quest
		if q == null or q.id == "":
			push_warning("QuestLog: bad quest resource %s/%s" % [dir, f])
			continue
		add_quest(q, activate)
		loaded += 1
	return loaded

func state_of(id: String) -> Dictionary:
	return _state.get(id, {})

func status_of(id: String) -> int:
	var st = _state.get(id, null)
	return int(st.status) if st != null else Status.LOCKED

func progress_of(id: String) -> Array:
	var st = _state.get(id, null)
	return (st.progress as Array) if st != null else []

func is_active(id: String) -> bool:
	return status_of(id) == Status.ACTIVE

func active_quests() -> Array[Quest]:
	var out: Array[Quest] = []
	for id in _quests:
		if is_active(id):
			out.append(_quests[id])
	return out

func mark_claimed(id: String) -> void:
	if not _state.has(id):
		return
	_state[id]["status"] = Status.CLAIMED
	# Prerequisites may unlock dependents now.
	for other_id in _quests:
		_refresh_status(other_id, true)
	changed.emit()

# ─── EVENT EVALUATION ───────────────────────────────

func on_kill(killer_id: int, victim_id: int, weapon: String, player_id: int) -> void:
	if killer_id != player_id:
		return
	for id in _active_ids():
		var q: Quest = _quests[id]
		for i in range(q.objectives.size()):
			var obj: QuestObjective = q.objectives[i]
			if obj.kind == QuestObjective.Kind.KILL and obj.matches_kill(weapon):
				_bump(id, i, 1)

func on_loot(item: Resource) -> void:
	for id in _active_ids():
		var q: Quest = _quests[id]
		for i in range(q.objectives.size()):
			var obj: QuestObjective = q.objectives[i]
			if obj.kind == QuestObjective.Kind.LOOT_ITEM and obj.matches_item(item):
				_bump(id, i, 1)

## Extraction objectives only count on a real SURVIVED (RUN_THROUGH excluded).
func on_extracted(point: Node, outcome: int) -> void:
	if outcome != Raid.Outcome.SURVIVED:
		return
	var pname := _point_name(point)
	for id in _active_ids():
		var q: Quest = _quests[id]
		for i in range(q.objectives.size()):
			var obj: QuestObjective = q.objectives[i]
			if obj.kind == QuestObjective.Kind.EXTRACT_AT and obj.matches_point(pname):
				_bump(id, i, 1)

func on_raid_ended(outcome: int) -> void:
	# "survive and extract" is SURVIVED only; RUN_THROUGH is explicitly excluded.
	if outcome == Raid.Outcome.SURVIVED:
		for id in _active_ids():
			var q: Quest = _quests[id]
			for i in range(q.objectives.size()):
				var obj: QuestObjective = q.objectives[i]
				if obj.kind == QuestObjective.Kind.SURVIVE_EXTRACT:
					_bump(id, i, 1)

# ─── STATE / REPORT ─────────────────────────────────

func progress_text() -> Array[String]:
	var out: Array[String] = []
	for q in active_quests():
		var parts: Array[String] = []
		var prog := progress_of(q.id)
		for i in range(q.objectives.size()):
			var obj: QuestObjective = q.objectives[i]
			parts.append("%s %d/%d" % [obj.describe(), int(prog[i]), obj.amount])
		out.append("%s: %s" % [q.display_title(), " | ".join(parts)])
	return out

func to_dict() -> Dictionary:
	var out := {}
	for id in _state:
		out[id] = {
			"progress": (_state[id]["progress"] as Array).duplicate(),
			"status": int(_state[id]["status"]),
		}
	return out

func apply_state(d) -> void:
	if not (d is Dictionary):
		return
	for id in d:
		if not _state.has(id):
			continue # quest resource no longer present; ignore gracefully
		var saved := d[id] as Dictionary
		var q: Quest = _quests[id]
		var prog: Array[int] = []
		prog.resize(q.objectives.size())
		prog.fill(0)
		var saved_prog = saved.get("progress", [])
		for i in range(mini(prog.size(), (saved_prog as Array).size())):
			prog[i] = maxi(int(saved_prog[i]), 0)
		_state[id] = {"progress": prog, "status": int(saved.get("status", Status.LOCKED))}
	for id in _quests:
		_refresh_status(id, true)

# ─── INTERNAL ───────────────────────────────────────

## Extraction point name, read as a property when present (ExtractionPoint)
## else from metadata — keeps the log free of scene-class dependencies.
func _point_name(point) -> String:
	if point == null:
		return ""
	if "display_name" in point:
		return String(point.display_name)
	return String(point.get_meta("display_name", ""))

func _active_ids() -> Array:
	var out: Array = []
	for id in _quests:
		if is_active(id):
			out.append(id)
	return out

func _refresh_status(id: String, activate: bool) -> void:
	if not _state.has(id):
		return
	if int(_state[id]["status"]) != Status.LOCKED:
		return
	if not activate:
		return
	var q: Quest = _quests[id]
	for req in q.requires:
		if status_of(req) != Status.CLAIMED:
			return
	_state[id]["status"] = Status.ACTIVE
	quest_activated.emit(q)

func _bump(id: String, index: int, amount: int) -> void:
	if not _state.has(id):
		return
	var q: Quest = _quests[id]
	var obj: QuestObjective = q.objectives[index]
	var prog: Array = _state[id]["progress"]
	if int(prog[index]) >= obj.amount:
		return
	prog[index] = mini(int(prog[index]) + amount, obj.amount)
	quest_updated.emit(q, _state[id])
	changed.emit()
	if _all_done(id):
		_state[id]["status"] = Status.COMPLETE
		quest_completed.emit(q)

func _all_done(id: String) -> bool:
	var q: Quest = _quests[id]
	var prog := progress_of(id)
	for i in range(q.objectives.size()):
		if int(prog[i]) < (q.objectives[i] as QuestObjective).amount:
			return false
	return true
