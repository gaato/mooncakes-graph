#!/usr/bin/env bash
# Writes llms.txt (https://llmstxt.org): what the site is, where its data is
# and the current top of the ranking, for agents that read no JavaScript.
# Usage: llms-txt.sh CLI
set -euo pipefail
cli=$1

as_of=$("$cli" stats | sed -n 's/.*"index_fetched_at": "\([^"]*\)".*/\1/p')
modules=$("$cli" stats | sed -n 's/.*"modules": \([0-9]*\).*/\1/p')
cli_version=$(sed -nE 's/^version = "(.*)"$/\1/p' "$(dirname "$0")/../mooncakes-graph/moon.mod")

cat <<TXT
# mooncakes graph

> Which mooncakes.io modules (the MoonBit package registry) are depended on
> the most: an interactive map of the registry's dependency graph, and the
> data behind it, rebuilt daily. Unofficial; not affiliated with mooncakes.io
> or the MoonBit team.

The data comes from the registry index that \`moon update\` fetches, as of
${as_of:-an unknown time} (${modules} modules). It is derived from mooncakes.io's data;
module descriptions are their authors' own. The registry's test modules
(\`test/*\`), which are in the index but not on the site, are left out.

A module's current version is its last version that is not yanked (its last
version when every version is yanked), and the graph has an edge from a
module to each module its current version depends on.

## Data

- [metrics.tsv](data/metrics.tsv): every module with how many modules depend on it. Columns: \`module\`, \`direct\` (modules whose current version depends on it), \`transitive\` (modules that depend on it directly or through others), \`owners\` (owners other than its own among the direct ones). Sorted by \`transitive\`.
- [versions.jsonl](data/versions.jsonl): every published version, one JSON object per line: \`{"name", "version", "created_at", "deps": {module: version, null, or {"version"?, "alias"?, "path"?}}, "yanked", "deprecated"?}\` (the object form only when the dependency has an import alias or a local path), in publication order per module.
- [modules.jsonl](data/modules.jsonl): one line per module from its current version: \`name\`, \`version\`, and \`description\`, \`repository\`, \`license\`, \`keywords\`, \`yanked_reason\` when present.
- [meta.json](data/meta.json): when the index was fetched, and counts of modules, versions and edges.

## Most depended on

TXT

"$cli" top -n 20 | tail -n +2 |
  awk -F'\t' '{ printf "%d. %s: %s modules depend on it, %s directly\n", NR, $1, $3, $2 }'

cat <<'TXT'

## Optional

- [The map](./): `?m=owner/name` opens a module, for example [?m=moonbitlang/async](?m=moonbitlang/async).
TXT
printf '%s\n' "- [Command-line tool](https://mooncakes.io/docs/gaato/mooncakes-graph): \`moonx gaato/mooncakes-graph/cmd/mooncakes-graph@${cli_version} dependents MODULE\` (or \`deps\`, \`top\`, \`stats\`) answers the same questions from a local \`moon update\`, offline."
echo "- [Source](https://github.com/gaato/mooncakes-graph)"
