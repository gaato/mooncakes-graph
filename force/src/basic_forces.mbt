///|
fn Simulation::apply_link(
  self : Simulation,
  edges : Array[(Int32, Int32)],
  distances : Array[Double],
  strengths : Array[Double],
  bias : Array[Double],
  iterations : Int32,
) -> Unit {
  for _ in 0..<iterations {
    for k, edge in edges {
      let (s, t) = edge
      let mut dx = self.xs[t] + self.vxs[t] - self.xs[s] - self.vxs[s]
      let mut dy = self.ys[t] + self.vys[t] - self.ys[s] - self.vys[s]
      if dx == 0 {
        dx = self.random.jiggle()
      }
      if dy == 0 {
        dy = self.random.jiggle()
      }
      let length = (dx * dx + dy * dy).sqrt()
      let f = (length - distances[k]) / length * self.alpha * strengths[k]
      dx *= f
      dy *= f
      self.vxs[t] -= dx * bias[k]
      self.vys[t] -= dy * bias[k]
      self.vxs[s] += dx * (1 - bias[k])
      self.vys[s] += dy * (1 - bias[k])
    }
  }
}

///|
fn Simulation::apply_center(
  self : Simulation,
  x : Double,
  y : Double,
  strength : Double,
) -> Unit {
  let n = self.node_count()
  if n == 0 {
    return
  }
  let mut sx = 0.0
  let mut sy = 0.0
  for i in 0..<n {
    sx += self.xs[i]
    sy += self.ys[i]
  }
  sx = (sx / n.to_double() - x) * strength
  sy = (sy / n.to_double() - y) * strength
  for i in 0..<n {
    self.xs[i] -= sx
    self.ys[i] -= sy
  }
}

///|
fn Simulation::apply_position(
  self : Simulation,
  horizontal : Bool,
  targets : Array[Double],
  strengths : Array[Double],
) -> Unit {
  for i in 0..<self.node_count() {
    let t = targets[i]
    // A NaN target leaves that node alone on this axis.
    if !t.is_nan() {
      if horizontal {
        self.vxs[i] += (t - self.xs[i]) * strengths[i] * self.alpha
      } else {
        self.vys[i] += (t - self.ys[i]) * strengths[i] * self.alpha
      }
    }
  }
}
