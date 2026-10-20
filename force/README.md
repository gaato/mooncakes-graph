# gaato/force

A force-directed graph layout for MoonBit, following
[d3-force](https://github.com/d3/d3-force). Nodes are indices `0..<n` and
edges are index pairs; you bring the drawing. Runs on JS, native and wasm-gc,
and gives the same positions on all three for the same seed.

```mbt
let sim = @force.Simulation::new(3, seed=1U)
sim.add_force(@force.link([(0, 1), (1, 2)]))
sim.add_force(@force.many_body())
sim.add_force(@force.center())
sim.tick(iterations=300)
let x = sim.xs()[0]
let y = sim.ys()[0]
ignore((x, y))
```

## Forces

| constructor | d3 equivalent |
|---|---|
| `link(edges)` | `forceLink` |
| `many_body()` | `forceManyBody` (Barnes–Hut) |
| `center()` | `forceCenter` |
| `collide(radii)` | `forceCollide` |
| `x()`, `y()` | `forceX`, `forceY` |

Each takes d3's settings as optional arguments (`strength`, `theta`,
`distance`, ...), with plural forms (`strengths`, `distances`, `targets`) for
per-node or per-link values.

Defaults and formulas match d3's: the initial phyllotaxis layout, alpha
cooling, velocity decay, and each force's defaults. `tick` does not stop by
itself at `alpha_min`; check `alpha` and stop when you like.

## Differences from d3

- Nodes are indices, not mutable objects. Read positions with `xs()` and
  `ys()`, and change them with `set_position`, `set_velocity` and `pin`.
- No timer or events: call `tick` from your own loop.
- Forces have no names or live setters. To change one, `clear_forces` and add
  them again.

`gaato/force/quadtree` is the quadtree behind many-body and collision, usable
on its own for hit testing: `find` returns the nearest point within a radius.

## License

Apache-2.0
