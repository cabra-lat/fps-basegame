# Player rig: what it owns, and which of its numbers are hand-set

Board card `task_1790427559412_78fee2`. Step (1) of the proposed order, and the
only step that needs neither GPU time nor a lock.

**Scope.** This is an inventory, not a rebuild proposal. Nothing here has been
changed; no file under `addons/cabra.lat_shooters/` was edited. The rig passes
LOC-02..LOC-07 with 63 checks green, so the *parameters* are not the reported
problem. The point of this document is to make a later rebuild safe, by writing
down what the rig is responsible for and separating values that are taste from
values that are consequences of other values.

Everything below was read from the working tree at `b93618e`.

---

## 1. Correction to the card's premise

The card proposes deriving rig values "from capsule dimensions or camera FOV".
Two corrections, both load-bearing:

**There is no capsule.** The player collider is a
`BoxShape3D_hwib0`, `size = (0.330, 0.181, 1.716)` m
(`src/player/scenes/player.tscn:178`), rotated 88.58° about X so the long axis
stands up. Half-width 0.165, half-height 0.858. The rig calls this a capsule
throughout (`CAPSULE_STAND`, `capsule_factor`, `_apply_capsule_stance`), which
is a naming debt, not a geometry one — but any derivation written against
"capsule radius" will be wrong by construction.

**The camera FOV in the .tscn is dead.** `Camera3D.fov = 55.37519`
(`player.tscn:95`) is overwritten every frame from config:
`camera.fov = lerp(camera.fov, current_camera_fov, stance_t)` with
`current_camera_fov = config.default_fov` (`controller.gd:865, 892, 899`).
`config.default_fov` is `50.0`. So the .tscn literal is not merely hand-set, it
is *inert* — a designer editing it would see no effect and no warning. This is
the clearest single example of the class of problem this card is about.

---

## 2. What the player rig owns

The rig is not one thing. It is four layers with different owners and different
correctness criteria, currently interleaved in the same files.

| Layer | Lives in | Owns | Should be judged on |
|---|---|---|---|
| Body/collider stance | `controller.gd` `_apply_capsule_stance`, `player.tscn` collider | box size across stand/crouch/prone | one collider, one scale source |
| Eye + camera | `controller.gd` L860-900, `config.gd` | eye height, FOV, stance smoothing | derived from stance + FOV budget |
| Foot placement | `ik.gd` (analytic, own solver) | stride, step height, foot spacing | reachable targets, not literals |
| Viewmodel (arms/held) | `viewmodel_rig.gd` | hip offset, grips, ADS, sway/bob | derived from weapon sockets + camera |

A fourth, separate owner: `humanoid_rig.gd` owns the *shared* skeleton used by
player and NPC, and carries a standing warning that GodotIK is not to be trusted
for arms. See §5.

**Who does NOT own the rig:** `addons/cabra.lat_shooters/` is a git submodule
(`.gitmodules`), so every number below lives in a different repository from this
document. Any change to them is a submodule commit, not a game-repo commit.

---

## 3. The literal-versus-derived inventory

Three verdicts: **DERIVED** (should be computed from something else, and is
currently typed), **TUNED** (genuine taste, correctly a named constant), and
**DEAD** (no effect; a trap for the next editor).

### 3.1 Three heights for one body

| Value | Where | Number | Note |
|---|---|---|---|
| Collider height | `player.tscn` `BoxShape3D_hwib0` | 1.716 | the physical truth |
| `config.stand_height` | `config.gd:19` | 1.70 | assigned at `controller.gd:864` |
| `EYE_STAND` | `player_movement_parameters.gd:9` | 1.62 | assigned to `camera_height` at `player_movement_parameters.gd:88` |

Three numbers for one body. The first two are close enough to look intentional
and are 1.6 cm apart, so a future collider change moves the collider and
silently desynchronises the eye. The third is worse: `EYE_STAND` is the
resolver's own stand eye height and it overrides the config value for the same
slot, so the stand height is decided in two places and the resolver wins 1.62
against the config's 1.70. **VERDICT: DERIVED** — eye height should be
`collider_height * k` with one `k`, and the collider should be the single source.

### 3.2 The crouch/prone ratio is written down twice, with different values

| Encoding | Stand | Crouch | Prone | Where |
|---|---|---|---|---|
| Collider stance | 1.0 | 0.55 | 0.35 | `player_movement_parameters.gd:12-14` → `capsule_factor` → `controller.gd:904` |
| Lean stance | 1.0 | **0.6** | **0.25** | `controller.gd:122-123` → `_lean_stance_scale()` |

Both scale the same body box. The lean path computes a wall-clamp margin
(`LEAN_PEEK_MARGIN = 0.25`, commented "body radius") against a body it believes
is 0.6/0.25 of full size, while the collider is actually 0.55/0.35. In prone the
disagreement is 0.25 vs 0.35 — 29% — so the corner-peek clamp is tested against
a body that is not the body. **VERDICT: DERIVED** — one stance-scale table, read
by both consumers.

### 3.3 Lean constants that describe geometry as if it were feel

| Constant | Value | Comment claims | Reality |
|---|---|---|---|
| `LEAN_PEEK_OFFSET` | 0.45 m | "lateral eye travel at full lean" | half-width (0.165) + margin (0.25) = 0.415; the literal is 0.035 m adrift |
| `LEAN_PEEK_MARGIN` | 0.25 m | "body radius" | half-width is 0.165; 0.25 is neither radius nor any measured dimension |

The comment on `LEAN_PEEK_MARGIN` is the problem: it claims a derivation that
does not hold, which is why the number survived. **VERDICT:** `LEAN_PEEK_OFFSET`
DERIVED (from collider half-width + margin), `LEAN_PEEK_MARGIN` TUNED but
**mislabelled** — the comment must stop asserting it is a body radius.

### 3.4 Foot IK exports are a second, unrelated tuning surface

`ik.gd:19-23`: `stride_length = 1.2`, `step_height = 0.3`, `step_speed = 5.0`,
`foot_spacing = 0.25`, `max_foot_distance = 1.5`.

These are `@export`s on a helper, not on the player, so they are invisible in the
player scene inspector and carry none of `config.gd`'s derivation discipline.
`foot_spacing` in particular is a body-width quantity and would follow from the
collider; `max_foot_distance` is a reachability guard whose correct value
depends on `stride_length` and leg length, so it should be computed from them.
**VERDICT: mixed** — `foot_spacing` DERIVED, `max_foot_distance` DERIVED from
leg length, `step_height`/`step_speed` TUNED.

### 3.5 Viewmodel offsets that should come from the weapon

`viewmodel_rig.gd:13-15,21-22`:

```
HIP_OFFSET        := Vector3(0.22, -0.20, -0.45)
GRIP_R            := Vector3(0.0, -0.09,  0.02)
GRIP_L            := Vector3(0.0, -0.08, -0.28)
DEFAULT_ADS_OFFSET:= Vector3(0.0, -0.135, -0.32)
ADS_DEPTH         := -0.32
```

These are hand-placed rest poses for the hands and the gun. Every one of them
describes a relationship between the camera and *a specific weapon's* sockets,
typed as a constant in the rig. Change a weapon and the rig is wrong for it;
nothing reports that. `ADS_DEPTH` ("gun-to-eye distance at full ADS") is a
function of weapon length and the aim FOV, both of which exist. **VERDICT:
DERIVED** — read from the weapon's grip/muzzle sockets and FOV, with the current
values kept as the fallback for weapons that do not publish sockets. This is the
largest single block of typed geometry in the rig, and the clearest candidate
for "redo properly, not patch".

### 3.6 Correctly tuned — leave alone

`STANCE_SMOOTH_RATE = 6.0` (documented time constant, QA-016),
`LEAN_ROLL_MAX` / `LEAN_BODY_MAX` (angles), `LEAN_VISUAL_RATE`,
`ADS_K` / `SWAY_K` / `KICK_K` / `DIP_K` / `BOB_FREQ` (blend rates),
`debug_fly_speed = 10000.0` (debug only). These are rate and angle choices with
no derivable parent. They are already named, commented, and grouped.

### 3.7 Unnamed literals still inline in code

`controller.gd:965-968`:

```gdscript
_tremor_phase += delta * 7.5
return Vector2(sin(_tremor_phase) * amp,
               sin(_tremor_phase * 1.7 + 1.3) * amp * 0.7)
```

`7.5` is a tremor frequency in Hz, `1.7` a phase multiplier, `1.3` a phase
offset, `0.7` an amplitude ratio. Four tuned values, none named, sitting in the
middle of a function. The file has a named-constant convention (L112-124) and
these four simply escaped it. **VERDICT: TUNED but UNNAMED** — promote to
constants for consistency; the values themselves are fine.

---

## 4. Counts

| File | lines | `config.*` refs | bare float literals | named constants |
|---|---|---|---|---|
| `controller.gd` | 1190 | 12 | 90 | 13 (L112-124) |
| `viewmodel_rig.gd` | 340 | — | 72 | 9+ |
| `ik.gd` | 201 | — | 24 | 0 (all `@export`) |
| `humanoid_rig.gd` | 375 | — | — | — |

The ratio that matters is not the raw literal count — most of the 90 are `0.0`
state initialisers and `1.0` identities, which are correct. It is that 90
literals coexist with a typed `PlayerConfig` resource and a
`PlayerMovementParameters` resolver that were built specifically to remove them.
Two of the three encoding systems predate the other and were never reconciled.
**That** is the actual shape of the debt: not "too many magic numbers" but
"three partial attempts to remove them, none of them complete".

---

## 5. One thing that changed while writing this

`humanoid_rig.gd` carries this standing note:

> the GodotIK GDExtension proved to never apply its solve (effector moved 1 m,
> hand moved 0.0000, isolated, 2026-09-22), so no code path may depend on it
> for arms.

That observation is **correct about the skeleton pose cache and wrong about the
solver**. Measured today on the live 87-bone rig:

- Reading the solve through `Skeleton3D` bone poses shows no movement — which is
  what the 2026-09-22 note measured, and it is a property of *where you look*,
  not of the solver.
- Reading it through `GodotIK.get_bone_position()` returns a live solved
  position.
- Against a same-input FABRIK solve on the same rig: arms and head agree to
  under 0.1 mm; the two legs return an identical residual to each other.

So the constraint "no code path may depend on GodotIK for arms" is still the
right *policy* — the player uses its own analytic solver and nothing should
change — but its stated *reason* is wrong, and the wrong reason will mislead
whoever next tries to retire the analytic solver. Recommend amending the comment
rather than the code.

---

## 6. The question that has to be answered before a rebuild

The card is right that this is a product call. It changes what "redo" means, and
it is not derivable from the code:

> Is the target a **grounded shooter with a committed strafe**, or a **movement
> shooter with a procedural sprint**?

They need different rigs. A committed strafe is an authored, finite set of
locomotion states with authored transitions — its rig is mostly data and can be
tuned safely. A procedural sprint needs continuous, derivable, physically
coupled parameters — in which case §3.1-3.5 stop being cleanup and become
prerequisites, because a procedural rig cannot carry three disagreeing stance
encodings.

Until that is answered, the safe order is:

1. Land this inventory.
2. Fix the items in §3 that are **wrong regardless of the answer**: the dead
   `.tscn` FOV (§1), the double stance encoding (§3.2), the false "body radius"
   comment (§3.3). These are defects, not taste, and they are small.
3. Ask the question. Then decide rebuild vs. derive-in-place.

Step 2 is deliberately small and does not depend on the product call.
