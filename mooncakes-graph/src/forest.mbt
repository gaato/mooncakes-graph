///|
/// One module in a `Forest`.
pub struct TreeNode {
  node : Int32
  /// In name order. Empty for a leaf, a duplicate or a truncated node.
  children : ArrayView[TreeNode]
  /// Already expanded earlier in the forest, or an ancestor of itself.
  duplicate : Bool
  /// Has neighbours that `max_depth` cut off.
  truncated : Bool
}

///|
fn TreeNode::leaf(
  node : Int32,
  duplicate~ : Bool,
  truncated~ : Bool,
) -> TreeNode {
  { node, children: [][:], duplicate, truncated, }
}

///|
/// Trees of what depends on (or what is depended on by) some modules, laid
/// out the way tree(1) lays out directories.
pub struct Forest {
  roots : ArrayView[TreeNode]
  /// Distinct modules below the roots (a root counts only when another root
  /// reaches it).
  modules : Int32
}

///|
/// The trees from `roots` in `direction`, in pre-order. Each module is
/// expanded once, at its first appearance; later appearances, and cycles
/// back to an ancestor, are marked `duplicate`. Below `max_depth` levels a
/// node with neighbours is marked `truncated` instead of expanded; a
/// `max_depth` of zero or less truncates the roots themselves.
///
/// ```mbt check
/// test {
///   let g = @graph.Graph::from_records([
///     @mooncakes_index.VersionRecord::new("a/core", version="0.1.0"),
///     @mooncakes_index.VersionRecord::new("b/app", version="0.1.0", deps=[
///       @mooncakes_index.Dep::new("a/core", version="0.1.0"),
///     ]),
///   ])
///   let f = g.forest([g.find("a/core").unwrap()], Dependents)
///   assert_eq(f.modules, 1)
///   assert_eq(g.name(f.roots[0].children[0].node), "b/app")
/// }
/// ```
pub fn Graph::forest(
  self : Graph,
  roots : ArrayView[Int32],
  direction : Direction,
  max_depth? : Int32,
) -> Forest {
  let neighbours = fn(node : Int32) {
    let list = self.next(node, direction).copy()
    list.sort_by((a, b) => {
      @mooncakes_index.compare_names(self.names[a], self.names[b])
    })
    list
  }
  let expanded = Array::make(self.size(), false)
  let listed = Array::make(self.size(), false)
  let on_path = Array::make(self.size(), false)
  let mut modules = 0
  fn visit(node : Int32, depth : Int32) -> TreeNode {
    let next = neighbours(node)
    if next.is_empty() {
      return TreeNode::leaf(node, duplicate=false, truncated=false)
    }
    if max_depth is Some(limit) && depth >= limit {
      return TreeNode::leaf(node, duplicate=false, truncated=true)
    }
    expanded[node] = true
    on_path[node] = true
    let children = []
    for c in next {
      if !listed[c] {
        listed[c] = true
        modules += 1
      }
      if expanded[c] || on_path[c] {
        // A repeat with nothing below it reads the same either way.
        children.push(
          TreeNode::leaf(
            c,
            duplicate=!neighbours(c).is_empty(),
            truncated=false,
          ),
        )
      } else {
        children.push(visit(c, depth + 1))
      }
    }
    on_path[node] = false
    { node, children: children[:], duplicate: false, truncated: false, }
  }

  let trees = roots.iter().map(r => visit(r, 0)).collect()
  { roots: trees[:], modules, }
}
