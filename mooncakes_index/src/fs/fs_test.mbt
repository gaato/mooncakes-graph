///|
test "a directory without user/ is NotFound" {
  let dir = "/nonexistent/mooncakes-index-test"
  let error = try @fs.read(dir) |> ignore catch {
    e => Some(e)
  } noraise {
    _ => None
  }
  assert_eq(error, Some(NotFound(dir~)))
}
