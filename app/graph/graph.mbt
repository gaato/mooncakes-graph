///|
/// Modules the map hides by default: they are depended on by about a quarter
/// of the registry each, and pull everything into one ball.
pub let default_hubs : Array[String] = ["moonbitlang/x", "moonbitlang/async"]

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
  let seen = Array::make(self.size(), false)
  seen[id] = true
  let order = []
  let mut head = 0
  let queue = [id]
  while head < queue.length() {
    let x = queue[head]
    head += 1
    for y in self.dependents[x] {
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
