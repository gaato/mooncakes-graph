///|
fn Simulation::apply_many_body(
  self : Simulation,
  weights : Array[Double],
  theta : Double,
  dmin : Double,
  dmax : Double,
) -> Unit {
  self.tree.rebuild(self.xs, self.ys, weights~)
  let theta2 = theta * theta
  let min2 = dmin * dmin
  let max2 = dmax * dmax
  for i in 0..<self.node_count() {
    self.tree.visit(q => {
      if q.mass == 0 {
        return true
      }
      let mut dx = q.cx - self.xs[i]
      let mut dy = q.cy - self.ys[i]
      let mut l = dx * dx + dy * dy
      let w = q.x1 - q.x0
      if theta2 > 0 && w * w / theta2 < l {
        if l < max2 {
          if dx == 0 {
            dx = self.random.jiggle()
            l += dx * dx
          }
          if dy == 0 {
            dy = self.random.jiggle()
            l += dy * dy
          }
          if l < min2 {
            l = (min2 * l).sqrt()
          }
          self.vxs[i] += dx * q.mass * self.alpha / l
          self.vys[i] += dy * q.mass * self.alpha / l
        }
        return true
      }
      if q.head < 0 || l >= max2 {
        return false
      }
      if q.head != i || self.tree.next(q.head) >= 0 {
        if dx == 0 {
          dx = self.random.jiggle()
          l += dx * dx
        }
        if dy == 0 {
          dy = self.random.jiggle()
          l += dy * dy
        }
        if l < min2 {
          l = (min2 * l).sqrt()
        }
      }
      let mut p = q.head
      while p >= 0 {
        if p != i {
          let f = weights[p] * self.alpha / l
          self.vxs[i] += dx * f
          self.vys[i] += dy * f
        }
        p = self.tree.next(p)
      }
      false
    })
  }
}
