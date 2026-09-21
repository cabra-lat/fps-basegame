# res://src/meta/raid_report.gd
class_name RaidReport
extends RefCounted
## Readable end-of-raid report. Persisted inside the profile so the end-of-raid
## screen can show the last result even after a restart.

var outcome: int = 0 # Raid.Outcome
var outcome_name: String = "—"
var survived: bool = false
var exp: int = 0
var currency_delta: int = 0
var gained: Array[Dictionary] = [] # {name, path, stack}
var lost: Array[Dictionary] = [] # loadout forfeited
var loot_discarded: int = 0
var loadout_restored: bool = false
## Insured items scheduled to come back after the delay.
var insured: int = 0

func summary() -> String:
	if survived:
		return "%s — %d item(ns) no stash, +%d EXP, +₽%d" % [outcome_name, gained.size(), exp, currency_delta]
	var ins := "" if insured <= 0 else ", %d segurados voltam depois" % insured
	return "%s — %d equipamento(s) perdido(s), %d loot descartado, +%d EXP%s" % [outcome_name, lost.size(), loot_discarded, exp, ins]

func to_dict() -> Dictionary:
	return {
		"outcome": outcome,
		"outcome_name": outcome_name,
		"survived": survived,
		"exp": exp,
		"currency_delta": currency_delta,
		"gained": gained,
		"lost": lost,
		"loot_discarded": loot_discarded,
		"loadout_restored": loadout_restored,
		"insured": insured,
	}

static func from_dict(d: Dictionary) -> RaidReport:
	var r := RaidReport.new()
	r.outcome = int(d.get("outcome", 0))
	r.outcome_name = String(d.get("outcome_name", "—"))
	r.survived = bool(d.get("survived", false))
	r.exp = int(d.get("exp", 0))
	r.currency_delta = int(d.get("currency_delta", 0))
	r.gained = _dict_array(d.get("gained", []))
	r.lost = _dict_array(d.get("lost", []))
	r.loot_discarded = int(d.get("loot_discarded", 0))
	r.loadout_restored = bool(d.get("loadout_restored", false))
	r.insured = int(d.get("insured", 0))
	return r

static func _dict_array(v) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for e in v:
			if e is Dictionary:
				out.append(e)
	return out
