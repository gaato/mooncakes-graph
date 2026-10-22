# gaato/mooncakes_index

Reads the [mooncakes.io](https://mooncakes.io) registry index that `moon update`
keeps at `$MOON_HOME/registry/index` (default `~/.moon/registry/index`): every
published version of every module, with its dependencies, dates, yank state
and what its `moon.mod` says about it.

Unofficial; not affiliated with mooncakes.io or the MoonBit team.

## Install

```sh
moon add gaato/mooncakes_index
```

## Usage

Each line of the index is one published version. Parse the lines of a module
and ask which version stands for it now:

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

To read the whole index from disk, use the `fs` package:
`@fs.read(@fs.index_dir().unwrap())` returns every module, sorted by name.

## Packages

| Package | What it is |
|---|---|
| `gaato/mooncakes_index` | Records and versions; pure, runs on every backend |
| `gaato/mooncakes_index/fs` | Reads the index directory (native, js, wasm) |

- `parse_line` reads one line of the index into a `VersionRecord`.
- `Module::current` picks the version that stands for a module now: the last
  one not yanked, or the last one when all are yanked.
- `compare_versions` and `release_line` order semantic versions and give the
  line they stay compatible within.
- `fs.read` counts broken lines in `skipped` instead of failing, and reports
  when `moon update` last fetched.

Records are read-only; build them for tests with `VersionRecord::new`,
`Dep::new` and `About::new`, whose optional arguments let the index grow new
fields without breaking you.

## Links

- [Changelog](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes_index/CHANGELOG.md)
- [Repository](https://github.com/gaato/mooncakes-graph)

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/mooncakes-graph/blob/main/mooncakes_index/LICENSE).
