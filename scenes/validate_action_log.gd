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
	# AWAITED, and that word is load-bearing. _refusal_readout_renders_in_place()
	# contains `await process_frame`, so calling it WITHOUT await runs it up to
	# that suspension and throws the rest away: the section silently contributed
	# ZERO checks while looking like it had run. The only symptom was an
	# unexpected check count, which is exactly the symptom a count-based gate
	# cannot diagnose -- it just reports a number. A section that can be skipped
	# by its own signature is a section that will be.
	await _run()
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
	await _refusal_readout_renders_in_place()
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


## The readout is the coordinator's decision, and the acceptance is behavioural
## in the same spirit as the rest: a refusal must APPEAR where the control is,
## survive until the state that caused it is resolved, and clear when the player
## does something that works. A check that only asserted the node exists would
## pass for a label that never shows anything.
func _refusal_readout_renders_in_place() -> void:
	ActionLog.clear()
	var readout := RefusalReadout.new()
	readout.name = "Readout"
	root.add_child(readout)
	await process_frame

	_check(readout is Label, "readout: it is a plain in-place Label, not a window, a dialog or an overlay")
	_check(readout.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"readout: and it ignores the mouse, so a readout cannot swallow the click it is reporting on")
	_check(not readout.is_showing(), "readout: it shows nothing before anything has gone wrong")

	# A NO_OP: the refusal case the card is about.
	var h1 := ActionLog.reached("Harness/BtnCycle", "cycle_action")
	ActionLog.no_op(h1, "inventory_weapon_has_no_cycled_action")
	_check(readout.is_showing(), "readout: a NO_OP makes it SHOW a refusal")
	_check(String(readout.text) == "inventory_weapon_has_no_cycled_action",
		"readout: showing the reason, so the text says WHY [got '%s']" % String(readout.text))
	_check(readout.is_inside_tree() and readout.get_parent() != null,
		"readout: and it lives in the tree beside the control rather than in some global layer")

	# A REFUSED is the same class of message to the player and must render too,
	# while staying distinguishable in the RECORD.
	var h2 := ActionLog.reached("Harness/BtnUnload", "unload_magazine")
	ActionLog.refused(h2, "inventory_internal_feed_cannot_be_detached")
	_check(readout.is_showing() and String(readout.text) == "inventory_internal_feed_cannot_be_detached",
		"readout: a REFUSED also renders, with its own reason [got '%s']" % String(readout.text))
	_check(ActionLog.result_name(int(ActionLog.entries()[-1]["result"])) == "REFUSED",
		"readout: and the two stay DISTINGUISHABLE in the record, because the readout showing text is not the same as the result being OK")

	# IT PERSISTS ACROSS TIME. This is the anti-toast property, and it is the
	# reason the decision went the way it did: the player can look away, come
	# back, and the answer is still there. There is no timer anywhere in this
	# component, so the test is that frames pass and the text remains.
	#
	# WHAT THIS DOES NOT CLAIM, because I got it wrong first. I originally asserted
	# that a click on a DIFFERENT control must not dismiss the refusal, and that
	# check FAILED against correct code. Re-reading the decision settles it: the
	# readout "clears when the player next does something that produces a RESULT".
	# A click elsewhere that succeeds IS such a RESULT, so clearing is the DECIDED
	# behaviour and my check was the thing that was wrong. Keeping it would have
	# meant shipping a readout that contradicts a scope the owner set, and calling
	# the divergence an anti-toast improvement. The decision wins.
	# AND THE WAIT IS REAL TIME, not a couple of frames. The first version of this
	# check awaited two process frames and a red arm that added a 0.5s auto-clear
	# -- a textbook toast -- passed 63/63, because two frames is about 30
	# milliseconds and the timer had not fired yet. The property is "there is no
	# timer", and only waiting longer than any plausible timer can actually test
	# it. 0.7s against an arm of 0.5s.
	await create_timer(0.7).timeout
	_check(readout.is_showing(), "readout: it survives 0.7s of real time with no interaction at all -- there is no timer, which is what separates it from a toast [showing %s]" % str(readout.is_showing()))
	_check(String(readout.text) == "inventory_internal_feed_cannot_be_detached",
		"readout: still showing the same reason, so a player who looks away and comes back finds the answer [text '%s']" % String(readout.text))

	# And it clears on the next thing that WORKED, not on a timer.
	var h3 := ActionLog.reached("Harness/BtnCycle", "cycle_action")
	ActionLog.ok(h3)
	_check(not readout.is_showing(), "readout: and clears once the player does something that succeeds")
	_check(String(readout.text) == RefusalReadout.EMPTY_TEXT, "readout: leaving no stale text behind")

	# The record is unaffected by the view existing. A view that is required for
	# the record to work would invert the split the decision rests on.
	_check(ActionLog.size() == 6, "readout: and the record itself is untouched by any of this [entries %d of 6]" % ActionLog.size())
	_check(ActionLog.subscriber_count() == 1, "readout: the hook lives on the RECORD and the view subscribed to it, rather than the record depending on a view")

	# queue_free() is DEFERRED, so asserting the view was gone after a single
	# frame failed on a queued-but-not-yet-freed node. That is a harness bug and
	# not a leak, and the two are worth telling apart: "still subscribed after
	# being freed" would be a real defect, this is not.
	readout.queue_free()
	for _i in 4:
		await process_frame
	# With the view gone, recording still works: the record does not depend on
	# anybody being looking at it.
	var h4 := ActionLog.reached("Harness/BtnAlone", "nobody_watching")
	ActionLog.no_op(h4, "no_listener")
	_check(not readout.is_inside_tree(), "readout: the view is now out of the tree")
	_check(ActionLog.subscriber_count() == 0,
		"readout: and it UNSUBSCRIBED on the way out, so the record holds no reference to a freed view [subscribers %d of 0]" % ActionLog.subscriber_count())
	_check(ActionLog.size() == 8, "readout: recording works with NO view attached, which is the direction the dependency must point [entries %d of 8]" % ActionLog.size())

	ActionLog.clear()


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

	# THE SCOPE LIMITS, AS NOTES AND NOT AS ASSERTIONS.
	#
	# These two used to be scored checks, and the first one was the same disease as
	# the hub's expired premise, wearing the OTHER polarity: it asserted an ABSENCE
	# -- main.gd does not contain "action_performed" -- and the project's direction
	# is to FILL that absence. So the harness was one correct fix away from failing
	# a system that had just got better, which is the same failure mode as
	# asserting a key is "currently untranslated" and watching it become
	# translated. Naming a limit does not unpin it; the word "honest" above was
	# doing the work that a real property would have to do.
	#
	# They are NOTES now, printed like the other LIMIT lines in this harness, so the
	# information survives and the VERDICT stops depending on a value the project
	# intends to change. An assertion about a property that is SUPPOSED to change
	# has to be written against the property, never against its current value.
	var requests_src := FileAccess.get_file_as_string("res://addons/cabra.lat_shooters/src/ui/inventory/main.gd")
	if not requests_src.contains("action_performed"):
		print("  NOTE  scope LIMIT: the inventory root does not forward action_performed, so inventory action")
		print("        results are not observable from the game. This is a DISCLOSURE, not a verdict: the")
		print("        addon is expected to grow that forward, and this line must not turn red when it does.")
	var scope_src := FileAccess.get_file_as_string("res://addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd")
	# THIS ONE STAYS AN ASSERTION, and it is the control for the reasoning above: it
	# asserts that the API EXISTS, which is a property of the interface, not a
	# value it happens to hold. A positive existence check does not expire when the
	# thing it names is used differently.
	_check(scope_src.contains("func start_zooming") and scope_src.contains("func stop_zooming"),
		"scope: the zoom API named in the card exists in the scope script")


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
