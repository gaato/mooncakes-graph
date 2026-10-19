///|
fn rec(
  name : String,
  version : String,
  deps : Array[String],
  yanked~ : Bool = false,
) -> @mooncakes_index.VersionRecord {
  {
    name,
    version,
    deps: deps.map(d => { name: d, version: Some("0.1.0"), }),
    created_at: None,
    yanked,
    deprecated: None,
  }
}

///|
/// a/core <- a/util <- b/app <- c/tool
///        <- b/lib  (b/lib's latest is yanked; its live version has no deps)
/// a/core also depends on itself and on a module missing from the index.
fn sample() -> @graph.Graph {
  @graph.Graph::from_records([
    rec("b/app", "0.1.0", ["a/util"]),
    rec("a/core", "0.1.0", ["a/core", "gone/missing"]),
    rec("a/util", "0.1.0", ["a/core"]),
    rec("b/lib", "0.1.0", []),
    rec("b/lib", "0.2.0", ["a/core"], yanked=true),
    rec("c/tool", "0.1.0", ["b/app", "a/util"]),
    rec("d/old", "0.1.0", ["a/core"], yanked=true),
  ])
}

///|
test "nodes are sorted and edges follow the current version" {
  let g = sample()
  assert_eq(g.names, ["a/core", "a/util", "b/app", "b/lib", "c/tool", "d/old"])
  assert_eq(g.current[3].version, "0.1.0")
  assert_eq(g.yanked, [false, false, false, false, false, true])
  // b/lib's live version has no deps; d/old is wholly yanked, so its last
  // version stands and its edge stays.
  assert_eq(g.dependents[0], [1, 5])
  assert_eq(g.deps[4], [2, 1])
  assert_eq(g.dangling, 1)
  assert_eq(g.edge_count(), 5)
}

///|
test "metrics" {
  let g = sample()
  let m = g.metrics()
  // a/core: direct a/util, d/old; transitive adds b/app, c/tool.
  // a/util: b/app and c/tool, counted once though c/tool reaches it twice.
  assert_eq(m.direct, [2, 2, 1, 0, 0, 0])
  assert_eq(m.transitive, [4, 2, 1, 0, 0, 0])
  // Owners other than its own among direct dependents: a/core has d.
  assert_eq(m.owners, [1, 2, 1, 0, 0, 0])
}

///|
test "exclusion cuts paths through a node" {
  let g = sample()
  let hidden = g.mask(["a/util", "nope/unknown"])
  let m = g.metrics(excluded=hidden)
  assert_eq(m.transitive, [1, 0, 1, 0, 0, 0])
  assert_eq(g.transitive_dependents(0), [1, 5, 2, 4])
  assert_eq(g.transitive_dependents(0, excluded=hidden), [5])
}

///|
test "transitive deps" {
  let g = sample()
  // c/tool -> b/app -> a/util -> a/core, and c/tool -> a/util.
  assert_eq(g.transitive_deps(4), [2, 1, 0])
  assert_eq(g.transitive_deps(4, excluded=g.mask(["a/util"])), [2])
  assert_eq(g.transitive_deps(0), [])
}
