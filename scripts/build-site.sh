#!/usr/bin/env bash
# Builds the static site into site/dist from the local registry index.
# Run `moon update` first for fresh data.
set -euo pipefail
cd "$(dirname "$0")/.."

moon build --target native --release mooncakes-graph/src/cmd/mooncakes-graph >/dev/null
mkdir -p site/public/data
cli=_build/native/release/build/gaato/mooncakes-graph/cmd/mooncakes-graph/mooncakes-graph.exe
"$cli" versions >site/public/data/versions.jsonl
# Read only when a module is first opened.
"$cli" modules >site/public/data/modules.jsonl
# For agents and anyone else who wants the data without the map.
"$cli" top -n 0 >site/public/data/metrics.tsv
"$cli" stats >site/public/data/meta.json
scripts/llms-txt.sh "$cli" >site/public/llms.txt
warren -C site build --browser-entry web
