#!/usr/bin/env bash
# Build the pinned GodotIK source and stage its runtime addon for Godot.
# This script is intentionally CI-oriented: it refuses to overwrite an
# existing runtime tree and never downloads an unpinned binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/third_party/godotik"
RUNTIME="$ROOT/addons/libik"
EXPECTED_GODOTIK="3bc5d2fb45f6e5a7f9467a7b301f0019b2b43a23"
EXPECTED_GODOT_CPP="f3a1a2fd458dfaf4de08c906f22a2fe9e924b16f"

[[ -d "$SOURCE" ]] || { echo "GodotIK source missing: $SOURCE" >&2; exit 1; }
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$EXPECTED_GODOTIK" ]] || {
  echo "GodotIK revision mismatch; refusing to build an unpinned source tree" >&2
  exit 1
}
[[ -d "$SOURCE/godot-cpp" ]] || {
  echo "godot-cpp is not initialized; run recursive submodule checkout first" >&2
  exit 1
}
[[ "$(git -C "$SOURCE/godot-cpp" rev-parse HEAD)" == "$EXPECTED_GODOT_CPP" ]] || {
  echo "godot-cpp revision mismatch; refusing to build" >&2
  exit 1
}

# SCons writes its object cache below the source checkout. Keep that generated
# directory out of the nested submodule's status without modifying its tracked
# .gitignore (the top-level gitlink must remain clean in CI logs).
source_exclude="$(git -C "$SOURCE" rev-parse --git-path info/exclude)"
if ! grep -qxF '.scons-cache/' "$source_exclude" 2>/dev/null; then
  printf '.scons-cache/\n' >> "$source_exclude"
fi

# The source and its nested dependency must be pristine. SCons outputs are
# ignored by the upstream .gitignore; do not treat those generated files as
# source drift. Reject both staged/unstaged tracked edits and any other
# untracked source file before compiling.
if ! git -C "$SOURCE" diff --quiet || ! git -C "$SOURCE" diff --cached --quiet; then
  echo "GodotIK source has tracked changes; refusing to build" >&2
  exit 1
fi
if ! git -C "$SOURCE/godot-cpp" diff --quiet || ! git -C "$SOURCE/godot-cpp" diff --cached --quiet; then
  echo "godot-cpp has tracked changes; refusing to build" >&2
  exit 1
fi
source_untracked="$(git -C "$SOURCE" ls-files --others --exclude-standard -- . \
  ':(exclude).scons-cache/**' ':(exclude).sconsign.dblite' \
  ':(exclude)godot_project/addons/libik/bin/**')"
if [[ -n "$source_untracked" ]]; then
  echo "GodotIK source has unexpected untracked files:" >&2
  printf '%s\n' "$source_untracked" >&2
  exit 1
fi
cpp_untracked="$(git -C "$SOURCE/godot-cpp" ls-files --others --exclude-standard)"
if [[ -n "$cpp_untracked" ]]; then
  echo "godot-cpp has unexpected untracked files:" >&2
  printf '%s\n' "$cpp_untracked" >&2
  exit 1
fi

command -v timeout >/dev/null 2>&1 || { echo "timeout is required" >&2; exit 1; }
command -v scons >/dev/null 2>&1 || { echo "scons is required" >&2; exit 1; }
command -v g++ >/dev/null 2>&1 || { echo "g++ is required" >&2; exit 1; }

if [[ -e "$RUNTIME" ]]; then
  echo "Refusing to overwrite existing runtime tree: $RUNTIME" >&2
  exit 1
fi

jobs="${GODOTIK_BUILD_JOBS:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "GODOTIK_BUILD_JOBS must be a positive integer" >&2; exit 1; }
build_timeout="${GODOTIK_BUILD_TIMEOUT:-1500}"
[[ "$build_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "GODOTIK_BUILD_TIMEOUT must be a positive integer" >&2; exit 1; }
cache_dir="${SCONS_CACHE_DIR:-$SOURCE/.scons-cache}"
mkdir -p "$cache_dir"

# SConstruct emits the Linux shared object into the source tree. The runtime
# tree is staged only after a successful, revision-checked source build. The
# default 1500-second bound leaves room for a cold Linux build on GitHub's
# 4-vCPU runner; timeout's exit status is deliberately propagated.
if (cd "$SOURCE" && timeout --kill-after=10s "${build_timeout}s" \
  env SCONS_CACHE_DIR="$cache_dir" scons \
    target=template_release platform=linux arch=x86_64 -j"$jobs"); then
  :
else
  rc=$?
  echo "GodotIK SCons build failed or timed out (rc=$rc, limit=${build_timeout}s)" >&2
  exit "$rc"
fi

[[ -f "$SOURCE/godot_project/addons/libik/bin/libik.so" ]] || {
  echo "GodotIK build completed without libik.so" >&2
  exit 1
}
cp -a "$SOURCE/godot_project/addons/libik" "$RUNTIME"
printf 'Staged GodotIK %s at %s\n' "$EXPECTED_GODOTIK" "$RUNTIME"
printf 'MIT notices remain available in third_party/godotik/{LICENSE.md,THIRDPARTY.md}\n'
