#!/usr/bin/env bash
# Compatibility wrapper. The canonical orchestrator is tools/verify-all.mjs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node "$ROOT/tools/verify-all.mjs" "$@"
