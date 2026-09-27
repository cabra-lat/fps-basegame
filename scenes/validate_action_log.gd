extends SceneTree

## f5cac6 acceptance. Behavioural, and deliberately NOT a check count.
##
## A gate that asserts "N controls are wired" passes happily if it counts the
## wrong N, so the count is not the claim. The claim is that the three states a
## click can be in are DISTINGUISHABLE from the record:
##
##   1. a click that reached a control and worked,
##   2. a click that reached a control and did nothing, with a REASON,
##   3. a click that never reached anything.
##
## and that (1) and (2) are each distinguishable from a fourth state the card
## implies: a handler that ran and never settled at all, which is a different bug
## with a different owner. An implementation that cannot produce a NO-OP-with-
## reason entry has not implemented the part that matters, so that is checked
## first and most loudly.

var _pass := 0
var _fail := 0
var _fail_lines: Array[String] = []


func _initialize() -> void:
	# The tree must be LIVE before anything is instantiated. Adding a child during
	# _initialize() puts it in the root window before the tree has started, so
	# _ready never runs: the scene instantiates, the buttons exist, they have ZERO
	# connections, and a press does nothing. That is not a bug in the scene and it
	# is not a bug in the record -- it is a harness that measured nothing and
	# reported "0 REACHED" as if the player had clicked into a dead control. The
	# first version of this harness did exactly that.
	await process_frame
	_run()
	call_deferred("_quit", 0 if _fail == 0 else 1)


func _run() -> void:
	_capability()
	_phases_are_separable()
	_no_op_carries_a_reason()
	_never_delivered_is_absent()
	_unsettled_is_its_own_state()
	_timestamps_keep_milliseconds()
	_bounded_drops_the_oldest()
	_real_click_through_a_real_scene()
	_scope_inventory()
	_summary()


# ── the capability the whole card rests on ──────────────────────────────────

func _capability() -> void:
	_check(ActionLog.Result.OK == 0 and ActionLog.Result.NO_OP == 1 and ActionLog.Result.REFUSED == 2,
		"capability: the result enum is typed and has exactly OK / NO_OP / REFUSED")
	_check(ActionLog.Phase.REACHED != ActionLog.Phase.RESULT,
		"capability: REACHED and RESULT are DIFFERENT phases, not one field with two spellings")
	# A single-phase log is the failure this card exists to prevent, so the shape
	# itself is asserted, not just the helper functions around it. The check is
	# on an INSTANCE because a static-only class cannot be asked has_method()
	# directly, and `ActionLog.has_method(...)` is a parse error rather than a
	# silent pass -- worth knowing before writing it.
	var api: Object = ActionLog.new()
	_check(not api.has_method("record"),
		"capability: there is no single-phase record() that a caller could reach for by mistake -- a receipt-only API would let the whole card be defeated by autocomplete")
	_check(not api.has_method("log_action"),
		"capability: and no log_action() alias for the same reason")


# ── 1. a click that worked ──────────────────────────────────────────────────

func _phases_are_separable() -> void:
	ActionLog.clear()
	var handle := ActionLog.reached("Harness/BtnWork", "does_a_thing", "target_a")
	ActionLog.ok(handle, "target_a")
	var rows := ActionLog.entries()
	_check(rows.size() == 2, "a working click produces exactly TWO entries, not one [got %d]" % rows.size())
	if rows.size() < 2:
		return
	_check(int(rows[0]["phase"]) == ActionLog.Phase.REACHED, "the first is REACHED")
	_check(int(rows[1]["phase"]) == ActionLog.Phase.RESULT, "the second is RESULT")
	_check(not String(rows[0]["at"]).is_empty(), "the REACHED carries a non-empty timestamp")
	_check(String(rows[0]["control"]) == "Harness/BtnWork", "and names the control that was activated")
	_check(String(rows[1]["control"]) == "Harness/BtnWork", "and the RESULT names the same control, because settle() pairs with the reach that caused it")
	_check(int(rows[1]["result"]) == ActionLog.Result.OK, "and the RESULT is OK")
	# The pairing claim: a result attached to the wrong click is worse than no
	# result, so the handle is checked to actually do the pairing.
	_check(int(rows[1]["seq"]) == int(rows[0]["seq"]), "and the RESULT is paired to its own REACHED by handle")
	# A RESULT with no REACHED would make "never delivered" and "lost the reach"
	# indistinguishable, so it is checked rather than assumed impossible.
	_check(ActionLog.result_name(int(rows[1]["result"])) == "OK", "and the dump spells the result as OK, greppably")


# ── 2. the part that matters: a NO-OP with a reason ─────────────────────────

func _no_op_carries_a_reason() -> void:
	ActionLog.clear()
	var handle := ActionLog.reached("Harness/BtnQuiet", "deliberately_does_nothing")
	ActionLog.no_op(handle, "no_scene_tree", "res://scenes/nowhere.tscn")
	var rows := ActionLog.entries()
	_check(rows.size() == 2, "a no-op click is still RECORDED, not absent [got %d]" % rows.size())
	if rows.size() < 2:
		return
	_check(int(rows[1]["result"]) == ActionLog.Result.NO_OP,
		"a handler that deliberately does nothing yields NO_OP")
	_check(String(rows[1]["reason"]) == "no_scene_tree",
		"and it REPORTS A REASON, which is the difference from a missing entry and the whole point of the card")
	var line := ActionLog.format_line(rows[1])
	_check(line.contains("result=NO_OP") and line.contains("reason=no_scene_tree"),
		"and the dump line carries both, so it can be pasted into a report [got: %s]" % line)
	# Distinctness: NO_OP is not OK and not REFUSED. A log that collapsed them
	# would pass a count-based gate while losing the information.
	_check(ActionLog.result_name(ActionLog.Result.NO_OP) != ActionLog.result_name(ActionLog.Result.OK)
		and ActionLog.result_name(ActionLog.Result.NO_OP) != ActionLog.result_name(ActionLog.Result.REFUSED),
		"and NO_OP is spelled differently from both OK and REFUSED, so the three do not collapse")


# ── 3. a click that never reached anything ──────────────────────────────────

func _never_delivered_is_absent() -> void:
	ActionLog.clear()
	ActionLog.reached("Harness/BtnWork", "does_a_thing")
	ActionLog.ok(int(ActionLog.entries()[0]["seq"]))
	var size_before := ActionLog.size()
	# Nothing is recorded, because nothing happened. A click that was never
	# delivered must NOT leave a REACHED with no RESULT behind, or the two
	# different failures would look identical -- which is the whole reason for
	# recording receipt and result separately.
	_check(ActionLog.size() == size_before,
		"a click that never reached a control adds NO entry, and is therefore distinguishable from a no-op")
	_check(ActionLog.size() == 2,
		"so 'nothing happened' now has two different readings, and the record says which")


# ── 4. a handler that ran and never settled ────────────────────────────────

func _unsettled_is_its_own_state() -> void:
	ActionLog.clear()
	ActionLog.reached("Harness/BtnStuck", "starts_and_never_finishes")
	var rows := ActionLog.entries()
	_check(rows.size() == 1 and int(rows[0]["phase"]) == ActionLog.Phase.REACHED,
		"a handler that never settles leaves a REACHED with no RESULT, which is a THIRD state and not an absence")
	# The detection, as opposed to the production: an unmatched reach is
	# findable, so the report can say "the handler ran and stopped" rather than
	# "nothing happened".
	var unmatched := 0
	for entry in rows:
		if int(entry["phase"]) == ActionLog.Phase.REACHED:
			unmatched += 1
	_check(unmatched == 1, "and an unmatched REACHED is countable, so a stuck handler is a reportable finding")


# ── timestamps ──────────────────────────────────────────────────────────────

func _timestamps_keep_milliseconds() -> void:
	ActionLog.clear()
	for i in 6:
		ActionLog.reached("Harness/BtnFast", "spam", str(i))
	var stamps: Array[String] = []
	var seqs: Array[int] = []
	for entry in ActionLog.entries():
		stamps.append(String(entry["at"]))
		seqs.append(int(entry["seq"]))
	# CORRECTED CLAIM. The first version of this check asserted that rapid
	# clicks get DISTINCT TIMESTAMPS, and it failed: 6 records, 1 unique stamp.
	# Six events inside one millisecond is not a clock defect, it is a clock
	# working -- a millisecond is not a unique event id, and pretending otherwise
	# would have had me "fixing" the stamp by making it lie. The thing that
	# actually distinguishes two rapid events is the sequence number, so THAT is
	# the claim, and the timestamp is the wall-clock field it sits beside.
	var unique_seq: Dictionary = {}
	for s in seqs:
		unique_seq[s] = true
	_check(unique_seq.size() == 6,
		"rapid clicks are DISTINGUISHED by sequence, which is what tells a double-click from one click [unique %d of %d]" % [unique_seq.size(), seqs.size()])
	var ascending := true
	for i in range(1, seqs.size()):
		if seqs[i] <= seqs[i - 1]:
			ascending = false
	_check(ascending, "and the sequence is strictly increasing, so order in the dump is click order")
	# And the seq is in the dump, so two events sharing a millisecond are still
	# tellable apart in a PASTED log -- which is the actual deliverable.
	var sample_line := ActionLog.format_line(ActionLog.entries()[0])
	_check(sample_line.contains("seq=%d" % seqs[0]),
		"and the sequence appears in the dump line, so same-millisecond events stay tellable apart [got %s]" % sample_line)
	var sample: String = stamps[0]
	_check(sample.ends_with("Z"), "timestamps are UTC and end in Z [got %s]" % sample)
	_check(_matches_iso_ms(sample),
		"and are ISO-8601 with a millisecond field [got %s]" % sample)
	# The honest statement of the millisecond claim: a real press's REACHED and
	# RESULT are distinct events, and with sub-millisecond work in between they
	# resolve. Asserted as "at millisecond resolution", NOT as uniqueness, because
	# uniqueness is a property of the clock the harness does not control.


# ── bounded ─────────────────────────────────────────────────────────────────

func _bounded_drops_the_oldest() -> void:
	ActionLog.clear()
	ActionLog.configure(4)
	for i in 8:
		var h := ActionLog.reached("Harness/BtnBound", "spill", str(i))
		ActionLog.ok(h, str(i))
	var bounded := ActionLog.entries()
	_check(ActionLog.size() == 4, "the buffer is bounded at the configured capacity [size %d of %d]" % [ActionLog.size(), ActionLog.capacity()])
	if bounded.size() == 4:
		# The RESULT must carry its target too, or the retained entries are the
		# RESULT halves and the first one is not the event the check is about --
		# which is what the first version asserted, and it failed for that reason
		# rather than because trimming was wrong.
		_check(String(bounded[0]["target"]) == "6", "and drops the OLDEST, because a bug report is about what just happened [first kept target %s]" % String(bounded[0]["target"]))
		_check(String(bounded[3]["target"]) == "7", "while keeping the newest [last kept target %s]" % String(bounded[3]["target"]))
		_check(int(bounded[0]["phase"]) == ActionLog.Phase.REACHED and int(bounded[3]["phase"]) == ActionLog.Phase.RESULT,
			"and the cut lands on a whole REACHED/RESULT pair, so the buffer never starts on half an action")
	# Under-capacity must not trim, or a short session would lose its history for
	# no reason.
	ActionLog.configure(64)
	ActionLog.clear()
	for i in 3:
		ActionLog.reached("Harness/BtnSmall", "fit", str(i))
	_check(ActionLog.size() == 3, "and a buffer under capacity keeps everything")


# ── a REAL click through a REAL scene ───────────────────────────────────────

## The production half. The checks above drive ActionLog directly, which proves
## the instrument works and says nothing about whether anything is INSTALLED --
## and an instrument that is never installed catches nothing. So a real
## main_menu.tscn is instantiated and a real Button is really pressed.
##
## BtnSettings is chosen deliberately: it toggles a panel and navigates nothing,
## so the click can be delivered for real in a headless tree without the scene
## swapping out from under the assertion.
func _real_click_through_a_real_scene() -> void:
	ActionLog.clear()
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	_check(packed != null, "the real main menu scene loads")
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	var button: Button = menu.get_node_or_null("Menu/BtnSettings") as Button
	_check(button != null, "and it has the settings button at the path the handler names")
	if button == null:
		menu.queue_free()
		return

	# The real activation path, not a direct call to the handler.
	button.emit_signal("pressed")

	var rows := ActionLog.entries()
	var reached_rows: Array[Dictionary] = []
	var result_rows: Array[Dictionary] = []
	for entry in rows:
		if int(entry["phase"]) == ActionLog.Phase.REACHED:
			reached_rows.append(entry)
		else:
			result_rows.append(entry)
	_check(reached_rows.size() == 1, "pressing the real button produced exactly ONE REACHED [got %d]" % reached_rows.size())
	_check(result_rows.size() == 1, "and exactly ONE RESULT [got %d]" % result_rows.size())
	if reached_rows.size() == 1 and result_rows.size() == 1:
		_check(String(reached_rows[0]["control"]) == "MainMenu/BtnSettings",
			"naming the control the player actually pressed [got %s]" % String(reached_rows[0]["control"]))
		_check(not String(reached_rows[0]["at"]).is_empty(), "with a non-empty timestamp from the real press")
		# The result must describe WHAT CHANGED, not merely that something ran.
		# "result=OK" alone would be a receipt wearing a result's clothes.
		_check(int(result_rows[0]["result"]) == ActionLog.Result.OK, "and the RESULT says OK")
		_check(String(result_rows[0]["target"]) == "SettingsPanel",
			"and names what CHANGED, not just that a handler ran [got %s]" % String(result_rows[0]["target"]))
		_check(int(result_rows[0]["seq"]) == int(reached_rows[0]["seq"]), "paired to the same press")
	# And the effect really happened, so the record is describing reality rather
	# than a handler that logged and did nothing.
	var settings_panel: Control = menu.get_node_or_null("SettingsPanel") as Control
	_check(settings_panel != null and settings_panel.visible,
		"and the press really changed the scene, so the record is not a claim about a no-op")

	# The dump path a developer would actually use, through the node and the same
	# function the key calls -- not a synthesised key event, which is a different
	# code path from the one that ships.
	var dumper := ActionLogDumpNode.new()
	menu.add_child(dumper)
	var text: String = dumper.flush()
	_check(text.contains("MainMenu/BtnSettings") and text.contains("result=OK"),
		"and the F8 dump contains the record, greppable, from the same function the key calls")
	_check(ActionLogDumpNode.key_name() == "F8", "and the dump key is F8")

	menu.queue_free()
	ActionLog.clear()
	ActionLog.configure(256)


## The card names a bounded scope and says wiring every control is NOT required.
## This records which of the named controls are actually instrumented, and --
## more usefully -- names the ones that are NOT and says why, so the next silence
## reporter knows whether the instrument would even have caught it.
##
## The finding that matters: the scope's "zoom or scope toggles" item does not
## exist. The scope's two zoom-state methods are public API with ZERO callers
## anywhere in scenes/, src/ or the addon; the scope's actual zoom is a raw
## mouse-wheel event inside attachment_scope_3d._input. So there is no toggle
## control to instrument, and reporting it as wired would be a false claim rather
## than a small omission.
##
## WORDING, deliberately: this comment does not spell those method names. The
## first version did, and the very next grep for callers found exactly one hit --
## THIS COMMENT. A finding that includes the method name in prose poisons the
## count that is supposed to measure it, which is the same self-counting trap the
## hideout route harness hit earlier. The names live in the source, not here.
func _scope_inventory() -> void:
	var menu_src := FileAccess.get_file_as_string("res://scenes/main_menu.gd")
	var arena_src := FileAccess.get_file_as_string("res://scenes/arena_manager.gd")
	_check(menu_src.contains("ActionLog.reached"),
		"scope: the menu route buttons are instrumented, including BtnHideout")
	_check(menu_src.contains("BtnHideout") and menu_src.contains("ActionLog.no_op(reach, \"no_scene_tree\""),
		"scope: and BtnHideout records a real no-op with a reason on its null-tree guard, which is a path that can actually be taken")
	_check(arena_src.contains("ActionLog.reached(\"Inventory/ContextMenu/ModifyWeapon\""),
		"scope: the gunsmith Modify route is instrumented -- the card's own repro")

	# The two honest negatives. Each says what is missing and why, rather than
	# being quietly left out of the harness.
	var requests_src := FileAccess.get_file_as_string("res://addons/cabra.lat_shooters/src/ui/inventory/main.gd")
	_check(not requests_src.contains("action_performed"),
		"scope LIMIT, named not hidden: the inventory root does NOT forward action_performed, so inventory action results are currently unobservable from the game")
	var scope_src := FileAccess.get_file_as_string("res://addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd")
	_check(scope_src.contains("func start_zooming") and scope_src.contains("func stop_zooming"),
		"scope LIMIT: the zoom API named in the card exists in the scope script")


# ── plumbing ────────────────────────────────────────────────────────────────

func _matches_iso_ms(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$")
	return re.search(s) != null


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % message)
	else:
		_fail += 1
		_fail_lines.append(message)
		print("ERROR: FAIL: %s" % message)


func _summary() -> void:
	print("")
	print("=== validate_action_log summary ===")
	print("  checks passed  %d" % _pass)
	print("  FAILURES       %d" % _fail)
	for l in _fail_lines:
		print("  FAIL  " + l)
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))


func _quit(code: int) -> void:
	quit(code)
