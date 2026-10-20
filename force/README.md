# gaato/force

A force-directed graph layout for MoonBit, following
[d3-force](https://github.com/d3/d3-force). Nodes are indices `0..<n` and
edges are index pairs; you bring the drawing. Runs on JS, native and wasm-gc,
and gives the same positions on all three for the same seed.

```mbt check
test {
  let sim = @force.Simulation::new(3)
  sim.add_force(@force.link([(0, 1), (1, 2)]))
  sim.add_force(@force.many_body())
  sim.add_force(@force.center())
  sim.tick(iterations=300)
  let _ = (sim.xs()[0], sim.ys()[0])
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

```mbt nocheck
@force.many_body(strength=All(-30))
@force.collide(radius=Each(radii))
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

## License

Apache-2.0
