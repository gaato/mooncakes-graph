#!/usr/bin/env bash
# The repository's checks, the same locally and in CI: formatting, interfaces,
# warnings, tests on every backend, changelogs, and then the number gates
# against the live index, where the CLI must agree with the independent Python
# reader in scripts/oracle.py and with tree(1).
# Needs `moon update` to have fetched the index, python3 and tree.
set -euo pipefail
cd "$(dirname "$0")/.."

run() { echo "+ $*"; "$@"; }

run moon fmt --check
run moon info
# Only meaningful in CI: in a jj working copy `git diff` compares against the
# parent change, so uncommitted edits would look stale.
if [ "${CI:-}" = true ]; then
  git diff --exit-code -- '*.mbti' || { echo "pkg.generated.mbti is stale: run 'moon info' and commit" >&2; exit 1; }
fi
# Warnings fail: reserved words (warning 35) and deprecations are cheap to fix
# now and breaking to fix after publishing.
run moon check --deny-warn --target native
run moon check --deny-warn --target js
libs=(force/src force/src/internal/quadtree mooncakes_index/src mooncakes-graph/src)
run moon check --deny-warn --target wasm-gc "${libs[@]}"
run moon test --target native
run moon test --target js
run moon test --target wasm-gc -p gaato/force -p gaato/force/internal/quadtree -p gaato/mooncakes_index -p gaato/mooncakes-graph
run scripts/release.sh check
# The published CLI runs as linear-memory Wasm under moonx.
run moon check --deny-warn --target wasm mooncakes-graph/src/cmd/mooncakes-graph
run moon build --target wasm --release mooncakes-graph/src/cmd/mooncakes-graph
wasm=_build/wasm/release/build/gaato/mooncakes-graph/cmd/mooncakes-graph/mooncakes-graph.wasm

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

moon build --target native --release mooncakes-graph/src/cmd/mooncakes-graph >/dev/null
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

# The Wasm build agrees with the native one, also inside the sandbox that
# SKILL.md tells agents to set up.
for args in "top -n 0 --by owners" "dependents gaato/http -J" "stats"; do
  "$cli" $args >"$tmp/native_out"
  moonrun "$wasm" $args >"$tmp/wasm_out"
  name="wasm $args matches native"; check cmp -s "$tmp/native_out" "$tmp/wasm_out"
done
printf '{"env":{"from_host":["HOME","MOON_HOME"]},"fs":{"read":["%s"]}}\n' \
  "${MOON_HOME:-$HOME/.moon}/registry/index" >"$tmp/policy.json"
moonrun --policy "$tmp/policy.json" "$wasm" stats >"$tmp/sandboxed" 2>&1 || true
"$cli" stats >"$tmp/native_out"
name="wasm runs in the SKILL.md sandbox"; check cmp -s "$tmp/native_out" "$tmp/sandboxed"

"$cli" stats | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d.pop("index_fetched_at"); print(json.dumps(d, sort_keys=True))' >"$tmp/cli_stats"
python3 -I scripts/oracle.py stats | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))' >"$tmp/oracle_stats"
name="stats matches oracle"; check cmp -s "$tmp/cli_stats" "$tmp/oracle_stats"
cat "$tmp/cli_stats"

[ "$fail" = 0 ] && echo "gates: OK"
exit "$fail"
