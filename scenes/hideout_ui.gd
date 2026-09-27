# res://scenes/hideout_ui.gd
class_name HideoutUI
extends Control
## The hideout's recovered-goods list: the surface the owner asked for, rendering
## FreeItemsView rather than reimplementing it.
##
## WHY A VIEW AND NOT ITS OWN LOGIC. cf9448 asks for "shows the recovered items,
## and lets a claim be resolved". FreeItemsView already answers "what is
## recoverable, why is it not here yet, and when does it come back" -- it is
## validated, it delegates to Insurance, and its reasons are catalogue KEYS. A
## surface that asked the insurance system its own questions would be a second
## implementation of an answer that exists, and would drift.
##
## WHY NO ROSTER. The genre rule here is that a framework cannot hardcode what the
## game decides. Rows come from the claim data, so adding a tenth insurance
## product or a fourth return policy needs a .tres, never an edit to this file.
##
## A claim is "resolved" by ASKING, not by mutating: process_returns() is the
## owning API and this surface only reports what it did. The button is disabled
## rather than hidden when there is nothing to collect, so the absence of free
## items is legible instead of being an empty screen with no explanation.

const VIEW_SCRIPT := preload("res://src/meta/free_items_view.gd")

## Emitted when the player asks for whatever has come due. The controller owns
## the MetaService, so this surface does not resolve anything itself.
signal resolve_requested

## The Back button existed, was resolved as %BtnBack, and was connected to
## NOTHING. A declared-but-unwired control is the most expensive kind of dead UI:
## it renders, it takes the click, and it produces no signal and no effect
## anywhere, so the player's report is "the back button does nothing" and the
## repository contains a green harness for a screen nobody could leave.
signal back_requested

@onready var _list: VBoxContainer = %Rows
@onready var _summary: Label = %Summary
@onready var _resolve: Button = %BtnResolve
@onready var _back: Button = %BtnBack
@onready var _stash_rows: VBoxContainer = %StashRows
@onready var _stash_summary: Label = %StashSummary

var _view: RefCounted = null
var _stash: StashView = null


func _ready() -> void:
	_resolve.pressed.connect(func() -> void: resolve_requested.emit())
	# Connected, finally. f5cac6's record goes in at the TOP of the handler so the
	# REACHED proves the click arrived before the work, and a REACHED with no
	# RESULT is then a navigation that started and did not land.
	_back.pressed.connect(_on_back_pressed)


## The surface emits an INTENT. It does not call change_scene_to_file itself,
## because the controller owns navigation -- that split is why the hub works and
## is the reason this is a signal rather than a direct route.
func _on_back_pressed() -> void:
	back_requested.emit()


## Bind a profile + insurance pair. Kept as an explicit call rather than an
## autoload lookup so the surface has no hidden dependency and a harness can drive
## it with fixtures.
func bind(profile, insurance) -> void:
	_view = VIEW_SCRIPT.new(profile, insurance)
	# StashView is constructed with the same profile and NO death policy, because
	# the hideout shows what the player OWNS rather than what a death would spare.
	# Handing it a policy here would answer a different question on this screen.
	_stash = StashView.new(profile as MetaProfile, null)
	refresh()


func refresh() -> void:
	if _view == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var rows: Array = _view.rows()
	for row in rows:
		_list.add_child(_make_row(row))
	var pending: int = int(_view.pending_item_count())
	var waits: int = int(_view.raids_until_next_return())
	_summary.text = "recovered goods (%d pending, next return in %s)" % [pending, _row_wait(waits)]
	# Disabled, not hidden: "you own nothing" and "the button is missing" must not
	# look the same.
	_resolve.disabled = _nothing_due(rows)
	_resolve.text = "collect" if not _resolve.disabled else "nothing due yet"
	_refresh_stash()


## The stored-goods half of the screen.
##
## DELEGATED, NOT REIMPLEMENTED. StashView already partitions the stash into what
## is STORED, what is in the SAFE POCKET, and what is RECOVERABLE, and it already
## resolves identity through ItemNames and capacity through the owning stash. A
## list built here would be a second answer to questions that have one, and would
## drift -- which is how the hub ended up with a hardcoded catalogue.
##
## CAPACITY IS SHOWN because a stash without its limit is a stash you cannot tell
## is full, and "full" is the single most common reason a player believes
## something has been lost.
func _refresh_stash() -> void:
	if _stash_rows == null:
		return
	for child in _stash_rows.get_children():
		child.queue_free()
	if _stash == null:
		if _stash_summary != null:
			_stash_summary.text = "stored goods (unavailable)"
		return
	if _stash_summary != null:
		_stash_summary.text = "stored goods (%d of %d cells, %.1f of %.1f mass)" % [
			_stash.used_cells(), _stash.capacity(), _stash.stored_weight(), _stash.weight_limit(),
		]
	for row in _stash.rows():
		_stash_rows.add_child(_make_stash_row(row))


func _make_stash_row(row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var id := String(row.get("id", ""))
	var name_label := Label.new()
	# Same rule as the claims list: never render a raw id, and mark an
	# unregistered one rather than leaking it to the player.
	name_label.text = "* unidentified item" if id.is_empty() else ItemNames.display_name(id)
	box.add_child(name_label)
	var note := Label.new()
	note.text = "%d x" % int(row.get("stack", 1))
	box.add_child(note)
	return box


## One row per claim line, labelled by KEY. The reason is a catalogue msgid, so
## it goes through TranslationServer and a screen can never render a raw key or a
## composed English sentence as if it were the game's copy.
func _make_row(row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var name_label := Label.new()
	var id := String(row.get("id", ""))
	if id == "":
		# Unregistered: mark it. Rendering the raw id is the leak this whole
		# registry exists to prevent, and FreeItemsView is the thing that already
		# knows which ids those are.
		name_label.text = "* unidentified item"
	else:
		name_label.text = ItemNames.display_name(id)
	var reason_key := String(row.get("key", ""))
	var reason := Label.new()
	reason.text = reason_label_text(reason_key, int(row.get("raids_until", -1)))
	box.add_child(name_label)
	box.add_child(reason)
	return box


## The reason sentence, translated, with the wait stated in the game's own units
## rather than a hardcoded "raid" string.
func reason_label_text(reason_key: String, raids_until: int) -> String:
	var text: String = TranslationServer.translate(reason_key) if reason_key != "" else reason_key
	if raids_until >= 0:
		return "%s (%d)" % [text, raids_until]
	return text


func _row_wait(waits: int) -> String:
	return "%d" % waits if waits > 0 else "now"


func _nothing_due(rows: Array) -> bool:
	for row in rows:
		if int(row.get("raids_until", 1)) <= 0:
			return false
	return true
