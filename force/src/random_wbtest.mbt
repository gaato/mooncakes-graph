///|
test "LCG golden words exercise overflow" {
  let rng = Random::new()
  for word in [1015568748U, 1586005467U, 2165703038U, 3027450565U, 217083232U] {
    assert_eq(rng.next(), word.to_double() / 4294967296.0)
  }
}
