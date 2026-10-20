///|
test "add_force rejects a force that does not fit, and installs nothing" {
  let sim = @force.Simulation::new(3)
  let rejected = fn(force : @force.Force) -> @force.ForceError? {
    sim.add_force(force) catch {
      e => return Some(e)
    }
    None
  }
  assert_eq(
    rejected(@force.many_body(strength=Each([1, 2]))),
    Some(LengthMismatch(setting="strength", expected=3, actual=2)),
  )
  assert_eq(
    rejected(@force.link([(0, 1)], distance=Each([30, 40]))),
    Some(LengthMismatch(setting="distance", expected=1, actual=2)),
  )
  assert_eq(
    rejected(@force.link([(0, 3)])),
    Some(NodeOutOfRange(node=3, count=3)),
  )
  assert_eq(
    rejected(@force.link([(-1, 0)])),
    Some(NodeOutOfRange(node=-1, count=3)),
  )
  assert_eq(
    rejected(@force.collide(radius=Each([1, -2, 1]))),
    Some(InvalidSetting(setting="radius", value=-2)),
  )
  assert_eq(
    rejected(@force.collide(iterations=-1)),
    Some(InvalidSetting(setting="iterations", value=-1)),
  )
  // Nothing was installed: ticking leaves the spiral at rest.
  let before = sim.xs().to_owned()
  sim.tick()
  assert_eq(sim.xs().to_owned(), before)
}

///|
test "a negative node count is an error" {
  let error = try @force.Simulation::new(-1) |> ignore catch {
    e => Some(e)
  } noraise {
    _ => None
  }
  assert_eq(error, Some(InvalidSetting(setting="n", value=-1)))
}

///|
test "All and Each give the same forces for the same values" {
  let uniform = @force.Simulation::new(4)
  let each = @force.Simulation::new(4)
  uniform.add_force(@force.many_body(strength=All(-30)))
  each.add_force(@force.many_body(strength=Each(Array::make(4, -30))))
  uniform.add_force(@force.x(target=All(5), strength=All(0.2)))
  each.add_force(
    @force.x(target=Each(Array::make(4, 5)), strength=Each(Array::make(4, 0.2))),
  )
  uniform.tick(iterations=10)
  each.tick(iterations=10)
  assert_eq(uniform.xs().to_owned(), each.xs().to_owned())
  assert_eq(uniform.ys().to_owned(), each.ys().to_owned())
}
