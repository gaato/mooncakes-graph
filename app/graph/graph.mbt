///|
/// Modules the map hides by default: they are depended on by about a quarter
/// of the registry each, and pull everything into one ball.
pub let default_hubs : Array[String] = ["moonbitlang/x", "moonbitlang/async"]

///|
/// Owners whose modules are in the index but not on mooncakes.io (neither the
/// site nor its API knows them): the registry's own test data, `test/B` to
/// `test/G`, which only depend on each other.
pub let absent_owners : Array[String] = ["test"]

///|
/// The module dependency graph at the current version of every module.
///
/// Node ids are indices into `names`, which is sorted by
/// `@mooncakes_index.compare_names`. An edge `a -> b` means the current
/// version of `a` depends on `b` (see `@mooncakes_index.current`).
/// Dependencies on modules missing from the index and self-dependencies are
/// dropped; `dangling` counts the former.
pub struct Graph {
  names : Array[String]
  ids : Map[String, Int32]
  owners : Array[String]
  /// The version each node stands for.
  current : Array[@mooncakes_index.VersionRecord]
  /// Every version of each node, in publication order.
  history : Array[Array[@mooncakes_index.VersionRecord]]
  /// Every published version is yanked.
  yanked : Array[Bool]
  deps : Array[Array[Int32]]
  dependents : Array[Array[Int32]]
  dangling : Int32
}

///|
/// Builds the graph from modules grouped as the index stores them: each entry
/// is a module name and its versions in publication order.
pub fn Graph::new(
  modules : ArrayView[(String, Array[@mooncakes_index.VersionRecord])],
) -> Graph {
  let sorted = modules.to_owned()
  sorted.sort_by((a, b) => @mooncakes_index.compare_names(a.0, b.0))
  let names = sorted.map(m => m.0)
  let ids : Map[String, Int32] = Map([])
  for i, name in names {
    ids[name] = i
  }
  let current = sorted.map(m => @mooncakes_index.current(m.1).unwrap())
  let yanked = sorted.map(m => @mooncakes_index.all_yanked(m.1))
  let deps = Array::makei(names.length(), _ => [])
  let dependents = Array::makei(names.length(), _ => [])
  let mut dangling = 0
  for a, record in current {
    for dep in record.deps {
      match ids.get(dep.name) {
        Some(b) if b != a
        // Duplicate keys cannot occur in a JSON object, so no dedup needed.
        => {
          deps[a].push(b)
          dependents[b].push(a)
        }
        Some(_) => ()
        None => dangling += 1
      }
    }
  }
  for list in dependents {
    list.sort()
  }
  {
    names,
    ids,
    owners: names.map(n => @mooncakes_index.owner(n).to_owned()),
    current,
    history: sorted.map(m => m.1),
    yanked,
    deps,
    dependents,
    dangling,
  }
}

///|
/// Groups records in file order (as `versions` writes them) and builds the
/// graph. Versions of one module keep their relative order.
pub fn Graph::from_records(
  records : ArrayView[@mooncakes_index.VersionRecord],
) -> Graph {
  let groups : Map[String, Array[@mooncakes_index.VersionRecord]] = Map([])
  for record in records {
    match groups.get(record.name) {
      Some(list) => list.push(record)
      None => groups[record.name] = [record]
    }
  }
  Graph::new(groups.to_array())
}

///|
/// The version of `b` that the current version of `a` asks for, if `a`
/// depends on `b` with a version.
pub fn Graph::asked(self : Graph, a : Int32, b : Int32) -> String? {
  let name = self.names[b]
  for dep in self.current[a].deps {
    if dep.name == name {
      return dep.version
    }
  }
  None
}

///|
/// Whether `a` asks for `b` from an older release line than `b`'s current
/// version, so that moving to it may break `a` (`0.20.3` against `0.22.5`;
/// not `0.22.4`). Requirements that are not plain versions (`*`, `^0.1.0`)
/// never count.
pub fn Graph::behind(self : Graph, a : Int32, b : Int32) -> Bool {
  guard self.asked(a, b) is Some(v) else { return false }
  let latest = self.current[b].version
  match
    (@mooncakes_index.release_line(v), @mooncakes_index.release_line(latest)) {
    (Some(lv), Some(ll)) =>
      lv != ll && @mooncakes_index.compare_versions(v, latest) < 0
    _ => false
  }
}

///|
/// Whether version `v` of `b` was published and then yanked.
pub fn Graph::version_yanked(self : Graph, b : Int32, v : String) -> Bool {
  self.history[b].iter().any(r => r.version == v && r.yanked)
}

///|
pub fn Graph::size(self : Graph) -> Int32 {
  self.names.length()
}

///|
pub fn Graph::edge_count(self : Graph) -> Int32 {
  self.deps.fold(init=0, (n, list) => n + list.length())
}

///|
/// A mask with `true` for the given module names (unknown names ignored).
pub fn Graph::mask(self : Graph, names : ArrayView[String]) -> Array[Bool] {
  let mask = Array::make(self.size(), false)
  for name in names {
    if self.ids.get(name) is Some(i) {
      mask[i] = true
    }
  }
  mask
}

///|
/// Modules that depend on `id` directly or through others, in BFS order
/// (nearest first). Paths through `excluded` nodes are cut; `id` itself is
/// never included.
pub fn Graph::transitive_dependents(
  self : Graph,
  id : Int32,
  excluded? : Array[Bool],
) -> Array[Int32] {
  reach(self.dependents, id, excluded)
}

///|
/// Modules that `id` depends on directly or through others, in BFS order
/// (nearest first). Paths through `excluded` nodes are cut; `id` itself is
/// never included.
pub fn Graph::transitive_deps(
  self : Graph,
  id : Int32,
  excluded? : Array[Bool],
) -> Array[Int32] {
  reach(self.deps, id, excluded)
}

///|
fn reach(
  edges : Array[Array[Int32]],
  id : Int32,
  excluded : Array[Bool]?,
) -> Array[Int32] {
  let seen = Array::make(edges.length(), false)
  seen[id] = true
  let order = []
  let mut head = 0
  let queue = [id]
  while head < queue.length() {
    let x = queue[head]
    head += 1
    for y in edges[x] {
      if seen[y] || (excluded is Some(e) && e[y]) {
        continue
      }
      seen[y] = true
      order.push(y)
      queue.push(y)
    }
  }
  order
}

///|
/// How much each module is depended on.
pub(all) struct Metrics {
  /// Modules whose current version lists it.
  direct : Array[Int32]
  /// Modules that reach it through dependencies.
  transitive : Array[Int32]
  /// Distinct owners, other than its own, among its direct dependents.
  owners : Array[Int32]
}

///|
/// Metrics for every node. Excluded nodes get zeros and are skipped as
/// dependents and as intermediate steps.
pub fn Graph::metrics(self : Graph, excluded? : Array[Bool]) -> Metrics {
  let n = self.size()
  let is_excluded = fn(i : Int32) { excluded is Some(e) && e[i] }
  let direct = Array::make(n, 0)
  let transitive = Array::make(n, 0)
  let owners = Array::make(n, 0)
  // Reused across nodes: stamp[i] == t means visited while computing t.
  let stamp = Array::make(n, -1)
  let queue = Array::make(n, 0)
  for t in 0..<n {
    if is_excluded(t) {
      continue
    }
    let seen_owners : Set[String] = Set([])
    for d in self.dependents[t] {
      if !is_excluded(d) {
        direct[t] += 1
        if self.owners[d] != self.owners[t] {
          seen_owners.add(self.owners[d])
        }
      }
    }
    owners[t] = seen_owners.length()
    stamp[t] = t
    let mut head = 0
    let mut tail = 0
    queue[tail] = t
    tail += 1
    while head < tail {
      let x = queue[head]
      head += 1
      for y in self.dependents[x] {
        if stamp[y] == t || is_excluded(y) {
          continue
        }
        stamp[y] = t
        queue[tail] = y
        tail += 1
      }
    }
    transitive[t] = tail - 1
  }
  { direct, transitive, owners, }
}

///|
/// Layers for drawing `root` with what it depends on above it and what
/// depends on it below: `root` is 0, a module in `upstream` is minus the
/// longest dependency path from `root` down to it, and one in `downstream`
/// is the longest path up from it to `root`. So every edge between two
/// layered modules points up, from a module to something above it.
///
/// Modules in neither set get 0. A dependency cycle cannot be layered this
/// way; its modules stop growing after as many rounds as there are modules.
pub fn Graph::layers(
  self : Graph,
  root : Int32,
  upstream : Array[Bool],
  downstream : Array[Bool],
) -> Array[Int32] {
  let n = self.size()
  let down = longest_paths(n, root, downstream, i => self.dependents[i])
  let up = longest_paths(n, root, upstream, i => self.deps[i])
  Array::makei(n, i => {
    if i == root {
      0
    } else if downstream[i] && down[i] > 0 {
      down[i]
    } else if upstream[i] && up[i] > 0 {
      -up[i]
    } else {
      0
    }
  })
}

///|
/// Longest path length from `root` to each node of `allowed` along `next`,
/// by relaxing until nothing changes (at most `n` rounds); 0 when
/// unreachable.
fn longest_paths(
  n : Int32,
  root : Int32,
  allowed : Array[Bool],
  next : (Int32) -> Array[Int32],
) -> Array[Int32] {
  let depth = Array::make(n, -1)
  depth[root] = 0
  let mut frontier = [root]
  let mut rounds = 0
  while !frontier.is_empty() && rounds < n {
    let changed : Map[Int32, Bool] = Map([])
    for u in frontier {
      for v in next(u) {
        if v != root && allowed[v] && depth[v] < depth[u] + 1 {
          depth[v] = depth[u] + 1
          changed[v] = true
        }
      }
    }
    frontier = changed.keys().collect()
    rounds += 1
  }
  depth.map(d => if d < 0 { 0 } else { d })
}
