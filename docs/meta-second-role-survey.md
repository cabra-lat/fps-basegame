# Second role (Contractor / Drifter) — deepened survey

Design only. No API, no code, no save changes — per the coordinator's approval
("se quiser adiantar, só o aprofundamento do levantamento"). This answers the three
questions the coordinator flagged as verification-first: the **role boundary**,
**karma vs trader reputation**, and the **state shape** — plus one blocking finding
about save migration found while grounding this in the current code.

## 1. What already exists (grounded, not assumed)

| Thing | Where | Consequence for this feature |
|---|---|---|
| `PlayerProfile.Faction {PMC, SCAV}` | `scenes/player_profile.gd:8` | The two roles already exist as an enum — but with borrowed names (identity rule: rename to neutral `CONTRACTOR`/`DRIFTER`). |
| `profile.faction` is **live** | read by `ExtractionPoint.can_use()` (`extraction_point.gd:58-64`), printed by `arena_manager.gd:281` | Role is already a runtime field that gates content. No new concept needed: keep `faction` as the **active** role. |
| `ExtractionPoint.Faction {ALL, PMC_ONLY, SCAV_ONLY}` | `extraction_point.gd:9` | Per-role extraction gates exist. Rename values only. |
| One `stash`, one `loadout`, one `currency`, one `inventory` | `src/meta/meta_profile.gd` | The economy is already single-account. This is what makes "one save, per-role state" cheap. |
| `prepare_raid()` moves `loadout` → Equipment; `resolve_raid()` loot → `stash`, kit kept on survive / forfeited on death | `meta_service.gd` | The kit lifecycle is already a two-slot model (`loadout` = deployed, `stash` = banked). Per-role kits slot into it without changing resolution. |
| `VERSION := 1`, and `ProfileStore` **quarantines** any other version | `meta_profile.gd:9`, `profile_store.gd:53-57` | ⚠️ **Blocking**: bumping the version for `roles` would *discard* every existing save (fresh profile + `.corrupt-*`). See §6. |

## 2. State shape: one profile, per-role state

Keep `faction` as the **active role** (so every existing reader keeps working), and add a
per-role state map alongside it:

```
MetaProfile
  faction: Faction              # ACTIVE role — unchanged meaning, unchanged readers
  team, currency, inventory     # SHARED (account-level)
  stash                          # SHARED (one bank)
  loadout                        # ACTIVE role's deployed kit (existing key, unchanged)
  roles: {                       # NEW — per-role state, keyed by role id
    "contractor": { "karma": int, "loadout": Dictionary, "raids": int, "survived": int, "kia": int },
    "drifter":    { "karma": int, "loadout": Dictionary, "raids": int, "survived": int, "kia": int },
  }
```

**Shared vs per-role, and why:**

| State | Scope | Rationale |
|---|---|---|
| `stash`, `currency` | shared | One bank. Two banks would double the persistence/migration/corruption surface the coordinator explicitly wants to avoid, and would need a transfer UI (new feature, new exploit). |
| `inventory` (key items), `team` | shared | Account-level identity; extraction gates read them and must not depend on which role is active. |
| skills (`progress.skills`) | shared | Skills are use-based on the *player*, and they feed `PlayerSurvival` hooks. Making them per-role would mean two characters' physiology in one body. |
| trader reputation (`progress.traders`) | shared | It is a per-trader relationship earned by trade/quest. See §4 — deliberately **not** per-role. |
| `loadout` (the kit) | **per-role** | The core of the feature: each role enters with its own kit. |
| karma | **per-role** | Karma is role behaviour, not account behaviour. |
| `raids`/`survived`/`kia` counters | **per-role** (plus the existing account-level counters kept) | Lets a role's record be shown without breaking the existing `character_level()`/report paths. |

## 3. The role boundary — what happens to role-2 gear when you return to role 1

This is the leak surface the coordinator will look at first, so it gets the explicit rule.

**Model chosen: shared bank, separate kits, swap only between raids.**

1. **Switching roles is legal only in PREP** (between raids). Not mid-raid, not while a kit is
   deployed. Enforced by the same flag `resolve_raid()` already uses (`_prepared`): a switch is
   refused while a raid is prepared/running.
2. **The switch is a deterministic two-slot swap**, never a copy:
   - active `loadout` → written into `roles[old].loadout`;
   - `roles[new].loadout` → becomes the active `loadout`;
   - `faction` = new role.
   Both slots are always exactly one of {stash, a role's loadout, deployed}; the swap touches
   only the two role slots, so the invariant to verify is **conservation**: the total item
   mass across `stash + all role loadouts` is identical before and after a switch (same check
   style as `INV-13`'s escrow-by-mass).
3. **Loot is role-agnostic once banked.** Anything extracted as Drifter lands in the one stash
   and is therefore usable by Contractor. This is *deliberate* (it is the genre-typical reason
   to run the second role), but it must be **visible, not incidental**: the raid report already
   records `gained`; the role should be stamped on it so the boundary is auditable.
4. **The one exploit to close now, not later:** `grant_starter_loadout()` currently refuses only
   when `loadout` is empty *and* the stash is empty. With two roles that would either (a) hand a
   free kit to the second role every time it is picked while the stash is empty, or (b) hand
   none. Rule: **the starter kit is granted once per role**, tracked as
   `roles[r].starter_granted: bool`, and role-2's starter gear is flagged non-transferable
   (`no_transfer: true` on the encoded item) so it cannot be laundered into the shared bank by
   extracting and then selling. Without this, the free-kit faucet is unbounded.
5. **On death, only the active role's kit is forfeited** — the *other* role's loadout sits in
   `roles[other].loadout` and must be untouched. This is the specific leak to test: KIA as
   Drifter must leave Contractor's kit byte-identical (the existing KIA test already proves
   "stash byte-identical"; extend it to "and the inactive role's kit untouched").

## 4. Karma vs trader reputation — how they coexist

Two axes, one rule, so there are never "two competing reputations":

- **Trader reputation** (`progress.traders[id].rep`) stays exactly as it is: per-trader,
  account-level, earned by trades and quests, consumed by the loyalty ladder
  (`loyalty_level_for(character_level, reputation)`). **Role does not change it.**
- **Role karma** is new, per-role, and gates **role-typical content only**: which extractions a
  role may use, and role-scoped offers/quests. It never substitutes for loyalty.
- **The only interaction**, stated so it can't grow into a second loyalty: an offer/quest may
  declare an *additional* gate `min_role_karma`, evaluated against the **active** role's karma.
  Loyalty gates stock/access as today; karma adds a role filter on top. If an offer has no
  `min_role_karma`, karma is invisible to it — i.e. karma can never *lower* a trader gate, only
  add one.

## 5. Entry point

Role choice lives on the same "enter raid" button the coordinator picked:
`main_menu` → choose role → `MetaService.prepare_raid()` with that role active. Concretely, the
sequence is: `set_active_role(r)` (PREP-only, performs the §3 swap) → existing
`prepare_raid()` → `raid.begin()`. No new scene, no new menu, and `ExtractionPoint.can_use()`
keeps working because `faction` is the active role.

## 6. Blocking finding: a version bump would eat existing saves

`ProfileStore.load_profile()` quarantines **any** `version != MetaProfile.VERSION`
(`profile_store.gd:53-57`) — it does not migrate. Today that is a *safe* default (unknown
future format → start clean). The moment we add `roles` and bump to `2`, every existing `v1`
save is moved to `.corrupt-*` and the player starts from zero — silently, with only a warning.

So the feature has a **hard prerequisite**: a migration step (`v1 → v2`, defaulting
`roles` from the current single `faction`/`loadout`) *before* the version bump, or the bump is a
data-loss event. This is the one item I would not let ship without, and it belongs in the
implementation plan rather than being discovered during it.

## 7. Verification hooks (what an independent verifier should be able to falsify)

1. **Conservation across a switch**: total mass over `stash + all role loadouts` is identical
   before/after any number of role switches; no item exists in two slots.
2. **KIA isolation**: dying as role A leaves role B's `loadout` byte-identical and the stash
   untouched (extends the existing KIA invariant).
3. **Starter faucet**: the starter kit can be granted at most once per role; role-2 starter
   gear cannot reach the shared bank/sale path.
4. **Karma is additive only**: with karma 0 vs max, a trader offer with no `min_role_karma`
   behaves identically; loyalty is unaffected by karma.
5. **Migration**: a real `v1` save (with a loadout and a stash) loads into the new version with
   its stash/currency/loadout intact and `roles` defaulted — no `.corrupt-*` file created.

## 8. Open questions for the coordinator

1. Should role-2 gear be **fully** transferable to role 1 (shared bank, my assumption), or
   should only *non-starter* role-2 gear be transferable? (Affects §3.4's flag scope.)
2. Rename `PlayerProfile.Faction` values to `CONTRACTOR`/`DRIFTER` now, or keep the enum and add
   a display-name mapping? (Rename touches 3 files; mapping touches 1 but leaves borrowed names
   in the enum.)
3. Per-role counters: keep the account-level `raids/survived/kia` *and* add per-role, or move to
   per-role only? (Keeping both is redundant but avoids touching existing report/quest code.)
