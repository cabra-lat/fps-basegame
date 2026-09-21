class_name ViewSetup
extends RefCounted
## Scene-side first-person view setup, shared by arena_manager and debug_range
## (was copy-pasted in both). The addon owns body visibility/near-clip
## (PlayerBodyVisibility); scenes only collapse the third-person spring arm.
## Idempotent — PlayerBodyVisibility.apply() is also called deferred by the
## controller, so calling it here just makes the first frame correct.

static func configure_fps(player: Node) -> void:
	if player == null:
		return
	var spring := player.get_node_or_null("SpringArm3D") as SpringArm3D
	if spring != null:
		spring.spring_length = 0.1
	PlayerBodyVisibility.apply(player)
