# gaato/mooncakes-graph

The [mooncakes.io](https://mooncakes.io) registry as a dependency graph. Find
out what depends on a MoonBit module before you change it, trace what a module
pulls in, or rank the modules the ecosystem depends on most. It is a
command-line tool that prints dependency trees like `tree(1)`, and a library.
Both read the registry index that `moon update` keeps, so they work offline.

The same data is also an [interactive map](https://gaato.github.io/mooncakes-graph/).

Unofficial, and not affiliated with mooncakes.io or the MoonBit team.

## Install

`moonx` runs the command without installing it, as below. To install it into
`~/.moon/bin`:

```sh
moon install gaato/mooncakes-graph/cmd/mooncakes-graph
```

For the library, see [Use the library](#use-the-library).

## Run

Fetch the index with `moon update`, then ask what depends on a module:

```sh
moon update
moonx gaato/mooncakes-graph/cmd/mooncakes-graph dependents moonbitlang/x
```

| Question | Command | Output |
| --- | --- | --- |
| Which modules use this one? | `dependents MODULE...` | A tree, like `tree(1)` |
| What does this module need? | `deps MODULE...` | A tree |
| Which modules have the most downstream users? | `top [-n N] [--by direct\|transitive\|owners]` | TSV |
| How large is the registry? | `stats` | JSON: counts of modules, versions and edges |
| Every version, or every module with its description | `versions`, `modules` | JSON Lines |

The trees take `tree`'s `-L` (depth), `--noreport` and `-J` (JSON). In `top`,
`--by direct` counts immediate dependents, `--by transitive` counts everything
downstream, and `--by owners` counts distinct owners of direct dependents,
leaving out the module's own owner. `--help` lists the rest.

## Use the library

```sh
moon add gaato/mooncakes-graph
moon add gaato/mooncakes_index
```

The module's name has a hyphen, so import it under an alias:

```mbt nocheck
///|
import {
  "gaato/mooncakes-graph" @graph,
  "gaato/mooncakes_index",
  "gaato/mooncakes_index/fs",
}
```

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

- `Graph` follows each module's current version: its last version that is not
  yanked. Edges describe the index as it was when you last ran `moon update`.
  Modules under the registry's `test` namespace are left out.
- `metrics` counts direct, transitive and other-owner dependents.
- `forest` builds the trees the command prints.
- `requirement` tells which version one module asks of another, and whether
  that comes from an older release line.

## Links

- [The interactive map](https://gaato.github.io/mooncakes-graph/)
- [Changelog](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes-graph/CHANGELOG.md)
- [Repository](https://github.com/gaato/mooncakes-graph)

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes-graph/LICENSE).
