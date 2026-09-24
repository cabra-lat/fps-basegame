class_name Raid1Scenario
extends RefCounted
## Deterministic first-clear contract for the bounded 10-minute encounter.
## This is scene data, not a second raid state machine: Raid owns time/outcome,
## while this class owns the objective, destination gates, and carry manifest.

signal objective_changed(collected: bool)
signal scenario_finished(success: bool, destination: String)

enum State { PREP, ACTIVE, SUCCESS, FAILURE }

const DURATION_SECONDS := 600.0
const OBJECTIVE_ID := "marked_intel"
const OBJECTIVE_NAME := "Marked Intel"
const FALLBACK_NAME := "Open Lane"
const GATED_NAME := "Signal Gate"

var state: State = State.PREP
var objective_collected := false
var carried_item_id := ""
var destination := ""
var failure_reason := ""
var elapsed := 0.0

var _raid: Raid
var _profile: PlayerProfile
var _fallback: ExtractionPoint
var _gated: ExtractionPoint


func begin(raid: Raid, profile: PlayerProfile, fallback: ExtractionPoint, gated: ExtractionPoint) -> void:
	_raid = raid
	_profile = profile
	_fallback = fallback
	_gated = gated
	state = State.ACTIVE
	elapsed = 0.0
	objective_collected = false
	carried_item_id = ""
	destination = ""
	failure_reason = ""


func tick(delta: float) -> bool:
	if state != State.ACTIVE:
		return false
	elapsed = minf(DURATION_SECONDS, elapsed + maxf(delta, 0.0))
	if elapsed >= DURATION_SECONDS:
		fail("time limit")
		return true
	return false


func collect(item_id: String) -> bool:
	if state != State.ACTIVE or item_id != OBJECTIVE_ID or objective_collected:
		return false
	objective_collected = true
	carried_item_id = OBJECTIVE_ID
	if _profile != null:
		_profile.inventory[OBJECTIVE_ID] = 1
	objective_changed.emit(true)
	return true


func can_extract(point: ExtractionPoint) -> bool:
	if state != State.ACTIVE or point == null:
		return false
	return point == _fallback or (point == _gated and objective_collected)


func gate_text(point: ExtractionPoint) -> String:
	if point == _gated and not objective_collected:
		return "GATED: collect %s first" % OBJECTIVE_NAME
	return "OPEN: %s" % (FALLBACK_NAME if point == _fallback else GATED_NAME)


func prepare_success_carried(backpack: InventoryContainer) -> void:
	if backpack == null or state != State.ACTIVE:
		return
	# The first-clear contract deliberately banks only the marked intel. Medical
	# and incidental world loot remain raid loot and are not carried.
	for item in backpack.items.duplicate():
		if not bool(item.get_meta("raid1_carry", false)):
			backpack.remove_item(item)


func discard_carry(backpack: InventoryContainer) -> void:
	if backpack == null:
		return
	for item in backpack.items.duplicate():
		backpack.remove_item(item)


func fail(reason: String) -> void:
	if state != State.ACTIVE:
		return
	state = State.FAILURE
	carried_item_id = ""
	destination = ""
	failure_reason = reason
	if _profile != null:
		_profile.inventory.erase(OBJECTIVE_ID)
	scenario_finished.emit(false, "")


func complete(point: ExtractionPoint) -> void:
	if state != State.ACTIVE or point == null or not objective_collected:
		return
	state = State.SUCCESS
	destination = point.display_name
	if _profile != null:
		_profile.inventory.erase(OBJECTIVE_ID)
	scenario_finished.emit(true, destination)


func status_text() -> String:
	if state == State.SUCCESS:
		return "INTEL SECURED -> %s" % destination
	if state == State.FAILURE:
		return "RAID FAILED: %s" % failure_reason
	var objective := "SECURED" if objective_collected else "FIND %s" % OBJECTIVE_NAME
	return "%s | %s / %s" % [objective, _time_text(), "10:00"]


func _time_text() -> String:
	var remaining := int(ceil(maxf(DURATION_SECONDS - elapsed, 0.0)))
	return "%02d:%02d" % [remaining / 60, remaining % 60]
