class_name ArenaSpawnSolver
extends RefCounted
## Deterministic arena spawn allocation around GameMode's frozen team cursor.
## The solver owns only collision-free selection; scene-tree occupancy is supplied
## by arena_manager so dead bodies remain obstacles until their corpse despawns.

const SEPARATION := 0.7
const RINGS := 3
const RING_ANGLES := 8

var _round_spawns: Array[Vector3] = []


func begin_round() -> void:
	_round_spawns.clear()


## Returns a global spawn point, lifted by 0.5 m. Preference order is the mode
## cursor, another live authored point, then deterministic ring offsets from the
## original cursor point. The cursor advances exactly once, even when blocked.
func allocate(
		team: int,
		mode: GameMode,
		authored_points: Array[Vector3],
		occupied: Array[Vector3],
) -> Vector3:
	var base := mode.get_spawn(team)
	var at := base
	if _taken(at, occupied):
		for point in authored_points:
			if not _taken(point, occupied):
				at = point
				break

	var attempt := 0
	while _taken(at, occupied) and attempt < RINGS * RING_ANGLES:
		at = _candidate(base, attempt)
		attempt += 1

	# Keep the pre-lift point in the ledger, matching the arena's proven behavior.
	_round_spawns.append(at)
	return at + Vector3(0.0, 0.5, 0.0)


func _taken(at: Vector3, occupied: Array[Vector3]) -> bool:
	for used in _round_spawns:
		if used.distance_to(at) < SEPARATION:
			return true
	for body in occupied:
		if body.distance_to(at) < SEPARATION:
			return true
	return false


func _candidate(base: Vector3, attempt: int) -> Vector3:
	var ring := 1 + attempt / RING_ANGLES
	var angle := float(attempt % RING_ANGLES) * TAU / float(RING_ANGLES)
	return base + Vector3(cos(angle), 0.0, sin(angle)) * (SEPARATION * float(ring))
