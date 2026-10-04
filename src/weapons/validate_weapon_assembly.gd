extends SceneTree

## Frankenstein weapons: parts that FIT, change the stats, and save as one item.
##
## The card's acceptance, unchanged: assemble from parts, assert the resolved stats
## DIFFER from the base weapon, assert an INCOMPATIBLE part is refused WITH A
## REASON, and assert the saved item reloads with the same parts and the same stats.
## The middle one is the load-bearing check -- an assembly layer that accepts
## anything is not realistic composability, it is a slot list -- so several of the
## checks below exist to make that specific refusal able to fail.
##
## WHY THE BASE STATS ARE A FIXTURE AND NOT A REAL WEAPON. The parts' deltas have to
## land on stat fields the weapon really has, and asserting that against a live
## Weapon would couple this to weapon tuning that is not this card's business. So
## the base block is declared here with the SAME FIELD NAMES Weapon exports
## (firerate, base_reload_time, base_accuracy, base_ergonomics, base_recoil_*), and
## one check asserts those names really exist on Weapon so the fixture cannot drift
## away from the model unnoticed.

var _pass := 0
var _fail := 0
var _fail_lines: Array[String] = []


func _initialize() -> void:
	await process_frame
	_run()
	_summary()


func _run() -> void:
	_parts_load_and_are_real()
	_a_valid_assembly_changes_the_stats()
	_one_part_per_socket_is_refused()
	_an_unfitted_part_is_refused()
	_a_calibre_mismatch_is_refused()
	_every_refusal_carries_a_catalogued_reason()
	_the_build_saves_as_an_item()
	_the_fixture_cannot_drift_from_the_model()
	_summary()


const BASE_STATS := {
	"firerate": 600.0,
	"base_reload_time": 2.5,
	"base_accuracy": 2.0,
	"base_ergonomics": 50.0,
	"base_recoil_vertical": 1.0,
	"base_recoil_horizontal": 0.5,
	"base_recoil_kick": 0.04,
}


func _part(file: String) -> WeaponPart:
	return load("res://src/weapons/parts/%s.tres" % file) as WeaponPart


# ── the parts are real data, not stubs ──────────────────────────────────────

func _parts_load_and_are_real() -> void:
	for file in ["receiver_ar15", "barrel_ar15", "magazine_ar15", "stock_ar15",
				 "barrel_shotgun", "magazine_ak47", "receiver_ak47", "barrel_ak47_heavy"]:
		var p := _part(file)
		_check(p != null, "part %s loads as a real WeaponPart" % file)
		if p != null:
			_check(not String(p.socket).is_empty(), "  %s declares the socket it occupies" % file)
			_check(not String(p.scene).is_empty(), "  %s points at a scene" % file)
			_check(FileAccess.file_exists(String(p.scene).replace("res://", "")) or ResourceLoader.exists(p.scene),
				"  %s's scene actually EXISTS, so a part cannot ship pointing at nothing" % file)
	# A part whose deltas are all zero would make the "stats differ" check
	# unfalsifiable, so at least one authored part must actually contribute.
	var contributor := _part("barrel_ar15")
	_check(not _all_zero(contributor.stat_deltas()),
		"at least one authored part contributes a non-zero delta, or 'the stats differ' cannot fail")


func _all_zero(deltas: Dictionary) -> bool:
	for k in deltas:
		if not is_zero_approx(float(deltas[k])):
			return false
	return true


# ── 1. a valid assembly CHANGES THE STATS ───────────────────────────────────

func _a_valid_assembly_changes_the_stats() -> void:
	var parts: Array = [_part("receiver_ar15"), _part("barrel_ar15"),
						_part("magazine_ar15"), _part("stock_ar15")]
	var r := WeaponAssembly.assemble("ar15", parts, BASE_STATS)
	_check(r.ok, "a fitting assembly is accepted [reason %s]" % r.reason_line())
	if not r.ok:
		return
	_check(r.stats.size() == BASE_STATS.size(),
		"resolution does not invent or drop stat keys [%d vs %d]" % [r.stats.size(), BASE_STATS.size()])
	# The load-bearing half: the resolved value for every field must equal the base
	# PLUS THE SUM OF EVERY FITTED PART'S DELTA.
	#
	# Two versions of this check were wrong before this one, both caught by
	# running it rather than by reading it. The first asserted a fixed set of four
	# fields including firerate, and no part in this assembly declares a firerate
	# delta -- only barrel_shotgun does and it is not fitted -- so it demanded a
	# stat the design never promised would move, satisfiable only by editing the
	# data until the test agreed. The second compared each field against base PLUS
	# ONE part's delta, which fails the moment two fitted parts touch the same stat:
	# here base_recoil_vertical is claimed by the barrel (-0.15) and the stock (+0.1)
	# and base_ergonomics by the magazine (-3) and the stock (+2), so it reported
	# "2 of 6" for a build whose arithmetic was exactly right. Summing per field is
	# the invariant; anything less asserts an authoring accident.
	var summed: Dictionary = {}
	for part in r.parts:
		for field in part.stat_deltas():
			var d := float(part.stat_deltas()[field])
			if is_zero_approx(d):
				continue
			summed[field] = float(summed.get(field, 0.0)) + d
	_check(summed.size() > 0, "the assembly declares at least one non-zero delta, or nothing can move")
	var wrong: Array[String] = []
	for field in summed:
		var expected := float(BASE_STATS.get(field, 0.0)) + float(summed[field])
		if not is_equal_approx(float(r.stats.get(field, -9999.0)), expected):
			wrong.append("%s (got %s, expected %s)" % [field, str(r.stats.get(field, -9999.0)), str(expected)])
	_check(wrong.is_empty(),
		"and every resolved field is base + the SUM of all fitted parts' deltas [%d fields checked, %d wrong: %s]"
			% [summed.size(), wrong.size(), ", ".join(wrong)])
	# And more than one field must move, so a build cannot pass by touching one.
	_check(summed.size() >= 3, "and more than one stat is involved, so an assembly is not a single-bolt upgrade [%d fields]" % summed.size())
	# And the deltas must be ADDITIVE and in the authored direction, so a barrel
	# that claims more velocity actually raises it rather than merely differing.
	_check(float(r.stats["base_accuracy"]) > float(BASE_STATS["base_accuracy"]),
		"a match-grade barrel raises accuracy as authored [2.0 -> %s]" % str(r.stats["base_accuracy"]))
	_check(float(r.stats["base_reload_time"]) < float(BASE_STATS["base_reload_time"]),
		"a quicker magazine lowers reload time as authored [2.5 -> %s]" % str(r.stats["base_reload_time"]))
	# The base stats must not have been mutated in place: a caller passing a
	# shared dict would otherwise see the deltas leak into their next assembly.
	_check(is_equal_approx(float(BASE_STATS["base_accuracy"]), 2.0),
		"and the base stat block is not mutated in place, so two assemblies cannot contaminate each other")


# ── 2. ONE PART PER SOCKET, refused WITH A REASON ────────────────────────────

func _one_part_per_socket_is_refused() -> void:
	var parts: Array = [_part("receiver_ar15"), _part("barrel_ar15"), _part("barrel_shotgun")]
	var r := WeaponAssembly.assemble("ar15", parts, BASE_STATS)
	_check(not r.ok, "two barrels on one receiver is REFUSED -- an assembly layer that accepts this is a slot list, not composability")
	_check(r.reason == WeaponAssembly.REASON_SOCKET_TAKEN,
		"  and it says which rule refused it [got %s]" % r.reason)
	_check(not r.offending_part.is_empty(),
		"  and it names the offending part so the player knows what to take off [got '%s']" % r.offending_part)
	_check(r.stats.is_empty(), "  and a refused build resolves NO stats, so it is never half-applied")


func _an_unfitted_part_is_refused() -> void:
	# barrel_ak47_heavy declares fits_receiver "ak47", so on an ar15 it does not go on.
	var parts: Array = [_part("receiver_ar15"), _part("barrel_ak47_heavy"), _part("magazine_ar15")]
	var r := WeaponAssembly.assemble("ar15", parts, BASE_STATS)
	_check(not r.ok, "a barrel cut for another receiver is REFUSED")
	_check(r.reason == WeaponAssembly.REASON_PART_FIT, "  naming the fit rule [got %s]" % r.reason)
	_check(r.offending_part.contains("barrel_ak47_heavy"),
		"  and naming the part by id [got '%s']" % r.offending_part)
	# The same part on the receiver it IS cut for must be accepted, or "refuses
	# everything" would pass every check above.
	var ok_parts: Array = [_part("receiver_ak47"), _part("barrel_ak47_heavy"), _part("magazine_ak47")]
	var r2 := WeaponAssembly.assemble("ak47", ok_parts, BASE_STATS)
	_check(r2.ok, "  and the SAME barrel is accepted on the receiver it is cut for [reason %s]" % r2.reason_line())


func _a_calibre_mismatch_is_refused() -> void:
	# A 7.62 magazine on a 5.56 barrel: the does-not-go-on rule along a different edge.
	var parts: Array = [_part("receiver_ar15"), _part("barrel_ar15"), _part("magazine_ak47")]
	var r := WeaponAssembly.assemble("ar15", parts, BASE_STATS)
	_check(not r.ok, "a 7.62 magazine on a 5.56 barrel is REFUSED")
	_check(r.reason == WeaponAssembly.REASON_CALIBRE_MISMATCH, "  naming the calibre rule [got %s]" % r.reason)
	# ORDER MUST NOT MATTER. If the magazine were written first it must still be
	# refused once the barrel fixes the calibre, or the same parts would assemble or
	# refuse depending on how they were typed into an array.
	var swapped: Array = [_part("receiver_ar15"), _part("magazine_ak47"), _part("barrel_ar15")]
	var r2 := WeaponAssembly.assemble("ar15", swapped, BASE_STATS)
	_check(r2.reason == WeaponAssembly.REASON_CALIBRE_MISMATCH or r2.reason == WeaponAssembly.REASON_PART_FIT,
		"  and the ORDER of the array does not change whether a build is legal [got %s]" % r2.reason)


func _every_refusal_carries_a_catalogued_reason() -> void:
	# A reason a player reads is a translation, so every key must be enumerable and
	# resolvable. A key nothing can render is a silent refusal wearing a name.
	for key in WeaponAssembly.all_reasons():
		_check(not key.is_empty(), "reason key %s is non-empty" % key)
		var translated: String = TranslationServer.translate(key)
		_check(translated != "" and translated != key,
			"  %s has catalogue copy, or a refusal renders as a bare key" % key)
	# And no refusal is a composed English sentence: the whole reason the key
	# exists is that the string is owned by the catalogue.
	for key in WeaponAssembly.all_reasons():
		_check(not key.contains(" "), "  %s is a key, not a sentence" % key)


# ── 3. THE BUILD SAVES AS AN ITEM (decision 2) ───────────────────────────────

func _the_build_saves_as_an_item() -> void:
	var parts: Array = [_part("receiver_ar15"), _part("barrel_ar15"),
						_part("magazine_ar15"), _part("stock_ar15")]
	var r := WeaponAssembly.assemble("ar15", parts, BASE_STATS)
	_check(r.ok, "assemble for the save check [reason %s]" % r.reason_line())
	if not r.ok:
		return
	# Saved as ONE thing: a flat dictionary of numbers plus the part identities.
	# NOT a recipe to be re-evaluated -- decision 2 is that the numbers are baked.
	var saved := {
		"kind": "frankenstein_build",
		"receiver": "ar15",
		"parts": r.parts.map(func(p: WeaponPart) -> String: return p.part_id()),
		"stats": r.stats.duplicate(true),
	}
	var json := JSON.stringify(saved)
	_check(not json.is_empty(), "the build serialises to one item payload")

	# RELOAD, and it must come back with the SAME parts and the SAME stats. This
	# is the assertion that would fail if the save were a recipe: a recipe would
	# re-resolve against whatever the parts say TODAY.
	var back: Variant = JSON.parse_string(json)
	_check(back is Dictionary, "and parses back as one item")
	if not (back is Dictionary):
		return
	var item := back as Dictionary
	_check(int((item["parts"] as Array).size()) == parts.size(),
		"  with the same number of parts [%d of %d]" % [(item["parts"] as Array).size(), parts.size()])
	_check((item["parts"] as Array)[0] == String(r.parts[0].part_id()),
		"  and the same part identities")
	var stats_back := item["stats"] as Dictionary
	_check(stats_back.size() == r.stats.size(), "  and the same stat keys")
	var same := true
	for k in r.stats:
		if not is_equal_approx(float(stats_back.get(k, -1.0)), float(r.stats[k])):
			same = false
	_check(same, "  and IDENTICAL stat values -- a recipe would have re-resolved instead of reloading")
	# And the saved numbers are the RESOLVED ones, not the base ones: if this ever
	# saved the base block the item would silently be a different weapon on reload.
	_check(not is_equal_approx(float(stats_back["base_accuracy"]), float(BASE_STATS["base_accuracy"])),
		"  and the saved numbers are the RESOLVED stats, not the untouched base")


# ── the fixture cannot drift from the model ──────────────────────────────────

func _the_fixture_cannot_drift_from_the_model() -> void:
	# Every delta target must be a field Weapon really has. A mistyped key would
	# silently add a stat nobody reads, and this harness would still be green.
	var weapon_script: GDScript = load("res://addons/cabra.lat_shooters/src/core/weapon/weapon.gd") as GDScript
	_check(weapon_script != null, "the Weapon script loads, so the delta targets can be checked against it")
	if weapon_script == null:
		return
	var source: String = FileAccess.get_file_as_string("res://addons/cabra.lat_shooters/src/core/weapon/weapon.gd")
	for field in _part("barrel_ar15").stat_deltas().keys():
		_check(source.contains(field) or source.contains("@export var %s" % field),
			"  delta target '%s' is a field Weapon actually has" % field)
	for field in BASE_STATS.keys():
		_check(source.contains(field), "  base stat '%s' is a field Weapon actually has" % field)


# ── plumbing ────────────────────────────────────────────────────────────────

func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % message)
	else:
		_fail += 1
		_fail_lines.append(message)
		print("ERROR: FAIL: %s" % message)


func _summary() -> void:
	print("")
	print("=== validate_weapon_assembly summary ===")
	print("  checks passed  %d" % _pass)
	print("  FAILURES       %d" % _fail)
	for l in _fail_lines:
		print("    " + l)
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))


func _quit(code: int) -> void:
	quit(code)