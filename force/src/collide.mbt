///|
fn Simulation::apply_collide(
  self : Simulation,
  radii : Array[Double],
  strength : Double,
  iterations : Int32,
) -> Unit {
  for _ in 0..<iterations {
    for i in 0..<self.node_count() {
      self.px[i] = self.xs[i] + self.vxs[i]
      self.py[i] = self.ys[i] + self.vys[i]
    }
    self.tree.rebuild(self.px, self.py, weights=radii)
    for i in 0..<self.node_count() {
      let ri = radii[i]
      let xi = self.xs[i] + self.vxs[i]
      let yi = self.ys[i] + self.vys[i]
      self.tree.visit(q => {
        let r = ri + q.max_weight
        if q.head >= 0 {
          // d3 tests only the head of a coincident leaf.
          let j = q.head
          if j > i {
            let mut dx = xi - self.xs[j] - self.vxs[j]
            let mut dy = yi - self.ys[j] - self.vys[j]
            let mut l = dx * dx + dy * dy
            let rj = radii[j]
            let sum = ri + rj
            if l < sum * sum {
              if dx == 0 {
                dx = self.random.jiggle()
                l += dx * dx
              }
              if dy == 0 {
                dy = self.random.jiggle()
                l += dy * dy
              }
              l = l.sqrt()
              let f = (sum - l) / l * strength
              dx *= f
              dy *= f
              let bias = rj * rj / (ri * ri + rj * rj)
              self.vxs[i] += dx * bias
              self.vys[i] += dy * bias
              self.vxs[j] -= dx * (1 - bias)
              self.vys[j] -= dy * (1 - bias)
            }
          }
          true
        } else {
          q.x0 > xi + r || q.x1 < xi - r || q.y0 > yi + r || q.y1 < yi - r
        }
      })
    }
  }
}
