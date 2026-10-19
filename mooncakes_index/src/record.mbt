///|
/// A dependency of one published version.
///
/// `version` is `None` for a local `{"path": ...}` dependency that was
/// published without a version requirement.
pub(all) struct Dep {
  name : String
  version : String?
} derive(Eq, Debug)

///|
pub extend Dep with Eq::{equal, not_equal}

///|
pub extend Dep with @debug.Debug::{to_repr}

///|
/// One line of the index: one published version of one module.
pub(all) struct VersionRecord {
  name : String
  version : String
  deps : Array[Dep]
  /// Missing on some early versions.
  created_at : String?
  yanked : Bool
  deprecated : String?
} derive(Eq, Debug)

///|
pub extend VersionRecord with Eq::{equal, not_equal}

///|
pub extend VersionRecord with @debug.Debug::{to_repr}

///|
pub(all) suberror ParseError {
  InvalidJson(String)
  MissingField(String)
} derive(Debug)

///|
pub extend ParseError with @debug.Debug::{to_repr}

///|
/// Parses one line of the index, or one line of the natural JSONL that
/// `VersionRecord::to_json` writes; the latter is a subset of the former.
///
/// Fields other than the ones in `VersionRecord` are ignored. A dependency is
/// either `"name": "version"` or an object with an optional `"version"`
/// (`{"version", "alias"}` or a local `{"path"}`).
pub fn parse_line(line : StringView) -> VersionRecord raise ParseError {
  let json = @json.parse(line) catch { e => raise InvalidJson(e.to_string()) }
  guard json is Object(obj) else { raise InvalidJson("not an object") }
  guard obj.get("name") is Some(String(name)) else {
    raise MissingField("name")
  }
  guard obj.get("version") is Some(String(version)) else {
    raise MissingField("version")
  }
  let deps = []
  if obj.get("deps") is Some(Object(map)) {
    for dep, req in map {
      let version = match req {
        String(v) => Some(v)
        Object(o) =>
          if o.get("version") is Some(String(v)) {
            Some(v)
          } else {
            None
          }
        _ => None
      }
      deps.push({ name: dep, version, })
    }
  }
  let created_at = if obj.get("created_at") is Some(String(t)) {
    Some(t)
  } else {
    None
  }
  let yanked = obj.get("yanked") is Some(True)
  let deprecated = if obj.get("deprecated") is Some(String(d)) {
    Some(d)
  } else {
    None
  }
  { name, version, deps, created_at, yanked, deprecated, }
}

///|
/// The natural JSONL shape:
/// `{"name","version","created_at","deps":{name: version|null},"yanked","deprecated"?}`.
pub impl ToJson for VersionRecord with fn to_json(self) {
  let deps : Map[String, Json] = Map([])
  for dep in self.deps {
    deps[dep.name] = match dep.version {
      Some(v) => Json::string(v)
      None => Json::null()
    }
  }
  let obj : Map[String, Json] = Map([
    ("name", Json::string(self.name)),
    ("version", Json::string(self.version)),
    (
      "created_at",
      match self.created_at {
        Some(t) => Json::string(t)
        None => Json::null()
      },
    ),
    ("deps", Json::object(deps)),
    ("yanked", Json::boolean(self.yanked)),
  ])
  if self.deprecated is Some(d) {
    obj["deprecated"] = Json::string(d)
  }
  Json::object(obj)
}

///|
/// The owner part of a module name: `"moonbitlang/x"` → `"moonbitlang"`.
pub fn owner(name : StringView) -> StringView {
  match name.find("/") {
    Some(i) => name[:i]
    None => name
  }
}

///|
/// The version that represents a module now: the last version that is not
/// yanked, or the last version when every version is yanked.
///
/// `versions` must be in publication order, which is the order of the lines
/// in the index.
pub fn current(versions : ArrayView[VersionRecord]) -> VersionRecord? {
  for i = versions.length() - 1; i >= 0; i = i - 1 {
    if !versions[i].yanked {
      return Some(versions[i])
    }
  }
  versions.last()
}

///|
/// Whether every version of a module is yanked.
pub fn all_yanked(versions : ArrayView[VersionRecord]) -> Bool {
  !versions.is_empty() && versions.iter().all(v => v.yanked)
}

///|
pub extend VersionRecord with ToJson::{to_json}

///|
/// Lexicographic order by UTF-16 code unit, which for module names (ASCII)
/// is byte order. `String::compare` orders by length first, so a sorted
/// listing would not look sorted.
pub fn compare_names(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = a.code_unit_at(i).compare(b.code_unit_at(i))
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}
