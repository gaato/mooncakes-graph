///|
test "parse an index line" {
  let line =
    #|{"deps":{"moonbit-community/js-ffi":"0.4.2"},"name":"moonbit-community/rabbita","readme":"README.md","yanked":false,"license":"Apache-2.0","version":"0.11.0","checksum":"54959b","created_at":"2026-02-11T07:20:01.468299+00:00","yanked_reason":null}
  let r = @mooncakes_index.parse_line(line)
  assert_eq(r.name, "moonbit-community/rabbita")
  assert_eq(r.version, "0.11.0")
  assert_eq(r.deps, [
    @mooncakes_index.Dep::new("moonbit-community/js-ffi", version="0.4.2"),
  ])
  assert_eq(r.created_at, Some("2026-02-11T07:20:01.468299+00:00"))
  assert_eq(r.yanked, false)
  assert_eq(r.deprecated, None)
  assert_eq(r.about.license, Some("Apache-2.0"))
}

///|
test "object-form deps keep their version, import name and path" {
  let line =
    #|{"name":"a/b","version":"0.1.0","deps":{"x/io":{"version":"0.2.6","alias":"io"},"x/local":{"path":"src/language"},"x/both":{"version":"0.1.0","path":"./both"},"x/plain":"1.0.0"}}
  let r = @mooncakes_index.parse_line(line)
  assert_eq(r.deps, [
    @mooncakes_index.Dep::new("x/io", version="0.2.6", imported_as="io"),
    @mooncakes_index.Dep::new("x/local", path="src/language"),
    @mooncakes_index.Dep::new("x/both", version="0.1.0", path="./both"),
    @mooncakes_index.Dep::new("x/plain", version="1.0.0"),
  ])
  // They round-trip through the natural JSONL, in the index's shape.
  assert_eq(
    r.to_json().stringify(),
    (
      #|{"name":"a/b","version":"0.1.0","created_at":null,"deps":{"x/io":{"version":"0.2.6","alias":"io"},"x/local":{"path":"src/language"},"x/both":{"version":"0.1.0","path":"./both"},"x/plain":"1.0.0"},"yanked":false}
    ),
  )
  assert_eq(@mooncakes_index.parse_line(r.to_json().stringify()), r)
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
  assert_true(parse_error("{") is Some(InvalidJson(..)))
  assert_true(parse_error("[]") is Some(InvalidJson(..)))
  assert_eq(
    parse_error("{\"version\":\"1\"}"),
    Some(MissingField(field="name")),
  )
  assert_eq(
    parse_error("{\"name\":\"a/b\"}"),
    Some(MissingField(field="version")),
  )
}

///|
test "natural JSONL round-trips" {
  let r = @mooncakes_index.VersionRecord::new(
    "a/b",
    version="1.2.3",
    deps=[
      @mooncakes_index.Dep::new("c/d", version="0.1.0"),
      @mooncakes_index.Dep::new("e/f"),
    ],
    created_at="2026-01-01T00:00:00+00:00",
    yanked=true,
    deprecated="use g/h",
    about=@mooncakes_index.About::new(
      description="A thing",
      repository="https://example.com/a/b",
      license="MIT",
      keywords=["x", "y"],
      yanked_reason="broken",
    ),
  )
  let line = r.to_json().stringify()
  assert_eq(
    line,
    (
      #|{"name":"a/b","version":"1.2.3","created_at":"2026-01-01T00:00:00+00:00","deps":{"c/d":"0.1.0","e/f":null},"yanked":true,"deprecated":"use g/h","description":"A thing","repository":"https://example.com/a/b","license":"MIT","keywords":["x","y"],"yanked_reason":"broken"}
    ),
  )
  assert_eq(@mooncakes_index.parse_line(line), r)
  // `deprecated` and empty `About` fields are omitted; `created_at` is null.
  let plain = @mooncakes_index.VersionRecord::new(
    "a/b",
    version="1.2.3",
    yanked=true,
  )
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
fn m(versions : Array[(String, Bool)]) -> @mooncakes_index.Module {
  @mooncakes_index.Module::new(
    "a/b",
    versions.map(v => {
      @mooncakes_index.VersionRecord::new("a/b", version=v.0, yanked=v.1)
    }),
  )
}

///|
test "current skips yanked versions" {
  assert_eq(
    m([("0.1.0", false), ("0.2.0", false), ("0.3.0", true)])
    .current()
    .map(r => r.version),
    Some("0.2.0"),
  )
  // Every version yanked: fall back to the last one.
  assert_eq(
    m([("0.1.0", true), ("0.2.0", true)]).current().map(r => r.version),
    Some("0.2.0"),
  )
  assert_eq(m([]).current(), None)
  assert_true(m([("0.1.0", true), ("0.2.0", true)]).all_yanked())
  assert_true(!m([("0.1.0", true), ("0.2.0", false)]).all_yanked())
  assert_true(!m([]).all_yanked())
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

///|
test "about fields: blanks read as absent, non-strings are skipped" {
  let r = @mooncakes_index.parse_line(
    (
      #|{"name":"a/b","version":"1.0.0","description":"  ","repository":"","license":null,"keywords":["k","",3],"yanked_reason":null}
    ),
  )
  assert_eq(r.about, @mooncakes_index.About::new(keywords=["k"]))
}

///|
test "compare_versions" {
  let ordered = [
    "0.9.0", "0.10.0-alpha", "0.10.0-alpha.1", "0.10.0-alpha.beta", "0.10.0-beta.2",
    "0.10.0-beta.11", "0.10.0", "0.10.1", "1.0.0",
  ]
  for i in 0..<(ordered.length() - 1) {
    assert_true(
      @mooncakes_index.compare_versions(ordered[i], ordered[i + 1]) < 0,
      msg="\{ordered[i]} < \{ordered[i + 1]}",
    )
    assert_true(
      @mooncakes_index.compare_versions(ordered[i + 1], ordered[i]) > 0,
    )
  }
  assert_eq(@mooncakes_index.compare_versions("1.2.3+build", "1.2.3"), 0)
  assert_true(@mooncakes_index.compare_versions("latest", "0.1.0") > 0)
}

///|
test "release_line" {
  assert_eq(@mooncakes_index.release_line("0.22.5"), Some("0.22"))
  assert_eq(@mooncakes_index.release_line("0.22.0-rc.1"), Some("0.22"))
  assert_eq(@mooncakes_index.release_line("2.3.1"), Some("2"))
  assert_eq(@mooncakes_index.release_line("^0.1.0"), None)
}
