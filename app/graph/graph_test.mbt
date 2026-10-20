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
    about: @mooncakes_index.About::default(),
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

///|
test "asked versions and who is behind" {
  let dep = fn(name : String, version : String?) -> @mooncakes_index.Dep {
    { name, version, }
  }
  let r = fn(
    name : String,
    version : String,
    deps : Array[@mooncakes_index.Dep],
  ) -> @mooncakes_index.VersionRecord {
    { ..rec(name, version, []), deps, }
  }
  let g = @graph.Graph::from_records([
    r("a/core", "0.2.0", []),
    r("a/core", "0.3.0", []),
    r("a/core", "0.3.1", []),
    r("b/old", "0.1.0", [dep("a/core", Some("0.2.0"))]),
    r("b/new", "0.1.0", [dep("a/core", Some("0.3.0"))]),
    r("b/newest", "0.1.0", [dep("a/core", Some("0.3.1"))]),
    r("b/range", "0.1.0", [dep("a/core", Some("^0.2.0"))]),
    r("b/path", "0.1.0", [dep("a/core", None)]),
  ])
  let id = fn(n : String) { g.ids[n] }
  let core = id("a/core")
  assert_eq(g.history[core].map(v => v.version), ["0.2.0", "0.3.0", "0.3.1"])
  assert_eq(g.asked(id("b/old"), core), Some("0.2.0"))
  assert_eq(g.asked(id("b/path"), core), None)
  assert_eq(g.asked(core, id("b/old")), None)
  assert_true(g.behind(id("b/old"), core))
  // Same release line, only an older patch: not behind.
  assert_true(!g.behind(id("b/new"), core))
  assert_true(!g.behind(id("b/newest"), core))
  assert_true(!g.behind(id("b/range"), core))
  assert_true(!g.behind(id("b/path"), core))
}

///|
test "version_yanked" {
  let g = sample()
  let lib = g.ids["b/lib"]
  assert_true(g.version_yanked(lib, "0.2.0"))
  assert_true(!g.version_yanked(lib, "0.1.0"))
  assert_true(!g.version_yanked(lib, "9.9.9"))
}

///|
test "layers put dependencies above and dependents below" {
  // a/core <- a/util <- b/app <- c/tool, and c/tool -> a/util directly.
  let g = sample()
  let id = fn(n : String) { g.ids[n] }
  let util = id("a/util")
  let down = g.mask(["a/util", "b/app", "c/tool"])
  let up = g.mask(["a/core"])
  let layers = g.layers(util, up, down)
  assert_eq(layers[id("a/core")], -1)
  assert_eq(layers[util], 0)
  assert_eq(layers[id("b/app")], 1)
  // Longest path: c/tool sits below b/app, not beside it.
  assert_eq(layers[id("c/tool")], 2)
  assert_eq(layers[id("b/lib")], 0)
}

///|
test "layers survive a dependency cycle" {
  let g = @graph.Graph::from_records([
    rec("a/x", "0.1.0", ["a/y"]),
    rec("a/y", "0.1.0", ["a/x"]),
    rec("a/z", "0.1.0", ["a/x"]),
  ])
  let x = g.ids["a/x"]
  let all = g.mask(["a/x", "a/y", "a/z"])
  let layers = g.layers(x, all, all)
  assert_eq(layers[x], 0)
  assert_true(layers[g.ids["a/z"]] > 0)
}
