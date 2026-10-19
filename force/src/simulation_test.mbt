///|
fn energy(sim : @force.Simulation) -> Double {
  let mut sum = 0.0
  for i in 0..<sim.node_count() {
    sum += sim.vxs()[i] * sim.vxs()[i] + sim.vys()[i] * sim.vys()[i]
  }
  sum
}

///|
test "LCG golden words exercise overflow" {
  let rng = @force.Random::new()
  for word in [1015568748U, 1586005467U, 2165703038U, 3027450565U, 217083232U] {
    assert_eq(rng.next(), word.to_double() / 4294967296.0)
  }
}

///|
fn jiggle_sim(seed : UInt32) -> @force.Simulation {
  let sim = @force.Simulation::new(12, seed~)
  for i in 0..<12 {
    sim.set_position(i, 0, 0)
  }
  sim.add_force(@force.link(Array::makei(12, i => (i, (i + 1) % 12))))
  sim.add_force(@force.many_body())
  sim.add_force(@force.collide(Array::make(12, 2)))
  sim.add_force(@force.center())
  sim.tick(iterations=50)
  sim
}

///|
test "same seed is identical; different seed changes jiggle" {
  let a = jiggle_sim(1U)
  let b = jiggle_sim(1U)
  let c = jiggle_sim(2U)
  assert_eq(a.xs(), b.xs())
  assert_eq(a.ys(), b.ys())
  assert_true(a.xs() != c.xs())
}

///|
test "chain cools and kinetic energy decays" {
  let sim = @force.Simulation::new(20)
  sim.add_force(@force.link(Array::makei(19, i => (i, i + 1))))
  sim.add_force(@force.many_body())
  sim.tick(iterations=10)
  let early = energy(sim)
  sim.tick(iterations=290)
  assert_true(energy(sim) < early * 0.001)
  assert_true((sim.alpha - sim.alpha_min).abs() < 1.0e-14)
  sim.tick()
  assert_true(sim.alpha < sim.alpha_min)
}

///|
test "link equilibrium at 30; overrides at 60" {
  for distance in [30.0, 60.0] {
    let sim = @force.Simulation::new(2)
    sim.add_force(
      @force.link([(0, 1)], distances=[distance], strengths=[1], iterations=2),
    )
    sim.tick(iterations=300)
    let dx = sim.xs()[1] - sim.xs()[0]
    let dy = sim.ys()[1] - sim.ys()[0]
    assert_true(((dx * dx + dy * dy).sqrt() - distance).abs() < 0.001)
  }
}

///|
test "collide eliminates overlap including coincident nodes and zero radius" {
  let n = 40
  let sim = @force.Simulation::new(n)
  let radii = Array::makei(n, i => 1.0 + (i % 5).to_double())
  for i in 0..<n {
    sim.set_position(i, 0, 0)
  }
  sim.add_force(@force.collide(radii, iterations=3))
  sim.tick(iterations=300)
  for i in 0..<n {
    for j in 0..<i {
      let dx = sim.xs()[i] - sim.xs()[j]
      let dy = sim.ys()[i] - sim.ys()[j]
      assert_true((dx * dx + dy * dy).sqrt() >= radii[i] + radii[j] - 0.001)
    }
  }
  let zero = @force.Simulation::new(2)
  zero.set_position(0, 0, 0)
  zero.set_position(1, 0, 0)
  zero.add_force(@force.collide([0, 0]))
  zero.tick()
  assert_eq(energy(zero), 0)
}

///|
test "center translates mean without changing velocities; empty simulation" {
  let sim = @force.Simulation::new(30)
  sim.add_force(@force.center(x=25, y=-10))
  sim.tick()
  let mut x = 0.0
  let mut y = 0.0
  for i in 0..<30 {
    x += sim.xs()[i]
    y += sim.ys()[i]
  }
  assert_true((x / 30 - 25).abs() < 1.0e-12)
  assert_true((y / 30 + 10).abs() < 1.0e-12)
  assert_eq(energy(sim), 0)
  let empty = @force.Simulation::new(0)
  empty.add_force(@force.center())
  empty.add_force(@force.many_body())
  empty.add_force(@force.collide([]))
  empty.tick()
  assert_eq(empty.node_count(), 0)
}

///|
test "integration order, independent pins, force order and positioning" {
  let sim = @force.Simulation::new(1)
  sim.set_position(0, 10, 20)
  sim.set_velocity(0, 2, 3)
  sim.set_alpha(1)
  sim.set_alpha_target(0.5)
  sim.set_alpha_decay(0.2)
  sim.set_alpha_min(0.002)
  sim.set_velocity_decay(0.4)
  sim.add_force(@force.x(target=0))
  sim.add_force(@force.y(target=0, strengths=[0.2]))
  sim.pin(0, x=7)
  sim.tick()
  assert_eq(sim.alpha, 0.9)
  assert_eq(sim.xs()[0], 7)
  assert_eq(sim.vxs()[0], 0)
  assert_true((sim.vys()[0] + 0.36).abs() < 1.0e-12)
  sim.pin(0)
  sim.clear_forces()
  sim.set_velocity(0, 1, 0)
  sim.tick()
  assert_eq(sim.xs()[0], 7.6)
  let a = @force.Simulation::new(1)
  a.set_position(0, 10, 0)
  a.set_alpha_decay(0)
  a.set_velocity_decay(0)
  a.add_force(@force.center())
  a.add_force(@force.x())
  a.tick()
  assert_eq(a.xs()[0], 0)
  a.clear_forces()
  a.set_position(0, 10, 0)
  a.add_force(@force.x())
  a.add_force(@force.center())
  a.tick()
  assert_eq(a.xs()[0], -1)
}

///|
test "backend bitwise fingerprint (50 ticks, all forces, phyllotaxis)" {
  let sim = @force.Simulation::new(24, seed=123U)
  sim.add_force(@force.link(Array::makei(24, i => (i, (i + 1) % 24))))
  sim.add_force(@force.many_body())
  sim.add_force(@force.collide(Array::make(24, 3)))
  sim.add_force(@force.x())
  sim.add_force(@force.y())
  sim.add_force(@force.center())
  sim.tick(iterations=50)
  let mut hash = 14695981039346656037UL
  for array in [sim.xs(), sim.ys(), sim.vxs(), sim.vys()] {
    for x in array {
      hash = (hash ^ x.reinterpret_as_uint64()) * 1099511628211UL
    }
  }
  inspect(hash, content="3662101533552554226")
  let j = jiggle_sim(321U)
  let mut hash2 = 14695981039346656037UL
  for array in [j.xs(), j.ys(), j.vxs(), j.vys()] {
    for x in array {
      hash2 = (hash2 ^ x.reinterpret_as_uint64()) * 1099511628211UL
    }
  }
  inspect(hash2, content="18427409436614671806")
}

///|
test "link degree bias and default strength match one-step formulas" {
  let sim = @force.Simulation::new(3)
  sim.set_position(0, 0, 0)
  sim.set_position(1, 60, 80)
  sim.set_position(2, 120, 160)
  sim.set_alpha_decay(0)
  sim.set_velocity_decay(0)
  // Degrees 1,2,1; first edge bias 1/3, second edge bias 2/3.
  let xs = [0.0, 60, 120]
  let ys = [0.0, 80, 160]
  let vx = [0.0, 0, 0]
  let vy = [0.0, 0, 0]
  for (s, t, bias) in [(0, 1, 1.0 / 3), (1, 2, 2.0 / 3)] {
    let dx = xs[t] + vx[t] - xs[s] - vx[s]
    let dy = ys[t] + vy[t] - ys[s] - vy[s]
    let l = (dx * dx + dy * dy).sqrt()
    let f = (l - 30) / l
    vx[t] -= dx * f * bias
    vy[t] -= dy * f * bias
    vx[s] += dx * f * (1 - bias)
    vy[s] += dy * f * (1 - bias)
  }
  sim.add_force(@force.link([(0, 1), (1, 2)]))
  sim.tick()
  for i in 0..<3 {
    assert_true((sim.vxs()[i] - vx[i]).abs() < 1.0e-12)
    assert_true((sim.vys()[i] - vy[i]).abs() < 1.0e-12)
  }
}

///|
test "collision uses predicted positions and squared radius bias, independent of alpha" {
  let sim = @force.Simulation::new(2)
  sim.set_position(0, 0, 0)
  sim.set_position(1, 3, 4)
  sim.set_velocity(0, 0.6, 0.8)
  sim.set_alpha(0)
  sim.set_velocity_decay(0)
  sim.add_force(@force.collide([2, 4]))
  sim.tick()
  // Predicted separation is 4, overlap 2; displacement on small radius is 4/5.
  assert_true((sim.vxs()[0] - (0.6 - 0.6 * 2 * 0.8)).abs() < 1.0e-12)
  assert_true((sim.vys()[0] - (0.8 - 0.8 * 2 * 0.8)).abs() < 1.0e-12)
  assert_true((sim.vxs()[1] - 0.6 * 2 * 0.2).abs() < 1.0e-12)
}

///|
test "position targets arrays and force input copies" {
  let targets = [10.0, 20]
  let strengths = [0.2, 0.4]
  let force = @force.x(targets~, strengths~)
  targets[0] = 1000
  strengths[0] = 100
  let sim = @force.Simulation::new(2)
  sim.set_position(0, 0, 0)
  sim.set_position(1, 0, 0)
  sim.set_alpha_decay(0)
  sim.set_velocity_decay(0)
  sim.add_force(force)
  sim.add_force(@force.y(targets=[-10, -20], strengths=[0.2, 0.4]))
  sim.tick()
  assert_eq(sim.xs()[0], 2)
  assert_eq(sim.xs()[1], 8)
  assert_eq(sim.ys()[0], -2)
  assert_eq(sim.ys()[1], -8)
}

///|
test "phyllotaxis matches d3 within numerical tolerance" {
  let sim = @force.Simulation::new(1600)
  let angle = @math.PI * (3 - 5.0.sqrt())
  for i in 0..<1600 {
    let r = 10.0 * (0.5 + i.to_double()).sqrt()
    assert_true(
      (sim.xs()[i] - r * @math.cos(angle * i.to_double())).abs() < 1.0e-9,
    )
    assert_true(
      (sim.ys()[i] - r * @math.sin(angle * i.to_double())).abs() < 1.0e-9,
    )
    assert_eq(sim.vxs()[i], 0)
    assert_eq(sim.vys()[i], 0)
  }
}
