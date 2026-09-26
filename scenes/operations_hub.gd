class_name OperationsHubUI
extends Control
## Bounded, presentation-only operations hub shell.
##
## This node does not load, save, mutate, or validate persistent profile data.
## Meta/player-rig owns the profile and loadout models; they push snapshots in
## through set_profile(), set_last_report(), and set_loadouts(). Navigation is
## exposed as signals so the surrounding flow can decide what a deploy means.

signal loadout_selected(loadout_id: String)
signal deploy_requested(loadout_id: String)
signal return_to_hub_requested

enum LoadoutState {
	EMPTY,
	VALID,
	INVALID,
}

@export var title_text := "CENTRAL DE OPERAÇÕES"
@export var empty_report_text := "Nenhum relatório anterior"
@export var empty_loadout_text := "Nenhum loadout disponível"
@export var empty_stash_text := "Reserva vazia"
@export var invalid_loadout_text := "Loadout inválido ou incompleto"
@export var valid_loadout_text := "Pronto para iniciar"

## The most recent snapshots supplied by the owner. They are intentionally
## retained as presentation data only; no authority is inferred from them.
var profile: PlayerProfile
var last_report: Variant
var loadout_options: Array[Dictionary] = []
var stash_items: Array[Dictionary] = []
var selected_loadout_id := ""
var loadout_state: LoadoutState = LoadoutState.EMPTY

# Public handles for focused UI tests and for a parent shell that wants to add
# decoration without reaching into the visual tree.
var profile_label: Label
var report_label: Label
var loadout_picker: OptionButton
var loadout_details: Label
var stash_label: Label
var status_label: Label
var deploy_button: Button
var return_button: Button

var _built := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_built = true
	_refresh()


func _build_ui() -> void:
	if _built or get_child_count() > 0:
		return

	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.055, 0.07, 0.09, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	column.add_child(title)

	var section := _section("PERFIL", column)
	profile_label = Label.new()
	profile_label.name = "ProfileSummary"
	profile_label.text = "Faction: —    Créditos: —"
	profile_label.add_theme_font_size_override("font_size", 18)
	profile_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	section.add_child(profile_label)
	report_label = Label.new()
	report_label.name = "LastReport"
	report_label.text = empty_report_text
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.75))
	section.add_child(report_label)

	var loadout_section := _section("LOADOUT", column)
	loadout_picker = OptionButton.new()
	loadout_picker.name = "LoadoutPicker"
	loadout_picker.custom_minimum_size = Vector2(360, 42)
	loadout_picker.item_selected.connect(_on_loadout_selected)
	loadout_section.add_child(loadout_picker)
	loadout_details = Label.new()
	loadout_details.name = "LoadoutDetails"
	loadout_details.text = empty_loadout_text
	loadout_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_section.add_child(loadout_details)

	var stash_section := _section("ARMAZENAMENTO", column)
	stash_label = Label.new()
	stash_label.name = "StashItems"
	stash_label.text = empty_stash_text
	stash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stash_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	stash_section.add_child(stash_label)

	status_label = Label.new()
	status_label.name = "LoadoutStatus"
	status_label.text = empty_loadout_text
	status_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	column.add_child(status_label)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	deploy_button = Button.new()
	deploy_button.name = "DeployButton"
	deploy_button.text = "Deploy"
	deploy_button.custom_minimum_size = Vector2(180, 44)
	deploy_button.pressed.connect(_on_deploy_pressed)
	actions.add_child(deploy_button)
	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "Voltar à central"
	return_button.custom_minimum_size = Vector2(180, 44)
	return_button.pressed.connect(_on_return_pressed)
	actions.add_child(return_button)
	for button in [deploy_button, return_button]:
		button.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.19, 0.25)))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.21, 0.29, 0.37)))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.14, 0.18)))


func _section(name_text: String, parent: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = name_text.capitalize().replace(" ", "") + "Section"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.16, 0.96)
	style.border_color = Color(0.22, 0.29, 0.37, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	panel.add_child(section)
	parent.add_child(panel)
	return section


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.content_margin_left = 14.0
	style.content_margin_top = 8.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 8.0
	return style


## Supply the profile snapshot. MetaProfile extends PlayerProfile, so callers can
## pass either without this shell knowing about persistence or MetaService.
func set_profile(value: PlayerProfile) -> void:
	profile = value
	_refresh()


func configure_profile(value: PlayerProfile) -> void:
	set_profile(value)


## Accepts either the persisted last_report Dictionary or a RaidReport object.
func set_last_report(value: Variant) -> void:
	last_report = value
	_refresh()


## Stash entries are presentation dictionaries: name, count and weapon. The
## shell never receives or mutates the owner's inventory objects.
func set_stash_items(items: Array) -> void:
	stash_items.clear()
	for item in items:
		if item is Dictionary:
			stash_items.append((item as Dictionary).duplicate(true))
	_refresh()


## Options are plain presentation dictionaries. Expected keys are:
##   id (required), label, valid, summary, items.
## The owner decides validity; this node only represents empty/valid/invalid
## selection state and never writes back to the owner.
func set_loadouts(options: Array) -> void:
	loadout_options.clear()
	for option in options:
		if option is Dictionary and String(option.get("id", "")) != "":
			loadout_options.append((option as Dictionary).duplicate(true))
	if selected_loadout_id == "" and not loadout_options.is_empty():
		selected_loadout_id = String(loadout_options[0].get("id", ""))
	elif _find_option(selected_loadout_id) == null:
		selected_loadout_id = ""
	_recompute_state()
	_refresh()


func set_selected_loadout(loadout_id: String) -> void:
	if loadout_id != "" and _find_option(loadout_id) == null:
		selected_loadout_id = ""
		return
	selected_loadout_id = loadout_id
	_recompute_state()
	_refresh()
	loadout_selected.emit(selected_loadout_id)


func can_deploy() -> bool:
	return loadout_state == LoadoutState.VALID and selected_loadout_id != ""


func _refresh() -> void:
	_recompute_state()
	if profile_label != null:
		if profile == null:
			profile_label.text = "Faction: —    Créditos: —"
		else:
			profile_label.text = "Faction: %s    Créditos: %d" % [profile.faction_name(), profile.currency]
	if report_label != null:
		report_label.text = _report_text()
	if loadout_picker != null:
		_rebuild_picker()
	if loadout_details != null:
		loadout_details.text = _details_text()
	if stash_label != null:
		stash_label.text = _stash_text()
	if status_label != null:
		match loadout_state:
			LoadoutState.VALID:
				status_label.text = valid_loadout_text
				status_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.58))
			LoadoutState.INVALID:
				status_label.text = invalid_loadout_text
				status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
			_:
				status_label.text = empty_loadout_text
				status_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	if deploy_button != null:
		deploy_button.disabled = not can_deploy()


func _recompute_state() -> void:
	if loadout_options.is_empty() or selected_loadout_id == "":
		loadout_state = LoadoutState.EMPTY
		return
	var option := _find_option(selected_loadout_id)
	loadout_state = LoadoutState.VALID if option != null and bool(option.get("valid", true)) else LoadoutState.INVALID


func _find_option(loadout_id: String) -> Dictionary:
	for option in loadout_options:
		if String(option.get("id", "")) == loadout_id:
			return option
	return {}


func _rebuild_picker() -> void:
	loadout_picker.clear()
	if loadout_options.is_empty():
		loadout_picker.add_item(empty_loadout_text)
		loadout_picker.set_item_disabled(0, true)
		loadout_picker.select(0)
		return
	var selected_index := 0
	for i in loadout_options.size():
		var option := loadout_options[i]
		var label := String(option.get("label", option.get("id", "Loadout %d" % (i + 1))))
		loadout_picker.add_item(label)
		loadout_picker.set_item_metadata(i, String(option.get("id", "")))
		if String(option.get("id", "")) == selected_loadout_id:
			selected_index = i
	loadout_picker.select(selected_index)


func _details_text() -> String:
	if loadout_options.is_empty():
		return empty_loadout_text
	var option := _find_option(selected_loadout_id)
	if option.is_empty():
		return "Selecione um loadout"
	var summary := String(option.get("summary", ""))
	if summary != "":
		return summary
	var items = option.get("items", [])
	if items is Array and not (items as Array).is_empty():
		var labels: Array[String] = []
		for item in items:
			labels.append(String(item.get("name", item)) if item is Dictionary else String(item))
		return ", ".join(labels)
	return "Sem detalhes fornecidos"


func _stash_text() -> String:
	if stash_items.is_empty():
		return empty_stash_text
	var labels: Array[String] = []
	for item in stash_items:
		var count := maxi(int(item.get("count", 1)), 1)
		var name_text := String(item.get("name", "?"))
		labels.append("%s ×%d" % [name_text, count] if count > 1 else name_text)
	return "    ".join(labels)


func _report_text() -> String:
	if last_report == null:
		return empty_report_text
	if last_report is RaidReport:
		return (last_report as RaidReport).summary()
	if last_report is Dictionary and (last_report as Dictionary).is_empty():
		return empty_report_text
	if last_report is Dictionary:
		var report := last_report as Dictionary
		var outcome := String(report.get("outcome_name", "—"))
		var exp := int(report.get("exp", 0))
		var currency_delta := int(report.get("currency_delta", 0))
		return "%s    EXP +%d    créditos %+d" % [outcome, exp, currency_delta]
	return String(last_report)


func _on_loadout_selected(index: int) -> void:
	if loadout_picker == null or index < 0 or index >= loadout_picker.item_count:
		return
	var id := String(loadout_picker.get_item_metadata(index))
	if id != "":
		set_selected_loadout(id)


func _on_deploy_pressed() -> void:
	if can_deploy():
		deploy_requested.emit(selected_loadout_id)


func _on_return_pressed() -> void:
	return_to_hub_requested.emit()
