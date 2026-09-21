class_name SettingsStore
extends RefCounted
## Shared settings (menu <-> arena): persist user://settings.cfg, apply live.
## Sensitivity maps to PlayerConfig.mouse_sensitivity (read every frame by
## the controller, so arena applies it in _ready and it just works).
## Volumes map straight onto the GameAudio buses (Master + SFX/UI/Ambient).

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"sensitivity": 1.0,
	"vol_master": 0.0,
	"vol_sfx": 0.0,
	"vol_ui": -3.0,
	"vol_ambient": -16.0,
	"resolution": Vector2i(1280, 720),
	"fullscreen": false,
	"pixelation": 1.0, # viewport scaling_3d_scale; 1.0 = off, lower = PS1 chunk
	"match_mode": "ffa", # "ffa" | "tdm"
}

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
]

static func load_all() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return out
	for key in DEFAULTS:
		out[key] = cfg.get_value("settings", key, DEFAULTS[key])
	out["resolution"] = Vector2i(out["resolution"])
	return out

static func save_all(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		if s.has(key):
			cfg.set_value("settings", key, s[key])
	cfg.save(PATH)

static func apply_volumes(s: Dictionary) -> void:
	GameAudio.ensure_buses()
	for bus in ["Master", "SFX", "UI", "Ambient"]:
		var key: String = "vol_" + bus.to_lower()
		if not s.has(key):
			continue
		for i in range(AudioServer.bus_count):
			if AudioServer.get_bus_name(i) == bus:
				AudioServer.set_bus_volume_db(i, float(s[key]))

static func apply_display(s: Dictionary) -> void:
	var res := Vector2i(s.get("resolution", DEFAULTS["resolution"]))
	var root := _window()
	if root == null:
		return
	if bool(s.get("fullscreen", false)):
		root.mode = Window.MODE_FULLSCREEN
	else:
		root.mode = Window.MODE_WINDOWED
		root.size = res
	# PS1 pixelation: render below native res, upscale bilinear (cheap, chunky).
	var pix := clampf(float(s.get("pixelation", 1.0)), 0.25, 1.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = pix

static func bus_db(bus: String) -> float:
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == bus:
			return AudioServer.get_bus_volume_db(i)
	return 0.0

static func _window() -> Window:
	# Static context: reach the main window via any autoload-free path.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root
