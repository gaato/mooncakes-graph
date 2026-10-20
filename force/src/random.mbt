///|
/// d3's wrapping 32-bit LCG. UInt arithmetic is modulo 2^32 on all targets.
priv struct Random {
  mut state : UInt32
}

///|
fn Random::new(seed~ : UInt32 = 1U) -> Random {
  { state: seed, }
}

///|
fn Random::next(self : Random) -> Double {
  self.state = self.state * 1664525U + 1013904223U
  self.state.to_double() / 4294967296.0
}

///|
fn Random::jiggle(self : Random) -> Double {
  (self.next() - 0.5) * 1.0e-6
}
