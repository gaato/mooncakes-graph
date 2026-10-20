# gaato/mooncakes-graph

The [mooncakes.io](https://mooncakes.io) registry as a dependency graph: what
depends on what, and which modules the MoonBit ecosystem depends on the most.
It reads the registry index that `moon update` keeps, so it works offline.

Unofficial; not affiliated with mooncakes.io or the MoonBit team. The same data
as an interactive map: https://gaato.github.io/mooncakes-graph/

## Command line

```sh
moon update
moonx gaato/mooncakes-graph/cmd/mooncakes-graph dependents gaato/http
```

| command | output |
|---|---|
| `dependents MODULE...` | What depends on MODULE, as a tree like `tree(1)` |
| `deps MODULE...` | What MODULE depends on, as a tree |
| `top [-n N] [--by direct\|transitive\|owners]` | The most depended-on modules, as TSV |
| `stats` | Counts of modules, versions and edges, as JSON |
| `versions`, `modules` | Every version, and each module's description, as JSONL |

The trees take tree's `-L`, `--noreport` and `-J`. `--help` lists the rest.

## Library

```mbt nocheck
let index = @fs.read(@fs.index_dir().unwrap())
let graph = @graph.Graph::new(index.modules)
let metrics = graph.metrics()
for node in metrics.ranking(Transitive)[:10] {
  println("\{graph.name(node)}: \{metrics.get(node, Transitive)}")
}
```

`Graph` follows each module's current version (its last version that is not
yanked). `metrics` counts direct, transitive and other-owner dependents;
`forest` builds the trees the CLI prints; `requirement` tells which version one
module asks of another and whether that is from an older release line.

## License

Apache-2.0
