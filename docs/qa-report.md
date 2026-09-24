# QA report — fps-basegame

Generated: 2026-09-24T14:00:20.038Z  
Tool: `tools/qa/audit.mjs` v2.1.0  |  scope: `addons/cabra.lat_shooters/src`, `src`, `scenes`

> Findings are **work orders**, not fixes. Every row carries a number or a `file:line`.
> Severity scale: BLOCKER / MAJOR / MINOR / NIT (see `.opencode/agents/qa.md`).

## Summary

| Severity | Count |
| --- | ---: |
| BLOCKER | 0 |
| MAJOR | 3 |
| MINOR | 41 |
| NIT | 0 |
| **Total** | **44** |

Scanned 127 shipping `.gd` files, 21203 lines, 1234 functions. 12 functions > 60 lines. Indent census (dominant): 72 tab files / 51 space files.

### By rule

| Rule | Count |
| --- | ---: |
| debug-print | 13 |
| long-function | 12 |
| deep-nesting | 7 |
| connect-leak | 5 |
| lambda-leak | 3 |
| god-object | 3 |
| node-churn | 1 |

## Baseline & taxonomy

Tool version **2.1.0**. Manual findings are re-probed by `--verify-manual`; a finding whose probe prints `QA_RESULT=RESOLVED` is dropped from the counts so a fixed bug cannot keep CI red.
Triage: **0** finding(s) suppressed by `tools/qa/ignore.json` (12 entries, each with a `confirmed_by`: npc-body, ballistics).

| Severity | Baseline | Current |
| --- | ---: | ---: |
| BLOCKER | 0 | 0 |
| MAJOR | 39 | 3 |
| MINOR | 37 | 41 |
| NIT | 30 | 0 |

Baseline tool v2.1.0

## Accepted follow-up debt (non-gating)

These findings remain visible for owner follow-up but are intentionally excluded from severity totals and the `--check` regression gate.

| ID | Severity | Owner | Task | Location | Disposition |
| --- | --- | --- | --- | --- | --- |
| QA-028 | MAJOR | inventory-ux | task_1790247342369_a480e9 | `scenes/gunsmith_ui.gd:492` | Accepted as bounded follow-up debt; inventory-ux owns the scoped core transfer/return API migration. Non-gating for this frozen candidate; not a claim that the architecture debt is fixed. |

## Findings

| Severity | Rule | Owner | Location | Finding | Evidence |
| --- | --- | --- | --- | --- | --- |
| MAJOR | god-object | per-owner | `addons/cabra.lat_shooters/src/player/controller.gd:1` | file has 1191 lines (> 800) | 64 functions |
| MAJOR | god-object | per-owner | `scenes/arena_manager.gd:1` | file has 1496 lines (> 800) | 103 functions |
| MAJOR | god-object | per-owner | `src/npcs/bot/bot.gd:1` | file has 1208 lines (> 800) | 77 functions |
| MINOR | long-function | ballistics | `addons/cabra.lat_shooters/src/core/armor/armor.gd:140` | resolve_projectile() is 62 lines (> 60) | ends line 201 |
| MINOR | deep-nesting | ballistics | `addons/cabra.lat_shooters/src/core/health/medical_item.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/backpack.gd:12` | 1 print()/printerr() call(s) in shipping source | 12: print("DEBUG: Initializing backpack with grid: ", grid_width, "x", grid_height) |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/equipment_slot.gd:18` | 2 print()/printerr() call(s) in shipping source | 18: print("EquipmentSlot.can_add_item: checking %s in slot type %s (current items: %d/%d)" % [ \|\| 44: print("  -> %s: %s" % ["COMPATIBLE" if compatible else "INCOMPATIBLE", item.name if item else "Unkno |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/core/inventory/grid.gd:41` | 31 print()/printerr() call(s) in shipping source | 41: print("DEBUG: Position out of bounds (negative): ", position) \|\| 44: print("DEBUG: Position out of bounds (exceeds grid): ", position, " size: ", size, " grid: ", width, \|\| 55: print("DEBUG: Grid row out of bound |
| MINOR | lambda-leak | ballistics | `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd:123` | 1 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 123 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:137` | _ready() is 76 lines (> 60) | ends line 212 |
| MINOR | connect-leak | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:168` | 12 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:211` | 7 print()/printerr() call(s) in shipping source | 211: print("PlayerController initialized") \|\| 237: print("Weapon %s equipped at %s" % [current_weapon.name, slot_name]) \|\| 267: print("Weapon unequipped from %s - viewmodel released" % slot_name) \|\| 681: print("Deb |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:736` | _physics_process() is 76 lines (> 60) | ends line 811 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/controller.gd:1045` | _on_state_entered() is 63 lines (> 60) | ends line 1107 |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/player/debug.gd:43` | 1 print()/printerr() call(s) in shipping source | 43: print("DebugSingleton initialized") |
| MINOR | deep-nesting | player-rig | `addons/cabra.lat_shooters/src/player/humanoid_rig.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/input.gd:66` | _process() is 80 lines (> 60) | ends line 145 |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/player/player_movement_parameters.gd:23` | resolve() is 71 lines (> 60) | ends line 93 |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/systems/inventory_system.gd:8` | 31 print()/printerr() call(s) in shipping source | 8: print("=== TRANSFER ITEM START ===") \|\| 9: print("Transfer: %s -> %s" % [source, target]) \|\| 10: print("Item: %s (dimensions: %s)" % [item.name, item.dimensions]) \|\| 12: print("Transfer result: %s" % result) |
| MINOR | node-churn | player-rig | `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd:1` | 13 add_child()/add_sibling() and 0 queue_free()/free() | unbounded growth risk |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd:41` | _build() is 103 lines (> 60) | ends line 143 |
| MINOR | deep-nesting | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/container.gd:1` | max block nesting depth 6 (>= 5) | measured from function bodies |
| MINOR | connect-leak | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/container.gd:25` | 7 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/equipment_slot.gd:36` | 1 print()/printerr() call(s) in shipping source | 36: print("Starting drag from equipment slot: %s" % associated_item.name if associated_item else "Unknow |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd:32` | 7 print()/printerr() call(s) in shipping source | 32: print("Equipment changed: %s in %s" % [item.name if item else "None", slot_name]) \|\| 137: print("EquipmentUI: Slot dropped: %s -> %s" % [ \|\| 148: print("Equipment drop attempt: %s -> %s" % [ \|\| 156: print("Atte |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/main.gd:83` | 16 print()/printerr() call(s) in shipping source | 83: print("Transfer failed - both UIs should remain unchanged") \|\| 90: print("Equipment drop attempt: %s -> %s" % [ \|\| 96: print("Attempting to equip item in %s" % slot_name) \|\| 98: print("Item equipped successfull |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/slot.gd:94` | 1 print()/printerr() call(s) in shipping source | 94: print("Drop accepted at slot %s (equipment: %s)" % [grid_position, is_equipment_slot]) |
| MINOR | debug-print | ballistics | `addons/cabra.lat_shooters/src/ui/inventory/world_drop_zone.gd:8` | 2 print()/printerr() call(s) in shipping source | 8: print("WorldDropZone: Checking if can drop data: ", data) \|\| 12: print("WorldDropZone: Dropping data: ", data) |
| MINOR | deep-nesting | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd:81` | 7 print()/printerr() call(s) in shipping source | 81: print("ViewportTexture assigned to shader") \|\| 124: print("Zoomed in: FOV = ", current_fov) \|\| 130: print("Zoomed out: FOV = ", current_fov) \|\| 135: print("Zoom control enabled") |
| MINOR | debug-print | player-rig | `addons/cabra.lat_shooters/src/world/magazine_3d.gd:9` | 12 print()/printerr() call(s) in shipping source | 9: print("Magazine3D _ready called, data: ", data) \|\| 12: print("Magazine3D _set_data called with: ", value) \|\| 23: print("Magazine data set, contents size: ", data.contents.size() if data.contents else 0) \|\| 30: p |
| MINOR | long-function | player-rig | `addons/cabra.lat_shooters/src/world/weapon_3d.gd:343` | _apply_recoil() is 63 lines (> 60) | ends line 405 |
| MINOR | deep-nesting | range | `scenes/arena_manager.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | lambda-leak | range | `scenes/arena_manager.gd:103` | 3 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 103,208,217 |
| MINOR | long-function | range | `scenes/arena_manager.gd:1080` | _build_hud() is 93 lines (> 60) | ends line 1172 |
| MINOR | connect-leak | range | `scenes/debug_range.gd:29` | 7 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | lambda-leak | range | `scenes/debug_range.gd:35` | 1 lambda .connect() without CONNECT_ONE_SHOT or stored Callable | 35 |
| MINOR | deep-nesting | range | `scenes/gunsmith_ui.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | long-function | range | `scenes/gunsmith_ui.gd:536` | _apply() is 65 lines (> 60) | ends line 600 |
| MINOR | connect-leak | range | `scenes/main_menu.gd:18` | 12 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | long-function | meta | `src/meta/meta_service.gd:172` | resolve_raid() is 79 lines (> 60) | ends line 250 |
| MINOR | deep-nesting | meta | `src/meta/quest_log.gd:1` | max block nesting depth 5 (>= 5) | measured from function bodies |
| MINOR | connect-leak | npc-body | `src/npcs/bot/bot.gd:240` | 3 .connect() and 0 .disconnect() in file | no teardown in _exit_tree |
| MINOR | long-function | npc-body | `src/npcs/bot/bot.gd:464` | _physics_process() is 90 lines (> 60) | ends line 553 |

## Top files by finding weight

| File | BLOCKER | MAJOR | MINOR | NIT |
| --- | ---: | ---: | ---: | ---: |
| `addons/cabra.lat_shooters/src/player/controller.gd` | 0 | 1 | 5 | 0 |
| `scenes/arena_manager.gd` | 0 | 1 | 3 | 0 |
| `src/npcs/bot/bot.gd` | 0 | 1 | 2 | 0 |
| `addons/cabra.lat_shooters/src/ui/hud/status_hud.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/container.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/world/attachment_scope_3d.gd` | 0 | 0 | 2 | 0 |
| `scenes/debug_range.gd` | 0 | 0 | 2 | 0 |
| `scenes/gunsmith_ui.gd` | 0 | 0 | 2 | 0 |
| `addons/cabra.lat_shooters/src/core/armor/armor.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/health/medical_item.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/backpack.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/equipment_slot.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/core/inventory/grid.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/effects/muzzle_flash_3d.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/debug.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/humanoid_rig.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/input.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/player/player_movement_parameters.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/systems/inventory_system.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/equipment_slot.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/main.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/slot.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/ui/inventory/world_drop_zone.gd` | 0 | 0 | 1 | 0 |
| `addons/cabra.lat_shooters/src/world/magazine_3d.gd` | 0 | 0 | 1 | 0 |

## Duplication (fingerprint, 8-line windows)

_none above threshold_

## Indentation census (per root)

| Root | Files | Tab-dominant | Space-dominant | No indentation |
| --- | ---: | ---: | ---: | ---: |
| addons (core) | 63 | 11 | 50 | 2 |
| scenes/ (game) | 27 | 26 | 1 | 0 |
| src/ (game) | 37 | 35 | 0 | 2 |

## Conventions

- **Indentation is split by repo, not messy per file.** The addon (`addons/`) is dominantly **4-space**; the game repo (`src/`, `scenes/`) is dominantly **tab**. No shipped file mixes both styles (see census). Proposed rule: keep the addon at 4 spaces and the game repo at tabs; do **not** mass-rewrite either.
- Debug `print()` is forbidden in shipping paths (`src/`, `scenes/`, addon `src/`); test harnesses (`validate_*.gd`, `test/`) may print. Prints on, or inside, an `if OS.is_debug_build():` guard are debug-only and are **not** counted as `debug-print` findings.
- **Dead-API triage (three classes).** `morto-real` = a value-returning function, computed property or field that exists and is never consumed -> **MAJOR debt** (`unused-func`, `unused-field`, `dead-api`). `consumidor-pendente` = a void hook/API with no caller yet -> **NIT, informational, not debt** (`pending-consumer`); a value-returning API/field whose declaration is documented as an intentional hook (doc comment containing `no caller yet`, `pending consumer` or `documented hook`) is also `consumidor-pendente`, so a planned consumer is not misreported as debt. `falso-positivo-de-scan` = the matcher missed a real caller -> **tool bug, never counted**. `falso-positivo-de-scan` = the matcher missed a real caller -> **tool bug, never counted**. The caller matcher covers `<inst>.<name>(`, `.<name>.connect(`, `.tscn`/`.tres` signal connections and properties, and `Callable("<name>")` strings.
- **Identity rule (AGENTS.md):** `ip-name` / `ip-tarkov` scan shipped code+resources for commercial-game proper nouns AND real firearm/accessory brands (`IP_BRANDS`: Glock, Magpul, Surefire, Aimpoint, EOTech, Vortex, Trijicon/ACOG, Beretta, Remington, Barrett, Colt, FN, HK, Kalashnikov, ...). Brands are matched in file contents AND in shipped filenames (`assets/**` included) so a branded `.tres`/`.png`/`.glb` cannot regress. Technical standards and authors (GOST, NIJ, VPAM, STANAG, RHA, HIC, Recht-Ipson, Poncelet) are public references and are NOT findings, and `docs/**` may cite sources. A proper noun/brand in a resource `name`, a `.tres`/`.tscn` filename, or a player-facing string is a BLOCKER; elsewhere (scripts, art filenames) MAJOR.
- **Reference integrity:** `broken-ref` reports `res://` paths that do not exist (latent export/shader failure); `case-mismatch` reports names that only exist with different case (case-sensitive export breakage).
- Contract checks a static tool cannot prove (rule 4 physics queries in `_physics_process`; rule 5 held items never simulated) are hand-reviewed in `tools/qa/manual-findings.json` and merged into the Findings table above (they carry an Owner and a `QA-NNN` id in the evidence).
- CI: `node tools/qa/audit.mjs --check` exits 1 on any BLOCKER and 2 when MAJOR rises above `docs/qa-baseline.json`; `--update-baseline` re-snapshots.

