///|
fn rec(
  name : String,
  version : String,
  deps : Array[String],
  yanked~ : Bool = false,
) -> @mooncakes_index.VersionRecord {
  @mooncakes_index.VersionRecord::new(
    name,
    version~,
    deps=deps.map(d => @mooncakes_index.Dep::new(d, version="0.1.0")),
    yanked~,
  )
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
fn names(g : @graph.Graph, nodes : ArrayView[Int32]) -> Array[String] {
  nodes.map(n => g.name(n))
}

///|
fn node(g : @graph.Graph, name : String) -> Int32 {
  g.find(name).unwrap()
}

///|
test "nodes are sorted and edges follow the current version" {
  let g = sample()
  assert_eq(names(g, Array::makei(g.size(), i => i)), [
    "a/core", "a/util", "b/app", "b/lib", "c/tool", "d/old",
  ])
  assert_eq(g.current(node(g, "b/lib")).version, "0.1.0")
  assert_true(g.all_yanked(node(g, "d/old")))
  assert_true(!g.all_yanked(node(g, "b/lib")))
  // b/lib's live version has no deps; d/old is wholly yanked, so its last
  // version stands and its edge stays.
  assert_eq(names(g, g.dependents(node(g, "a/core"))), ["a/util", "d/old"])
  assert_eq(names(g, g.deps(node(g, "c/tool"))), ["b/app", "a/util"])
  assert_eq(g.owner(node(g, "c/tool")), "c")
  assert_eq(g.find("gone/missing"), None)
}

///|
test "stats" {
  let s = sample().stats()
  assert_eq(
    (
      s.modules,
      s.versions,
      s.modules_with_deps,
      s.edges,
      s.dangling_edges,
      s.all_yanked,
    ),
    (6, 7, 5, 5, 1, 1),
  )
}

///|
test "the registry's test modules are left out" {
  let g = @graph.Graph::from_records([
    rec("a/core", "0.1.0", []),
    rec("test/B", "0.1.0", ["a/core"]),
    rec("b/app", "0.1.0", ["a/core", "test/B"]),
  ])
  assert_eq(g.find("test/B"), None)
  assert_eq(names(g, g.dependents(node(g, "a/core"))), ["b/app"])
  // A dependency on one is like any dependency outside the index.
  assert_eq(g.stats().dangling_edges, 1)
}

///|
test "metrics" {
  let g = sample()
  let m = g.metrics()
  let all = fn(metric : @graph.Metric) {
    Array::makei(g.size(), i => m.get(i, metric))
  }
  // a/core: direct a/util, d/old; transitive adds b/app, c/tool.
  // a/util: b/app and c/tool, counted once though c/tool reaches it twice.
  assert_eq(all(Direct), [2, 2, 1, 0, 0, 0])
  assert_eq(all(Transitive), [4, 2, 1, 0, 0, 0])
  // Owners other than its own among direct dependents: a/core has d.
  assert_eq(all(Owners), [1, 2, 1, 0, 0, 0])
}

///|
test "ranking: most depended on first, ties in name order" {
  let g = sample()
  let m = g.metrics()
  assert_eq(names(g, m.ranking(Transitive)), [
    "a/core", "a/util", "b/app", "b/lib", "c/tool", "d/old",
  ])
  // a/core and a/util tie on direct; name order breaks it.
  assert_eq(names(g, m.ranking(Direct, among=[4, 1, 0])), [
    "a/core", "a/util", "c/tool",
  ])
}

///|
test "exclusion cuts paths through a node" {
  let g = sample()
  let util = node(g, "a/util")
  let core = node(g, "a/core")
  let hidden = fn(n : Int32) { n == util }
  let m = g.metrics(excluded=hidden)
  assert_eq(Array::makei(g.size(), i => m.get(i, Transitive)), [
    1, 0, 1, 0, 0, 0,
  ])
  assert_eq(names(g, g.reachable(core, Dependents)), [
    "a/util", "d/old", "b/app", "c/tool",
  ])
  assert_eq(names(g, g.reachable(core, Dependents, excluded=hidden)), ["d/old"])
}

///|
test "reachable dependencies" {
  let g = sample()
  let tool = node(g, "c/tool")
  // c/tool -> b/app -> a/util -> a/core, and c/tool -> a/util.
  assert_eq(names(g, g.reachable(tool, Deps)), ["b/app", "a/util", "a/core"])
  assert_eq(
    names(g, g.reachable(tool, Deps, excluded=n => n == node(g, "a/util"))),
    ["b/app"],
  )
  assert_eq(g.reachable(node(g, "a/core"), Deps), [])
}

///|
test "isolated" {
  let g = sample()
  assert_true(g.isolated(node(g, "b/lib")))
  assert_true(!g.isolated(node(g, "d/old")))
  // d/old's only neighbour is a/core; without it, d/old stands alone.
  assert_true(
    g.isolated(node(g, "d/old"), excluded=n => n == node(g, "a/core")),
  )
}

///|
test "requirements: versions asked for, who is behind, yanked versions" {
  let dep = fn(name : String, version : String?) -> @mooncakes_index.Dep {
    @mooncakes_index.Dep::new(name, version?)
  }
  let r = fn(
    name : String,
    version : String,
    deps : Array[@mooncakes_index.Dep],
    yanked : Bool,
  ) -> @mooncakes_index.VersionRecord {
    @mooncakes_index.VersionRecord::new(name, version~, deps~, yanked~)
  }
  let g = @graph.Graph::from_records([
    r("a/core", "0.2.0", [], false),
    r("a/core", "0.3.0", [], true),
    r("a/core", "0.3.1", [], false),
    r("a/gone", "0.1.0", [], true),
    r("b/old", "0.1.0", [dep("a/core", Some("0.2.0"))], false),
    r("b/new", "0.1.0", [dep("a/core", Some("0.3.0"))], false),
    r("b/newest", "0.1.0", [dep("a/core", Some("0.3.1"))], false),
    r("b/range", "0.1.0", [dep("a/core", Some("^0.2.0"))], false),
    r("b/path", "0.1.0", [dep("a/core", None)], false),
    r(
      "b/many",
      "0.1.0",
      [
        dep("a/gone", Some("0.1.0")),
        dep("x/missing", Some("1.0.0")),
        dep("b/many", Some("0.1.0")),
      ],
      false,
    ),
  ])
  let core = node(g, "a/core")
  let req = fn(dependent : String) {
    g.requirement(dependent=node(g, dependent), dependency=core).unwrap()
  }
  let old = req("b/old")
  assert_eq(
    (old.name, old.node, old.asked, old.behind, old.yanked),
    ("a/core", Some(core), Some("0.2.0"), true, false),
  )
  // Same release line, only an older patch: not behind. 0.3.0 was yanked.
  assert_true(!req("b/new").behind)
  assert_true(req("b/new").yanked)
  assert_true(!req("b/newest").behind && !req("b/newest").yanked)
  assert_true(!req("b/range").behind)
  assert_eq(req("b/path").asked, None)
  assert_eq(g.requirement(dependent=core, dependency=node(g, "b/old")), None)
  // Every dependency, in order: a wholly yanked module is not flagged per
  // version, one missing from the index has no node, and a self-dependency
  // is listed though it is not an edge.
  let many = g.requirements(node(g, "b/many"))
  assert_eq(many.map(x => x.name), ["a/gone", "x/missing", "b/many"])
  assert_true(!many[0].yanked)
  assert_eq(many[1].node, None)
  assert_eq(many[2].node, Some(node(g, "b/many")))
  assert_eq(g.deps(node(g, "b/many")).length(), 1)
}
