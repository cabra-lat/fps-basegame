extends Node3D
## Arena Fase 1 manager: playable loop on the blockout arena.
## Spawns the player + N player-rig NpcBots (signal died(bot), method
## range_hit) with patrol waypoints. Connector also accepts
## Health.player_died / target_down fallbacks. Controls: WASD move,
## mouse aim (click captures), LMB fire, R reload, 1/2 switch weapon,
## G drop, E pick up loot, Esc pause.
## Hit-detect is deferred from cartridge_fired into a _pending_shots
## queue drained in _physics_process (AGENTS.md rule 4). Slot/drop/pickup
## intents queue the same way; raycasts never leave _physics_process.

const SHOT_RANGE := 300.0
const MAG_SIZE := 10
const SEC_MAG_SIZE := 10
const LOOT_RANGE := 2.8
const SWITCH_S := 0.35
const BOT_COUNT := 3
const PLAYER_ID := 0
const NO_KILLER := -1
const KILL_EXP := 100
const LOOT_EXP := 50
const RAID_DURATION := 600.0 # RAID-1 bounded first-clear run (10 minutes)

const SLOT_ORDER: Array[String] = ["primary", "secondary"]
const INVENTORY_PANEL_CHROME := 64.0
const BotScene: PackedScene = preload("res://src/npcs/bot/bot.tscn")

const ArenaSpawnSolverScript = preload("./arena_spawn_solver.gd")
const ArenaResultAdapterScript = preload("./arena_result_adapter.gd")
const Raid1ScenarioScript = preload("./raid1_scenario.gd")

@onready var ammo_template: Ammo = preload("res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres")
@onready var weapon_template: Weapon = preload("res://resources/weapons/M4_Carbine.tres")
@onready var sec_ammo_template: Ammo = preload("res://resources/ammo/7_62_39mm_PS_GOST_BR4.tres")
@onready var sec_weapon_template: Weapon = preload("res://resources/weapons/AK_47.tres")
@onready var player: PlayerController = $Player

## Match rules. Leave null to use the SettingsStore choice (default FFA);
## assign in the inspector or via code to test another mode.
@export var game_mode: GameMode

var weapon: Weapon # active weapon (mirrors controller.current_weapon)
var active_slot := "primary"
var plate_mat: BallisticMaterial
var audio: GameAudio
var gunsmith: GunsmithUI
var raid: Raid
var scenario: RefCounted
var profile: PlayerProfile
var factions: FactionRegistry
var meta: MetaService
var _meta_summary := ""
var deaths := 0 # player deaths (respawn UX); match score lives in game_mode
var shots := 0
var _player_team := 0
var _match_over := false
var _raid_over := false
var _footsteps := Footsteps.new()
var _spawn_solver := ArenaSpawnSolverScript.new()
var _result_adapter := ArenaResultAdapterScript.new()
var _loot_corpse: NpcBot = null
var _inventory_hidden_chrome: Array[Node] = []
var _switch_cd := 0.0
var _intents: Array = [] # [kind, arg] consumed in _physics_process
var _weapon_kit := {} # Weapon -> [weapon_template, ammo_template, mag_n]

var _pending_shots: Array = []
var _bot_seq := 0

var top_label: Label
var feed_labels: Array[Label] = []
var center_label: Label
var death_label: Label
var extract_label: Label
var raid_label: Label
var result_panel: PanelContainer
var result_label: Label
var back_btn: Button
var market_panel: PanelContainer
var market_title: Label
var market_rows: VBoxContainer
var market_msg: Label
var _market_close_btn: Button
var _pause_buttons: Array[Button] = []
var _market_open := false
var _market_trader := ""
var flash_rect: ColorRect
var dir_marker: ColorRect
var pause_panel: PanelContainer
var _feed: Array[String] = []
var _hud_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	plate_mat = BallisticMaterial.new()
	plate_mat.name = "Arena Blockout"
	plate_mat.type = BallisticMaterial.Type.METAL_MEDIUM
	plate_mat.hardness = 300.0
	ViewSetup.configure_fps(player)
	call("_equip_loadout", )
	player.insert_ammo_feed.connect(Callable(self, "_on_reserve_mag"))
	call("_connect_player_health", )
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.start_ambient()
	if not player.reloaded.is_connected(_on_player_reloaded):
		player.reloaded.connect(_on_player_reloaded)
	gunsmith = GunsmithUI.new()
	gunsmith.name = "GunsmithUI"
	add_child(gunsmith)
	gunsmith.bind(audio)
	# Primary entry (player-rig hook): inventory -> click weapon -> Modificar.
	if not player.weapon_modify_requested.is_connected(Callable(self, "_on_weapon_modify_requested")):
		player.weapon_modify_requested.connect(Callable(self, "_on_weapon_modify_requested"))
	if player.inventory_ui != null:
		if not player.inventory_ui.inventory_closed.is_connected(Callable(self, "_on_inventory_closed")):
			player.inventory_ui.inventory_closed.connect(Callable(self, "_on_inventory_closed"))
		if not player.inventory_ui.visibility_changed.is_connected(Callable(self, "_on_inventory_visibility_changed")):
			player.inventory_ui.visibility_changed.connect(Callable(self, "_on_inventory_visibility_changed"))
	call("_apply_settings", )
	_setup_game_mode()
	call("_build_hud", )
	call("_build_pause", )
	_setup_raid()
	call("_spawn_bots", )
	_spawn_medical_pickups()
	_spawn_raid1_objective()
	call("_push_feed", "%s — %d bots" % [game_mode.mode_name, BOT_COUNT])
	call("_refresh_top", "WASD - 1/2 troca arma - G drop - E pega - H medico - R reload - Esc pausa")
	if OS.is_debug_build(): print("ARENA READY: %s + %s, mode=%s teams=%d, bots=%d, raid=%.0fs extracts=%d, ray_excludes=%d" % [call("_slot_weapon", "primary").name if call("_slot_weapon", "primary") else "none", call("_slot_weapon", "secondary").name if call("_slot_weapon", "secondary") else "none", game_mode.mode_name, game_mode.team_count, get_tree().get_nodes_in_group("bots").size(), RAID_DURATION, get_tree().get_nodes_in_group("extraction_points").size(), call("_shot_excludes", ).size()])


func _disconnect_signal(signal_ref: Signal, method_name: String) -> void:
	var callback := Callable(self, method_name)
	if signal_ref.is_connected(callback):
		signal_ref.disconnect(callback)


func _exit_tree() -> void:
	if player == null:
		return
	_disconnect_signal(player.insert_ammo_feed, "_on_reserve_mag")
	_disconnect_signal(player.reloaded, "_on_player_reloaded")
	_disconnect_signal(player.weapon_modify_requested, "_on_weapon_modify_requested")
	if player.inventory_ui != null:
		_disconnect_signal(player.inventory_ui.inventory_closed, "_on_inventory_closed")
		_disconnect_signal(player.inventory_ui.visibility_changed, "_on_inventory_visibility_changed")
	if meta != null:
		_disconnect_signal(meta.report_ready, "_on_meta_report")
	if raid != null:
		_disconnect_signal(raid.raid_started, "_on_raid_started")
		_disconnect_signal(raid.raid_ended, "_on_raid_ended")
		_disconnect_signal(raid.exp_gained, "_on_exp_gained")
		_disconnect_signal(raid.player_extracted, "_on_player_extracted")
	for node in get_tree().get_nodes_in_group("extraction_points"):
		if node is ExtractionPoint:
			var point := node as ExtractionPoint
			_disconnect_signal(point.player_entered, "_on_extract_enter")
			_disconnect_signal(point.player_left, "_on_extract_leave")
			_disconnect_signal(point.progress_changed, "_on_extract_progress")
			_disconnect_signal(point.extracted, "_on_extracted")
			_disconnect_signal(point.cancelled, "_on_extract_cancelled")
	for node in get_tree().get_nodes_in_group("traders"):
		if node is TraderPoint:
			_disconnect_signal((node as TraderPoint).requested, "_open_market")

## Pick the mode (exported wins; else SettingsStore) and inject spawn points.
func _setup_game_mode() -> void:
	if game_mode == null:
		var choice := String(SettingsStore.load_all().get("match_mode", "ffa"))
		game_mode = TDMMode.new() if choice == "tdm" else FFAMode.new()
	game_mode.setup(call("_spawn_points", ))
	_spawn_solver.begin_round()
	_player_team = game_mode.assign_team(PLAYER_ID)

## World medical loot (Fase: medical items). Player-rig's kit covers the
## starter; these are real world pickups proving the medical loot path.
func _spawn_medical_pickups() -> void:
	_spawn_medical_loot("bandage", Vector3(3.0, 1.0, 34.0))
	_spawn_medical_loot("splint", Vector3(-7.0, 1.0, 30.0))
	_spawn_medical_loot("water", Vector3(8.0, 1.0, 6.0))

func _configure_raid1_extractions() -> Array[ExtractionPoint]:
	var fallback: ExtractionPoint = null
	var gated: ExtractionPoint = null
	if get_tree() == null:
		return []
	for node in get_tree().get_nodes_in_group("extraction_points"):
		if not node is ExtractionPoint:
			continue
		var point := node as ExtractionPoint
		if point.name == "ExtractInstant" and fallback == null:
			fallback = point
		elif point.name == "ExtractTimed" and gated == null:
			gated = point
		else:
			# Keep authored nodes for diagnostics, but do not expose extra
			# destinations in the bounded first-clear slice.
			point.monitoring = false
			point.visible = false
			point.remove_from_group("extraction_points")
	if fallback == null or gated == null:
		push_error("RAID-1 requires ExtractInstant and ExtractTimed extraction points")
		return []
	fallback.display_name = "Open Lane"
	fallback.kind = ExtractionPoint.Kind.INSTANT
	fallback.required_item = ""
	fallback.extract_time = 0.0
	gated.display_name = "Signal Gate"
	gated.kind = ExtractionPoint.Kind.TIMED
	gated.required_item = Raid1ScenarioScript.OBJECTIVE_ID
	gated.timed_open = 120.0
	gated.timed_close = 540.0
	gated.extract_time = 3.0
	var configured: Array[ExtractionPoint] = [fallback, gated]
	return configured

func _spawn_raid1_objective() -> void:
	var intel := load("res://resources/raid1/marked_intel.tres") as Item
	if intel == null:
		push_warning("RAID-1: marked intel resource missing")
		return
	var loot := Item3D.create_from_data(intel, Vector3.ZERO)
	loot.name = "Loot_MarkedIntel"
	loot.set_meta("raid1_objective", true)
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.2, 0.25)
	var collision := CollisionShape3D.new()
	collision.shape = box
	loot.add_child(collision)
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.15, 1.0)
	mi.material_override = mat
	loot.add_child(mi)
	add_child(loot)
	loot.attractors.clear()
	loot.collision_layer = 1
	loot.collision_mask = 1
	loot.global_position = Vector3(0.0, 1.0, 2.0)
	loot.add_to_group("loot")

func _spawn_medical_loot(key: String, pos: Vector3) -> void:
	var path: String = MedicalKit.PATHS.get(key, "")
	if path == "":
		return
	var med := load(path) as MedicalItem
	if med == null:
		push_warning("ARENA: medical resource missing: %s" % path)
		return
	var loot := Item3D.create_from_data(med, Vector3.ZERO)
	loot.name = "Loot_med_%s" % key
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.2, 0.25)
	var cs := CollisionShape3D.new()
	cs.shape = box
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.3, 1)
	mat.roughness = 0.7
	mi.material_override = mat
	loot.add_child(cs)
	loot.add_child(mi)
	add_child(loot)
	loot.attractors.clear() # never spring-simulate world loot
	loot.collision_layer = 1 # hittable by the pickup ray
	loot.collision_mask = 1 # rests on the WorldBoundary floor
	loot.linear_damp = 0.6
	loot.angular_damp = 1.5
	loot.global_position = pos
	loot.add_to_group("loot")
	loot.set_meta("medical_key", key)

# ─── raid loop + extraction (Fase 1) ───

func _setup_raid() -> void:
	# Single authority for the profile: the `Meta` autoload (project.godot).
	# It owns persistence + progression; the arena only consumes and reports.
	if get_tree() == null:
		return
	meta = _ensure_meta()
	if meta == null:
		# _ensure_meta returns null when it is not in the tree; abort rather than
		# dereference it on the next line.
		return
	if meta.profile == null:
		meta.use_profile(MetaProfile.new())
	profile = meta.profile
	profile.team = _player_team
	# Faction pack (content, not an enum). A profile id the pack does not know,
	# or an NPC-only one, is an error in the data — report it, never mask it.
	factions = FactionRegistry.default_registry()
	profile.validate_faction(factions)
	raid = Raid.new()
	raid.name = "Raid"
	raid.duration = RAID_DURATION
	add_child(raid)
	# Bind meta BEFORE the manager's own handler so the resolution (stash /
	# currency / EXP) lands before the result banner is built.
	meta.bind_carrier(player.equipment, player.get_equipped_backpack())
	meta.bind_raid(raid)
	if not _prepare_raid_or_abort():
		return
	var prog := meta.enable_progression()
	prog.bind_raid(raid)
	prog.bind_player(player, PLAYER_ID)
	if not meta.report_ready.is_connected(_on_meta_report):
		meta.report_ready.connect(_on_meta_report)
	raid.raid_started.connect(_on_raid_started)
	raid.raid_ended.connect(_on_raid_ended)
	raid.exp_gained.connect(_on_exp_gained)
	if not raid.player_extracted.is_connected(_on_player_extracted):
		raid.player_extracted.connect(_on_player_extracted)
	var scenario_points: Array[ExtractionPoint] = _configure_raid1_extractions()
	# Callee can return empty when it is not in the tree; the size check below
	# then aborts the raid rather than indexing an empty array.
	if scenario_points.size() != 2:
		raid.end(Raid.Outcome.LEFT_BEHIND)
		return
	for point in get_tree().get_nodes_in_group("extraction_points"):
		if point is ExtractionPoint:
			var ep := point as ExtractionPoint
			ep.bind(profile, raid, factions)
			ep.player_entered.connect(_on_extract_enter)
			ep.player_left.connect(_on_extract_leave)
			ep.progress_changed.connect(_on_extract_progress)
			ep.extracted.connect(_on_extracted)
			if not ep.cancelled.is_connected(_on_extract_cancelled):
				ep.cancelled.connect(_on_extract_cancelled)
	scenario = Raid1ScenarioScript.new()
	scenario.begin(raid, profile, scenario_points[0], scenario_points[1])
	raid.begin()
	_refresh_raid_hud()
	# Traders: reachable markers open the market panel; Meta owns the economy.
	for t in get_tree().get_nodes_in_group("traders"):
		if t is TraderPoint and not (t as TraderPoint).requested.is_connected(Callable(self, "_open_market")):
			(t as TraderPoint).requested.connect(Callable(self, "_open_market"))

## The autoload is the authority; a local fallback keeps standalone/headless
## scenes working if the autoload was not registered.
func _ensure_meta() -> MetaService:
	var m := get_node_or_null("/root/Meta") as MetaService
	if m == null:
		var tree := get_tree()
		if tree == null:
			return null
		m = MetaService.new()
		m.name = "Meta"
		tree.root.add_child(m)
	return m

func _prepare_raid_or_abort() -> bool:
	var result: Dictionary = meta.prepare_raid_checked()
	if bool(result.get("ok", false)):
		return true
	var reason := String(result.get("reason", "prepare_raid failed"))
	push_error("RAID-1 prepare aborted: %s" % reason)
	_raid_over = true
	return false


func _on_player_reloaded(_player: PlayerController) -> void:
	audio.play_reload()


func _on_player_extracted(_point: Node) -> void:
	call("_push_feed", "Extraído — saiu da raid")


func _on_extract_cancelled(_point: ExtractionPoint) -> void:
	call("_set_center", "extraction cancelada")


func _on_meta_report(summary: String) -> void:
	_meta_summary = summary
	if result_panel != null and result_panel.visible:
		_apply_result_text()

func _quest_line() -> String:
	if meta == null or meta.progression == null or meta.profile == null:
		return ""
	var lines: Array = meta.profile.quests.progress_text()
	if lines.is_empty():
		return ""
	return String(lines[0])

func _apply_result_text() -> void:
	if result_label == null:
		return
	var extra := _meta_summary
	var q := _quest_line()
	if q != "":
		extra = ("%s\n%s" % [extra, q]) if extra != "" else q
	result_label.text = "%s\nEXP %d%s" % [raid.outcome_name(), raid.exp, ("\n" + extra) if extra != "" else ""]


func _on_raid_started() -> void:
	_raid_over = false
	if result_panel:
		result_panel.visible = false
	if raid_label:
		raid_label.visible = true
	call("_push_feed", "Raid iniciou — %s" % raid.time_text())

func _on_raid_ended(outcome: int) -> void:
	if scenario != null and outcome != Raid.Outcome.SURVIVED and outcome != Raid.Outcome.RUN_THROUGH and outcome != Raid.Outcome.SCENARIO_CLEARED and scenario.state == Raid1ScenarioScript.State.ACTIVE:
		scenario.fail(raid.outcome_name(outcome))
		scenario.discard_carry(_raid1_backpack())
	_raid_over = true
	var out_name: String = raid.outcome_name(outcome)
	if audio:
		audio.play_ui()
	call("_show_result", out_name, raid.exp)
	call("_push_feed", "Raid terminou: %s" % out_name)
	if OS.is_debug_build(): print("RAID ENDED: outcome=%s exp=%d elapsed=%.1f" % [out_name, raid.exp, raid.elapsed])

func _raid1_backpack() -> InventoryContainer:
	return player.get_equipped_backpack() if player != null else null


func _on_exp_gained(amount: int) -> void:
	if amount > 0:
		_refresh_raid_hud()

func _on_extract_enter(point: ExtractionPoint) -> void:
	raid.zone_enter(point)
	call("_set_center", "Entrando em %s" % point.display_name)

func _on_extract_leave(point: ExtractionPoint) -> void:
	raid.zone_leave(point)

func _on_extract_progress(point: ExtractionPoint, _ratio: float) -> void:
	if extract_label:
		extract_label.text = "Extraindo em %s... %d/%ds" % [point.display_name, int(point._progress), int(point.extract_time)]

func _on_extracted(point: ExtractionPoint) -> void:
	if scenario != null and not scenario.objective_collected:
		# The fallback is physically open, but leaving without the marked intel is
		# a failed first clear: the existing meta resolution then forfeits kit.
		scenario.fail(tr("marked intel not extracted"))
		scenario.discard_carry(_raid1_backpack())
		raid.end(Raid.Outcome.LEFT_BEHIND)
		call("_push_feed", tr("Failure: intel not collected — kit lost"))
		return
	var out: int
	if scenario != null:
		scenario.prepare_success_carried(_raid1_backpack())
		scenario.complete(point)
		out = raid.complete_scenario(point)
	else:
		out = raid.extract(point)
	call("_push_feed", "Extraído por %s [%s]" % [point.display_name, raid.outcome_name(out)])

## Rebuild the raid portion of the HUD (timer, extractions, coin, EXP).
func _refresh_raid_hud() -> void:
	if raid_label == null or raid == null:
		return
	var scenario_line := ""
	if scenario != null:
		scenario_line = scenario.status_text()
	raid_label.text = "RAID1 %s  |  %s  |  EXP %d  |  %d cr  |  %s" % [raid.time_text(), profile.faction_name(factions), raid.exp, profile.currency, scenario_line]
	# Faction colour is data too: the HUD tints the name, the pack defines the hue.
	raid_label.add_theme_color_override("font_color", profile.faction_color(factions))
	if extract_label:
		extract_label.text = point_list_text()

func point_list_text() -> String:
	var parts: Array[String] = []
	if get_tree() == null:
		return ""
	for point in get_tree().get_nodes_in_group("extraction_points"):
		if point is ExtractionPoint:
			parts.append((point as ExtractionPoint).status_text())
	return "   ".join(parts)

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if scenario != null and scenario.tick(delta) and raid != null and not _raid_over:
		scenario.discard_carry(player.get_equipped_backpack())
		raid.end(Raid.Outcome.MIA)
	call("_tick_corpse_loot", )
	# While the gunsmith or inventory is open the player is busy working: drop
	# combat input (the raid keeps running — you are vulnerable), then keep the
	# sim ticking.
	if (gunsmith != null and gunsmith.is_open()) or call("_inventory_open", ):
		_pending_shots.clear()
		_intents.clear()
	# Skill rule: physics queries live in _physics_process, never _process.
	for pending in _pending_shots:
		call("_resolve_shot", pending[0], pending[1])
	_pending_shots.clear()
	_consume_intents()
	if _switch_cd > 0.0:
		_switch_cd = move_toward(_switch_cd, 0.0, delta)
	_footsteps.tick(audio, player, delta)
	if not _match_over:
		game_mode.tick(delta)
		call("_check_match_over", )
	# HUD rebuilds at ~10 Hz instead of every physics tick (P0 perf); event
	# paths (_set_center, feeds) still refresh immediately.
	_hud_t += delta
	if _hud_t >= 0.1:
		_hud_t = 0.0
		call("_refresh_top", "")
		_refresh_raid_hud()

func _input(event: InputEvent) -> void:
	# PlayerController closes its inventory from _unhandled_input. The arena is
	# the parent and may receive the same Esc afterwards, so close here and mark
	# it handled BEFORE child unhandled handlers can turn it into a pause toggle.
	if call("_inventory_open", ) and event.is_action_pressed("ui_cancel"):
		call("_close_inventory", )
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if gunsmith != null and gunsmith.is_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("mod_weapon"):
			gunsmith.close()
		return
	if call("_inventory_open", ):
		if event.is_action_pressed("ui_cancel"):
			call("_close_inventory", )
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _market_open:
			call("_close_market", )
		else:
			call("_toggle_pause", )
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("weapon_slot1"):
		_intents.append(["slot", "primary"])
	elif event.is_action_pressed("weapon_slot2"):
		_intents.append(["slot", "secondary"])
	elif event.is_action_pressed("weapon_slot3"):
		_intents.append(["slot", "secondary"]) # sidearm vive no secondary
	elif event.is_action_pressed("weapon_drop"):
		_intents.append(["drop", ""])
	elif event.is_action_pressed("interact"):
		_intents.append(["interact", ""])

func _consume_intents() -> void:
	for intent in _intents:
		match intent[0]:
			"slot":
				call("_activate_slot", intent[1])
			"drop":
				call("_drop_active", )
			"interact":
				call("_try_pickup", )
	_intents.clear()
