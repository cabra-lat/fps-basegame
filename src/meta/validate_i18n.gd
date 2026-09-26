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
]
## A key that is deliberately absent, used to prove the invariant has teeth.
const MISSING_PROBE := "__i18n_missing_probe__"
## Both spellings count: tr() inside instances, TranslationServer.translate()
## inside the static display helpers, because tr() is instance-bound.
const KEY_PATTERNS := ['tr\\("([^"]*)"\\)', 'TranslationServer\\.translate\\("([^"]*)"\\)']

var _checks := 0
var _passed := 0

func _initialize() -> void:
	_check_catalogue_loaded()
	_check_keys_are_declared()
	_check_every_key_is_translated()
	_check_teeth()
	_check_no_translated_literal_in_source()
	_check_item_registry()
	_check_helpers_are_translation_backed()
	_check_gated_reason_is_localized()
	print("i18n probe: checks=%d passed=%d" % [_checks, _passed])
	print("  passed  %d" % _passed)
	# verify-all.mjs gates on this exact marker, so a missing translation entry
	# fails the build instead of silently rendering English.
	print("RESULT: %s" % ("PASS" if _passed == _checks else "FAIL"))
	quit(0 if _passed == _checks else 1)

## The catalogue must be registered in project.godot, not just present on disk.
func _check_catalogue_loaded() -> void:
	var locales := TranslationServer.get_loaded_locales()

	# === CONSTRUCTED PROBE v5 (throwaway, never merge) ===
	# Which catalogue is actually loaded? For each msgid in the committed PO,
	# report whether TranslationServer resolves it. A catalogue that resolves
	# SOME ids and not others is an OLDER catalogue; one that resolves NONE
	# is a DIFFERENT catalogue entirely.
	var _po2 = load("res://locale/game.po")
	var _all: Array[String] = []
	if _po2 != null:
		for _m in _po2.get_message_list():
			_all.append(String(_m))
	print("PROBE loaded_count=", locales.size(), " po_msg_count=", _all.size())
	for _k in _all:
		var _r := TranslationServer.translate(_k)
		print("PROBE msg |", _k, "| -> ", ("SAME" if _r == _k else "TRANSLATED"))
	# === END CONSTRUCTED PROBE v5 ===
	_check(locales.has("pt_BR"), "pt_BR catalogue is registered in project.godot and loaded")

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
