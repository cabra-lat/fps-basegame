class_name ExtractionPoint
extends Area3D
## Extraction zone with real genre-typical gates (Fase 1).
##
## Presence-based: while a player stands inside, progress accumulates on the
## physics clock; leaving cancels it. All rules are checked through can_use()
## so the HUD and the harness see the exact same verdict.

enum Kind { INSTANT, PAID, FLARE, LEVER, COOP, TIMED }

@export var display_name: String = "EXTRACT"
## Faction ids allowed to use this point; EMPTY = any faction. Ids come from the
## faction pack (`FactionRegistry`), so a game with 1 or 10 factions needs no
## code change here — the gate is a data list, not an enum of two.
@export var allowed_factions: Array[String] = []
@export var kind: Kind = Kind.INSTANT
@export var extract_time: float = 0.0 ## seconds held inside (INSTANT = 0)
@export var single_use: bool = false
@export var required_item: String = "" ## item_id gating the point (note/key)
@export var required_item_name: String = "" ## optional display override; empty resolves the id through ItemNames
@export var paid_cost: int = 0 ## paid extract: credits charged on completion
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
## Faction pack used to mount the gate text. Falls back to the shared pack.
var factions: FactionRegistry

var _bodies: Array[Node] = []
var _players_inside := 0
var _progress := 0.0
var _completed := false
var _lever_pulled := false
var _flare_active := false

func bind(p_profile: PlayerProfile, p_raid: Raid, p_factions: FactionRegistry = null) -> void:
	profile = p_profile
	raid = p_raid
	factions = p_factions

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
	if not allowed_factions.is_empty() and not allowed_factions.has(profile.faction):
		return _no(faction_gate_text())
	if required_item != "" and not profile.has_item(required_item):
		return _no(tr("requires %s") % _required_item_display())
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

## "apenas <names>" mounted from the pack; "" when the point takes anyone.
func faction_gate_text() -> String:
	if allowed_factions.is_empty():
		return ""
	var reg := factions if factions != null else FactionRegistry.default_registry()
	var names: Array[String] = []
	for id in allowed_factions:
		names.append(reg.display_name(id))
	return "apenas %s" % ", ".join(PackedStringArray(names))


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

## Player-facing name for the item gate. `required_item` is a machine key (it is
## what has_item/consume_item compare against), so it must never be interpolated
## into a HUD string: the id is resolved through the ItemNames registry, which
## maps it to a tr() key, and the generic fallback keeps an unknown id out of
## the UI instead of leaking it.
func _required_item_display() -> String:
	if required_item_name != "":
		return required_item_name
	var resolved := ItemNames.display_name(required_item)
	if resolved == "":
		if OS.is_debug_build():
			push_warning("ExtractionPoint '%s': required_item '%s' has no ItemNames entry" % [name, required_item])
		return tr("a specific item")
	return resolved


## Localized display text for the point list. The `Kind` enum stays the
## machine-readable key (scenes and quests match on it), so only this text is
## translated; the gate reasons in can_use() are already Portuguese and the two
## strings are read on the same HUD line. Static, so keys resolve through
## TranslationServer rather than the instance-bound tr().
static func kind_display_name(k: Kind) -> String:
	match k:
		Kind.INSTANT: return TranslationServer.translate("INSTANT")
		Kind.PAID: return TranslationServer.translate("PAID")
		Kind.FLARE: return TranslationServer.translate("FLARE")
		Kind.LEVER: return TranslationServer.translate("LEVER")
		Kind.COOP: return TranslationServer.translate("COOP")
		Kind.TIMED: return TranslationServer.translate("TIMED")
	return "?"


## Instance convenience wrapper: this point's kind.
func kind_name() -> String:
	return kind_display_name(kind)

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
