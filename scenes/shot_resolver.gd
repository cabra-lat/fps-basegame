class_name ShotResolver
extends RefCounted
## Shared hitscan core for arena_manager and debug_range (was duplicated).
## Physics rule (AGENTS.md 4): call only from _physics_process. The function
## owns the raycast + exclude + distance/angle/impact; callers own the HUD
## message, the impact FX and the collider reaction (they differ per scene).

## Returns {hit: false} on a miss, else {hit: true, position, distance, angle,
## impact, collider}. `camera` may be null (returns miss).
static func resolve(camera: Camera3D, world: World3D, center: Vector2, round: Ammo, plate_mat: BallisticMaterial, shot_range: float, excludes: Array[RID]) -> Dictionary:
	if camera == null or world == null or round == null:
		return {"hit": false}
	var origin := camera.project_ray_origin(center)
	var end := origin + camera.project_ray_normal(center) * shot_range
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = excludes
	query.collide_with_areas = false
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": false}
	var position: Vector3 = result.position
	var dir: Vector3 = (position - origin).normalized()
	var distance := origin.distance_to(position)
	var angle := rad_to_deg(acos(clampf(-dir.dot(result.normal), -1.0, 1.0)))
	return {
		"hit": true,
		"position": position,
		"distance": distance,
		"angle": angle,
		"impact": BallisticsCalculator.calculate_impact(round, plate_mat, 3.0, distance, angle),
		"collider": result.collider,
	}

## Apply a resolved hit the same way in every scene: impact spark, collider
## reaction (range_hit), then hit audio (flesh for bodies, steel otherwise —
## world loot/props are RigidBody3D and simply don't fire as steel in the range,
## where targets are StaticBody3D). Callers own only the HUD message.
static func apply_hit(parent: Node, collider: Object, impact: BallisticsImpact, round: Ammo, pos: Vector3, audio: GameAudio) -> void:
	HitFlash.spawn(parent, pos)
	if collider != null and collider.has_method("range_hit"):
		collider.range_hit(impact, round)
		if audio != null:
			if collider is NpcBot:
				audio.play_hit_flesh(pos)
			else:
				audio.play_hit_steel(pos)
	elif collider is RigidBody3D and audio != null:
		audio.play_hit_steel(pos) # loot / props
