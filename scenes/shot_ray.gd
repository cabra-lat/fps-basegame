class_name ShotRay
extends RefCounted
## Defense-in-depth for resolver rays: never hit the shooter or ANY viewmodel
## body. The addon owns viewmodel lifecycle, including the leaked "ghost"
## left behind on weapon switch (player-rig), so a single current_hands walk
## is not enough. Every "WeaponModel" subtree in the tree is tagged into the
## "viewmodel" group, and all of those CollisionObject3D RIDs are excluded.
## Cheap: one small tree walk per shot, immune to reference leaks.

const GROUP := "viewmodel"
const VM_NAME := "WeaponModel"

## RIDs to exclude for [player] (any CollisionObject3D): its own body, every
## tagged viewmodel body, and — as a same-frame safety net before tagging —
## the held subtree. Pass rescan=true to re-tag WeaponModel nodes first;
## scenes call the cheaper group+subtree path per shot and rescan on equip.
static func collect(player: Node, scene: Node, rescan: bool = false) -> Array[RID]:
	if rescan:
		register(scene)
	var rids: Array[RID] = []
	if player is CollisionObject3D:
		_push_rid(rids, (player as CollisionObject3D).get_rid())
	var tree := scene.get_tree()
	if tree:
		for n in tree.get_nodes_in_group(GROUP):
			if n is CollisionObject3D:
				_push_rid(rids, (n as CollisionObject3D).get_rid())
	var hands: Node = player.get("current_hands") if player != null else null
	if hands != null and is_instance_valid(hands):
		_collect_subtree(hands, rids)
	return rids

## Tag every WeaponModel-ish node (and its children) into GROUP.
static func register(scene: Node) -> void:
	_register(scene)

## Tag every WeaponModel-ish node (and its children) into GROUP. Godot
## auto-renames duplicates to WeaponModel2/@WeaponModel@…, so match by
## substring, not equality. Scans from the tree root so a leaked ghost
## reparented anywhere still gets caught.
static func _register(scene: Node) -> void:
	var tree := scene.get_tree()
	if tree == null or tree.root == null:
		return
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).contains(VM_NAME):
			_tag_subtree(n)
		stack.append_array(n.get_children())

static func _tag_subtree(n: Node) -> void:
	if n is CollisionObject3D and not n.is_in_group(GROUP):
		n.add_to_group(GROUP)
	for c in n.get_children():
		_tag_subtree(c)

static func _collect_subtree(n: Node, rids: Array[RID]) -> void:
	if n is CollisionObject3D:
		_push_rid(rids, (n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_collect_subtree(c, rids)

static func _push_rid(rids: Array[RID], rid: RID) -> void:
	if not rid.is_valid():
		return
	for existing in rids:
		if existing == rid:
			return
	rids.append(rid)
