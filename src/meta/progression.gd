# res://src/meta/progression.gd
class_name Progression
extends Node
## Skills (use-based) + quests, driven by the real hooks:
##   survival.stamina_changed  -> endurance xp on stamina drained
##   overweight travel         -> strength xp (sampled in _physics_process)
##   health.health_changed     -> vitality xp on damage taken
## and by the raid event bus for quest objectives. Levels are written back into
## PlayerSurvival.endurance_level / .strength_level (the hooks that existed).

signal skill_leveled(skill_id: String, level: int)
signal quest_reward(quest: Quest, summary: String)

const SAVE_INTERVAL := 5.0 # throttle disk writes while skills tick per frame
const QUESTS_DIR := "res://resources/meta/quests"

var profile: MetaProfile
var save_callable: Callable = Callable()

var _raid: Raid
## Duck-typed on purpose: the meta lane must not statically depend on the
## addon PlayerController (keeps skill/quest code headless-loadable).
var _player: Node
var _player_id: int = 0
var _last_stamina: float = -1.0
var _last_pos := Vector3.ZERO
var _have_pos := false
var _dirty := false
var _since_save := 0.0

func setup(p_profile: MetaProfile, save: Callable = Callable()) -> void:
	profile = p_profile
	if profile == null:
		profile = MetaProfile.new()
	if profile.skills == null:
		profile.skills = SkillSet.new()
	if profile.quests == null:
		profile.quests = QuestLog.new()
	save_callable = save
	if not profile.quests.changed.is_connected(mark_dirty):
		profile.quests.changed.connect(mark_dirty)
	if not profile.quests.quest_completed.is_connected(_on_quest_completed):
		profile.quests.quest_completed.connect(_on_quest_completed)

## Load the quest pack and re-apply saved progress to the (now known) quests.
func load_quests(dir: String = QUESTS_DIR) -> int:
	var n := profile.quests.load_dir(dir)
	profile.quests.apply_state(profile.progress.get("quests", {}))
	return n

func bind_raid(raid: Raid) -> void:
	if _raid == raid:
		return
	_raid = raid
	if raid == null:
		return
	if not raid.kill_registered.is_connected(_on_kill):
		raid.kill_registered.connect(_on_kill)
	if not raid.item_looted.is_connected(_on_loot):
		raid.item_looted.connect(_on_loot)
	if not raid.player_extracted.is_connected(_on_extracted):
		raid.player_extracted.connect(_on_extracted)
	if not raid.raid_ended.is_connected(_on_raid_ended):
		raid.raid_ended.connect(_on_raid_ended)

func bind_player(player: Node, player_id: int = 0) -> void:
	_player = player
	_player_id = player_id
	if player == null:
		return
	var survival = player.get("survival")
	if survival != null:
		_last_stamina = float(survival.stamina)
		if not survival.stamina_changed.is_connected(_on_stamina_changed):
			survival.stamina_changed.connect(_on_stamina_changed)
	var health = player.get("health")
	if health != null:
		if not health.health_changed.is_connected(_on_health_changed):
			health.health_changed.connect(_on_health_changed)
	_apply_skill_levels()

func _physics_process(delta: float) -> void:
	var survival = _player.get("survival") if _player != null and is_instance_valid(_player) else null
	if survival != null and survival.is_overweight():
		var pos: Vector3 = _player.global_position
		if _have_pos:
			on_distance_moved(Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length())
		_last_pos = pos
		_have_pos = true
	_since_save += delta
	if _dirty and _since_save >= SAVE_INTERVAL:
		flush()

# ─── SKILL ACTIVITY (public so the harness can drive the real conversions) ───

func on_stamina_drained(amount: float) -> void:
	_after_skill(SkillSet.ENDURANCE, profile.skills.add_activity(SkillSet.ENDURANCE, amount, SkillSet.ENDURANCE_XP_PER_STAMINA))

func on_distance_moved(meters: float) -> void:
	_after_skill(SkillSet.STRENGTH, profile.skills.add_activity(SkillSet.STRENGTH, meters, SkillSet.STRENGTH_XP_PER_METER))

func on_damage_taken(hp: float) -> void:
	_after_skill(SkillSet.VITALITY, profile.skills.add_activity(SkillSet.VITALITY, hp, SkillSet.VITALITY_XP_PER_HP))

func mark_dirty() -> void:
	_dirty = true

## Write now (called on raid end and by tests).
func flush() -> void:
	_since_save = 0.0
	_dirty = false
	profile.sync_progress()
	if save_callable.is_valid():
		save_callable.call()

## Tear down every connection this node made, so a long-lived Raid/Player (or
## the profile's Resource signals) cannot outlive the Progression owner.
func _exit_tree() -> void:
	_teardown()

func _teardown() -> void:
	if _raid != null and is_instance_valid(_raid):
		_disconnect_if(_raid.kill_registered, _on_kill)
		_disconnect_if(_raid.item_looted, _on_loot)
		_disconnect_if(_raid.player_extracted, _on_extracted)
		_disconnect_if(_raid.raid_ended, _on_raid_ended)
	if _player != null and is_instance_valid(_player):
		var survival = _player.get("survival")
		if survival != null:
			_disconnect_if(survival.stamina_changed, _on_stamina_changed)
		var health = _player.get("health")
		if health != null:
			_disconnect_if(health.health_changed, _on_health_changed)
	if profile != null and profile.quests != null:
		_disconnect_if(profile.quests.changed, mark_dirty)
		_disconnect_if(profile.quests.quest_completed, _on_quest_completed)

func _disconnect_if(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)

# ─── HOOKS ──────────────────────────────────────────

func _on_stamina_changed(current: float, _maximum: float) -> void:
	if _last_stamina >= 0.0 and current < _last_stamina:
		on_stamina_drained(_last_stamina - current)
	_last_stamina = current

func _on_health_changed(_part, old_hp: float, new_hp: float) -> void:
	if new_hp < old_hp:
		on_damage_taken(old_hp - new_hp)

func _on_kill(killer_id: int, victim_id: int, weapon: String) -> void:
	profile.quests.on_kill(killer_id, victim_id, weapon, _player_id)
	mark_dirty()

func _on_loot(item: Resource) -> void:
	profile.quests.on_loot(item)
	mark_dirty()

func _on_extracted(point: Node) -> void:
	var outcome: int = _raid.outcome if _raid != null else Raid.Outcome.NONE
	profile.quests.on_extracted(point, outcome)
	mark_dirty()

func _on_raid_ended(outcome: int) -> void:
	profile.quests.on_raid_ended(outcome)
	flush()

# ─── REWARDS ────────────────────────────────────────

func _on_quest_completed(quest: Quest) -> void:
	_grant_rewards(quest)
	profile.quests.mark_claimed(quest.id)
	mark_dirty()
	quest_reward.emit(quest, quest.reward_text())

func _grant_rewards(quest: Quest) -> void:
	if quest.reward_currency > 0:
		profile.earn_currency(quest.reward_currency)
	if quest.reward_exp > 0:
		profile.total_exp += quest.reward_exp
	for path in quest.reward_items:
		var item := ItemCodec.item_from_path(String(path))
		if item == null:
			continue
		if not profile.stash.deposit(item):
			push_warning("Progression: stash full, reward %s lost" % path)
	for skill_id in quest.reward_skill_xp:
		profile.skills.add_xp(String(skill_id), int(quest.reward_skill_xp[skill_id]))
	for trader_id in quest.reward_reputation:
		if profile.market != null:
			profile.market.add_reputation(String(trader_id), int(quest.reward_reputation[trader_id]))
	_apply_skill_levels()

func _apply_skill_levels() -> void:
	if _player != null and is_instance_valid(_player):
		profile.skills.apply_to_survival(_player.get("survival"))

func _after_skill(skill_id: String, gained: int) -> void:
	if gained > 0:
		_apply_skill_levels()
		skill_leveled.emit(skill_id, profile.skills.level(skill_id))
	mark_dirty()
