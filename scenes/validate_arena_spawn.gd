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
## The arena's player participant id (`arena_manager.PLAYER_ID`); kept here so the
## attribution checks can assert who was credited.
const PLAYER_ID := 0
## Switch the arena to TDM and re-spawn, then check it: FFA gives every bot its
## own team (1,2,3), but "two teams with two colours" is the TDM case.
const TDM_CHECK_FRAME := FLOOR_FRAMES + 4
## Wall-clock guard: the whole frame plan (134 frames of a headless scene) takes a
## couple of seconds. If the engine is starved (the shared .godot cache under
## contention), the harness would otherwise sit here until the gate timeout kills
## it, leaving a silent log. Fail fast with a diagnostic instead.
const TIME_BUDGET_MS := 120000
const FLOOR_Y := 3.0

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, 10), Vector3(10, 0, 10),
]

var v: ValidateUtil
var _arena
var _frame := 0
var _done := false
var _mid_run_names: Array[String] = []
var _tdm_names: Array[String] = []
## The frame-130 block must run exactly once and must NOT end the gate (TDM still follows).
var _tdm_started := false
## The frame-130 block must run exactly once, and must not end the gate.


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
	if Time.get_ticks_msec() > TIME_BUDGET_MS:
		print("TIMEOUT: %d frames in %d ms — the engine is starved (shared .godot cache under contention?); re-run, or clear .godot/uid_cache.bin + .godot/editor/filesystem_cache10" % [_frame, Time.get_ticks_msec()])
		v.check(false, "the frame plan finished inside the %d ms budget" % TIME_BUDGET_MS)
		quit(1)
		return true
	_frame += 1
	if _frame == 3:
		_check_bot_spawns()
		_check_current_weapon()
		return false
	if _frame == MID_RUN_FRAME:
		_spawn_mid_raid()
		return false
	if _frame >= FLOOR_FRAMES and not _tdm_started:
		# NOT _done yet: the TDM section below still has to run (the gate only ends
		# in the block after TDM_CHECK_FRAME).
		_tdm_started = true
		_check_nobody_launched()
		_check_mid_raid_bots_landed()
		_check_free_spawn_dedup()
		_check_teams_and_attribution()
		_switch_to_tdm_and_spawn()
		return false
	if _frame >= TDM_CHECK_FRAME:
		_done = true
		_check_tdm_two_teams()
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
		# A launched body goes to ~100 m; `is_on_floor()` alone is NOT the signal
		# (a bot walking off a ledge is legitimately airborne for a frame).
		if y > FLOOR_Y:
			launched.append("%s y=%.1f floor=%s" % [body.name, y, body.is_on_floor()])
	v.check(launched.is_empty(), "no bot is in the air (max y=%.1f m, limit %.1f; offenders: %s)"
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
		# Same id/team scheme the arena uses in _spawn_bots(), or the team check
		# below would (correctly) complain that the probe invented a team.
		var team: int = _arena.game_mode.assign_team(seq)
		_arena._spawn_bot(_arena._free_spawn(team), team)
		_mid_run_names.append("Bot%d" % seq)


func _check_mid_raid_bots_landed() -> void:
	v.check(_mid_run_names.size() == 2, "spawned %d bot(s) mid-raid (the race scenario)" % _mid_run_names.size())
	for bot_name in _mid_run_names:
		var bot := _arena.get_node_or_null(NodePath(bot_name)) as CharacterBody3D
		v.check(bot != null and bot.global_position.y <= FLOOR_Y,
			"%s spawned mid-raid stays on the ground (y=%.2f, floor=%s)"
			% [bot_name, bot.global_position.y if bot != null else -999.0,
				str(bot.is_on_floor()) if bot != null else "missing"])


## The DETERMINISTIC core of the spawn fix, tested directly (npc-body's
## suggestion): 8 calls is more than the 4 spawn points, so the per-team cursor
## wraps and the dedup in _free_spawn() has to hold. This discriminates in a way
## the order-based check cannot: with `randi()` (or with the nudge removed) two
## points coincide and the assertion fails; no physics step is involved.
## Threshold is 0.5 m, not the 0.9 m step: a point that needs SEVERAL nudges
## (step 1 + step 2 at different angles) can end closer than one step length.
func _check_free_spawn_dedup() -> void:
	v.section("[arena: _free_spawn never repeats a point]")
	var team: int = int(_arena.get("_player_team"))
	var seen: Array[Vector3] = []
	for i in range(8):
		seen.append(_arena._free_spawn(team))
	v.check(seen.size() == 8, "_free_spawn returned %d points (8 > the 4 spawn points, so it wrapped)" % seen.size())
	var min_d := 999.0
	for i in range(seen.size()):
		for j in range(i + 1, seen.size()):
			var a := seen[i]
			var c := seen[j]
			min_d = minf(min_d, Vector2(a.x - c.x, a.z - c.z).length())
	v.check(min_d >= 0.5, "every pair of _free_spawn points is apart in XZ (min %.2f m, threshold 0.5)" % min_d)


## The arena used to spawn bots with team -1: the team was written to a meta but
## never applied to the bot, which silently disabled team tint, per-team
## hostility (in FFA the bots never fought each other, they only targeted the
## player), the squad blackboard (needs team >= 0) and died_with_team(). npc-body
## found it. Real teams also require real attribution: the arena credited the
## PLAYER for every bot death, which only stayed invisible while bots could not
## kill each other.
func _check_teams_and_attribution() -> void:
	v.section("[arena: bots carry a real team + kills are attributed]")
	var bots := _bots()
	v.check(bots.size() >= 2, "%d bot(s) to check" % bots.size())
	for b in bots:
		var bot := b as NpcBot
		var meta_id: int = int(bot.get_meta("id", -1))
		v.check(bot.team >= 0 and bot.team == _arena.game_mode.assign_team(meta_id),
			"%s carries a real team (%d) matching assign_team(%d)" % [bot.name, bot.team, meta_id])
		v.check(bot.npc_id == meta_id, "%s npc_id=%d matches its participant id" % [bot.name, bot.npc_id])
		v.check(bot.friendly_fire == _arena.game_mode.friendly_fire,
			"%s friendly_fire=%s matches the mode" % [bot.name, str(bot.friendly_fire)])
	if bots.size() < 2:
		return
	# Hostility: two bots on DIFFERENT teams are hostile with friendly fire off.
	var a := bots[0] as NpcBot
	var b2 := bots[1] as NpcBot
	if a.team != b2.team:
		v.check(NpcTargeting.is_hostile(b2 as Node, a.team, false),
			"a bot treats a different team (%d vs %d) as hostile" % [a.team, b2.team])
	else:
		v.check(not NpcTargeting.is_hostile(b2 as Node, a.team, false),
			"teammates (%d == %d) are not hostile with friendly fire off" % [a.team, b2.team])
	# Attribution, in the mode's own score key (FFA: id, TDM: team).
	var pair := _killer_victim_pair(bots)
	if pair.is_empty():
		v.check(false, "a non-teammate pair exists to check kill attribution")
		return
	var killer := pair[0] as NpcBot
	var victim := pair[1] as NpcBot
	var key := _score_key(killer.npc_id)
	var before_killer: int = _arena.game_mode.get_score_of(key)
	var before_player: int = _arena.game_mode.get_score_of(_score_key(PLAYER_ID))
	victim.set_attacker(killer.npc_id)
	_arena._on_bot_health_died("gate", victim)
	v.check(_arena.game_mode.get_score_of(key) == before_killer + 1,
		"a bot-vs-bot kill scores for the killer bot (id %d)" % killer.npc_id)
	v.check(_arena.game_mode.get_score_of(_score_key(PLAYER_ID)) == before_player,
		"a bot-vs-bot kill does NOT score for the player")
	# No recorded attacker (environment / the range resolver leaves it at -1): the
	# player is credited, exactly as before this change.
	var spare := _victim_for_player(bots)
	if spare == null:
		v.check(false, "a bot not on the player's team exists for the player-kill check")
		return
	var before_player2: int = _arena.game_mode.get_score_of(_score_key(PLAYER_ID))
	spare.set_attacker(-1)
	_arena._on_bot_health_died("gate", spare)
	v.check(_arena.game_mode.get_score_of(_score_key(PLAYER_ID)) == before_player2 + 1,
		"a kill with no recorded attacker still scores for the player")


## FFA scores per participant id, TDM per team: the mode owns the key.
func _score_key(id: int) -> int:
	return _arena.game_mode.assign_team(id) if _arena.game_mode.team_count > 1 else id


func _killer_victim_pair(bots: Array) -> Array:
	for i in range(bots.size()):
		for j in range(bots.size()):
			var k := bots[i] as NpcBot
			var v2 := bots[j] as NpcBot
			if k != v2 and k.team != v2.team:
				return [k, v2]
	return []


func _victim_for_player(bots: Array) -> NpcBot:
	var player_team: int = _arena.game_mode.assign_team(PLAYER_ID)
	for b in bots:
		var bot := b as NpcBot
		if bot.team != player_team:
			return bot
	return null


## Replaces the mode with TDM and spawns a fresh group through the same arena path,
## so the two-team case (and its tint) is exercised for real, not asserted from the
## mode's own math.
func _switch_to_tdm_and_spawn() -> void:
	_tdm_names.clear()
	var mode := TDMMode.new()
	mode.setup(_arena._spawn_points())
	_arena.game_mode = mode
	_arena._player_team = mode.assign_team(PLAYER_ID)
	for i in range(3):
		var seq: int = int(_arena.get("_bot_seq")) + 1
		var team: int = mode.assign_team(seq)
		_arena._spawn_bot(_arena._free_spawn(team), team)
		_tdm_names.append("Bot%d" % seq)


func _check_tdm_two_teams() -> void:
	v.section("[arena: TDM gives exactly two teams, tinted and hostile]")
	var bots: Array[NpcBot] = []
	for n in _tdm_names:
		var b := _arena.get_node_or_null(NodePath(n)) as NpcBot
		if b != null:
			bots.append(b)
	v.check(bots.size() == 3, "spawned %d bot(s) under TDM" % bots.size())
	var teams := {}
	var tinted := 0
	for bot in bots:
		teams[bot.team] = true
		v.check(bot.team == _arena.game_mode.assign_team(bot.npc_id),
			"%s team=%d matches assign_team(%d)" % [bot.name, bot.team, bot.npc_id])
		var rig := bot.get_node_or_null("Skeleton3D") as HumanoidRig
		var mats := rig.own_materials() if rig != null else []
		var col: Color = Color.TRANSPARENT
		var has_col := false
		if not mats.is_empty():
			var got := mats[0].get_shader_parameter("modulate_color") as Color
			if got != null:
				col = got
				has_col = true
		var want := NpcVisuals.team_color(bot.team)
		var ok: bool = has_col and col.is_equal_approx(want)
		if ok:
			tinted += 1
		v.check(ok, "%s is tinted with its team colour (%s vs %s)" % [bot.name, str(col), str(want)])
	v.check(teams.size() == 2, "TDM produced exactly 2 distinct teams (%s)" % str(teams.keys()))
	v.check(tinted == bots.size(), "every TDM bot tinted (%d/%d)" % [tinted, bots.size()])
	var mates := _pair_with_same_team(bots)
	if mates.is_empty():
		v.check(false, "a teammate pair exists for the TDM friendly-fire check")
	else:
		v.check(not NpcTargeting.is_hostile(mates[1] as Node, (mates[0] as NpcBot).team, false),
			"TDM teammates (%d == %d) are NOT hostile" % [(mates[0] as NpcBot).team, (mates[1] as NpcBot).team])
	var enemies := _killer_victim_pair(bots)
	if enemies.is_empty():
		v.check(false, "an enemy pair exists for the TDM hostility check")
	else:
		v.check(NpcTargeting.is_hostile(enemies[1] as Node, (enemies[0] as NpcBot).team, false),
			"TDM enemies (%d vs %d) are hostile" % [(enemies[0] as NpcBot).team, (enemies[1] as NpcBot).team])


func _pair_with_same_team(bots: Array) -> Array:
	for i in range(bots.size()):
		for j in range(i + 1, bots.size()):
			if (bots[i] as NpcBot).team == (bots[j] as NpcBot).team:
				return [bots[i], bots[j]]
	return []


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
