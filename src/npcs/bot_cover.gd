class_name NpcCover
extends RefCounted
## Cover / line-of-sight geometry helpers for NpcBot (src/npcs lane).
##
## Pure static helpers over a CollisionObject3D so bot.gd does not carry the
## raycast plumbing. All functions are physics-safe (callers invoke them from
## _physics_process per AGENTS.md rule 4).
##
## Cover is "cheap and legible": probe a ring of points around the body and
## pick the nearest one that blocks LOS to the threat, has walkable floor under
## it and a clear path from the body. No pathfinding.

const GROUND_MIN_NORMAL_DOT: float = 0.6


## Body-excluding raycast in the body's world.
static func raycast(body: CollisionObject3D, from: Vector3, to: Vector3) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	return space.intersect_ray(query)


## True when `collider` is `node` or parented under it (child body colliders,
## e.g. the player's TorsoAttachment).
static func collider_belongs_to(node: Node, collider) -> bool:
	if collider == node:
		return true
	if not (collider is Node):
		return false
	var n: Node = (collider as Node).get_parent()
	while n != null:
		if n == node:
			return true
		n = n.get_parent()
	return false


## Ground point under an XZ candidate, or Vector3.INF when none/too steep.
static func ground_at(body: Node3D, cand: Vector3, probe: float) -> Vector3:
	var top := Vector3(cand.x, body.global_position.y + probe, cand.z)
	var bottom := Vector3(cand.x, body.global_position.y - probe, cand.z)
	var hit := raycast(body as CollisionObject3D, top, bottom)
	if hit.is_empty():
		return Vector3.INF
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.dot(Vector3.UP) < GROUND_MIN_NORMAL_DOT:
		return Vector3.INF
	return hit.get("position", Vector3.INF)


## Horizontal path from the body to a candidate is clear of walls (bodies are
## fine — the bot can slide/push).
static func path_clear(body: Node3D, cand: Vector3) -> bool:
	var from := body.global_position + Vector3.UP * 1.0
	var to := Vector3(cand.x, from.y, cand.z)
	var hit := raycast(body as CollisionObject3D, from, to)
	if hit.is_empty():
		return true
	return hit.collider is CharacterBody3D


## Does standing at cover_pos block LOS to threat_pos? (threat_node may be null
## when the threat position is only an approximation.)
static func blocks_los(body: Node3D, cover_pos: Vector3, threat_pos: Vector3,
		eye_height: float, threat_node: Node) -> bool:
	var from := cover_pos + Vector3.UP * eye_height
	var to := threat_pos + Vector3.UP * 1.2
	var hit := raycast(body as CollisionObject3D, from, to)
	if hit.is_empty():
		return false
	return not collider_belongs_to(threat_node, hit.collider)


## Nearest ring point that blocks LOS to the threat; Vector3.ZERO if none.
static func find_cover(body: Node3D, threat_pos: Vector3, radius: float,
		rays: int, eye_height: float, threat_node: Node) -> Vector3:
	if rays <= 0 or radius <= 0.0:
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_d := INF
	for i in rays:
		var ang := TAU * float(i) / float(rays)
		var cand := body.global_position \
			+ Vector3(sin(ang), 0.0, cos(ang)) * radius
		if not path_clear(body, cand):
			continue
		var ground := ground_at(body, cand, radius)
		if ground == Vector3.INF:
			continue
		if not blocks_los(body, ground, threat_pos, eye_height, threat_node):
			continue
		var d := body.global_position.distance_to(ground)
		if d < best_d:
			best_d = d
			best = ground
	return best
