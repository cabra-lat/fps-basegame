class_name Raid
extends Node
## Raid state machine + event bus (Fase 1).
##
## States: PREP -> RAID -> RESOLVE. Self-ticking on the physics clock (never
## _process polling). The event bus is intentionally consumer-less for now:
## quests/skills (Fase 3+) will subscribe. Emit only; nobody is required.

enum State { PREP, RAID, RESOLVE }
enum Outcome { NONE, SURVIVED, RUN_THROUGH, MIA, KIA, LEFT_BEHIND }

# ─── RAID EVENT BUS (base for quests/skills) ───
signal raid_started
signal raid_ended(outcome: int)
signal player_extracted(point: Node)
signal kill_registered(killer_id: int, victim_id: int, weapon: String)
signal item_looted(item: Resource)
signal exp_gained(amount: int)
signal zone_entered(zone: Node)
signal zone_left(zone: Node)

## RUN_THROUGH rule (genre-typical): extract under 7 min AND under 200 EXP earned.
const RUN_THROUGH_TIME := 420.0
const RUN_THROUGH_EXP := 200

@export var duration: float = 2100.0 # 35 min (genre-typical long raid)

var state: State = State.PREP
var outcome: Outcome = Outcome.NONE
var time_left: float = 0.0
var elapsed: float = 0.0
var exp: int = 0

func _ready() -> void:
	time_left = duration

func begin() -> bool:
	if state == State.RAID:
		return false
	state = State.RAID
	outcome = Outcome.NONE
	time_left = duration
	elapsed = 0.0
	exp = 0
	raid_started.emit()
	return true

func is_active() -> bool:
	return state == State.RAID

func _physics_process(delta: float) -> void:
	tick(delta)

## Advances the countdown; MIA when it reaches zero without extracting.
func tick(delta: float) -> void:
	if state != State.RAID:
		return
	elapsed += delta
	time_left = maxf(0.0, duration - elapsed)
	if time_left <= 0.0:
		_end(Outcome.MIA)

func add_exp(amount: int) -> void:
	if state != State.RAID or amount <= 0:
		return
	exp += amount
	exp_gained.emit(amount)

func register_kill(killer_id: int, victim_id: int, weapon: String = "") -> void:
	if state != State.RAID:
		return
	kill_registered.emit(killer_id, victim_id, weapon)

func register_loot(item: Resource) -> void:
	if state != State.RAID:
		return
	item_looted.emit(item)

func zone_enter(zone: Node) -> void:
	if state == State.RAID:
		zone_entered.emit(zone)

func zone_leave(zone: Node) -> void:
	if state == State.RAID:
		zone_left.emit(zone)

## Successful extraction: RUN_THROUGH when too fast and too poor, else SURVIVED.
func extract(point: Node) -> Outcome:
	if state != State.RAID:
		return outcome
	var out: Outcome = Outcome.RUN_THROUGH \
		if (elapsed < RUN_THROUGH_TIME and exp < RUN_THROUGH_EXP) else Outcome.SURVIVED
	_end(out)
	player_extracted.emit(point)
	return out

## Hard end (KIA on death, LEFT_BEHIND on abandon).
func end(out: Outcome) -> void:
	if state != State.RAID:
		return
	_end(out)

func _end(out: Outcome) -> void:
	state = State.RESOLVE
	outcome = out
	raid_ended.emit(out)

func outcome_name(out: int = -1) -> String:
	match (outcome if out < 0 else out):
		Outcome.SURVIVED: return "SURVIVED"
		Outcome.RUN_THROUGH: return "RUN THROUGH"
		Outcome.MIA: return "MIA"
		Outcome.KIA: return "KIA"
		Outcome.LEFT_BEHIND: return "LEFT BEHIND"
		_: return "—"

func time_text() -> String:
	var t: int = int(ceil(maxf(time_left, 0.0)))
	return "%02d:%02d" % [t / 60, t % 60]
