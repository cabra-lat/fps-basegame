class_name NpcPerception
extends RefCounted
## Pure perception helpers for NpcBot (src/npcs lane).
##
## Duck-typed and side-effect free so bot.gd keeps only state/orchestration.
## "Crouched/still targets are less noticeable" lives here; a caller passes
## whether a fresh noise has restored full attention.

static func is_crouched(n) -> bool:
	if not is_instance_valid(n):
		return false
	# Explicit bool/int flags (bots, dummies). NOTE: never call bool() on an
	# arbitrary value — PlayerController exposes a `crouched` *signal*, and
	# bool(Signal) is an engine error (spams every physics frame).
	for p in ["is_crouched", "crouched", "is_crouching"]:
		var v = n.get(p)
		if v is bool:
			return v
		if v is int:
			return v != 0
	# Player-like state machine (PlayerController.crouching.state is a String).
	var sm = n.get("crouching")
	if sm != null:
		var st = sm.get("state")
		if st is String:
			return st == "Crouching" or st == "Proning"
	# Metadata fallback for tests/dummies.
	for m in ["crouched", "is_crouched"]:
		if n.has_meta(m):
			var mv = n.get_meta(m)
			if mv is bool:
				return mv
			if mv is int:
				return mv != 0
	return false


static func target_speed(n) -> float:
	if not is_instance_valid(n):
		return 0.0
	var v = n.get("velocity")
	if v is Vector3:
		return (v as Vector3).length()
	return 0.0


## Crouched and/or still targets are less noticeable; a fresh noise restores
## full attention.
static func effective_sight_range(target, sight_range: float,
		crouch_factor: float, still_factor: float, noise_boosted: bool) -> float:
	if noise_boosted:
		return sight_range
	var f := 1.0
	if is_crouched(target):
		f *= crouch_factor
	if target_speed(target) < 0.4:
		f *= still_factor
	return sight_range * f


## Horizontal FOV test: is `flat_to_target` inside the body's cone?
static func in_cone(body: Node3D, flat_to_target: Vector3,
		fov_degrees: float) -> bool:
	if flat_to_target.length_squared() < 0.0001:
		return true
	var fwd := -body.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return false
	var ang := rad_to_deg(fwd.normalized().angle_to(flat_to_target.normalized()))
	return ang <= fov_degrees * 0.5
