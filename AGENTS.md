# AGENTS.md — fps-basegame conventions

Godot 4.7 FPS testbed. Read this before touching anything.

## Repo layout (separate git repos — do NOT cross-commit)

- `.` — game repo (scenes, resources, tools, docs). Subagents work here by default.
- `addons/cabra.lat_shooters` — own git repo (core gunplay: ballistics, weapon,
  player, IK). Edits allowed, but never commit there unless asked.
- `../tarkov-wiki` — sibling data repo (CC-BY-SA wiki mirror, reference only).

## Golden commands (run from repo root)

```bash
# THE verification gate (single entry point: parse + all harnesses + quality gate).
# Aggregate exit code; per-gate PASS/FAIL/SKIP + check counts.
bash tools/verify-all.sh --quick        # parse + harnesses (~90s)
bash tools/verify-all.sh                # + quality gate (~150s)
bash tools/verify-all.sh --with-export  # + Linux/Windows export

# ⚠️ `godot --headless --path . --import` is NOT a parse gate. It exits 0 and prints
# nothing for a broken script (proven by sabotage). Use it to refresh the import cache,
# never as proof of parse. The parse gate is `check_scripts.gd`, run by verify-all.

# ⚠️ Run Godot DIRECTLY only through the lock wrapper. The `.godot/` cache is shared;
# several lanes running `godot --import` at once HANG the import and block the gate for
# everyone. `tools/godot-lock.sh` takes the SAME per-repo lock as verify-all, so a direct
# import waits instead of racing:
tools/godot-lock.sh --headless --path . --import            # not `godot ... --import`
tools/godot-lock.sh --clean-tmp --headless --path . --import # also clears 0-byte leftovers

# ⚠️ Do NOT wrap the wrapper in a short `timeout`: it WAITS on the lock (`flock -w 900`),
# so a short timeout returns exit 124 — that LOOKS like a broken harness but is lock-wait.

# Play a scene with GPU rendering, INVISIBLE (awesomewm-safe):
# app window lives on dummy :99, GL ships to NVIDIA via VirtualGL.
DISPLAY=:99 nix shell nixpkgs#virtualgl -c vglrun -d :0 \
  godot --path . --resolution 1280x720 --script <SceneTree-runner>

# Animated GIF from frames (imagemagick_light lacks PNG; use ffmpeg)
nix shell nixpkgs#ffmpeg -c ffmpeg -y -framerate 8 \
  -pattern_type glob -i '/tmp/shooter/frm_*.png' /tmp/shooter/out.gif
```

Xvfb on `:99` is expected to be already running. If not: `Xvfb :99 &`.

## Rules

1. **Never commit/push** unless explicitly asked. Leave trees dirty, report status.
   - **Always commit with an explicit pathspec:** `git commit -m "..." -- <your files>`.
     The worktree is SHARED, so the INDEX carries whatever other lanes staged; a
     pathless `git commit` sweeps their work (proven: board commit `a403a54` reverted
     the NPC body swap that another lane had staged for an A/B test).
   - **Better: commit from a THROWAWAY index** (immune to others' staging *by construction*):
     ```bash
     base=$(git rev-parse HEAD)                       # record HEAD
     export GIT_INDEX_FILE=/tmp/shooter/x.index
     rm -f "$GIT_INDEX_FILE"; git read-tree "$base"   # clean index, nothing of anyone else
     git add <your files>
     [ "$(git rev-parse HEAD)" = "$base" ] || { git read-tree HEAD; git add <your files>; }  # HEAD moved? redo
     git commit -m "..."
     unset GIT_INDEX_FILE; git reset -q -- <your files>   # (see trap)
     git show --stat --format="" HEAD                 # MUST list ONLY your files
     ```
     A throwaway index is immune to others' STAGING, but **not** to HEAD MOVING between
     `read-tree` and `commit` — then your commit's tree lacks the in-between commits and
     REVERTS them. So record `base`, redo the `read-tree` if HEAD moved, and confirm with
     `git show --stat HEAD` that only your files entered (a "board" commit listing 3 NPC
     files is how `a403a54` would have been caught in 2 seconds).
     Trap: after a throwaway-index commit the REAL index is stale for those paths
     (`git status` shows `D ` staged) — a lane committing without a pathspec would then
     DELETE your files. Always close with **`git reset -q -- <your files>`** (path-scoped,
     never a bare `git reset`, which would drop other lanes' staging).
   - **Never `git checkout <rev> -- <path>`, `git add -A` or `git stash` for testing** —
     the first two write the INDEX. For A/B use `git worktree add` or copy the file to /tmp.
2. **Scratch goes to `/tmp/shooter/`** (screenshots, strips, GIFs, logs).
   Nothing capture-related enters the repo. Temp runner scripts live under
   `addons/cabra.lat_shooters/test/*_tmp.gd` and MUST be deleted after the run —
   **unless the probe caught a real bug or proves an invariant**, in which case the
   assertion is **promoted** into `test/validate_invariants.gd` (permanent) instead of
   deleted. Probes are disposable; invariants are not. A probe that found something
   leaves the assertion behind, with a comment saying which bug it caught.
3. **EditorScript tests can't run headless.** Verify math with a temporary
   `extends SceneTree` script (`_initialize()` + `quit()`), then delete it.
   The editor suite (`test/main.gd`) only runs inside the Godot editor.
4. **Physics queries only in `_physics_process`** (`intersect_ray` etc.).
   Hit-detect from `cartridge_fired` by deferring into a `_pending_shots` queue.
5. **Held items are never physics-simulated.** Guns/attachments in hands are
   frozen rigid bodies posed procedurally (`ViewmodelRig`); only world loot
   uses `Grabbable3D` springs. Obliquity via LOS thickness (`t/cos`).
6. **Ballistics references:** Recht-Ipson residual `Er = max(0, Eh - Ebl)`,
   Poncelet tissue `P = K·ln(1+E/E1)`. Cert tables in `certification.gd`
   decide armor stops; physics is the fall-through, never the reverse.
7. **Coordinate via AMQ.** Queue root is `.agent-mail/` (gitignored). Handles:
   `coordinator`, `ballistics`, `player-rig`, `range`, `spotter`, `npc-body`,
   `meta`, `testkit`, `qa`. Prefix shell with `export PATH="$HOME/.local/bin:$PATH"`.
   Skill reference: `.opencode/skills/amq-cli/SKILL.md`.

   **Message protocol (all agents, no exceptions):**
   - **Drain first:** `amq drain --me <handle> --include-body`, then claim your task
     in `.opencode/bus/STATUS.md` (`CLAIMED by <handle> <UTC time>`).
   - **Always reply to the sender.** Every order or question you receive gets an
     answer to *whoever sent it*, on the same thread:
     `amq reply --me <handle> --id <msg_id> --body @/tmp/shooter/reply.txt`
     (it sets to/thread/refs automatically). Do NOT default to reporting to
     `coordinator` — report to the sender. Only CC `coordinator` when shared state
     (the board) changes.
   - **Every message that expects action must say so** (`reply needed`, `ack`,
     or an explicit question) — and you answer the same way when you receive one.
   - **Report shape:** (1) what was asked, (2) what was done + files touched,
     (3) evidence (numbers, paths, commands), (4) blockers/dependencies,
     (5) board status. Never invent results; report gates honestly.
   - **Blocked or need a peer:** message that peer directly. Ask `spotter` for
     numeric/visual verification.
   - One agent per file-set; claim before editing. Never touch `.agent-mail/`
     files directly — `amq` CLI only. Long bodies use `--body @file` (backticks
     are eaten by the shell and corrupt the message).
   - **Never verify a diff with the repo's external diff driver on.** This repo sets
     one (`sem`, the boxed output): bare `git diff` emits **no** `+`/`-` lines, so a
     check like "the diff only touches icons" can pass *vacuously* instead of failing.
     Always disable it: `git -c diff.external= diff --no-ext-diff --unified=0
     <from> <to> -- <paths>`. (Reproduced by `meta`+`testkit`: a "0 changed lines"
     check where the real diff had 30 — it had falsified an "icon-only" claim.)

## Identity rule (this is a genre framework, NOT a clone)

Tarkov is the **mechanical reference** (see `docs/genre-feature-survey.md`), never our
content. This project ships **no proper nouns or content from any commercial game**:

- trader, map, item, quest, faction and boss names in `resources/`, `src/`, `scenes/` and
  the UI must be neutral placeholders invented here — no `Prapor`, no `Customs`, no
  `Escape from Tarkov` strings.
- Attributing a **mechanic** is fine and encouraged (`Recht-Ipson`, `Poncelet`,
  "genre-typical 7-minute run-through rule") — borrowing a **name** is not.
- No ripped assets, icons or logos; placeholders only.
- `docs/` may cite sources and use their names (research material). Shipped code may not.

**Content is data, mechanics may be enums.** A game framework cannot hardcode things the game
decides. Factions, maps, items, quests, traders and modes are **data** (`.tres` + a registry),
so a game can ship 3, 5 or 10 of them. Finite, universal simulation categories may stay enums
(`Ammo.Type`, `BodyPart.Type`, `BallisticMaterial.Type`, `Certification.Standard`). Hardcoding a
faction list is the same mistake as hardcoding the weapon list.

## AMQ ↔ herdr bridge (delivery)

AMQ queues reliably but has no doorbell; herdr knows who is idle/blocked but has no
message semantics. `tools/amq-herdr-bridge.mjs` joins them — same handle names on
both sides, so no mapping is needed. It watches each handle's inbox and, when there
is unread mail: **idle/done → prompts the agent via herdr to drain and reply to the
sender**; working → leaves it alone (drains on its next turn); blocked → raises one
alert to `coordinator` (a blocked agent needs a human answer, not more mail).

```bash
node tools/amq-herdr-bridge.mjs --once --dry-run   # side-effect free preview
node tools/amq-herdr-bridge.mjs --once             # one delivery pass
node tools/amq-herdr-bridge.mjs                    # daemon (3s interval)
```

State (delivered message ids) lives in `/tmp/shooter/amq-herdr-bridge-state.json`,
so a message is never doorbelled twice. `--dry-run` never mutates that state.

## Key scenes / entry points

- `scenes/debug_range.tscn` — playable range (manager: `debug_range.gd`).
- `scenes/debug_movement.tscn` — bare player + floor.
- `scenes/test_player.tscn` — heavy full-terrain scene (slow, avoid for loops).
- `scenes/range_target.gd` — knock-down target (`range_hit(impact, ammo)`).
