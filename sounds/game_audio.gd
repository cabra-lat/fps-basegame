class_name GameAudio
extends Node
## Fase 2 audio: runtime buses (Master/SFX/UI/Ambient), one-shot pools
## (never a single shared player), staged gun/reload layers, ambient loop.
## One instance per scene (arena, menu); call ensure_buses() first so all
## instances share the same bus layout. All streams CC0, see SOUNDS.md.

const BLAST := preload("res://sounds/sfx_rifle_blast.wav")
const MECH := preload("res://sounds/sfx_rifle_mech.mp3")
const TAIL := preload("res://sounds/sfx_rifle_tail.wav")
const MAG_OUT := preload("res://sounds/sfx_reload_mag_out.mp3")
const MAG_IN := preload("res://sounds/sfx_reload_mag_in.mp3")
const CHARGING := preload("res://sounds/sfx_reload_charging.mp3")
const FLESH := preload("res://sounds/sfx_impact_flesh.ogg")
const STEEL := preload("res://sounds/sfx_impact_steel.wav")
const STEP_CONCRETE := preload("res://sounds/sfx_step_concrete.ogg")
const STEP_DIRT := preload("res://sounds/sfx_step_dirt.ogg")
const UI_CLICK := preload("res://sounds/sfx_ui_click.wav")
const WIND := preload("res://sounds/amb_wind_loop.mp3")

const POOL_2D := 8
const POOL_3D := 8

var _bus_sfx := "SFX"
var _bus_ui := "UI"
var _bus_ambient := "Ambient"

var _p2d: Array[AudioStreamPlayer] = []
var _i2d := 0
var _p3d: Array[AudioStreamPlayer3D] = []
var _i3d := 0
var _pui: Array[AudioStreamPlayer] = []
var _iui := 0
var _ambient: AudioStreamPlayer
## Audit counters (P0): prove the fireplace actually reached the mixer.
var shots_played := 0
var reloads_played := 0
var malfunctions_played := 0
var malfunction_clears_played := 0

static func ensure_buses() -> void:
	for spec in [["SFX", 0.0], ["UI", -3.0], ["Ambient", -16.0]]:
		var bus_name: String = spec[0]
		var found := -1
		for i in range(AudioServer.bus_count):
			if AudioServer.get_bus_name(i) == bus_name:
				found = i
				break
		if found == -1:
			AudioServer.add_bus()
			found = AudioServer.bus_count - 1
			AudioServer.set_bus_name(found, bus_name)
			AudioServer.set_bus_send(found, "Master")
		AudioServer.set_bus_volume_db(found, spec[1])

func _ready() -> void:
	ensure_buses()
	for i in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		p.bus = _bus_sfx
		add_child(p)
		_p2d.append(p)
	for i in range(POOL_3D):
		var p := AudioStreamPlayer3D.new()
		p.bus = _bus_sfx
		p.max_distance = 120.0
		add_child(p)
		_p3d.append(p)
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = _bus_ui
		add_child(p)
		_pui.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = _bus_ambient
	_ambient.stream = WIND
	_ambient.volume_db = -6.0
	_ambient.finished.connect(_on_ambient_finished)
	add_child(_ambient)

# ─── one-shot core (round-robin pools) ───

func _play2d(stream: AudioStream, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if _p2d.is_empty():
		return
	var p := _p2d[_i2d]
	_i2d = (_i2d + 1) % _p2d.size()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func _play3d(stream: AudioStream, pos: Vector3, vol_db: float = 0.0) -> void:
	if _p3d.is_empty():
		return
	var p := _p3d[_i3d]
	_i3d = (_i3d + 1) % _p3d.size()
	p.global_position = pos
	p.stream = stream
	p.volume_db = vol_db
	p.play()

func _later(delay: float, fn: Callable) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(self) and is_inside_tree():
		fn.call()

# ─── gameplay API (wired by scenes) ───

## Rifle shot: mech + blast now, tail +120 ms quieter (SOUNDS.md layering).
func play_shot() -> void:
	shots_played += 1
	_play2d(MECH, -4.0)
	_play2d(BLAST, 0.0)
	_later(0.12, func() -> void: _play2d(TAIL, -8.0))

## Reload staged across the 2.2 s M4 reload_time: out @ .3, in @ 1.2, charge @ 1.9.
func play_reload() -> void:
	reloads_played += 1
	_later(0.3, func() -> void: _play2d(MAG_OUT, -2.0))
	_later(1.2, func() -> void: _play2d(MAG_IN, -2.0))
	_later(1.9, func() -> void: _play2d(CHARGING, -2.0))

func play_step(dirt: bool = false) -> void:
	_play3d(STEP_DIRT if dirt else STEP_CONCRETE, _feet_pos(), -10.0)

## Weapon malfunction (jam/stovepipe/misfire): the metallic mechanism voice
## pitched per kind so the three failures are audibly distinct.
func play_malfunction(kind: int = 0) -> void:
	malfunctions_played += 1
	var pitch := 0.7
	match kind:
		2: pitch = 0.82 # STOVEPIPE
		3: pitch = 0.6 # MISFIRE
	_play2d(MECH, -5.0, pitch)

## Malfunction cleared: a crisp charging-handle rack.
func play_malfunction_cleared() -> void:
	malfunction_clears_played += 1
	_play2d(CHARGING, -3.0, 1.15)

func play_hit_flesh(pos: Vector3) -> void:
	_play3d(FLESH, pos, -2.0)

func play_hit_steel(pos: Vector3) -> void:
	_play3d(STEEL, pos, -4.0)

func play_ui() -> void:
	if _pui.is_empty():
		return
	var p := _pui[_iui]
	_iui = (_iui + 1) % _pui.size()
	p.stream = UI_CLICK
	p.volume_db = -6.0
	p.play()

func start_ambient() -> void:
	if _ambient and not _ambient.playing:
		_ambient.play()

func stop_ambient() -> void:
	if _ambient and _ambient.playing:
		_ambient.stop()

func _on_ambient_finished() -> void:
	# Loop any stream type (mp3 loop flags vary); replay is gapless enough
	# for wind at -22 dB effective.
	if is_instance_valid(self) and is_inside_tree():
		_ambient.play()

func _feet_pos() -> Vector3:
	var scene := get_tree().current_scene
	var stack: Array = [scene] if scene else []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is PlayerController:
			return (n as Node3D).global_position
		stack.append_array(n.get_children())
	return Vector3.ZERO
