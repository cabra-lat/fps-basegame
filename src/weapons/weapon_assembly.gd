# res://src/weapons/weapon_assembly.gd
class_name WeaponAssembly
extends RefCounted

## Fit rules and stat resolution for a frankenstein weapon.
##
## WHAT THIS IS NOT. It is not a scene builder and not a recipe. Decision 2 is that
## a build SAVES AS AN ITEM -- one thing in the inventory, with its numbers baked in
## rather than a recipe re-evaluated at load. So this class validates and RESOLVES
## once, and what it produces is a flat set of numbers plus the part list that
## produced them. Assembling the scene is the weapon's job and already works: the
## scenes instance their own barrels and stocks.
##
## THE THREE FIT RULES, and where each comes from. Decision 3 says a barrel that
## does not fit the receiver does not go on, and that fit is a constraint a player
## can see rather than a free-for-all socket list. Reading that once gives all
## three, so none of them is a preference of mine:
##
##   ONE PART PER SOCKET. Two barrels on one receiver is the free-for-all the
##   decision names, and it is unreachable in the scene structure anyway: Stock and
##   Barrel are single Marker3D parents.
##   A PART MUST FIT THE RECEIVER. By declared receiver id, or by being authored
##   as a fit-any part.
##   CALIBRE MUST AGREE ALONG AN EDGE. A magazine has to match the barrel already
##   fitted. This is the same does-not-go-on rule applied along a different edge,
##   not a second rule.
##
## WHY REASONS ARE KEYS. A reason a player reads is a translation, and a
## translation needs a stable key. Composing an English sentence here would be a
## second source of copy that no catalogue owns, and it is the shape that made the
## hub's reasons unreadable. Every refusal returns a key; the caller renders it.

## Catalogue keys for every refusal. Present as constants rather than as literals
## at the raise sites so a reader can enumerate the whole vocabulary in one place
## and the harness can assert every key is translatable.
const REASON_NO_RECEIVER := "ASSEMBLY_NO_RECEIVER"
const REASON_PART_FIT := "ASSEMBLY_PART_DOES_NOT_FIT_RECEIVER"
const REASON_SOCKET_TAKEN := "ASSEMBLY_SOCKET_ALREADY_TAKEN"
const REASON_CALIBRE_MISMATCH := "ASSEMBLY_CALIBRE_MISMATCH"
const REASON_NO_PARTS := "ASSEMBLY_NO_PARTS"

## "any" is what a part declares when it does not participate in calibre matching. An
## explicit sentinel rather than an empty string, because  cannot take an
## empty first argument and because "" would read as "no calibre stated" in the data
## file, which is a different claim from "fits any".
const CALIBRE_ANY := "any"

const SOCKET_RECEIVER := &"Receiver"
const SOCKET_BARREL := &"Barrel"
const SOCKET_MAGAZINE := &"MagazinePoint"


## A validated assembly: the parts, and the stats they resolved to.
class Result extends RefCounted:
	var ok: bool = false
	## Empty when ok is true; otherwise exactly one catalogue key.
	var reason: String = ""
	## The part whose rejection produced the reason, for a message that names a
	## thing the player can act on rather than a category they cannot.
	var offending_part: String = ""
	var parts: Array = []
	var stats: Dictionary = {}

	func reason_line() -> String:
		if ok:
			return ""
		return reason


## Validate and resolve. `receiver_id` is the id of the weapon being built up;
## `base_stats` is the hand-tuned stat block the deltas apply to.
##
## NEVER returns a partially-valid Result. A build that half-applied is worse than
## one that was refused, because the player cannot tell which half they have.
static func assemble(receiver_id: String, parts: Array, base_stats: Dictionary) -> Result:
	var out := Result.new()
	if parts.is_empty():
		return _refuse(out, REASON_NO_PARTS, "")

	var taken: Dictionary = {}

	# The receiver comes first and is not optional: without it there is nothing for
	# the other parts to fit, and the parts' declared fits_receiver has no subject.
	var receiver: WeaponPart = null
	for part in parts:
		if part.socket == SOCKET_RECEIVER:
			receiver = part
			break
	if receiver == null:
		return _refuse(out, REASON_NO_RECEIVER, "")

	# TWO PASSES, and the second one exists because the first version of this was
	# ORDER-DEPENDENT, which the harness caught by listing the same parts in the
	# other order. A barrel sets the calibre, so a magazine written BEFORE the
	# barrel in the array had nothing to disagree with and sailed through. The same
	# parts would then assemble or refuse depending on how they were typed down,
	# which is not a rule, it is an accident of the array.
	#
	# Pass 1 fixes the calibre from the BARREL, regardless of position. Pass 2 then
	# applies every other rule. Splitting it also means the receiver, which must
	# also be found regardless of position, is settled before anything is judged
	# against it.
	var calibre := ""
	for part in parts:
		if part.socket == SOCKET_BARREL and _states_a_calibre(part):
			calibre = part.calibre
			break

	for part in parts:
		if part == receiver:
			continue
		# ONE PART PER SOCKET. Refused by name so the player knows WHICH part they
		# have to take off.
		if taken.has(part.socket):
			return _refuse(out, REASON_SOCKET_TAKEN, part.part_id())
		if not _fits_receiver(part, receiver_id):
			return _refuse(out, REASON_PART_FIT, part.part_id())
		# CALIBRE, against the barrel's, whichever came first in the list. A part
		# that states no calibre does not participate, so a stock cannot be refused
		# for a calibre it never claimed.
		if _states_a_calibre(part) and part.socket != SOCKET_BARREL:
			if calibre != "" and part.calibre != calibre:
				return _refuse(out, REASON_CALIBRE_MISMATCH, part.part_id())
		taken[part.socket] = part

	out.ok = true
	out.parts.assign(parts)
	out.stats = resolve_stats(parts, base_stats)
	return out


## Base stats plus every part's deltas, added.
##
## NOT a reimplementation of weapon stats. This reads whatever block the caller
## passes -- which is the weapon's own authored values -- and adds. It does not know
## what a weapon is, so it cannot drift from one.
static func resolve_stats(parts: Array, base_stats: Dictionary) -> Dictionary:
	var out := base_stats.duplicate(true)
	for part in parts:
		for field in part.stat_deltas():
			var delta: float = float(part.stat_deltas()[field])
			if is_zero_approx(delta):
				continue
			# A delta on a stat the base does not have is a DATA fault, not a
			# silent zero: creating the key would invent a stat the weapon never
			# had, and a part could then "work" on a field nobody reads.
			if not out.has(field):
				push_warning("part %s declares a delta for '%s', which the base stats do not have" % [part.part_id(), field])
				continue
			out[field] = float(out[field]) + delta
	return out


## A part participates in calibre matching only if it STATES one. "any" and the
## empty string both mean "does not constrain", so a stock is never refused for a
## calibre it never claimed.
static func _states_a_calibre(part: WeaponPart) -> bool:
	return part.calibre != "" and part.calibre != CALIBRE_ANY


## Fit-any is authored as an empty fits_receiver, so a generic magazine needs no
## per-receiver copy and a specific one is refused by name.
static func _fits_receiver(part: WeaponPart, receiver_id: String) -> bool:
	return part.fits_receiver == &"" or String(part.fits_receiver) == receiver_id


static func _refuse(out: Result, reason: String, part_id: String) -> Result:
	out.ok = false
	out.reason = reason
	out.offending_part = part_id
	return out


## Every reason this class can return, so a harness can assert the catalogue is
## complete rather than trusting a reader to have found them all.
static func all_reasons() -> Array[String]:
	return [
		REASON_NO_RECEIVER, REASON_PART_FIT, REASON_SOCKET_TAKEN,
		REASON_CALIBRE_MISMATCH, REASON_NO_PARTS,
	]