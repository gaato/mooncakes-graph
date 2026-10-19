# gaato/force

A deterministic force-directed layout engine for node indices `0..<n` and
integer edge pairs. No graph metadata, rendering, timers, or dependencies beyond
`moonbitlang/core`. Supports JS, native, and wasm-gc.

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

Import `"gaato/force"` in your `moon.pkg`. Positions and velocities are read-only
array views; use `set_position` / `set_velocity` to edit them. `pin(i, x=..., y=...)`
fixes either axis independently; omitted axes are released. Rebuild a simulation
to change node count. Append forces with `add_force` and remove them with
`clear_forces`. To change configuration, clear and reinstall forces. Constructors
copy configuration arrays; lengths/indices must be valid (invalid input panics).
Coordinates, weights and settings should be finite, except distance_max, which
may be infinity. Radii must be nonnegative. Do not modify tree coordinates during
traversal, or re-enter/rebuild a tree from its visit callback.

## d3-force compatibility

The numerical formulas follow [d3-force](https://github.com/d3/d3-force):

- Initial phyllotaxis radius `10 * sqrt(0.5 + i)`, angle `pi * (3 - sqrt(5))`.
- Alpha starts at 1, minimum 0.001, decay `1 - 0.001^(1/300)`, target 0;
  velocity decay 0.4. Setters expose all five parameters. `tick` cools, applies
  forces in insertion order, then damps and integrates (or pins each axis).
  It never automatically stops at alpha_min; callers decide when to stop.
- Link uses predicted positions, degree bias, distance 30, default strength
  `1 / min(source_degree, target_degree)`, and one iteration. Per-link distances
  and strengths can override defaults.
- Many-body uses strength -30, theta 0.9, distance_min 1, distance_max infinity.
  Per-node strengths override the uniform value. Barnes–Hut uses quad width and
  `width² / theta² < distance²`; theta zero traverses leaves exactly. Internal
  centers use absolute child strength, including d3's zero-mass subtree pruning.
- Center translates positions without alpha scaling or velocity changes.
  Collision uses predicted positions, squared-radius weighting and quad radius
  pruning, independently of alpha. As in d3, it tests the head of a coincident
  leaf; repeated ticks separate an initially coincident cluster.
- X/Y forces default to target 0 and strength 0.1; both allow per-node arrays.
  The seeded wrapping UInt LCG supplies every jiggle.

This is a manual indexed API, without d3's mutable node objects, accessors,
force names, event/timer system, or live force setters. Pure-arithmetic sin/cos
initialization removes host-libm backend differences; it approximates d3's initial
positions (tested within 1e-9 for 1600 nodes), rather than reproducing JavaScript
Math bits. Fifty-tick fingerprints of all position/velocity bits agree across
all three backends, including jiggle-dependent inputs.

`gaato/force/quadtree` exposes reusable `Tree::rebuild`, pre-order `visit`
(return true to prune), coincident-point chains, and `find` with a strict radius
boundary. Positive weights give ordinary mass/center of mass; signed weights
use d3's absolute-child-mass center convention. Non-finite points are ignored.
Quad views expire on rebuild. At floating-point subdivision limits, inseparable
points share a leaf.

## Validation and performance

Black-box tests compare theta zero with 200-node brute force to 1e-9. The
fixed seeded sample at theta 0.9 must have relative vector RMS error below 5%:
`sqrt(sum(|approx - exact|²) / sum(|exact|²))`. This measures total force accuracy
without unstable per-node relative error near cancellation; it is a layout
accuracy budget for that sample, not a universal Barnes–Hut error guarantee.
Tests also cover cooling, convergence, link/collision formulas, pins, ordered
forces, weighted aggregates and nearest-point queries.

The native benchmark measures a warm tick of 1600 nodes / 4000 seeded random
links with link, many-body and center forces. It includes resetting positions,
velocities and alpha to avoid measuring a cooled or expanded graph. Quads and
scratch buffers are reused; initial growth or a larger tree can allocate.

Run from the repository root (fish-compatible commands):

```fish
moon -C force test src src/quadtree --target js
moon -C force test src src/quadtree --target native
moon -C force test src src/quadtree --target wasm-gc
moon -C force check src src/quadtree --target native
moon -C force fmt src src/quadtree
moon -C force info src src/quadtree
moon -C force bench src --target native
```
