///|
/// The index as read from disk.
pub(all) struct Index {
  /// Grouped by module, modules sorted by name, versions in publication order.
  modules : Array[(String, Array[@mooncakes_index.VersionRecord])]
  /// Lines that could not be parsed and were skipped.
  skipped : Int32
  /// When `moon update` last moved the index (Unix seconds), if known.
  fetched_at : Int64?
}

///|
/// The index directory has no `user/` tree, typically because `moon update`
/// has never run.
pub(all) suberror NotFound {
  NotFound(String)
} derive(Debug)

///|
pub extend NotFound with @debug.Debug::{to_repr}

///|
/// `$MOON_HOME/registry/index`, with `MOON_HOME` defaulting to `$HOME/.moon`
/// as `moon` itself does.
pub fn index_dir() -> String? {
  let home = match @env.get_env_var("MOON_HOME") {
    Some(h) if !h.is_empty() => h
    _ =>
      match @env.get_env_var("HOME") {
        Some(h) if !h.is_empty() => h + "/.moon"
        _ => return None
      }
  }
  Some(home + "/registry/index")
}

///|
/// Reads `<dir>/user/<owner>/<name>.index`. Broken lines are counted in
/// `skipped` instead of failing the whole read.
pub fn read(dir : String) -> Index raise {
  if !@xfs.path_exists(dir + "/user") {
    raise NotFound(dir)
  }
  let modules = []
  let mut skipped = 0
  let user = dir + "/user"
  for owner in sorted(@xfs.read_dir(user)) {
    let owner_dir = user + "/" + owner
    if !@xfs.is_dir(owner_dir) {
      continue
    }
    for file in sorted(@xfs.read_dir(owner_dir)) {
      guard file.has_suffix(".index") else { continue }
      let text = @xfs.read_file_to_string(owner_dir + "/" + file)
      let versions = []
      for line in text.split("\n") {
        let line = line.trim()
        if line.is_empty() {
          continue
        }
        versions.push(@mooncakes_index.parse_line(line)) catch {
          _ => skipped += 1
        }
      }
      if versions.length() > 0 {
        modules.push((versions[0].name, versions))
      }
    }
  }
  // Sort by the module name itself, not by path: `a-b/c` and `a/b` order
  // differently as paths and as names.
  modules.sort_by((a, b) => @mooncakes_index.compare_names(a.0, b.0))
  { modules, skipped, fetched_at: fetched_at(dir), }
}

///|
fn sorted(names : ArrayView[String]) -> Array[String] {
  let names = names.to_owned()
  names.sort_by(@mooncakes_index.compare_names)
  names
}

///|
/// The time of the last entry in the index repository's HEAD reflog, which
/// `moon update` writes on every fetch (`reset: moving to FETCH_HEAD`).
fn fetched_at(dir : String) -> Int64? {
  let log = @xfs.read_file_to_string(dir + "/.git/logs/HEAD") catch {
    _ => return None
  }
  let lines = log.trim().split("\n").collect()
  guard lines.last() is Some(last) else { return None }
  // "<old> <new> <name> <<email>> <unix-seconds> <tz>\t<message>"
  guard last.split("\t").next() is Some(head) else { return None }
  guard head.rev_find("> ") is Some(i) else { return None }
  guard head[i + 2:].split(" ").next() is Some(secs) else { return None }
  Some(@string.parse_int64(secs)) catch {
    _ => None
  }
}
