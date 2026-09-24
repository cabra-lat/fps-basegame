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
const RAID_DURATION := 2100.0 # 35 min, genre-typical long raid

const SLOT_ORDER: Array[String] = ["primary", "secondary"]
const INVENTORY_PANEL_CHROME := 64.0
const BotScene: PackedScene = preload("res://src/npcs/bot/bot.tscn")

const ArenaSpawnSolverScript = preload("./arena_spawn_solver.gd")
const ArenaResultAdapterScript = preload("./arena_result_adapter.gd")

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
	_equip_loadout()
	player.insert_ammo_feed.connect(_on_reserve_mag)
	_connect_player_health()
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.start_ambient()
	player.reloaded.connect(func(_p: PlayerController) -> void: audio.play_reload())
	gunsmith = GunsmithUI.new()
	gunsmith.name = "GunsmithUI"
	add_child(gunsmith)
	gunsmith.bind(audio)
	# Primary entry (player-rig hook): inventory -> click weapon -> Modificar.
	if not player.weapon_modify_requested.is_connected(_on_weapon_modify_requested):
		player.weapon_modify_requested.connect(_on_weapon_modify_requested)
	if player.inventory_ui != null:
		if not player.inventory_ui.inventory_closed.is_connected(_on_inventory_closed):
			player.inventory_ui.inventory_closed.connect(_on_inventory_closed)
		if not player.inventory_ui.visibility_changed.is_connected(_on_inventory_visibility_changed):
			player.inventory_ui.visibility_changed.connect(_on_inventory_visibility_changed)
	_apply_settings()
	_setup_game_mode()
	_build_hud()
	_build_pause()
	_setup_raid()
	_spawn_bots()
	_spawn_medical_pickups()
	_push_feed("%s — %d bots" % [game_mode.mode_name, BOT_COUNT])
	_refresh_top("WASD - 1/2 troca arma - G drop - E pega - H medico - R reload - Esc pausa")
	if OS.is_debug_build(): print("ARENA READY: %s + %s, mode=%s teams=%d, bots=%d, raid=%.0fs extracts=%d, ray_excludes=%d" % [_slot_weapon("primary").name if _slot_weapon("primary") else "none", _slot_weapon("secondary").name if _slot_weapon("secondary") else "none", game_mode.mode_name, game_mode.team_count, get_tree().get_nodes_in_group("bots").size(), RAID_DURATION, get_tree().get_nodes_in_group("extraction_points").size(), _shot_excludes().size()])

## Pick the mode (exported wins; else SettingsStore) and inject spawn points.
func _setup_game_mode() -> void:
	if game_mode == null:
		var choice := String(SettingsStore.load_all().get("match_mode", "ffa"))
		game_mode = TDMMode.new() if choice == "tdm" else FFAMode.new()
	game_mode.setup(_spawn_points())
	_spawn_solver.begin_round()
	_player_team = game_mode.assign_team(PLAYER_ID)

## World medical loot (Fase: medical items). Player-rig's kit covers the
## starter; these are real world pickups proving the medical loot path.
func _spawn_medical_pickups() -> void:
	_spawn_medical_loot("bandage", Vector3(3.0, 1.0, 34.0))
	_spawn_medical_loot("splint", Vector3(-7.0, 1.0, 30.0))
	_spawn_medical_loot("water", Vector3(8.0, 1.0, 6.0))

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
	meta = _ensure_meta()
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
	meta.prepare_raid()
	var prog := meta.enable_progression()
	prog.bind_raid(raid)
	prog.bind_player(player, PLAYER_ID)
	if not meta.report_ready.is_connected(_on_meta_report):
		meta.report_ready.connect(_on_meta_report)
	raid.raid_started.connect(_on_raid_started)
	raid.raid_ended.connect(_on_raid_ended)
	raid.exp_gained.connect(_on_exp_gained)
	raid.player_extracted.connect(func(_point: Node) -> void: _push_feed("Extraído — saiu da raid"))
	for point in get_tree().get_nodes_in_group("extraction_points"):
		if point is ExtractionPoint:
			var ep := point as ExtractionPoint
			ep.bind(profile, raid, factions)
			ep.player_entered.connect(_on_extract_enter)
			ep.player_left.connect(_on_extract_leave)
			ep.progress_changed.connect(_on_extract_progress)
			ep.extracted.connect(_on_extracted)
			ep.cancelled.connect(func(p: ExtractionPoint) -> void: _set_center("extraction cancelada"))
	raid.begin()
	_refresh_raid_hud()
	# Traders: reachable markers open the market panel; Meta owns the economy.
	for t in get_tree().get_nodes_in_group("traders"):
		if t is TraderPoint and not (t as TraderPoint).requested.is_connected(_open_market):
			(t as TraderPoint).requested.connect(_open_market)

## The autoload is the authority; a local fallback keeps standalone/headless
## scenes working if the autoload was not registered.
func _ensure_meta() -> MetaService:
	var m := get_node_or_null("/root/Meta") as MetaService
	if m == null:
		m = MetaService.new()
		m.name = "Meta"
		get_tree().root.add_child(m)
	return m

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
	_push_feed("Raid iniciou — %s" % raid.time_text())

func _on_raid_ended(outcome: int) -> void:
	_raid_over = true
	var out_name: String = raid.outcome_name(outcome)
	if audio:
		audio.play_ui()
	_show_result(out_name, raid.exp)
	_push_feed("Raid terminou: %s" % out_name)
	if OS.is_debug_build(): print("RAID ENDED: outcome=%s exp=%d elapsed=%.1f" % [out_name, raid.exp, raid.elapsed])

func _on_exp_gained(amount: int) -> void:
	if amount > 0:
		_refresh_raid_hud()

func _on_extract_enter(point: ExtractionPoint) -> void:
	raid.zone_enter(point)
	_set_center("Entrando em %s" % point.display_name)

func _on_extract_leave(point: ExtractionPoint) -> void:
	raid.zone_leave(point)

func _on_extract_progress(point: ExtractionPoint, _ratio: float) -> void:
	if extract_label:
		extract_label.text = "Extraindo em %s... %d/%ds" % [point.display_name, int(point._progress), int(point.extract_time)]

func _on_extracted(point: ExtractionPoint) -> void:
	var out: int = raid.extract(point)
	_push_feed("Extraído por %s [%s]" % [point.display_name, raid.outcome_name(out)])

## Rebuild the raid portion of the HUD (timer, extractions, coin, EXP).
func _refresh_raid_hud() -> void:
	if raid_label == null or raid == null:
		return
	raid_label.text = "RAID %s  |  %s  |  EXP %d  |  %d cr" % [raid.time_text(), profile.faction_name(factions), raid.exp, profile.currency]
	# Faction colour is data too: the HUD tints the name, the pack defines the hue.
	raid_label.add_theme_color_override("font_color", profile.faction_color(factions))
	if extract_label:
		extract_label.text = point_list_text()

func point_list_text() -> String:
	var parts: Array[String] = []
	for point in get_tree().get_nodes_in_group("extraction_points"):
		if point is ExtractionPoint:
			parts.append((point as ExtractionPoint).status_text())
	return "   ".join(parts)

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_tick_corpse_loot()
	# While the gunsmith or inventory is open the player is busy working: drop
	# combat input (the raid keeps running — you are vulnerable), then keep the
	# sim ticking.
	if (gunsmith != null and gunsmith.is_open()) or _inventory_open():
		_pending_shots.clear()
		_intents.clear()
	# Skill rule: physics queries live in _physics_process, never _process.
	for pending in _pending_shots:
		_resolve_shot(pending[0], pending[1])
	_pending_shots.clear()
	_consume_intents()
	if _switch_cd > 0.0:
		_switch_cd = move_toward(_switch_cd, 0.0, delta)
	_footsteps.tick(audio, player, delta)
	if not _match_over:
		game_mode.tick(delta)
		_check_match_over()
	# HUD rebuilds at ~10 Hz instead of every physics tick (P0 perf); event
	# paths (_set_center, feeds) still refresh immediately.
	_hud_t += delta
	if _hud_t >= 0.1:
		_hud_t = 0.0
		_refresh_top("")
		_refresh_raid_hud()

func _input(event: InputEvent) -> void:
	# PlayerController closes its inventory from _unhandled_input. The arena is
	# the parent and may receive the same Esc afterwards, so close here and mark
	# it handled BEFORE child unhandled handlers can turn it into a pause toggle.
	if _inventory_open() and event.is_action_pressed("ui_cancel"):
		_close_inventory()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if gunsmith != null and gunsmith.is_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("mod_weapon"):
			gunsmith.close()
		return
	if _inventory_open():
		if event.is_action_pressed("ui_cancel"):
			_close_inventory()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _market_open:
			_close_market()
		else:
			_toggle_pause()
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
				_activate_slot(intent[1])
			"drop":
				_drop_active()
			"interact":
				_try_pickup()
	_intents.clear()

# ─── multi-weapon loadout (public Equipment flow only) ───
# Slots primary/secondary hold one Weapon each; ammo lives on the Weapon
# resource, so it persists per weapon across switches. The controller only
# tracks the LAST equipped item, so switching unequips everything and
# re-equips with the target last (same frame: no visible flicker).

func _make_mag_for(feed_template: AmmoFeed, round_template: Ammo, n: int) -> AmmoFeed:
	var magazine = feed_template.duplicate(true)
	for i in range(n):
		var cartridge = round_template.duplicate(true)
		cartridge.name = round_template.caliber + " Round " + str(i)
		magazine.insert(cartridge)
	return magazine

func _issue(w_template: Weapon, a_template: Ammo, n: int) -> Weapon:
	var w := w_template.duplicate(true) as Weapon
	w.ammo_feed = _make_mag_for(w_template.ammo_feed, a_template, n)
	_weapon_kit[w] = [w_template, a_template, n]
	return w

func _slot_item(slot: String) -> InventoryItem:
	var items := player.equipment.get_equipped(slot)
	return items[0] if not items.is_empty() else null

func _slot_weapon(slot: String) -> Weapon:
	var item := _slot_item(slot)
	return item.extra as Weapon if item and item.extra is Weapon else null

func _track_weapon(old_w: Weapon, new_w: Weapon) -> void:
	if old_w != null:
		if old_w.cartridge_fired.is_connected(_on_cartridge_fired):
			old_w.cartridge_fired.disconnect(_on_cartridge_fired)
		if old_w.ammo_feed_empty.is_connected(_on_mag_empty):
			old_w.ammo_feed_empty.disconnect(_on_mag_empty)
		if old_w.firemode_changed.is_connected(_on_firemode_changed):
			old_w.firemode_changed.disconnect(_on_firemode_changed)
		if old_w.weapon_malfunctioned.is_connected(_on_weapon_malfunctioned):
			old_w.weapon_malfunctioned.disconnect(_on_weapon_malfunctioned)
		if old_w.malfunction_cleared.is_connected(_on_malfunction_cleared):
			old_w.malfunction_cleared.disconnect(_on_malfunction_cleared)
	weapon = new_w
	if new_w != null:
		if not new_w.cartridge_fired.is_connected(_on_cartridge_fired):
			new_w.cartridge_fired.connect(_on_cartridge_fired)
		if not new_w.ammo_feed_empty.is_connected(_on_mag_empty):
			new_w.ammo_feed_empty.connect(_on_mag_empty)
		if not new_w.firemode_changed.is_connected(_on_firemode_changed):
			new_w.firemode_changed.connect(_on_firemode_changed)
		if not new_w.weapon_malfunctioned.is_connected(_on_weapon_malfunctioned):
			new_w.weapon_malfunctioned.connect(_on_weapon_malfunctioned)
		if not new_w.malfunction_cleared.is_connected(_on_malfunction_cleared):
			new_w.malfunction_cleared.connect(_on_malfunction_cleared)

## Weapon malfunction audio cues (player-rig owns the mechanic/signals).
func _on_weapon_malfunctioned(_w: Weapon, kind: int) -> void:
	if audio != null:
		audio.play_malfunction(kind)
	_set_center("ARMA ENGASGOU (X para limpar)")

func _on_malfunction_cleared(_w: Weapon, _kind: int) -> void:
	if audio != null:
		audio.play_malfunction_cleared()
	_set_center("Arma limpa")

func _equip_loadout() -> void:
	# Full fresh loadout (ready + respawn): M4 primary, AK secondary.
	for slot in SLOT_ORDER:
		for old in player.equipment.get_equipped(slot):
			player.equipment.unequip(old, slot)
	_track_weapon(weapon, null)
	var m4 := _issue(weapon_template, ammo_template, MAG_SIZE)
	var ak := _issue(sec_weapon_template, sec_ammo_template, SEC_MAG_SIZE)
	if not player.equipment.equip(InventorySystem.create_inventory_item(ak), "secondary"):
		push_warning("ARENA: secondary equip failed")
	if not player.equipment.equip(InventorySystem.create_inventory_item(m4), "primary"):
		push_warning("ARENA: primary equip failed")
		return
	active_slot = "primary"
	_track_weapon(null, m4)
	ShotRay.register(self)
	_refresh_top("")

func _activate_slot(slot: String) -> void:
	if _switch_cd > 0.0:
		return
	var target := _slot_weapon(slot)
	if target == null:
		_set_center("slot %s vazio" % slot)
		return
	if slot == active_slot and target == weapon:
		return
	var items := {}
	for s in SLOT_ORDER:
		var it := _slot_item(s)
		if it:
			items[s] = it
			player.equipment.unequip(it, s)
	for s in SLOT_ORDER: # target LAST: controller tracks last equipped
		if s == slot:
			continue
		if items.has(s):
			player.equipment.equip(items[s], s)
	player.equipment.equip(items[slot], slot)
	_track_weapon(weapon, target)
	active_slot = slot
	# The controller owns `current_weapon`; tell it which slot is live, or it keeps
	# resolving the OLD one and the gunsmith/HUD show the previous weapon.
	player.set_active_weapon_slot(slot)
	_switch_cd = SWITCH_S # lower/raise window
	ShotRay.register(self)
	if audio:
		audio.play_reload() # metallic handling voice as raise cue
	_set_center(">> %s" % target.name)
	_refresh_top("")

func _drop_active() -> void:
	# Dropping never falls back to another slot: the gun leaves the hand and
	# its slot, nothing is auto-drawn (press 1/2 to draw the other).
	var item := _slot_item(active_slot)
	var w := _slot_weapon(active_slot)
	if item == null or w == null:
		_set_center("nada para largar")
		return
	var rounds := w.ammo_feed.capacity if w.ammo_feed else 0
	# Out of the slot; the controller's (now fixed) unequip handler frees the
	# held viewmodel because the dropped gun is the current_weapon.
	player.equipment.unequip(item, active_slot)
	_track_weapon(w, null)
	_spawn_loot(w)
	active_slot = ""
	# Nothing is drawn any more: the controller must not keep resolving the slot it
	# just dropped (this is the "gunsmith opens with the gun I threw away" bug).
	player.set_active_weapon_slot("")
	ShotRay.register(self)
	_push_feed("Largou %s (%d na mag)" % [w.name, rounds])
	_refresh_top("")

func _spawn_loot(w: Weapon) -> void:
	if w.view_model == null:
		push_warning("ARENA: dropped weapon has no view_model loot")
		return
	var loot := w.view_model.instantiate() as Weapon3D
	loot.name = "Loot_%s" % w.name
	add_child(loot)
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	loot.global_position = player.global_position + fwd.normalized() * 1.2 + Vector3.UP * 1.0
	loot.data = w # _set_data wires magazine + signals
	# The weapon scene ships layer/mask 0 (it is meant to be held): give the
	# world loot the same collision the grab path uses, or it falls through
	# the WorldBoundary floor and can never be picked back up.
	loot.collision_layer = loot.collision_layers_on_grab
	loot.collision_mask = loot.collision_mask_on_grab
	loot.contact_monitor = false # resting prop, no contact harvesting
	loot.linear_damp = 0.6
	loot.angular_damp = 1.5
	loot.add_to_group("loot")
	loot.set_meta("kit", _weapon_kit.get(w, [weapon_template, ammo_template, MAG_SIZE]))

func _try_pickup() -> void:
	# A second interact (or Esc) closes the market instead of raycasting.
	if _market_open:
		_close_market()
		return
	var cam: Camera3D = player.camera
	if cam == null:
		return
	var space := get_world_3d().direct_space_state
	var origin := cam.project_ray_origin(get_viewport().get_visible_rect().size / 2.0)
	var end := origin + cam.project_ray_normal(get_viewport().get_visible_rect().size / 2.0) * LOOT_RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = _shot_excludes() # viewmodel would block pickup too
	# CorpseHitbox is an Area3D enabled only after death. This flag belongs to
	# the pickup ray alone; ShotResolver intentionally keeps areas off so a
	# looted body never blocks bullets.
	query.collide_with_areas = true
	var result := space.intersect_ray(query)
	if result.is_empty():
		return
	# Traders / extraction levers / corpses take priority over world loot.
	var interactable := _interact_ancestor(result.collider)
	if interactable != null:
		if interactable is NpcBot:
			var corpse := interactable as NpcBot
			if not corpse.interact(player):
				_set_center("Cadáver sem itens")
			return
		if interactable is TraderPoint:
			interactable.interact(player) # emits -> _open_market
			return
		interactable.interact(player)
		_set_center("%s ativado" % interactable.display_name)
		return
	# The center ray can hit the loot's own child colliders first (a mounted
	# optic/mag is a separate CollisionObject3D on layer 4). Resolve the hit
	# up the parent chain to the loot root instead of requiring a direct hit.
	var loot := _loot_root(result.collider)
	if loot == null:
		return
	var loot_data: Resource = loot.get("data")
	if loot is Weapon3D and loot_data is Weapon:
		_pickup_weapon(loot as Weapon3D, loot_data as Weapon)
	elif loot_data is MedicalItem:
		_pickup_medical(loot, loot_data as MedicalItem)
	else:
		_set_center("nao pegavel")

func _pickup_weapon(loot: Weapon3D, w: Weapon) -> void:
	var free := ""
	for s in SLOT_ORDER:
		if _slot_weapon(s) == null:
			free = s
			break
	if free == "":
		_set_center("SLOTS CHEIOS")
		return
	if loot.has_meta("kit"):
		_weapon_kit[w] = loot.get_meta("kit")
	if player.equipment.equip(InventorySystem.create_inventory_item(w), free):
		loot.queue_free()
		_activate_slot(free)
		if raid != null:
			raid.register_loot(w)
			raid.add_exp(LOOT_EXP)
		_push_feed("Pegou %s" % w.name)
	else:
		_set_center("slot incompativel")

## Medical/consumable pickup: goes into the equipped backpack (never a weapon
## slot). Uses position (-1,-1) so the grid finds free space (ZERO collides).
func _pickup_medical(loot: Node, med: MedicalItem) -> void:
	var bag: InventoryContainer = player.get_equipped_backpack()
	if bag == null:
		_set_center("precisa de mochila")
		return
	var item: InventoryItem = InventoryItem.slurp(med)
	if item == null:
		return
	if bag.add_item(item, Vector2i(-1, -1)):
		loot.queue_free()
		if raid != null:
			raid.register_loot(med)
			raid.add_exp(LOOT_EXP)
		_push_feed("Pegou %s" % med.name)
	else:
		_set_center("mochila cheia")

## Walk up from a raycast collider to the world-loot root (any node in group
## "loot", weapon or item), so child bodies (optic/mag) don't block pickup.
func _loot_root(collider: Object) -> Node:
	var n := collider as Node
	while n != null:
		if n.is_in_group("loot"):
			return n
		n = n.get_parent()
	return null

## Back-compat wrapper for weapon-only callers/tests.
func _loot_ancestor(collider: Object) -> Weapon3D:
	var n := _loot_root(collider)
	return n as Weapon3D

## Walk up from a raycast collider to an ExtractionPoint (or any node with an
## interact() method) so lever bodies/steps don't need to be the point itself.
## Walk up from a raycast collider to an interactable (ExtractionPoint lever or
## TraderPoint) — body children don't need to carry the script.
func _interact_ancestor(collider: Object) -> Node:
	var n := collider as Node
	while n != null:
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null

func _on_firemode_changed(_w: Weapon, _mode: String) -> void:
	_refresh_top("")

func _on_cartridge_fired(fired_weapon: Weapon, round: Ammo) -> void:
	_pending_shots.append([fired_weapon, round])
	if audio:
		audio.play_shot()

## RIDs the resolver ray must never hit: player body + EVERY viewmodel body
## (held gun, attachments, and any ghost leaked on switch). See ShotRay.
## Registration happens on equip/switch/drop (and every 16th shot as a
## safety net) so the common per-shot path is just a group query.
func _shot_excludes() -> Array[RID]:
	var rescan := shots % 16 == 0
	return ShotRay.collect(player, self, rescan)

func _resolve_shot(_fired_weapon: Weapon, round: Ammo) -> void:
	shots += 1
	# Raycast + impact + hit application live in ShotResolver (shared with range).
	var r := ShotResolver.resolve(player.camera, get_world_3d(),
		get_viewport().get_visible_rect().size / 2.0, round, plate_mat,
		SHOT_RANGE, _shot_excludes())
	if not r.get("hit", false):
		_set_center("miss")
		return
	var impact: BallisticsImpact = r["impact"]
	ShotResolver.apply_hit(self, r["collider"], impact, round, r["position"], audio)
	_set_center("HIT %.0fm %.0fJ" % [r["distance"], impact.hit_energy])

func _on_mag_empty(_w: Weapon, _feed: AmmoFeed) -> void:
	_set_center("MAG EMPTY - press R")

func _on_reserve_mag(_p: PlayerController) -> void:
	if weapon == null:
		return
	var kit: Array = _weapon_kit.get(weapon, [weapon_template, ammo_template, MAG_SIZE])
	if WeaponSystem.change_magazine(weapon, _make_mag_for(kit[0].ammo_feed, kit[1], kit[2])):
		_set_center("reloaded")

# ─── settings (menu <-> arena via SettingsStore) ───

func _apply_settings() -> void:
	var s := SettingsStore.load_all()
	if player and player.config:
		player.config.mouse_sensitivity = float(s.get("sensitivity", 1.0))
	SettingsStore.apply_volumes(s)
	SettingsStore.apply_display(s)

# ─── bots (player-rig NpcBot API: signal died(bot), range_hit) ───

func _spawn_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in range(1, 5):
		var m := get_node_or_null("Spawn%d" % i) as Marker3D
		if m:
			pts.append(m.global_position)
	if pts.is_empty():
		pts = [Vector3(0, 1, -40), Vector3(-40, 1, 0), Vector3(40, 1, 0), Vector3(0, 1, 40)]
	return pts

func _spawn_bots() -> void:
	for i in range(BOT_COUNT):
		var index := _bot_seq + 1
		var team: int = game_mode.assign_team(index)
		_spawn_bot(_free_spawn(team), team)


## Thin scene adapter for the pure allocator. GameMode keeps the frozen team
## cursor; ArenaSpawnSolver owns the second-line dedup ledger and deterministic
## fallback rings. Scene-tree occupancy is sampled here.
func _free_spawn(team: int) -> Vector3:
	return _spawn_solver.allocate(team, game_mode, _spawn_points(), _spawn_occupants())


func _spawn_occupants() -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	if player != null:
		occupied.append(player.global_position)
	# Deliberately include dead bots while their corpses remain in the group.
	for bot in get_tree().get_nodes_in_group("bots"):
		if bot is Node3D:
			occupied.append((bot as Node3D).global_position)
	return occupied

func _spawn_bot(at: Vector3, team: int) -> void:
	_bot_seq += 1
	var bot := BotScene.instantiate() as NpcBot
	bot.name = "Bot%d" % _bot_seq
	bot.display_name = "Cadáver — %s" % bot.name
	# Position BEFORE add_child (npc-body's fix, applied to the arena too): adding
	# the bot first leaves it at the arena origin for the rest of the frame, and a
	# body that exists at the origin can be thrown up by the floor's depenetration
	# instead of landing on its spawn point. They proved the direction in
	# NpcWaveSpawner (2 bots at one point: 2/2 launched; positioned before
	# add_child: lands at y=0.001 - commit 6d7fce4).
	# HONEST LIMIT (measured): in the ARENA path I could not reproduce that
	# difference - the gate's mid-raid spawn passes with either order (18/18 both
	# ways), so here this is defence-in-depth, not a measured arena fix. The arena
	# root sits at the origin, so to_local() is a no-op today and stays correct if
	# the root is ever moved.
	bot.position = to_local(at)
	# Same contract as NpcWaveSpawner._spawn_one: the team has to land on the BOT,
	# not only in a meta. Without this every arena bot stayed team -1: no team
	# tint, no per-team hostility (in FFA the bots never fought each other, they
	# only ever targeted the player), no squad blackboard (it needs team >= 0) and
	# died_with_team() reported -1. `npc_id` matters too: it is the id a bot records
	# as its attacker, so without it bot-vs-bot kills cannot be attributed.
	# set_team() BEFORE add_child is safe and is what NpcWaveSpawner does: the tint
	# is applied by NpcBot._ready() (the pre-ready call bails on _rig == null).
	bot.set_team(team)
	bot.npc_id = _bot_seq
	bot.friendly_fire = game_mode.friendly_fire
	# Explicit learning-target contract: armed npc-body combat is opt-IN here.
	# 12 J is the pre-scale input; npc-body's 0.20 safety scale makes each
	# synthetic shot 2.4 J at an 18 m reach.
	bot.weapon_enabled = true
	bot.weapon_range = 18.0
	bot.attack_energy = 12.0
	add_child(bot)
	bot.set_meta("id", _bot_seq) # COOP extraction gates read this meta
	bot.set_meta("team", team)
	# Patrol the full arena; chase/attack logic lives in the bot.
	var pts := _spawn_points()
	bot.setup([pts[1], pts[2], pts[3], pts[0]])
	_connect_bot(bot)

func _connect_bot(bot: Node) -> void:
	if bot is NpcBot:
		var npc := bot as NpcBot
		if not npc.loot_requested.is_connected(_on_corpse_loot_requested):
			npc.loot_requested.connect(_on_corpse_loot_requested)
	# 1) player-rig API: signal died(bot)
	if bot.has_signal("died"):
		var died_sig := (bot as NpcBot).died as Signal
		if not died_sig.is_connected(_on_bot_died):
			died_sig.connect(_on_bot_died)
		return
	# 2) Health-based fallback: Health.player_died
	if "health" in bot:
		var h = bot.get("health")
		if h is Health and not (h as Health).player_died.is_connected(_on_bot_health_died.bind(bot)):
			(h as Health).player_died.connect(_on_bot_health_died.bind(bot))
		return
	# 3) RangeTarget-style: signal target_down
	if bot is RangeTarget:
		var target := bot as RangeTarget
		if not target.target_down.is_connected(_on_bot_target_down.bind(bot)):
			target.target_down.connect(_on_bot_target_down.bind(bot))

func _on_bot_died(bot: NpcBot) -> void:
	_register_bot_death(bot, true)

func _on_bot_health_died(_cause: String, bot: Node) -> void:
	_register_bot_death(bot, true)

func _on_bot_target_down(bot: Node) -> void:
	_register_bot_death(bot, false)


## npc-body owns the corpse data and guard; the arena owns the UI bridge. The
## live InventoryContainer is opened beside the player's backpack/equipment so
## the existing transfer, quick-equip and world-drop paths stay authoritative.
func _on_corpse_loot_requested(corpse: NpcBot, container: InventoryContainer) -> void:
	if not is_instance_valid(corpse) or container == null:
		return
	if corpse.get_corpse_inventory() != container:
		_set_center("Cadáver sem itens")
		return
	if player == null or player.inventory_ui == null:
		push_warning("ARENA: corpse loot requested without player inventory UI")
		return
	if _inventory_open():
		player.inventory_ui.close_inventory()
	var label: String = corpse.display_name.strip_edges()
	if label.is_empty():
		label = corpse.name
	container.name = label
	_loot_corpse = corpse
	_set_inventory_chrome_hidden(true)
	player.inventory_ui.open_inventory(player, container)
	call_deferred("_focus_corpse_inventory", container)
	_set_center("Saqueando %s" % label)


func _inventory_open() -> bool:
	return player != null and player.inventory_ui != null and player.inventory_ui.is_open()


func _close_inventory() -> void:
	_loot_corpse = null
	if _inventory_open():
		player.inventory_ui.close_inventory()
	else:
		_set_inventory_chrome_hidden(false)


func _on_inventory_closed() -> void:
	_loot_corpse = null
	_set_inventory_chrome_hidden(false)


func _on_inventory_visibility_changed() -> void:
	_set_inventory_chrome_hidden(_inventory_open())


## InventoryContainerUI's grid is a plain Control, so its row height does not
## become the panel's container minimum. Without an explicit height, two open
## panels receive shallow VBox space and their grids paint over each other.
## Size each live panel from its actual grid and scroll the corpse section into
## view; all transfer/drop behavior remains in the shared inventory UI.
func _focus_corpse_inventory(container: InventoryContainer) -> void:
	if not _inventory_open() or player.inventory_ui == null:
		return
	var corpse_ui: InventoryContainerUI = null
	for ui in player.inventory_ui.open_containers:
		_fit_inventory_panel(ui)
		if ui.current_inventory_source == container:
			corpse_ui = ui
	if corpse_ui == null:
		return
	await get_tree().process_frame
	if not _inventory_open() or not is_instance_valid(corpse_ui):
		return
	var column := corpse_ui.get_parent()
	var scroll: ScrollContainer = null
	if column != null:
		scroll = column.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = int(maxf(0.0, corpse_ui.position.y))


func _fit_inventory_panel(ui: InventoryContainerUI) -> void:
	var container := ui.current_inventory_source as InventoryContainer
	if container == null:
		return
	var grid_height := float(container.grid_height * ui.slot_size)
	ui.custom_minimum_size = Vector2(0.0, grid_height + INVENTORY_PANEL_CHROME)
	ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Hide only persistent chrome that competes with the centered inventory. The
## damage flash remains visible because the raid keeps running while looting.
func _set_inventory_chrome_hidden(hidden: bool) -> void:
	if hidden:
		if not _inventory_hidden_chrome.is_empty():
			return
		var candidates: Array[Node] = []
		if top_label != null:
			candidates.append(top_label.get_parent())
		if raid_label != null:
			candidates.append(raid_label.get_parent())
		if not feed_labels.is_empty():
			var feed_box := feed_labels[0].get_parent()
			if feed_box != null:
				candidates.append(feed_box.get_parent())
		candidates.append(center_label)
		candidates.append(death_label)
		candidates.append(extract_label)
		candidates.append(dir_marker)
		if player != null:
			candidates.append(player.get_node_or_null("PlayerStatusHud"))
			for child in player.get_children():
				if child is SubViewportContainer:
					candidates.append(child)
		for item in candidates:
			if item != null and is_instance_valid(item) and _node_visible(item):
				_inventory_hidden_chrome.append(item)
				_set_node_visible(item, false)
		return
	for item in _inventory_hidden_chrome:
		if is_instance_valid(item):
			_set_node_visible(item, true)
	_inventory_hidden_chrome.clear()


func _node_visible(node: Node) -> bool:
	if node is CanvasLayer:
		return (node as CanvasLayer).visible
	if node is CanvasItem:
		return (node as CanvasItem).visible
	return false


func _set_node_visible(node: Node, value: bool) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = value
	elif node is CanvasItem:
		(node as CanvasItem).visible = value


func _tick_corpse_loot() -> void:
	if _loot_corpse == null:
		return
	if not is_instance_valid(_loot_corpse):
		_close_inventory()
		_set_center("Cadáver removido")
		return
	if _loot_corpse.get_corpse_inventory() == null:
		_close_inventory()
		_set_center("Cadáver saqueado")

## The adapter owns attribution/result interpretation; this method retains the
## scene lifecycle around it. Respawn scheduling stays here because it depends on
## arena timers and the frozen match/raid lifecycle.
func _register_bot_death(bot: Node, respawn: bool) -> void:
	if not _match_over and not _raid_over:
		_apply_kill_result(_result_adapter.record_bot_death(game_mode, bot, PLAYER_ID))
	if respawn:
		_respawn_bot_later()


## Single kill entry: the adapter calls GameMode exactly once, then this scene
## publishes raid/EXP/feed/match-over side effects in their historical order.
func _register_kill(killer_id: int, victim_id: int, victim_team: int, victim_name: String) -> void:
	if _match_over or _raid_over:
		return
	_apply_kill_result(_result_adapter.record_kill(
		game_mode, PLAYER_ID, killer_id, victim_id, victim_team, victim_name))


func _apply_kill_result(result: Dictionary) -> void:
	var killer_id := int(result.get("killer_id", NO_KILLER))
	var victim_id := int(result.get("victim_id", 0))
	# Raid event bus: consumer-less for now (quests/skills arrive later).
	if raid != null:
		raid.register_kill(killer_id, victim_id, _current_weapon_name())
		if killer_id == PLAYER_ID:
			raid.add_exp(KILL_EXP)
	_push_feed(String(result.get("feed_text", "")))
	_check_match_over()

func _current_weapon_name() -> String:
	return weapon.name if weapon != null else ""

func _check_match_over() -> void:
	if _match_over or not game_mode.is_match_over():
		return
	_match_over = true
	var winner := _winner_text()
	if death_label:
		death_label.text = "FIM DE JOGO — %s" % winner
		death_label.visible = true
	_push_feed("FIM DE JOGO: %s" % winner)
	if OS.is_debug_build(): print("MATCH OVER: mode=%s winner=%s scores=%s" % [game_mode.mode_name, winner, game_mode.get_scores()])

func _winner_text() -> String:
	return _result_adapter.winner_text(game_mode, PLAYER_ID)

func _respawn_bot_later() -> void:
	# NpcBot despawns itself; spawn a wave replacement after respawn_delay.
	await get_tree().create_timer(game_mode.respawn_delay).timeout
	if not is_inside_tree() or _match_over or _raid_over:
		return
	var index := _bot_seq + 1
	var team: int = game_mode.assign_team(index)
	_spawn_bot(_free_spawn(team), team)
	_push_feed("Wave: novo %s" % game_mode.team_name(team))

# ─── player death + respawn ───

func _connect_player_health() -> void:
	if player.health is Health:
		if not player.health.player_died.is_connected(_on_player_died):
			player.health.player_died.connect(_on_player_died)
		if not player.health.health_changed.is_connected(_on_player_damaged):
			player.health.health_changed.connect(_on_player_damaged)

func _on_player_damaged(_part: BodyPart, old_hp: float, new_hp: float) -> void:
	if new_hp >= old_hp or flash_rect == null:
		return
	flash_rect.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.5)
	_show_damage_direction()

func _on_player_died(cause: String) -> void:
	deaths += 1
	# Killer is unknown (melee bot doesn't report itself).
	_register_kill(NO_KILLER, PLAYER_ID, _player_team, "você")
	if raid != null and raid.is_active():
		# KIA ends the raid: no respawn loop in the raid ruleset.
		raid.end(Raid.Outcome.KIA)
		if death_label:
			death_label.text = "Você morreu: %s" % cause
		return
	if _match_over or _raid_over:
		return
	_push_feed("Você morreu: %s" % cause)
	var delay: float = game_mode.respawn_delay
	if death_label:
		death_label.text = "Você morreu — respawn em %ds" % int(delay)
		death_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or _match_over or _raid_over:
		return
	_respawn_player()

func _respawn_player() -> void:
	player.global_position = _free_spawn(_player_team)
	player.velocity = Vector3.ZERO
	player.health = Health.new()
	_connect_player_health()
	_equip_loadout()
	if OS.is_debug_build(): print("ARENA RESPAWN: %s" % _rounds_left())
	if death_label:
		death_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_push_feed("Respawn — boa sorte")
	_refresh_top("respawned")

# ─── HUD (scene code only; addon HUD untouched) ───

func _panel_style() -> StyleBoxFlat:
	return HudStyle.panel()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ArenaHUD"
	add_child(layer)
	# Damage flash (full screen, under everything else).
	flash_rect = ColorRect.new()
	flash_rect.name = "DamageFlash"
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	# Top bar on a translucent panel.
	var top_panel := PanelContainer.new()
	top_panel.name = "TopPanel"
	top_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_panel.position = Vector2(-330, 8)
	top_panel.size = Vector2(660, 40)
	top_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(top_panel)
	top_label = Label.new()
	top_label.name = "TopBar"
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.add_theme_font_size_override("font_size", 20)
	top_panel.add_child(top_label)
	center_label = Label.new()
	center_label.name = "CenterMsg"
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.position = Vector2(-320, 40)
	center_label.size = Vector2(640, 30)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", HudStyle.FONT_MSG)
	layer.add_child(center_label)
	# Damage direction: dot on a 110px ring around the center.
	dir_marker = ColorRect.new()
	dir_marker.name = "DirMarker"
	dir_marker.color = Color(1.0, 0.35, 0.15, 0.95)
	dir_marker.size = Vector2(12, 12)
	dir_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dir_marker.visible = false
	layer.add_child(dir_marker)
	# Killfeed on a translucent panel.
	var feed_panel := PanelContainer.new()
	feed_panel.name = "FeedPanel"
	feed_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_panel.position = Vector2(-332, 58)
	feed_panel.size = Vector2(322, 100)
	feed_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(feed_panel)
	var feed_box := VBoxContainer.new()
	feed_box.name = "Killfeed"
	feed_panel.add_child(feed_box)
	for i in range(3):
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_size_override("font_size", 16)
		l.text = ""
		feed_box.add_child(l)
		feed_labels.append(l)
	death_label = Label.new()
	death_label.name = "DeathMsg"
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.position = Vector2(-320, -60)
	death_label.size = Vector2(640, 40)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 28)
	death_label.visible = false
	layer.add_child(death_label)
	# Raid line (timer + EXP + currency) on its own panel under the top bar.
	var raid_panel := PanelContainer.new()
	raid_panel.name = "RaidPanel"
	raid_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	raid_panel.position = Vector2(-330, 54)
	raid_panel.size = Vector2(660, 32)
	raid_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(raid_panel)
	raid_label = Label.new()
	raid_label.name = "RaidLine"
	raid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raid_label.add_theme_font_size_override("font_size", 18)
	raid_panel.add_child(raid_label)
	# Extraction list + in-progress line, bottom center.
	extract_label = Label.new()
	extract_label.name = "ExtractLine"
	extract_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	extract_label.position = Vector2(-460, -84)
	extract_label.size = Vector2(920, 30)
	extract_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extract_label.add_theme_font_size_override("font_size", HudStyle.FONT_HINT)
	layer.add_child(extract_label)
	_build_result_panel(layer)
	_build_market(layer)

## Trader panel: lists Meta's offer lines and drives Meta.buy/sell.
func _build_market(layer: CanvasLayer) -> void:
	market_panel = PanelContainer.new()
	market_panel.name = "MarketPanel"
	market_panel.set_anchors_preset(Control.PRESET_CENTER)
	market_panel.position = Vector2(-330, -190)
	market_panel.size = Vector2(660, 380)
	market_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	market_panel.visible = false
	layer.add_child(market_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	market_panel.add_child(box)
	market_title = Label.new()
	market_title.name = "MarketTitle"
	market_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	market_title.add_theme_font_size_override("font_size", 22)
	box.add_child(market_title)
	market_rows = VBoxContainer.new()
	market_rows.name = "MarketRows"
	market_rows.add_theme_constant_override("separation", 6)
	box.add_child(market_rows)
	market_msg = Label.new()
	market_msg.name = "MarketMsg"
	market_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	market_msg.add_theme_font_size_override("font_size", 16)
	box.add_child(market_msg)
	var close := Button.new()
	close.text = "Fechar (E/Esc)"
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(_close_market)
	box.add_child(close)

func _open_market(trader_id: String) -> void:
	if meta == null or meta.profile == null:
		return
	meta.load_market()
	if meta.profile.market.get_trader(trader_id) == null:
		_set_center("trader desconhecido: %s" % trader_id)
		return
	_market_trader = trader_id
	_market_open = true
	market_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_market()

func _close_market() -> void:
	if not _market_open:
		return
	_market_open = false
	if market_panel != null:
		market_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_market() -> void:
	if meta == null or meta.profile == null:
		return
	var market: Market = meta.profile.market
	var t: Trader = market.get_trader(_market_trader)
	if t == null:
		market_title.text = "Trader desconhecido"
		return
	market_title.text = "%s  |  LL%d  |  REP %d  |  %d cr" % [t.display_name(), market.loyalty_level(_market_trader), market.reputation(_market_trader), meta.profile.currency]
	for c in market_rows.get_children():
		market_rows.remove_child(c)
		c.queue_free()
	for i in range(t.offers.size()):
		# Single source of truth for availability: Meta.can_buy/can_sell.
		var cb: Dictionary = meta.can_buy(_market_trader, i)
		var cs: Dictionary = meta.can_sell(_market_trader, i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = market.offer_line(_market_trader, i)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", HudStyle.FONT_HINT)
		if not cb.get("ok", false):
			lbl.text += "  [%s]" % String(cb.get("reason", ""))
		row.add_child(lbl)
		var buy := Button.new()
		buy.text = "Comprar"
		buy.disabled = not cb.get("ok", false)
		buy.tooltip_text = String(cb.get("reason", ""))
		buy.pressed.connect(_market_buy.bind(i))
		row.add_child(buy)
		var sell := Button.new()
		sell.text = "Vender"
		sell.disabled = not cs.get("ok", false)
		sell.tooltip_text = String(cs.get("reason", ""))
		sell.pressed.connect(_market_sell.bind(i))
		row.add_child(sell)
		market_rows.add_child(row)

func _market_buy(index: int) -> void:
	var r: Dictionary = meta.buy(_market_trader, index)
	if r.get("ok", false):
		var item = r.get("item")
		var nm: String = item.name if item != null else "item"
		market_msg.text = "Comprado: %s" % nm
		_push_feed("Comprou %s" % nm)
	else:
		market_msg.text = "Recusado: %s" % String(r.get("reason", "?"))
	meta.persist()
	_refresh_market()

func _market_sell(index: int) -> void:
	var r: Dictionary = meta.sell(_market_trader, index)
	if r.get("ok", false):
		market_msg.text = "Vendido por %d cr" % int(r.get("price", 0))
		_push_feed("Vendeu por %d cr" % int(r.get("price", 0)))
	else:
		market_msg.text = "Recusado: %s" % String(r.get("reason", "?"))
	meta.persist()
	_refresh_market()


## End-of-raid banner: outcome + EXP + "Voltar ao menu".
func _build_result_panel(layer: CanvasLayer) -> void:
	result_panel = PanelContainer.new()
	result_panel.name = "RaidResult"
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.position = Vector2(-230, -130)
	result_panel.size = Vector2(460, 260)
	result_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	result_panel.visible = false
	layer.add_child(result_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	result_panel.add_child(box)
	result_label = Label.new()
	result_label.name = "ResultText"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 30)
	box.add_child(result_label)
	back_btn = Button.new()
	back_btn.name = "BackToMenu"
	back_btn.text = "Voltar ao menu"
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(_on_back_to_menu)
	box.add_child(back_btn)

func _show_result(out_name: String, exp: int) -> void:
	if result_panel == null:
		return
	result_panel.visible = true
	result_label.text = "%s\nEXP %d" % [out_name, exp]
	_apply_result_text() # adds meta report (items/currency) + quest line
	death_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# freeze combat: stop waves, pause bots' aggression by pausing physics.
	for b in get_tree().get_nodes_in_group("bots"):
		if b is NpcBot:
			(b as NpcBot).set_physics_process(false)

func _on_back_to_menu() -> void:
	# Never lose the save: flush the profile before leaving the scene.
	if meta != null:
		meta.persist()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _mag_text(w: Weapon) -> String:
	if w == null or w.ammo_feed == null:
		return "-- vazio"
	var s := "%d" % w.ammo_feed.capacity
	if w.chambered_round:
		s += "+1"
	return "%s [%s]" % [s, w.get_firemode_name()]

func _rounds_left() -> String:
	if weapon == null:
		return "DESARMADO"
	return "MAG " + _mag_text(weapon)

func _slots_line() -> String:
	var parts: Array[String] = []
	var idx := 1
	for s in SLOT_ORDER:
		var w := _slot_weapon(s)
		var mark := ">" if s == active_slot else " "
		parts.append("%s%d %s" % [mark, idx, ("%s %s" % [w.name, _mag_text(w)] if w else "--")])
		idx += 1
	return "  ".join(parts)

# ─── damage vignette + approximate direction (kept: not aim UI) ───

## Approximate bearing to the nearest living bot, on a ring around center.
func _show_damage_direction() -> void:
	if dir_marker == null or player == null or player.camera == null:
		return
	var best: NpcBot = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("bots"):
		if n is NpcBot and (n as NpcBot).is_alive():
			var d: float = player.global_position.distance_squared_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n
	if best == null:
		return
	var cam := player.camera
	var to: Vector3 = best.global_position - cam.global_position
	var local: Vector3 = cam.global_transform.basis.inverse() * to
	var ang := atan2(local.x, -local.z)
	var vp := get_viewport().get_visible_rect().size / 2.0
	dir_marker.position = vp + Vector2(sin(ang), -cos(ang)) * 110.0 - dir_marker.size / 2.0
	dir_marker.visible = true
	dir_marker.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(dir_marker, "modulate:a", 0.0, 0.4)
	tween.tween_callback(dir_marker.hide)

func _hp_text() -> String:
	if player == null or player.health == null:
		return "HP ?"
	var h: Health = player.health
	return "HP %d/%d" % [int(h.total_health), int(h.max_total_health)]

## Mode-owned scoreboard text (no hardcoded kill counters in the manager).
func _score_text() -> String:
	if game_mode == null:
		return ""
	if game_mode.team_count > 1:
		var parts: Array[String] = []
		for t in range(game_mode.team_count):
			parts.append("%s %d" % [game_mode.team_name(t), game_mode.get_team_score(t)])
		return "%s — primeiro a %d" % ["  |  ".join(parts), game_mode.score_limit]
	return "PLACAR %d/%d" % [game_mode.get_score_of(PLAYER_ID), game_mode.score_limit]

func _refresh_top(msg: String) -> void:
	if top_label == null:
		return
	var base := "%s | %s | %s\n%s" % [_hp_text(), _rounds_left(), _score_text(), _slots_line()]
	top_label.text = base if msg == "" else "%s   -- %s" % [base, msg]

func _set_center(msg: String) -> void:
	if center_label:
		center_label.text = msg
	_refresh_top("")

func _push_feed(line: String) -> void:
	_feed.push_front(line)
	while _feed.size() > 3:
		_feed.pop_back()
	for i in range(feed_labels.size()):
		feed_labels[i].text = _feed[i] if i < _feed.size() else ""

# ─── pause (Esc) ───

func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.name = "PauseMenu"
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-140, -110)
	pause_panel.size = Vector2(280, 220)
	pause_panel.visible = false
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	pause_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PAUSADO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var btn_cont := Button.new()
	btn_cont.text = "Continuar"
	btn_cont.pressed.connect(_on_pause_continue)
	btn_cont.pressed.connect(audio.play_ui)
	box.add_child(btn_cont)
	var btn_restart := Button.new()
	btn_restart.text = "Reiniciar"
	btn_restart.pressed.connect(_on_pause_restart)
	btn_restart.pressed.connect(audio.play_ui)
	box.add_child(btn_restart)
	var btn_menu := Button.new()
	btn_menu.text = "Menu"
	btn_menu.pressed.connect(_on_pause_menu)
	btn_menu.pressed.connect(audio.play_ui)
	box.add_child(btn_menu)
	# HUD layer is child 0; pause goes on top in its own layer.
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = 10
	add_child(layer)
	layer.add_child(pause_panel)

func _toggle_pause() -> void:
	if pause_panel == null:
		return
	var will_pause := not get_tree().paused
	get_tree().paused = will_pause
	pause_panel.visible = will_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if will_pause else Input.MOUSE_MODE_CAPTURED

func _on_pause_continue() -> void:
	_toggle_pause()

## Inventory "Modificar" (inventory-ux -> player-rig) -> edit that weapon.
## Order matters: close the inventory first (it recaptures the mouse), THEN
## open the gunsmith (which releases it last). In debug_range there is no
## listener, so nothing closes blindly — only the opener closes.
func _on_weapon_modify_requested(w: Weapon) -> void:
	if gunsmith == null or w == null:
		return
	var inv = player.get("inventory_ui")
	if inv != null and inv.has_method("close_inventory") and inv.visible:
		inv.close_inventory()
	gunsmith.open_for_weapon(w)

func _on_pause_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_pause_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
