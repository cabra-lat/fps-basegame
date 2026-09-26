#!/usr/bin/env bash
# tools/godot-lock.sh — run Godot under the SAME per-cache lock as verify-all.sh.
#
# WHY: `.godot/` is a SHARED cache. The gate's own flock serializes verify-all
# runs against each other, but NOT the direct `godot --import` / harness calls
# other lanes make — so concurrent imports hang the gate (reproduced:
# `reimport | pistol_9mm_albedo.png`, timeout, plus leftover 0-byte
# `.godot/imported/*.tmp`). This wrapper takes the IDENTICAL lock, so a direct
# Godot invocation can never race the gate on the same repo.
#
# RULE (documented in the lane): run Godot DIRECTLY only through this wrapper —
#   tools/godot-lock.sh --headless --path . --import
#   tools/godot-lock.sh --headless --path . --script res://some/harness.gd
#
# Extra flags (consumed here, not passed to Godot):
#   --clean-tmp        delete leftover 0-byte .godot/imported/*.tmp before running.
#   --proceed-unlocked DELIBERATE override: if the lock cannot be taken within
#                      GODOT_LOCK_WAIT seconds, run anyway WITHOUT it. Off by
#                      default, because running unlocked is exactly the race this
#                      wrapper exists to prevent. When used, the output says so.
#
# Environment:
#   GODOT_LOCK_WAIT    seconds to wait for the lock (default 900). Lowering it
#                      only makes this wrapper refuse MORE often, never less
#                      safe, which is why it is overridable for tests.
#   GODOT_LOCK_FILE    TEST ONLY: use a different lock file, so
#                      tools/test-godot-lock.sh can hold a lock and be
#                      contended without touching the shared one the gate and
#                      every other lane use. The DEFAULT is unchanged and must
#                      stay byte-identical to verify-all.sh's lock path.
#
# EXIT CODES: 0 ran, 69 missing dependency (flock), and 75 EX_TEMPFAIL when the
# lock could not be taken and --proceed-unlocked was not given. 75 is distinct
# on purpose: a caller must be able to tell "somebody else holds the lock, retry"
# apart from "the harness failed", because those two need opposite responses.
#
# The lock path MUST match verify-all.sh exactly (same resolved .godot cache
# path), so do not "improve" one side without the other.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-godot}"
GODOT_LOCK_WAIT="${GODOT_LOCK_WAIT:-900}"

CLEAN_TMP=0
PROCEED_UNLOCKED=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --clean-tmp) CLEAN_TMP=1 ;;
    --proceed-unlocked) PROCEED_UNLOCKED=1 ;;
    *) ARGS+=("$a") ;;
  esac
done

if ! command -v flock >/dev/null 2>&1; then
  echo "godot-lock: flock is required to protect the shared .godot cache" >&2
  exit 69
fi

mkdir -p /tmp/shooter
GODOT_CACHE="$(realpath .godot 2>/dev/null || printf '%s' "$ROOT/.godot")"
LOCK_FILE="${GODOT_LOCK_FILE:-/tmp/shooter/verify-all.${GODOT_CACHE//\//_}.lock}"

# A Node/timeout intermediary can sit between verify-all.sh and this wrapper,
# so argv-based ancestor detection alone is not sufficient.  If any ancestor
# still has the gate lock file open, the gate already owns serialization; do
# not open a second descriptor and wait on our own parent.  The inode/device
# check is intentionally independent of process names and works through Node.
_lock_held_by_ancestor() {
  local target="$1"
  local target_dev target_inode pid fd fd_dev fd_inode depth=0
  target_dev="$(stat -Lc '%d' "$target" 2>/dev/null || true)"
  target_inode="$(stat -Lc '%i' "$target" 2>/dev/null || true)"
  [ -n "$target_dev" ] && [ -n "$target_inode" ] || return 1
  pid="${PPID:-1}"
  while [ "$depth" -lt 64 ]; do
    case "$pid" in ''|*[!0-9]*|0|1) break ;; esac
    for fd in "/proc/$pid/fd/"*; do
      [ -e "$fd" ] || continue
      fd_dev="$(stat -Lc '%d' "$fd" 2>/dev/null || true)"
      fd_inode="$(stat -Lc '%i' "$fd" 2>/dev/null || true)"
      if [ "$fd_dev" = "$target_dev" ] && [ "$fd_inode" = "$target_inode" ]; then
        return 0
      fi
    done
    pid="$(awk '/^PPid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)"
    depth=$((depth + 1))
  done
  return 1
}

# The lock file is intentionally persistent. Never unlink it after a holder
# exits: flock releases kernel ownership automatically, while unlinking a held
# inode lets a new process create a different inode and bypass serialization.
#
# NESTED-GATE fast path (testkit 2026-09-22): verify-all.sh holds this same lock
# for its WHOLE run (FD 9, released only on exit). Anything the gate itself
# spawns that comes back through this wrapper (gate_qa -> audit.mjs -> QA-001
# probe) opens the lockfile on a NEW file description, so `flock -n` fails
# against the inherited lock and `flock -w 900` burns 900s waiting on its own
# parent (measured: FULL round where qa_audit hit `timeout 900` -> rc=124 ->
# WARN, with zero external contention). The gate already serializes us against
# the outside world, so re-locking is both unnecessary and self-deadlocking.
#
# Detection is deliberately STRICT: an ancestor counts only if it is actually
# EXECUTING this repo's verify-all.sh — i.e. argv = [<shell>, <script>] with
# <script> canonicalizing to $ROOT/tools/verify-all.sh. A mere substring match
# on the full command line is WRONG: `bash -c` payloads carry their script text
# in argv (a lane running `bash -c '...verify-all.sh...'` would false-positive).
# The FD/inode ancestor check above is the fallback for Node/timeout chains;
# uncertain external ancestry falls through to the legacy wait below.
_in_gate=0
_gate_script="$(readlink -m "$ROOT/tools/verify-all.sh" 2>/dev/null || true)"
if [ -n "$_gate_script" ] && [ -d /proc/self ]; then
  _p="${PPID:-1}" _n=0
  while [ "$_n" -lt 64 ]; do
    case "$_p" in ''|*[!0-9]*|1|0) break ;; esac
    _a0="$(tr '\0' '\n' < "/proc/$_p/cmdline" 2>/dev/null | sed -n '1p')"
    _a1="$(tr '\0' '\n' < "/proc/$_p/cmdline" 2>/dev/null | sed -n '2p')"
    case "${_a0##*/}" in
      bash|sh|dash|zsh)
        case "$_a1" in ""|-*) ;; *)
          _acwd="$(readlink "/proc/$_p/cwd" 2>/dev/null || true)"
          case "$_a1" in
            /*) _ascript="$(readlink -m "$_a1" 2>/dev/null || true)" ;;
            *)  _ascript="$(readlink -m "$_acwd/$_a1" 2>/dev/null || true)" ;;
          esac
          if [ -n "$_ascript" ] && [ "$_ascript" = "$_gate_script" ]; then
            _in_gate=1
            break
          fi
          ;;
        esac
        ;;
    esac
    _p="$(awk '{print $4}' "/proc/$_p/stat" 2>/dev/null || echo 1)"
    _n=$((_n + 1))
  done
fi
if [ "$_in_gate" -eq 1 ]; then
  echo "godot-lock: path=NESTED-IN-GATE ($ROOT) — verify-all already holds the lock, skipping re-lock" >&2
elif _lock_held_by_ancestor "$LOCK_FILE"; then
  # Same effect, different reason: an ancestor (Node/timeout intermediary)
  # holds the lock file open. Say WHICH path, because there are now three ways
  # out of this script and only two of them hold the lock.
  echo "godot-lock: path=ANCESTOR-HOLDS-LOCK — an ancestor process already holds ${LOCK_FILE}, skipping re-lock" >&2
else
  exec 9>"$LOCK_FILE"
  if flock -n 9; then
    # Lock was FREE -> any `godot` already running is NOT holding it (bypass).
    # Same "lock acquired" wording as the waiting branch below, deliberately:
    # one phrase means one state, so a grep for it can never match a run that
    # did not have the lock.
    echo "godot-lock: lock acquired immediately (${LOCK_FILE}) — path=LOCKED" >&2
    if command -v pgrep >/dev/null 2>&1; then
      # NOTE: `pgrep -c` prints 0 AND exits 1 on no match, so `|| echo 0`
      # would append a second line ("0\n0") and break the integer test.
      others="$(pgrep -c -x godot 2>/dev/null || true)"
      [ "${others:-0}" -gt 0 ] 2>/dev/null && echo "godot-lock: WARNING: ${others} 'godot' process(es) running WITHOUT the lock — .godot may still race (use this wrapper everywhere)" >&2
    fi
  else
    # Say so BEFORE blocking: a caller that wraps us in a short `timeout` then sees
    # exit 124 and may think the harness broke — it is just the lock wait.
    echo "godot-lock: waiting up to ${GODOT_LOCK_WAIT}s for the gate lock (${LOCK_FILE})..." >&2
    _t0="$(date +%s)"
    if flock -w "$GODOT_LOCK_WAIT" 9; then
      # ONLY HERE. The acquired line is printed if and only if flock returned 0.
      # An earlier version printed it unconditionally, so a run that timed out
      # and continued UNLOCKED logged that it had acquired the lock — the one
      # piece of information this wrapper exists to report, reported falsely.
      echo "godot-lock: lock acquired after $(( $(date +%s) - _t0 ))s (${LOCK_FILE})" >&2
    elif [ "$PROCEED_UNLOCKED" -eq 1 ]; then
      echo "godot-lock: WARNING: lock NOT acquired in ${GODOT_LOCK_WAIT}s; --proceed-unlocked was given, continuing WITHOUT the lock — .godot WILL race the gate" >&2
      echo "godot-lock:          holder is UNKNOWN; flock cannot report which process owns ${LOCK_FILE}" >&2
    else
      echo "godot-lock: ERROR: lock NOT acquired in ${GODOT_LOCK_WAIT}s; refusing to run unlocked" >&2
      echo "godot-lock:        lock file: ${LOCK_FILE}" >&2
      echo "godot-lock:        holder is UNKNOWN — flock does not report the owning process, so this says nothing about why it is held" >&2
      echo "godot-lock:        retry when the gate is free, or pass --proceed-unlocked to override deliberately" >&2
      echo "godot-lock:        (a genuinely hung godot process is a DIFFERENT fault; this wrapper will not kill the holder)" >&2
      exit 75
    fi
  fi
fi

if [ "$CLEAN_TMP" -eq 1 ]; then
  find .godot/imported -maxdepth 1 -type f -size 0 \( -name '*.ctex-*' -o -name '*.tmp' \) -delete 2>/dev/null || true
fi

exec "$GODOT_BIN" "${ARGS[@]}"
