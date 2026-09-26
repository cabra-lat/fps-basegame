#!/usr/bin/env bash
# Shell-level regression for the hard-bounded timeout helper.
# It uses only a TERM-ignoring fake process and a child sleeper; no Godot.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/bounded-timeout.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bounded-timeout-test.XXXXXX")"
PID_FILE="$TMP_DIR/pids"
trap 'rm -rf -- "$TMP_DIR"' EXIT

start_ns="$(date +%s%N)"
set +e
run_bounded_timeout 1 1 bash -c '
	set -u
	pid_file="$1"
	trap "" TERM
	printf "%s\n" "$$" >"$pid_file"
	sleep 30 &
	child=$!
	printf "%s\n" "$child" >>"$pid_file"
	wait "$child"
' bash "$PID_FILE" >"$TMP_DIR/output.log" 2>&1
rc=$?
set -e
end_ns="$(date +%s%N)"
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))

if [ "$rc" -ne 124 ] && [ "$rc" -ne 137 ]; then
	echo "FAIL: expected timeout exit 124/137, got $rc" >&2
	exit 1
fi
if [ "$elapsed_ms" -gt 5000 ]; then
	echo "FAIL: TERM-ignoring process was not killed within 5000ms (${elapsed_ms}ms)" >&2
	exit 1
fi
if [ ! -s "$PID_FILE" ]; then
	echo "FAIL: fake process did not record its PID" >&2
	exit 1
fi
while IFS= read -r pid; do
	[ -z "$pid" ] && continue
	if ps -o stat= -p "$pid" 2>/dev/null | grep -qv '^[[:space:]]*Z'; then
		echo "FAIL: process $pid survived timeout" >&2
		exit 1
	fi
done <"$PID_FILE"

assert_missing_prerequisite_fails_closed() {
	local missing="$1" fakebin tool rc
	fakebin="$(mktemp -d "${TMPDIR:-/tmp}/bounded-timeout-path.XXXXXX")"
	for tool in timeout setsid; do
		[ "$tool" = "$missing" ] && continue
		ln -s "$(command -v "$tool")" "$fakebin/$tool"
	done
	set +e
	PATH="$fakebin" run_bounded_timeout 1 1 true >/dev/null 2>&1
	rc=$?
	set -e
	rm -rf -- "$fakebin"
	if [ "$rc" -ne 125 ]; then
		echo "FAIL: missing $missing did not fail closed (rc=$rc)" >&2
		exit 1
	fi
}

assert_missing_prerequisite_fails_closed timeout
assert_missing_prerequisite_fails_closed setsid
echo "PASS: TERM-ignoring process group killed in ${elapsed_ms}ms (rc=$rc); missing timeout/setsid fail closed"
