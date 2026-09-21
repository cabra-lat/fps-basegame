class_name NpcTargeting
extends RefCounted
## Target selection / friendly-fire rules for NpcBot (src/npcs lane).
##
## Duck-typed and side-effect free so bot.gd keeps only state/orchestration.
## Deliberately avoids referencing NpcBot (no cyclic global-class dependency);
## behaviour is identical to the previous in-bot helpers.

## Nearest hostile CharacterBody3D with health in `scene` from `body`.
static func acquire(body: Node3D, scene: Node, team: int,
		friendly_fire: bool) -> Node3D:
	if scene == null:
		return null
	var best: Node3D = null
	var best_d := INF
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if is_valid_target(body, n, team, friendly_fire):
			var d: float = (n as Node3D).global_position.distance_squared_to(
				body.global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
		stack.append_array(n.get_children())
	return best


static func is_valid_target(body: Node3D, n, team: int,
		friendly_fire: bool) -> bool:
	if n == null or n == body:
		return false
	if not is_instance_valid(n):
		return false
	if not (n is CharacterBody3D):
		return false
	if n.get("health") == null:
		return false
	# A corpse (dead bot) is not a target; duck-type is_alive().
	if n.has_method("is_alive") and not bool(n.call("is_alive")):
		return false
	return is_hostile(n, team, friendly_fire)


## Friendly-fire rule: with friendly_fire off, a bot never treats its own team
## as hostile. A target with no int `team` (player) is always hostile; bots
## with no team (team < 0) compare equal and ignore each other as before.
static func is_hostile(n: Node, team: int, friendly_fire: bool) -> bool:
	if friendly_fire:
		return true
	var t = n.get("team")
	if t is int:
		return int(t) != team
	return true
