# Meta layer — how it works

Everything that **survives a raid**: the profile, the stash, the between-raid loadout,
traders, insurance, the flea market, quests and skills. No combat code, no player code,
no mandatory UI — the layer is headless-testable end to end.

Design rule that shapes all of it: the raid scene (`scenes/raid.gd`) emits an **event bus**
and the meta layer is the consumer. Nothing here reaches into the raid; resolution happens
when `raid_ended(outcome)` fires.

## 1. File map

| File (`src/meta/`) | Role |
|---|---|
| `meta_service.gd` | `MetaService` — the single authority (autoload `Meta`). Owns the profile, listens to the raid bus, exposes the buy/sell/flea API, resolves raids. |
| `meta_profile.gd` | `MetaProfile extends PlayerProfile` — same object the extraction gates use (`faction`/`team`/`currency`/`inventory`), plus stash, loadout, `progress`, counters, `last_report`. |
| `profile_store.gd` | Versioned, atomic save/load. |
| `item_codec.gd` | Item ↔ `Dictionary` (weapon + attachments + magazine + stack + grid position). |
| `stash.gd` | Persistent out-of-raid grid (`InventoryContainer`, 10×20, 200 kg), position-preserving. |
| `market.gd`, `trader.gd`, `trader_offer.gd`, `trader_loyalty.gd` | Traders, stock, reputation, loyalty ladder, barter. |
| `trade_ops.gd` | Shared item/currency/stash primitives — **one** validation path for `Market` *and* `FleaMarket`. |
| `insurance.gd` | Insured manifest, return delay, no-return / killer-loot exclusions. |
| `flea_market.gd`, `flea_listing.gd` | Listings: fee, escrow, expiry on the raid counter. |
| `progression.gd` | Skills + quests, wired to the real hooks and the raid bus. |
| `skill.gd`, `skill_set.gd` | Use-based skills and the XP curve. |
| `quest.gd`, `quest_objective.gd`, `quest_log.gd` | Data-driven quests and their live progress. |
| `raid_report.gd` | End-of-raid summary; persisted so the screen survives a restart. |

Data lives in `resources/meta/`: `traders/` (3), `quests/` (3), `starter_loadout.tres`.
Gates: `validate_meta_{persistence,progression,market,flea}.gd` over the shared
`validate_util.gd`.

## 2. Wiring — the only thing a scene manager has to do

```gdscript
var meta := MetaService.new()          # or the `Meta` autoload
meta.bind_carrier(player.equipment, player.get_equipped_backpack())
meta.bind_raid(raid)
meta.prepare_raid()                    # before raid.begin()
# -> raid_ended(outcome) resolves + saves automatically
```

`enable_progression()` additionally creates the skills/quests consumer
(`bind_raid` / `bind_player` inside it). Keep the meta lane free of static addon
dependencies: `progression.gd` reaches the player duck-typed (`player.get("survival")`)
on purpose so the harnesses stay headless-loadable.

## 3. Raid resolution — what each outcome does

`resolve_raid(outcome, exp)` is the heart. `SURVIVED` and `RUN_THROUGH` take the same
"survived" branch here (loot in, kit kept, payout); the raid decides the outcome label and the
EXP it passes in, and `RUN_THROUGH` is what forfeits quest extraction credit. `KIA`, `MIA` and
`LEFT_BEHIND` forfeit.

| | SURVIVED / RUN_THROUGH | KIA / MIA / LEFT_BEHIND |
|---|---|---|
| carried loot | decoded → stash, each valued | discarded (`loot_discarded`) |
| equipped kit | kept for the next raid (`loadout_restored`) | forfeited, listed in `lost` |
| currency | `sum(item value) + SURVIVAL_REWARD` (5000) | — |
| insurance | — | manifest registered (`register_loss`) |
| counters | `survived += 1` | `kia += 1` |

Then, in this order: due insurance is **delivered** (`process_returns`, *before*
`raids += 1` because `register_loss` stamps `due_raid` off the current counter), `raids += 1`,
`market.on_raid_resolved()`, `flea.on_raid_resolved()`, `last_report = report.to_dict()`,
and finally the save.

Item value (`_item_value`) comes from the item's `extra` resource: `Attachment.cost`, or a
`cost` field when present, else 0.

## 4. Persistence contract

- **One file**, `user://profile.save`, JSON, with a top-level `version` (`MetaProfile.VERSION`).
- **Atomic**: serialize → `user://profile.save.tmp` → `flush()` → rename over the live save.
  A crash mid-write can never truncate the previous save. If the rename is refused
  (Windows-style overwrite), the old file is removed and the rename retried once.
- **Tolerant**: missing, unreadable, unparseable, wrong-shaped or unknown-version saves
  return a **clean profile + a warning** — never a crash — and the bad file is moved aside
  to `profile.save.corrupt-<stamp>` so the data stays inspectable.
- **No absolute paths**: item identity in the save is a `res://` path (via `ItemCodec`).
- **Persisting is the caller's job.** The `MetaProfile`/`Market`/`FleaMarket` APIs mutate
  in-memory state; `Meta.persist()` writes it. `resolve_raid()` saves for you, and the arena
  calls `persist()` in `_market_buy`/`_market_sell`. Calling the API directly and forgetting
  `persist()` loses the operation at close — documented, intentional, and flagged as debt below.

## 5. Traders and the economy

- Definitions are **resources** (`resources/meta/traders/*.tres`); live state (stock,
  reputation, reset counter) lives in `Market.state` and persists inside the profile.
  Saved state for a trader that no longer exists is ignored gracefully.
- `character_level = clampi(1 + total_exp / 1000, 1, 50)`.
- `loyalty_level` = the highest ladder rung whose requirements are met
  (`TraderLoyalty.met(character_level, reputation)`).
- `can_buy` is the single source of truth for the HUD and returns a clear `reason`:
  unknown trader · invalid offer · `loyalty insuficiente (precisa LLn)` · `sem estoque` ·
  `barter insuficiente (…)` · `saldo insuficiente (₽n)`. `can_sell` mirrors it.
- `buy` consumes barter items first, then currency; `sell` takes one unit from the stash and
  credits `sell_price`. Both award reputation:
  `reputation_per_trade + max(buy_price, sell_price) / 1000`.
- Stock resets every `reset_every_raids` resolved raids (`0` = never); `stock_max < 0` =
  unlimited.
- HUD line: `offer_line()` → `Comprar <item> por <price|barter> | Vender por <price> [stock]`.

## 6. Flea market

A second sink for loot, sharing `TradeOps` with the traders.

- **Fee**: `max(100, ceil(price * 0.05))` — a 5 % rate with a floor. Charged on listing and
  **not refunded** on cancel.
- **Escrow**: `list_from_stash` removes the item from the stash and keeps it encoded in the
  listing. `cancel` and expiry return it (stash-full ⇒ the call fails honestly).
- **Seeding**: `seed_from_market` turns every currency trader offer into an NPC listing at
  `ceil(buy_price * 1.25)`. Barter-only lines stay with the trader.
- **Raid clock**: `on_raid_resolved()` expires due listings (`expiry_raids`, default 3;
  `< 0` never expires) and sells a **player** listing when its price is at or below
  `reference_value(item)`.
- **Reference value** (our formula): base by kind — weapon 8000, attachment 3000, medical 1500,
  ammo 150, else 100 — plus `int(mass * 100)`.
- Buying checks: active, not your own listing, affordable; a failed deposit rolls the price
  back (`honest rollback`).

## 7. Insurance

- On `prepare_raid()` (`auto_insure`), the equipped gear is snapshotted as the **insured
  manifest** — that snapshot, not the carried kit, is what can come back.
- On KIA/MIA, `register_loss` schedules the manifest, **excluding** items on the map's
  `no_return` meta and anything in `enemy_looted_paths` (taken by the killer). A no-return map
  insures nothing at all.
- Returns land **one resolved raid later** (`DEFAULT_DELAY_RAIDS`); if the stash is full the
  remainder stays pending for another raid. Insurance pays **nothing else** — no currency.

## 8. Progression

**Skills** are use-based, with XP per unit of real activity:

| Skill | Source hook | Rate |
|---|---|---|
| `endurance` | `survival.stamina_changed` (stamina drained) | 0.1 XP / stamina |
| `strength` | overweight travel sampled in `_physics_process` | 0.2 XP / metre |
| `vitality` | `health.health_changed` (damage taken) | 1 XP / HP |

Curve: `round(100 * 1.5^level)`, max level 50. Fractional XP is carried in `pending`.
Levels are **written into the hooks that already exist**
(`PlayerSurvival.endurance_level` / `.strength_level`) rather than a parallel system.

**Quests** are data-driven `.tres`; the resource is immutable and live progress lives in
`QuestLog`, so several profiles can share one quest. Objective kinds:

- `KILL` — player kills only; optional weapon-name substring.
- `LOOT_ITEM` — optional item-name substring and/or the `medical` tag.
- `EXTRACT_AT` — named extraction point.
- `SURVIVE_EXTRACT` — survive and extract.

`RUN_THROUGH` explicitly does **not** count for `EXTRACT_AT` / `SURVIVE_EXTRACT`. Rewards
(currency, EXP, items, skill XP, trader reputation) are granted on completion and the quest is
claimed; `requires` gates dependents. Saves are throttled to every 5 s while skills tick, and
flushed on raid end.

## 9. Adding content

- **Trader**: drop a `.tres` in `resources/meta/traders/` with `id`, `offers`, `loyalty`
  (and optionally `reset_every_raids`, `reputation_per_trade`). `Market.load_dir()` picks it up;
  new offers start at full stock, saved state is re-applied on load.
- **Quest**: drop a `.tres` in `resources/meta/quests/` with `id`, `objectives`, rewards and
  optional `requires`. Objective filters are plain substrings, so no code change is needed for
  a new kill/loot/extract goal.
- **Item**: any existing `InventoryItem`-derived `.tres` already works — `ItemCodec` encodes it
  generically (weapons keep attachments/magazine, stacks keep counts and position).

## 10. Verification

```bash
for t in persistence progression market flea; do
  godot --headless --path . --script res://src/meta/validate_meta_$t.gd
done
```

Current results (HEAD `50ab5ce`… verified by `spotter` on `7d8b7b0`): persistence 38/38,
progression 34/34, market 45/45, flea 35/35.

Independent verification (spotter, own SceneTree runners — **not** these harnesses): save
atomicity under 28 `kill -9` runs mid-write (published save always intact; 2/28 caught between
`.tmp` write and rename → direct proof of no in-place truncation), corrupt-save quarantine,
escrow proven to move a **real item by mass** (`get_mass()`, not counters), exact economy
arithmetic, and the real arena path (interact → panel → `offer_line()` → buy/sell → reload).
Evidence: `/tmp/shooter/spot_kill_verify.txt`, `/tmp/shooter/spot_meta_verify.txt`,
`/tmp/shooter/spot_arena_verify.txt`.

⚠️ Environment hazard: `.godot/` is shared. Running `godot --import` or harnesses **concurrently**
with another lane corrupts the UID cache and produces **false FAILs** (seen: `market 7/45`,
recovered after a clean re-import). Serialize Godot runs, or re-import clean before trusting a FAIL.

## Known debt

- **Persist is the caller's job.** Calling the profile APIs directly without `persist()` loses the
  operation when the process closes. Intentional and covered by tests; hardening it (auto-persist
  in the `MetaService` wrappers) would be a behaviour change needing re-verification.
