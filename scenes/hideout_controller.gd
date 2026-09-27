# res://scenes/hideout_controller.gd
class_name HideoutController
extends Node
## Owns the hideout screen's dependencies and its navigation, exactly as
## operations_hub_controller.gd owns the hub's. The surface asks; the controller
## acts, so nothing in the UI reaches for a singleton.
##
## WHY THIS FILE EXISTS RATHER THAN A SCRIPT ON THE SCENE ROOT. cf9448's acceptance
## is that the hideout is REACHABLE, and the same failure has already been found
## three times tonight: a thing that is structurally complete and behaviourally
## unreachable, with its own green harness. A controller with a named scene
## constant, a route in and a route out is what makes "reachable" a property
## something else can assert.
##
## The data itself is NOT here. Insurance answers what is pending, when it
## returns, and what a resolve does; FreeItemsView answers what to show. This
## controller only binds them and moves the player, because a surface that
## reimplemented those answers would be a second implementation of them.

const HIDEOUT_SCENE := "res://scenes/hideout.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _service: Node = null
var _ui: HideoutUI = null


func _ready() -> void:
	_bind_existing_ui()
	_connect_ui()
	refresh()


## Explicit injection, so a harness can drive the screen with fixtures and so
## nothing depends on an autoload being present in a test environment.
func set_meta_service(value: Node) -> void:
	_service = value
	refresh()


func bind_hideout(value: HideoutUI) -> void:
	_ui = value
	_connect_ui()
	refresh()


## Pull the owning pair straight from MetaService and hand the view to the
## surface. Guarded: a hideout opened before the service exists shows an empty
## list rather than a crash, because "no free items yet" and "the service is not
## up" must not look the same to a player.
func refresh() -> void:
	if _ui == null or _service == null:
		return
	_ui.bind(_service.profile, _service.insurance)


func _connect_ui() -> void:
	if _ui == null:
		return
	if not _ui.resolve_requested.is_connected(_on_resolve_requested):
		_ui.resolve_requested.connect(_on_resolve_requested)


## Resolve what is DUE, through the owning API, and re-render from its result.
## It does not decide that a claim may be resolved -- Insurance does that -- and it
## reports what happened rather than assuming a return happened.
func _on_resolve_requested() -> void:
	if _service == null:
		return
	var returned: Array = _service.insurance.process_returns(_service.profile)
	if _service.has_method("save"):
		_service.save()
	refresh()
	# `returned` is deliberately not turned into a sentence here: the surface
	# re-reads the view, and inventing a message would be a second source of truth
	# for what happened. If the game later wants a toast, it comes from the
	# claim_returned signal that Insurance already emits.


func return_to_menu() -> void:
	# Cached and null-checked rather than a chained get_tree() deref: INV-38a
	# ratchets chained get_tree() call sites, and this file added one. The fix is
	# the pattern operations_hub_controller already uses, not a loosened baseline.
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.change_scene_to_file(MAIN_MENU_SCENE)


func _bind_existing_ui() -> void:
	if _ui != null:
		return
	for child in get_children():
		if child is HideoutUI:
			_ui = child as HideoutUI
			return
	_bind_existing_ui_deep(self)


## The UI is a child of the scene root, not necessarily a direct child, so the
## lookup walks the tree rather than assuming the shape. Found on first _ready.
func _bind_existing_ui_deep(node: Node) -> void:
	for child in node.get_children():
		if child is HideoutUI:
			_ui = child as HideoutUI
			return
		_bind_existing_ui_deep(child)
