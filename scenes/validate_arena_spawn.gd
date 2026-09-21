# res://scenes/validate_arena_spawn.gd
#
# Headless gate for the arena's SPAWN and ACTIVE-SLOT contracts. Two user-visible
# bugs shipped here:
#
#   [1] two participants could be spawned on the SAME point (`game_mode._pick_spawn`
#       used `randi()`), and two CharacterBody3D created on one point in one frame
#       are depenetrated UPWARDS and LAUNCHED — spotter telemetry: bots born at
#       ~17 m, up to ~135-143 m, then falling back, in ~1/3 of the boots.
#       npc-body proved the mechanism (2/2 bots at y~100 after 120 frames).
#   [2] the controller's `current_weapon` went stale on slot switch/drop, so the
#       gunsmith/HUD showed the weapon the player had thrown on the ground.
#
# Checks:
#   - `get_spawn()` never repeats a point until its slice wraps, per team
#     (FFA: one cursor over all points; TDM: teams walk disjoint slices)
#   - a fresh `setup()` reproduces the same sequence: the spawn is DETERMINISTIC
#     (no `randi()`), which is what makes a spawn bug reproducible at all
#   - the arena spawns BOT_COUNT bots on distinct points
#   - after ~130 physics frames nobody is in the air: max y stays at floor level
#     and every bot reports is_on_floor()
#   - `_activate_slot(slot)` -> `player.current_weapon` is that slot's weapon
#   - `_drop_active()`      -> `player.current_weapon` is null and `active_slot` is ""
#
# Run:
#   tools/godot-lock.sh --headless --path . --script res://scenes/validate_arena_spawn.gd
# Exit code: 0 = every check passed, 1 = at least one failure.
extends SceneTree

const ARENA := "res://scenes/arena_blockout.tscn"
const BOT_COUNT := 3
## Bots are 0.7 m apart or more; two bodies inside that radius in one frame are the
## overlap that launches them.
const MIN_SEPARATION := 0.7
## Long enough for a launched body to be well above the floor (npc-body measured
## y~100 at 120 frames); a clean spawn stays at ~0 m.
const FLOOR_FRAMES := 130
## A spawn that happens while the raid is RUNNING (not from _ready) is the case
## that used to stack the bots on the arena origin, inside the floor.
const MID_RUN_FRAME := 30
const FLOOR_Y := 3.0

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 10), Vector3(10, 0, 10),
]

var v: ValidateUtil
var _arena
var _frame := 0
var _done := false
var _mid_run_names: Array[String] = []


func _initialize() -> void:
	v = ValidateUtil.new("validate_arena_spawn")
	v.begin()
	_check_cursor_ffa()
	_check_cursor_tdm()
	# The arena is loaded at RUNTIME (PackedScene, not a global class name): a
	# harness must not pull a script chain that needs autoloads at compile time.
	_arena = (load(ARENA) as PackedScene).instantiate()
	get_root().add_child(_arena)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame == 3:
		_check_bot_spawns()
		_check_current_weapon()
		return false
	if _frame == MID_RUN_FRAME:
		_spawn_mid_raid()
		return false
	if _frame >= FLOOR_FRAMES:
		_done = true
		_check_nobody_launched()
		_check_mid_raid_bots_landed()
		quit(v.finish())
		return true
	return false


# ─── [1] THE SPAWN CURSOR (no scene) ────────────────

func _check_cursor_ffa() -> void:
	v.section("[FFA: get_spawn() cursor]")
	var mode := FFAMode.new()
	mode.setup(SPAWN_POINTS)
	var seen: Array[Vector3] = []
	for i in range(SPAWN_POINTS.size()):
		seen.append(mode.get_spawn(0))
	v.check(_all_distinct(seen), "FFA hands out %d distinct points before wrapping (%d unique)"
		% [SPAWN_POINTS.size(), _unique_count(seen)])
	v.check(seen == SPAWN_POINTS, "FFA walks the points in order (deterministic, no randi())")
	v.check(mode.get_spawn(0) == seen[0], "the cursor wraps back to the first point")
	# Determinism across rounds: the same setup gives the same sequence.
	var again := FFAMode.new()
	again.setup(SPAWN_POINTS)
	var repeat: Array[Vector3] = []
	for i in range(SPAWN_POINTS.size()):
		repeat.append(again.get_spawn(0))
	v.check(repeat == seen, "a fresh round reproduces the exact same sequence")


func _check_cursor_tdm() -> void:
	v.section("[TDM: per-team slices]")
	var mode := TDMMode.new()
	mode.setup(SPAWN_POINTS)
	var alpha: Array[Vector3] = []
	var bravo: Array[Vector3] = []
	for i in range(2):
		alpha.append(mode.get_spawn(0))
		bravo.append(mode.get_spawn(1))
	v.check(_all_distinct(alpha), "team 0 gets distinct points (%d unique)" % _unique_count(alpha))
	v.check(_all_distinct(bravo), "team 1 gets distinct points (%d unique)" % _unique_count(bravo))
	var shared := 0
	for p in alpha:
		if bravo.has(p):
			shared += 1
	v.check(shared == 0, "teams spawn in disjoint slices (%d shared point(s))" % shared)


# ─── [2] THE REAL ARENA ─────────────────────────────

func _check_bot_spawns() -> void:
	v.section("[arena: bot spawns]")
	var bots := _bots()
	v.check(bots.size() == BOT_COUNT, "the arena spawned %d bots" % bots.size())
	var min_d := 999.0
	var positions: Array[Vector3] = []
	for b in bots:
		positions.append((b as Node3D).global_position)
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			min_d = minf(min_d, positions[i].distance_to(positions[j]))
	v.check(bots.size() < 2 or min_d >= MIN_SEPARATION,
		"no two bots spawn inside %.1f m (min distance %.2f m)" % [MIN_SEPARATION, min_d])


func _check_nobody_launched() -> void:
	v.section("[arena: nobody launched after %d frames]" % (_frame - 1))
	var launched: Array[String] = []
	var max_y := -999.0
	for b in _bots():
		var body := b as CharacterBody3D
		var y := body.global_position.y
		max_y = maxf(max_y, y)
		if y > FLOOR_Y or not body.is_on_floor():
			launched.append("%s y=%.1f floor=%s" % [body.name, y, body.is_on_floor()])
	v.check(launched.is_empty(), "every bot is on the floor (max y=%.1f m, limit %.1f; offenders: %s)"
		% [max_y, FLOOR_Y, " | ".join(PackedStringArray(launched)) if not launched.is_empty() else "none"])


func _check_current_weapon() -> void:
	v.section("[arena: current_weapon follows the active slot]")
	var player = _arena.get("player")
	v.check(player != null, "the arena has a player")
	if player == null:
		return
	var secondary: Weapon = _arena._slot_weapon("secondary")
	v.check(secondary != null, "the secondary slot holds a weapon")
	_arena._switch_cd = 0.0
	_arena._activate_slot("secondary")
	v.check(player.current_weapon == secondary,
		"after switching to secondary, current_weapon is that weapon (%s)"
		% (player.current_weapon.name if player.current_weapon != null else "null"))
	_arena._drop_active()
	v.check(player.current_weapon == null,
		"after dropping, current_weapon is null (%s)"
		% (player.current_weapon.name if player.current_weapon != null else "null"))
	v.check(String(_arena.get("active_slot")) == "", "the arena's active_slot is empty after the drop")


## A spawn while the raid is RUNNING (not from _ready), which is the shape the
## wave spawner uses. HONEST LIMIT (measured): this does NOT discriminate the
## racy order (add_child then move) from the fixed one (move then add_child) in
## the ARENA path - both give 18/18 PASS - so it is a regression GUARD ("a
## mid-raid spawn ends up on the floor"), not a proof of the spawn race.
## npc-body's scenario in NpcWaveSpawner is where the order did matter.
func _spawn_mid_raid() -> void:
	v.section("[arena: mid-raid spawn race]")
	for i in range(2):
		var seq: int = int(_arena.get("_bot_seq")) + 1
		var team: int = _arena.game_mode.assign_team(900 + i)
		_arena._spawn_bot(_arena._free_spawn(team), team)
		_mid_run_names.append("Bot%d" % seq)


func _check_mid_raid_bots_landed() -> void:
	v.check(_mid_run_names.size() == 2, "spawned %d bot(s) mid-raid (the race scenario)" % _mid_run_names.size())
	for bot_name in _mid_run_names:
		var bot := _arena.get_node_or_null(NodePath(bot_name)) as CharacterBody3D
		v.check(bot != null and bot.global_position.y <= FLOOR_Y and bot.is_on_floor(),
			"%s spawned mid-raid stays on the floor (y=%.2f, floor=%s)"
			% [bot_name, bot.global_position.y if bot != null else -999.0,
				str(bot.is_on_floor()) if bot != null else "missing"])


# ─── HELPERS ───

func _bots() -> Array:
	return get_nodes_in_group("bots")


func _all_distinct(points: Array[Vector3]) -> bool:
	return _unique_count(points) == points.size()


func _unique_count(points: Array[Vector3]) -> int:
	var unique: Array[Vector3] = []
	for p in points:
		if not unique.has(p):
			unique.append(p)
	return unique.size()
