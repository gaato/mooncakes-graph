# gaato/mooncakes_index

Read the [mooncakes.io](https://mooncakes.io) registry index that `moon update`
keeps on your machine. It holds every published version of every module, with
its dependencies, publication date, yank state and what its `moon.mod` says
about it. Use it for release reports, dependency analysis, or test fixtures that
behave like the registry. For dependency trees and rankings built on these
records, use [`gaato/mooncakes-graph`](https://mooncakes.io/docs/gaato/mooncakes-graph).

Unofficial, and not affiliated with mooncakes.io or the MoonBit team.

## Install

```sh
moon add gaato/mooncakes_index
```

## Pick the current version of a module

Each line of the index is one published version, in publication order. Parse
the lines of a module and ask which version stands for it now:

```mbt check
///|
test "the current version of a module" {
  let first =
    #|{"name":"a/core","version":"0.1.0","deps":{"moonbitlang/x":"0.4.0"},"yanked":false}
  let second =
    #|{"name":"a/core","version":"0.2.0","deps":{},"yanked":true,"yanked_reason":"broken build"}
  let versions = [
    @mooncakes_index.parse_line(first),
    @mooncakes_index.parse_line(second),
  ]
  let module_ = @mooncakes_index.Module::new("a/core", versions)
  let now = module_.current().unwrap()
  assert_eq(now.version, "0.1.0")
  assert_eq(now.deps.length(), 1)
}
```

`Module::current()` returns the last version that is not yanked, in
publication order, so a yanked 0.2.0 leaves 0.1.0 current. When every version
is yanked, it returns the last one. For an empty history, it returns `None`.
Publication order is not semantic-version order: use `compare_versions` and
`release_line` (the range a version stays compatible within) for questions
about version numbers.

## Read the index from disk

Run `moon update` first. The index lives at `$MOON_HOME/registry/index`
(by default `~/.moon/registry/index`). Import `gaato/mooncakes_index/fs`, then
`@fs.read(@fs.index_dir().unwrap())` returns every module, sorted by name.

- `skipped` counts lines that could not be parsed. They are skipped rather
  than failing the whole read.
- `fetched_at` is when `moon update` last fetched, when known.
- `read` raises `NotFound(dir~)` when there is no index, and
  `Unreadable(path~, message~)` when a file cannot be read.

## Packages

| Package | What it is | Targets |
|---|---|---|
| `gaato/mooncakes_index` | Records and versions. Pure: no I/O. | Every backend |
| `gaato/mooncakes_index/fs` | Reads the index directory | native, js, wasm |

Records are read-only. Build them for tests with `VersionRecord::new`,
`Dep::new` and `About::new`. Their optional arguments let the index gain new
fields without breaking your code.

## Links

- [`gaato/mooncakes-graph`](https://mooncakes.io/docs/gaato/mooncakes-graph):
  dependency trees and rankings over these records
- [Changelog](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes_index/CHANGELOG.md)
- [Repository](https://github.com/gaato/mooncakes-graph)

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes_index/LICENSE).
