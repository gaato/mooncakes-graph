# mooncakes-graph

Which [mooncakes.io](https://mooncakes.io) modules does the MoonBit ecosystem
depend on the most? This repository answers that two ways:

- A web map, written in [Rabbita](https://github.com/moonbit-community/rabbita).
- A command-line tool that prints dependency trees like `tree(1)`.

Unofficial; not affiliated with mooncakes.io or the MoonBit team.

## Web

- **Node size:** how many modules depend on the module, directly or
  indirectly, scaled so that area is proportional to the count.
- **Colour:** the owner. Each of the twelve owners with the most visible
  modules gets its own colour; the rest are grey.
- **Hover and click:** hovering shows a module's neighbours. Clicking
  highlights everything that would be affected by a change to the module,
  and opens its details: the description, licence and keywords from its
  current version, its release history, and links to mooncakes.io and its
  source. The lists of what it depends on and what depends on it give the
  version asked for along each edge, marked when it is from an older release
  line (`0.20.x` against `0.22.5`).
- **Links:** `?m=owner/name` links to a module. Esc and Back return to the
  overview.
- **Toggles:**
  - `moonbitlang/x & async`: about a quarter of the registry depends on each
    of these, so they start hidden.
  - `yanked`: modules whose every version is yanked are drawn faded.
  - `unconnected`: modules with no dependency edges start hidden.

The data is the registry index as `moon update` fetches it, less the
registry's test modules (`test/*`), which are in the index but not on the
site. A daily job turns
it into `data/versions.jsonl`, and the browser computes everything else.
Descriptions and the rest come from `data/modules.jsonl`, which is fetched
when a module is first opened.

## CLI

```sh
moon run --target native app/cli -- dependents gaato/http
```

```
gaato/http
├── gaato/anthropic
├── gaato/discord
│   ├── gaato/discord-cli
│   └── gaato/discord_voice
…
11 modules (index as of 2026-10-19T07:49Z)
```

| command | output |
|---|---|
| `dependents MODULE...` | Modules that depend on MODULE, as a tree. |
| `deps MODULE...` | Modules MODULE depends on, as a tree. |
| `top [-n N] [--by direct\|transitive\|owners]` | A ranking, as TSV. |
| `versions` | Every published version, as one JSON object per line. |
| `modules` | Each module's description, repository, licence and keywords, from its current version, as one JSON object per line. |

The trees follow `tree(1)`:

- Each module is expanded once; later repeats are marked `(*)`.
- `-L N` limits the depth, and `--noreport` drops the count.
- `-J` prints tree's JSON layout, with `"type": "module"` plus `version`,
  `owner` and `metrics`.

The CLI reads `$MOON_HOME/registry/index` (default `~/.moon`). Run
`moon update` first to refresh it.

The exit status follows grep: 0 for success, 1 when a module is not found,
and 2 for a usage error or failure.

## Layout

| directory | module | contents |
|---|---|---|
| `force/` | `gaato/force` | A d3-force compatible layout with a Barnes–Hut many-body force. |
| `mooncakes_index/` | `gaato/mooncakes_index` | A reader for the registry index. |
| `app/` | `gaato/mooncakes-graph` | `graph` (the graph and its metrics), `cli`, and `web`. |

## Checks

```sh
./scripts/gates.sh      # CLI vs an independent Python reader, and vs tree(1)
./scripts/build-site.sh # builds the site into app/dist
```

## License

Apache-2.0
