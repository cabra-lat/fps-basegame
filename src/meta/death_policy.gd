# res://src/meta/death_policy.gd
class_name DeathPolicy
extends Resource
## What a death costs the player. DATA, per the project's rule that content is
## data and mechanics may be enums: a game ships its own `.tres` and never
## edits this file.
##
## The values below are the human's answer as derived by the coordinator
## (2026-09-26) and they are not a four-way taste question:
##
##   loss = CONSUME   the deployed kit is lost, with a recoverable subset.
##                    This is the only reading under which BOTH a safe pocket
##                    and recoverable gear are doing any work. CONSUME_KEEP_ALL
##                    keeps everything, which is the absence of a pocket, and
##                    REGRANT discards everything, which is the absence of a
##                    pocket being worth protecting.
##
## `safe_pocket` is the population, as resource paths rather than a per-item
## export. The design called for `ItemDef.keep_on_death`; `Item` lives in
## addons/cabra.lat_shooters, which is a separate repository, so adding the
## export there is the addon's to make and not mine to commit. A path list in
## this `.tres` is the same declaration with the same editability -- "a handful
## of items" becomes a `.tres` edit either way -- and `keeps()` also honours a
## `keep_on_death` item meta so the day the export lands, nothing here changes.

enum Loss {
	## The deployed kit is lost. Only the safe pocket and un-equipped entries
	## come back. This is what shipped before the policy existed.
	CONSUME,
	## Everything the player deployed comes back.
	CONSUME_KEEP_ALL,
	## The kit is lost and `starter` is granted again.
	REGRANT,
}

## What a death leaves behind in `profile.loadout`, and which entries survive.
@export var loss: Loss = Loss.CONSUME

## Used when `loss == REGRANT`. Null in the shipped policy, and a REGRANT policy
## with no starter is a configuration error the invariant below names.
@export var starter: StarterLoadout = null

## Currency added alongside a REGRANT. 0 means "use the starter's own value",
## which keeps the two numbers from being able to disagree silently.
@export_range(0, 1000000, 100) var grant_currency_on_regrant: int = 0

## The safe pocket: item resource paths that survive a death. Declared here
## rather than on each item so the population is one editable list, and so the
## shipped default is populated rather than a word in a design doc.
@export var safe_pocket: Array[String] = []

## Recoverable gear: if false, a death forfeits the kit outright and insurance
## is the only route back. If true, the safe pocket survives directly. The
## original request called this "probably a setting"; it is one export.
@export var recoverable: bool = true

## Whether a role's granted kit is exempt. A free-entry role that hands out a kit
## which the first death then eats is a role that gives the item back once.
@export var preserves_role_kit: bool = true


## True when this item survives a death under this policy.
##
## SEMANTICS CALL, 2026-09-27 (meta, after inventory-ux reported the divergence
## against StashView). This is the GENERAL "is this spared" query, NOT a pocket
## query, and it reads `loss` as well as the pocket. The evidence that settled it,
## in the order it decided it:
##
##   1. THIS FILE ALREADY SET THE PRECEDENT FOR THE OTHER DIRECTION. `recoverable`
##      was missed in exactly this way once -- the first `_kept_by_policy`
##      consulted the pocket and the meta but forgot the switch -- and the fix was
##      to consult it in BOTH entry points, not to narrow either one. `loss` is
##      the same class of switch, so the same answer applies.
##   2. `keeps()` HAD NO CALL SITES AT ALL on main. Nothing depended on the narrow
##      reading, so choosing it would have protected nothing and cost correctness.
##   3. THE POCKET QUESTION IS ALREADY ANSWERED ELSEWHERE. StashView carries
##      `safe_pocket_rows()` and `recoverable_rows()`, which are the honest pocket
##      queries. If `keeps()` were the pocket query it would be a third answer to
##      a question two dedicated methods already own.
##
## Both entry points now delegate to `_spared()`, so they cannot diverge by
## omission again, which is the actual fix. Adding the `loss` test to this
## function alone would have made the two agree today and left the next switch
## free to be missed in one of them again.
func keeps(item_path: String, item: Variant = null) -> bool:
	var flagged := item != null and bool(item.get_meta("keep_on_death", false))
	return _spared(item_path, flagged)


## One definition of "this policy spares this item", consulted by every entry
## point. `flagged` is the per-item `keep_on_death` signal, which arrives as an
## item meta from a caller holding an Item and as a manifest field from
## `partition` holding encoded data; both are folded in here so the two shapes
## cannot answer differently.
func _spared(item_path: String, flagged: bool = false) -> bool:
	# The switch comes FIRST and overrides everything below it. Under KEEP_ALL the
	# deployed kit comes back whole, so the pocket list and the recoverable flag
	# have nothing left to decide. Reading it after `recoverable` would let
	# `recoverable = false` claim to destroy a kit the switch already returned,
	# which is the same class of bug this function exists to prevent.
	if loss == Loss.CONSUME_KEEP_ALL:
		return true
	if not recoverable:
		return false
	if safe_pocket.has(item_path):
		return true
	return flagged


## Split a carried manifest into the entries this policy destroys and the ones it
## returns. `carried_loadout` is slot -> Array[Dictionary] of encoded items, the
## shape `_resolve_loss` already has in hand.
func partition(carried_loadout: Dictionary) -> Dictionary:
	var lost: Array = []
	var kept: Dictionary = {}
	for slot in carried_loadout:
		var entries: Array = carried_loadout[slot]
		var surviving: Array = []
		for data in entries:
			if _kept_by_policy(data):
				surviving.append(data)
			else:
				lost.append(data)
		if not surviving.is_empty():
			kept[slot] = surviving
	return {"lost": lost, "kept": kept}


## The per-entry half of `partition`, so the same rule is not written twice.
## It holds no rule of its own any more: it normalises a manifest entry into a
## path and a flag and hands both to `_spared`. That is the point of the refactor
## -- while this function carried its own copy of the test, a switch added to one
## entry point silently missed the other, which is the divergence inventory-ux
## found on 2026-09-27 and pinned rather than patched.
func _kept_by_policy(data: Dictionary) -> bool:
	var path := String(data.get("path", ""))
	if path.is_empty() and data.has("extra_path"):
		path = String(data.get("extra_path", ""))
	return _spared(path, bool(data.get("keep_on_death", false)))


## Configuration errors, so a policy that cannot mean what it says is loud at
## load time rather than silently forgiving at settlement.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if loss == Loss.REGRANT and starter == null:
		problems.append("loss = REGRANT but `starter` is null: the death would forfeit the kit and grant nothing")
	if loss == Loss.REGRANT and grant_currency_on_regrant != 0 and starter != null and grant_currency_on_regrant == starter.currency:
		problems.append("grant_currency_on_regrant duplicates starter.currency; set it to 0 to inherit")
	for path in safe_pocket:
		if not ResourceLoader.exists(path):
			problems.append("safe_pocket entry does not load: %s" % path)
	return problems
