# res://src/meta/trade_ops.gd
class_name TradeOps
extends RefCounted
## Shared item/currency/stash primitives. BOTH the trader Market and the
## FleaMarket go through here, so there is one validation path for
## "can afford / take from stash / deposit", not two.

static func count_in_stash(profile: MetaProfile, path: String) -> int:
	if profile == null or path == "":
		return 0
	var total := 0
	for item in profile.stash.items:
		if ItemCodec.content_path(item) == path:
			total += maxi(item.stack_count, 1)
	return total

## True when the item may leave the profile through a trade (trader sale, barter or
## flea listing). Starter gear is flagged `no_transfer` — it can be equipped and
## used, but it must not be laundered into the shared bank (see the roles design).
static func is_transferable(item: InventoryItem) -> bool:
	return item != null and not item.has_meta("no_transfer")

## Like `count_in_stash`, but only counts units the player is allowed to trade.
## Every trade path must use this one, otherwise a sell attempt succeeds on paper
## and then fails on the take (or, worse, takes the wrong copy).
static func count_transferable_in_stash(profile: MetaProfile, path: String) -> int:
	if profile == null or path == "":
		return 0
	var total := 0
	for item in profile.stash.items:
		if ItemCodec.content_path(item) == path and is_transferable(item):
			total += maxi(item.stack_count, 1)
	return total

static func find_stash_item(profile: MetaProfile, path: String) -> InventoryItem:
	if profile == null or path == "":
		return null
	for item in profile.stash.items:
		if ItemCodec.content_path(item) == path:
			return item
	return null

## The item a trade may actually take: the first TRANSFERABLE copy of `path`.
static func find_transferable_stash_item(profile: MetaProfile, path: String) -> InventoryItem:
	if profile == null or path == "":
		return null
	for item in profile.stash.items:
		if ItemCodec.content_path(item) == path and is_transferable(item):
			return item
	return null

## Remove `count` units of `path` from the stash. All-or-nothing.
static func take_from_stash(profile: MetaProfile, path: String, count: int) -> bool:
	if count <= 0:
		return true
	if count_transferable_in_stash(profile, path) < count:
		return false
	var remaining := count
	for item in profile.stash.items.duplicate():
		if ItemCodec.content_path(item) != path:
			continue
		if not is_transferable(item):
			continue # never take a non-transferable copy when a transferable one exists
		var take := mini(item.stack_count, remaining)
		if take >= item.stack_count:
			profile.stash.remove_item(item)
		else:
			item.stack_count -= take
		remaining -= take
		if remaining <= 0:
			break
	return remaining <= 0

static func deposit(profile: MetaProfile, item: InventoryItem) -> bool:
	return profile != null and item != null and profile.stash.deposit(item)

static func can_afford(profile: MetaProfile, amount: int) -> bool:
	return profile != null and (amount <= 0 or profile.currency >= amount)

static func charge(profile: MetaProfile, amount: int) -> bool:
	if not can_afford(profile, amount):
		return false
	profile.spend(amount)
	return true

static func credit(profile: MetaProfile, amount: int) -> void:
	if profile != null:
		profile.earn_currency(maxi(amount, 0))
