#!/usr/bin/env bash
# tools/godot-lock.sh — run Godot under the SAME per-repo lock as verify-all.sh.
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
# Extra flag (consumed here, not passed to Godot):
#   --clean-tmp   delete leftover 0-byte .godot/imported/*.tmp before running.
#
# The lock path MUST match verify-all.sh exactly (same ROOT -> same cksum), so
# do not "improve" one side without the other.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-godot}"

CLEAN_TMP=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --clean-tmp) CLEAN_TMP=1 ;;
    *) ARGS+=("$a") ;;
  esac
done

mkdir -p /tmp/shooter
if command -v flock >/dev/null 2>&1; then
  LOCK_FILE="/tmp/shooter/verify-all.$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1).lock"
  exec 9>"$LOCK_FILE"
  flock -w 900 9 || echo "godot-lock: WARNING: lock not acquired in 900s; proceeding (may race the gate)" >&2
fi

if [ "$CLEAN_TMP" -eq 1 ]; then
  find .godot/imported -maxdepth 1 -type f -size 0 \( -name '*.ctex-*' -o -name '*.tmp' \) -delete 2>/dev/null || true
fi

exec "$GODOT_BIN" "${ARGS[@]}"
