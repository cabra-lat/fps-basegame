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
## The locale this harness asserts against. Taken BEFORE anything is built,
## because a headless run inherits the host's active locale and this harness
## asserts on translated text: under an `en` host the line renders the English
## frame and the two checks below fail for a reason that has nothing to do with
## the flea. Measured, not assumed -- this harness is what made the dependency
## visible once the rest of the suite had the precondition.
const TranslationProbe := preload("res://src/meta/translation_probe.gd")
const BANDAGE := "res://resources/medical/army_bandage.tres"
## Developer placeholder text that must never ship. Matched as a SUBSTRING so a
## scaffold line is caught whatever noun the class uses, and kept as a list so a
## new one is a one-line addition rather than a new rule.
const SCAFFOLD_DESCRIPTION_MARKERS: Array[String] = [
	"is the default one",
	"Generic ammunition",
	"Default armor.",
]

var v: ValidateUtil
var profile: MetaProfile

func _check(cond: bool, msg: String) -> void:
	v.check(cond, msg)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_flea")
	v.begin()
	# Precondition, before anything is built: the locale this harness asserts
	# against must be the ACTIVE one, not inherited from the host. Asserted, not
	# assumed -- a harness that silently failed to select would report a missing
	# translation for a catalogue that is complete.
	TranslationProbe.select_test_locale()
	v.check(TranslationProbe.locale_is_selected(),
		"the harness pins the locale it asserts against (%s)" % TranslationProbe.PROBE_LOCALE)
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
	_check_description_tail()
	_check_no_scaffold_descriptions_in_shipped_resources()
	_check_trader_set_is_data()
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
## The optional description tail: the positive half (a described item's line ends
## with its resolved, translated prose) and the negative half (an undescribed
## item's line has no tail, no gap, and no invented "no description" text).
##
## Both halves are needed, and the negative one is the half that can go quietly.
## A check that only asserts "a described item shows a description" passes on a
## build where the tail is ALWAYS appended -- including to items that have no
## description, which is how a frame ends up with a trailing "-- " and nothing
## after it. That is the empty-gap outcome this design exists to avoid, and only
## the negative half rules it out.
##
## The placeholder half is here too, and it is a live finding rather than a
## hypothetical: `M4_Carbine.tres` declares no `description` line at all, and on
## an addon build predating 0a5f3aa it reports the CLASS DEFAULT
## ("This Weapon is the default one."). A reader shipped before the addon fix
## would therefore have rendered that scaffold text into the flea frame for any
## undescribed weapon. This asserts the fix has landed, which is the ordering
## dependency made executable.
func _check_description_tail() -> void:
	v.section("[J] the description tail is optional, resolved, and honest")
	_check(ResourceLoader.exists(BANDAGE), "description fixture exists: %s" % BANDAGE.get_file())
	if not ResourceLoader.exists(BANDAGE):
		return

	# POSITIVE: a described, translated item shows its prose, and the prose is the
	# CATALOGUE's, not the English source.
	var described := _line_for(BANDAGE)
	var src := ItemDescriptions.source_text(load(BANDAGE))
	var resolved := ItemDescriptions.display_description(load(BANDAGE))
	_check(resolved != "" and resolved != src,
		"a described item resolves to catalogue prose, not the English source ('%s')" % resolved)
	_check(described.ends_with(" -- " + resolved),
		"a described item's line ends with ' -- <resolved prose>' (line: %s)" % described)
	_check(not described.contains(src) and resolved != src,
		"a described item's line carries no English source prose (line: %s)" % described)

	# NEGATIVE: an item with NO description gets no tail. Asserted on a resource
	# that genuinely declares none, and on the rendered line rather than on the
	# helper, because the bug this catches lives in line() and not in the reader.
	var bare := "res://resources/weapons/M4_Carbine.tres"
	var bare_line := _line_for(bare)
	var bare_desc := ItemDescriptions.display_description(load(bare))
	_check(bare_desc == "",
		"an undescribed item resolves to no description (got '%s')" % bare_desc)
	_check(not bare_line.ends_with(" --"),
		"an undescribed item's line has NO trailing separator (line: %s)" % bare_line)
	_check(not bare_line.contains(" -- "),
		"an undescribed item's line has no description segment at all (line: %s)" % bare_line)

	# THE PLACEHOLDER ARM, which is the whole reason the tail is optional. If the
	# addon's default-empty change has NOT landed, an undescribed weapon still
	# answers the class default, and the frame would read
	#   "Anúncio #1 Carabina M4 900 cr [Ativo] vendedor=x -- This Weapon is the default one."
	_check(ItemDescriptions.source_text(load(bare)) == "",
		"an undescribed item does not report a CLASS DEFAULT description (got '%s')"
			% ItemDescriptions.source_text(load(bare)))

	# And the scaffold text must never reach a frame, wherever it comes from.
	# Enumerated from the trader RESOURCES rather than hardcoded here, so a new
	# offer cannot slip past by being omitted from a list.
	# CORRECTION to the comment that used to stand here, which cited
	# validate_i18n.gd's _trader_item_paths() as following the same rule. It does
	# not: that function enumerates OFFERS from the trader resources (true) while
	# hardcoding the three trader PATHS three lines above the offers loop
	# (validate_i18n.gd:480-482), and its own comment claims the opposite. I cited
	# it as precedent without reading it, which is the same mistake as citing a
	# README, so the precedent claim is gone rather than repeated.
	var scaffold: Array[String] = []
	for path in _offered_item_paths():
		var text := ItemDescriptions.source_text(load(path))
		if text.contains("default one") or text.contains("Generic ammunition") or text.contains("Default armor."):
			scaffold.append(path.get_file())
	_check(not _offered_item_paths().is_empty() and scaffold.is_empty(),
		"no item offered to a trader carries scaffold description text (checked %d, scaffold: %s)"
			% [_offered_item_paths().size(), str(scaffold)])

## Every shipped resource, at any nesting depth, not just what a trader offers.
## CAUGHT 2026-09-26, the way the finding that prompted it says it should be
## caught: coordinator asked whether any OTHER class carried the same scaffold
## string, on the grounds that a check which found one instance will not find the
## other five. It could not. The existing check above reads `source_text()`, which
## is the TOP-LEVEL item's description, and the scaffold text turned out to live
## 16 times in NESTED sub-resources (15 Ammofeed blocks inside weapon .tres files,
## 1 Attachment), where a top-level reader cannot see it -- and one of the three
## traders' item sets does not happen to include PEQ-15, so even a full scan of
## the offered set would have missed it. A raw text scan is the only mechanism
## that closes the gap by construction: the string cannot hide from a scan of the
## file it is written in, at any depth, loaded or not.
##
## Its red arm is the data it removed: re-adding any one of the 16 lines turns
## this check red while every other check in this file stays green.
func _check_no_scaffold_descriptions_in_shipped_resources() -> void:
	v.section("[K] no shipped resource declares a scaffold description")
	var hits: Array[String] = []
	var paths := _shipped_resource_paths("res://resources/")
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		for line in text.split("\n"):
			var trimmed := String(line).strip_edges()
			if not trimmed.begins_with("description"):
				continue
			for marker in SCAFFOLD_DESCRIPTION_MARKERS:
				if trimmed.contains(marker):
					hits.append("%s: %s" % [path.get_file(), trimmed])
					break
	_check(paths.size() > 0, "the scan actually found resources to read (scanned %d)" % paths.size())
	_check(hits.is_empty(),
		"no shipped resource declares a scaffold description at any depth (scanned %d, hits: %s)"
			% [paths.size(), str(hits)])

## Every .tres under `root`, recursively. Enumerated from the filesystem rather
## than a hardcoded list for the same reason the trader items are: a resource
## nobody remembered to list is exactly the one that ships broken.
func _shipped_resource_paths(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_shipped_resource_paths(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out

## THE FLEA SUBJECT, deliberately outside the trader set. The raid mission item
## is listable even though no trader stocks it, which is the whole point of a flea
## market, so it is named here rather than smuggled in as a fourth trader.
const FLEA_SUBJECT := "res://resources/raid1/marked_intel.tres"
## Where the trader set LIVES. The set is the directory: a trader exists because
## its resource is in here, and adding a fourth trader is dropping a file in, not
## editing three harnesses.
const TRADERS_DIR := "res://resources/meta/traders/"

## The trader set is DATA, and this is the check that says so.
## CAUGHT 2026-09-26, in a review of my own work rather than in a failure:
## _offered_item_paths() listed the three trader .tres paths as literals, so the
## third trader was a string in a test I wrote and a fourth trader needed a code
## edit. That is the exact mistake AGENTS.md names -- "Hardcoding a faction list is
## the same mistake as hardcoding the weapon list" -- and the irony is not lost on me
## that the same reading of paperclip's declarative registry, which I had just
## written up as the thing worth copying, was describing the fix for a literal list
## sitting in my own harness.
##
## Paperclip's registry is worth more than its shape here, because of the one check
## that shape comes with: "throws when a declared adapter has no installed
## implementation" (adapter-registry-bootstrap.reconcile.test.ts). A trader may
## therefore DECLARE an offer, but every declared offer must resolve to a real
## resource -- advertising stock that cannot be loaded is the same class of defect as
## offering a harness that does not exist, and in this codebase it is worse, because
## market.gd:157 charges the player and takes barter goods BEFORE it resolves
## item_path, and returns "item indisponivel" with the money already gone.
##
## Deliberately NOT enforced here: that a declared trader has no runtime scene.
## trader_point.gd binds a trader by GROUP plus a trader_id, so the mapping is
## scene-side and there is no data field to check; paperclip could throw because its
## adapter type names an installed module, and we cannot, which is the asymmetry
## behind "copy the shape, not the behaviour" from the same review.
func _check_trader_set_is_data() -> void:
	v.section("[L] the trader set is data, not a list of literals")
	var paths := _trader_resource_paths()
	# Non-vacuity FIRST. An enumeration that finds nothing must not read as
	# "no scaffold text" and "no bad offers" -- that is how a directory typo turns
	# this section into four vacuous passes.
	_check(paths.size() > 0,
		"the trader directory is enumerable, not missing (found %d, dir %s)"
			% [paths.size(), TRADERS_DIR])

	var declared_offers := 0
	var declared_paths: Dictionary = {}
	var bad_ids: Array[String] = []
	var empty_offers: Array[String] = []
	var unimplemented: Array[String] = []
	var offered := _offered_item_paths()
	for path in paths:
		var t := load(path) as Resource
		if t == null:
			bad_ids.append("%s: not loadable" % path.get_file())
			continue
		var id := String(t.get("id"))
		if id == "":
			bad_ids.append("%s: no trader id" % path.get_file())
		var offers: Array = t.get("offers") as Array
		if offers.is_empty():
			empty_offers.append(path.get_file())
		for offer in offers:
			if offer == null:
				unimplemented.append("%s: null offer" % path.get_file())
				continue
			var item_path := String((offer as Resource).get("item_path"))
			declared_offers += 1
			# The paperclip check, on our data: declared but not implemented fails.
			if item_path == "" or not ResourceLoader.exists(item_path):
				unimplemented.append("%s: %s" % [path.get_file(), item_path if item_path != "" else "<empty item_path>"])
			declared_paths[item_path] = true
	_check(bad_ids.is_empty(), "every trader resource loads and carries an id (bad: %s)" % str(bad_ids))
	_check(empty_offers.is_empty(), "every trader stocks at least one offer (empty: %s)" % str(empty_offers))
	_check(unimplemented.is_empty(),
		"every declared offer resolves to a real resource (declared %d, unimplemented: %s)"
			% [declared_offers, str(unimplemented)])
	# And the flea surface must equal the DATA, not a subset of it: if the
	# enumeration silently dropped a trader, the scaffold check above would have
	# passed while covering less ground than it appears to.
	#
	# Set equality, not a count. The first version of this check compared COUNTS
	# and failed at 9 declared offers against 8 seen, which looked like a dropped
	# trader and was not: two traders stock the same item, and _collect_offer()
	# dedupes because the flea surface is a set of distinct items. Counting
	# declared offers therefore measures duplicates, and a harness that gets
	# "refuse to count duplicates" wrong will send the next person looking for a
	# bug in the enumeration. Sets cannot drift that way.
	var missing: Array[String] = []
	for item_path in declared_paths:
		if not offered.has(item_path):
			missing.append(item_path)
	var extra: Array[String] = []
	for item_path in offered:
		if item_path != FLEA_SUBJECT and not declared_paths.has(item_path):
			extra.append(item_path)
	_check(missing.is_empty() and extra.is_empty(),
		"the flea surface is exactly the declared offer set (declared %d offers = %d distinct, subject %s, missing: %s, extra: %s)"
			% [declared_offers, declared_paths.size(), FLEA_SUBJECT.get_file(), str(missing), str(extra)])

## Every trader resource in the pack, from the FILESYSTEM. The point of not
## writing the three paths out is that a fourth trader is a file rather than a code
## edit, so a harness cannot disagree with the game about who the traders are.
func _trader_resource_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TRADERS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(TRADERS_DIR + f)
	out.sort()
	return out

## Every item a trader offers or barters, read from the trader resources.
func _offered_item_paths() -> Array[String]:
	var out: Array[String] = []
	for tp in _trader_resource_paths():
		var t := load(tp) as Resource
		if t == null:
			continue
		for offer in (t.get("offers") as Array):
			_collect_offer(out, offer as Resource)
	out.append(FLEA_SUBJECT)
	return out

func _collect_offer(out: Array[String], offer: Resource) -> void:
	if offer == null:
		return
	var ip := String(offer.get("item_path"))
	if ip != "" and not out.has(ip):
		out.append(ip)

## A rendered flea line for the item at `path`, through the real composition
## (encoded payload -> FleaListing.line()), so the check exercises the same path
## the report uses rather than calling the reader directly.
func _line_for(path: String) -> String:
	var listing := FleaListing.new()
	listing.item = ItemCodec.encode_item(ItemCodec.item_from_path(path))
	listing.price = 100
	listing.seller = "anon"
	listing.status = FleaListing.Status.ACTIVE
	return listing.line()


## The same word as the catalogue leaves it when NOTHING is translated.
func _flea_key_word() -> String:
	return _FLEA_FRAME_KEY.split(" ")[0]

## The frame word as the CATALOGUE renders it, so the positive half of the
## language check compares against this build's translation rather than a
## hardcoded Portuguese string that would need editing per locale.
func _flea_frame_word() -> String:
	return TranslationServer.translate(_FLEA_FRAME_KEY).split(" ")[0]
