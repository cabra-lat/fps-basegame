# res://src/meta/validate_meta_flea.gd
#
# Headless gate for the flea market (second loot sink). Proves:
#   [A] NPC listings seeded from trader offers
#   [B] listing escrows the item (leaves the stash) and charges the fee
#   [C] clear refusals (bad price / item not in stash / fee unaffordable)
#   [D] cancel returns the escrowed item to the stash
#   [E] buying an NPC listing debits and delivers; own/repeat/poor refused
#   [F] expiry on the RAID counter returns the item
#   [G] a fairly priced listing sells on the next resolved raid (MetaService path)
#   [H] listings + stash + currency survive close/reopen
#
# Run:
#   godot --headless --path . --script res://src/meta/validate_meta_flea.gd
# Exit code: 0 = all checks passed, 1 = at least one failure.
extends SceneTree

const TEST_DIR := "user://meta_flea_test"
const SAVE := "user://meta_flea_test/profile.save"
const _FLEA_FRAME_KEY := "Listing #%d %s %d cr [%s] seller=%s"
const BANDAGE := "res://resources/medical/army_bandage.tres"

var v: ValidateUtil
var profile: MetaProfile

func _check(cond: bool, msg: String) -> void:
	v.check(cond, msg)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_flea")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()

	profile = MetaProfile.new()
	profile.market.load_dir()
	var seeded := profile.flea.seed_from_market(profile.market)
	_check(seeded > 0, "NPC listings seeded from trader offers (%d)" % seeded)

	_scenario_list_escrow()
	_scenario_list_refusals()
	_scenario_cancel()
	_scenario_buy_npc()
	_scenario_expiry()
	_scenario_fair_price_sale()
	_scenario_service_api()
	_scenario_persistence()

	quit(v.finish())

# ─── SCENARIOS ──────────────────────────────────────

func _scenario_list_escrow() -> void:
	v.section("[B] listing escrows the item and charges the fee")
	profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	var before := profile.market.count_in_stash(BANDAGE)
	var currency_before := profile.currency
	var r := profile.flea.list_from_stash(BANDAGE, 1000)
	_check(r.get("ok", false), "list ok (%s)" % r.get("reason", ""))
	var listing: FleaListing = r.get("listing")
	_check(listing != null and listing.status == FleaListing.Status.ACTIVE, "listing ACTIVE")
	_check(listing != null and listing.seller == FleaMarket.PLAYER_SELLER, "seller is the player")
	_check(profile.market.count_in_stash(BANDAGE) == before - 1, "escrow removed the item from the stash")
	_check(profile.currency == currency_before - profile.flea.listing_fee(1000), "listing fee charged (%d cr)" % profile.flea.listing_fee(1000))
	profile.flea.cancel(listing.id) # keep the pool clean for later scenarios

func _scenario_list_refusals() -> void:
	v.section("[C] listing refusals are clear")
	var r0 := profile.flea.list_from_stash(BANDAGE, 0)
	_check(not r0.get("ok", false) and String(r0.get("reason", "")).contains("preco"), "refused: preco (%s)" % r0.get("reason", ""))
	var r1 := profile.flea.list_from_stash("res://resources/weapons/M4_Carbine.tres", 1000)
	_check(not r1.get("ok", false) and String(r1.get("reason", "")).contains("item"), "refused: item ausente (%s)" % r1.get("reason", ""))
	profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	var saved_currency := profile.currency
	profile.currency = 0
	var r2 := profile.flea.list_from_stash(BANDAGE, 1000)
	_check(not r2.get("ok", false) and String(r2.get("reason", "")).contains("saldo"), "refused: taxa sem saldo (%s)" % r2.get("reason", ""))
	profile.currency = saved_currency

func _scenario_cancel() -> void:
	v.section("[D] cancel returns the escrowed item")
	var before := profile.market.count_in_stash(BANDAGE)
	var listing: FleaListing = profile.flea.list_from_stash(BANDAGE, 100000).get("listing")
	_check(profile.market.count_in_stash(BANDAGE) == before - 1, "item escrowed")
	var c := profile.flea.cancel(listing.id)
	_check(c.get("ok", false), "cancel ok")
	_check(listing.status == FleaListing.Status.CANCELLED, "listing CANCELLED")
	_check(profile.market.count_in_stash(BANDAGE) == before, "item returned to the stash")

func _scenario_buy_npc() -> void:
	v.section("[E] buying an NPC listing")
	var target: FleaListing = null
	for l in profile.flea.active_listings():
		if l.seller != FleaMarket.PLAYER_SELLER and (target == null or l.price < target.price):
			target = l
	_check(target != null, "an NPC listing exists")
	if target == null:
		return
	var currency_before := profile.currency
	var stash_before := profile.stash.count_items()
	var r := profile.flea.buy(target.id)
	_check(r.get("ok", false), "buy ok (%s)" % r.get("reason", ""))
	_check(profile.currency == currency_before - target.price, "currency debited (%d cr)" % target.price)
	_check(profile.stash.count_items() == stash_before + 1, "item delivered to the stash")
	_check(target.status == FleaListing.Status.SOLD, "listing SOLD")
	var again := profile.flea.buy(target.id)
	_check(not again.get("ok", false) and String(again.get("reason", "")).contains("indisponivel"), "repeat buy refused")

	# Own listing cannot be bought by the seller.
	var mine: FleaListing = profile.flea.list_from_stash(BANDAGE, 1000).get("listing")
	var own := profile.flea.buy(mine.id)
	_check(not own.get("ok", false) and String(own.get("reason", "")).contains("proprio"), "own listing refused")
	profile.flea.cancel(mine.id)

	# Insufficient funds.
	var saved := profile.currency
	profile.currency = 0
	var poor := profile.flea.buy(target.id)
	_check(not poor.get("ok", false), "no funds refused")
	profile.currency = saved

func _scenario_expiry() -> void:
	v.section("[F] expiry on the raid counter returns the item")
	var before := profile.market.count_in_stash(BANDAGE)
	var listing: FleaListing = profile.flea.list_from_stash(BANDAGE, 100000).get("listing")
	profile.raids = listing.listed_raid + listing.expiry_raids
	profile.flea.on_raid_resolved()
	_check(listing.status == FleaListing.Status.EXPIRED, "listing EXPIRED at the due raid")
	_check(profile.market.count_in_stash(BANDAGE) == before, "expired item returned to the stash")

func _scenario_fair_price_sale() -> void:
	v.section("[G] fair price sells on the next resolved raid (MetaService path)")
	profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	var listing: FleaListing = profile.flea.list_from_stash(BANDAGE, 1).get("listing")
	var currency_before := profile.currency
	var service := MetaService.new()
	service.save_path = SAVE
	service.use_profile(profile, SAVE)
	var eq := Equipment.new()
	var bag := Backpack.new()
	service.bind_carrier(eq, bag)
	service.resolve_raid(Raid.Outcome.SURVIVED, 0) # resolves -> flea clock ticks
	_check(listing.status == FleaListing.Status.SOLD, "fair listing SOLD on raid resolve")
	_check(profile.currency > currency_before, "seller credited %d cr" % listing.price)

## Exercises the MetaService (autoload) wrappers the arena/HUD will call.
func _scenario_service_api() -> void:
	v.section("[I] MetaService flea wrappers")
	var service := MetaService.new()
	service.save_path = SAVE
	service.use_profile(profile, SAVE)
	profile.stash.deposit(ItemCodec.item_from_path(BANDAGE))
	var lr := service.list_on_flea(BANDAGE, 100)
	_check(lr.get("ok", false), "Meta.list_on_flea ok (%s)" % lr.get("reason", ""))
	_check(service.flea_listing_fee(1000) == profile.flea.listing_fee(1000), "Meta.flea_listing_fee matches (%d)" % service.flea_listing_fee(1000))
	var listing: FleaListing = lr.get("listing")
	var flea_lines := service.flea_report_lines()
	# A CONTENT check, not `.size() > 0`. QA's review of 19a3043 is the reason:
	# the market's report line is verified for language
	# (validate_meta_market.gd asserts it contains "Comprar") while this one only
	# asserted that some string existed, so a line could be entirely English and
	# still pass. Two sibling report paths, two different standards, is how a
	# display line stays untranslated through a stack that is otherwise green.
	_check(not flea_lines.is_empty(), "Meta.flea_report_lines() non-empty")
	_check(flea_lines.size() > 0 and str(flea_lines[0]).contains(_flea_frame_word()),
		"Meta.flea_report_lines() renders in the catalogue language (line 0: %s, expected the frame word %s)" % [str(flea_lines[0] if not flea_lines.is_empty() else ""), _flea_frame_word()])
	# The negative half is what makes the positive half honest: with no catalogue
	# loaded, translate() returns the msgid, so the first word of the pattern is
	# the same in both languages and a contains() check would happily pass on the
	# raw English frame. Requiring the English word to be ABSENT is the check
	# that cannot be satisfied by an untranslated line.
	_check(flea_lines.size() > 0 and not str(flea_lines[0]).contains(_flea_key_word()),
		"Meta.flea_report_lines() does not leak the raw English frame (line 0: %s)" % str(flea_lines[0] if not flea_lines.is_empty() else ""))
	_check(service.cancel_flea(listing.id).get("ok", false), "Meta.cancel_flea ok")
	var target: FleaListing = null
	for l in profile.flea.active_listings():
		if l.seller != FleaMarket.PLAYER_SELLER and (target == null or l.price < target.price):
			target = l
	if target != null:
		var bought := service.buy_flea(target.id)
		_check(bought.get("ok", false), "Meta.buy_flea ok (%s)" % bought.get("reason", ""))
	service.persist() # wrappers mutate state; persistence is the caller's job

func _scenario_persistence() -> void:
	v.section("[H] flea + stash + currency survive close/reopen")
	var loaded := ProfileStore.load_profile(SAVE)
	_check(loaded != null, "profile reloads")
	_check(loaded.flea.listings.size() == profile.flea.listings.size(), "listings persisted (%d)" % loaded.flea.listings.size())
	var a := loaded.flea.count_by_status()
	var b := profile.flea.count_by_status()
	_check(a == b, "listing statuses persisted (%s vs %s)" % [a, b])
	_check(loaded.currency == profile.currency, "currency persisted (%d)" % loaded.currency)
	_check(loaded.stash.count_items() == profile.stash.count_items(), "stash persisted (%d)" % loaded.stash.count_items())

# ─── HELPERS ────────────────────────────────────────

func _cleanup() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)

## The first space-delimited word of the flea frame, taken from whichever
## language the catalogue resolved to. A word rather than the whole pattern,
## because "%d" and "%s" are substituted away by the time the line is rendered
## and the pattern itself can never appear inside its own output.
func _flea_frame_word() -> String:
	return TranslationServer.translate(_FLEA_FRAME_KEY).split(" ")[0]

## The same word as the catalogue leaves it when NOTHING is translated.
func _flea_key_word() -> String:
	return _FLEA_FRAME_KEY.split(" ")[0]
