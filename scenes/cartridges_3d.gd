@tool
extends Node3D

class_name AmmunitionDemo

const BULLET_SHADER = "res://addons/cabra.lat_shooters/src/shaders/cartridges/cartridge.gdshader"

# Font atlas configuration
const STAMP_FONT_PATH = "res://addons/cabra.lat_shooters/asset/cartridge-font.png"
const STAMP_CONFIG = {
  "cells_per_row": 16,
  "cells_per_col": 16,
  "cells_width": 32,
  "cells_height": 32
}

# Ammunition database - real-world specifications
const AMMO_DATABASE = {
  "5.56x45mm NATO": {
    "land_diameter_mm": 5.56,
    "bullet_diameter_mm": 5.70,
    "neck_diameter_mm": 6.43,
    "shoulder_diameter_mm": 9.00,
    "head_diameter_mm": 9.58,  # Changed from base_diameter_mm
    "rim_diameter_mm": 9.60,
    "rim_thickness_mm": 1.27,  # Added missing parameter
    "case_length_mm": 44.70,
    "overall_length_mm": 57.40,
    "primer_diameter_mm": 3.0,
    "bullet_base_percent": 0.1,
    "bullet_tip_percent": 0.7,
    "ogive_radius_factor": 1.2,
    "tip_profile": 1,
    "neck_percent": 0.90,  # Added missing parameter
    "shoulder_percent": 0.85,  # Added missing parameter
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
    "stamp_text": "5.56 NATO",
    "stamp_depth": 0.0002,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  "7.62x51mm NATO": {
    "land_diameter_mm": 7.62,
    "bullet_diameter_mm": 7.82,
    "neck_diameter_mm": 8.53,
    "shoulder_diameter_mm": 11.53,
    "head_diameter_mm": 11.84,  # Changed from base_diameter_mm
    "rim_diameter_mm": 11.94,
    "rim_thickness_mm": 1.40,  # Added
    "case_length_mm": 51.18,
    "overall_length_mm": 69.85,
    "primer_diameter_mm": 3.8,
    "bullet_base_percent": 0.12,
    "bullet_tip_percent": 0.65,
    "ogive_radius_factor": 1.3,
    "tip_profile": 1,
    "neck_percent": 0.88,
    "shoulder_percent": 0.80,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
    "stamp_text": "7.62 NATO",
    "stamp_depth": 0.0002,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  "9x19mm Parabellum": {
    "land_diameter_mm": 9.00,
    "bullet_diameter_mm": 9.02,
    "neck_diameter_mm": 9.65,
    "shoulder_diameter_mm": 9.93,
    "head_diameter_mm": 9.93,  # Changed from base_diameter_mm
    "rim_diameter_mm": 9.96,
    "rim_thickness_mm": 1.27,
    "case_length_mm": 19.15,
    "overall_length_mm": 29.69,
    "primer_diameter_mm": 2.8,
    "bullet_base_percent": 0.15,
    "bullet_tip_percent": 0.6,
    "ogive_radius_factor": 1.1,
    "tip_profile": 3,
    "neck_percent": 0.95,
    "shoulder_percent": 0.90,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.65, 0.35, 0.15),
    "stamp_text": "9mm LUGER",
    "stamp_depth": 0.00015,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  ".45 ACP": {
    "land_diameter_mm": 11.43,
    "bullet_diameter_mm": 11.48,
    "neck_diameter_mm": 12.09,
    "shoulder_diameter_mm": 12.09,
    "head_diameter_mm": 12.09,  # Changed from base_diameter_mm
    "rim_diameter_mm": 12.19,
    "rim_thickness_mm": 1.40,
    "case_length_mm": 22.81,
    "overall_length_mm": 32.39,
    "primer_diameter_mm": 3.0,
    "bullet_base_percent": 0.2,
    "bullet_tip_percent": 0.55,
    "ogive_radius_factor": 1.0,
    "tip_profile": 3,
    "neck_percent": 0.95,
    "shoulder_percent": 0.90,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.6, 0.3, 0.1),
    "stamp_text": ".45 ACP",
    "stamp_depth": 0.00015,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  ".50 BMG": {
    "land_diameter_mm": 12.70,
    "bullet_diameter_mm": 13.01,
    "neck_diameter_mm": 14.22,
    "shoulder_diameter_mm": 18.79,
    "head_diameter_mm": 20.42,  # Changed from base_diameter_mm
    "rim_diameter_mm": 20.42,
    "rim_thickness_mm": 1.80,
    "case_length_mm": 99.31,
    "overall_length_mm": 138.43,
    "primer_diameter_mm": 5.0,
    "bullet_base_percent": 0.08,
    "bullet_tip_percent": 0.75,
    "ogive_radius_factor": 1.5,
    "tip_profile": 1,
    "neck_percent": 0.85,
    "shoulder_percent": 0.75,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.75, 0.45, 0.25),
    "stamp_text": ".50 BMG",
    "stamp_depth": 0.0003,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  "7.62x39mm Soviet": {
    "land_diameter_mm": 7.62,
    "bullet_diameter_mm": 7.92,
    "neck_diameter_mm": 8.60,
    "shoulder_diameter_mm": 10.07,
    "head_diameter_mm": 11.35,  # Changed from base_diameter_mm
    "rim_diameter_mm": 11.35,
    "rim_thickness_mm": 1.50,
    "case_length_mm": 38.70,
    "overall_length_mm": 56.00,
    "primer_diameter_mm": 3.2,
    "bullet_base_percent": 0.15,
    "bullet_tip_percent": 0.6,
    "ogive_radius_factor": 1.1,
    "tip_profile": 1,
    "neck_percent": 0.90,
    "shoulder_percent": 0.82,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
    "stamp_text": "7.62x39",
    "stamp_depth": 0.0002,
    "stamp_color": Color(0.3, 0.3, 0.3),
  },
  "7.62x54mmR": {
    "land_diameter_mm": 7.62,
    "bullet_diameter_mm": 7.92,
    "neck_diameter_mm": 8.53,
    "shoulder_diameter_mm": 11.61,
    "head_diameter_mm": 12.37,  # Changed from base_diameter_mm
    "rim_diameter_mm": 14.48,
    "rim_thickness_mm": 1.60,
    "case_length_mm": 53.72,
    "overall_length_mm": 77.16,
    "primer_diameter_mm": 3.8,
    "bullet_base_percent": 0.1,
    "bullet_tip_percent": 0.7,
    "ogive_radius_factor": 1.3,
    "tip_profile": 1,
    "neck_percent": 0.87,
    "shoulder_percent": 0.78,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
  },
  "7.62x25mm Tokarev": {
    "land_diameter_mm": 7.62,
    "bullet_diameter_mm": 7.85,
    "neck_diameter_mm": 8.50,
    "shoulder_diameter_mm": 9.96,
    "head_diameter_mm": 9.96,  # Changed from base_diameter_mm
    "rim_diameter_mm": 9.96,
    "rim_thickness_mm": 1.20,
    "case_length_mm": 25.10,
    "overall_length_mm": 34.30,
    "primer_diameter_mm": 2.8,
    "bullet_base_percent": 0.2,
    "bullet_tip_percent": 0.5,
    "ogive_radius_factor": 0.9,
    "tip_profile": 3,
    "neck_percent": 0.95,
    "shoulder_percent": 0.92,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
  },
  "12 Gauge Buckshot": {
    "land_diameter_mm": 18.53,
    "bullet_diameter_mm": 18.53,
    "neck_diameter_mm": 18.53,
    "shoulder_diameter_mm": 18.53,
    "head_diameter_mm": 18.53,  # Changed from base_diameter_mm
    "rim_diameter_mm": 22.45,
    "rim_thickness_mm": 1.80,
    "case_length_mm": 70.00,
    "overall_length_mm": 71.00,
    "primer_diameter_mm": 6.1,
    "bullet_base_percent": 0.9,
    "bullet_tip_percent": 0.95,
    "ogive_radius_factor": 0.8,
    "tip_profile": 3,
    "neck_percent": 0.98,
    "shoulder_percent": 0.98,
    "case_color": Color(0.95, 0.95, 0.95),
    "bullet_color": Color(0.3, 0.3, 0.3),
    "stamp_text": "12 GA",
  },
  "12 Gauge Slug": {
    "land_diameter_mm": 18.53,
    "bullet_diameter_mm": 18.53,
    "neck_diameter_mm": 18.53,
    "shoulder_diameter_mm": 18.53,
    "head_diameter_mm": 18.53,  # Changed from base_diameter_mm
    "rim_diameter_mm": 22.45,
    "rim_thickness_mm": 1.80,
    "case_length_mm": 70.00,
    "overall_length_mm": 75.00,
    "primer_diameter_mm": 6.1,
    "bullet_base_percent": 0.7,
    "bullet_tip_percent": 0.8,
    "ogive_radius_factor": 1.2,
    "tip_profile": 3,
    "neck_percent": 0.98,
    "shoulder_percent": 0.98,
    "case_color": Color(0.5, 0, 0),
    "bullet_color": Color(0.5, 0.4, 0.3),
  },
  "20 Gauge": {
    "land_diameter_mm": 15.63,
    "bullet_diameter_mm": 15.63,
    "neck_diameter_mm": 15.63,
    "shoulder_diameter_mm": 15.63,
    "head_diameter_mm": 15.63,  # Changed from base_diameter_mm
    "rim_diameter_mm": 19.69,
    "rim_thickness_mm": 1.60,
    "case_length_mm": 70.00,
    "overall_length_mm": 70.00,
    "primer_diameter_mm": 6.1,
    "bullet_base_percent": 0.9,
    "bullet_tip_percent": 0.95,
    "ogive_radius_factor": 0.8,
    "tip_profile": 0,
    "neck_percent": 0.98,
    "shoulder_percent": 0.98,
    "case_color": Color(1.0, 0, 0),
    "bullet_color": Color(0.3, 0.3, 0.3),
  },
  ".357 Magnum": {
    "land_diameter_mm": 9.07,
    "bullet_diameter_mm": 9.06,
    "neck_diameter_mm": 9.68,
    "shoulder_diameter_mm": 9.68,
    "head_diameter_mm": 9.68,  # Changed from base_diameter_mm
    "rim_diameter_mm": 11.18,
    "rim_thickness_mm": 1.50,
    "case_length_mm": 33.00,
    "overall_length_mm": 39.00,
    "primer_diameter_mm": 3.0,
    "bullet_base_percent": 0.25,
    "bullet_tip_percent": 0.5,
    "ogive_radius_factor": 1.0,
    "tip_profile": 3,
    "neck_percent": 0.95,
    "shoulder_percent": 0.95,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.65, 0.35, 0.15),
  },
  ".44 Magnum": {
    "land_diameter_mm": 10.90,
    "bullet_diameter_mm": 10.89,
    "neck_diameter_mm": 11.61,
    "shoulder_diameter_mm": 11.61,
    "head_diameter_mm": 11.61,  # Changed from base_diameter_mm
    "rim_diameter_mm": 13.06,
    "rim_thickness_mm": 1.60,
    "case_length_mm": 32.78,
    "overall_length_mm": 40.90,
    "primer_diameter_mm": 3.0,
    "bullet_base_percent": 0.2,
    "bullet_tip_percent": 0.5,
    "ogive_radius_factor": 1.0,
    "tip_profile": 3,
    "neck_percent": 0.95,
    "shoulder_percent": 0.95,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.6, 0.3, 0.1),
  },
  "5.7x28mm": {
    "land_diameter_mm": 5.70,
    "bullet_diameter_mm": 5.70,
    "neck_diameter_mm": 6.35,
    "shoulder_diameter_mm": 7.80,
    "head_diameter_mm": 7.80,  # Changed from base_diameter_mm
    "rim_diameter_mm": 7.80,
    "rim_thickness_mm": 1.10,
    "case_length_mm": 28.80,
    "overall_length_mm": 40.50,
    "primer_diameter_mm": 2.7,
    "bullet_base_percent": 0.1,
    "bullet_tip_percent": 0.7,
    "ogive_radius_factor": 1.2,
    "tip_profile": 1,
    "neck_percent": 0.92,
    "shoulder_percent": 0.85,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.75, 0.45, 0.25),
  },
  ".300 Blackout": {
    "land_diameter_mm": 7.62,
    "bullet_diameter_mm": 7.82,
    "neck_diameter_mm": 8.43,
    "shoulder_diameter_mm": 9.60,
    "head_diameter_mm": 9.60,  # Changed from base_diameter_mm
    "rim_diameter_mm": 9.60,
    "rim_thickness_mm": 1.40,
    "case_length_mm": 35.10,
    "overall_length_mm": 57.40,
    "primer_diameter_mm": 3.0,
    "bullet_base_percent": 0.1,
    "bullet_tip_percent": 0.7,
    "ogive_radius_factor": 1.3,
    "tip_profile": 1,
    "neck_percent": 0.90,
    "shoulder_percent": 0.83,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
  },
  "6.5mm Creedmoor": {
    "land_diameter_mm": 6.50,
    "bullet_diameter_mm": 6.71,
    "neck_diameter_mm": 7.34,
    "shoulder_diameter_mm": 11.53,
    "head_diameter_mm": 11.94,  # Changed from base_diameter_mm
    "rim_diameter_mm": 11.94,
    "rim_thickness_mm": 1.50,
    "case_length_mm": 48.77,
    "overall_length_mm": 72.39,
    "primer_diameter_mm": 3.8,
    "bullet_base_percent": 0.08,
    "bullet_tip_percent": 0.75,
    "ogive_radius_factor": 1.4,
    "tip_profile": 1,
    "neck_percent": 0.86,
    "shoulder_percent": 0.78,
    "case_color": Color(0.8, 0.6, 0.2),
    "bullet_color": Color(0.7, 0.4, 0.2),
  }
}

# Export variables for stamps
var stamp_enabled: bool = true
var stamp_text_override: String = "":
  set(value):
    stamp_text_override = value
    # Convert text to ASCII codes
    var stamp_codes = []
    for i in range(value.length()):
      stamp_codes.append(value.unicode_at(i))

    # Pad array to 20 elements with zeros
    while stamp_codes.size() < 20:
      stamp_codes.append(0)

    if Engine.is_editor_hint() and has_node("MainBullet"):
      var material = $MainBullet.mesh.material
      if material:
        # Set stamp parameters
        material.set_shader_parameter("stamp_characters", value.length())
        material.set_shader_parameter("stamp_name", stamp_codes)

var stamp_depth_override: float = 0.0001
var stamp_ring_inner_override: float = 0.00
var stamp_ring_outer_override: float = 0.92
var stamp_char_scale_override: float = 0.49

# Export variables for easy editing in inspector
var current_ammo_index: int = 0:
  set(value):
    current_ammo_index = value % AMMO_DATABASE.size()
    if Engine.is_editor_hint() and has_node("MainBullet"):
      current_ammo_name = AMMO_DATABASE.keys()[current_ammo_index]
      apply_ammo_type(current_ammo_name)

var bullet_extraction: float = 100.0 * 1000.0:
  set(value):
    bullet_extraction = value
    if Engine.is_editor_hint() and has_node("MainBullet"):
      var material = $MainBullet.mesh.material
      if material:
        material.set_shader_parameter("bullet_extraction_mm", value)

var bullet_time: float = 0.5

# Performance optimization settings
var max_ejected_casings: int = 8
var casing_lifetime: float = 3.0
var use_low_poly_casings: bool = true
var disable_casing_shadows: bool = true
var casing_lod_distance: float = 20.0

# Current ammo type
var current_ammo_name = ""
var ejected_casings = []

# Scene nodes
@onready var main_bullet = $MainBullet
@onready var camera = $Camera3D
@onready var ui_label = $UI/Label

# FPS Counter
@onready var fps_label = $UI/FPSCounter
var fps_counter_enabled: bool = true

# Control settings
var camera_speed: float = 200.0
var rotation_speed: float = 1.5
var smooth_rotation: bool = true

# Performance tracking
var frame_count: int = 0
var last_fps_update: float = 0.0
var current_fps: int = 0

# Low-poly mesh for casings
var low_poly_bullet_mesh: Mesh
var ejected_case_material: Material


# Input state tracking
var input_state = {
  "move_forward": false,
  "move_backward": false,
  "move_left": false,
  "move_right": false,
  "move_up": false,
  "move_down": false,
  "rotate_cam_left": false,
  "rotate_cam_right": false,
  "rotate_obj_up": false,
  "rotate_obj_down": false,
  "rotate_obj_left": false,
  "rotate_obj_right": false
}

func _ready():
  if Engine.is_editor_hint():
    _setup_scene()

  # Pre-create low-poly mesh if needed
  if use_low_poly_casings:
    _create_low_poly_mesh()

  # Load the first ammo type
  current_ammo_name = AMMO_DATABASE.keys()[current_ammo_index]
  apply_ammo_type(current_ammo_name)
  update_ui()

func _create_low_poly_mesh():
  # Create a much lower poly cylinder for ejected casings
  var cylinder = CylinderMesh.new()
  cylinder.top_radius = 0.01
  cylinder.bottom_radius = 0.01
  cylinder.height = 0.1
  cylinder.radial_segments = 16  # Reduced from 64
  cylinder.rings = 32            # Reduced from 128
  cylinder.cap_top = false
  cylinder.cap_bottom = false

  low_poly_bullet_mesh = cylinder

func _setup_scene():
  # Create main bullet if it doesn't exist
  if not has_node("MainBullet"):
    var bullet = create_bullet_mesh()
    bullet.name = "MainBullet"
    add_child(bullet)
    if Engine.is_editor_hint():
      bullet.owner = get_tree().edited_scene_root

  # Create camera if it doesn't exist
  if not has_node("Camera3D"):
    var cam = Camera3D.new()
    cam.name = "Camera3D"
    cam.position = Vector3(0, 0, 0.06)
    cam.fov = 60
    cam.near = 0.001
    add_child(cam)
    if Engine.is_editor_hint():
      cam.owner = get_tree().edited_scene_root

  # Create UI if it doesn't exist
  if not has_node("UI"):
    var ui = CanvasLayer.new()
    ui.name = "UI"
    add_child(ui)
    if Engine.is_editor_hint():
      ui.owner = get_tree().edited_scene_root

    var label = Label.new()
    label.name = "Label"
    label.position = Vector2(20, 20)
    label.size = Vector2(400, 150)
    label.add_theme_font_size_override("font_size", 20)
    label.add_theme_font_color_override("font_color", Color.BLACK)
    ui.add_child(label)
    if Engine.is_editor_hint():
      label.owner = get_tree().edited_scene_root

    # Create FPS counter
    var fps_label = Label.new()
    fps_label.name = "FPSCounter"
    fps_label.position = Vector2(20, 180)
    fps_label.size = Vector2(200, 30)
    fps_label.add_theme_font_size_override("font_size", 16)
    fps_label.add_theme_font_color_override("font_color", Color.BLACK)
    fps_label.text = "FPS: 0"
    ui.add_child(fps_label)
    if Engine.is_editor_hint():
      fps_label.owner = get_tree().edited_scene_root

func create_bullet_mesh(low_poly: bool = false) -> MeshInstance3D:
  var mesh_instance = MeshInstance3D.new()

  if low_poly and low_poly_bullet_mesh:
    mesh_instance.mesh = low_poly_bullet_mesh
  else:
    var cylinder = CylinderMesh.new()
    cylinder.top_radius = 0.01
    cylinder.bottom_radius = 0.01
    cylinder.height = 0.1
    cylinder.radial_segments = 64
    cylinder.rings = 128
    cylinder.cap_top = false
    cylinder.cap_bottom = false
    mesh_instance.mesh = cylinder

  # Create shader material
  var shader_material = ShaderMaterial.new()
  if ResourceLoader.exists(BULLET_SHADER):
    var shader = load(BULLET_SHADER)
    shader_material.shader = shader

    # Set up stamp font texture
    if ResourceLoader.exists(STAMP_FONT_PATH):
      var font_texture = load(STAMP_FONT_PATH)
      shader_material.set_shader_parameter("stamp_font", font_texture)

    # Set stamp configuration
    shader_material.set_shader_parameter("cells_per_row", STAMP_CONFIG.cells_per_row)
    shader_material.set_shader_parameter("cells_per_col", STAMP_CONFIG.cells_per_col)
    shader_material.set_shader_parameter("cells_width", STAMP_CONFIG.cells_width)
    shader_material.set_shader_parameter("cells_height", STAMP_CONFIG.cells_height)
  else:
    push_warning("Bullet shader not found at: " + BULLET_SHADER)

  mesh_instance.mesh.material = shader_material

  # Performance: Disable shadows for casings
  if disable_casing_shadows:
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

  return mesh_instance

func apply_ammo_type(ammo_name: String):
  if not AMMO_DATABASE.has(ammo_name):
    return

  var ammo_data = AMMO_DATABASE[ammo_name]
  var material = main_bullet.mesh.material

  if material:
    # Apply all dimensions
    for key in ammo_data:
      if key != "case_color" and key != "bullet_color" and key != "stamp_text":
        material.set_shader_parameter(key, ammo_data[key])

    # Apply colors
    material.set_shader_parameter("case_color", ammo_data.get("case_color", Color(0.8, 0.6, 0.2)))
    material.set_shader_parameter("bullet_color", ammo_data.get("bullet_color", Color(0.7, 0.4, 0.2)))
    material.set_shader_parameter("scale", 1.0)

    # Apply stamp settings
    apply_stamp_settings(material, ammo_data)
  ejected_case_material = main_bullet.mesh.material.duplicate()
  ejected_case_material.set_shader_parameter("bullet_color", Color(0.0, 0.0, 0.0, 0.0))
  ejected_case_material.set_shader_parameter("bullet_tip_color", Color(0.0, 0.0, 0.0, 0.0))
  ejected_case_material.set_shader_parameter("bullet_base_color", Color(0.0, 0.0, 0.0, 0.0))
  ejected_case_material.set_shader_parameter("tracer_color", Color(0.0, 0.0, 0.0, 0.0))
  ejected_case_material.set_shader_parameter("bullet_extraction_mm", 0.0)
  current_ammo_name = ammo_name
  update_ui()

func apply_stamp_settings(material: ShaderMaterial, ammo_data: Dictionary):
  if not stamp_enabled:
    material.set_shader_parameter("stamp_characters", 0)
    return

  # Get stamp text from ammo data or use default
  var stamp_text = stamp_text_override if stamp_text_override else ammo_data.get("stamp_text", current_ammo_name)

  # Convert text to ASCII codes
  var stamp_codes = []
  for i in range(stamp_text.length()):
    stamp_codes.append(stamp_text.unicode_at(i))

  # Pad array to 20 elements with zeros
  while stamp_codes.size() < 20:
    stamp_codes.append(0)

  # Set stamp parameters
  material.set_shader_parameter("stamp_characters", stamp_text.length())
  material.set_shader_parameter("stamp_name", stamp_codes)

  # Use overrides if provided, otherwise use ammo-specific values
  material.set_shader_parameter("stamp_depth", stamp_depth_override if stamp_depth_override > 0 else ammo_data.get("stamp_depth", 0.0001))
  material.set_shader_parameter("stamp_ring_inner", stamp_ring_inner_override if stamp_ring_inner_override > 0 else ammo_data.get("stamp_ring_inner", 0.0))
  material.set_shader_parameter("stamp_ring_outer", stamp_ring_outer_override if stamp_ring_outer_override > 0 else ammo_data.get("stamp_ring_outer", 0.92))
  material.set_shader_parameter("stamp_char_scale", stamp_char_scale_override if stamp_char_scale_override > 0 else ammo_data.get("stamp_char_scale", 0.5))
  material.set_shader_parameter("stamp_radius_offset", 0.8)

func update_ui():
  if ui_label:
    var stamp_status = "ON" if stamp_enabled else "OFF"
    var perf_info = "Casings: %d/%d" % [ejected_casings.size(), max_ejected_casings]
    ui_label.text = "Current: %s\nStamp: %s\n%s\n\nControls:\n[1-9] Switch Ammo\n[,/.] Prev/Next Ammo\n[SPACE] Extract Bullet\n[ENTER] Eject Casing\n[R] Reset\n[T] Toggle Stamp\n[F] Toggle FPS Counter\n[WASD] Move Camera\n[Q/E] Rotate Camera\n[Arrow Keys] Rotate Object" % [current_ammo_name, stamp_status, perf_info]

func _input(event):
  # Handle discrete key presses
  if event is InputEventKey and event.is_pressed():
    if event.keycode == KEY_1: switch_ammo(0)
    if event.keycode == KEY_2: switch_ammo(1)
    if event.keycode == KEY_3: switch_ammo(2)
    if event.keycode == KEY_4: switch_ammo(3)
    if event.keycode == KEY_5: switch_ammo(4)
    if event.keycode == KEY_6: switch_ammo(5)
    if event.keycode == KEY_7: switch_ammo(6)
    if event.keycode == KEY_8: switch_ammo(7)
    if event.keycode == KEY_9: switch_ammo(8)
    if event.keycode == KEY_COMMA: switch_ammo(current_ammo_index-1)
    if event.keycode == KEY_PERIOD: switch_ammo(current_ammo_index+1)
    if event.keycode == KEY_SPACE: extract_bullet()
    if event.keycode == KEY_ENTER: eject_casing()
    if event.keycode == KEY_R: reset_scene()
    if event.keycode == KEY_T: toggle_stamp()
    if event.keycode == KEY_F: toggle_fps_counter()

  # Update input state for continuous movement
  if event is InputEventKey:
    match event.keycode:
      KEY_W:
        input_state["move_forward"] = event.is_pressed()
      KEY_S:
        input_state["move_backward"] = event.is_pressed()
      KEY_A:
        input_state["move_left"] = event.is_pressed()
      KEY_D:
        input_state["move_right"] = event.is_pressed()
      KEY_E:
        input_state["move_up"] = event.is_pressed()
      KEY_Q:
        input_state["move_down"] = event.is_pressed()
      KEY_LEFT:
        input_state["rotate_cam_left"] = event.is_pressed()
      KEY_RIGHT:
        input_state["rotate_cam_right"] = event.is_pressed()
      KEY_UP:
        input_state["rotate_obj_up"] = event.is_pressed()
      KEY_DOWN:
        input_state["rotate_obj_down"] = event.is_pressed()

func _process(delta):
  # Optimized FPS counter - update less frequently
  frame_count += 1
  last_fps_update += delta
  if last_fps_update >= 0.25:  # Update 4 times per second instead of every frame
    current_fps = Engine.get_frames_per_second()
    if fps_counter_enabled and fps_label:
      fps_label.text = "FPS: %d (Casings: %d)" % [current_fps, ejected_casings.size()]
    last_fps_update = 0.0
    frame_count = 0

  # Handle continuous camera movement
  handle_camera_movement(delta)

  # Handle continuous rotations
  handle_camera_rotation(delta)
  handle_object_rotation(delta)

  # Performance: Dynamic LOD for casings based on distance
  _update_casing_lod()

func _update_casing_lod():
  pass
  #if not camera or ejected_casings.is_empty():
    #return
  #
  #var camera_pos = camera.global_position
  #
  #for casing in ejected_casings:
    #if not is_instance_valid(casing):
      #continue
      #
    #var distance = casing.global_position.distance_to(camera_pos)
    #
    ## Performance: Disable casings that are too far
    #if distance > 10.0:  # 10 units away
      #casing.visible = false
    #else:
      #casing.visible = true
      #
      ## Simple LOD: Reduce visibility quality at distance
      #if distance > casing_lod_distance:
        ## At distance, we could reduce material quality, but for now just ensure it's visible
        #pass

func handle_camera_movement(delta):
  if not camera:
    return

  var movement = Vector3.ZERO

  # Camera-relative movement
  var camera_basis = camera.global_transform.basis

  if input_state["move_forward"]:
    movement -= camera_basis.z
  if input_state["move_backward"]:
    movement += camera_basis.z
  if input_state["move_left"]:
    movement -= camera_basis.x
  if input_state["move_right"]:
    movement += camera_basis.x
  if input_state["move_up"]:
    movement += camera_basis.y
  if input_state["move_down"]:
    movement -= camera_basis.y

  # Normalize and apply speed
  if movement.length_squared() > 0:
    movement = movement.normalized() * camera_speed * delta
    camera.global_translate(movement)

func handle_camera_rotation(delta):
  if not camera:
    return

  var rotation_delta = Vector3.ZERO

  if input_state["rotate_cam_left"]:
    rotation_delta.y += rotation_speed * delta
  if input_state["rotate_cam_right"]:
    rotation_delta.y -= rotation_speed * delta

  if rotation_delta.length_squared() > 0:
    if smooth_rotation:
      # Smooth rotation using quaternions
      var current_quat = camera.global_transform.basis.get_rotation_quaternion()
      var target_quat = current_quat * Quaternion(Vector3.UP, rotation_delta.y)
      camera.global_transform.basis = Basis(target_quat)
    else:
      # Direct rotation
      camera.rotate_y(rotation_delta.y)

func handle_object_rotation(delta):
  if not main_bullet:
    return

  var rotation_delta = Vector3.ZERO

  if input_state["rotate_obj_up"]:
    rotation_delta.x -= rotation_speed * delta
  if input_state["rotate_obj_down"]:
    rotation_delta.x += rotation_speed * delta
  if input_state["rotate_obj_left"]:
    rotation_delta.y += rotation_speed * delta
  if input_state["rotate_obj_right"]:
    rotation_delta.y -= rotation_speed * delta

  if rotation_delta.length_squared() > 0:
    if smooth_rotation:
      # Apply rotation in local space
      main_bullet.rotate_object_local(Vector3.RIGHT, rotation_delta.x)
      main_bullet.rotate_object_local(Vector3.UP, rotation_delta.y)
    else:
      # Direct rotation
      main_bullet.rotation.x += rotation_delta.x
      main_bullet.rotation.y += rotation_delta.y

func toggle_fps_counter():
  fps_counter_enabled = !fps_counter_enabled
  if fps_label:
    fps_label.visible = fps_counter_enabled

func toggle_stamp():
  stamp_enabled = not stamp_enabled
  apply_ammo_type(current_ammo_name)

func switch_ammo(index: int):
  current_ammo_index = index % AMMO_DATABASE.size()
  current_ammo_name = AMMO_DATABASE.keys()[current_ammo_index]
  apply_ammo_type(current_ammo_name)
  reset_scene()

func _set_bullet_extraction(value: float = 0.0):
  var material = main_bullet.mesh.material
  if material:
    material.set_shader_parameter("bullet_extraction_mm", value)

func eject_casing():
  # Performance: Limit number of casings
  if ejected_casings.size() >= max_ejected_casings:
    var oldest_casing = ejected_casings.pop_front()
    if is_instance_valid(oldest_casing):
      oldest_casing.queue_free()

  # Create a duplicate of the current bullet with low-poly mesh
  var ejected_bullet = create_bullet_mesh(use_low_poly_casings)
  ejected_bullet.rotation = main_bullet.rotation
  ejected_bullet.position = main_bullet.position
  # Share material to reduce draw calls
  ejected_bullet.mesh.material = ejected_case_material

  add_child(ejected_bullet)

  # Extract bullet from main casing
  extract_bullet()

  # Performance: Simplified animation with fewer properties
  var tween = create_tween()
  var start_pos = ejected_bullet.position
  var end_pos = start_pos + Vector3(
    randf_range(0.3, 0.6),
    randf_range(0.1, 0.3),
    randf_range(-0.2, 0.2)
  )

  # Only tween essential properties
  tween.parallel().tween_property(ejected_bullet, "position", end_pos, 0.5)
  tween.parallel().tween_property(ejected_bullet, "rotation",
    Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)), 0.5)

  # Scale down for performance
  ejected_bullet.scale = Vector3(0.7, 0.7, 0.7)

  ejected_casings.append(ejected_bullet)

  # Performance: Use shorter lifetime and auto-remove
  _start_casing_cleanup(ejected_bullet)

func _start_casing_cleanup(casing: MeshInstance3D):
  await get_tree().create_timer(casing_lifetime).timeout

  if is_instance_valid(casing) and ejected_casings.has(casing):
    # Fade out before removal
    var tween = create_tween()
    tween.tween_property(casing, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
    tween.tween_callback(casing.queue_free)
    ejected_casings.erase(casing)

func extract_bullet():
  var material = main_bullet.mesh.material
  if material:
    # Animate bullet extraction
    var tween = create_tween()
    tween.tween_method(_set_bullet_extraction, 0.0, bullet_extraction, bullet_time)\
       .finished.connect(_set_bullet_extraction)

func reset_scene():
  # Reset main bullet
  var material = main_bullet.mesh.material
  if material:
    material.set_shader_parameter("bullet_extraction_mm", 0.0)

  # Clear ejected casings with fade-out animation
  for casing in ejected_casings:
    if is_instance_valid(casing):
      var tween = create_tween()
      tween.tween_property(casing, "scale", Vector3(0.1, 0.1, 0.1), 0.2)
      tween.tween_callback(casing.queue_free)
  ejected_casings.clear()

# Tool function to automatically set up the scene in the editor
func _get_configuration_warnings():
  var warnings = PackedStringArray()

  if not has_node("MainBullet"):
    warnings.append("MainBullet node is missing. Run _setup_scene() in the editor.")

  if not ResourceLoader.exists(BULLET_SHADER):
    warnings.append("Bullet shader not found at: " + BULLET_SHADER)

  return warnings

# Export properties for the editor
func _get_property_list():
  var properties = []

  properties.append({
    "name": "Ammunition",
    "type": TYPE_NIL,
    "usage": PROPERTY_USAGE_CATEGORY
  })

  properties.append({
    "name": "current_ammo_index",
    "type": TYPE_INT,
    "hint": PROPERTY_HINT_ENUM,
    "hint_string": ",".join(AMMO_DATABASE.keys())
  })

  properties.append({
    "name": "bullet_extraction",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.0,100000.0,0.1"
  })

  # Add stamp properties
  properties.append({
    "name": "Stamp Settings",
    "type": TYPE_NIL,
    "usage": PROPERTY_USAGE_GROUP
  })

  properties.append({
    "name": "stamp_enabled",
    "type": TYPE_BOOL
  })

  properties.append({
    "name": "stamp_depth_override",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.0,0.001,0.00001"
  })

  properties.append({
    "name": "stamp_ring_inner_override",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.0,1.0,0.01"
  })

  properties.append({
    "name": "stamp_ring_outer_override",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.0,1.0,0.01"
  })

  properties.append({
    "name": "stamp_char_scale_override",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.1,2.0,0.01"
  })

  # Add performance settings group
  properties.append({
    "name": "Performance Settings",
    "type": TYPE_NIL,
    "usage": PROPERTY_USAGE_GROUP
  })

  properties.append({
    "name": "max_ejected_casings",
    "type": TYPE_INT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "1,50,1"
  })

  properties.append({
    "name": "casing_lifetime",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.5,10.0,0.1"
  })

  properties.append({
    "name": "use_low_poly_casings",
    "type": TYPE_BOOL
  })

  properties.append({
    "name": "disable_casing_shadows",
    "type": TYPE_BOOL
  })

  properties.append({
    "name": "casing_lod_distance",
    "type": TYPE_FLOAT,
    "hint": PROPERTY_HINT_RANGE,
    "hint_string": "0.1,10.0,0.1"
  })

  return properties
