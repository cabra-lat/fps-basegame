# res://src/meta/free_items_view.gd
class_name FreeItemsView
extends RefCounted
## What the player can obtain for FREE, and what is still on its way.
##
## THE CARD IS "free-items marking when the player owns nothing", and the honest
## first question is where "owns nothing" actually comes from. It is NOT the starter
## grant: the coordinator decided the starter call site is FIRST DEPLOY and
## explicitly said not to add it yet, so a brand-new profile has no kit to mark in
## normal play. It IS reachable today through insurance. A KIA forfeits the
## deployed kit, register_loss() schedules the un-looted, insured items as a
## pending claim, and they are delivered on a LATER resolved raid. In the window
## between losing everything and the return landing, the player owns nothing and
## has a known, finite set of items on the way.
##
## That window is what this view describes, and it is the honest reading of the
## card: marking free items is only meaningful when the player can see WHY an item
## is not in their hands yet. A screen that listed "free items" without the delay
## would invite the player to think the system is broken during a window where it
## is behaving correctly.
##
## WHAT IS DELEGATED, because a second implementation of any of this is how the
## raid screen and this screen start disagreeing:
##   - pending_count()        the number of items awaiting return
##   - raids_until_next()     when the next return lands
##   - process_returns()      delivery, which only MetaService may drive
## This view reads and labels. It never moves an item and never decides a return.
##
## IDENTITY, per the tranche's correctness bar: names come from the ItemNames
## id-to-translation-key registry via the resource path, never from the "name"
## field the codec stores and never from a display string. A row whose path is not
## registered is reported as UNTRANSLATED rather than rendered as English, which is
## the difference the registry exists to make.

enum Reason {
	PENDING_RETURN, ## insured, lost, and due back on a later raid
	NOT_OWNED,      ## the player does not hold it yet
}

## Player-facing text is a KEY. This file never composes a sentence, and never
## hardcodes Portuguese, which is how the market feed once leaked
## "Comprou marked intel" into a translated frame.
const REASON_KEYS := {
	Reason.PENDING_RETURN: "FREE_ITEMS_REASON_PENDING_RETURN",
	Reason.NOT_OWNED: "FREE_ITEMS_REASON_NOT_OWNED",
}

var _profile: MetaProfile = null
var _insurance: Insurance = null


func _init(profile: MetaProfile = null, insurance: Insurance = null) -> void:
	_profile = profile
	_insurance = insurance


## One row per free item, with the reason it is not in hand. Data, not layout.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _insurance == null:
		return out
	for claim in _insurance.pending:
		var due_raid := int(claim.get("due_raid", 0))
		for data in claim.get("items", []):
			if not (data is Dictionary):
				continue
			out.append({
				"id": ItemNames.id_for_path(String(data.get("path", ""))),
				"path": String(data.get("path", "")),
				"translated": _is_translated(String(data.get("path", ""))),
				"reason": Reason.PENDING_RETURN,
				"key": REASON_KEYS[Reason.PENDING_RETURN],
				"due_raid": due_raid,
				"raids_until": _raids_until(due_raid),
			})
	return out


## Does the player currently hold NOTHING? This is the state the card is about, so
## it is asked of the profile's own reachable contents rather than of a panel, and
## it counts a nested container's contents once instead of once per path.
func owns_nothing() -> bool:
	if _profile == null:
		return false
	if not _profile.loadout.is_empty() or _profile.stash_item_count() > 0:
		return false
	# A pending claim is not ownership: those items are on the way, not in hand.
	# Counting them here would make this method always false in exactly the window
	# it exists to describe.
	return true


## The counts a screen needs, delegated to the owners of those numbers.
func pending_item_count() -> int:
	return _insurance.pending_count() if _insurance != null else 0


func raids_until_next_return() -> int:
	if _insurance == null or _profile == null:
		return 0
	return _insurance.raids_until_next(_profile)


## Is there anything to show at all? An empty free-items panel is noise, and the
## card's own worry is a screen that looks finished while showing nothing.
func has_free_items() -> bool:
	return not rows().is_empty()


func _raids_until(due_raid: int) -> int:
	if _profile == null:
		return maxi(due_raid - 0, 0)
	return maxi(due_raid - _profile.raids, 0)


## Registered in the catalogue, so the row can render through translation. A row
## that cannot is marked, not shown as English: that is the whole point of the
## registry and the reason an unregistered id must be visible rather than silent.
func _is_translated(path: String) -> bool:
	var id := ItemNames.id_for_path(path)
	if id == "":
		return false
	return TranslationServer.translate(ItemNames.key_for(id)) != ItemNames.key_for(id)
