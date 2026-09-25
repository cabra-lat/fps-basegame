extends SceneTree
## Invariant: every translation key the shipped HUD uses has a Portuguese entry,
## and no translated literal leaked back into the source.
##
## The point of this harness is that a missing catalogue entry FAILS instead of
## silently rendering English. Godot's tr() falls back to the key, which is
## invisible in a screenshot, so the check has to be explicit — and _check_teeth
## proves the check itself can fail rather than passing vacuously.
##
## Keys are the English source strings, so "the code is English" and "the
## catalogue is complete" are the same assertion.

const PO_PATH := "res://locale/game.po"
## Files whose translation-key call sites are covered. A new translated string
## in the HUD means adding the file here and the key to DECLARED_KEYS.
const SOURCE_FILES := [
	"res://scenes/raid.gd",
	"res://scenes/raid1_scenario.gd",
	"res://scenes/arena_manager_core.gd",
	"res://scenes/extraction_point.gd",
	"res://scenes/arena_manager.gd",
	"res://src/meta/flea_listing.gd",
]
## Every key those files use, plus the ItemNames registry. This is the
## catalogue contract: a new call site without an entry here fails, and an entry
## here without a call site fails.
const DECLARED_KEYS := [
	"SURVIVED",
	"RUN THROUGH",
	"MIA",
	"KIA",
	"LEFT BEHIND",
	"SCENARIO CLEARED",
	"INSTANT",
	"PAID",
	"FLARE",
	"LEVER",
	"COOP",
	"TIMED",
	"requires %s",
	"a specific item",
	"INTEL SECURED -> %s",
	"RAID FAILED: %s",
	"SECURED",
	"FIND %s",
	"Marked Intel",
	"marked intel not extracted",
	"Failure: intel not collected — kit lost",
	# Market surface. The next two are the purchase feed in arena_manager.gd; the
	# rest are the item registry, asserted by _check_market_surface.
	"Bought: %s",
	"Bought %s",
	"an item",
	"5.56x45mm Ammo",
	"Red Dot Sight",
	"Muzzle Suppressor",
	"M4 Carbine",
	"Army Bandage",
	"CAT Hemostatic Tourniquet",
	"First Aid Kit",
]
## A key that is deliberately absent, used to prove the invariant has teeth.
const MISSING_PROBE := "__i18n_missing_probe__"
## Both spellings count: tr() inside instances, TranslationServer.translate()
## inside the static display helpers, because tr() is instance-bound.
const KEY_PATTERNS := ['tr\\("([^"]*)"\\)', 'TranslationServer\\.translate\\("([^"]*)"\\)']

# Preloaded, not referenced by its global class_name: a `--script` runner must
# not name a global class, or it is compiled before autoloads register.
const TranslationProbe := preload("res://src/meta/translation_probe.gd")

var _checks := 0
var _passed := 0

func _initialize() -> void:
	# Precondition: the locale under test must be SELECTED, not merely
	# registered. See translation_probe.gd for why inheriting the host's active
	# locale made this harness report missing translations for a catalogue that
	# was complete.
	TranslationProbe.select_test_locale()
	_check_catalogue_loaded()
	_check_keys_are_declared()
	_check_every_key_is_translated()
	_check_teeth()
	_check_no_translated_literal_in_source()
	_check_item_registry()
	_check_helpers_are_translation_backed()
	_check_gated_reason_is_localized()
	_check_registry_ids_match_their_resources()
	_check_every_offered_item_is_registered()
	_check_purchase_feed_is_localized()
	_check_market_call_site_uses_the_registry()
	_check_flea_listing_resolves_through_the_registry()
	print("i18n probe: checks=%d passed=%d" % [_checks, _passed])
	print("  passed  %d" % _passed)
	# verify-all.mjs gates on this exact marker, so a missing translation entry
	# fails the build instead of silently rendering English.
	print("RESULT: %s" % ("PASS" if _passed == _checks else "FAIL"))
	quit(0 if _passed == _checks else 1)

## The catalogue must be registered in project.godot, not just present on disk.
func _check_catalogue_loaded() -> void:
	# Both checks below can fail, which the pair they replaced could not: a
	# locale is REGISTERED whether or not it is SELECTED, so the old
	# `get_loaded_locales().has("pt_BR")` was true in the working case and the
	# broken case alike.
	#
	# On a failure of the second check, read the fixture note first: SENTINEL is
	# wired to one specific msgid, so if locale/game.po renames it, this is a
	# fixture break and the fix is to update SENTINEL, not to hunt a missing
	# translation. See src/meta/translation_probe.gd.
	_check(TranslationProbe.locale_is_selected(),
		"the locale under test (%s) is the ACTIVE locale, not inherited from the host" % TranslationProbe.PROBE_LOCALE)
	_check(TranslationProbe.catalogue_answers(),
		"fixture msgid %r resolves from the catalogue - if it was RENAMED in locale/game.po, update SENTINEL in translation_probe.gd rather than hunting a content defect (came back as %r)" % [TranslationProbe.SENTINEL, TranslationProbe.sentinel_result()])

## Call sites and the declared contract must describe the same key set, in both
## directions: a new tr() call without a declared key fails, and a declared key
## nothing uses fails.
func _check_keys_are_declared() -> void:
	var used := _keys_used_in_sources()
	var undeclared := _keys_in(used, true, DECLARED_KEYS)
	_check(undeclared.is_empty(), "every translation-key call site is declared (undeclared: %s)" % ", ".join(undeclared))
	for key in _registry_keys():
		if not used.has(key):
			used.append(key)
	var unused := _keys_in(DECLARED_KEYS, true, used)
	_check(unused.is_empty(), "every declared key is used by a call site or the registry (unused: %s)" % ", ".join(unused))

## THE invariant: a key with no catalogue entry must fail, not fall back.
func _check_every_key_is_translated() -> void:
	var missing: Array[String] = []
	for key in DECLARED_KEYS:
		if TranslationServer.translate(key) == key:
			missing.append(key)
	_check(missing.is_empty(), "no key is untranslated (missing entries: %s)" % ", ".join(missing))

## A check that cannot fail is decoration. This proves an absent entry really
## does come back as the English key, which is what the check above looks for.
func _check_teeth() -> void:
	_check(TranslationServer.translate(MISSING_PROBE) == MISSING_PROBE, "an absent entry falls back to the key, so the untranslated-key check can fail")

## The translated text lives in locale/game.po and nowhere else.
func _check_no_translated_literal_in_source() -> void:
	var sources := ""
	for path in SOURCE_FILES:
		sources += _read(path)
	var leaked: Array[String] = []
	for value in _po_msgstrs():
		if value != "" and sources.contains(value):
			leaked.append(value)
	_check(leaked.is_empty(), "no Portuguese msgstr appears in the source files (leaked: %s)" % ", ".join(leaked))

## The registry is the id -> key mapping. Every entry must resolve to text that
## is neither the raw id nor the untranslated key.
func _check_item_registry() -> void:
	var ids := ItemNames.registered_ids()
	var unresolved: Array[String] = []
	for id in ids:
		var shown := ItemNames.display_name(id)
		if shown == "" or shown == id or shown == ItemNames.key_for(id):
			unresolved.append(id)
	_check(not ids.is_empty() and unresolved.is_empty(), "every registered item id resolves to a translated name (unresolved: %s)" % ", ".join(unresolved))
	var bad: Array[String] = []
	for key in _registry_keys():
		if not DECLARED_KEYS.has(key) or TranslationServer.translate(key) == key:
			bad.append(key)
	_check(bad.is_empty(), "every ItemNames key is declared and translated (missing: %s)" % ", ".join(bad))

## If someone hardcodes a translated string in a display helper, these two stop
## being equal to the catalogue lookup.
func _check_helpers_are_translation_backed() -> void:
	_check(Raid.outcome_display_name(Raid.Outcome.SURVIVED) == TranslationServer.translate("SURVIVED"), "outcome display name is resolved through the catalogue")
	_check(ExtractionPoint.kind_display_name(ExtractionPoint.Kind.TIMED) == TranslationServer.translate("TIMED"), "extraction kind display name is resolved through the catalogue")

## End to end on the line that started this work: the gated destination must
## show the translated item name and never the internal id.
func _check_gated_reason_is_localized() -> void:
	var profile := PlayerProfile.new()
	profile.inventory = {}
	var point := ExtractionPoint.new()
	point.display_name = "Signal Gate"
	point.kind = ExtractionPoint.Kind.TIMED
	point.required_item = "marked_intel"
	point.profile = profile
	root.add_child(point)
	var res: Dictionary = point.can_use()
	point.queue_free()
	var reason := String(res.get("reason", ""))
	var closed := not bool(res.get("ok", false))
	var shows_name := reason.contains(ItemNames.display_name("marked_intel"))
	var leaks_id := reason.contains("marked_intel")
	_check(closed and shows_name and not leaks_id, "the gated extraction reason shows the translated name and never the item id")

## Keys in `subject` that are not in `other`, or (when `missing_only` is false)
## keys in `other` that are not in `subject`.
## The market surface, end to end, because this is the class of defect that a
## screenshot cannot catch: a display path that BYPASSES the registry and looks
## correct until a human reads the string. Buying the marked intel used to render
## "Comprou marked intel", an English noun inside a Portuguese sentence, because
## arena_manager.gd read item.name off the .tres while every other surface
## resolved through ItemNames.
func _check_purchase_feed_is_localized() -> void:
	var intel := load("res://resources/raid1/marked_intel.tres")
	if intel == null:
		_check(false,
			"I18N-MKT purchase_feed_uses_the_registry: marked_intel.tres missing — cannot exercise the purchase feed (F-MKT: a display path that bypasses ItemNames renders the .tres name)")
		return
	var resolved := ItemNames.display_name_for_item(intel)
	var line := TranslationServer.translate("Bought %s") % resolved
	var tres_name := String(intel.name)
	_check(resolved != "" and resolved != tres_name,
		"I18N-MKT registry_wins_over_the_tres_name: tres='%s' resolves to '%s' (F-MKT: a display path that bypasses ItemNames renders the .tres name)" % [tres_name, resolved])
	_check(line.contains(resolved) and not line.contains(tres_name),
		"I18N-MKT purchase_feed_is_fully_portuguese: '%s' (F-MKT: English noun inside a Portuguese sentence)" % line)
	# The raw name must be a FALLBACK, not the answer: a registry entry is what
	# makes the difference, so an unregistered id has to resolve to nothing and
	# leave the choice to the caller rather than silently returning a name.
	_check(ItemNames.display_name("__not_registered__") == "",
		"I18N-MKT unregistered_resolves_to_nothing: callers must fall back deliberately (F-MKT: a silent default would hide every future unregistered item)")
	# The WRAPPER case, which is what a purchase actually returns. Added because
	# driving the real _market_buy showed the leak surviving the fix: the buy
	# hands back an InventoryItem whose resource_path is EMPTY, so resolving by
	# the wrapper's own path returned "" and the caller fell back to the .tres
	# name. Asserting the .tres case alone would have stayed green through it.
	var wrapped := ItemCodec.item_from_path("res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres")
	var wrapped_name := ItemNames.display_name_for_item(wrapped)
	_check(wrapped_name != "" and wrapped_name != "5_56_45mm_SS109_VPAM_PM7",
		"I18N-MKT wrapper_resolves_too: the InventoryItem a purchase returns resolves to '%s' (F-MKT: InventoryItem.resource_path is empty; a wrapper must resolve through ItemCodec.content_path)" % wrapped_name)

## The player-to-player surface has the same defect the market had: the listing
## rendered the escrow payload's own "name", so a listing of the 5.56 ammo read
## `556_SS109_VPAM_PM7` next to a Portuguese row. The escrow dict IS ItemCodec
## encoding and carries "path", so the same registry entry serves both surfaces —
## which is the point of the registry rather than a per-surface string table.
##
## Flea listings cannot be enumerated (any item a player owns is listable), so the
## check is the enforceable half: for every item the game's own content can hand a
## player, the listing path resolves to the same name the market renders.
func _check_flea_listing_resolves_through_the_registry() -> void:
	var paths := _trader_item_paths()
	var leaked: Array[String] = []
	for path in paths:
		var listing := FleaListing.new()
		listing.item = ItemCodec.encode_item(ItemCodec.item_from_path(path))
		var rendered: String = listing.item_name()
		var expected := ItemNames.display_name_for_path(path)
		var payload_name := String(listing.item.get("name", "?"))
		if rendered != expected or rendered == payload_name or rendered.contains(payload_name):
			leaked.append("%s: listing='%s' expected='%s' payload='%s'" % [path, rendered, expected, payload_name])
	_check(not paths.is_empty() and leaked.is_empty(),
		"I18N-FLEA every_listable_item_renders_the_registry_name: %d leaked (F-FLEA: the listing bypasses the registry and renders the escrow payload's own name)" % leaked.size())
	# Same precedence rule as the market: the registry lookup must come first, or a
	# fallback that runs first is the defect again.
	var body := _function_body("res://src/meta/flea_listing.gd", "item_name")
	var registry_at := body.find("ItemNames.display_name_for_path")
	var raw_at := body.find("item.get(\"name\"")
	_check(registry_at >= 0 and raw_at > registry_at,
		"I18N-FLEA flea_call_site_uses_the_registry: registry@%d raw@%d (F-FLEA: precedence is the whole fix)" % [registry_at, raw_at])

## says nothing about whether the real call site uses it. Measured: reverting
## _market_buy to `item.name` left that check GREEN, because the harness never
## ran the function. Driving _market_buy needs a live MetaService, a profile and
## an offer index, and a harness that constructs a market and asserts on a
## rendered feed line is a second subsystem's worth of fixture. So this asserts
## the call site directly instead, in the only way that can fail today: the
## registry lookup must be present, must come BEFORE the raw .tres name, and the
## raw name must sit behind an emptiness check so it is a fallback rather than
## the answer. Re-run the sabotage (restore `var nm: String = item.name ...` in
## _market_buy) and this fails.
func _check_market_call_site_uses_the_registry() -> void:
	var body := _function_body("res://scenes/arena_manager.gd", "_market_buy")
	if body == "":
		_check(false, "I18N-MKT market_call_site_uses_the_registry: _market_buy not found in arena_manager.gd (F-MKT: a renamed or moved call site would go unchecked)")
		return
	var registry_at := body.find("ItemNames.display_name_for_item")
	var raw_at := body.find(".name")
	var guard_at := body.find("== \"\"")
	_check(registry_at >= 0,
		"I18N-MKT market_call_site_uses_the_registry: _market_buy does not consult ItemNames (F-MKT: the purchase line bypasses the registry and renders the .tres name)")
	_check(registry_at >= 0 and (raw_at < 0 or registry_at < raw_at) and guard_at > registry_at,
		"I18N-MKT market_call_site_uses_the_registry: the raw .tres name is read before the registry, or is not behind an emptiness check (registry@%d raw@%d guard@%d) — precedence is the whole fix, a fallback that runs first is the defect again" % [registry_at, raw_at, guard_at])

## The source text of one function, so a call site can be asserted without
## building the object it belongs to. Empty when the function is not found.
func _function_body(path: String, func_name: String) -> String:
	var text := _read(path)
	var start := text.find("func %s(" % func_name)
	if start < 0:
		return ""
	var next := text.find("\nfunc ", start + 1)
	return text.substr(start, next - start) if next > 0 else text.substr(start)
## resource must be loadable. This is what keeps `id_for_path` honest instead of
## a convention nobody checks: add an id whose file is named differently and the
## market silently falls back to the .tres name.
func _check_registry_ids_match_their_resources() -> void:
	var mismatched: Array[String] = []
	for id in ItemNames.registered_ids():
		var found := ""
		for path in _trader_item_paths():
			if path.get_file().get_basename() == id:
				found = path
				break
		if found == "" and FileAccess.file_exists("res://resources/raid1/%s.tres" % id):
			found = "res://resources/raid1/%s.tres" % id
		if found == "" or ItemNames.id_for_path(found) != id or load(found) == null:
			mismatched.append(id)
	_check(mismatched.is_empty(),
		"I18N-MKT registered_ids_resolve_from_their_resource: mismatched: %s (an id whose file is named differently would silently fall back to the .tres name)" % ", ".join(mismatched))

## The strong half: nothing a trader can sell or barter may be missing from the
## registry, because that is exactly how "Comprou marked intel" happened. Adding
## an offer without registering its item fails here rather than shipping English.
func _check_every_offered_item_is_registered() -> void:
	var paths := _trader_item_paths()
	var unregistered: Array[String] = []
	for path in paths:
		if ItemNames.display_name_for_path(path) == "":
			unregistered.append(path)
	_check(not paths.is_empty() and unregistered.is_empty(),
		"I18N-MKT every_offered_item_is_registered: unregistered: %s (adding an offer without registering its item is how 'Comprou marked intel' shipped)" % ", ".join(unregistered))

## Offer and barter item paths, read from the trader resources rather than
## hardcoded here, so a new offer cannot slip past the check by omission. Split
## into helpers because the nesting limit is 5 and the inline version hit 6.
func _trader_item_paths() -> Array[String]:
	var out: Array[String] = []
	for trader_path in ["res://resources/meta/traders/field_surgeon.tres",
			"res://resources/meta/traders/quartermaster.tres",
			"res://resources/meta/traders/gunsmith.tres"]:
		var trader := load(trader_path) as Resource
		if trader == null:
			continue
		# A typed local, no `or []` idiom: an empty Dictionary is FALSY in GDScript,
		# so `get("barter_required") or {}` changes type with the data and `x or []`
		# returns the bool when x is a non-empty array.
		var offers: Array = trader.get("offers")
		for offer in offers:
			_collect_offer_paths(out, offer as Resource)
	return out


func _collect_offer_paths(out: Array[String], offer: Resource) -> void:
	if offer == null:
		return
	_append_path(out, String(offer.get("item_path")))
	var barter: Variant = offer.get("barter_required")
	if barter is Dictionary:
		for path in barter:
			_append_path(out, String(path))


func _append_path(out: Array[String], path: String) -> void:
	if path != "" and not out.has(path):
		out.append(path)

func _keys_in(subject: Array, missing_only: bool, other: Array) -> Array[String]:
	var out: Array[String] = []
	if missing_only:
		for key in subject:
			if not other.has(key):
				out.append(key)
		return out
	for key in other:
		if not subject.has(key):
			out.append(key)
	return out

func _keys_used_in_sources() -> Array[String]:
	var texts: Array[String] = []
	for path in SOURCE_FILES:
		texts.append(_read(path))
	var found: Array[String] = []
	for text in texts:
		for key in _keys_in_text(text):
			if not found.has(key):
				found.append(key)
	return found

## Every translation key a single file passes to tr() / translate().
func _keys_in_text(text: String) -> Array[String]:
	var found: Array[String] = []
	for pattern in KEY_PATTERNS:
		for key in _match_all(text, pattern):
			found.append(key)
	return found

func _registry_keys() -> Array[String]:
	var keys: Array[String] = []
	for id in ItemNames.registered_ids():
		var key := ItemNames.key_for(id)
		if not keys.has(key):
			keys.append(key)
	return keys

## Every non-header msgstr in the catalogue.
func _po_msgstrs() -> Array[String]:
	var out: Array[String] = []
	var in_header := true
	for raw in _read(PO_PATH).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid "):
			in_header = line == 'msgid ""'
		elif line.begins_with("msgstr ") and not in_header:
			out.append(_unquote(line.trim_prefix("msgstr").strip_edges()))
	return out

func _match_all(text: String, pattern: String) -> Array[String]:
	var out: Array[String] = []
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return out
	for m in regex.search_all(text):
		out.append(m.get_string(1))
	return out

func _unquote(value: String) -> String:
	if value.length() < 2:
		return value
	return value.substr(1, value.length() - 2)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		_passed += 1
	else:
		push_error("FAIL: " + label)
