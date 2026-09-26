# Screen inventory — what each screen is for

Audited against `origin/main` `b93618e`. This is a product inventory, not a widget
list: a screen earns its place only if it answers one decision the player is
trying to make. Overlays that merely decorate the current decision are listed as
part of their parent screen, not as separate destinations. The pattern research
and the player-rig recommendation live in
[`genre-ui-ux-survey.md`](genre-ui-ux-survey.md).

## The questions behind the loop

| # | Player question | Screen that should answer it | Current coverage |
|---|---|---|---|
| 1 | What can I do next, and how do I leave? | Main menu | Covered |
| 2 | How do I change input, audio, display and match options? | Settings | Covered |
| 3 | What is my active kit, and can I deploy this raid? | Operations hub | Covered |
| 4 | What do I own, and what can I take into the next raid? | Operations hub stash summary | Partial — readable summary is being added by FLOW task `task_1790427584692_14c46f`; no out-of-raid rearrangement grid yet |
| 5 | Which faction am I active with, and which kit does that give me? | Operations hub | Missing — the hub renders the faction as inert text although `switch_faction()` already swaps the two kits |
| 6 | What is happening in this raid right now? | In-raid HUD | Covered, dense |
| 7 | What am I carrying and what can I move, use or equip? | Inventory | Covered for the raid carrier |
| 8 | What fits where across my containers? | Inventory | Covered by per-container mass/free-cell titles and the opened-container stack; aggregate carried mass is missing |
| 9 | What can I buy or sell here, at what price, and did it succeed? | Trader panel | Covered in-raid; no persistent hub trader screen |
| 10 | How does this weapon perform now, and what will this attachment change? | Gunsmith | Covered |
| 11 | Is the simulation stopped, and how do I resume, restart or quit? | Pause menu | Covered |
| 12 | How did the raid end, what did I keep, lose or earn, and where do I go next? | Raid result | Covered, but the post-raid destination returns to the menu instead of the hub |

## Screen-by-screen inventory

### 1. Main menu

- **Source:** `scenes/main_menu.tscn`, `scenes/main_menu.gd`
- **Question answered:** “What can I do next, and how do I leave?”
- **Shows:** title, **Jogar**, **Central de operações**, **Configurações**, **Sair**.
- **Authority:** scene routing only; no profile or economy mutation.
- **Exits:** Play, hub, settings, quit.
- **Gap:** on `b93618e`, **Jogar** bypasses the hub and enters the arena directly.
  The FLOW task changes Play to enter the hub so a loadout decision always comes
  first. Until that lands, the menu advertises two different entries into play.

### 2. Settings

- **Source:** `SettingsPanel` inside `scenes/main_menu.tscn`
- **Question answered:** “How do I change sensitivity, volume, resolution, fullscreen and match mode?”
- **Shows:** live sliders and selectors; values apply immediately for preview.
- **Authority:** `SettingsStore`; writes `user://settings.cfg` only on **Voltar**.
- **Exits:** back to the main menu.
- **Gap:** none blocking. Match mode is stored here but has no player-facing
  explanation of its effect.

### 3. Operations hub

- **Source:** `scenes/operations_hub.tscn` + persistent
  `scenes/operations_hub_controller.tscn` (`OperationsHubRoute` autoload)
- **Question answered:** “What is my active kit, what is in my stash, and can I
  deploy this raid?”
- **Shows:** profile summary, last raid report, loadout option picker, loadout
  validity, Deploy.
- **Authority:** presentation-only shell. `MetaService` owns profile, stash,
  loadout validation, starter kit, deployment and persistence.
- **Exits:** Deploy → arena; return/refresh stays in the hub.
- **Gaps:** no ARMAZENAMENTO section and no unarmed-profile rescue on `b93618e`
  (FLOW task); no trader, quest, skill or insurance surfaces yet; the
  **Voltar à central** button reloads the hub and is therefore not a useful exit
  until a real menu exit is defined. The faction is inert text even though
  `MetaService.switch_faction()` already swaps the active/inactive role kits, so
  the player cannot yet answer “which kit am I actually deploying?”.

### 4. In-raid HUD

- **Source:** `scenes/arena_manager.gd` (`ArenaHUD`)
- **Question answered:** “What is happening right now, and what should I do next?”
- **Shows:** top status, center event messages, directional damage, killfeed,
  raid timer/outcome/EXP, extraction hint, death message.
- **Authority:** reads live raid/player state; it does not own progression.
- **Exits:** none — this is the always-on context layer for the arena.
- **Gaps:** several simultaneous messages compete for the same center/bottom
  real estate; extraction, quest and trader prompts can overlap.

### 5. Inventory

- **Source:** `addons/cabra.lat_shooters/src/ui/inventory/main.gd`
  (`InventoryUI`)
- **Question answered:** “What am I carrying, what fits where, and what can I
  move, use or equip?”
- **Shows:** equipment slots plus a stack of opened containers (rig inside
  backpack inside the raid carrier), drag/drop targets, use/modify actions, and
  the world-drop zone.
- **Authority:** `InventorySystem`, `Equipment` and `InventoryContainer`; the UI
  transfers ownership only through the core system.
- **Exits:** close button / inventory toggle.
- **Gaps:** per-container mass and free cells are already first-class in each
  foldable panel title, but equipment has no mass line and nothing aggregates
  equipment + all open containers, so the player cannot answer “how heavy am I
  overall?” without adding the numbers by hand. The screen also answers only the
  raid-carrier question, not the persistent stash question.

### 6. Trader panel

- **Source:** `_build_market()` in `scenes/arena_manager.gd`
- **Question answered:** “What can I buy or sell here, at what price, and did my
  transaction succeed?”
- **Shows:** trader, loyalty level, reputation, credits, buy/sell rows, result
  message, close.
- **Authority:** `MetaService` market API; the panel is presentation only.
- **Exits:** close and return to the raid.
- **Gaps:** the same economy is unavailable between raids; there is no flea,
  barter explanation, or pending-claim visibility outside this panel.

### 7. Gunsmith

- **Source:** `scenes/gunsmith_ui.gd` (`GunsmithUI`)
- **Question answered:** “How does this weapon perform now, and what will this
  attachment change?”
- **Shows:** live weapon preview, derived statistics, attachment points,
  compatible options, mount/dismount actions.
- **Authority:** weapon/attachment resources and the inventory owner; UI previews
  must not mutate persistence by themselves.
- **Entry contract:** opened from the inventory's **Modificar** action; the
  inventory closes first, then the gunsmith owns the screen.
- **Exits:** cancel/close back to the arena.
- **Gaps:** available only while carrying a weapon; no owned-items source for
  planning a future kit.

### 8. Pause menu

- **Source:** `_build_pause()` in `scenes/arena_manager.gd`
- **Question answered:** “Is the raid stopped, and how do I resume, restart or
  leave?”
- **Shows:** PAUSADO, Continuar, Reiniciar, Menu.
- **Authority:** arena/pause state and scene routing.
- **Exits:** resume, restart, main menu.
- **Gaps:** **Menu** is an immediate destructive-feeling exit from a live raid;
  it needs an explicit abandon/confirm decision, and a settings entry.

### 9. Raid result

- **Source:** `_build_result_panel()` in `scenes/arena_manager.gd`
- **Question answered:** “How did the raid end, what did I keep, lose or earn,
  and where do I go next?”
- **Shows:** outcome, report summary, quest line, EXP, **Voltar ao menu**.
- **Authority:** `MetaService` resolves and persists the raid before this screen
  is shown; the panel only reports.
- **Exits:** main menu.
- **Gaps:** returns to the menu instead of the hub, so the player must choose
  play again rather than landing on the post-raid stash/loadout decision; the
  detailed lost/insured/banked breakdown is compressed into the summary line.

## Overlays that are not separate screens

| Element | Parent | Question answered |
|---|---|---|
| Center event text | In-raid HUD | “What just happened to me?” |
| Extraction line | In-raid HUD | “What is my exit condition now?” |
| Damage direction marker | In-raid HUD | “Where did that hit come from?” |
| Killfeed | In-raid HUD | “Who did what, and is it relevant to me?” |
| Death message | In-raid HUD | “Did the raid end for me?” |
| Toast / market message | Trader panel | “Did my last action succeed?” |

## Flow audit (base `b93618e`)

```text
main menu ──Jogar──────────────► arena ──result──► main menu
     │                                            (stash/loadout not shown)
     └──Central de operações──► hub ──Deploy──► arena

         raid overlays: trader · pause
                           inventory ──Modificar (inventory closes)──► gunsmith
```

Target after FLOW integration:

```text
main menu ──Jogar──► hub ──Deploy──► arena ──result──► hub
                       ▲                                │
                       └────────────────────────────────┘
```

## Next coverage decisions (not implementation)

1. Give the hub a real menu exit; do not ship a button that reloads the hub.
2. Decide whether the trader/economy is raid-only or also available between raids.
3. Add the faction/role-kit switch plus quest, skill and insurance questions to
   the hub, or explicitly defer each with a one-line reason. The faction switch
   comes first because it changes the deployable kit while the hub already shows
   the faction as if it were a choice.
4. Add abandon confirmation to Pause → Menu.
5. When out-of-raid rearrangement becomes necessary, reuse the same core and
   vocabulary as the raid carrier: `InventoryContainerUI` slots, drag/drop,
   dimension rotation, stacking and tooltips. The FLOW task intentionally ships
   a readable stash summary; a bespoke second grid would teach two drag models
   for one mental model.
