class_name Footsteps
extends RefCounted
## Distance-based footstep cadence while walking, shared by arena_manager and
## debug_range (was copy-pasted in both). Owns its own accumulator; call
## tick() from _physics_process only (AGENTS.md rule 4).

const STRIDE := 2.4 ## metres of travel per step
const MIN_SPEED := 1.5 ## below this (or airborne) the cadence resets

var step_acc := 0.0

func tick(audio: GameAudio, player: Node, delta: float) -> void:
	if audio == null or player == null:
		return
	var v: Vector3 = player.velocity
	v.y = 0.0
	if not player.is_on_floor() or v.length() < MIN_SPEED:
		step_acc = 0.0
		return
	step_acc += v.length() * delta
	if step_acc >= STRIDE:
		step_acc = 0.0
		audio.play_step(false)
