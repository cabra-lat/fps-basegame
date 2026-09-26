extends "res://scenes/arena_manager_core.gd"

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
	call("_set_center", "ARMA ENGASGOU (X para limpar)")

func _on_malfunction_cleared(_w: Weapon, _kind: int) -> void:
	if audio != null:
		audio.play_malfunction_cleared()
	call("_set_center", "Arma limpa")

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
	call("_refresh_top", "")

func _activate_slot(slot: String) -> void:
	if _switch_cd > 0.0:
		return
	var target := _slot_weapon(slot)
	if target == null:
		call("_set_center", "slot %s vazio" % slot)
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
	call("_set_center", ">> %s" % target.name)
	call("_refresh_top", "")

func _drop_active() -> void:
	# Dropping never falls back to another slot: the gun leaves the hand and
	# its slot, nothing is auto-drawn (press 1/2 to draw the other).
	var item := _slot_item(active_slot)
	var w := _slot_weapon(active_slot)
	if item == null or w == null:
		call("_set_center", "nada para largar")
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
	call("_push_feed", "Largou %s (%d na mag)" % [w.name, rounds])
	call("_refresh_top", "")

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
		call("_close_market", )
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
				call("_set_center", "Cadáver sem itens")
			return
		if interactable is TraderPoint:
			interactable.interact(player) # emits -> _open_market
			return
		interactable.interact(player)
		call("_set_center", "%s ativado" % interactable.display_name)
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
	elif loot.has_meta("raid1_objective") and loot_data is Item:
		_pickup_raid1_objective(loot, loot_data as Item)
	else:
		call("_set_center", "nao pegavel")

func _pickup_weapon(loot: Weapon3D, w: Weapon) -> void:
	var free := ""
	for s in SLOT_ORDER:
		if _slot_weapon(s) == null:
			free = s
			break
	if free == "":
		call("_set_center", "SLOTS CHEIOS")
		return
	if loot.has_meta("kit"):
		_weapon_kit[w] = loot.get_meta("kit")
	if player.equipment.equip(InventorySystem.create_inventory_item(w), free):
		loot.queue_free()
		_activate_slot(free)
		if raid != null:
			raid.register_loot(w)
			raid.add_exp(LOOT_EXP)
		call("_push_feed", "Pegou %s" % w.name)
	else:
		call("_set_center", "slot incompativel")

func _pickup_raid1_objective(loot: Node, intel: Item) -> void:
	var bag: InventoryContainer = player.get_equipped_backpack()
	if bag == null:
		call("_set_center", "precisa de mochila")
		return
	var item: InventoryItem = InventoryItem.slurp(intel)
	if item == null:
		return
	item.set_meta("raid1_carry", true)
	if bag.add_item(item, Vector2i(-1, -1)):
		loot.queue_free()
		if raid != null:
			raid.register_loot(intel)
		if scenario != null and scenario.collect(Raid1ScenarioScript.OBJECTIVE_ID):
			call("_push_feed", "Intel marcado coletado — leve ao Signal Gate")
		call("_push_feed", "Pegou %s" % intel.name)
	else:
		call("_set_center", "mochila cheia")


## Medical/consumable pickup: goes into the equipped backpack (never a weapon
## slot). Uses position (-1,-1) so the grid finds free space (ZERO collides).
func _pickup_medical(loot: Node, med: MedicalItem) -> void:
	var bag: InventoryContainer = player.get_equipped_backpack()
	if bag == null:
		call("_set_center", "precisa de mochila")
		return
	var item: InventoryItem = InventoryItem.slurp(med)
	if item == null:
		return
	if bag.add_item(item, Vector2i(-1, -1)):
		loot.queue_free()
		if raid != null:
			raid.register_loot(med)
			raid.add_exp(LOOT_EXP)
		call("_push_feed", "Pegou %s" % med.name)
	else:
		call("_set_center", "mochila cheia")

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
	call("_refresh_top", "")

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
		call("_set_center", "miss")
		return
	var impact: BallisticsImpact = r["impact"]
	ShotResolver.apply_hit(self, r["collider"], impact, round, r["position"], audio)
	call("_set_center", "HIT %.0fm %.0fJ" % [r["distance"], impact.hit_energy])

func _on_mag_empty(_w: Weapon, _feed: AmmoFeed) -> void:
	call("_set_center", "MAG EMPTY - press R")

func _on_reserve_mag(_p: PlayerController) -> void:
	if weapon == null:
		return
	var kit: Array = _weapon_kit.get(weapon, [weapon_template, ammo_template, MAG_SIZE])
	if WeaponSystem.change_magazine(weapon, _make_mag_for(kit[0].ammo_feed, kit[1], kit[2])):
		call("_set_center", "reloaded")

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
		call("_set_center", "Cadáver sem itens")
		return
	if player == null or player.inventory_ui == null:
		push_warning("ARENA: corpse loot requested without player inventory UI")
		return
	if _inventory_open():
		player.inventory_ui.close_inventory()
	var label: String = String(corpse.get("display_name")).strip_edges()
	if label.is_empty():
		label = corpse.name
	container.name = label
	_loot_corpse = corpse
	_set_inventory_chrome_hidden(true)
	player.inventory_ui.open_inventory(player, container)
	call_deferred("_focus_corpse_inventory", container)
	call("_set_center", "Saqueando %s" % label)


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
	# The frame here is load-bearing and stays. An earlier version skipped it
	# when the corpse panel looked like it was already in view; both attempts at
	# that were wrong (the first guarded on where the VIEWPORT is, the second on
	# a count that the panel column does not share), and a wrong guard here makes
	# the corpse silently invisible. Reverted on QA's instruction, with the
	# numbers recorded so nobody re-derives it:
	#   this await costs one frame, ~16.7 ms at 60 fps
	#   inventory-ux's node-reuse on the same path took 87.6 ms -> 1.6 ms
	# Optimising the 16.7 ms is not worth a behaviour change whose correct form
	# depends on pooled-UI ownership in another lane. If it is ever worth it, the
	# red arm now exists: validate_inventory_ux's _check_corpse_panel_scroll().
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
		call("_set_center", "Cadáver removido")
		return
	if _loot_corpse.get_corpse_inventory() == null:
		_close_inventory()
		call("_set_center", "Cadáver saqueado")

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
	call("_push_feed", String(result.get("feed_text", "")))
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
	call("_push_feed", "FIM DE JOGO: %s" % winner)
	if OS.is_debug_build(): print("MATCH OVER: mode=%s winner=%s scores=%s" % [game_mode.mode_name, winner, game_mode.get_scores()])

func _winner_text() -> String:
	return _result_adapter.winner_text(game_mode, PLAYER_ID)

func _respawn_bot_later() -> void:
	# NpcBot despawns itself; spawn a wave replacement after the mode's
	# bot-replacement delay. That is SEPARATE from the player's respawn_delay on
	# purpose: the arena can be told (per server, in the mode .tres) that a
	# reinforcement enters the fight immediately while the player still takes
	# the 3 s breather. At 0.0 the guard below is still a POST-YIELD guard (a
	# zero timer yields rather than resuming inline, measured), so the ordinary
	# case is covered. The accepted edge of "enter immediately": a match that
	# ends in the same frame as the kill can now spawn a replacement where the
	# 3 s breather used to hide it. That is the price of the ruling, not a bug.
	await get_tree().create_timer(game_mode.effective_bot_respawn_delay()).timeout
	if not is_inside_tree() or _match_over or _raid_over:
		return
	var index := _bot_seq + 1
	var team: int = game_mode.assign_team(index)
	_spawn_bot(_free_spawn(team), team)
	call("_push_feed", "Wave: novo %s" % game_mode.team_name(team))

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
	call("_show_damage_direction", )

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
	call("_push_feed", "Você morreu: %s" % cause)
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
	if OS.is_debug_build(): print("ARENA RESPAWN: %s" % call("_rounds_left", ))
	if death_label:
		death_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	call("_push_feed", "Respawn — boa sorte")
	call("_refresh_top", "respawned")
