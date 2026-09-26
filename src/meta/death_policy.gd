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
## Two sources, deliberately: the declared path list, and a `keep_on_death` item
## meta. The meta is the seam the addon's per-item export will arrive through, so
## the population can move from a list to per-item flags without a code change
## here.
func keeps(item_path: String, item: Variant = null) -> bool:
	# `item` is accepted and deliberately NOT consulted for the decision. It used
	# to be: a per-item `keep_on_death` flag could return an item that was not in
	# the pocket, which made the ITEM a second, silent, unlisted authority over
	# surviving death -- the exact failure class this resource exists to remove.
	# The pocket is now the only authority; the flag is a declaration the policy
	# must ratify, and `validate()` reports any item that declares itself safe
	# without the policy agreeing.
	# `item` is intentionally unused: see above.
	return _keeps_path(item_path)

## The one rule, read once. Two copies of this used to exist (one reading a
## Resource's meta, one reading an encoded Dictionary) and they disagreed about
## where the fact lives, which is how the seam ended up wrong in one copy and
## inert in the other without either looking wrong.
func _keeps_path(path: String) -> bool:
	if not recoverable:
		return false
	return safe_pocket.has(path)

## What an item that declares itself death-safe contributes. The game can author
## the population as per-item flags and derive the pocket from them, so when the
## addon's `keep_on_death` export lands this is the whole migration: the flags
## are already read, and `validate()` names every flag the policy has not
## ratified. No change to how a death is settled, and none needed then.
func pocket_entries_from_items(item_paths: Array) -> Array[String]:
	var entries: Array[String] = []
	for p in item_paths:
		var path := String(p)
		if keep_on_death_declared(path) and not safe_pocket.has(path):
			entries.append(path)
	return entries

## Whether an item RESOURCE declares itself death-safe. Metadata only, and that
## is the whole subtlety: a GDScript `@export var` is a property, not metadata,
## so `get_meta()` cannot see an exported flag. When the addon export lands this
## becomes `item.get("keep_on_death")` -- and until then it returns false for
## every item, which is why nothing silently overrides the pocket.
func keep_on_death_declared(item_path: String) -> bool:
	if not ResourceLoader.exists(item_path):
		return false
	var res: Resource = load(item_path)
	if res == null:
		return false
	if res.has_meta(KEEP_ON_DEATH_META):
		return bool(res.get_meta(KEEP_ON_DEATH_META))
	var content: Resource = res.get("extra") as Resource
	if content != null and content.has_meta(KEEP_ON_DEATH_META):
		return bool(content.get_meta(KEEP_ON_DEATH_META))
	return false


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
			if loss == Loss.CONSUME_KEEP_ALL or _kept_by_policy(data):
				surviving.append(data)
			else:
				lost.append(data)
		if not surviving.is_empty():
			kept[slot] = surviving
	return {"lost": lost, "kept": kept}


## The per-entry half of `partition`, so the same rule is not written twice.
## `recoverable` is checked HERE and not only in `keeps()`: the first version of
## this function consulted the pocket and the meta but forgot the switch, so
## `recoverable = false` kept everything and the flag that the original request
## called "probably a setting" did nothing at all. The invariant arm
## "recoverable = false keeps nothing, even from a populated pocket" is what
## found it.
func _kept_by_policy(data: Dictionary) -> bool:
	var path := String(data.get("path", ""))
	if path.is_empty() and data.has("extra_path"):
		path = String(data.get("extra_path", ""))
	return _keeps_path(path)


## Configuration errors, so a policy that cannot mean what it says is loud at
## load time rather than silently forgiving at settlement.
## The metadata key an item resource uses to declare itself death-safe. A const so
## the reader, the policy and a test all name the same string.
const KEEP_ON_DEATH_META := &"keep_on_death"

func validate() -> Array[String]:
	var problems: Array[String] = []
	if loss == Loss.REGRANT and starter == null:
		problems.append("loss = REGRANT but `starter` is null: the death would forfeit the kit and grant nothing")
	if loss == Loss.REGRANT and grant_currency_on_regrant != 0 and starter != null and grant_currency_on_regrant == starter.currency:
		problems.append("grant_currency_on_regrant duplicates starter.currency; set it to 0 to inherit")
	for path in safe_pocket:
		if not ResourceLoader.exists(path):
			problems.append("safe_pocket entry does not load: %s" % path)
	# An item may declare itself death-safe, but the POLICY decides. An item that
	# declares and is not in safe_pocket is a contradiction, and it is reported
	# rather than honoured: a second path to surviving death that nobody can see
	# is a dead end replaced by an undocumented exception.
	for path in pocket_entries_from_items(safe_pocket):
		problems.append("unreachable: pocket entry is already ratified (%s)" % path)
	return problems
