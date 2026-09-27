class_name RefusalReadout
extends Label

## In-place refusal text, owned by the control that produced it (coordinator's
## decision, 2026-09-27). NOT a toast, and the reason is the design rather than
## the aesthetic.
##
## A toast is transient and global: it answers a question the player did not ask,
## it appears wherever the camera happens to be pointing rather than where the
## player is looking, and it disappears before it can be read if they were not
## watching at the time. A REFUSAL is the answer to an action the player just
## took, so it belongs where they are looking and it belongs there for as long as
## the state that caused it. "Cycle action" on a one-mode weapon says so next to
## the control; an unload that leaves an empty magazine says that where the
## magazine is shown; an extract refused because the feed is empty says that
## where the feed is shown.
##
## WHY IT IS A SEPARATE CLASS RATHER THAN PART OF THE RECORD. ActionLog is the
## permanent typed contract: REACHED and RESULT, in place, no presentation
## opinions. This is a VIEW onto it. Any lane may later replace this readout with
## a better presentation without touching a single emitted signal -- which is the
## same split the impact-result card already uses, and the reason the signal can
## outlive any particular visual treatment. The moment this node becomes the
## thing people depend on, the split has been broken and the presentation needs
## rebuilding as a first-class thing rather than quietly promoted.
##
## NOT A NOTIFICATION CENTRE. It does not queue, it does not persist across
## scenes, and it holds exactly one line: the latest refusal. Anything that
## accumulates history here has become a different product.

## Shown when there is no refusal. Empty rather than a caption, because a caption
## that is only sometimes true trains people to ignore the label.
const EMPTY_TEXT := ""

## How long a refusal stays after it is superseded. The decision was "as long as
## the state that caused it", and no state here can be observed changing except
## by a new action, so the refusal clears on the next RESULT rather than on a
## timer. A timer would be the toast behaviour wearing this component's clothes.
@export var clear_on_next_result := true


func _ready() -> void:
	# A Label is not a Button and does not want the mouse; a readout that eats
	# clicks would be an instrument that perturbs the thing it measures.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	text = EMPTY_TEXT
	ActionLog.subscribe(_on_result_recorded)


func _exit_tree() -> void:
	# Unsubscribed on the way out. A freed view left in the subscriber list would
	# be called into on the next result, and the failure would surface as a
	# crash in whatever happened to record something next -- which is the least
	# informative place it could possibly surface.
	ActionLog.unsubscribe(_on_result_recorded)


## Show a refusal line. `reason` is a catalogue key, NOT finished copy: the
## control that owns the readout resolves it, because a view that translated its
## own strings would be a second translation authority and translation is already
## the thing ItemNames exists to stop happening twice.
func show_reason(reason: String, resolved_text: String = "") -> void:
	if reason.is_empty():
		clear_readout()
		return
	text = resolved_text if not resolved_text.is_empty() else reason
	visible = true


func clear_readout() -> void:
	text = EMPTY_TEXT
	visible = false


## True when this readout is currently showing a refusal, which is what the
## acceptance checks rather than the mere existence of the node.
func is_showing() -> bool:
	return visible and not String(text).is_empty()


func _on_result_recorded(entry: Dictionary) -> void:
	var result := int(entry.get("result", -1))
	if result == ActionLog.Result.NO_OP or result == ActionLog.Result.REFUSED:
		# A NO_OP and a REFUSED are both "you asked, here is why not", and the
		# decision names both. They stay distinguishable in the record by the
		# result field, which the dump prints; the readout shows the reason,
		# which is the part the player needs.
		show_reason(String(entry.get("reason", "")))
		return
	if clear_on_next_result:
		# Cleared on the next thing that WORKED, not on the next click: a refusal
		# describing a state that has since been resolved is worse than no
		# refusal, because it is now a false statement about the world.
		clear_readout()
