class_name Faction
extends Resource
## One faction, as DATA.
##
## Why not `enum Faction { A, B }`: a faction is CONTENT (like maps, items,
## traders), not mechanics. A framework cannot know how many factions a game
## has, so hardcoding two of them is the same mistake as hardcoding the weapon
## list. The pack lives in `resources/meta/factions/*.tres` and the game that
## ships on top of this framework defines its own names — the examples in the
## repo are neutral placeholders, never content from an existing game.
##
## Mechanics stay enums (`Ammo.Type`, `BodyPart.Type`, `Certification.Standard`):
## finite, universal, owned by the engine. Content is data.
##
## Loaded through `FactionRegistry`; see `PlayerProfile.faction` (a String id)
## and `ExtractionPoint.allowed_factions`.

## Stable key used by profiles, saves and extraction gates. Never player-facing.
@export var id: String = ""
## Player-facing name. Data, so the game can rename it without touching code.
@export var display_name: String = ""
## Team-tint hint for HUD/markers. Aligned with the NPC team palette
## (`src/npcs/bot_visuals.gd`), but a match team is per-match state, not faction.
@export var color: Color = Color(0.85, 0.85, 0.9, 1.0)
## false = NPC-only faction (never selectable for a player profile).
@export var playable: bool = true


## The label to show; falls back to the id only so a half-filled pack is readable.
func resolved_name() -> String:
	return display_name if display_name != "" else id
