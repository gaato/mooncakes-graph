// `dependents` and `deps` print trees the way tree(1) prints directories:
// the same rules, the same -L/--noreport/-J, a module where tree has a file.

///|
enum Direction {
  Dependents
  Deps
}

///|
struct TreeNode {
  id : Int32
  children : Array[TreeNode]
  /// Expanded earlier in the output (or an ancestor): printed with `(*)`.
  duplicate : Bool
  /// Has children that -L cut off.
  truncated : Bool
}

///|
struct Forest {
  roots : Array[TreeNode]
  /// Distinct modules below the roots.
  modules : Int32
}

///|
fn neighbors(
  graph : @graph.Graph,
  direction : Direction,
  id : Int32,
) -> Array[Int32] {
  let list = match direction {
    Dependents => graph.dependents[id].copy()
    Deps => graph.deps[id].copy()
  }
  list.sort_by((a, b) => {
    @mooncakes_index.compare_names(graph.names[a], graph.names[b])
  })
  list
}

///|
/// Builds the trees. Each module is expanded once, at its first appearance
/// in pre-order; later appearances, and cycles back to an ancestor, are
/// marked duplicate. `max_depth` is tree's -L (`None` for unlimited).
fn build_forest(
  graph : @graph.Graph,
  direction : Direction,
  roots : ArrayView[Int32],
  max_depth : Int32?,
) -> Forest {
  let expanded = Array::make(graph.size(), false)
  let listed = Array::make(graph.size(), false)
  let on_path = Array::make(graph.size(), false)
  let mut modules = 0
  fn visit(id : Int32, depth : Int32) -> TreeNode {
    let next = neighbors(graph, direction, id)
    if next.is_empty() {
      return { id, children: [], duplicate: false, truncated: false, }
    }
    if max_depth is Some(limit) && depth >= limit {
      return { id, children: [], duplicate: false, truncated: true, }
    }
    expanded[id] = true
    on_path[id] = true
    let children = []
    for c in next {
      if !listed[c] {
        listed[c] = true
        modules += 1
      }
      if expanded[c] || on_path[c] {
        if neighbors(graph, direction, c).is_empty() {
          children.push({
            id: c,
            children: [],
            duplicate: false,
            truncated: false,
          })
        } else {
          children.push({
            id: c,
            children: [],
            duplicate: true,
            truncated: false,
          })
        }
      } else {
        children.push(visit(c, depth + 1))
      }
    }
    on_path[id] = false
    { id, children, duplicate: false, truncated: false, }
  }

  let trees = roots.iter().map(r => visit(r, 0)).collect()
  { roots: trees, modules, }
}

///|
fn module_count(n : Int32) -> String {
  if n == 1 {
    "1 module"
  } else {
    "\{n} modules"
  }
}

///|
fn render_text(
  graph : @graph.Graph,
  forest : Forest,
  report : String?,
) -> String {
  let out = StringBuilder()
  fn line(prefix : String, branch : String, node : TreeNode) -> Unit {
    out.write_string(prefix)
    out.write_string(branch)
    out.write_string(graph.names[node.id])
    if node.duplicate {
      out.write_string(" (*)")
    }
    out.write_char('\n')
  }

  fn children(prefix : String, node : TreeNode) -> Unit {
    let n = node.children.length()
    for k, child in node.children {
      let last = k == n - 1
      line(prefix, if last { "└── " } else { "├── " }, child)
      children(prefix + (if last { "    " } else { "│   " }), child)
    }
  }

  for root in forest.roots {
    line("", "", root)
    children("", root)
  }
  if report is Some(r) {
    out.write_char('\n')
    out.write_string(r)
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// tree's -J layout: a pretty-printed array of nodes, four spaces per level,
/// ending with a report object.
fn render_json(
  graph : @graph.Graph,
  forest : Forest,
  metrics : @graph.Metrics,
  report : Json?,
) -> String {
  let out = StringBuilder()
  fn node(level : Int32, n : TreeNode, last : Bool) -> Unit {
    out.write_string(" ".repeat(4 * level))
    let i = n.id
    let fields : Map[String, Json] = Map([
      ("type", Json::string("module")),
      ("name", Json::string(graph.names[i])),
      ("version", Json::string(graph.current[i].version)),
      ("owner", Json::string(graph.owners[i])),
      (
        "metrics",
        Json::object(
          Map([
            ("direct", Json::number(metrics.direct[i].to_double())),
            ("transitive", Json::number(metrics.transitive[i].to_double())),
            ("owners", Json::number(metrics.owners[i].to_double())),
          ]),
        ),
      ),
    ])
    if n.duplicate {
      fields["duplicate"] = Json::boolean(true)
    }
    if n.truncated {
      fields["truncated"] = Json::boolean(true)
    }
    let head = Json::object(fields).stringify()
    if n.children.is_empty() {
      out.write_string(head)
    } else {
      // Reopen the object to append "contents", keeping tree's shape.
      out.write_string(head[:head.length() - 1].to_owned())
      out.write_string(",\"contents\":[\n")
      let k = n.children.length()
      for j, c in n.children {
        node(level + 1, c, j == k - 1)
      }
      out.write_string(" ".repeat(4 * level))
      out.write_string("]}")
    }
    out.write_string(if last { "\n" } else { ",\n" })
  }

  out.write_string("[\n")
  let k = forest.roots.length()
  for j, root in forest.roots {
    node(1, root, j == k - 1 && report is None)
  }
  if report is Some(r) {
    out.write_string("    ")
    out.write_string(r.stringify())
    out.write_char('\n')
  }
  out.write_string("]\n")
  out.to_string()
}
