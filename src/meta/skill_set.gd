# res://src/meta/skill_set.gd
class_name SkillSet
extends RefCounted
## The player's skills. XP is earned by use; levels are pushed into the systems
## that already expose hooks (PlayerSurvival.endurance_level / .strength_level).

const ENDURANCE := "endurance"
const STRENGTH := "strength"
const VITALITY := "vitality"

const KNOWN := [ENDURANCE, STRENGTH, VITALITY]

## XP per unit of real activity. Tuned so a session advances, not a sprint.
const ENDURANCE_XP_PER_STAMINA := 0.1 # 1 xp / 10 stamina drained
const STRENGTH_XP_PER_METER := 0.2 # overweight travel
const VITALITY_XP_PER_HP := 1.0 # damage absorbed

var skills: Dictionary = {} # id -> Skill
## Fractional XP still under 1 from add_activity(), keyed by skill id.
var pending: Dictionary = {}

func _init() -> void:
	for id in KNOWN:
		skills[id] = Skill.new(id)

func get_skill(id: String) -> Skill:
	if not skills.has(id):
		skills[id] = Skill.new(id)
	return skills[id]

func level(id: String) -> int:
	return get_skill(id).level

func xp(id: String) -> int:
	return get_skill(id).xp

## Returns levels gained.
func add_xp(id: String, amount: int) -> int:
	return get_skill(id).add_xp(amount)

func add_activity(id: String, units: float, xp_per_unit: float) -> int:
	var accum := float(pending.get(id, 0.0)) + units * xp_per_unit
	var whole := int(floor(accum))
	pending[id] = accum - float(whole)
	if whole <= 0:
		return 0
	return add_xp(id, whole)

## Feed the levels into an existing survival component (real hook, no shim).
func apply_to_survival(survival) -> void:
	if survival == null:
		return
	survival.endurance_level = level(ENDURANCE)
	survival.strength_level = level(STRENGTH)

func progress_text() -> Array[String]:
	var out: Array[String] = []
	for id in KNOWN:
		var s := get_skill(id)
		out.append("%s %d (%d/%d)" % [id.capitalize(), s.level, s.xp, s.xp_to_next()])
	return out

func to_dict() -> Dictionary:
	var out := {}
	for id in skills:
		out[id] = (skills[id] as Skill).to_dict()
	return out

static func from_dict(d) -> SkillSet:
	var set := SkillSet.new()
	if d is Dictionary:
		for id in d:
			set.skills[id] = Skill.from_dict(id, d[id] as Dictionary)
	return set
