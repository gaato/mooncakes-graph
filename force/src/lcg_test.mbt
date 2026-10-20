///|
/// Test data generator; the library's own LCG is private.
struct Lcg {
  mut state : UInt32
}

///|
fn Lcg::new(seed : UInt32) -> Lcg {
  { state: seed, }
}

///|
fn Lcg::next(self : Lcg) -> Double {
  self.state = self.state * 1664525U + 1013904223U
  self.state.to_double() / 4294967296.0
}
