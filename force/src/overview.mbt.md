# gaato/force

A force-directed graph layout for MoonBit, following
[d3-force](https://github.com/d3/d3-force). Nodes are indices `0..<n` and
edges are index pairs; you bring the drawing. Runs on JS, native and wasm-gc,
and gives the same positions on all three for the same seed.

## Install

```sh
moon add gaato/force
```

## Usage

Make a simulation of `n` nodes, add forces, and tick until it cools down:

```mbt check
///|
test "lay out a path of three nodes" {
  let sim = @force.Simulation::new(3)
  sim.add_force(@force.link([(0, 1), (1, 2)]))
  sim.add_force(@force.many_body())
  sim.add_force(@force.center())
  while sim.alpha > sim.alpha_min {
    sim.tick()
  }
  // Draw node i at (sim.xs()[i], sim.ys()[i]).
  let ends = (sim.xs()[0] - sim.xs()[2], sim.ys()[0] - sim.ys()[2])
  assert_true(ends.0 * ends.0 + ends.1 * ends.1 > 0)
}
```

## Forces

| constructor | d3 equivalent |
|---|---|
| `link(edges)` | `forceLink` |
| `many_body()` | `forceManyBody` (Barnes–Hut) |
| `center()` | `forceCenter` |
| `collide()` | `forceCollide` |
| `x()`, `y()` | `forceX`, `forceY` |

Settings that d3 lets you give per node take a `Values`: `All(v)` for every
node, or `Each(array)` with one value per node (per link, for `link`).

```mbt check
///|
test "per-node settings" {
  let sim = @force.Simulation::new(3)
  sim.add_force(@force.many_body(strength=All(-30)))
  sim.add_force(@force.collide(radius=Each([4, 8, 12])))
  sim.tick(iterations=10)
}
```

Defaults and formulas match d3's: the initial spiral layout, alpha cooling,
velocity decay, and each force's defaults. `tick` does not stop by itself at
`alpha_min`; check `alpha` and stop when you like.

`add_force` checks a force against the simulation and raises `ForceError`,
installing nothing, when it does not fit: an `Each` of the wrong length, a link
to a missing node, or a negative radius.

## Differences from d3

- Nodes are indices, not mutable objects. Read positions with `xs()` and
  `ys()`, and change them with `set_position(i, x=, y=)`,
  `set_velocity(i, vx=, vy=)` and `pin`.
- No timer or events: call `tick` from your own loop.
- Forces have no names or live setters. To change one, `clear_forces` and add
  them again.

## Links

- [Changelog](https://github.com/gaato/mooncakes-graph/blob/main/force/CHANGELOG.md)
- [Repository](https://github.com/gaato/mooncakes-graph)
- [d3-force](https://github.com/d3/d3-force), the layout it follows

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/mooncakes-graph/blob/main/force/LICENSE).
