# res://test/scenes/test_player.gd
extends Node

var can_connect_signals: bool = false

# DEV/DEBUG
#@onready var ammo: Ammo = preload("res://resources/ammo/7_62_39mm_PS_GOST_BR4.tres")
#@onready var weapon: Weapon = preload("res://resources/weapons/AK_47.tres")
@onready var ammo: Ammo = preload("res://resources/ammo/5_56_45mm_SS109_VPAM_PM7.tres")
@onready var weapon: Weapon = preload("res://resources/weapons/M4_Carbine.tres")
#@onready var ammo: Ammo = preload("res://resources/ammo/7_62_51mm_DM111_VPAM_PM7.tres")
#@onready var weapon: Weapon = preload("res://resources/weapons/IMBEL_AGLC.tres")
@onready var player: PlayerController = $Player
# END DEV/DEBUG

func _ready():
  # Create and load a magazine
  var magazine = weapon.ammo_feed.duplicate(true)

    # Fill with ammunition
  for i in range(30):  # Load 10 rounds for testing
    var cartridge = ammo.duplicate(true)
    cartridge.name = ammo.caliber + " Round " + str(i)
    magazine.insert(cartridge)

  weapon.ammo_feed = magazine
  var weapon_item = InventorySystem.create_inventory_item(weapon)
  $Player.equipment.equip(weapon_item, "primary")

  var magazine_item = InventorySystem.create_inventory_item(magazine.duplicate(true))
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

func _on_player_equipped(item: Item, _slot_name: String):
  if item is Weapon:
    _connect_weapon_signals(item as Weapon)

func _connect_weapon_signals(_weapon: Weapon):
  if weapon:
    print("DEBUG: Connecting to weapon signals: ", weapon.name)
    for sig in weapon.get_signal_list():
      if not weapon.is_connected(sig.name,  Callable(self, "_on_%s" % sig.name)) and \
         self.has_method("_on_%s" % sig.name):
        weapon.connect(sig.name, Callable(self, "_on_%s" % sig.name))

func _on_trigger_locked(_weapon: Weapon):
  $HUD.show_popup("[can't pull the trigger]")

func _on_cartridge_fired(_weapon: Weapon, ejected: Ammo):
  print("Cartridge fired signal received, ejected: ", ejected)
  $HUD.show_popup("Pow! (%d) %s" % [
    _weapon.ammo_feed.max_capacity - _weapon.ammo_feed.capacity \
    if _weapon.ammo_feed else 0, # It might have it chambered and mag ejected
    ejected.caliber
  ])

func _on_trigger_released(_weapon: Weapon):
  $HUD.add_log("[ Trigger released ]")

func _on_firemode_changed(_weapon: Weapon, mode: String):
  $HUD.show_popup("[ Changed firemode: %s ]" % mode)

func _on_ammo_feed_empty(_weapon: Weapon, _ammo_feed: AmmoFeed):
  $HUD.show_popup("[ AmmoFeed is empty! ]")

func _on_ammo_feed_missing(_weapon: Weapon):
  $HUD.show_popup('[ AmmoFeed is missing! ]')

func _on_ammo_feed_changed(_weapon: Weapon, old: AmmoFeed, new: AmmoFeed):
  $HUD.show_popup("changed mag %d/%d to %d/%d"
    % [old.capacity  if old else 0,
      old.max_capacity if old else 0,
      new.capacity,
      new.max_capacity])

func _on_ammofeed_incompatible(_weapon: Weapon, _ammo_feed: AmmoFeed):
  $HUD.show_popup("[ AmmoFeed incompatible ]")

func _on_player_debug(_player: PlayerController, text: String) -> void:
  $HUD.update_debug(text)

func _on_trigger_pressed(_weapon: Weapon):
  $HUD.show_popup("[ You pressed the trigger ]")

func _on_weapon_racked(_weapon: Weapon):
  $HUD.show_popup("[ Weapon racking sound ]")

func _on_attachment_added(_weapon: Weapon, _attachment: Attachment, _point: int):
  $HUD.show_popup("[ Attachment added sound ]")

func _on_attachment_removed(_weapon: Weapon, _attachment: Attachment, _point: int):
  $HUD.show_popup("[ Attachment removed sound ]")

func _on_shell_ejected(_weapon: Weapon, _cartridge: Ammo):
  $HUD.show_popup("[ Shell ejection sound ]")

func _on_cartridge_ejected(_weapon: Weapon, _cartridge: Ammo):
  $HUD.show_popup("[ Cartridge ejection sound ]")

func _on_cartridge_inserted(_weapon: Weapon, _cartridge: Ammo):
  $HUD.show_popup("[ Cartridge insertion sound ]")

func _on_player_landed(_player: PlayerController, max_velocity: float, delta: float) -> void:
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
