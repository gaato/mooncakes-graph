///|
// Pure IEEE-754 arithmetic avoids host-libm sin/cos differences. Range-reduce
// to [-pi, pi], then use 20 Taylor terms (truncation < 3e-30 here).
// The rounded result can differ by a few ulps from the host trigonometric API.
fn initial_sin(angle : Double) -> Double {
  let tau = 2.0 * @math.PI
  let x = angle - (angle / tau + 0.5).floor() * tau
  let mut term = x
  let mut sum = x
  for k in 1..<20 {
    term = term * -(x * x) / (2 * k * (2 * k + 1)).to_double()
    sum += term
  }
  sum
}

///|
fn initial_cos(angle : Double) -> Double {
  let tau = 2.0 * @math.PI
  let x = angle - (angle / tau + 0.5).floor() * tau
  let mut term = 1.0
  let mut sum = 1.0
  for k in 1..<20 {
    term = term * -(x * x) / ((2 * k - 1) * (2 * k)).to_double()
    sum += term
  }
  sum
}
