///|
fn sample_graph() -> @graph.Graph {
  let rec = fn(
    name : String,
    deps : Array[String],
  ) -> @mooncakes_index.VersionRecord {
    @mooncakes_index.VersionRecord::new(
      name,
      version="0.1.0",
      deps=deps.map(d => @mooncakes_index.Dep::new(d, version="0.1.0")),
    )
  }
  @graph.Graph::from_records([
    rec("a/core", []),
    rec("a/util", ["a/core"]),
    rec("b/app", ["a/util", "a/core"]),
    rec("c/tool", ["b/app"]),
  ])
}

///|
test "duplicates are expanded once and marked" {
  let g = sample_graph()
  let forest = g.forest([g.find("a/core").unwrap()], Dependents)
  assert_eq(forest.modules, 3)
  assert_eq(
    render_text(g, forest, Some(module_count(forest.modules))),
    (
      #|a/core
      #|├── a/util
      #|│   └── b/app
      #|│       └── c/tool
      #|└── b/app (*)
      #|
      #|3 modules
      #|
    ),
  )
}

///|
test "-L stops descending and leaves later copies expandable" {
  let g = sample_graph()
  let forest = g.forest([g.find("a/core").unwrap()], Dependents, max_depth=1)
  assert_eq(
    render_text(g, forest, None),
    (
      #|a/core
      #|├── a/util
      #|└── b/app
      #|
    ),
  )
  assert_true(forest.roots[0].children[0].truncated)
}

///|
test "deps of several roots" {
  let g = sample_graph()
  let forest = g.forest(
    [g.find("c/tool").unwrap(), g.find("a/util").unwrap()],
    Deps,
  )
  assert_eq(
    render_text(g, forest, Some(module_count(forest.modules))),
    (
      #|c/tool
      #|└── b/app
      #|    ├── a/core
      #|    └── a/util
      #|        └── a/core
      #|a/util
      #|└── a/core
      #|
      #|3 modules
      #|
    ),
  )
}

///|
test "format_time" {
  assert_eq(format_time(0L), "1970-01-01T00:00Z")
  assert_eq(format_time(1792395964L), "2026-10-19T07:46Z")
  assert_eq(format_time(951782400L), "2000-02-29T00:00Z")
}
