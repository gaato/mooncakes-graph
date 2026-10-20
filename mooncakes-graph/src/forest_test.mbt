///|
/// a/core <- a/util <- b/app <- c/tool, and b/app -> a/core too.
fn chain() -> @graph.Graph {
  let rec = fn(name : String, deps : Array[String]) {
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
/// Each node as `name`, `name (*)` or `name [cut]`, indented two spaces a
/// level.
fn outline(g : @graph.Graph, f : @graph.Forest) -> String {
  let out = StringBuilder()
  fn walk(n : @graph.TreeNode, depth : Int32) -> Unit {
    out.write_string("  ".repeat(depth) + g.name(n.node))
    if n.duplicate {
      out.write_string(" (*)")
    }
    if n.truncated {
      out.write_string(" [cut]")
    }
    out.write_char('\n')
    for c in n.children {
      walk(c, depth + 1)
    }
  }

  for r in f.roots {
    walk(r, 0)
  }
  out.to_string()
}

///|
test "each module is expanded once; later appearances are duplicates" {
  let g = chain()
  let f = g.forest([g.find("a/core").unwrap()], Dependents)
  assert_eq(
    outline(g, f),
    (
      #|a/core
      #|  a/util
      #|    b/app
      #|      c/tool
      #|  b/app (*)
      #|
    ),
  )
  assert_eq(f.modules, 3)
}

///|
test "max_depth cuts below it, and a cut module can still expand later" {
  let g = chain()
  let f = g.forest([g.find("a/core").unwrap()], Dependents, max_depth=1)
  assert_eq(
    outline(g, f),
    (
      #|a/core
      #|  a/util [cut]
      #|  b/app [cut]
      #|
    ),
  )
  let none = g.forest([g.find("a/core").unwrap()], Dependents, max_depth=0)
  assert_eq(outline(g, none), "a/core [cut]\n")
}

///|
test "a repeat with nothing below it is not marked" {
  let g = chain()
  let f = g.forest([g.find("b/app").unwrap()], Deps)
  assert_eq(
    outline(g, f),
    (
      #|b/app
      #|  a/core
      #|  a/util
      #|    a/core
      #|
    ),
  )
}

///|
test "several roots: a root counts as a module only when another reaches it" {
  let g = chain()
  let f = g.forest([g.find("c/tool").unwrap(), g.find("a/util").unwrap()], Deps)
  // Below c/tool: b/app, a/core, a/util. Below a/util: a/core again.
  assert_eq(f.modules, 3)
  assert_eq(f.roots.length(), 2)
  assert_true(!f.roots[1].duplicate)
}
