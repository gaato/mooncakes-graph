///|
/// A setting given either once for every node (or link), or once per node.
///
/// ```mbt check
/// test {
///   let _ = @force.many_body(strength=All(-30))
///   let _ = @force.x(target=Each([0, 100, 200]))
/// }
/// ```
pub(all) enum Values {
  /// The same value for every node or link.
  All(Double)
  /// One value per node (or per link, for `link`), in index order.
  Each(Array[Double])
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `Values`.
pub extend Values with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `Values`, for debug output.
pub extend Values with @debug.Debug::{to_repr}

///|
/// A force that `Simulation::add_force` refused.
pub(all) suberror ForceError {
  /// An `Each` setting or a node count does not fit: `setting` names the
  /// argument (such as `"strength"` or `"radius"`).
  LengthMismatch(setting~ : String, expected~ : Int32, actual~ : Int32)
  /// A link names a node the simulation does not have.
  NodeOutOfRange(node~ : Int32, count~ : Int32)
  /// A setting is out of its range, such as a negative radius or count.
  InvalidSetting(setting~ : String, value~ : Double)
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `ForceError`.
pub extend ForceError with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `ForceError`, for debug output.
pub extend ForceError with @debug.Debug::{to_repr}

///|
/// A force, as configured. Build one with `link`, `many_body`, `center`,
/// `collide`, `x` or `y`, and install it with `Simulation::add_force`, which
/// checks it against the simulation.
enum Force {
  Link(
    edges~ : Array[(Int32, Int32)],
    distance~ : Values,
    strength~ : Values?,
    iterations~ : Int32
  )
  ManyBody(
    strength~ : Values,
    theta~ : Double,
    distance_min~ : Double,
    distance_max~ : Double
  )
  Center(x~ : Double, y~ : Double, strength~ : Double)
  Collide(radius~ : Values, strength~ : Double, iterations~ : Int32)
  Position(horizontal~ : Bool, target~ : Values, strength~ : Values)
}

///|
/// Pulls linked nodes toward `distance` apart, as d3's `forceLink`.
///
/// Without `strength`, each link gets d3's default: one over the smaller
/// degree of its two ends. `Each` settings take one value per link.
pub fn link(
  edges : Array[(Int32, Int32)],
  distance~ : Values = All(30),
  strength? : Values,
  iterations~ : Int32 = 1,
) -> Force {
  Link(
    edges=edges.copy(),
    distance=distance.copy(),
    strength=strength.map(Values::copy),
    iterations~,
  )
}

///|
/// Makes nodes repel (or, with a positive strength, attract) each other, as
/// d3's `forceManyBody`, with a Barnes–Hut approximation of accuracy `theta`.
pub fn many_body(
  strength~ : Values = All(-30),
  theta~ : Double = 0.9,
  distance_min~ : Double = 1,
  distance_max~ : Double = @double.infinity,
) -> Force {
  ManyBody(strength=strength.copy(), theta~, distance_min~, distance_max~)
}

///|
/// Moves every node together so that their mean is at (`x`, `y`), as d3's
/// `forceCenter`.
pub fn center(
  x~ : Double = 0,
  y~ : Double = 0,
  strength~ : Double = 1,
) -> Force {
  Center(x~, y~, strength~)
}

///|
/// Keeps nodes from overlapping, treating each as a circle of `radius`, as
/// d3's `forceCollide`.
pub fn collide(
  radius~ : Values = All(1),
  strength~ : Double = 1,
  iterations~ : Int32 = 1,
) -> Force {
  Collide(radius=radius.copy(), strength~, iterations~)
}

///|
/// Pulls each node toward the vertical line at `target`, as d3's `forceX`.
pub fn x(target~ : Values = All(0), strength~ : Values = All(0.1)) -> Force {
  Position(horizontal=true, target=target.copy(), strength=strength.copy())
}

///|
/// Pulls each node toward the horizontal line at `target`, as d3's `forceY`.
pub fn y(target~ : Values = All(0), strength~ : Values = All(0.1)) -> Force {
  Position(horizontal=false, target=target.copy(), strength=strength.copy())
}

///|
/// A copy that later changes to the caller's array do not reach.
fn Values::copy(self : Values) -> Values {
  match self {
    All(v) => All(v)
    Each(a) => Each(a.copy())
  }
}

///|
/// One value per item, after checking an `Each` against `count`.
fn Values::resolve(
  self : Values,
  setting : String,
  count : Int32,
) -> Array[Double] raise ForceError {
  match self {
    All(v) => Array::make(count, v)
    Each(a) => {
      guard a.length() == count else {
        raise LengthMismatch(setting~, expected=count, actual=a.length())
      }
      a
    }
  }
}

///|
/// A force ready to apply to a simulation of a given size: every setting is
/// one value per node or link.
priv enum Installed {
  Link(
    edges~ : Array[(Int32, Int32)],
    distances~ : Array[Double],
    strengths~ : Array[Double],
    bias~ : Array[Double],
    iterations~ : Int32
  )
  ManyBody(
    strengths~ : Array[Double],
    theta~ : Double,
    distance_min~ : Double,
    distance_max~ : Double
  )
  Center(x~ : Double, y~ : Double, strength~ : Double)
  Collide(radii~ : Array[Double], strength~ : Double, iterations~ : Int32)
  Position(
    horizontal~ : Bool,
    targets~ : Array[Double],
    strengths~ : Array[Double]
  )
}

///|
/// Checks `self` against a simulation of `n` nodes.
fn Force::install(self : Force, n : Int32) -> Installed raise ForceError {
  let count = fn(setting : String, value : Int32) raise ForceError {
    guard value >= 0 else {
      raise InvalidSetting(setting~, value=value.to_double())
    }
  }
  match self {
    Link(edges~, distance~, strength~, iterations~) => {
      count("iterations", iterations)
      for edge in edges {
        let (s, t) = edge
        for node in [s, t] {
          guard node >= 0 && node < n else {
            raise NodeOutOfRange(node~, count=n)
          }
        }
      }
      let degrees = Array::make(n, 0)
      for edge in edges {
        degrees[edge.0] += 1
        degrees[edge.1] += 1
      }
      let strengths = match strength {
        Some(values) => values.resolve("strength", edges.length())
        None => edges.map(e => 1.0 / degrees[e.0].min(degrees[e.1]).to_double())
      }
      Link(
        edges~,
        distances=distance.resolve("distance", edges.length()),
        strengths~,
        bias=edges.map(e => {
          degrees[e.0].to_double() / (degrees[e.0] + degrees[e.1]).to_double()
        }),
        iterations~,
      )
    }
    ManyBody(strength~, theta~, distance_min~, distance_max~) =>
      ManyBody(
        strengths=strength.resolve("strength", n),
        theta~,
        distance_min~,
        distance_max~,
      )
    Center(x~, y~, strength~) => Center(x~, y~, strength~)
    Collide(radius~, strength~, iterations~) => {
      count("iterations", iterations)
      let radii = radius.resolve("radius", n)
      for r in radii {
        guard r >= 0 else { raise InvalidSetting(setting="radius", value=r) }
      }
      Collide(radii~, strength~, iterations~)
    }
    Position(horizontal~, target~, strength~) =>
      Position(
        horizontal~,
        targets=target.resolve("target", n),
        strengths=strength.resolve("strength", n),
      )
  }
}
