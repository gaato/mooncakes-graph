// `dependents` and `deps` print trees the way tree(1) prints directories:
// the same rules, the same -L/--noreport/-J, a module where tree has a file.

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
  forest : @graph.Forest,
  report : String?,
) -> String {
  let out = StringBuilder()
  fn line(prefix : String, branch : String, node : @graph.TreeNode) -> Unit {
    out.write_string(prefix)
    out.write_string(branch)
    out.write_string(graph.name(node.node))
    if node.duplicate {
      out.write_string(" (*)")
    }
    out.write_char('\n')
  }

  fn children(prefix : String, node : @graph.TreeNode) -> Unit {
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
  forest : @graph.Forest,
  metrics : @graph.Metrics,
  report : Json?,
) -> String {
  let out = StringBuilder()
  fn node(level : Int32, n : @graph.TreeNode, last : Bool) -> Unit {
    out.write_string(" ".repeat(4 * level))
    let i = n.node
    let fields : Map[String, Json] = Map([
      ("type", Json::string("module")),
      ("name", Json::string(graph.name(i))),
      ("version", Json::string(graph.current(i).version)),
      ("owner", Json::string(graph.owner(i))),
      (
        "metrics",
        Json::object(
          Map([
            ("direct", Json::number(metrics.get(i, Direct).to_double())),
            ("transitive", Json::number(metrics.get(i, Transitive).to_double())),
            ("owners", Json::number(metrics.get(i, Owners).to_double())),
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
