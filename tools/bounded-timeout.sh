#!/usr/bin/env bash
# Shared hard-bounded command runner for CI/verification subprocesses.
#
# timeout(1) sends TERM at the deadline, but can then wait forever when the
# command ignores TERM or leaves a child holding the output pipe.  setsid
# gives the command its own process group; timeout --kill-after escalates to
# KILL for that group, so the caller gets a bounded return even for a broken
# process tree.  Linux util-linux provides both commands in CI and the dev
# environment; fail closed if either prerequisite is unavailable.

run_bounded_timeout() {
	local duration="$1" kill_after="$2"
	shift 2
	if ! command -v timeout >/dev/null 2>&1; then
		echo "bounded-timeout: timeout(1) is required" >&2
		return 125
	fi
	if ! command -v setsid >/dev/null 2>&1; then
		echo "bounded-timeout: setsid(1) is required for process-group cleanup" >&2
		return 125
	fi
	local rc=0
	setsid --wait timeout --kill-after="$kill_after" "$duration" "$@" || rc=$?
	# With setsid, GNU timeout may report 137 when its KILL escalation tears
	# down the group.  Preserve timeout(1)'s stable API for gate callers.
	case "$rc" in
		124|137|143) return 124 ;;
		*) return "$rc" ;;
	esac
}
