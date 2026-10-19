///|
/// Force configuration. Use the factory functions; they copy input arrays.
pub enum Force {
  Link(
    Array[(Int32, Int32)],
    Array[Double],
    Array[Double],
    Array[Double],
    Int32
  )
  ManyBody(Double, Array[Double]?, Double, Double, Double)
  Center(Double, Double, Double)
  Collide(Array[Double], Double, Int32)
  Position(Bool, Double, Double, Array[Double]?, Array[Double]?)
}

///|
/// Link defaults follow d3: distance 30, strength 1/min(degrees), degree bias.
/// Optional distances/strengths are per-edge overrides.
pub fn link(
  edges : Array[(Int32, Int32)],
  distance~ : Double = 30,
  distances? : Array[Double],
  strengths? : Array[Double],
  iterations~ : Int32 = 1,
) -> Force {
  let mut n = 0
  for (s, t) in edges {
    guard! s >= 0 && t >= 0
    n = n.max(s + 1).max(t + 1)
  }
  let degrees = Array::make(n, 0)
  for (s, t) in edges {
    degrees[s] += 1
    degrees[t] += 1
  }
  let bias = edges.map(e => {
    degrees[e.0].to_double() / (degrees[e.0] + degrees[e.1]).to_double()
  })
  let ds = match distances {
    Some(a) => {
      guard! a.length() == edges.length()
      a.copy()
    }
    None => Array::make(edges.length(), distance)
  }
  let ss = match strengths {
    Some(a) => {
      guard! a.length() == edges.length()
      a.copy()
    }
    None => edges.map(e => 1.0 / degrees[e.0].min(degrees[e.1]).to_double())
  }
  Link(edges.copy(), ds, ss, bias, iterations)
}

///|
pub fn many_body(
  strength~ : Double = -30,
  strengths? : Array[Double],
  theta~ : Double = 0.9,
  distance_min~ : Double = 1,
  distance_max~ : Double = @double.infinity,
) -> Force {
  ManyBody(
    strength,
    strengths.map(a => a.copy()),
    theta,
    distance_min,
    distance_max,
  )
}

///|
pub fn center(
  x~ : Double = 0,
  y~ : Double = 0,
  strength~ : Double = 1,
) -> Force {
  Center(x, y, strength)
}

///|
pub fn collide(
  radii : Array[Double],
  strength~ : Double = 1,
  iterations~ : Int32 = 1,
) -> Force {
  for r in radii {
    guard! r >= 0
  }
  Collide(radii.copy(), strength, iterations)
}

///|
pub fn x(
  target~ : Double = 0,
  strength~ : Double = 0.1,
  targets? : Array[Double],
  strengths? : Array[Double],
) -> Force {
  Position(
    true,
    target,
    strength,
    targets.map(a => a.copy()),
    strengths.map(a => a.copy()),
  )
}

///|
pub fn y(
  target~ : Double = 0,
  strength~ : Double = 0.1,
  targets? : Array[Double],
  strengths? : Array[Double],
) -> Force {
  Position(
    false,
    target,
    strength,
    targets.map(a => a.copy()),
    strengths.map(a => a.copy()),
  )
}
