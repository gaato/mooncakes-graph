///|
test "1600 nodes / 4000 links: one warm tick" (b : @bench.T) {
  let rng = @force.Random::new(seed=42U)
  let edges = Array::makei(4000, _ => {
    ((rng.next() * 1600).to_int(), (rng.next() * 1600).to_int())
  })
  let sim = @force.Simulation::new(1600)
  sim.add_force(@force.link(edges))
  sim.add_force(@force.many_body())
  sim.add_force(@force.center())
  // Repeatedly measure the same populated state, including rebuild/integration.
  let xs = sim.xs().to_owned()
  let ys = sim.ys().to_owned()
  sim.tick()
  b.bench(fn() {
    for i in 0..<1600 {
      sim.set_position(i, xs[i], ys[i])
      sim.set_velocity(i, 0, 0)
    }
    sim.set_alpha(1)
    sim.tick()
    b.keep(sim.xs()[0])
  })
}
