///|
/// A quad view. Bounds are half-open; head is -1 for internal nodes.
/// Mass is signed. Internal centers use absolute child mass (as d3-force).
/// max_weight is the largest point weight, useful for collision pruning.
pub struct Quad {
  mut x0 : Double
  mut y0 : Double
  mut x1 : Double
  mut y1 : Double
  mut mass : Double
  mut cx : Double
  mut cy : Double
  mut max_weight : Double
  mut head : Int32
  priv children : FixedArray[Int32]
}

///|
/// Reusable flat quadtree. Coordinate arrays are borrowed until rebuild;
/// do not mutate them during visit/find. Quad views expire on rebuild.
pub struct Tree {
  priv quads : Array[Quad]
  priv mut used : Int32
  priv mut xs : Array[Double]
  priv mut ys : Array[Double]
  priv nexts : Array[Int32]
}

///|
/// Build a square, power-of-two tree. Non-finite points are ignored.
/// Weights default to one; supplied arrays must match coordinate lengths.
pub fn build(
  xs : Array[Double],
  ys : Array[Double],
  weights? : Array[Double],
) -> Tree {
  let tree = Tree::{ quads: [], used: 0, xs: [], ys: [], nexts: [], }
  tree.rebuild(xs, ys, weights?)
  tree
}

///|
fn finite(x : Double) -> Bool {
  x.abs() < @double.infinity
}

///|
fn Tree::alloc(
  self : Tree,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Int32 {
  let i = self.used
  self.used += 1
  if i == self.quads.length() {
    self.quads.push({
      x0,
      y0,
      x1,
      y1,
      mass: 0,
      cx: 0,
      cy: 0,
      max_weight: 0,
      head: -1,
      children: FixedArray::make(4, -1),
    })
  } else {
    let q = self.quads[i]
    q.x0 = x0
    q.y0 = y0
    q.x1 = x1
    q.y1 = y1
    q.mass = 0
    q.cx = 0
    q.cy = 0
    q.max_weight = 0
    q.head = -1
    for k in 0..<4 {
      q.children[k] = -1
    }
  }
  i
}

///|
fn Tree::insert(self : Tree, index : Int32, point : Int32) -> Unit {
  let q = self.quads[index]
  let xm = (q.x0 + q.x1) * 0.5
  let ym = (q.y0 + q.y1) * 0.5
  if q.head >= 0 {
    let old = q.head
    if (self.xs[old] == self.xs[point] && self.ys[old] == self.ys[point]) ||
      xm == q.x0 ||
      xm == q.x1 ||
      ym == q.y0 ||
      ym == q.y1 {
      self.nexts[point] = old
      q.head = point
      return
    }
    q.head = -1
    let mut p = old
    while p >= 0 {
      let next = self.nexts[p]
      self.nexts[p] = -1
      self.place(index, p)
      p = next
    }
  } else if q.children.iter().all(c => c < 0) {
    q.head = point
    return
  }
  self.place(index, point)
}

///|
fn Tree::place(self : Tree, index : Int32, point : Int32) -> Unit {
  let q = self.quads[index]
  let xm = (q.x0 + q.x1) * 0.5
  let ym = (q.y0 + q.y1) * 0.5
  let right = self.xs[point] >= xm
  let bottom = self.ys[point] >= ym
  let k = (if right { 1 } else { 0 }) + (if bottom { 2 } else { 0 })
  let child = if q.children[k] < 0 {
    let c = self.alloc(
      if right {
        xm
      } else {
        q.x0
      },
      if bottom {
        ym
      } else {
        q.y0
      },
      if right {
        q.x1
      } else {
        xm
      },
      if bottom {
        q.y1
      } else {
        ym
      },
    )
    q.children[k] = c
    c
  } else {
    q.children[k]
  }
  self.insert(child, point)
}

///|
/// Rebuild while retaining the quad pool and point-link buffer.
pub fn Tree::rebuild(
  self : Tree,
  xs : Array[Double],
  ys : Array[Double],
  weights? : Array[Double],
) -> Unit {
  guard! xs.length() == ys.length()
  if weights is Some(w) {
    guard! w.length() == xs.length()
  }
  self.xs = xs
  self.ys = ys
  self.used = 0
  self.nexts.clear()
  let mut xmin = @double.infinity
  let mut ymin = @double.infinity
  let mut xmax = @double.neg_infinity
  let mut ymax = @double.neg_infinity
  for i in 0..<xs.length() {
    self.nexts.push(-1)
    if finite(xs[i]) && finite(ys[i]) {
      xmin = xmin.min(xs[i])
      ymin = ymin.min(ys[i])
      xmax = xmax.max(xs[i])
      ymax = ymax.max(ys[i])
    }
  }
  if xmin == @double.infinity {
    return
  }
  let x0 = xmin.floor()
  let y0 = ymin.floor()
  let mut size = 1.0
  while x0 + size <= xmax || y0 + size <= ymax {
    size *= 2
  }
  ignore(self.alloc(x0, y0, x0 + size, y0 + size))
  for i in 0..<xs.length() {
    if finite(xs[i]) && finite(ys[i]) {
      self.insert(0, i)
    }
  }
  for i = self.used - 1; i >= 0; i = i - 1 {
    let q = self.quads[i]
    if q.head >= 0 {
      q.cx = xs[q.head]
      q.cy = ys[q.head]
      let mut p = q.head
      while p >= 0 {
        let w = match weights {
          Some(ws) => ws[p]
          None => 1.0
        }
        q.mass += w
        q.max_weight = q.max_weight.max(w)
        p = self.nexts[p]
      }
    } else {
      let mut weight = 0.0
      for c in q.children {
        if c >= 0 {
          let child = self.quads[c]
          let w = child.mass.abs()
          q.mass += child.mass
          weight += w
          q.cx += child.cx * w
          q.cy += child.cy * w
          q.max_weight = q.max_weight.max(child.max_weight)
        }
      }
      if weight > 0 {
        q.cx /= weight
        q.cy /= weight
      }
    }
  }
}

///|
/// Next coincident point, or -1. Valid for points reached through Quad.head.
pub fn Tree::next(self : Tree, point : Int32) -> Int32 {
  self.nexts[point]
}

///|
fn Tree::walk(self : Tree, i : Int32, callback : (Quad) -> Bool) -> Unit {
  let q = self.quads[i]
  if callback(q) {
    return
  }
  for c in q.children {
    if c >= 0 {
      self.walk(c, callback)
    }
  }
}

///|
/// Pre-order, quadrants NW, NE, SW, SE. Return true to prune a subtree.
pub fn Tree::visit(self : Tree, callback : (Quad) -> Bool) -> Unit {
  if self.used > 0 {
    self.walk(0, callback)
  }
}

///|
/// Nearest point strictly inside radius (default infinity); ties use tree order.
pub fn Tree::find(
  self : Tree,
  x : Double,
  y : Double,
  radius~ : Double = @double.infinity,
) -> Int32? {
  if radius < 0 || !finite(x) || !finite(y) {
    return None
  }
  let mut best = radius * radius
  let mut found = None
  self.visit(q => {
    let dx = (q.x0 - x).max(0).max(x - q.x1)
    let dy = (q.y0 - y).max(0).max(y - q.y1)
    if dx * dx + dy * dy > best {
      return true
    }
    let mut p = q.head
    while p >= 0 {
      let dx = self.xs[p] - x
      let dy = self.ys[p] - y
      let d = dx * dx + dy * dy
      if d < best {
        best = d
        found = Some(p)
      }
      p = self.nexts[p]
    }
    false
  })
  found
}
