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
moon run --target native mooncakes-graph/src/cmd/mooncakes-graph -- dependents OWNER/MODULE
```

```
owner/module
├── someone/app
│   └── someone/app-cli
└── other/tool
3 modules (index as of <when moon update last ran>)
```

| command | output |
|---|---|
| `dependents MODULE...` | What depends on MODULE, as a tree |
| `deps MODULE...` | What MODULE depends on, as a tree |
| `top [-n N] [--by direct\|transitive\|owners]` | A ranking, as TSV |
| `versions`, `modules`, `stats` | The data the site serves |

The trees take tree's `-L`, `--noreport` and `-J`. `--help` lists the rest.

## Building the site

```sh
moon update
./scripts/build-site.sh # into site/dist
./scripts/gates.sh      # checks the CLI against an independent reader and tree(1)
```

## License

Apache-2.0
