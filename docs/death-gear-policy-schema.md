# Death and gear policy: the schema first, so the post-death dead end is configuration

Status: design, for the human's decision. Nothing in here is implemented.
Scope: `task_1790381416376_020326` (policy schema) and
`task_1790377289975_a7fc59` (the dead end that follows from it).

## 0. What I measured first, because it changes which question you are answering

The dead-end card's mechanism says a *clear* consumes the kit. It does not.
Measured on the real `MetaService` and the real `operations_hub.tscn` node:

| after | `loadout_restored` | `profile.loadout` | `validate_deploy` | hub state | `can_deploy()` |
|---|---|---|---|---|---|
| a **clear** | `true` | `["primary","secondary"]` | ok | VALID (1) | **true** |
| a **death** | `false` | `[]` | `selecao vazia` | EMPTY (0) | **false** |

`MetaService._resolve_survival()` restores the kit deliberately — *"the equipped
kit stays available for the next raid"*. The branch that consumes it is the KIA
one (`meta_service.gd:286`): `profile.loadout = _deploy_leftovers if _prepared
else {}`. The same restoration code is present on `5348011`, the tree the
instrumented hub visits ran on, so this is not a tree skew.

So option **(a) on the card — "nothing is consumed, a clear always returns a
deployable kit" — is already shipped behaviour**, and the real question is what a
player gets after **dying**. Everything below is scoped to that.

Two smaller corrections, both from reading the same code:

- **The picker is never removed.** Nothing in `operations_hub.gd` hides it;
  `_rebuild_picker()` repopulates it in every state. What the run recorded as
  "'Active kit' absent" is that on that tree the label const read
  `"Loadout ativo"` (hardcoded Portuguese) — the English key did not exist yet. It
  does now, as a translation key, after the hub localization commit. So that
  symptom was a language artifact, not a missing control.
- **`loadout_state` 2 (INVALID) is the partial case**, not the death case: it
  needs a non-empty loadout that fails validation, e.g. a slot that never
  equipped leaving the profile without its primary. A clean death gives EMPTY
  (0). If you want the INVALID arm pinned too, it is one more probe.

## 1. The three mechanics are all values, and one resource already exists

`(a)` safe pocket, `(b)` free-entry role, `(c)` recoverable gear are policy, not
code, and the project already has the pattern: `src/meta/starter_loadout.gd` is a
`Resource` holding `currency` and `slots`, and the AGENTS rule is *content is
data, mechanics may be enums*. So the answer is not "data over code, but idk" —
it is the pattern this repo already follows, and the work is to finish it.

One structural point that is cheap now and expensive later: **policy must be read
at the settlement boundary, not at the UI.** The dead end exists because the
death branch (`meta_service.gd:286`) and the hub's projection
(`deploy_options()`) each assume "no kit means no deploy", and nothing in between
carries a *reason*. A policy resource changes that one thing.

## 2. The schema

Three resources, no new code paths, all read at settlement.

### 2.1 `DeathPolicy` — what a death costs

```gdscript
class_name DeathPolicy extends Resource

enum Loss {
    CONSUME,          # the deployed kit is lost (today's behaviour)
    REGRANT,          # the kit is lost and a starter kit is granted
    PRESERVE_STASH,   # the kit is lost; the stash is the recovery path
}

@export var loss: Loss = Loss.CONSUME
@export var starter: StarterLoadout = null      # used when loss == REGRANT
@export var grant_currency_on_regrant: int = 0  # 0 = the starter's own value
@export var preserves_role_kit: bool = true     # free-entry role kit is never lost
@export var recoverable: bool = false           # mechanic (c), see 2.3
```

`recoverable` is a **setting**, as the original request suspected. It is one
export on the policy, not a mode.

### 2.2 `ItemDef.keep_on_death` — the safe pocket, per item

`class_name ItemDef extends Resource` (extending the existing item resource, so
no new file per item) gains:

```gdscript
@export var keep_on_death: bool = false   # the safe pocket
```

Cheap by design: it is a per-item flag exactly as the request describes, and it
reads from the item resources the game already loads. It composes with the
existing `no_transfer` meta flag rather than replacing it — `no_transfer` stops
laundering, `keep_on_death` stops loss; they are different questions and merging
them would make one of them wrong.

### 2.3 `RoleDefinition` — the free-entry role, declared not coded

`StarterLoadout` already exists; the role is the thing that names it.

```gdscript
class_name RoleDefinition extends Resource

@export var id: StringName
@export var display_name_key: String   # a PO msgid, not a literal
@export var grants: StarterLoadout = null
@export var on_entry: EntryPolicy      # GRANT_ALWAYS | GRANT_ONCE
```

The neutral display name lives in the `.tres` — which is the naming constraint and
the requested architecture pointing at the same place, exactly as the card
observed. No commercial name ships; `display_name_key` is a translation key like
every other player-visible string after this series.

### 2.4 Reading it

One call at the death boundary, replacing the bare `else {}`:

```gdscript
profile.loadout = _apply_death_policy(carried_loadout, _deploy_leftovers, policy)
```

`LOS` and `REGRANT` are the two live options; `PRESERVE_STASH` is what the
existing stash already is, written down so the choice is visible.

## 3. Why the schema first, and what it costs

The sequencing question on the card is mine to recommend, and the argument is not
"small and reusable" — it is that **the hub has nothing to render without it**.

Option (c) on the card says the hub *must* show the re-acquisition path rather
than deleting the picker. A path is data: what you can reacquire, from whom, at
what cost. None of that exists today, so option (c) is unimplementable as stated
without the schema. Options (a) and (b) are one line each and need no schema —
but choosing (b) puts a `StarterLoadout` reference in the death path, which *is*
the schema, just with one field filled in. So every branch except (d) ends up
needing it, and (d) is a decision to leave a dead end in place.

My recommendation: **schema first, one field, defaulting to today's behaviour.**
The default is `Loss.CONSUME`, so landing it changes no gameplay, the harness
stays green, and the human's answer becomes a one-line `.tres` edit instead of a
code change. That is the whole argument, and it is cheap enough to be worth
making before the decision rather than after.

## 4. What I am not doing, and what I need

- **Not choosing.** `(a)` is already shipped; `(b)` and `(c)` are visibly
  different products; `(d)` should be written down as a decision if chosen. The
  human picks. I will implement whichever, and the schema makes it a value.
- **Not pinning the KIA behaviour.** The only invariant I added pins the
  *survived* half (a survived raid leaves the player deployable), because that
  holds under all four options. Note the existing loss scenario already asserts
  `"loss forfeits the deployed loadout"`, so `(b)` and `(c)` change an existing
  assertion, not just UI.
- **Needed from the human:** the loss answer, and whether the safe pocket starts
  as an empty flag on a handful of items or ships off.

## 5. Naming, per AGENTS

Research and benchmarking two commercial games' hubs is fine in `docs/` — this
file cites neither by name deliberately, since the useful output is the mechanic
not the brand. No faction, item, map, role or trader name from any commercial
game appears in the schema above; `display_name_key` values are PO msgids and the
`.tres` is the declaration. The genre's own ~7-minute run-through rule is
attributed as a mechanic, which is what the identity rule permits.
