#!/usr/bin/env bash
# Number gates against the live index: the CLI must agree with the
# independent Python reader in scripts/oracle.py.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

moon build --target native --release app/cli >/dev/null
cli=_build/native/release/build/gaato/mooncakes-graph/cli/cli.exe

fail=0
check() {
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}

"$cli" versions >"$tmp/cli.jsonl"
python3 -I scripts/oracle.py versions >"$tmp/oracle.jsonl"
name="versions matches oracle byte for byte"; check cmp -s "$tmp/cli.jsonl" "$tmp/oracle.jsonl"

for key in direct transitive owners; do
  "$cli" top -n 0 --by "$key" >"$tmp/cli.tsv"
  python3 -I scripts/oracle.py top "$key" >"$tmp/oracle.tsv"
  name="top --by $key matches oracle"; check cmp -s "$tmp/cli.tsv" "$tmp/oracle.tsv"
done

python3 -I scripts/oracle.py stats

exit "$fail"
