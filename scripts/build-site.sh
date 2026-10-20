#!/usr/bin/env bash
# Builds the static site into app/dist from the local registry index.
# Run `moon update` first for fresh data.
set -euo pipefail
cd "$(dirname "$0")/.."

moon build --target native --release app/cmd/mooncakes-graph >/dev/null
mkdir -p app/public/data
cli=_build/native/release/build/gaato/mooncakes-graph/cmd/mooncakes-graph/mooncakes-graph.exe
"$cli" versions >app/public/data/versions.jsonl
# Read only when a module is first opened.
"$cli" modules >app/public/data/modules.jsonl
# For agents and anyone else who wants the data without the map.
"$cli" top -n 0 >app/public/data/metrics.tsv
"$cli" stats >app/public/data/meta.json
scripts/llms-txt.sh "$cli" >app/public/llms.txt
warren -C app build --browser-entry web
