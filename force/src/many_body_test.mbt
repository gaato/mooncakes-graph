///|
fn random_sim(n : Int32) -> @force.Simulation {
  let rng = @force.Random::new(seed=456U)
  let sim = @force.Simulation::new(n)
  for i in 0..<n {
    sim.set_position(i, rng.next() * 1000, rng.next() * 1000)
  }
  sim.set_alpha_decay(0)
  sim.set_velocity_decay(0)
  sim
}

///|
test "Barnes-Hut theta zero is exact; theta .9 has bounded RMS error" {
  let n = 200
  let exact = random_sim(n)
  let approx = random_sim(n)
  let weights = Array::makei(n, i => -10.0 - i.to_double() * 0.2)
  let vx = Array::make(n, 0.0)
  let vy = Array::make(n, 0.0)
  for i in 0..<n {
    for j in 0..<n {
      if i == j {
        continue
      }
      let dx = exact.xs()[j] - exact.xs()[i]
      let dy = exact.ys()[j] - exact.ys()[i]
      let l = dx * dx + dy * dy
      let denom = if l < 1 { l.sqrt() } else { l }
      vx[i] += dx * weights[j] / denom
      vy[i] += dy * weights[j] / denom
    }
  }
  exact.add_force(@force.many_body(theta=0, strengths=weights))
  approx.add_force(@force.many_body(theta=0.9, strengths=weights))
  exact.tick()
  approx.tick()
  let mut error = 0.0
  let mut energy = 0.0
  for i in 0..<n {
    assert_true((exact.vxs()[i] - vx[i]).abs() < 1.0e-9)
    assert_true((exact.vys()[i] - vy[i]).abs() < 1.0e-9)
    let dx = approx.vxs()[i] - vx[i]
    let dy = approx.vys()[i] - vy[i]
    error += dx * dx + dy * dy
    energy += vx[i] * vx[i] + vy[i] * vy[i]
  }
  // Relative vector RMS avoids unstable relative errors near equilibrium.
  // 5% is a useful layout accuracy budget at d3's default opening angle.
  assert_true((error / energy).sqrt() < 0.05)
}

///|
test "distance cutoffs and signed child-mass center" {
  let sim = @force.Simulation::new(2)
  sim.set_position(0, 0, 0)
  sim.set_position(1, 3, 4)
  sim.set_velocity_decay(0)
  sim.set_alpha_decay(0)
  sim.add_force(@force.many_body(theta=0, strength=-10, distance_min=10))
  sim.tick()
  assert_true((sim.vxs()[0] + 0.6).abs() < 1.0e-12)
  assert_true((sim.vys()[0] + 0.8).abs() < 1.0e-12)
  sim.clear_forces()
  sim.set_velocity(0, 0, 0)
  sim.set_velocity(1, 0, 0)
  sim.add_force(@force.many_body(distance_max=1))
  sim.tick()
  assert_eq(sim.vxs()[0], 0)
  assert_eq(sim.vys()[1], 0)
}
