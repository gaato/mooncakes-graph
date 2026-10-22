///|
/// A module and every version it has published, in publication order (the
/// order of the lines in the index).
pub struct Module {
  name : String
  versions : Array[VersionRecord]
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `Module`.
pub extend Module with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `Module`, for debug output.
pub extend Module with @debug.Debug::{to_repr}

///|
/// `versions` must be in publication order.
pub fn Module::new(name : String, versions : Array[VersionRecord]) -> Module {
  { name, versions, }
}

///|
/// The version that represents the module now: the last version that is not
/// yanked, or the last version when every version is yanked. `None` only
/// when there are no versions.
///
/// ```mbt check
/// test {
///   let m = @mooncakes_index.Module::new("a/b", [
///     @mooncakes_index.VersionRecord::new("a/b", version="0.1.0"),
///     @mooncakes_index.VersionRecord::new("a/b", version="0.2.0", yanked=true),
///   ])
///   assert_eq(m.current().map(v => v.version), Some("0.1.0"))
/// }
/// ```
pub fn Module::current(self : Module) -> VersionRecord? {
  for i in self.versions.length()>..0 {
    if !self.versions[i].yanked {
      return Some(self.versions[i])
    }
  }
  self.versions.last()
}

///|
/// Whether every version of the module is yanked.
pub fn Module::all_yanked(self : Module) -> Bool {
  !self.versions.is_empty() && self.versions.iter().all(v => v.yanked)
}
