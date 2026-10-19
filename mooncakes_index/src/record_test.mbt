///|
test "parse an index line" {
  let line =
    #|{"deps":{"moonbit-community/js-ffi":"0.4.2"},"name":"moonbit-community/rabbita","readme":"README.md","yanked":false,"license":"Apache-2.0","version":"0.11.0","checksum":"54959b","created_at":"2026-02-11T07:20:01.468299+00:00","yanked_reason":null}
  let r = @mooncakes_index.parse_line(line)
  assert_eq(r.name, "moonbit-community/rabbita")
  assert_eq(r.version, "0.11.0")
  assert_eq(r.deps, [
    { name: "moonbit-community/js-ffi", version: Some("0.4.2"), },
  ])
  assert_eq(r.created_at, Some("2026-02-11T07:20:01.468299+00:00"))
  assert_eq(r.yanked, false)
  assert_eq(r.deprecated, None)
}

///|
test "object-form deps keep the name and an optional version" {
  let line =
    #|{"name":"a/b","version":"0.1.0","deps":{"x/io":{"version":"0.2.6","alias":"io"},"x/local":{"path":"src/language"},"x/plain":"1.0.0"}}
  let r = @mooncakes_index.parse_line(line)
  assert_eq(r.deps, [
    { name: "x/io", version: Some("0.2.6"), },
    { name: "x/local", version: None, },
    { name: "x/plain", version: Some("1.0.0"), },
  ])
  // Missing yanked and created_at.
  assert_eq(r.yanked, false)
  assert_eq(r.created_at, None)
}

///|
test "yanked and deprecated" {
  let line =
    #|{"name":"mizchi/git","version":"0.3.0","yanked":true,"deprecated":"renamed to mizchi/bit","created_at":null}
  let r = @mooncakes_index.parse_line(line)
  assert_eq(r.yanked, true)
  assert_eq(r.deprecated, Some("renamed to mizchi/bit"))
  assert_eq(r.created_at, None)
}

///|
fn parse_error(line : String) -> @mooncakes_index.ParseError? {
  try @mooncakes_index.parse_line(line) catch {
    e => Some(e)
  } noraise {
    _ => None
  }
}

///|
test "broken lines raise" {
  assert_true(parse_error("{") is Some(InvalidJson(_)))
  assert_true(parse_error("[]") is Some(InvalidJson(_)))
  assert_true(parse_error("{\"version\":\"1\"}") is Some(MissingField("name")))
  assert_true(
    parse_error("{\"name\":\"a/b\"}") is Some(MissingField("version")),
  )
}

///|
test "natural JSONL round-trips" {
  let r : @mooncakes_index.VersionRecord = {
    name: "a/b",
    version: "1.2.3",
    deps: [
      { name: "c/d", version: Some("0.1.0"), },
      { name: "e/f", version: None, },
    ],
    created_at: Some("2026-01-01T00:00:00+00:00"),
    yanked: true,
    deprecated: Some("use g/h"),
  }
  let line = r.to_json().stringify()
  assert_eq(
    line,
    (
      #|{"name":"a/b","version":"1.2.3","created_at":"2026-01-01T00:00:00+00:00","deps":{"c/d":"0.1.0","e/f":null},"yanked":true,"deprecated":"use g/h"}
    ),
  )
  assert_eq(@mooncakes_index.parse_line(line), r)
  // `deprecated` is omitted when absent; `created_at` is null.
  let plain = { ..r, created_at: None, deprecated: None, deps: [], }
  assert_eq(
    plain.to_json().stringify(),
    (
      #|{"name":"a/b","version":"1.2.3","created_at":null,"deps":{},"yanked":true}
    ),
  )
}

///|
test "owner" {
  assert_eq(@mooncakes_index.owner("moonbitlang/x").to_owned(), "moonbitlang")
  assert_eq(
    @mooncakes_index.owner("moonbit-community/rabbita/sub").to_owned(),
    "moonbit-community",
  )
  assert_eq(@mooncakes_index.owner("solo").to_owned(), "solo")
}

///|
fn v(version : String, yanked : Bool) -> @mooncakes_index.VersionRecord {
  {
    name: "a/b",
    version,
    deps: [],
    created_at: None,
    yanked,
    deprecated: None,
  }
}

///|
test "current skips yanked versions" {
  assert_eq(
    @mooncakes_index.current([
      v("0.1.0", false),
      v("0.2.0", false),
      v("0.3.0", true),
    ]).map(r => r.version),
    Some("0.2.0"),
  )
  // Every version yanked: fall back to the last one.
  assert_eq(
    @mooncakes_index.current([v("0.1.0", true), v("0.2.0", true)]).map(r => {
      r.version
    }),
    Some("0.2.0"),
  )
  assert_eq(@mooncakes_index.current([]), None)
  assert_true(@mooncakes_index.all_yanked([v("0.1.0", true), v("0.2.0", true)]))
  assert_true(
    !@mooncakes_index.all_yanked([v("0.1.0", true), v("0.2.0", false)]),
  )
  assert_true(!@mooncakes_index.all_yanked([]))
}

///|
test "compare_names is byte order" {
  let names = [
    "moonbitlang/x", "a/b", "moonbit-community/rabbita", "B/c", "a-b/c",
  ]
  names.sort_by(@mooncakes_index.compare_names)
  assert_eq(names, [
    "B/c", "a-b/c", "a/b", "moonbit-community/rabbita", "moonbitlang/x",
  ])
}
