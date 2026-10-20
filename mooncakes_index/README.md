# gaato/mooncakes_index

Reads the [mooncakes.io](https://mooncakes.io) registry index that `moon update`
keeps at `$MOON_HOME/registry/index` (default `~/.moon/registry/index`): every
published version of every module, with its dependencies, dates, yank state
and what its `moon.mod` says about it.

```mbt nocheck
let index = @fs.read(@fs.index_dir().unwrap())
for m in index.modules {
  if m.current() is Some(now) {
    println("\{m.name} \{now.version}: \{now.deps.length()} deps")
  }
}
```

- `gaato/mooncakes_index` is pure and runs on every backend.
  - `parse_line` reads one line of the index into a `VersionRecord`.
  - `Module::current` picks the version that stands for a module now: the
    last one not yanked, or the last one when all are yanked.
  - `compare_versions` and `release_line` order semantic versions and give
    the line they stay compatible within.
- `gaato/mooncakes_index/fs` reads the index directory (native, js, wasm).
  `read` counts broken lines in `skipped` instead of failing, and reports when
  `moon update` last fetched.

Records are read-only; build them for tests with `VersionRecord::new`,
`Dep::new` and `About::new`, whose optional arguments let the index grow new
fields without breaking you.

## License

Apache-2.0
