extends Control
## Main menu: title + Jogar / Configurações / Sair. Settings panel edits a
## live dict: volumes apply instantly to the GameAudio buses, display applies
## on change, everything persists to user://settings.cfg on Voltar.
## UI clicks via shared GameAudio (UI bus pool).

const HUB_SCENE := "res://scenes/operations_hub.tscn"

var audio: GameAudio
var settings: Dictionary
var _sliders: Dictionary = {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio = GameAudio.new()
	audio.name = "GameAudio"
	add_child(audio)
	settings = SettingsStore.load_all()
	SettingsStore.apply_volumes(settings)
	($Menu/BtnPlay as Button).pressed.connect(_on_play)
	($Menu/BtnPlay as Button).pressed.connect(audio.play_ui)
	($Menu/BtnHub as Button).pressed.connect(_on_hub)
	($Menu/BtnHub as Button).pressed.connect(audio.play_ui)
	($Menu/BtnSettings as Button).pressed.connect(_on_open_settings)
	($Menu/BtnSettings as Button).pressed.connect(audio.play_ui)
	($Menu/BtnQuit as Button).pressed.connect(_on_quit)
	($Menu/BtnQuit as Button).pressed.connect(audio.play_ui)
	_setup_settings()

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/arena_blockout.tscn")

func _on_hub() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func _on_quit() -> void:
	get_tree().quit()

# ─── settings screen ───

func _setup_settings() -> void:
	# Profiler scope (src/dev/profiler): script-side UI build work. Engine-side
	# container layout is inside process_total and is not script-scopable.
	ProfilerRecorder.begin(&"ui_layout")
	_sliders = {
		"SliderSens": "sensitivity", "SliderMaster": "vol_master",
		"SliderSfx": "vol_sfx", "SliderUi": "vol_ui", "SliderAmb": "vol_ambient",
		"SliderPix": "pixelation",
	}
	for slider_name in _sliders:
		var slider := _find_slider(slider_name)
		slider.value = float(settings[_sliders[slider_name]])
		slider.value_changed.connect(_on_slider.bind(slider_name))
	_refresh_value_labels()
	var opt := $SettingsPanel/Margin/Box/RowRes/OptRes as OptionButton
	for r in SettingsStore.RESOLUTIONS:
		opt.add_item("%dx%d" % [r.x, r.y])
	opt.selected = _res_index(Vector2i(settings["resolution"]))
	opt.item_selected.connect(_on_resolution)
	var check := $SettingsPanel/Margin/Box/RowFull/CheckFull as CheckButton
	check.button_pressed = bool(settings["fullscreen"])
	check.toggled.connect(_on_fullscreen)
	var opt_mode := $SettingsPanel/Margin/Box/RowMode/OptMode as OptionButton
	opt_mode.add_item("FFA", 0)
	opt_mode.add_item("TDM", 1)
	opt_mode.selected = 1 if String(settings["match_mode"]) == "tdm" else 0
	opt_mode.item_selected.connect(_on_match_mode)
	($SettingsPanel/Margin/Box/BtnBack as Button).pressed.connect(_on_back)
	($SettingsPanel/Margin/Box/BtnBack as Button).pressed.connect(audio.play_ui)
	ProfilerRecorder.end()

func _on_match_mode(idx: int) -> void:
	settings["match_mode"] = "tdm" if idx == 1 else "ffa"

func _find_slider(slider_name: String) -> HSlider:
	# Rows are named RowXxx; slider path is deterministic.
	var row := slider_name.trim_prefix("Slider")
	var rows := {"Sens": "RowSens", "Master": "RowMaster", "Sfx": "RowSfx",
		"Ui": "RowUi", "Amb": "RowAmb", "Pix": "RowPix"}
	return get_node("SettingsPanel/Margin/Box/%s/%s" % [rows[row], slider_name]) as HSlider

func _on_slider(_value: float, slider_name: String) -> void:
	settings[_sliders[slider_name]] = _value
	SettingsStore.apply_volumes(settings) # live feedback on the buses
	SettingsStore.apply_display(settings) # pixelation previews instantly
	_refresh_value_labels()

func _refresh_value_labels() -> void:
	($SettingsPanel/Margin/Box/RowSens/ValSens as Label).text = "%.2f" % float(settings["sensitivity"])
	($SettingsPanel/Margin/Box/RowPix/ValPix as Label).text = "%d%%" % int(float(settings["pixelation"]) * 100.0)
	var vol_keys := {"Master": "vol_master", "Sfx": "vol_sfx",
		"Ui": "vol_ui", "Amb": "vol_ambient"}
	for row in vol_keys:
		(get_node("SettingsPanel/Margin/Box/Row%s/Val%s" % [row, row]) as Label).text = "%d dB" % int(settings[vol_keys[row]])

func _res_index(res: Vector2i) -> int:
	for i in range(SettingsStore.RESOLUTIONS.size()):
		if SettingsStore.RESOLUTIONS[i] == res:
			return i
	return 0

func _on_resolution(idx: int) -> void:
	settings["resolution"] = SettingsStore.RESOLUTIONS[idx]
	SettingsStore.apply_display(settings)

func _on_fullscreen(on: bool) -> void:
	settings["fullscreen"] = on
	SettingsStore.apply_display(settings)

func _on_open_settings() -> void:
	($Menu as Control).visible = false
	($SettingsPanel as Control).visible = true

func _on_back() -> void:
	SettingsStore.save_all(settings)
	($SettingsPanel as Control).visible = false
	($Menu as Control).visible = true
