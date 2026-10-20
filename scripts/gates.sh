#!/usr/bin/env bash
# Number gates against the live index: the CLI must agree with the
# independent Python reader in scripts/oracle.py.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

moon build --target native --release app/cmd/mooncakes-graph >/dev/null
cli=_build/native/release/build/gaato/mooncakes-graph/cmd/mooncakes-graph/mooncakes-graph.exe

fail=0
check() {
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}

"$cli" versions >"$tmp/cli.jsonl"
python3 -I scripts/oracle.py versions >"$tmp/oracle.jsonl"
name="versions matches oracle byte for byte"; check cmp -s "$tmp/cli.jsonl" "$tmp/oracle.jsonl"

"$cli" modules >"$tmp/cli_modules.jsonl"
python3 -I scripts/oracle.py modules >"$tmp/oracle_modules.jsonl"
name="modules matches oracle byte for byte"; check cmp -s "$tmp/cli_modules.jsonl" "$tmp/oracle_modules.jsonl"

for key in direct transitive owners; do
  "$cli" top -n 0 --by "$key" >"$tmp/cli.tsv"
  python3 -I scripts/oracle.py top "$key" >"$tmp/oracle.tsv"
  name="top --by $key matches oracle"; check cmp -s "$tmp/cli.tsv" "$tmp/oracle.tsv"
done

name="dependents/deps draw like tree(1)"; check python3 -I scripts/tree_gate.py "$cli"

"$cli" dependents gaato/http --noreport | tail -n +2 | sed 's/^[│├└─ ]*//; s/ (\*)$//' | sort -u >"$tmp/tree_names"
"$cli" dependents gaato/http -J | python3 -I -c 'import json,sys; print(json.load(sys.stdin)[-1]["modules"])' >"$tmp/count"
python3 -I scripts/oracle.py top transitive | awk -F'\t' '$1=="gaato/http"{print $3}' >"$tmp/oracle_count"
name="dependents count equals transitive dependents"; check cmp -s "$tmp/count" "$tmp/oracle_count"

"$cli" stats | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d.pop("index_fetched_at"); print(json.dumps(d, sort_keys=True))' >"$tmp/cli_stats"
python3 -I scripts/oracle.py stats | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))' >"$tmp/oracle_stats"
name="stats matches oracle"; check cmp -s "$tmp/cli_stats" "$tmp/oracle_stats"
cat "$tmp/cli_stats"

exit "$fail"
