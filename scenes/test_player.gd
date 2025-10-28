# res://test/scenes/test_player.gd
extends Node

var can_connect_signals: bool = false

# DEV/DEBUG
@onready var ammo: Ammo = preload("res://resources/ammo/7_62_39mm_PS_GOST_BR4.tres")
@onready var weapon: Weapon = preload("res://resources/weapons/AK_47.tres")
@onready var player: PlayerController = $Player
# END DEV/DEBUG

func _ready():
    # Equip to player body
  var weapon_item = InventorySystem.create_inventory_item(weapon)
  $Player.equipment.equip(weapon_item, "primary")

  var magazine = AmmoFeed.new()
  magazine.compatible_calibers.append(ammo.caliber)
  magazine.type = AmmoFeed.Type.EXTERNAL
  magazine.icon = preload("res://assets/ui/inventory/icon_stock_mag.png")
  magazine.view_model = preload("res://src/weapons/magazine_ak47.tscn")
  var magazine_item = InventorySystem.create_inventory_item(magazine)
  magazine_item.dimensions = Vector2i(1,2)

  var backpack = Backpack.new()
  backpack.icon = preload("res://assets/ui/inventory/backpack.png")
  backpack.add_item(magazine_item)

  var backpack_item = InventorySystem.create_inventory_item(backpack)
  backpack_item.dimensions = Vector2i(2,2)
  $Player.equipment.equip(backpack_item, "back")

  # Connect to player's current weapon signals
  $Player.equipment.equipped.connect(_on_player_equipped)

  # If weapon is already equipped, connect to it
  var primary = $Player.equipment.get_equipped("primary")
  if not primary.is_empty():
    _connect_weapon_signals(primary[0].extra as Weapon)

  load_ammunition_into_weapon()

func _on_player_equipped(item: Item, _slot_name: String):
  if item is Weapon:
    _connect_weapon_signals(item as Weapon)

func _connect_weapon_signals(weapon: Weapon):
  if weapon:
    print("DEBUG: Connecting to weapon signals: ", weapon.name)
    for sig in weapon.get_signal_list():
      if not weapon.is_connected(sig.name,  Callable(self, "_on_%s" % sig.name)):
        weapon.connect(sig.name, Callable(self, "_on_%s" % sig.name))

func _on_trigger_locked(_weapon: Weapon):
  $HUD.show_popup("[can't pull the trigger]")

func _on_cartridge_fired(_weapon: Weapon, ejected: Ammo):
  print("Cartridge fired signal received, ejected: ", ejected)
  $HUD.show_popup("Pow! (%d) %s" % [
    _weapon.ammofeed.max_capacity - _weapon.ammofeed.capacity,
    ejected.caliber
  ])

func _on_trigger_released(_weapon: Weapon):
  $HUD.add_log("[ Trigger released ]")

func _on_firemode_changed(_weapon: Weapon, mode: String):
  $HUD.show_popup("[ Changed firemode: %s ]" % mode)

func _on_ammofeed_empty(_weapon: Weapon, _ammofeed: AmmoFeed):
  $HUD.show_popup("[ AmmoFeed is empty! ]")

func _on_ammofeed_missing(_weapon: Weapon):
  $HUD.show_popup('[ AmmoFeed is missing! ]')

func _on_ammofeed_changed(_weapon: Weapon, old: AmmoFeed, new: AmmoFeed):
  $HUD.show_popup("changed mag %d/%d to %d/%d"
    % [old.capacity  if old else 0,
      old.max_capacity if old else 0,
      new.capacity,
      new.max_capacity])

func _on_ammofeed_incompatible(_weapon: Weapon, ammofeed: AmmoFeed):
  $HUD.show_popup("[ AmmoFeed incompatible ]")

func _on_player_debug(player: PlayerController, text: String) -> void:
  $HUD.update_debug(text)

func _on_trigger_pressed(_weapon: Weapon):
   $HUD.show_popup("[ You pressed the trigger ]")

func _on_weapon_racked(_weapon: Weapon):
   $HUD.show_popup("[ Weapon racking sound ]")

func _on_attachment_added(_weapon: Weapon, _attachment: Attachment, _point: int):
   $HUD.show_popup("[ Attachment added sound ]")

func _on_attachment_removed(_weapon: Weapon, _attachment: Attachment, _point: int):
   $HUD.show_popup("[ Attachment removed sound ]")

func _on_shell_ejected(_weapon: Weapon, cartridge: Ammo):
   $HUD.show_popup("[ Shell ejection sound ]")

func _on_cartridge_ejected(_weapon: Weapon, _cartridge: Ammo):
   $HUD.show_popup("[ Cartridge ejection sound ]")

func _on_cartridge_inserted(_weapon: Weapon, _cartridge: Ammo):
   $HUD.show_popup("[ Cartridge insertion sound ]")

func _on_player_landed(player: PlayerController, max_velocity: float, delta: float) -> void:
  var letal_g = player.config.letal_acceleration
  var a = abs(max_velocity - player.velocity.length()) / (2.0 * delta)
  var g = a / player.config.gravity
  var letality_ratio = g / letal_g
  if letality_ratio > 1:
    $HUD.show_popup("Letal fall damage (%.2f g)" % g)
  elif letality_ratio > .5:
    $HUD.show_popup("Minor fall damage (%.2f g)" % g)
  elif letality_ratio > 0.1:
    $HUD.show_popup("Safely landed     (%.2f g)" % g)

func load_ammunition_into_weapon():
  var player_weapon = $Player.equipment.get_equipped("primary")[0].extra as Weapon
  if player_weapon:
    # Create and load a magazine
    var magazine = AmmoFeed.new()
    magazine.name = "AK-47 Magazine"
    magazine.compatible_calibers = ["7.62x39mm"]
    magazine.max_capacity = 30
    magazine.type = AmmoFeed.Type.EXTERNAL

    # Fill with ammunition
    for i in range(30):  # Load 10 rounds for testing
      var round = ammo.duplicate()
      round.name = "7.62x39mm Round " + str(i)
      magazine.insert(round)

    # Load into weapon
    var success = WeaponSystem.change_magazine(player_weapon, magazine)
    print("DEBUG: Magazine load success: ", success)

    if success:
      print("DEBUG: Weapon ammofeed: ", player_weapon.ammofeed != null)
      print("DEBUG: Chambered round: ", player_weapon.chambered_round != null)
      if player_weapon.ammofeed:
        print("DEBUG: Rounds in magazine: ", player_weapon.ammofeed.capacity)
  else:
    print("DEBUG: No weapon found to load ammunition")
