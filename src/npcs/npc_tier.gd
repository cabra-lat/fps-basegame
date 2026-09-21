class_name NpcTier
extends RefCounted
## Difficulty tiers for NpcBot (Fase 2 cont, src/npcs lane).
##
## A tier tunes four levers used by the bot:
##   reaction_time        seconds of continuous sight before ENGAGING (slower at
##                        range, shortened inside engage_range)
##   shot_dispersion_deg  aim jitter applied when a melee/ranged attack lands
##   aggression           scales engage_range and chase speed
##   cover_use            0..1 commitment to seeking cover (search radius/priority)
##   burst_shots / reload_time  synthetic weapon cadence that opens the
##                        "reloading" cover trigger
##
## Tiers are intentionally few and plausible: RECRUIT < REGULAR < VETERAN.

enum Tier { RECRUIT, REGULAR, VETERAN }

static func config(tier: int) -> Dictionary:
	match tier:
		Tier.RECRUIT:
			return {
				"reaction_time": 1.4,
				"shot_dispersion_deg": 6.0,
				"aggression": 0.8,
				"cover_use": 0.6,
				"burst_shots": 3,
				"reload_time": 2.6,
			}
		Tier.VETERAN:
			return {
				"reaction_time": 0.25,
				"shot_dispersion_deg": 1.5,
				"aggression": 1.25,
				"cover_use": 1.0,
				"burst_shots": 6,
				"reload_time": 1.4,
			}
		_:
			return {
				"reaction_time": 0.7,
				"shot_dispersion_deg": 3.0,
				"aggression": 1.0,
				"cover_use": 0.85,
				"burst_shots": 4,
				"reload_time": 2.0,
			}

static func tier_name(tier: int) -> String:
	match tier:
		Tier.RECRUIT: return "RECRUIT"
		Tier.VETERAN: return "VETERAN"
		_: return "REGULAR"
