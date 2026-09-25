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

command -v ccache >/dev/null 2>&1 && ccache --version >/dev/null 2>&1 && ccache_usable=1 || ccache_usable=0

# ── ccache shims ─────────────────────────────────────────────────────────────
# godot-cpp resolves its compiler BY NAME from PATH: SConstruct builds a default
# Environment before opts.Update(env), and CC/CXX are not registered variables
# (tools/godotcpp.py declares target/platform/arch/threads/... but never CC or
# CXX), so `scons CC="ccache g++"` is dropped as an unknown variable and SCons
# prints a warning about it. The other injection point, the custom.py that
# SConstruct imports from the source root, is forbidden by the pristine-source
# checks above. A directory of same-named shims prepended to PATH is therefore
# the only route that survives both, and it keeps common_compiler_flags.py's
# `os.path.basename(env["CC"])` is-clang test honest: basename stays "g++"
# instead of becoming the string "ccache g++".
#
# This is safe to share between machines only while the build uses baseline ISA
# flags. `arch=x86_64` expands to -march=x86-64, a fixed target, so objects stay
# portable. If anyone adds -march=native or -mtune=native, a shared ccache stops
# being sound and must be disabled.
#
# Why this is worth having: the GodotIK build cache in CI is keyed on the exact
# pinned commits and deliberately has no restore-keys, so bumping a pin restores
# nothing and forces a full cold rebuild. That is the case ccache exists for --
# godot-cpp's headers barely move when the extension's own sources do, so most
# translation units become cache hits. When the pins have not moved, the build
# cache already makes the build a no-op and ccache changes nothing.
ccache_shim_dir=""
if [[ "$ccache_usable" == 1 && "${GODOTIK_USE_CCACHE:-1}" != "0" ]]; then
  ccache_shim_dir="$(mktemp -d)"
  for cc_name in gcc g++ cc c++ clang clang++; do
    cc_real="$(command -v "$cc_name" 2>/dev/null || true)"
    # Never shim a name that already resolves inside the shim dir.
    [[ -n "$cc_real" && "$cc_real" != "$ccache_shim_dir"/* ]] || continue
    printf '#!/usr/bin/env bash\nexec ccache %q "$@"\n' "$cc_real" > "$ccache_shim_dir/$cc_name"
    chmod +x "$ccache_shim_dir/$cc_name"
  done
  if [[ -z "$(command -v gcc 2>/dev/null || true)" ]]; then
    echo "ccache shims produced no compiler; building without ccache" >&2
    rm -rf "$ccache_shim_dir"
    ccache_shim_dir=""
  else
    export PATH="$ccache_shim_dir:$PATH"
    ccache --set-config=quiet=true >/dev/null 2>&1 || true
    printf 'ccache enabled (compiler cache at %s)\n' "${CCACHE_DIR:-$HOME/.ccache}"
  fi
elif [[ "$ccache_usable" != 1 ]]; then
  echo "ccache not available; building without a compiler cache" >&2
elif [[ "${GODOTIK_USE_CCACHE:-1}" == "0" ]]; then
  echo "GODOTIK_USE_CCACHE=0; building without a compiler cache" >&2
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
  build_rc=0
else
  build_rc=$?
fi

# Report the compiler cache whatever happened. A build that dies on the timeout
# is exactly when you want to know how much of it was reusable, and the
# hard-killed children cannot report for themselves: ccache flushes its counters
# on a clean exit, so after a kill the counters read zero even though the
# results are on disk. Count the stored result files as well, because that
# number survives a kill and is the measure that actually matters.
if [[ -n "$ccache_shim_dir" ]]; then
  ccache_dir="${CCACHE_DIR:-$HOME/.ccache}"
  printf 'ccache: %s cached result file(s) in %s\n' \
    "$(find "$ccache_dir" -type f 2>/dev/null | wc -l)" "$ccache_dir"
  ccache_stats="$(ccache --show-stats 2>/dev/null || ccache -s 2>/dev/null || true)"
  if printf '%s' "$ccache_stats" | grep -qE 'Cacheable calls'; then
    printf '%s\n' "$ccache_stats"
  else
    echo "ccache: counters unavailable, which is expected if the build was" \
      "killed mid-flight; the cached result file count above is the real measure"
  fi
fi

if [[ "$build_rc" != 0 ]]; then
  echo "GodotIK SCons build failed or timed out (rc=$build_rc, limit=${build_timeout}s)" >&2
  exit "$build_rc"
fi

[[ -f "$SOURCE/godot_project/addons/libik/bin/libik.so" ]] || {
  echo "GodotIK build completed without libik.so" >&2
  exit 1
}
cp -a "$SOURCE/godot_project/addons/libik" "$RUNTIME"
printf 'Staged GodotIK %s at %s\n' "$EXPECTED_GODOTIK" "$RUNTIME"
printf 'MIT notices remain available in third_party/godotik/{LICENSE.md,THIRDPARTY.md}\n'
