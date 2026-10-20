# mooncakes-graph

Which [mooncakes.io](https://mooncakes.io) modules does the MoonBit ecosystem
depend on the most? This is an interactive map of the registry's dependency
graph, and a command-line tool that prints dependency trees like `tree(1)`.

Unofficial; not affiliated with mooncakes.io or the MoonBit team.

## Web

The map is rebuilt daily from the registry index. Bigger nodes have more
modules depending on them. Click a module to see what depends on it and what
it depends on; `?m=owner/name` links straight to one.

The data behind the map is served as plain files, listed in `llms.txt`. It is
derived from mooncakes.io's registry index, and module descriptions are their
authors' own.

## CLI

```sh
moon update
moonx gaato/mooncakes-graph/cmd/mooncakes-graph dependents OWNER/MODULE
```

```
owner/module
├── someone/app
│   └── someone/app-cli
└── other/tool
3 modules (index as of <when moon update last ran>)
```

The commands and the library are described in
[`mooncakes-graph/README.md`](mooncakes-graph/README.md).

## Modules

| directory | module | |
|---|---|---|
| `mooncakes-graph/` | [`gaato/mooncakes-graph`](https://mooncakes.io/docs/gaato/mooncakes-graph) | The graph, its metrics and the CLI |
| `mooncakes_index/` | [`gaato/mooncakes_index`](https://mooncakes.io/docs/gaato/mooncakes_index) | A reader for the registry index |
| `force/` | [`gaato/force`](https://mooncakes.io/docs/gaato/force) | A force-directed layout, used by the map |
| `site/` | (not published) | The map |

## Building the site

```sh
moon update
./scripts/build-site.sh # into site/dist
./scripts/gates.sh      # checks the CLI against an independent reader and tree(1)
```

## License

Apache-2.0
