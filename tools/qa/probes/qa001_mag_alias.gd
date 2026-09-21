# tools/qa/probes/qa001_mag_alias.gd
# Reproducible probe for QA-001 (magazine aliasing / source-mag drain).
# Prints QA_RESULT=RESOLVED when ejecting from the installed feed does NOT
# change the source magazine, QA_RESULT=PRESENT when it does. Run:
#   godot --headless --path . --script res://tools/qa/probes/qa001_mag_alias.gd
extends SceneTree

func _make_feed(rounds: int) -> AmmoFeed:
	var feed := AmmoFeed.new()
	feed.type = AmmoFeed.Type.EXTERNAL
	feed.compatible_calibers = PackedStringArray(["9x19mm"])
	for i in rounds:
		var a := Ammo.create_9mm_ammo()
		a.caliber = "9x19mm"
		feed.insert(a)
	return feed

func _initialize() -> void:
	var source := _make_feed(3)
	var before := source.contents.size()

	var weapon := Weapon.new()
	weapon.feed_type = AmmoFeed.Type.EXTERNAL
	weapon.ammo_feed = source

	var incoming := _make_feed(3)
	var swapped := WeaponSystem.change_magazine(weapon, incoming)

	# change_magazine chambers one round; drain whatever the installed feed holds.
	while weapon.ammo_feed != null and not weapon.ammo_feed.is_empty():
		weapon.ammo_feed.eject()

	var after := source.contents.size()
	print("QA001 swapped=%s source_before=%d source_after=%d" % [str(swapped), before, after])
	print("QA_RESULT=RESOLVED" if (swapped and after == before) else "QA_RESULT=PRESENT")
	quit()
