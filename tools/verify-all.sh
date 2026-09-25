#!/usr/bin/env bash
# tools/verify-all.sh — single verification entry point for fps-basegame.
#
# Runs every headless gate in sequence and returns ONE aggregate exit code, so a
# human and CI run the exact same thing. Test toolchain only; it never edits
# game code or other owners' harnesses — it just calls them.
#
# Gates, in order:
#   1. import/parse        godot --headless --path . --import + check_scripts.gd (hard)
#   2. uid_tracking        every tracked script has its tracked .uid   (hard)
#   3. assets              test/validate_assets.gd              (hard)
#   4. ballistics          test/validate_ballistics.gd          (hard)
#   5. weapon_mechanics    test/validate_weapon_mechanics.gd    (hard)
#   6. inventory_ux        test/validate_inventory_ux.gd        (hard)
#   7. factions            scenes/validate_factions.gd          (hard)
#   8. gunsmith_preview    scenes/validate_gunsmith_preview.gd   (hard)
#   9. arena_spawn         scenes/validate_arena_spawn.gd        (hard; regression
#                                                                guard, not a proof
#                                                                of the race mechanism)
#  10. meta_persistence    src/meta/validate_meta_persistence.gd (hard)
#  11. meta_progression    src/meta/validate_meta_progression.gd (hard)
#  12. meta_market         src/meta/validate_meta_market.gd     (hard)
#  13. meta_flea           src/meta/validate_meta_flea.gd       (hard)
#  14. invariants          test/validate_invariants.gd          (hard; cross-system
#                                                                regression probes
#                                                                promoted from *_tmp.gd)
#  15. locomotion_orientation test/validate_locomotion_orientation.gd (hard;
#                                                                procedural facing
#                                                                and nested-transform
#                                                                regression)
#  16. qa_audit            tools/qa/audit.mjs --check           (graded: BLOCKER hard,
#                                                                     MAJOR regression = WARN)
#  17. export              optional, --with-export only (SKIP if no templates)
#
# Why run ALL gates instead of stopping at the first hard failure? Each harness is
# independent and cheap; a full matrix shows every regression in one pass instead
# of revealing them one CI cycle at a time. The aggregate exit code is still
# non-zero as soon as any hard gate fails.
#
# Usage:
#   tools/verify-all.sh                 # full local gate
#   tools/verify-all.sh --quick         # parse + assets only
#   tools/verify-all.sh --with-export   # also build Linux/Windows binaries
#   tools/verify-all.sh --no-qa         # skip the qa quality gate
#   tools/verify-all.sh --qa-fast       # qa without re-probing manual findings
#   tools/verify-all.sh --qa-soft       # qa BLOCKER becomes a warning
#
# Exit codes: 0 = all hard gates pass | 1 = at least one hard gate failed
#             | 64 = usage error.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-godot}"
# Per-run log dir by DEFAULT: two agents running verify-all at the same time used
# to write the same /tmp/shooter/verify/*.log and clobber each other, which made a
# gate read another run's half-written log and report a spurious FAIL (observed
# 2026-09-21: assets/weapon_mechanics/meta_progression FAILed rc=0 with "RESULT:
# PASS" actually present in the final file). VERIFY_LOG_DIR still forces an exact
# path when a caller wants one.
LOG_DIR="${VERIFY_LOG_DIR:-/tmp/shooter/verify.$$}"

QUICK=0 WITH_EXPORT=0 NO_QA=0 QA_FAST=0 QA_SOFT=0

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --with-export) WITH_EXPORT=1 ;;
    --no-qa) NO_QA=1 ;;
    --qa-fast) QA_FAST=1 ;;
    --qa-soft) QA_SOFT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "verify-all: unknown flag '$arg'" >&2; usage >&2; exit 64 ;;
  esac
done

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "verify-all: godot not found (set GODOT_BIN)" >&2
  exit 64
fi
if ! command -v flock >/dev/null 2>&1; then
  echo "verify-all: flock is required to protect the shared .godot cache" >&2
  exit 69
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "verify-all: timeout is required to bound Godot processes" >&2
  exit 69
fi

# ─── LOCKING: acquire the per-cache lock before any Godot/cache work ──────
# Worktrees have separate source directories, but this checkout's .godot may be a
# symlink to the main checkout's cache. Lock by the resolved cache path, not by
# the worktree root, so every process touching that cache gets the same lock.
mkdir -p /tmp/shooter
GODOT_CACHE="$(realpath .godot 2>/dev/null || printf '%s' "$ROOT/.godot")"
LOCK_FILE="/tmp/shooter/verify-all.${GODOT_CACHE//\//_}.lock"
exec 9>"$LOCK_FILE"
flock -w 900 9 || { echo "verify-all: FATAL: lock not acquired in 900s" >&2; exit 1; }

mkdir -p "$LOG_DIR"

# ─── PREFLIGHT: the addon harnesses live in a SEPARATE repo ──────────
# The addon contains check_scripts.gd and the shared validation harnesses. A
# missing checkout is an environment/setup failure, not a code regression.
if [ ! -f "addons/cabra.lat_shooters/test/check_scripts.gd" ]; then
  echo "verify-all: FATAL: addons/cabra.lat_shooters is not checked out." >&2
  echo "  Initialize the declared submodules or provide the addon checkout." >&2
  if [ -f .gitmodules ]; then
    echo "  Addons declared in .gitmodules  [status] path  url:" >&2
    while read -r _key path; do
      name="$(printf '%s' "$_key" | sed 's/^submodule\.//;s/\.path$//')"
      url="$(git config -f .gitmodules --get "submodule.$name.url" 2>/dev/null)"
      if [ -f "$path/.git" ] || [ -d "$path/.git" ]; then st="present"; else st="MISSING"; fi
      printf '    [%-7s] %s  %s\n' "$st" "$path" "${url:-?}" >&2
    done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)
    echo "  To obtain declared submodules: git submodule update --init --recursive" >&2
  fi
  exit 1
fi

# ─── result bookkeeping ─────────────────────────────
declare -a R_NAME R_STATUS R_DETAIL
HARD_FAILS=0
WARNS=0

record() { # name status detail
  R_NAME+=("$1"); R_STATUS+=("$2"); R_DETAIL+=("$3")
}

count_checks() { # logfile -> prints a check count or "?"
  local f="$1" n=""
  n="$(grep -oE 'checks passed[[:space:]]+[0-9]+' "$f" | grep -oE '[0-9]+' | head -1)"
  [ -z "$n" ] && n="$(grep -oE 'checks:[[:space:]]*[0-9]+ pass' "$f" | grep -oE '[0-9]+' | head -1)"
  [ -z "$n" ] && n="$(grep -oE '^[[:space:]]*passed[[:space:]]+[0-9]+' "$f" | grep -oE '[0-9]+' | head -1)"
  echo "${n:-?}"
}

# ─── GATE 1: import / parse ─────────────────────────
# Two independent checks, because neither alone is a real gate:
#   (a) `godot --import` exits 0 even with parse errors, so we also scan its
#       output (catches broken referenced scripts / resource import errors).
#   (b) check_scripts.gd compiles EVERY project .gd (catches a stray broken file
#       that --import never touches). This is the bug the old CI step had: a
#       "parse gate" that could never fail.
CHECK_SCRIPTS_SCRIPT="res://addons/cabra.lat_shooters/test/check_scripts.gd"
gate_import() {
  local ilog="$LOG_DIR/import.log" clog="$LOG_DIR/check_scripts.log" rc errs crc cfail n attempt=1
  local loop_stats loop_count loop_asset
  # The lock is already held here. Remove only zero-byte import residue; never
  # remove source .import files or generate repository files as a side effect.
  find .godot/imported -maxdepth 1 -type f -size 0 \( -name '*.ctex-*' -o -name '*.tmp' \) -delete 2>/dev/null || true
  while :; do
    timeout --kill-after=10s 120s "$GODOT_BIN" --headless --path . --import >"$ilog" 2>&1; rc=$?

    # Godot prefixes progress output with ANSI colour codes and appends a reset
    # sequence to asset names. Strip those codes before grouping by asset. A high
    # count for ONE asset is a deterministic stale-metadata loop, not ordinary
    # contention. Scan after every attempt, including successful exits.
    loop_stats="$(sed -n 's/.*reimport | //p' "$ilog" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C sort | uniq -c | LC_ALL=C sort -nr | head -1 || true)"
    loop_count="$(printf '%s\n' "$loop_stats" | awk 'NF {print $1; exit}')"
    loop_asset="$(printf '%s\n' "$loop_stats" | awk 'NF {$1=""; sub(/^ /, ""); print; exit}')"
    if [ "${loop_count:-0}" -gt 50 ]; then
      record "import/parse" "FAIL" "import reimport loop detected: '$loop_asset' reimported $loop_count times. Fix the source .import metadata, then rerun (see $ilog)"
      HARD_FAILS=$((HARD_FAILS + 1))
      return
    fi

    [ "$rc" -ne 124 ] && break
    if [ "$attempt" -ge 2 ]; then
      record "import/parse" "FAIL" "import TIMED OUT (120s x2) — concurrent import contention or a non-repeating hang (see $ilog)"
      HARD_FAILS=$((HARD_FAILS + 1))
      return
    fi
    echo "verify-all: import timed out; waiting 5s + retry once" >&2
    sleep 5
    find .godot/imported -maxdepth 1 -type f -size 0 \( -name '*.ctex-*' -o -name '*.tmp' \) -delete 2>/dev/null || true
    attempt=$((attempt + 1))
  done
  errs="$(grep -cE 'SCRIPT ERROR|Parse Error|Failed to load|Cannot open|Failed to compile' "$ilog")"
  "$GODOT_BIN" --headless --path . --script "$CHECK_SCRIPTS_SCRIPT" >"$clog" 2>&1
  crc=$?
  cfail="$(grep -oE 'failures: [0-9]+' "$clog" | grep -oE '[0-9]+' | head -1)"
  n="$(grep -oE 'scripts compiled: [0-9]+' "$clog" | grep -oE '[0-9]+' | head -1)"
  if [ "$rc" -ne 0 ] || [ "$errs" -gt 0 ] || [ "$crc" -ne 0 ]; then
    record "import/parse" "FAIL" "import rc=$rc errs=$errs; scripts rc=$crc failures=${cfail:-?} (see $ilog, $clog)"
    HARD_FAILS=$((HARD_FAILS + 1))
  else
    record "import/parse" "PASS" "0 parse errors, ${n:-?} scripts compiled"
  fi
}

# ─── GATE 2: tracked-script / .uid parity ───
# WHY (verifier finding, 2026-09-21): Godot 4.4+ references scripts by UID, but a
# tracked .gd/.gdshader/.gdshaderinc WITHOUT a tracked .uid regenerates a
# DIFFERENT uid on a clean clone, so every .tres/.tscn referencing it by
# `uid://...` silently falls back to the text path (and breaks if the file moves).
# Proven: `git archive HEAD` of the addon + `--import` regenerated weapon.gd.uid
# with a new UID and printed "WARNING: ext_resource, invalid UID ..."; copying the
# real .uid removed the warning. This is a GIT invariant, not runtime, so it lives
# here (not in validate_invariants.gd). Scope: our two repos only — vendored
# submodules are not ours to gate, and a missing git checkout (e.g. a private
# addon the runner could not fetch) is skipped rather than faked green.
UID_REPOS=("." "addons/cabra.lat_shooters")
gate_uid_tracking() {
  local repo total=0 checked=0 skipped="" details="" list="$LOG_DIR/uid_missing.log"
  local headf="$LOG_DIR/.uid_head" scr="$LOG_DIR/.uid_scripts" trk="$LOG_DIR/.uid_tracked"
  local scr_uid="$LOG_DIR/.uid_script_uids" missing="$LOG_DIR/.uid_missing" orphan="$LOG_DIR/.uid_orphan"
  : >"$list"
  for repo in "${UID_REPOS[@]}"; do
    # Must be its OWN repo TOPLEVEL, not a subdirectory of a parent repo. If the
    # addon dir exists but is not a repo (uninitialised submodule / `.git`
    # removed), `git -C <dir> rev-parse` WALKS UP to the game repo and returns
    # it, so the addon would count as "checked" while `ls-files` sees none of its
    # scripts -> false PASS. Compare the repo toplevel with the dir itself.
    # (verifier, sandbox B1.)
    local repo_abs top
    repo_abs="$(cd "$repo" 2>/dev/null && pwd -P)" || repo_abs=""
    top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || top=""
    top="$(cd "$top" 2>/dev/null && pwd -P)" || top=""
    if [ -z "$repo_abs" ] || [ -z "$top" ] || [ "$top" != "$repo_abs" ]; then
      skipped+="$repo "
      continue
    fi
    # HEAD, NOT the index. The invariant is "a CLEAN CLONE works", and a clone
    # only has committed files. `git ls-files` (index) produced a false green
    # while 36 .uid were staged-but-uncommitted: gate PASS, clean clone FAIL with
    # 6 missing uid:// refs (verifier e2e). Check BOTH directions on HEAD:
    #   forward: every committed script has its committed .uid
    #   reverse: every committed .uid has its committed script (an orphan .uid
    #            makes --import try to open a missing file, cf. dim_tmp.gd.uid)
    if ! git -C "$repo" ls-tree -r --name-only HEAD >"$headf" 2>/dev/null; then
      skipped+="$repo "
      continue
    fi
    checked=$((checked + 1))
    # Exclude HIDDEN paths (any component starting with '.'): Godot does not scan
    # hidden dirs, so it NEVER generates a .uid for e.g. `.opencode/**/*.gd` — the
    # invariant would be unsatisfiable there (verifier: 152 false positives at HEAD
    # 31a5fcc). Content roots (src, scenes, the addon, resources, tools) are kept.
    grep -E '\.(gd|gdshader|gdshaderinc)$' "$headf" | grep -vE '(^|/)\.' | LC_ALL=C sort >"$scr"
    grep -E '\.uid$' "$headf" | grep -vE '(^|/)\.' | LC_ALL=C sort >"$trk"
    sed 's/$/.uid/' "$scr" | LC_ALL=C sort >"$scr_uid"
    comm -23 "$scr_uid" "$trk" >"$missing"
    comm -13 "$scr_uid" "$trk" >"$orphan"
    n="$(wc -l <"$missing")"
    n=$((n + $(wc -l <"$orphan")))
    if [ "$n" -gt 0 ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf '%s/%s (script without .uid)\n' "$repo" "${f%.uid}" >>"$list"
      done <"$missing"
      while IFS= read -r u; do
        [ -z "$u" ] && continue
        printf '%s/%s (uid without script)\n' "$repo" "$u" >>"$list"
      done <"$orphan"
      total=$((total + n))
      details+="$repo:$n "
    fi
  done
  local skip_note=""
  [ -n "$skipped" ] && skip_note="; SKIPPED (no git checkout): $skipped"
  if [ "$checked" -eq 0 ]; then
    # Nothing was actually checked, so it MUST NOT report PASS: a clean clone
    # without the (private) addon would otherwise look green. Mirrors the export
    # gate's honest SKIP. Found by `verifier` (sandbox: addon .git removed ->
    # PASS with an empty missing list).
    record "uid_tracking" "SKIP" "no git checkout to check (skipped: ${skipped:-none})"
  elif [ "$total" -gt 0 ]; then
    record "uid_tracking" "FAIL" "$total tracked script(s) without a tracked .uid ($details) — list in $list$skip_note"
    HARD_FAILS=$((HARD_FAILS + 1))
  else
    record "uid_tracking" "PASS" "every tracked script in $checked repo(s) has a tracked .uid$skip_note"
  fi
}

# ─── HARNESS GATE ───────────────────────────────────
# NOTE: the verdict is the EXIT CODE + the "RESULT: PASS" line, PLUS a scan for
# REAL log errors: `SCRIPT ERROR` and `referenced non-existent resource` /
# `Resource file not found` FAIL (a harness must not PASS over an error). Benign
# text does NOT gate: `invalid UID ... using text path instead` (the resource
# still loads) is only reported. Autoload-startup noise is also a `SCRIPT ERROR`
# and IS gated — that is the harness-hazard in test/check_scripts.gd: a runner
# that names an autoload-dependent class is a harness bug to fix.
gate_harness() { # name script
  local name="$1" script="$2" log="$LOG_DIR/$1.log" rc n attempt=1 lerr lse luid
  while :; do
    # BOUND the harness: without a timeout a hung harness (stale .godot, a scene
    # that never boots) hangs the WHOLE gate forever — observed: the arena_spawn
    # harness ran 891 s and my full verify-all never reached the summary.
    if command -v timeout >/dev/null 2>&1; then
      timeout --kill-after=10s 600s "$GODOT_BIN" --headless --path . --script "$script" >"$log" 2>&1; rc=$?
    else
      "$GODOT_BIN" --headless --path . --script "$script" >"$log" 2>&1; rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      record "$name" "FAIL" "harness TIMED OUT (600s) — hung; suspect stale .godot or a scene that never boots (see $log)"
      HARD_FAILS=$((HARD_FAILS + 1))
      return
    fi
    n="$(count_checks "$log")"
    # A harness must not PASS over a REAL log error (gate honesty):
    #   - `SCRIPT ERROR` (incl. a script chain that names an autoload -> the
    #     harness-hazard in check_scripts.gd; that is a harness bug to fix);
    #   - `referenced non-existent resource` / `Resource file not found`.
    # Benign text does NOT gate: `invalid UID ... using text path instead` (the
    # resource still loads) is only reported in the PASS detail.
    lerr="$(grep -cE 'referenced non-existent resource|Resource file not found' "$log")"
    lse="$(grep -cE 'SCRIPT ERROR' "$log")"
    luid="$(grep -cE 'invalid UID' "$log")"
    if [ "$rc" -eq 0 ] && grep -qE 'RESULT: PASS' "$log" && [ "$lerr" -eq 0 ] && [ "$lse" -eq 0 ]; then
      if [ "$attempt" -eq 1 ]; then
        record "$name" "PASS" "$n checks$([ "$luid" -gt 0 ] && printf ' (%d invalid-UID warning(s))' "$luid")"
      else
        record "$name" "PASS" "$n checks (retried after re-import: transient .godot cache race)"
      fi
      return
    fi
    if [ "$attempt" -ge 3 ]; then
      if [ "$lerr" -gt 0 ] || [ "$lse" -gt 0 ]; then
        record "$name" "FAIL" "$n checks but $((lerr + lse)) log error(s) ($lerr load, $lse script) — a harness must not PASS over an error (see $log)"
      else
        record "$name" "FAIL" "rc=$rc, $n checks after $((attempt)) attempts (see $log)"
      fi
      HARD_FAILS=$((HARD_FAILS + 1))
      return
    fi
    # First failure: refresh the import cache and retry. TWO retries are allowed
    # because a FLAKY gate is worse than none (a false FAIL trains people to ignore
    # red): the arena_spawn canary served stale .godot bytecode ~1/7 runs, and
    # (1/7)^3 makes a false FAIL negligible. A real regression still fails every time.
    echo "verify-all: $name failed (rc=$rc, load=$lerr script=$lse) — bounded re-import + retry (attempt $((attempt + 1))/3)" >&2
    local rlog="$LOG_DIR/reimport.$name.log" rrc rloop_stats rloop_count rloop_asset
    if command -v timeout >/dev/null 2>&1; then
      timeout --kill-after=10s 120s "$GODOT_BIN" --headless --path . --import >"$rlog" 2>&1
      rrc=$?
    else
      "$GODOT_BIN" --headless --path . --import >"$rlog" 2>&1
      rrc=$?
    fi
    rloop_stats="$(sed -n 's/.*reimport | //p' "$rlog" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C sort | uniq -c | LC_ALL=C sort -nr | head -1 || true)"
    rloop_count="$(printf '%s\n' "$rloop_stats" | awk 'NF {print $1; exit}')"
    rloop_asset="$(printf '%s\n' "$rloop_stats" | awk 'NF {$1=""; sub(/^ /, ""); print; exit}')"
    if [ "$rrc" -eq 124 ] || [ "${rloop_count:-0}" -gt 50 ] || grep -qE 'Unrecognized UID|Can.t find file .* during file reimport' "$rlog"; then
      record "$name" "FAIL" "re-import after harness failure hit a UID/import loop or timeout (rc=$rrc, repeats=${rloop_count:-0}, asset=${rloop_asset:-unknown}; see $rlog)"
      HARD_FAILS=$((HARD_FAILS + 1))
      return
    fi
    attempt=$((attempt + 1))
  done
}

# ─── GATE 8: qa quality audit ───────────────────────
gate_qa() {
  local log="$LOG_DIR/qa_audit.log" rc counts
  local args=(--check --no-import)
  [ "$QA_FAST" -eq 1 ] && args+=(--no-verify)
  if ! command -v node >/dev/null 2>&1; then
    record "qa_audit" "SKIP" "node not found"
    return
  fi
  # BOUND it: under heavy .godot/ contention the audit has been seen to run past
  # 300s (coordinator measured it); without a timeout it hangs the whole gate.
  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=10s 900s node tools/qa/audit.mjs "${args[@]}" >"$log" 2>&1; rc=$?
  else
    node tools/qa/audit.mjs "${args[@]}" >"$log" 2>&1; rc=$?
  fi
  if [ "$rc" -eq 124 ]; then
    record "qa_audit" "WARN" "TIMED OUT (900s) — likely .godot/ contention, not a found BLOCKER (see $log)"
    WARNS=$((WARNS + 1))
    return
  fi
  counts="$(grep -oE 'BLOCKER=[0-9]+ MAJOR=[0-9]+ MINOR=[0-9]+ NIT=[0-9]+' "$log" | head -1)"
  [ -z "$counts" ] && counts="rc=$rc"
  case "$rc" in
    0) record "qa_audit" "PASS" "$counts" ;;
    1) if [ "$QA_SOFT" -eq 1 ]; then
         record "qa_audit" "WARN" "BLOCKER present (soft): $counts (see $log)"
         WARNS=$((WARNS + 1))
       else
         record "qa_audit" "FAIL" "BLOCKER present: $counts (see $log)"
         HARD_FAILS=$((HARD_FAILS + 1))
       fi ;;
    2) record "qa_audit" "WARN" "MAJOR regressed vs baseline (informative): $counts (see $log)"
       WARNS=$((WARNS + 1)) ;;
    *) record "qa_audit" "FAIL" "audit error rc=$rc (see $log)"
       HARD_FAILS=$((HARD_FAILS + 1)) ;;
  esac
}

# ─── GATE 9: export (conditional) ───────────────────
gate_export() {
  local ver tpl_dir out rc log="$LOG_DIR/export.log"
  ver="$("$GODOT_BIN" --version 2>/dev/null | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+\.[a-z]+).*/\1/')"
  tpl_dir="${HOME}/.local/share/godot/export_templates/${ver}"
  if [ ! -d "$tpl_dir" ]; then
    record "export" "SKIP" "export templates not installed ($ver)"
    return
  fi
  out="$LOG_DIR/export"; mkdir -p "$out"
  "$GODOT_BIN" --headless --path . --export-release "Linux/X11" "$out/fps-basegame.x86_64" >"$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    record "export" "FAIL" "Linux/X11 export rc=$rc (see $log)"
    HARD_FAILS=$((HARD_FAILS + 1))
    return
  fi
  "$GODOT_BIN" --headless --path . --export-release "Windows Desktop" "$out/fps-basegame.exe" >>"$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    record "export" "FAIL" "Windows export rc=$rc (see $log)"
    HARD_FAILS=$((HARD_FAILS + 1))
  else
    record "export" "PASS" "Linux/X11 + Windows Desktop"
  fi
}

# ─── RUN ────────────────────────────────────────────
echo "=== verify-all ===  root=$ROOT  godot=$("$GODOT_BIN" --version 2>/dev/null)"
echo "logs: $LOG_DIR"
echo ""

gate_import
gate_uid_tracking

if [ "$QUICK" -eq 1 ]; then
  gate_harness "assets" "res://addons/cabra.lat_shooters/test/validate_assets.gd"
  echo "(quick mode: import + assets only)"
else
  gate_harness "assets" "res://addons/cabra.lat_shooters/test/validate_assets.gd"
  gate_harness "ballistics" "res://addons/cabra.lat_shooters/test/validate_ballistics.gd"
  gate_harness "weapon_mechanics" "res://addons/cabra.lat_shooters/test/validate_weapon_mechanics.gd"
  gate_harness "inventory_ux" "res://addons/cabra.lat_shooters/test/validate_inventory_ux.gd"
  gate_harness "meta_persistence" "res://src/meta/validate_meta_persistence.gd"
  gate_harness "meta_progression" "res://src/meta/validate_meta_progression.gd"
  gate_harness "meta_market" "res://src/meta/validate_meta_market.gd"
  gate_harness "meta_flea" "res://src/meta/validate_meta_flea.gd"
  gate_harness "invariants" "res://addons/cabra.lat_shooters/test/validate_invariants.gd"
  gate_harness "locomotion_orientation" "res://addons/cabra.lat_shooters/test/validate_locomotion_orientation.gd"
  gate_harness "factions" "res://scenes/validate_factions.gd"
  gate_harness "gunsmith_preview" "res://scenes/validate_gunsmith_preview.gd"
  # NOTE (arena_spawn): this is the CANARY for stale .godot bytecode (1/7 runs can
  # serve pre-fix logic). A FAIL here after the re-import+retry = suspect STALE
  # BYTECODE, not a logic regression — re-check with tools/godot-lock.sh before
  # believing it.
  gate_harness "arena_spawn" "res://scenes/validate_arena_spawn.gd"
  if [ "$NO_QA" -eq 1 ]; then
    record "qa_audit" "SKIP" "--no-qa"
  else
    gate_qa
  fi
  if [ "$WITH_EXPORT" -eq 1 ]; then
    gate_export
  else
    record "export" "SKIP" "pass --with-export to include"
  fi
fi

# ─── SUMMARY ────────────────────────────────────────
echo ""
echo "=== verify-all summary ==="
i=0
while [ "$i" -lt "${#R_NAME[@]}" ]; do
  printf '  %-4s %-17s %s\n' "${R_STATUS[$i]}" "${R_NAME[$i]}" "${R_DETAIL[$i]}"
  i=$((i + 1))
done

if [ "$HARD_FAILS" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL ($HARD_FAILS hard gate(s) failed, $WARNS warning(s))"
  exit 1
fi
echo ""
if [ "$WARNS" -gt 0 ]; then
  echo "RESULT: PASS ($WARNS non-blocking warning(s))"
else
  echo "RESULT: PASS"
fi
exit 0
