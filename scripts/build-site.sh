#!/usr/bin/env bash
# Builds the static site into app/dist from the local registry index.
# Run `moon update` first for fresh data.
set -euo pipefail
cd "$(dirname "$0")/.."

moon build --target native --release app/cli >/dev/null
mkdir -p app/public/data
_build/native/release/build/gaato/mooncakes-graph/cli/cli.exe versions >app/public/data/versions.jsonl
warren -C app build --browser-entry web
