# Changelog

All notable changes to `gaato/mooncakes-graph` are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the
version is 0.x, a minor release (0.x → 0.y) may contain breaking changes; a
patch release never does. Every breaking change is listed with a migration
note.

## [Unreleased]

## [0.1.0] - 2026-10-20

### Added

- **The registry as a dependency graph.** `Graph` follows each module's
  current version, leaves out the registry's test modules, and answers what
  depends on a module and what it depends on (`reachable`), how much it is
  depended on (`metrics`: direct, transitive and other-owner dependents,
  with `ranking`), which version each dependency asks for and whether it is
  behind or yanked (`requirement`), and the trees `tree(1)` would draw
  (`forest`).
- **The `mooncakes-graph` command** (`cmd/mooncakes-graph`), runnable with
  `moonx`: `dependents` and `deps` as trees with tree's `-L`, `--noreport`
  and `-J`, `top` as TSV, `stats`, and `versions` and `modules` as JSONL. Its
  `SKILL.md` describes it for agents.
