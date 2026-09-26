#!/usr/bin/env bash
# tools/test-godot-lock.sh — the RED ARM for tools/godot-lock.sh's lock honesty.
#
# WHY THIS EXISTS. godot-lock.sh used to swallow a 900s lock timeout, run
# Godot anyway, and then print "lock acquired" unconditionally — so a run that
# held NO lock logged that it had acquired one. The diagnostic that exists to
# report the lock state was reporting it falsely, and a lane reading that line
# would conclude the shared `.godot` cache was protected when it was not.
#
# WHAT IS ASSERTED, and the first one is the whole point:
#   A contended lock REFUSES: non-zero exit (75 EX_TEMPFAIL), Godot is NOT
#     executed, and the string "lock acquired" does NOT appear anywhere.
#   B the --proceed-unlocked override runs, still never claims the lock, and
#     says in so many words that it is running unprotected.
#   C a free lock is taken, SAYS SO, and runs.
#   D a nested call (an ancestor already holding the lock, as verify-all does)
#     takes the skip path, says WHICH path that was, and does not self-deadlock.
#   E a real, uncontended invocation still works end to end.
#
# Each case asserts on BOTH the exit code and the text, because the bug was in
# the text: an exit-code-only check would have passed against the old wrapper
# whenever Godot happened to succeed.
#
# It never touches the shared lock. GODOT_LOCK_FILE points every case at a
# private file, so this can hold a lock and be contended without interfering
# with the gate or another lane. It never kills a holder either: a genuinely
# hung godot process is a different fault from this wrapper bug, and killing
# one would hide the bug instead of fixing it.
#
# HOW TO FALSIFY THIS TEST (it is a red arm, so it must be able to fail).
# Run it against the pre-fix wrapper and watch case [A] catch the lie. Two
# test-only injections into the OLD copy are needed, because otherwise the test
# proves nothing:
#   1. the old wrapper hardcodes its LOCK_FILE, so with GODOT_LOCK_FILE set it
#      would lock a DIFFERENT file, never see contention, and `flock -n` would
#      succeed — the test would pass against the very bug it exists to catch;
#   2. the old wrapper hardcodes `flock -w 900`, so the timeout is unreachable
#      in a test that must finish; shorten it.
# With both applied and a holder that outlives the wait, the old wrapper prints
#   WARNING: lock not acquired in 900s; proceeding (may race the gate)
#   lock acquired after 2s
#   GODOT-RAN ...
# i.e. it ran unlocked and claimed it had the lock, and [A] fails. Note the
# first line also misreports the DURATION it waited — the "900s" is literal
# text, not the real wait. Without those two injections this test reports a
# false PASS, which is worth knowing before trusting it either way.
#
# Run:  tools/test-godot-lock.sh          (exits 0 = all cases passed)
# SAFE TO RUN WHILE THE GATE IS RUNNING: it uses its own lock file and never
# invokes Godot (GODOT_BIN is a stub).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/tools/godot-lock.sh"
# AGENTS: scratch goes to /tmp/shooter. Create it rather than assuming — a
# fresh CI runner has no such directory, and `mktemp -d` on a missing parent
# fails, which would look like a test failure rather than a missing directory.
mkdir -p /tmp/shooter
TMP="$(mktemp -d /tmp/shooter/godot-lock-test.XXXXXX)"
LOCK="$TMP/test.lock"
STUB="$TMP/stub-godot"
PASS=0
FAIL=0
HOLDER_PID=""
READY=""
HOLD_SEQ=0

cleanup() {
  release_lock
  rm -rf "$TMP"
}
trap cleanup EXIT

cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# The pwd is the POINT: it is the print-marker technique, so a test can assert
# WHICH TREE Godot would have opened, not merely that it ran.
echo "GODOT-RAN pwd=$PWD args:$*"
exit 0
STUBEOF
chmod +x "$STUB"

# Holds the lock for ${1:-300}s. The test releases it explicitly, so the
# duration is not "how long the case needs" — it is "long enough that machine
# load cannot expire it mid-case".
#
# That margin is not theoretical. The first version slept 10s and failed 5 runs
# in 20 under load: godot-lock.sh itself takes 5-10s on a loaded box (measured,
# load average 23.6 — it forks stat/tr/awk/sed/readlink/pgrep and walks /proc),
# so a 10s holder could EXPIRE while the wrapper was still running, the lock
# became genuinely free, and the wrapper correctly acquired it. Every case-A
# check then failed for a reason that had nothing to do with the wrapper. A
# holder that expires on its own turns this test into a load meter; make it
# effectively permanent and let release_lock end it.
#
# Exactly ONE process ends up holding it: bash opens fd 9, flocks, then EXECs
# sleep, so there is a single killable PID. (`flock -x file -c "sleep N" &`
# would leave the forked `sleep` holding an inherited descriptor, so killing the
# flock process does NOT release the lock.)
#
# It then PROVES it holds the lock (a ready file) instead of sleeping and
# hoping: a fixed `sleep 0.4` was the original version here, and the wrapper
# could start before the child had run at all. Never kills anyone's process but
# the one this script started.
hold_lock() {
  READY="$TMP/ready.$HOLD_SEQ"
  HOLD_SEQ=$((HOLD_SEQ + 1))
  rm -f "$READY"
  bash -c 'exec 9>"$1"; flock -x 9; : > "$2"; exec sleep "$3"' _ "$LOCK" "$READY" "${1:-300}" &
  HOLDER_PID=$!
  for _ in $(seq 1 100); do
    [ -e "$READY" ] && return 0
    sleep 0.1
  done
  return 1
}

release_lock() {
  [ -n "$HOLDER_PID" ] || return 0
  kill "$HOLDER_PID" 2>/dev/null
  wait "$HOLDER_PID" 2>/dev/null
  HOLDER_PID=""
}

# Runs the wrapper, capturing combined output and the exit code.
run_wrapper() {
  OUT="$(GODOT_BIN="$STUB" GODOT_LOCK_FILE="$LOCK" GODOT_LOCK_WAIT=2 bash "$WRAPPER" "$@" 2>&1)"
  RC=$?
}

check() { # check <description> <condition-result 0/1> [detail]
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$1"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s%s\n' "$1" "${3:+ — $3}"
  fi
}

has()   { printf '%s' "$OUT" | grep -qF -- "$1"; }
lacks() { ! printf '%s' "$OUT" | grep -qF -- "$1"; }

echo "=== godot-lock.sh red arm ==="
echo "wrapper: $WRAPPER"
echo "lock:    $LOCK (private; the shared gate lock is untouched)"

# Every case below invokes the wrapper the DOCUMENTED way — from inside the repo
# by absolute path — so the tree guard is satisfied. Case [F] is the one that
# deliberately steps outside it.
cd "$ROOT" || { echo "cannot cd to $ROOT" >&2; exit 1; }

# ── A: contended, default flags → refuse loudly, claim nothing ──────────────
echo "[A] contended lock, no override"
hold_lock
check "setup: the holder really holds the lock" $?
run_wrapper --headless --path . --import
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -ne 0 ];                                    check "exits non-zero" $?
[ "$RC" -eq 75 ];                                    check "exits 75 EX_TEMPFAIL, not a generic 1" $? "rc=$RC"
lacks "lock acquired";                               check "prints NO 'lock acquired' line" $?
lacks "GODOT-RAN";                                   check "does NOT execute Godot" $?
has "refusing to run unlocked";                      check "says it is refusing to run unlocked" $?
has "$LOCK";                                         check "names the lock file" $?
has "holder is UNKNOWN";                             check "says the holder is unknown" $?
release_lock
# Prove the wait actually ended, rather than assuming the kill worked: a stale
# holder would silently turn every later case into a contended one.
flock -n "$LOCK" -c true 2>/dev/null; check "the lock is free again after release" $?

# ── B: contended, --proceed-unlocked → runs, says so, still claims nothing ─
echo "[B] contended lock with --proceed-unlocked"
hold_lock
check "setup: the holder really holds the lock" $?
run_wrapper --proceed-unlocked --headless --path . --import
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -eq 0 ];                                     check "runs (exit 0)" $?
has "GODOT-RAN";                                     check "executes Godot" $?
lacks "lock acquired";                               check "still prints NO 'lock acquired' line" $?
has "continuing WITHOUT the lock";                   check "says it is running without the lock" $?
release_lock

# ── C: free lock → taken, said, and used ───────────────────────────────────
echo "[C] free lock"
run_wrapper --headless --path . --import
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -eq 0 ];                                     check "runs (exit 0)" $?
has "path=LOCKED";                                   check "states which path it took" $?
has "lock acquired";                                 check "reports the lock acquired (true here)" $?
has "GODOT-RAN";                                     check "executes Godot" $?
[ "$(printf '%s' "$OUT" | grep -cF 'lock acquired')" -eq 1 ]; check "the acquired line appears exactly once" $?

# ── D: nested inside a holder, the way verify-all nests ────────────────────
echo "[D] nested: an ancestor already holds the lock"
cat > "$TMP/holder.sh" <<'HOLDEREOF'
#!/usr/bin/env bash
# Hold the lock on fd 9 and run the wrapper as a CHILD, so the wrapper's /proc
# ancestor walk finds this process holding the lock file — which is exactly the
# situation verify-all creates for anything it spawns. The ready file is the
# same handshake hold_lock uses: the wrapper must not start before the lock is
# actually held, or this case silently tests the non-nested path.
exec 9>"$1"
flock -x 9
: > "$2"
shift 2
"$@"
HOLDEREOF
chmod +x "$TMP/holder.sh"
READY="$TMP/ready.D"
OUT="$(GODOT_BIN="$STUB" GODOT_LOCK_FILE="$LOCK" GODOT_LOCK_WAIT=2 bash "$TMP/holder.sh" "$LOCK" "$READY" bash "$WRAPPER" --headless --path . --import 2>&1)"
RC=$?
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -eq 0 ];                                     check "runs without self-deadlocking (exit 0)" $?
has "ANCESTOR-HOLDS-LOCK";                           check "names the NESTED path it took" $?
lacks "lock acquired";                               check "does not claim to have acquired the lock" $?
has "GODOT-RAN";                                     check "executes Godot" $?

# There WAS a case [E] "plain uncontended run" here, asserting exit 0 and that
# Godot ran. It was removed rather than kept as a cheap smoke check: it invoked
# the wrapper with arguments identical to case [C] and asserted a strict subset
# of what [C] already asserts. On a loaded box one wrapper invocation costs 5-10s
# (it walks /proc and forks a dozen helpers), and this gate runs before the
# import on the fleet's bottleneck box, so a duplicate that buys no coverage is
# the most expensive line in the file. Do not re-add it without an argument that
# [C] does not already cover.

# ── F: a green must never describe a different tree ───────────────────────
# The wrapper resolves its own root from its own location, so invoking it BY
# ABSOLUTE PATH from another worktree used to silently run Godot against the
# WRONG tree and still exit 0. On this machine the wrong tree is the shared base
# checkout: 17 commits behind origin/main, carrying another lane's unlanded
# commit, with 36 dirty paths. Proven with the print marker before the guard
# existed: a stub Godot reported pwd=<base checkout> while the caller stood in a
# clean worktree at origin/main, and the run exited 0 with nothing in the output
# saying so. This is the worst failure a wrapper can have — a confident,
# well-formatted result about code nobody meant to test.
echo "[F] invoked from another tree must refuse, not silently substitute"
OUT="$(cd "$TMP" && GODOT_BIN="$STUB" GODOT_LOCK_FILE="$LOCK" GODOT_LOCK_WAIT=2 bash "$WRAPPER" --headless --path . --import 2>&1)"
RC=$?
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -eq 64 ];                                   check "exits 64 EX_USAGE, distinct from a lock timeout" $? "rc=$RC"
lacks "GODOT-RAN";                                   check "does NOT run Godot against the wrong tree" $?
has "REFUSING";                                     check "says it is refusing" $?
has "$TMP";                                         check "names the caller's directory" $?
has "$ROOT";                                        check "names the wrapper's repo" $?
has "cd into the tree you want to test";            check "gives the one-line remedy" $?

echo "[F2] the same call, deliberately overridden"
OUT="$(cd "$TMP" && GODOT_BIN="$STUB" GODOT_LOCK_FILE="$LOCK" GODOT_LOCK_WAIT=2 bash "$WRAPPER" --allow-cross-tree --headless --path . --import 2>&1)"
RC=$?
printf '%s\n' "$OUT" | sed 's/^/    | /'
[ "$RC" -eq 0 ];                                     check "runs when explicitly allowed (exit 0)" $?
has "WARNING: --allow-cross-tree";                  check "still warns which two trees are involved" $?
has "pwd=$ROOT";                                     check "print marker: Godot would open the WRAPPER's tree, proving the substitution was real" $?

# ONE-SHOT / ALWAYS FLAKE — exists so the GATE'S RETRY can be proven rather
# than assumed. Unset in every normal run, so it cannot affect a real gate.
# tools/verify-all.mjs inherits the environment, so:
#   GODOT_LOCK_TEST_FLAKE=once GODOT_LOCK_TEST_FLAKE_MARKER=/tmp/m node tools/verify-all.mjs --quick
# fails exactly once (creating the marker) and then passes — exercising the
# retry path end to end. `always` fails on every attempt, which proves the retry
# does NOT mask a genuine failure. This hook is why the retry is believed: a
# retry nobody has watched fire is a hope.
case "${GODOT_LOCK_TEST_FLAKE:-}" in
  once)
    if [ ! -e "${GODOT_LOCK_TEST_FLAKE_MARKER:-/nonexistent}" ]; then
      : > "${GODOT_LOCK_TEST_FLAKE_MARKER}" 2>/dev/null || true
      echo "  FAIL  deliberate one-shot flake (proves the gate retries)"
      FAIL=$((FAIL + 1))
    fi
    ;;
  always) echo "  FAIL  deliberate permanent flake (proves the gate does NOT mask a real failure)"; FAIL=$((FAIL + 1)) ;;
esac

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
