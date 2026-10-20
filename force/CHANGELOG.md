# Changelog

All notable changes to `gaato/force` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is
0.x, a minor release (0.x → 0.y) may contain breaking changes; a patch release
never does. Every breaking change is listed with a migration note.

## [Unreleased]

## [0.1.0] - 2026-10-20

### Added

- **A d3-force compatible layout on indexed nodes.** `Simulation` with d3's
  initial spiral, alpha cooling and velocity decay; the forces `link`,
  `many_body` (Barnes–Hut), `center`, `collide`, `x` and `y` with d3's
  defaults; per-node settings as `Values` (`All` or `Each`); and a seed, so a
  run gives the same positions on JS, native and wasm-gc.
- **`ForceError` instead of aborting.** `add_force` refuses a force that does
  not fit the simulation (an `Each` of the wrong length, a link to a missing
  node, a negative radius or iteration count) and installs nothing.
