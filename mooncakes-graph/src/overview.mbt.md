# gaato/mooncakes-graph

The [mooncakes.io](https://mooncakes.io) registry as a dependency graph: what
depends on what, and which modules the MoonBit ecosystem depends on the most.
It is a library and a command-line tool that prints dependency trees like
`tree(1)`. Both read the registry index that `moon update` keeps, so they work
offline.

Unofficial; not affiliated with mooncakes.io or the MoonBit team. The same data
as an interactive map: https://gaato.github.io/mooncakes-graph/

## Install

As a library:

```sh
moon add gaato/mooncakes-graph
```

The command-line tool runs with `moonx` without installing (see Run below), or
installs into `~/.moon/bin`:

```sh
moon install gaato/mooncakes-graph/cmd/mooncakes-graph
```

## Run

Fetch the index with `moon update`, then ask what depends on a module:

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

## Usage

Build a graph from index records and rank the modules by how many depend on
them:

```mbt check
///|
test "rank modules by their dependents" {
  let graph = @graph.Graph::from_records([
    @mooncakes_index.VersionRecord::new("a/core", version="0.1.0"),
    @mooncakes_index.VersionRecord::new("b/app", version="0.1.0", deps=[
      @mooncakes_index.Dep::new("a/core", version="0.1.0"),
    ]),
    @mooncakes_index.VersionRecord::new("c/tool", version="0.2.0", deps=[
      @mooncakes_index.Dep::new("b/app", version="0.1.0"),
    ]),
  ])
  let metrics = graph.metrics()
  let core = graph.find("a/core").unwrap()
  assert_eq(metrics.get(core, Direct), 1)
  assert_eq(metrics.get(core, Transitive), 2)
  assert_eq(metrics.ranking(Transitive).map(n => graph.name(n)), [
    "a/core", "b/app", "c/tool",
  ])
}
```

For the real registry, read the index with
[`gaato/mooncakes_index/fs`](https://mooncakes.io/docs/gaato/mooncakes_index)
and pass its modules to `Graph::new`:
`@graph.Graph::new(@fs.read(@fs.index_dir().unwrap()).modules)`.

`Graph` follows each module's current version (its last version that is not
yanked). `metrics` counts direct, transitive and other-owner dependents;
`forest` builds the trees the CLI prints; `requirement` tells which version one
module asks of another and whether that is from an older release line.

## Links

- [Changelog](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes-graph/CHANGELOG.md)
- [Repository](https://github.com/gaato/mooncakes-graph)
- [The interactive map](https://gaato.github.io/mooncakes-graph/)

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes-graph/LICENSE).
