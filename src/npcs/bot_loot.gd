class_name NpcLoot
extends RefCounted
## Loot-target search for NpcBot (src/npcs lane).
##
## Picks the nearest unconsumed group "loot" node or corpse (any node exposing
## a true-valued is_alive(); dead bots qualify). Duck-typed to avoid a cyclic
## dependency on NpcBot.

static func find_nearest(body: Node3D, radius: float, looted: Dictionary) -> Node3D:
	if not body.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := radius
	for n in body.get_tree().get_nodes_in_group("loot"):
		if not (n is Node3D) or looted.has(n.get_instance_id()):
			continue
		var d: float = body.global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	for n in body.get_tree().get_nodes_in_group("bots"):
		if n == body or not (n is Node3D):
			continue
		if not n.has_method("is_alive") or bool(n.call("is_alive")):
			continue
		if looted.has(n.get_instance_id()):
			continue
		var d2: float = body.global_position.distance_to((n as Node3D).global_position)
		if d2 < best_d:
			best_d = d2
			best = n as Node3D
	return best
