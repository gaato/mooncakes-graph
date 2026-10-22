///|
/// The index as read from disk.
pub struct Index {
  /// Sorted by name (`@mooncakes_index.compare_names`).
  modules : Array[@mooncakes_index.Module]
  /// Lines that could not be parsed and were skipped.
  skipped : Int32
  /// When `moon update` last moved the index (Unix seconds), if known.
  fetched_at : Int64?
}

///|
/// An index that could not be read.
pub(all) suberror IndexError {
  /// `dir` has no `user/` tree, typically because `moon update` has never
  /// run.
  NotFound(dir~ : String)
  /// A directory or file under the index could not be read.
  Unreadable(path~ : String, message~ : String)
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `IndexError`.
pub extend IndexError with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `IndexError`, for debug output.
pub extend IndexError with @debug.Debug::{to_repr}

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
pub fn read(dir : String) -> Index raise IndexError {
  if !@xfs.path_exists(dir + "/user") {
    raise NotFound(dir~)
  }
  let unreadable = fn(path : String, e : Error) -> IndexError {
    Unreadable(path~, message=e.to_string())
  }
  let modules = []
  let mut skipped = 0
  let user = dir + "/user"
  let owners = @xfs.read_dir(user) catch { e => raise unreadable(user, e) }
  for owner in sorted(owners) {
    let owner_dir = user + "/" + owner
    if !(@xfs.is_dir(owner_dir) catch { _ => false }) {
      continue
    }
    let files = @xfs.read_dir(owner_dir) catch {
      e => raise unreadable(owner_dir, e)
    }
    for file in sorted(files) {
      guard file.has_suffix(".index") else { continue }
      let path = owner_dir + "/" + file
      let text = @xfs.read_file_to_string(path) catch {
        e => raise unreadable(path, e)
      }
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
        modules.push(@mooncakes_index.Module::new(versions[0].name, versions))
      }
    }
  }
  // Sort by the module name itself, not by path: `a-b/c` and `a/b` order
  // differently as paths and as names.
  modules.sort_by((a, b) => @mooncakes_index.compare_names(a.name, b.name))
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
