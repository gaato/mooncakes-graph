# gaato/mooncakes_index

Reads the [mooncakes.io](https://mooncakes.io) registry index that `moon update`
keeps at `$MOON_HOME/registry/index` (default `~/.moon/registry/index`).

The index holds one JSON line per published version under
`user/<owner>/<name>.index`. This module turns those lines into
`VersionRecord { name, version, deps, created_at, yanked, deprecated, about }`,
where `about` holds the description, repository, license, keywords and yank
reason.

- `gaato/mooncakes_index` — pure, every backend
  - `parse_line` reads an index line, or a line that `VersionRecord::to_json`
    wrote.
  - `current` picks the version that represents a module now: the last
    version that is not yanked. If every version is yanked, it picks the
    last one.
  - `compare_versions` orders semantic versions, and `release_line` gives
    the line they stay compatible within (`0.22` for `0.22.5`).
  - `owner` and `compare_names` (byte order) are small helpers.
- `gaato/mooncakes_index/fs` — reads the directory (native, js, wasm)
  - `index_dir` resolves the path.
  - `read` returns every module with its versions in publication order. It
    counts broken lines instead of failing, and reports when `moon update`
    last fetched.

```moonbit nocheck
let dir = @fs.index_dir().unwrap()
let index = @fs.read(dir)
for entry in index.modules {
  let (name, versions) = entry
  let now = @mooncakes_index.current(versions).unwrap()
  println("\{name} \{now.version} \{now.deps.length()} deps")
}
```

A dependency is usually `"name": "version"`. Some versions use an object:
`{"version", "alias"}`, or a local `{"path"}` with no version, in which case
`Dep::version` is `None`.
