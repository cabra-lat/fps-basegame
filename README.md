# fps-basegame

A **Godot 4.7 framework for building immersive-sim / extraction-shooter FPS games**
(genre-typical). The combat, ballistics, survival and raid-loop systems are implemented
as verified subsystems; game content sits on top of them.

Not a demo — a basegame. Each system below was built with a written contract, a
headless harness, and an independent GPU verification pass.

## What is in the box

**Gunplay & terminals** — 18 weapons (data-driven `.tres`), 50 ammunition types,
23 armor pieces, 15 attachments, 9 medical items.

| System | What it does |
|---|---|
| **Ballistics** | Recht–Ipson residual energy `Er = max(0, Eh − Ebl)` with a ballistic-limit energy per material; Poncelet tissue model `P = K·ln(1+E/E1)`; line-of-sight thickness `t/cos θ`; multi-projectile rounds (buckshot = N real projectiles, each rolling armor/damage/bleed) |
| **Armor** | Certification tables (GOST / NIJ / VPAM) **decide stops**, physics is the fall-through; layered plates overriding base class; per-material destructibility (`effective durability = dur / destructibility`); durability damage with a minimum of 1 per projectile; penetrating hits do ~10–15% less durability damage; repair lowers max durability; helmet ricochet windows |
| **Ammunition** | Damage, penetration, armor-damage %, light/heavy bleed %, feed-failure and misfire ratings, durability burn, heat, ricochet %, fragmentation %, ballistic coefficient — calibrated against a local wiki mirror for 27 rounds |
| **Optics & zeroing** | `sight_height_over_bore`, `zero_distance`, `magnification`; POI-vs-POA computed from the drop model; ADS alignment derived from the sight marker (not hand-tuned) — verified **POI = POA at 15/30/50 m** for M4 and AK |
| **Weapon handling** | Frozen rigid-body viewmodel posed procedurally (sway, bob, kick, reload dip — exponentially damped, never spring-simulated); multi-slot loadout (primary/secondary) with raise/lower, world drop and pickup as loot; per-weapon ammo persistence |
| **Movement** | Walk / sprint / crouch / prone / jump / fall damage; **lean that actually peeks** — the camera translates 0.45 m laterally around a corner with a collision clamp (0.20 m against a wall) so line-of-sight genuinely clears the edge; procedural micro-bob, stride scaling, auto-lean |
| **Survival** | Stamina (drain scaled by carried weight, sprint gate, aim tremor when low), encumbrance (real item mass), medical conditions — light/heavy bleeding, persistent fracture (splint only), pain + analgesics, blacked limbs with overkill, surgery, medkits with real `use_time` — plus energy and hydration |
| **NPCs** | Patrol → suspect → engaged → search alert states driven by a **110° vision cone** with LOS and a **30 m hearing radius** fed by `emit_noise()`; per-team tint, friendly fire, wave spawner with difficulty scaling |
| **Raid loop** | Raid state machine with timer and outcomes **SURVIVED / RUN_THROUGH (<7 min and <200 XP) / MIA / KIA / LEFT_BEHIND**; extraction points of six kinds (instant, paid Express, flare, lever, co-op, timed) with faction gating, single-use and required items; raid **event bus** for downstream consumers |
| **Game modes** | Pluggable `GameMode` resource; FFA and TDM implementations with team scoring, win conditions and per-mode spawns — selectable from the menu |
| **Presentation** | Shared environment/material/HUD style across scenes, settings (sensitivity, per-bus volumes, resolution, PS1-style pixelation), layered audio buses with pooled one-shots, low-fidelity art direction with no crosshair (sights are the reticle) |

## Architecture

Two repos, do not cross-commit:

- **`.`** — the game: scenes, resources, tuning, docs, tooling.
- **`addons/cabra.lat_shooters`** — the core library: ballistics, ammo, armor, health,
  inventory, player, weapon, NPC, UI. This is the framework proper.
- Sibling addons: `cabra.lat_state_machines` (AnimationTree-based FSM), `cabra.lat_interactions`
  (grab/interact), `cabra.lat_terrains`, `libik`.

Layer rule: **data (`.tres`) → logic (addon) → scenes (game)**. Signals travel up; scenes
never reach into another scene's internals. Held items are never physics-simulated — they
are posed. Physics queries live in `_physics_process`, never `_process`.

## Quick start

```bash
# parse/import check (fast, headless, catches GDScript errors)
godot --headless --path . --import

# play (main scene is the menu -> arena)
godot --path . --resolution 1280x720

# headless GPU rendering, invisible (awesomewm-safe), NVIDIA via VirtualGL
DISPLAY=:99 nix shell nixpkgs#virtualgl -c vglrun -d :0 godot --path . <scene>

# everything at once (Godot + VirtualGL + Xvfb + ffmpeg + the local AI toolchain)
nix develop
```

Controls: `WASD` move · `Shift` sprint · `Ctrl` crouch · `Z` prone · `Space` jump ·
`Q`/`E` lean · `RMB` aim · `LMB` fire · `R` reload · `1`/`2` weapons · `G` drop ·
`F` interact · `Esc` pause.

## Extending it

**A weapon** — duplicate a `.tres` in `resources/weapons/`, point `view_model` at a
PackedScene under `src/weapons/`, set `ammo_feed`, `firemodes`, `firerate`,
`attach_points`, and the sight group (`sight_height_over_bore`, `zero_distance`).
Then run `validate_assets`.

**Ammunition** — add a `.tres` under `resources/ammo/`. `reference_penetration` (mm RHA at
`reference_distance`) anchors the armor model; `light_bleed_chance`, `feed_failure`,
`misfire`, `durability_burn` drive terminal effects; `projectile_count` > 1 for shot loads.

**An attachment** — add a scene under `src/attachments/` and a mount under the weapon's
`attach_points` bitmask; stat modifiers (`recoil_modifier`, `ergonomics_modifier`,
`sound_suppression`, `magnification`) are read by the weapon.

**A game mode** — extend `GameMode` (`scenes/game_mode.gd`): implement `assign_team`,
`get_spawn`, `on_kill`, `is_match_over`, `get_scores` and set `team_count`,
`score_limit`, `friendly_fire`.

**A level** — build a small scene with a `WorldEnvironment`, a player instance and
spawn/extraction markers, then wire a manager that owns a `Raid` and a `GameMode`.
`scenes/arena_blockout.tscn` + `arena_manager.gd` is the reference implementation.

**A medical item** — add a `.tres` with `MedicalItem` (use time, effects, conditions
treated). Provenance for the shipped values is recorded in `docs/medical-items.md`.

## Verification

**One command runs every gate and returns one exit code — the same thing CI runs.**
This is the main verification path for humans and CI:

```bash
tools/verify-all.sh                  # import/parse + 6 harnesses + qa audit
tools/verify-all.sh --quick          # import/parse + assets only (fast)
tools/verify-all.sh --with-export    # also build Linux/Windows binaries
tools/verify-all.sh --no-qa          # skip the qa quality gate
```

It prints `PASS/FAIL/WARN/SKIP` per gate and exits non-zero if any hard gate fails.
The parse gate is twofold: `godot --import` **plus** `check_scripts.gd`, which
compiles every project `.gd`. This matters because `godot --import` exits `0` even
for a broken unreferenced script — so the old import-only CI step could never fail.
The qa audit is graded: a `BLOCKER` is hard, a `MAJOR` regression is only a warning
(`--qa-soft` downgrades even BLOCKER).

Each gate can still be run individually:

```bash
godot --headless --path . --script res://addons/cabra.lat_shooters/test/validate_assets.gd
godot --headless --path . --script res://addons/cabra.lat_shooters/test/validate_ballistics.gd
godot --headless --path . --script res://addons/cabra.lat_shooters/test/validate_weapon_mechanics.gd
```

**Shipping gate** — build a real binary. Export templates matching the engine
version are provisioned by the dev shell (`nix develop` links
`share/godot/export_templates/<version>` into `~/.local/share/godot/export_templates`);
outside the shell, install the matching templates manually.
```bash
godot --headless --path . --export-release "Linux/X11" /tmp/shooter/export/fps-basegame.x86_64
godot --headless --path . --export-release "Windows Desktop" /tmp/shooter/export/fps-basegame.exe
```
Presets live in `export_presets.cfg`; CI runs the gates above and keeps the export job
behind the `RUN_EXPORT` repo variable so a missing template never reddens the build.

`validate_assets.gd` loads **every** weapon, ammo, armor, attachment, magazine and
viewmodel (123 checks) and fails on dead script UIDs — the class of bug that silently
killed 53 assets in an earlier pass.

Visual/numeric verification runs on real GPU through the VirtualGL recipe above; evidence
(frames, strips, GIFs, logs) goes to `/tmp/shooter/`, never into the repo.

An optional **AI judgment oracle** lives in `addons/cabra.lat_shooters/test/jev/` with three
backends — `deterministic` (pure code, **the only source of truth in CI**), `jev` (cloud
System-One model via OpenCode Zen) and `laya` (local, offline, `$0`). Model verdicts are an
auxiliary signal with confidence, never a gate. See `docs/ai-local-models-survey.md`.

## Working on it with agents

Development is driven by a small fleet coordinated over a file-based message bus (**AMQ**)
and terminal supervision (**herdr**):

- `.opencode/bus/STATUS.md` — the shared board (claims live here, not in chat).
- `.opencode/agents/*.md` — one brief per workstream owner: `ballistics`, `player-rig`,
  `range`, `npc-body`, `meta`, `testkit`, `spotter`.
- Protocol (AGENTS.md rule 7): drain your inbox, claim on the board, **reply to the sender
  on the same thread**, report in five parts (asked / done + files / evidence / blockers /
  board), never invent results.
- `tools/amq-herdr-bridge.mjs` — closes the loop: when an idle agent has unread mail it is
  prompted to drain; a working agent is left alone; a blocked one raises one alert.

```bash
node tools/amq-herdr-bridge.mjs --once --dry-run   # preview
node tools/amq-herdr-bridge.mjs                    # daemon
```

## Layout

```
addons/cabra.lat_shooters/     core framework (ballistics, ammo, armor, health,
                               inventory, player, weapon, npc, ui)
addons/cabra.lat_state_machines/  AnimationTree FSM used by player and weapons
scenes/                        main_menu, arena_blockout (+manager), debug_range,
                               debug_movement, test terrain
resources/                     weapons, ammo, armor, attachments, magazines, medical
src/                           game-side weapon/attachment/NPC scenes
tools/                         reference-wiki scraper, amq<->herdr bridge
docs/                          genre-feature-survey, ai-local-models-survey,
                               medical-items (provenance)
.opencode/                     agent briefs, board, commands, skills
flake.nix                      dev shell (godot, virtualgl, ffmpeg, local AI)
```

## Roadmap

Done: raid loop, extraction, ballistics to genre depth, survival, perception, game modes.
In flight: **persistence** (stash + profile save/load + raid outcome resolution),
**AI depth** (cover, squads, looting, difficulty tiers), **weapon mechanics** (malfunctions,
durability wear, ergonomics). Next: quests + skills on the raid event bus, traders/insurance,
framework docs and export presets.

See `docs/genre-feature-survey.md` for the full feature-by-feature gap analysis against the
genre.
