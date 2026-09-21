# res://src/meta/skill.gd
class_name Skill
extends RefCounted
## One use-based skill: XP pooled toward the next level on an exponential curve.
## Levels are exposed as plain ints so existing systems (survival's
## endurance_level / strength_level) can consume them.

const DEFAULT_MAX_LEVEL := 50
const DEFAULT_BASE_COST := 100.0
const DEFAULT_CURVE := 1.5

var id: String = ""
var level: int = 0
var xp: int = 0
var max_level: int = DEFAULT_MAX_LEVEL
var base_cost: float = DEFAULT_BASE_COST
var curve: float = DEFAULT_CURVE

func _init(p_id: String = "") -> void:
	id = p_id

func xp_to_next() -> int:
	if level >= max_level:
		return 0
	return int(round(base_cost * pow(curve, level)))

func ratio() -> float:
	var need := xp_to_next()
	return 1.0 if need <= 0 else clampf(float(xp) / float(need), 0.0, 1.0)

## Adds XP and returns how many levels were gained by this call.
func add_xp(amount: int) -> int:
	if amount <= 0 or level >= max_level:
		return 0
	xp += amount
	var gained := 0
	var need := xp_to_next()
	while level < max_level and need > 0 and xp >= need:
		xp -= need
		level += 1
		gained += 1
		need = xp_to_next()
	if level >= max_level:
		xp = 0
	return gained

func to_dict() -> Dictionary:
	return {"level": level, "xp": xp}

static func from_dict(p_id: String, d: Dictionary) -> Skill:
	var s := Skill.new(p_id)
	s.level = clampi(int(d.get("level", 0)), 0, s.max_level)
	s.xp = maxi(int(d.get("xp", 0)), 0)
	return s
