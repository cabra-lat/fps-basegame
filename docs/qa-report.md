# QA report — fps-basegame

Generated: 2026-09-21T15:44:32.724Z  
Tool: `tools/qa/audit.mjs` v2.1.0  |  scope: `addons/cabra.lat_shooters/src`, `src`, `scenes`

> Findings are **work orders**, not fixes. Every row carries a number or a `file:line`.
> Severity scale: BLOCKER / MAJOR / MINOR / NIT (see `.opencode/agents/qa.md`).

## Summary

| Severity | Count |
| --- | ---: |
| BLOCKER | 0 |
| MAJOR | 48 |
| MINOR | 36 |
| NIT | 14 |
| **Total** | **98** |

Scanned 118 shipping `.gd` files, 17396 lines, 1046 functions. 11 functions > 60 lines. Indent census (dominant): 64 tab files / 50 space files.

### By rule

| Rule | Count |
| --- | ---: |
| unused-field | 29 |
| unused-func | 15 |
| pending-consumer | 14 |
| debug-print | 13 |
| long-function | 11 |
| deep-nesting | 4 |
| connect-leak | 4 |
| lambda-leak | 3 |
| god-object | 2 |
| dead-api | 2 |
| node-churn | 1 |

## Import gate

`godot --headless --path . --import` → exit **0**, 0 `ERROR:` lines, 0 parse/script error lines. Log: `/tmp/shooter/qa-import.log`.

## Baseline & taxonomy

Tool version **2.1.0**. Manual findings are re-probed by `--verify-manual`; a finding whose probe prints `QA_RESULT=RESOLVED` is dropped from the counts so a fixed bug cannot keep CI red.
This run verified **2** probe(s): 0 still reproduced, 2 resolved, 25 without a probe (reported as `unverified`).
Triage: **10** finding(s) suppressed by `tools/qa/ignore.json` (12 entries, each with a `confirmed_by`: npc-body, ballistics).

## Dead-API breakdown by owner

| Owner | unused-func (MAJOR) | unused-field (MAJOR) | dead-api (MAJOR) | pending-consumer (NIT) |
| --- | ---: | ---: | ---: | ---: |
| ballistics | 1 | 11 | 1 | 5 |
| npc-body | 0 | 0 | 0 | 2 |
| player-rig | 14 | 18 | 1 | 7 |

| Severity | Baseline | Current |
| --- | ---: | ---: |
| BLOCKER | 0 | 0 |
| MAJOR | 48 | 48 |
| MINOR | 36 | 36 |
| NIT | 14 | 14 |

Baseline tool v2.1.0 — **taxonomy changed** (new/removed rule set): a MAJOR jump is an explained reclassification, and `--check` will not fail on it until the baseline is refreshed.

## Findings

| Severity | Rule | Owner | Location | Finding | Evidence |
| --- | --- | --- | --- | --- | --- |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/armor/armor.gd:33` | dead API: @export var hit_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/armor/ballistic_material.gd:76` | dead API: @export var impact_effect never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/armor/ballistic_material.gd:77` | dead API: @export var penetration_effect never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/armor/ballistic_material.gd:78` | dead API: @export var impact_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/armor/ballistic_material.gd:79` | dead API: @export var exit_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/core/inventory/backpack.gd:15` | dead API: get_quick_access_items() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/core/inventory/container.gd:130` | dead API: find_item_by_content() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/core/inventory/container.gd:141` | dead API: get_used_space() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/core/inventory/equipment.gd:67` | dead API: get_insulation_rating() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/core/inventory/equipment.gd:76` | dead API: get_movement_penalty() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/weapon/weapon.gd:44` | dead API: @export var fire_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/weapon/weapon.gd:45` | dead API: @export var feed_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/weapon/weapon.gd:46` | dead API: @export var empty_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/core/weapon/weapon.gd:47` | dead API: @export var extra_sound never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd:24` | dead API: const PIXELS_PER_METER never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/gameplay/spring_recoil.gd:45` | dead API: add_recoil() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:3` | dead API: const NOT_MOVING never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:7` | dead API: @export var gentle_push never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:18` | dead API: @export var default_shoulder never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:20` | dead API: @export var default_turn_speed never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:29` | dead API: @export var aim_shoulder_x never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:31` | dead API: @export var aim_focused_duration never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:35` | dead API: @export var walk_fov never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:37` | dead API: @export var walk_height never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:49` | dead API: @export var sprint_fov never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:51` | dead API: @export var sprint_height never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/config.gd:65` | dead API: @export var lean_time never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | god-object | per-owner | `addons/cabra.lat_shooters/src/player/controller.gd:1` | file has 1215 lines (> 800) | 62 functions |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:24` | dead API: var debug_text never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | dead-api | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:93` | dead API: field current_lean_angle is written but never read | refs=5 reads=0 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:134` | dead API: var debug_fly_slow_multiplier never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:137` | dead API: var _last_debug_time never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:138` | dead API: var _debug_interval never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:139` | dead API: var _condition_cache never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:407` | dead API: cancel_use() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:524` | dead API: emit_step_noise() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:548` | dead API: surface_is_soft_ground() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:1196` | dead API: get_camera_basis() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:1201` | dead API: get_head_position() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:1206` | dead API: get_look_direction() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/survival.gd:87` | dead API: weight_ratio() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-func | player-rig | `addons/cabra.lat_shooters/src/player/viewmodel_rig.gd:123` | dead API: ads_blend() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | dead-api | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/base_slot.gd:17` | dead API: field parent_ui is written but never read | refs=2 reads=0 |
| MAJOR | unused-func | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd:143` | dead API: handle_equipment_drop() computes a value but no caller consumes it (grep-based; confirm it is not an engine/duck-typed hook) | refs=1 |
| MAJOR | unused-field | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/item.gd:8` | dead API: var debug_label never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:12` | dead API: @export var zoom_sensitivity never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | unused-field | player-rig | `addons/cabra.lat_shooters/src/world/item_3d.gd:14` | dead API: @export var pickup_radius never referenced anywhere (grep-based, confirm it is not read by a scene/resource) | refs=1 |
| MAJOR | god-object | per-owner | `scenes/arena_manager.gd:1` | file has 1266 lines (> 800) | 90 functions |
| MINOR | long-function | ballistics | `addons/cabra.lat_shooters/src/core/armor/armor.gd:140` | resolve_projectile() is 62 lines (> 60) | ends line 201 |
| MINOR | deep-nesting | ballistics | `addons/cabra.lat_shooters/src/core/health/medical_item.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/backpack.gd:12` | 1 print()/printerr() call(s) in shipping source | 12: print("DEBUG: Initializing backpack with grid: ", grid_width, "x", grid_height) |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/equipment_slot.gd:18` | 2 print()/printerr() call(s) in shipping source | 18: print("EquipmentSlot.can_add_item: checking %s in slot type %s (current items: %d/%d)" % [ \|\| 44: print("  -> %s: %s" % ["COMPATIBLE" if compatible else "INCOMPATIBLE", item.name if item else "Unkno |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/grid.gd:41` | 31 print()/printerr() call(s) in shipping source | 41: print("DEBUG: Position out of bounds (negative): ", position) \|\| 44: print("DEBUG: Position out of bounds (exceeds grid): ", position, " size: ", size, " grid: ", width, \|\| 55: print("DEBUG: Grid row out of bound |
| MINOR | lambda-leak | ballistics | `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd:123` | 1 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 123 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:142` | _ready() is 75 lines (> 60) | ends line 216 |
| MINOR | connect-leak | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:173` | 11 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:215` | 7 print()/printerr() call(s) in shipping source | 215: print("PlayerController initialized") \|\| 245: print("Weapon %s equipped at %s" % [current_weapon.name, slot_name ]) \|\| 275: print("Weapon unequipped from %s - viewmodel released" % slot_name) \|\| 654: print("De |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:709` | _physics_process() is 74 lines (> 60) | ends line 782 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:826` | _update_movement_parameters() is 106 lines (> 60) | ends line 931 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:1070` | _on_state_entered() is 62 lines (> 60) | ends line 1131 |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/player/debug.gd:43` | 1 print()/printerr() call(s) in shipping source | 43: print("DebugSingleton initialized") |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/input.gd:47` | _process() is 78 lines (> 60) | ends line 124 |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/systems/inventory_system.gd:6` | 40 print()/printerr() call(s) in shipping source | 6: print("=== TRANSFER ITEM START ===") \|\| 7: print("Transfer: %s -> %s" % [source, target]) \|\| 8: print("Item: %s (dimensions: %s)" % [item.name if item else "Unknown", item.dimensions]) \|\| 10: print("Transfer res |
| MINOR | node-churn | player-rig | `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd:1` | 13 add_child()/add_sibling() and 0 queue_free()/free() | unbounded growth risk |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd:41` | _build() is 103 lines (> 60) | ends line 143 |
| MINOR | deep-nesting | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/container.gd:1` | max block nesting depth 6 (>= 5) | measured from function bodies |
| MINOR | connect-leak | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/container.gd:25` | 7 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/equipment_slot.gd:36` | 1 print()/printerr() call(s) in shipping source | 36: print("Starting drag from equipment slot: %s" % associated_item.name if associated_item else "Unknow |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd:32` | 7 print()/printerr() call(s) in shipping source | 32: print("Equipment changed: %s in %s" % [item.name if item else "None", slot_name]) \|\| 137: print("EquipmentUI: Slot dropped: %s -> %s" % [ \|\| 148: print("Equipment drop attempt: %s -> %s" % [ \|\| 156: print("Atte |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/main.gd:80` | 16 print()/printerr() call(s) in shipping source | 80: print("Transfer failed - both UIs should remain unchanged") \|\| 87: print("Equipment drop attempt: %s -> %s" % [ \|\| 93: print("Attempting to equip item in %s" % slot_name) \|\| 95: print("Item equipped successfull |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/slot.gd:90` | 1 print()/printerr() call(s) in shipping source | 90: print("Drop accepted at slot %s (equipment: %s)" % [grid_position, is_equipment_slot]) |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/world_drop_zone.gd:8` | 2 print()/printerr() call(s) in shipping source | 8: print("WorldDropZone: Checking if can drop data: ", data) \|\| 12: print("WorldDropZone: Dropping data: ", data) |
| MINOR | deep-nesting | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:81` | 7 print()/printerr() call(s) in shipping source | 81: print("ViewportTexture assigned to shader") \|\| 124: print("Zoomed in: FOV = ", current_fov) \|\| 130: print("Zoomed out: FOV = ", current_fov) \|\| 135: print("Zoom control enabled") |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/world/magazine_3d.gd:9` | 12 print()/printerr() call(s) in shipping source | 9: print("Magazine3D _ready called, data: ", data) \|\| 12: print("Magazine3D _set_data called with: ", value) \|\| 20: print("Magazine data set, contents size: ", data.contents.size() if data.contents else 0) \|\| 27: p |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/world/weapon_3d.gd:227` | _apply_recoil() is 63 lines (> 60) | ends line 289 |
| MINOR | lambda-leak | range | `scenes/arena_manager.gd:95` | 3 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 95,191,200 |
| MINOR | long-function | range | `scenes/arena_manager.gd:845` | _build_hud() is 93 lines (> 60) | ends line 937 |
| MINOR | connect-leak | range | `scenes/debug_range.gd:29` | 7 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | lambda-leak | range | `scenes/debug_range.gd:35` | 1 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 35 |
| MINOR | connect-leak | range | `scenes/main_menu.gd:18` | 12 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | long-function | meta | `src/meta/meta_service.gd:172` | resolve_raid() is 72 lines (> 60) | ends line 243 |
| MINOR | deep-nesting | meta | `src/meta/quest_log.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | long-function | npc-body | `src/npcs/bot/bot.gd:337` | _physics_process() is 82 lines (> 60) | ends line 418 |
| NIT | pending-consumer | ballistics | `addons/cabra.lat_shooters/src/core/attachment/attatchments.gd:114` | pending consumer: toggle_laser() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | ballistics | `addons/cabra.lat_shooters/src/core/attachment/attatchments.gd:118` | pending consumer: toggle_light() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | ballistics | `addons/cabra.lat_shooters/src/core/attachment/attatchments.gd:122` | pending consumer: deploy_bipod() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/core/inventory/grid.gd:332` | pending consumer: debug_print_grid() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | ballistics | `addons/cabra.lat_shooters/src/core/weapon/weapon.gd:344` | pending consumer: clear_immediately() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | ballistics | `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd:150` | pending consumer: stop_flash() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:88` | pending consumer: update_scope_view() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:133` | pending consumer: start_zooming() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:137` | pending consumer: stop_zooming() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:142` | pending consumer: set_fov() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:148` | pending consumer: reset_fov() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | player-rig | `addons/cabra.lat_shooters/src/world/weapon_3d.gd:316` | pending consumer: set_casing_ejection() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | npc-body | `src/npcs/bot/bot.gd:221` | pending consumer: set_tier() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |
| NIT | pending-consumer | npc-body | `src/npcs/bot/bot.gd:688` | pending consumer: set_debug_perception() has no caller yet (wire it up or delete it; informational, not debt) | refs=1 |

## Top files by finding weight

| File | BLOCKER | MAJOR | MINOR | NIT |
| --- | ---: | ---: | ---: | ---: |
| `addons/cabra.lat_shooters/src/player/controller.gd` | 0 | 13 | 6 | 0 |
| `addons/cabra.lat_shooters/src/player/config.gd` | 0 | 11 | 0 | 0 |
| `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd` | 0 | 1 | 2 | 5 |
| `addons/cabra.lat_shooters/src/core/weapon/weapon.gd` | 0 | 4 | 0 | 1 |
| `addons/cabra.lat_shooters/src/core/armor/ballistic_material.gd` | 0 | 4 | 0 | 0 |
| `addons/cabra.lat_shooters/src/core/attachment/attatchments.gd` | 0 | 0 | 0 | 3 |
| `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd` | 0 | 1 | 1 | 1 |
| `scenes/arena_manager.gd` | 0 | 1 | 2 | 0 |
| `src/npcs/bot/bot.gd` | 0 | 0 | 1 | 2 |
| `addons/cabra.lat_shooters/src/core/armor/armor.gd` | 0 | 1 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/backpack.gd` | 0 | 1 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/container.gd` | 0 | 2 | 0 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/equipment.gd` | 0 | 2 | 0 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/grid.gd` | 0 | 0 | 1 | 1 |
| `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/container.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd` | 0 | 1 | 1 | 0 |
| `addons/cabra.lat_shooters/src/world/weapon_3d.gd` | 0 | 0 | 1 | 1 |
| `scenes/debug_range.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/core/health/medical_item.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/equipment_slot.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/gameplay/spring_recoil.gd` | 0 | 1 | 0 | 0 |
| `addons/cabra.lat_shooters/src/player/debug.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/input.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/survival.gd` | 0 | 1 | 0 | 0 |

## Duplication (fingerprint, 8-line windows)

_none above threshold_

## Indentation census (per root)

| Root | Files | Tab-dominant | Space-dominant | No indentation |
| --- | ---: | ---: | ---: | ---: |
| addons (core) | 61 | 10 | 49 | 2 |
| scenes/ (game) | 20 | 19 | 1 | 0 |
| src/ (game) | 37 | 35 | 0 | 2 |

## Conventions

- **Indentation is split by repo, not messy per file.** The addon (`addons/`) is dominantly **4-space**; the game repo (`src/`, `scenes/`) is dominantly **tab**. No shipped file mixes both styles (see census). Proposed rule: keep the addon at 4 spaces and the game repo at tabs; do **not** mass-rewrite either.
- Debug `print()` is forbidden in shipping paths (`src/`, `scenes/`, addon `src/`); test harnesses (`validate_*.gd`, `test/`) may print. Prints on, or inside, an `if OS.is_debug_build():` guard are debug-only and are **not** counted as `debug-print` findings.
- **Dead-API triage (three classes).** `morto-real` = a value-returning function, computed property or field that exists and is never consumed -> **MAJOR debt** (`unused-func`, `unused-field`, `dead-api`). `consumidor-pendente` = a void hook/API with no caller yet -> **NIT, informational, not debt** (`pending-consumer`). `falso-positivo-de-scan` = the matcher missed a real caller -> **tool bug, never counted**. The caller matcher covers `<inst>.<name>(`, `.<name>.connect(`, `.tscn`/`.tres` signal connections and properties, and `Callable("<name>")` strings.
- **Identity rule (AGENTS.md):** `ip-name` / `ip-tarkov` scan shipped code+resources for commercial-game proper nouns. Technical standards and authors (GOST, NIJ, VPAM, STANAG, RHA, HIC, Recht-Ipson, Poncelet) are public references and are NOT findings, and `docs/**` may cite sources. A proper noun in a resource `name` or player-facing string is a BLOCKER; elsewhere MAJOR.
- **Reference integrity:** `broken-ref` reports `res://` paths that do not exist (latent export/shader failure); `case-mismatch` reports names that only exist with different case (case-sensitive export breakage).
- Contract checks a static tool cannot prove (rule 4 physics queries in `_physics_process`; rule 5 held items never simulated) are hand-reviewed in `tools/qa/manual-findings.json` and merged into the Findings table above (they carry an Owner and a `QA-NNN` id in the evidence).
- CI: `node tools/qa/audit.mjs --check` exits 1 on any BLOCKER and 2 when MAJOR rises above `docs/qa-baseline.json`; `--update-baseline` re-snapshots.

