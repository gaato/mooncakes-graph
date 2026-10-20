///|
fn sample(state : Ref[UInt32]) -> Double {
  state.val = state.val * 1664525U + 1013904223U
  state.val.to_double() / 4294967296.0
}

///|
test "weighted aggregates, preorder pruning and buffer reuse" {
  let rng = Ref(42U)
  let xs = Array::makei(200, _ => sample(rng) * 1000)
  let ys = Array::makei(200, _ => sample(rng) * 1000)
  let ws = Array::makei(200, _ => 0.1 + sample(rng) * 3)
  let tree = @quadtree.build(xs, ys, weights=ws)
  let mut mass = 0.0
  let mut cx = 0.0
  let mut cy = 0.0
  for i in 0..<200 {
    mass += ws[i]
    cx += xs[i] * ws[i]
    cy += ys[i] * ws[i]
  }
  let mut visits = 0
  let mut correct = false
  tree.visit(q => {
    visits += 1
    correct = (q.mass - mass).abs() < 1.0e-9 &&
      (q.cx - cx / mass).abs() < 1.0e-9 &&
      (q.cy - cy / mass).abs() < 1.0e-9
    true
  })
  assert_eq(visits, 1)
  assert_true(correct)
  tree.rebuild([2, 2, 2], [3, 3, 3])
  tree.visit(q => {
    correct = q.mass == 3 &&
      q.cx == 2 &&
      q.cy == 3 &&
      q.head == 2 &&
      tree.next(2) == 1
    true
  })
  assert_true(correct)
  tree.rebuild([], [])
  assert_eq(tree.find(0, 0), None)
}

///|
test "nearest agrees with brute force, radius is strict" {
  let rng = Ref(100U)
  let xs = Array::makei(500, _ => sample(rng) * 200 - 100)
  let ys = Array::makei(500, _ => sample(rng) * 200 - 100)
  let tree = @quadtree.build(xs, ys)
  for _ in 0..<200 {
    let x = sample(rng) * 400 - 200
    let y = sample(rng) * 400 - 200
    let mut nearest = -1
    let mut best = 1.0e100
    for i in 0..<500 {
      let dx = xs[i] - x
      let dy = ys[i] - y
      let d = dx * dx + dy * dy
      if d < best {
        best = d
        nearest = i
      }
    }
    assert_eq(tree.find(x, y), Some(nearest))
    assert_eq(tree.find(x, y, radius=best.sqrt() + 1.0e-8), Some(nearest))
    assert_eq(tree.find(x, y, radius=(best.sqrt() - 1.0e-8).max(0)), None)
  }
  let one = @quadtree.build([0], [0])
  assert_eq(one.find(3, 4, radius=5), None)
  assert_eq(one.find(0, 0, radius=0), None)
  assert_eq(one.find(0, 0, radius=-1), None)
}

///|
test "nonfinite points, negative coordinates, zero mass and near-coincidence" {
  let tree = @quadtree.build(
    [0.0 / 0.0, -2, -2, 1.0 / 0.0],
    [0, -3, -3 + 1.0e-15, 0],
    weights=[1, 0, 0, 1],
  )
  let mut mass = 1.0
  tree.visit(q => {
    mass = q.mass
    true
  })
  assert_eq(mass, 0)
  assert_eq(tree.find(-2, -3), Some(1))
}

///|
test "all quads agree with brute aggregates; signed centers use child absolute mass" {
  let rng = Ref(112U)
  let xs = Array::makei(100, _ => sample(rng) * 500 - 250)
  let ys = Array::makei(100, _ => sample(rng) * 500 - 250)
  let ws = Array::makei(100, _ => sample(rng) + 0.1)
  let tree = @quadtree.build(xs, ys, weights=ws)
  let mut correct = true
  let mut count = 0
  tree.visit(q => {
    count += 1
    let mut mass = 0.0
    let mut cx = 0.0
    let mut cy = 0.0
    for i in 0..<100 {
      if xs[i] >= q.x0 && xs[i] < q.x1 && ys[i] >= q.y0 && ys[i] < q.y1 {
        mass += ws[i]
        cx += xs[i] * ws[i]
        cy += ys[i] * ws[i]
      }
    }
    correct = correct &&
      (q.mass - mass).abs() < 1.0e-10 &&
      (q.cx - cx / mass).abs() < 1.0e-10 &&
      (q.cy - cy / mass).abs() < 1.0e-10
    false
  })
  assert_true(correct)
  assert_true(count >= 100)
  tree.rebuild([0, 3], [0, 3], weights=[-2, 1])
  tree.visit(q => {
    correct = q.mass == -1 && q.cx == 1 && q.cy == 1
    true
  })
  assert_true(correct)
}
