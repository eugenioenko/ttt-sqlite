#!/usr/bin/env bash
# Unit tests (gopher-lua, the Lua ttt embeds; needs Go), then the smoke test,
# which is skipped unless ttt and sqlite3 are installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$ROOT/tests/runner" && go run . "$ROOT")
"$ROOT/tests/smoke.sh"
