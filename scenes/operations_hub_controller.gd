class_name OperationsHubController
extends Node
## Persistent route adapter for the operations hub.
##
## The hub owns presentation and emits an opaque UI loadout id. Meta owns the
## selection registry's contents, validation, deployment, and persistence. This
## node only binds those boundaries and routes scene changes. It deliberately
## does not inspect or mutate ItemCodec data.

signal deploy_started(loadout_id: String)
signal deploy_rejected(loadout_id: String, reason: String)
signal arena_launch_requested(loadout_id: String)
signal report_routed(summary: String)
signal hub_return_requested

const HUB_SCENE := "res://scenes/operations_hub.tscn"
const DEFAULT_ARENA_SCENE := "res://scenes/arena_blockout.tscn"

@export var arena_scene_path := DEFAULT_ARENA_SCENE
@export var auto_route := true

var meta_service: Node
var hub: OperationsHubUI
var selection_registry: Dictionary = {}

var _awaiting_report := false
var _launching := false
var _meta_explicit := false


func _ready() -> void:
	if not _meta_explicit:
		meta_service = get_node_or_null("/root/Meta") as Node
	_connect_meta()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_bind_existing_hub")


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_disconnect_meta()


## Bind (or replace) the MetaService implementation. Meta owns this reference;
## the adapter only calls its public deploy boundary.
func set_meta_service(value: Node) -> void:
	_disconnect_meta()
	_meta_explicit = true
	meta_service = value
	_connect_meta()
	_apply_meta_snapshot()


## Inject the Meta-owned UI-id -> canonical selection map. The map is routing
## configuration, not persistence. Each value must be the shape accepted by
## MetaService.validate_deploy(): {primary: [ItemCodec dict], secondary: [...]}.
func set_selection_registry(value: Dictionary) -> void:
	selection_registry = value.duplicate(true)


func get_selection(loadout_id: String) -> Variant:
	return selection_registry.get(loadout_id, null)


func bind_hub(value: OperationsHubUI) -> void:
	if hub == value:
		return
	if hub != null:
		_disconnect_hub()
	hub = value
	if hub == null:
		return
	hub.deploy_requested.connect(_on_deploy_requested)
	hub.return_to_hub_requested.connect(_on_hub_return_requested)
	_apply_meta_snapshot()


## Public route hook for a player/arena flow that wants to return explicitly.
## It is safe to call when the hub is already active.
func return_to_hub() -> void:
	_awaiting_report = false
	hub_return_requested.emit()
	if auto_route and get_tree() != null:
		get_tree().change_scene_to_file(HUB_SCENE)


func _connect_meta() -> void:
	if meta_service == null:
		return
	if meta_service.has_signal("profile_loaded") and not meta_service.is_connected("profile_loaded", _on_profile_loaded):
		meta_service.connect("profile_loaded", _on_profile_loaded)
	if meta_service.has_signal("report_ready") and not meta_service.is_connected("report_ready", _on_report_ready):
		meta_service.connect("report_ready", _on_report_ready)


func _disconnect_meta() -> void:
	if meta_service == null:
		return
	if meta_service.has_signal("profile_loaded") and meta_service.is_connected("profile_loaded", _on_profile_loaded):
		meta_service.disconnect("profile_loaded", _on_profile_loaded)
	if meta_service.has_signal("report_ready") and meta_service.is_connected("report_ready", _on_report_ready):
		meta_service.disconnect("report_ready", _on_report_ready)


func _disconnect_hub() -> void:
	if hub == null:
		return
	if hub.deploy_requested.is_connected(_on_deploy_requested):
		hub.deploy_requested.disconnect(_on_deploy_requested)
	if hub.return_to_hub_requested.is_connected(_on_hub_return_requested):
		hub.return_to_hub_requested.disconnect(_on_hub_return_requested)


func _on_node_added(node: Node) -> void:
	if node is OperationsHubUI:
		bind_hub(node as OperationsHubUI)


func _bind_existing_hub() -> void:
	if get_tree() == null:
		return
	var current := get_tree().current_scene
	if current is OperationsHubUI:
		bind_hub(current as OperationsHubUI)


func _on_profile_loaded(_profile: Variant = null) -> void:
	_apply_meta_snapshot()


func _on_report_ready(summary: String) -> void:
	if not _awaiting_report:
		return
	_awaiting_report = false
	_launching = false
	report_routed.emit(summary)
	if auto_route and get_tree() != null:
		get_tree().change_scene_to_file(HUB_SCENE)


func _apply_meta_snapshot() -> void:
	if hub == null or meta_service == null:
		return
	var profile_value = meta_service.get("profile")
	if profile_value is PlayerProfile:
		hub.set_profile(profile_value as PlayerProfile)
		if profile_value is MetaProfile:
			hub.set_last_report((profile_value as MetaProfile).last_report)


func _on_hub_return_requested() -> void:
	return_to_hub()


func _on_deploy_requested(loadout_id: String) -> void:
	if _launching:
		deploy_rejected.emit(loadout_id, "launch already in progress")
		return
	var selection = get_selection(loadout_id)
	if not selection is Dictionary:
		deploy_rejected.emit(loadout_id, "unknown loadout id")
		return
	if meta_service == null or not meta_service.has_method("validate_deploy") or not meta_service.has_method("deploy_loadout"):
		deploy_rejected.emit(loadout_id, "MetaService deploy boundary unavailable")
		return

	var validation = meta_service.call("validate_deploy", selection)
	if not validation is Dictionary or not bool((validation as Dictionary).get("ok", false)):
		deploy_rejected.emit(loadout_id, String((validation as Dictionary).get("reason", "loadout rejected")) if validation is Dictionary else "loadout rejected")
		return
	var deployment = meta_service.call("deploy_loadout", selection)
	if not deployment is Dictionary or not bool((deployment as Dictionary).get("ok", false)):
		deploy_rejected.emit(loadout_id, String((deployment as Dictionary).get("reason", "deploy rejected")) if deployment is Dictionary else "deploy rejected")
		return

	_launching = true
	_awaiting_report = true
	deploy_started.emit(loadout_id)
	arena_launch_requested.emit(loadout_id)
	if auto_route and get_tree() != null:
		get_tree().change_scene_to_file(arena_scene_path)
