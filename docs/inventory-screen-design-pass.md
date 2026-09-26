# Inventory screens: the design pass

Owner: inventory-ux · Card `task_1790435725218_eab3e6` · Written to land **before** the
four screens finish, not after. If a screen in flight contradicts this, the screen changes.

Four screens, one question each:

| Screen | Card | The decision the player is making |
|---|---|---|
| Loadout selection | `0ed569` | What do I take in, and does it still fit? |
| Stash / home | `e48dd5` | What survived, and what do I want next time? |
| Free-items marking | `87ab63` | I own nothing — can I still play, and what am I being given? |
| Post-raid / death summary | `2ed343` | What did I lose, and what is coming back? |

**The test for whether a screen is one screen:** if a single sentence on it answers two of
these questions, it is two screens wearing one skin. Split it.

**Not in scope here, deliberately:** theming, layout constants, visual polish, and any second
drag model. Those are explicit non-goals on all four sibling cards and this document does not
reopen them.

---

## 1. Loadout selection — "what do I take in, and does it still fit?"

**What the player looks at:** the kit as the data model holds it — the equipment slots and the
backpack grid — not a sentence describing it. The hub today composes a loadout into prose:
`scenes/operations_hub.gd:281 _details_text()` returns `option["summary"]` if present, else a
comma-joined list of item names, else `"Sem detalhes fornecidos"`. That is a caption of a kit,
and a caption cannot answer the question the player actually has, which is *does another
magazine still fit*. A loadout screen whose primary surface is text has no space model on
screen, so every capacity question becomes arithmetic in the player's head or a hover.

**The decision, in two moves.** First, which kit to take. Second — and this is the one the
current string surface cannot serve — **what to remove to make room**, which means free cells
and carried mass must be visible *in the kit*, at the point of the decision, not in a corner
of the screen.

**Free cells and mass are the screen's real content.** Both already exist and are already
trustworthy: carried mass is defined by *ownership reachability*, never by which panels are
open (folding a panel must not change your own mass, or mass reads as UI state), and a nested
container is summed once, not once per path. The design consequence is that the loadout screen
shows the same two numbers the raid screen shows, from the same query — a screen that
recomputes them differently is a second source of truth for a value that already has one.

**Deploy validity is a state, not a disabled button.** If the kit cannot be deployed, the screen
says which item is the reason, next to that item. A greyed button with no reason teaches the
player to hunt, and hunting is what they were trying to avoid.

**Item identity comes from the id-to-translation-key registry, never from display text.** A quest
already matches on item identity (`QuestObjective.matches_item`) and the market feed already
leaked raw display text once ("Comprou marked intel" inside a Portuguese sentence). This screen
is the largest surface where that mistake would become normal, because it is the one place the
player is deliberately comparing items by eye.

**Must not show:** anything about the stash. "Take from stash" is the stash screen's decision.
If the loadout screen also lists what is in the stash, it is answering question 2 while
pretending to answer question 1.

---

## 2. Stash / home — "what survived, and what do I want next time?"

**What the player looks at:** owned items, and — this is the part the screen exists for — **the
recoverable subset, visibly marked as recoverable.** The death policy states `loss = 0/CONSUME`,
`recoverable = true`, `preserves_role_kit = true`, with a safe pocket holding the marked intel
and seven medical or consumable entries. A recovery mechanic the player cannot inspect is
indistinguishable from a permanent loss, so the marking is not decoration: it is the difference
between "I lost it" and "I lost it *for now*".

**The grid is not a new grid.** Any stash grid reuses `InventoryContainerUI`'s slots, drag/drop,
rotation, stacking and tooltips (screen inventory decision 5, fixed at
`agent/meta-inventory-docs` c7c33d4). A second drag model in the stash is how drag and click
come to disagree about what a drop means.

### The 109 untranslated descriptions — recommendation and cost

Locally: **122 item `.tres` files carry a `description =` field** and `locale/game.po` carries
22 msgids, none of which are item prose — so item *names* are fully translated and enforced
(`src/meta/validate_i18n.gd:137 _check_item_registry()`), while item *prose* is untranslated
source text. The cards record this as 117/8; the exact denominator depends on how items are
counted, and I am reporting my own count rather than the cards' because the debt must be
countable from one place.

Three options, and the recommendation:

1. **Show the raw source text.** Rejected. It puts an English paragraph inside a Portuguese
   frame, which is the exact defect class that has already leaked twice in this project
   (`RaidReport.summary()` composes `"%d segurados voltam depois"` as a literal, next to an
   English branch `"%d item(ns) no stash"`, in the same function). Normalising it is how the
   frame stops being a signal.
2. **Script 109 msgids out of the `.tres` prose.** Rejected, and it is explicitly forbidden on
   the card. It makes the number move by making the check weaker: every one of those strings
   becomes a declared key nobody reviewed, and the i18n gate then reports "translated" for text
   that was never read by a human in context.
3. **RECOMMENDED — an explicit "translation pending" state on the prose, and the debt stated
   once, visibly.** The row renders its name, mass, stack and legality normally (all of which
   come from the registry and are already correct); only the *prose* is replaced by a neutral
   placeholder line, and the top of the list states the debt in one line — "N of M item
   descriptions are not translated yet". The row is a `PROSE_PENDING` state, not a broken row.

**What it costs, honestly:** the stash looks unfinished in pt_BR, on purpose, and a reviewer will
read that as a defect. The mitigation is that the number is on the screen and in the gate, so
the debt is legible instead of silent — and a stash that renders empty for 109 of 117 rows is
worse than one that admits it. The other cost is one new catalogue key plus one tooltip branch,
and the discipline that the key must be authored, never derived.

**The debt must be assertable, not just stated.** `validate_i18n.gd` should report the untranslated
description count so the number cannot drift in either direction: a *drop* is a fix, a *rise* is
a regression, and a row added with prose and no key is a new debt.

---

## 3. Free-items marking — "I own nothing: can I still play, and what am I being given?"

**What the player looks at:** the starter set, marked as *issued* — visibly distinct from owned
gear, and visibly not a shop. The behaviour the user described is "if you dont have any you mark
free items and press play", and the screen has exactly one job: make the player able to deploy,
and make it unambiguous that they are being issued kit rather than offered a purchase.

**The starter set is DATA, not a UI branch.** A hardcoded fallback inside the hub is how this
project produced a hardcoded Portuguese catalogue (416e7e1), a hardcoded ccache shim, and a
hardcoded comparison operator (e043fa5) — all of which drift silently from the thing they
duplicate. The free set belongs in a resource listing ids, resolved through the same registry as
every other item, so renaming an item cannot leave the hub offering a ghost. `meta`'s
`ensure_playable_loadout()` already implements it as data (agent/meta-flow 378df2f); this card
is the screen and the durable assertion, not a new mechanism.

**"Free" must not read as "unlimited".** Starter gear stays `no_transfer`, and a refill requires
having lost every weapon in a real raid. So the row says what it is — issued starter gear, not
tradeable — because a player who believes starter gear is fungible will try to move it and find
out at the worst moment. This is the one place where a word on the screen is the whole feature.

**The decision is one click and must stay one click.** No sub-screen, no wizard: mark → deploy.
Anything that makes the empty-save path longer than the normal path teaches players to hoard
rather than to play, which is the opposite of what a free-entry rule is for.

---

## 4. Post-raid and death summary — "what did I lose, and what is coming back?"

**What the player looks at:** three classes, and all three always visible:

- **KEPT** — returned to the stash.
- **LOST** — gone (policy `loss = 0`, `CONSUME`).
- **RECOVERABLE** — in the safe pocket, coming back.

**The gap is real and it is exactly the half the card names.** `src/meta/raid_report.gd:12-13`
has `gained` and `lost` and **no `kept` anywhere in the file**. So today the report can say what
you lost and what you gained, and has nothing at all for "kept" — which is the half that makes
the safe pocket honest. The design answer: `kept` is not a new concept for this screen to
define, it is the death policy's own result. If the summary computes its own kept-list it becomes
a second source of truth for a value that has just been given one, and the two will disagree in
exactly the case the player cares about. It waits for the policy, then reports what the policy
kept. (`fe42546` is unpushed, so this is a dependency, not a design choice.)

**The summary is composed from machine reasons, which is the leak shape.** `RaidReport.summary()`
builds a player-visible sentence out of literals in two languages in the same function, and
`ExtractionPoint.can_use()` reasons are the same class of string that leaked Portuguese inside an
English frame. Design rule, and it is the rule the four screens share: **nothing a player reads
is a composed literal.** The summary composes *keys*; the catalogue renders them; the policy
supplies the facts. Then the pt_BR assertion has something to assert, and `validate_factions.gd`'s
existing contract at 127,186 has something to protect.

**The decision the player is making here is forward-looking.** Not "what happened" (the raid was
watched) but "what do I do about it" — and the only actionable thing in a death is the
recoverable list, so that list is the screen's centre of gravity, not a footnote under a loss
count.

---

## Rules that hold across all four

1. **One decision per screen.** The table at the top is the test.
2. **One row model.** Identity from the registry, legality from the *same* validate-then-commit
   entry point drag/drop uses (two parallel implementations satisfy the sentence in a document
   and not in the game), tooltip *signature* from the owning slot while the stat source stays the
   item's own resources.
3. **Nothing a player reads is a composed literal.** Machine reasons are keys, always.
4. **Reuse, do not re-model.** Out-of-raid grids are `InventoryContainerUI`; there is no second
   drag model, and the reuse cost assertions in `validate_inventory_ux.gd`
   (`_check_ui_rebuild_cost()`) apply to any new grid as written.
5. **Mass and free space are ownership-reachable, never panel-state.** Folding a panel must not
   change your own numbers.

## Harness discipline for anything these screens assert

Written down here because the screens will trip it, and the rule is not optional:

- **Any assertion reading `position`, `size`, `scroll_*` or a global rect must first establish
  that the state change happened, that layout was re-evaluated (an awaited frame or an explicit
  trigger), and that the thing being read demonstrably settled** — moved, or demonstrably did
  not, whichever the assertion is about. A value returned by a system that has not done the thing
  yet is a real-looking number that means nothing.
- **A hidden root runs no container layout.** A screen that opens a panel while its root is
  hidden and then reads a position is reading last frame's layout. This is not hypothetical: it
  is why the corpse-panel scroll check calls `show()` and awaits frames before reading anything.
- **A green layout assertion ships a constructed break** proving it can go red. Do not report a
  passing layout assertion as evidence without one.
- **Pooled UI keeps stack order equal to open order.** Released panels stay parented, so a
  popped panel that is not moved to the end of its box can be laid out *above* one that was
  opened before it — player-visible, and it invalidates position math done per index.

## Open slots — these are the user's calls, not mine

Written as slots with both shapes and **no recommendation**, because answering them here would be
a decision wearing the costume of a design pass.

**Slot A — faction / role-kit switch in the hub.** Unresolved.
- **Shape A1:** a role/kit selector beside the loadout list; picking a role replaces the whole kit.
- **Shape A2:** no switch — the role kit is fixed at profile creation and the hub only displays it.
- *What each costs, because this is the part that is hard to reverse:* A1 makes the death
  summary's kept/recoverable list vary per role, so the summary has to be parameterised by the
  kit; A2 means a player who picks the wrong role at creation has no in-game way to change it.
  The death-summary card is already sequenced behind this answer, so the cost lands there.

**Slot B — abandon confirmation on Pause.** Unresolved.
- **Shape B1:** a confirmation that names what is at risk, using the policy's own numbers (what is
  lost, what is recoverable) rather than a generic "are you sure".
- **Shape B2:** single-tap abandon with a short undo window.
- *Costs:* B1 interrupts every player, including the 95% who did not mean to press it; B2 costs a
  mis-tap, and our death policy currently has no `kept` concept to soften what a mis-tap takes.

## Evidence, so nobody has to trust this

- `scenes/operations_hub.gd:281` `_details_text()` — the loadout-as-prose surface.
- `src/meta/raid_report.gd:12-13,21-23` — `gained`/`lost`, no `kept`; two languages in one
  composed summary.
- `src/meta/validate_i18n.gd:137` — item *names* enforced translated; item *prose* is not.
- 122 item `.tres` files carry `description =`; `locale/game.po` has 22 msgids, none of them item
  prose.
- `addons/cabra.lat_shooters/src/ui/inventory/equipment.gd:66-72` — UI maps 5 core slots of 7;
  `arms`/`legs` are authoritative and displayed nowhere, and a mapped `Loadout/utility` slot can
  never hold anything (`Equipment.get_equipped()` returns `[]` for a non-core key). Carried into
  the loadout screen as-is: **the screen shows the core slot set or it is lying by omission.**
- `addons/cabra.lat_shooters/test/validate_inventory_ux.gd:138` `_check_ui_rebuild_cost()`,
  `:194` `_check_corpse_panel_scroll()` — reuse and layout-read discipline, both with negative arms.
