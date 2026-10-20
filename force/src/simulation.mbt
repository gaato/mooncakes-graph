///|
/// Indexed structure-of-arrays state. Use setters to edit nodes; array getters
/// return read-only views. Construct a new simulation to change node count.
pub struct Simulation {
  priv xs : Array[Double]
  priv ys : Array[Double]
  priv vxs : Array[Double]
  priv vys : Array[Double]
  priv fx : Array[Double?]
  priv fy : Array[Double?]
  priv forces : Array[Installed]
  priv random : Random
  priv tree : @quadtree.Tree
  priv px : Array[Double]
  priv py : Array[Double]
  mut alpha : Double
  mut alpha_min : Double
  mut alpha_decay : Double
  mut alpha_target : Double
  mut velocity_decay : Double
}

///|
/// A simulation of `n` nodes, placed in d3's phyllotaxis spiral and at rest,
/// with no forces. `seed` fixes the small random nudges that separate
/// coincident nodes, so a run is the same on every backend.
///
/// ```mbt check
/// test {
///   let sim = @force.Simulation::new(3)
///   sim.add_force(@force.link([(0, 1), (1, 2)]))
///   sim.add_force(@force.many_body())
///   sim.tick(iterations=300)
///   inspect(sim.node_count(), content="3")
/// }
/// ```
pub fn Simulation::new(
  n : Int32,
  seed~ : UInt32 = 1,
) -> Simulation raise ForceError {
  guard n >= 0 else { raise InvalidSetting(setting="n", value=n.to_double()) }
  let angle = @math.PI * (3 - 5.0.sqrt())
  let xs = Array::makei(n, i => {
    10.0 * (0.5 + i.to_double()).sqrt() * initial_cos(i.to_double() * angle)
  })
  let ys = Array::makei(n, i => {
    10.0 * (0.5 + i.to_double()).sqrt() * initial_sin(i.to_double() * angle)
  })
  {
    xs,
    ys,
    vxs: Array::make(n, 0),
    vys: Array::make(n, 0),
    fx: Array::make(n, None),
    fy: Array::make(n, None),
    forces: [],
    random: Random::new(seed~),
    tree: @quadtree.build([], []),
    px: Array::make(n, 0),
    py: Array::make(n, 0),
    alpha: 1,
    alpha_min: 0.001,
    alpha_decay: 1 - @math.pow(0.001, 1.0 / 300),
    alpha_target: 0,
    velocity_decay: 0.4,
  }
}

///|
pub fn Simulation::node_count(self : Simulation) -> Int32 {
  self.xs.length()
}

///|
pub fn Simulation::xs(self : Simulation) -> ArrayView[Double] {
  self.xs[:]
}

///|
pub fn Simulation::ys(self : Simulation) -> ArrayView[Double] {
  self.ys[:]
}

///|
pub fn Simulation::vxs(self : Simulation) -> ArrayView[Double] {
  self.vxs[:]
}

///|
pub fn Simulation::vys(self : Simulation) -> ArrayView[Double] {
  self.vys[:]
}

///|
/// Moves node `i`, which must be below `node_count`, like an array index.
pub fn Simulation::set_position(
  self : Simulation,
  i : Int32,
  x~ : Double,
  y~ : Double,
) -> Unit {
  self.xs[i] = x
  self.ys[i] = y
}

///|
/// Sets node `i`'s velocity; `i` must be below `node_count`.
pub fn Simulation::set_velocity(
  self : Simulation,
  i : Int32,
  vx~ : Double,
  vy~ : Double,
) -> Unit {
  self.vxs[i] = vx
  self.vys[i] = vy
}

///|
/// Set either fixed coordinate; omitted axes are released. Applied at tick end.
pub fn Simulation::pin(
  self : Simulation,
  i : Int32,
  x? : Double,
  y? : Double,
) -> Unit {
  self.fx[i] = x
  self.fy[i] = y
}

///|
pub fn Simulation::set_alpha(self : Simulation, value : Double) -> Unit {
  self.alpha = value
}

///|
pub fn Simulation::set_alpha_min(self : Simulation, value : Double) -> Unit {
  self.alpha_min = value
}

///|
pub fn Simulation::set_alpha_decay(self : Simulation, value : Double) -> Unit {
  self.alpha_decay = value
}

///|
pub fn Simulation::set_alpha_target(self : Simulation, value : Double) -> Unit {
  self.alpha_target = value
}

///|
pub fn Simulation::set_velocity_decay(
  self : Simulation,
  value : Double,
) -> Unit {
  self.velocity_decay = value
}

///|
/// Installs `force` after the ones already installed; `tick` applies them in
/// that order. Raises, installing nothing, when the force does not fit this
/// simulation: an `Each` of the wrong length, a link to a missing node, or a
/// negative radius or iteration count.
pub fn Simulation::add_force(
  self : Simulation,
  force : Force,
) -> Unit raise ForceError {
  self.forces.push(force.install(self.node_count()))
}

///|
pub fn Simulation::clear_forces(self : Simulation) -> Unit {
  self.forces.clear()
}

///|
/// Manual d3 tick: cool, apply ordered forces, damp velocities, integrate/pin.
/// alpha_min is a stopping threshold for callers, not a clamp in tick.
pub fn Simulation::tick(self : Simulation, iterations~ : Int32 = 1) -> Unit {
  for _ in 0..<iterations {
    self.alpha += (self.alpha_target - self.alpha) * self.alpha_decay
    for force in self.forces {
      match force {
        Link(edges~, distances~, strengths~, bias~, iterations~) =>
          self.apply_link(edges, distances, strengths, bias, iterations)
        ManyBody(strengths~, theta~, distance_min~, distance_max~) =>
          self.apply_many_body(strengths, theta, distance_min, distance_max)
        Center(x~, y~, strength~) => self.apply_center(x, y, strength)
        Collide(radii~, strength~, iterations~) =>
          self.apply_collide(radii, strength, iterations)
        Position(horizontal~, targets~, strengths~) =>
          self.apply_position(horizontal, targets, strengths)
      }
    }
    for i in 0..<self.node_count() {
      match self.fx[i] {
        Some(x) => {
          self.xs[i] = x
          self.vxs[i] = 0
        }
        None => {
          self.vxs[i] *= 1 - self.velocity_decay
          self.xs[i] += self.vxs[i]
        }
      }
      match self.fy[i] {
        Some(y) => {
          self.ys[i] = y
          self.vys[i] = 0
        }
        None => {
          self.vys[i] *= 1 - self.velocity_decay
          self.ys[i] += self.vys[i]
        }
      }
    }
  }
}
