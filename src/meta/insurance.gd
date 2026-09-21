# res://src/meta/insurance.gd
class_name Insurance
extends RefCounted
## End-of-raid insurance. A manifest of insured gear is composed when entering
## the raid; on KIA/MIA the non-looted pieces are scheduled to come back after a
## delay. Maps flagged "no return" never pay out, and items taken by the killer
## are excluded.

signal claim_registered(claim: Dictionary)
signal claim_returned(items: Array)

const DEFAULT_DELAY_RAIDS := 1

## Each entry: {"items": Array[Dictionary], "due_raid": int, "reason": String}
var pending: Array[Dictionary] = []
## Last batch delivered (for the report screen).
var last_returned: Array = []

func pending_count() -> int:
	var n := 0
	for claim in pending:
		n += (claim.get("items", []) as Array).size()
	return n

func clear() -> void:
	pending.clear()
	last_returned.clear()

## Schedule the return of `items` (ItemCodec dictionaries) that were not looted
## and are not on a no-return map. Returns how many items were insured.
func register_loss(items: Array, profile: MetaProfile, no_return: bool = false,
		looted_paths: Array = [], delay_raids: int = DEFAULT_DELAY_RAIDS) -> int:
	if no_return or profile == null:
		return 0
	var keep: Array = []
	for d in items:
		if not (d is Dictionary):
			continue
		if looted_paths.has(String(d.get("path", ""))):
			continue
		keep.append(d)
	if keep.is_empty():
		return 0
	var claim := {
		"items": keep,
		"due_raid": profile.raids + maxi(delay_raids, 0),
		"reason": "KIA/MIA",
	}
	pending.append(claim)
	claim_registered.emit(claim)
	return keep.size()

## Deliver every claim that is due; items that do not fit stay pending.
func process_returns(profile: MetaProfile) -> Array:
	var delivered: Array = []
	if profile == null:
		return delivered
	for claim in pending.duplicate():
		if int(claim.get("due_raid", 0)) > profile.raids:
			continue
		var undelivered: Array = []
		for d in claim.get("items", []):
			var item := ItemCodec.decode_item(d)
			if item == null:
				continue
			if profile.stash.deposit(item):
				delivered.append(d)
			else:
				undelivered.append(d)
		pending.erase(claim)
		if not undelivered.is_empty():
			pending.append({"items": undelivered, "due_raid": profile.raids + 1, "reason": "stash full"})
	if not delivered.is_empty():
		last_returned = delivered.duplicate(true)
		claim_returned.emit(delivered)
	return delivered

## Raids still to wait before the earliest claim comes back (0 = due now).
func raids_until_next(profile: MetaProfile) -> int:
	if profile == null or pending.is_empty():
		return 0
	var best := 1 << 30
	for claim in pending:
		best = mini(best, int(claim.get("due_raid", 0)))
	return maxi(best - profile.raids, 0)

func summary(profile: MetaProfile = null) -> String:
	if pending.is_empty():
		return ""
	return "%d item(ns) segurados a caminho (em %d raid(s))" % [pending_count(), raids_until_next(profile)]

func to_dict() -> Dictionary:
	return {
		"pending": pending.duplicate(true),
		"last_returned": last_returned.duplicate(true),
	}

func apply_state(d) -> void:
	if not (d is Dictionary):
		return
	var p = d.get("pending", [])
	if p is Array:
		for claim in p:
			if claim is Dictionary:
				pending.append(claim)
	var r = d.get("last_returned", [])
	if r is Array:
		for item in r:
			if item is Dictionary:
				last_returned.append(item)
