# res://src/meta/validate_meta_progression.gd
#
# Headless gate for skills + quests. Drives the REAL raid event bus (not stubs)
# and proves:
#   [A] kill objective advances per player kill, ignores non-player kills,
#       completes and pays currency/EXP/item/skill XP
#   [B] RUN_THROUGH does NOT complete extraction objectives; a real SURVIVED does
#       (medical loot objective + EXTRACT_AT "Ponte" + SURVIVE_EXTRACT)
#   [C] skills level by USE (stamina drained / overweight distance / damage) and
#       write into PlayerSurvival.endurance_level / .strength_level
#   [D] rewards + quest state + skill levels survive close/reopen
#
# Run:
#   godot --headless --path . --script res://src/meta/validate_meta_progression.gd
# Exit code: 0 = all checks passed, 1 = at least one failure.
extends SceneTree

const TEST_DIR := "user://meta_prog_test"
const SAVE := "user://meta_prog_test/profile.save"
const QUESTS_DIR := "res://resources/meta/quests"
const BANDAGE := "res://resources/medical/army_bandage.tres"

var v: ValidateUtil
var profile: MetaProfile
var prog: Progression
var raid: Raid

func _check(cond: bool, msg: String) -> void:
	v.check(cond, msg)

func _initialize() -> void:
	v = ValidateUtil.new("validate_meta_progression")
	v.begin()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_cleanup()

	profile = MetaProfile.new()
	prog = Progression.new()
	prog.setup(profile, func() -> void: ProfileStore.save(profile, SAVE))
	var loaded := prog.load_quests(QUESTS_DIR)
	_check(loaded == 3, "3 example quests loaded (got %d)" % loaded)
	_check(profile.quests.status_of("hunter_3") == QuestLog.Status.ACTIVE, "hunter_3 starts ACTIVE")
	_check(profile.quests.status_of("field_medic") == QuestLog.Status.ACTIVE, "field_medic starts ACTIVE")
	_check(profile.quests.status_of("survive_raid") == QuestLog.Status.ACTIVE, "survive_raid starts ACTIVE")

	raid = Raid.new()
	raid.duration = 2100.0
	prog.bind_raid(raid)

	_scenario_kill()
	_scenario_extraction_rules()
	_scenario_skills()
	_scenario_persistence()

	quit(v.finish())

# ─── SCENARIOS ──────────────────────────────────────

func _scenario_kill() -> void:
	print("\n[A] kill objective advances on player kills only")
	raid.begin()
	raid.register_kill(5, 90, "AK 47") # bot kill: must be ignored
	_check(int(profile.quests.progress_of("hunter_3")[0]) == 0, "non-player kill ignored")
	raid.register_kill(0, 91, "M4 Carbine")
	raid.register_kill(0, 92, "M4 Carbine")
	_check(int(profile.quests.progress_of("hunter_3")[0]) == 2, "kill progress 2/3 (got %d)" % int(profile.quests.progress_of("hunter_3")[0]))
	var currency_before := profile.currency
	var exp_before := profile.total_exp
	var endurance_before := profile.skills.xp("endurance")
	raid.register_kill(0, 93, "M4 Carbine")
	_check(profile.quests.status_of("hunter_3") == QuestLog.Status.CLAIMED, "hunter_3 COMPLETE + CLAIMED")
	_check(profile.currency == currency_before + 8000, "reward currency +8000 (got +%d)" % (profile.currency - currency_before))
	_check(profile.total_exp == exp_before + 300, "reward EXP +300 (got +%d)" % (profile.total_exp - exp_before))
	_check(profile.stash.count_items() == 1, "reward item in stash")
	_check(profile.skills.xp("endurance") == endurance_before + 30, "reward skill xp +30 endurance")

func _scenario_extraction_rules() -> void:
	print("\n[B] RUN_THROUGH does not count; SURVIVED completes")
	var medical := load(BANDAGE) as MedicalItem
	raid.begin()
	raid.register_loot(medical)
	raid.register_loot(medical)
	_check(int(profile.quests.progress_of("field_medic")[0]) == 2, "medical loot 2/2 (got %d)" % int(profile.quests.progress_of("field_medic")[0]))

	raid.extract(_point("Ponte")) # elapsed 0, exp 0 -> RUN_THROUGH
	_check(profile.quests.status_of("field_medic") != QuestLog.Status.CLAIMED, "RUN_THROUGH does NOT complete field_medic")
	_check(profile.quests.status_of("survive_raid") != QuestLog.Status.CLAIMED, "RUN_THROUGH does NOT complete survive_raid")
	_check(int(profile.quests.progress_of("field_medic")[2]) == 0, "SURVIVE_EXTRACT still 0 after RUN_THROUGH")

	var currency_before := profile.currency
	raid.begin()
	raid.add_exp(250) # > RUN_THROUGH_EXP -> SURVIVED
	raid.extract(_point("Ponte"))
	_check(profile.quests.status_of("field_medic") == QuestLog.Status.CLAIMED, "SURVIVED completes field_medic")
	_check(profile.quests.status_of("survive_raid") == QuestLog.Status.CLAIMED, "SURVIVED completes survive_raid")
	_check(profile.currency == currency_before + 12000 + 6000, "both rewards paid (+%d)" % (profile.currency - currency_before))
	_check(profile.stash.count_items() == 2, "second reward item in stash (got %d)" % profile.stash.count_items())

func _scenario_skills() -> void:
	print("\n[C] skills level by use; survival hooks fed")
	prog.on_stamina_drained(1200.0) # 120 xp -> endurance level 1
	_check(profile.skills.level("endurance") >= 1, "endurance levelled by stamina drained (lvl %d)" % profile.skills.level("endurance"))
	prog.on_distance_moved(600.0) # 120 xp -> strength level 1
	_check(profile.skills.level("strength") >= 1, "strength levelled by overweight distance (lvl %d)" % profile.skills.level("strength"))
	prog.on_damage_taken(150.0) # 150 xp -> vitality level 1
	_check(profile.skills.level("vitality") >= 1, "vitality levelled by damage taken (lvl %d)" % profile.skills.level("vitality"))

	# Fractional activity must accumulate (not floor to zero every call).
	var xp_before := profile.skills.xp("strength")
	for i in range(20):
		prog.on_distance_moved(1.0) # 0.2 xp each -> 4 total
	_check(profile.skills.xp("strength") == xp_before + 4, "fractional xp accumulated (+%d)" % (profile.skills.xp("strength") - xp_before))

	var survival := PlayerSurvival.new()
	profile.skills.apply_to_survival(survival)
	_check(survival.endurance_level == profile.skills.level("endurance"), "PlayerSurvival.endurance_level fed")
	_check(survival.strength_level == profile.skills.level("strength"), "PlayerSurvival.strength_level fed")

func _scenario_persistence() -> void:
	print("\n[D] rewards + quest state + skills survive close/reopen")
	prog.flush()
	var reloaded := ProfileStore.load_profile(SAVE)
	_check(reloaded != null, "profile reloads")
	_check(reloaded.currency == profile.currency, "currency persisted (%d)" % reloaded.currency)
	_check(reloaded.total_exp == profile.total_exp, "EXP persisted (%d)" % reloaded.total_exp)
	_check(reloaded.skills.level("endurance") == profile.skills.level("endurance"), "endurance level persisted")
	_check(reloaded.skills.xp("strength") == profile.skills.xp("strength"), "strength xp persisted")
	_check(reloaded.stash.count_items() == 2, "reward items persisted (%d)" % reloaded.stash.count_items())

	var prog2 := Progression.new()
	prog2.setup(reloaded)
	prog2.load_quests(QUESTS_DIR)
	_check(reloaded.quests.status_of("hunter_3") == QuestLog.Status.CLAIMED, "hunter_3 CLAIMED persisted")
	_check(reloaded.quests.status_of("field_medic") == QuestLog.Status.CLAIMED, "field_medic CLAIMED persisted")
	_check(reloaded.quests.status_of("survive_raid") == QuestLog.Status.CLAIMED, "survive_raid CLAIMED persisted")

# ─── HELPERS ────────────────────────────────────────

func _point(pname: String) -> Node:
	var p := Node.new()
	p.set_meta("display_name", pname)
	return p

func _cleanup() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
