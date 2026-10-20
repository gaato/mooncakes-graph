///|
/// Owners whose modules are in the index but not on mooncakes.io (neither the
/// site nor its API knows them): the registry's own test data, `test/B` to
/// `test/G`, which only depend on each other. `Graph::new` leaves them out.
let absent_owners : Array[String] = ["test"]

///|
/// The mooncakes.io registry as a dependency graph, at the current version
/// of every module (`@mooncakes_index.Module::current`).
///
/// Nodes are numbered `0..<size()` in module-name order
/// (`@mooncakes_index.compare_names`); use `find` to get a module's node. An
/// edge from `a` to `b` means the current version of `a` depends on `b`.
/// Dependencies on modules missing from the index, and on the module itself,
/// are not edges.
///
/// ```mbt check
/// test {
///   let g = @graph.Graph::from_records([
///     @mooncakes_index.VersionRecord::new("a/core", version="0.1.0"),
///     @mooncakes_index.VersionRecord::new("b/app", version="0.1.0", deps=[
///       @mooncakes_index.Dep::new("a/core", version="0.1.0"),
///     ]),
///   ])
///   let core = g.find("a/core").unwrap()
///   assert_eq(g.dependents(core).map(n => g.name(n)), ["b/app"])
/// }
/// ```
struct Graph {
  names : Array[String]
  ids : Map[String, Int32]
  owners : Array[String]
  current : Array[@mooncakes_index.VersionRecord]
  history : Array[Array[@mooncakes_index.VersionRecord]]
  yanked : Array[Bool]
  deps : Array[Array[Int32]]
  /// Sorted, so in name order.
  dependents : Array[Array[Int32]]
  dangling : Int32
}

///|
/// Builds the graph from the modules of the index. Modules without versions
/// and the registry's test modules are left out.
pub fn Graph::new(modules : ArrayView[@mooncakes_index.Module]) -> Graph {
  let sorted = modules
    .iter()
    .filter(m => {
      !m.versions.is_empty() &&
      !absent_owners.contains(@mooncakes_index.owner(m.name).to_owned())
    })
    .collect()
  sorted.sort_by((a, b) => @mooncakes_index.compare_names(a.name, b.name))
  let names = sorted.map(m => m.name)
  let ids : Map[String, Int32] = Map([])
  for i, name in names {
    ids[name] = i
  }
  let current = sorted.map(m => m.current().unwrap())
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
    history: sorted.map(m => m.versions),
    yanked: sorted.map(m => m.all_yanked()),
    deps,
    dependents,
    dangling,
  }
}

///|
/// Builds the graph from version records in publication order per module,
/// as the CLI's `versions` writes them.
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
  Graph::new(groups.to_array().map(g => @mooncakes_index.Module::new(g.0, g.1)))
}

///|
/// The number of modules, so nodes are `0..<size()`.
pub fn Graph::size(self : Graph) -> Int32 {
  self.names.length()
}

///|
/// The node of the module named `name`, if the graph has it.
pub fn Graph::find(self : Graph, name : StringView) -> Int32? {
  self.ids.get(name.to_owned())
}

///|
pub fn Graph::name(self : Graph, node : Int32) -> String {
  self.names[node]
}

///|
/// The owner part of the module's name (`moonbitlang` in `moonbitlang/x`).
pub fn Graph::owner(self : Graph, node : Int32) -> String {
  self.owners[node]
}

///|
/// The version that stands for the module: its last version not yanked, or
/// its last version when every one is.
pub fn Graph::current(
  self : Graph,
  node : Int32,
) -> @mooncakes_index.VersionRecord {
  self.current[node]
}

///|
/// Every version of the module, in publication order.
pub fn Graph::history(
  self : Graph,
  node : Int32,
) -> ArrayView[@mooncakes_index.VersionRecord] {
  self.history[node][:]
}

///|
/// Whether every version of the module is yanked.
pub fn Graph::all_yanked(self : Graph, node : Int32) -> Bool {
  self.yanked[node]
}

///|
/// What the module's current version depends on, in the order it lists them.
pub fn Graph::deps(self : Graph, node : Int32) -> ArrayView[Int32] {
  self.deps[node][:]
}

///|
/// What depends on the module, in name order.
pub fn Graph::dependents(self : Graph, node : Int32) -> ArrayView[Int32] {
  self.dependents[node][:]
}

///|
/// One dependency of a module's current version, as it asks for it.
pub struct Requirement {
  /// The module asked for.
  name : String
  /// Its node; `None` when the index does not have it.
  node : Int32?
  /// The version asked for; `None` for a local path without a version.
  asked : String?
  /// The version asked for is from an older release line than the module's
  /// current one, so moving to it may break the dependent (`0.20.3` against
  /// `0.22.5`; not `0.22.4`). Requirements that are not plain versions
  /// (`*`, `^0.1.0`) never count.
  behind : Bool
  /// The version asked for was yanked, while the module itself still has
  /// versions that are not (a module yanked as a whole says so itself).
  yanked : Bool
} derive(Eq, Debug)

///|
pub extend Requirement with Eq::{equal, not_equal}

///|
pub extend Requirement with @debug.Debug::{to_repr}

///|
fn Graph::requirement_of(
  self : Graph,
  dep : @mooncakes_index.Dep,
) -> Requirement {
  let node = self.ids.get(dep.name)
  let (behind, yanked) = match (node, dep.version) {
    (Some(b), Some(v)) => {
      let latest = self.current[b].version
      let behind = match
        (
          @mooncakes_index.release_line(v),
          @mooncakes_index.release_line(latest),
        ) {
        (Some(lv), Some(ll)) =>
          lv != ll && @mooncakes_index.compare_versions(v, latest) < 0
        _ => false
      }
      let yanked = !self.yanked[b] &&
        self.history[b].iter().any(r => r.version == v && r.yanked)
      (behind, yanked)
    }
    _ => (false, false)
  }
  { name: dep.name, node, asked: dep.version, behind, yanked, }
}

///|
/// Every dependency of the module's current version, in the order it lists
/// them, including ones the index does not have.
pub fn Graph::requirements(self : Graph, node : Int32) -> Array[Requirement] {
  self.current[node].deps.map(d => self.requirement_of(d))
}

///|
/// How `dependent`'s current version asks for `dependency`, if it does.
///
/// ```mbt check
/// test {
///   let g = @graph.Graph::from_records([
///     @mooncakes_index.VersionRecord::new("a/core", version="0.1.0"),
///     @mooncakes_index.VersionRecord::new("a/core", version="0.2.0"),
///     @mooncakes_index.VersionRecord::new("b/app", version="0.1.0", deps=[
///       @mooncakes_index.Dep::new("a/core", version="0.1.0"),
///     ]),
///   ])
///   let r = g
///     .requirement(
///       dependent=g.find("b/app").unwrap(),
///       dependency=g.find("a/core").unwrap(),
///     )
///     .unwrap()
///   assert_eq(r.asked, Some("0.1.0"))
///   assert_true(r.behind)
/// }
/// ```
pub fn Graph::requirement(
  self : Graph,
  dependent~ : Int32,
  dependency~ : Int32,
) -> Requirement? {
  let name = self.names[dependency]
  for dep in self.current[dependent].deps {
    if dep.name == name {
      return Some(self.requirement_of(dep))
    }
  }
  None
}

///|
/// The registry at a glance.
pub struct Stats {
  modules : Int32
  /// Every published version of those modules.
  versions : Int32
  /// Modules whose current version lists any dependency.
  modules_with_deps : Int32
  /// Dependencies between modules of the graph.
  edges : Int32
  /// Dependencies on modules the index does not have.
  dangling_edges : Int32
  /// Modules whose every version is yanked.
  all_yanked : Int32
} derive(Eq, Debug)

///|
pub extend Stats with Eq::{equal, not_equal}

///|
pub extend Stats with @debug.Debug::{to_repr}

///|
pub fn Graph::stats(self : Graph) -> Stats {
  {
    modules: self.size(),
    versions: self.history.fold(init=0, (n, h) => n + h.length()),
    modules_with_deps: self.current
    .iter()
    .filter(r => !r.deps.is_empty())
    .count(),
    edges: self.deps.fold(init=0, (n, list) => n + list.length()),
    dangling_edges: self.dangling,
    all_yanked: self.yanked.iter().filter(y => y).count(),
  }
}
