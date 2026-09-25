extends "res://scenes/arena_manager_gameplay.gd"


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
	_market_close_btn = close
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
	_pause_buttons.append(btn_cont)
	box.add_child(btn_cont)
	var btn_restart := Button.new()
	btn_restart.text = "Reiniciar"
	btn_restart.pressed.connect(_on_pause_restart)
	btn_restart.pressed.connect(audio.play_ui)
	_pause_buttons.append(btn_restart)
	box.add_child(btn_restart)
	var btn_menu := Button.new()
	btn_menu.text = "Menu"
	btn_menu.pressed.connect(_on_pause_menu)
	btn_menu.pressed.connect(audio.play_ui)
	_pause_buttons.append(btn_menu)
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


func _exit_tree() -> void:
	super._exit_tree()
	if back_btn != null and is_instance_valid(back_btn):
		_disconnect_signal(back_btn.pressed, "_on_back_to_menu")
	if _market_close_btn != null and is_instance_valid(_market_close_btn):
		_disconnect_signal(_market_close_btn.pressed, "_close_market")
	for button in _pause_buttons:
		if not is_instance_valid(button):
			continue
		_disconnect_signal(button.pressed, "_on_pause_continue")
		_disconnect_signal(button.pressed, "_on_pause_restart")
		_disconnect_signal(button.pressed, "_on_pause_menu")
		if audio != null:
			var audio_callback := audio.play_ui
			if button.pressed.is_connected(audio_callback):
				button.pressed.disconnect(audio_callback)
