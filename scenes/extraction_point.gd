class_name ExtractionPoint
extends Area3D
## Extraction zone with real genre-typical gates (Fase 1).
##
## Presence-based: while a player stands inside, progress accumulates on the
## physics clock; leaving cancels it. All rules are checked through can_use()
## so the HUD and the harness see the exact same verdict.

enum Faction { ALL, PMC_ONLY, SCAV_ONLY }
enum Kind { INSTANT, PAID, FLARE, LEVER, COOP, TIMED }

@export var display_name: String = "EXTRACT"
@export var faction: Faction = Faction.ALL
@export var kind: Kind = Kind.INSTANT
@export var extract_time: float = 0.0 ## seconds held inside (INSTANT = 0)
@export var single_use: bool = false
@export var required_item: String = "" ## item_id gating the point (note/key)
@export var paid_cost: int = 0 ## V-Ex: roubles charged on completion
@export var timed_open: float = 0.0 ## raid seconds when the window opens
@export var timed_close: float = 0.0 ## raid seconds when it closes (0 = never)

signal player_entered(point: ExtractionPoint)
signal player_left(point: ExtractionPoint)
signal progress_changed(point: ExtractionPoint, ratio: float)
signal cancelled(point: ExtractionPoint)
signal extracted(point: ExtractionPoint)
signal state_changed(point: ExtractionPoint)

var profile: PlayerProfile
var raid: Raid

var _bodies: Array[Node] = []
var _players_inside := 0
var _progress := 0.0
var _completed := false
var _lever_pulled := false
var _flare_active := false

func bind(p_profile: PlayerProfile, p_raid: Raid) -> void:
	profile = p_profile
	raid = p_raid

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not is_in_group("extraction_points"):
		add_to_group("extraction_points")

# ─── RULES ───

## Returns {ok: bool, reason: String}. Single source of truth for the HUD.
func can_use() -> Dictionary:
	if profile == null:
		return _no("sem perfil")
	if _completed and single_use:
		return _no("ja usada")
	match faction:
		Faction.PMC_ONLY:
			if profile.faction != PlayerProfile.Faction.PMC:
				return _no("apenas PMC")
		Faction.SCAV_ONLY:
			if profile.faction != PlayerProfile.Faction.SCAV:
				return _no("apenas SCAV")
	if required_item != "" and not profile.has_item(required_item):
		return _no("precisa %s" % required_item)
	match kind:
		Kind.PAID:
			if not profile.can_afford(paid_cost):
				return _no("saldo insuficiente (%d)" % paid_cost)
		Kind.FLARE:
			if not _flare_active:
				return _no("sinalizador ausente")
		Kind.LEVER:
			if not _lever_pulled:
				return _no("alavanca nao puxada")
		Kind.COOP:
			if not _has_ally_inside():
				return _no("precisa de aliado")
		Kind.TIMED:
			if not in_window():
				return _no("fora da janela")
	return {"ok": true, "reason": ""}

func is_open() -> bool:
	return can_use().get("ok", false)

func in_window() -> bool:
	if kind != Kind.TIMED:
		return true
	var t: float = raid.elapsed if raid != null else 0.0
	if timed_close > 0.0 and t > timed_close:
		return false
	return t >= timed_open

func progress_ratio() -> float:
	var need: float = maxf(extract_time, 0.01)
	return clampf(_progress / need, 0.0, 1.0)

func kind_name() -> String:
	match kind:
		Kind.INSTANT: return "INSTANT"
		Kind.PAID: return "PAID"
		Kind.FLARE: return "FLARE"
		Kind.LEVER: return "LEVER"
		Kind.COOP: return "COOP"
		Kind.TIMED: return "TIMED"
	return "?"

## HUD one-liner: name, kind, gate status.
func status_text() -> String:
	var res: Dictionary = can_use()
	var state: String = "ABERTA" if res.get("ok", false) else String(res.get("reason", "?"))
	return "%s [%s] %s" % [display_name, kind_name(), state]

# ─── ACTIONS ───

## Completes the extraction if every gate passes; charges/consumes there.
func attempt_extract() -> bool:
	var res: Dictionary = can_use()
	if not res.get("ok", false):
		return false
	if kind == Kind.PAID and not profile.spend(paid_cost):
		return false
	if required_item != "" and not profile.consume_item(required_item):
		return false
	_completed = true
	_progress = 0.0
	extracted.emit(self)
	state_changed.emit(self)
	return true

func pull_lever() -> void:
	if kind != Kind.LEVER or _lever_pulled:
		return
	_lever_pulled = true
	state_changed.emit(self)

func activate_flare() -> bool:
	if kind != Kind.FLARE:
		return false
	if not profile.has_item(required_item if required_item != "" else "flare"):
		return false
	_flare_active = true
	state_changed.emit(self)
	return true

## E-press from the arena. Only LEVER/FLARE react.
func interact(_who: Node) -> bool:
	if kind == Kind.LEVER:
		pull_lever()
		return true
	if kind == Kind.FLARE:
		return activate_flare()
	return false

func cancel() -> void:
	if _progress > 0.0:
		_progress = 0.0
		cancelled.emit(self)

# ─── PRESENCE / PROGRESS ───

func _on_body_entered(body: Node) -> void:
	if _bodies.has(body):
		return
	_bodies.append(body)
	if body is PlayerController:
		_players_inside += 1
		if _players_inside == 1:
			player_entered.emit(self)

func _on_body_exited(body: Node) -> void:
	_bodies.erase(body)
	if body is PlayerController:
		_players_inside = maxi(0, _players_inside - 1)
		if _players_inside == 0:
			cancel()
			player_left.emit(self)

func _physics_process(delta: float) -> void:
	if _completed or _players_inside <= 0:
		return
	if raid == null or not raid.is_active():
		return
	if not can_use().get("ok", false):
		cancel()
		return
	_progress += delta
	progress_changed.emit(self, progress_ratio())
	if _progress >= maxf(extract_time, 0.0):
		attempt_extract()

func _has_ally_inside() -> bool:
	for b in _bodies:
		if b is NpcBot:
			if int(b.get_meta("team", -1)) == (profile.team if profile != null else -1):
				return true
	return false

func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
