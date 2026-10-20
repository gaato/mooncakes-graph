///|
/// Which way to follow dependencies.
pub(all) enum Direction {
  /// From a module to what depends on it.
  Dependents
  /// From a module to what it depends on.
  Deps
} derive(Eq, Debug)

///|
pub extend Direction with Eq::{equal, not_equal}

///|
pub extend Direction with @debug.Debug::{to_repr}

///|
fn Graph::next(
  self : Graph,
  node : Int32,
  direction : Direction,
) -> Array[Int32] {
  match direction {
    Dependents => self.dependents[node]
    Deps => self.deps[node]
  }
}

///|
/// Every module reached from `node` in `direction`, directly or through
/// others, nearest first; `node` itself is not included. Paths through an
/// `excluded` module are cut.
pub fn Graph::reachable(
  self : Graph,
  node : Int32,
  direction : Direction,
  excluded~ : (Int32) -> Bool = _ => false,
) -> Array[Int32] {
  let seen = Array::make(self.size(), false)
  seen[node] = true
  let order = []
  let queue = [node]
  for head = 0; head < queue.length(); head = head + 1 {
    for next in self.next(queue[head], direction) {
      if seen[next] || excluded(next) {
        continue
      }
      seen[next] = true
      order.push(next)
      queue.push(next)
    }
  }
  order
}

///|
/// Whether the module has no dependency, and no dependent, outside
/// `excluded`.
pub fn Graph::isolated(
  self : Graph,
  node : Int32,
  excluded~ : (Int32) -> Bool = _ => false,
) -> Bool {
  !self.deps[node].iter().any(n => !excluded(n)) &&
  !self.dependents[node].iter().any(n => !excluded(n))
}

///|
/// A way to count how much a module is depended on.
pub(all) enum Metric {
  /// Modules whose current version lists it.
  Direct
  /// Modules that depend on it directly or through others.
  Transitive
  /// Distinct owners, other than its own, among its direct dependents.
  Owners
} derive(Eq, Debug)

///|
pub extend Metric with Eq::{equal, not_equal}

///|
pub extend Metric with @debug.Debug::{to_repr}

///|
/// The three metrics for every module of one graph.
struct Metrics {
  graph : Graph
  direct : Array[Int32]
  transitive : Array[Int32]
  owners : Array[Int32]
}

///|
/// The metrics of every module. An `excluded` module scores zero and does
/// not count, or carry counts, as a dependent of anything else.
pub fn Graph::metrics(
  self : Graph,
  excluded~ : (Int32) -> Bool = _ => false,
) -> Metrics {
  let n = self.size()
  let direct = Array::make(n, 0)
  let transitive = Array::make(n, 0)
  let owners = Array::make(n, 0)
  // Reused across nodes: stamp[i] == t means visited while computing t.
  let stamp = Array::make(n, -1)
  let queue = Array::make(n, 0)
  for t in 0..<n {
    if excluded(t) {
      continue
    }
    let seen_owners : Set[String] = Set([])
    for d in self.dependents[t] {
      if !excluded(d) {
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
        if stamp[y] == t || excluded(y) {
          continue
        }
        stamp[y] = t
        queue[tail] = y
        tail += 1
      }
    }
    transitive[t] = tail - 1
  }
  { graph: self, direct, transitive, owners, }
}

///|
pub fn Metrics::get(self : Metrics, node : Int32, metric : Metric) -> Int32 {
  match metric {
    Direct => self.direct[node]
    Transitive => self.transitive[node]
    Owners => self.owners[node]
  }
}

///|
/// Modules from most to least depended on by `metric`, ties in name order:
/// every module, or only those `among`.
///
/// ```mbt check
/// test {
///   let g = @graph.Graph::from_records([
///     @mooncakes_index.VersionRecord::new("a/core", version="0.1.0"),
///     @mooncakes_index.VersionRecord::new("b/app", version="0.1.0", deps=[
///       @mooncakes_index.Dep::new("a/core", version="0.1.0"),
///     ]),
///   ])
///   let top = g.metrics().ranking(Transitive)
///   assert_eq(top.map(n => g.name(n)), ["a/core", "b/app"])
/// }
/// ```
pub fn Metrics::ranking(
  self : Metrics,
  metric : Metric,
  among? : ArrayView[Int32],
) -> Array[Int32] {
  let order = match among {
    Some(nodes) => nodes.to_owned()
    None => Array::makei(self.graph.size(), i => i)
  }
  order.sort_by((a, b) => {
    let c = self.get(b, metric).compare(self.get(a, metric))
    if c != 0 {
      c
    } else {
      @mooncakes_index.compare_names(self.graph.names[a], self.graph.names[b])
    }
  })
  order
}
