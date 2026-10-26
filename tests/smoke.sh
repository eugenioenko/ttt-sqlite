#!/usr/bin/env bash
# Opens a small database in the real ttt binary, runs a query, and checks that a
# write is stopped by the read-only first run. Needs ttt (or $TTT) and sqlite3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TTT="${TTT:-$(command -v ttt || true)}"
if [ -z "$TTT" ] || ! command -v sqlite3 >/dev/null; then
  echo "smoke: skipped (needs ttt, or TTT=/path/to/ttt, and sqlite3 on PATH)"
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sqlite3 "$TMP/smoke.db" "CREATE TABLE t(a, b); INSERT INTO t VALUES (1, 'x'), (2, NULL);"
mkdir -p "$TMP/config"
TTT_CONFIG_DIR="$TMP/config" "$TTT" --size 160x45 --plugin "$ROOT/init.lua" --exec "
wait-for Explore; exec \"SQLite: Open Database…\"; wait-for \"Database file\"; type $TMP/smoke.db; key enter;
wait-for \"Tables and views\"; exec \"SQLite: New Query\"; wait-for \"Write SQL\";
type select count(*) as n from t; key F5; wait-for \"1 row\"; screenshot $TMP/read.txt;
key ctrl+a; type insert into t default values; key F5; wait-for \"write access\"; screenshot $TMP/write.txt; quit" >/dev/null
grep -q "1 row" "$TMP/read.txt"
grep -q "write access" "$TMP/write.txt"
[ "$(sqlite3 "$TMP/smoke.db" "SELECT count(*) FROM t")" = 2 ] || { echo "smoke: the read-only run changed the database"; exit 1; }
echo "smoke: ok"
