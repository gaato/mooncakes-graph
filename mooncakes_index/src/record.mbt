///|
/// A dependency of one published version, as its `moon.mod` declared it.
///
/// Most are `"name": "version"`. Some name a local `path` (with or without a
/// version) or import the module under another name (`alias` in the index).
pub struct Dep {
  name : String
  /// `None` for a local path dependency published without a version.
  version : String?
  /// The name the module is imported as, when not its own.
  imported_as : String?
  path : String?
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `Dep`.
pub extend Dep with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `Dep`, for debug output.
pub extend Dep with @debug.Debug::{to_repr}

///|
/// A dependency on module `name`, for tests and tools that build records;
/// the optional fields are absent when omitted.
pub fn Dep::new(
  name : String,
  version? : String,
  imported_as? : String,
  path? : String,
) -> Dep {
  { name, version, imported_as, path, }
}

///|
/// What a version says about its module, from its `moon.mod`. Every field is
/// optional in the index.
pub struct About {
  description : String?
  repository : String?
  license : String?
  keywords : Array[String]
  /// Why the version was yanked, when it was and the owner said.
  yanked_reason : String?
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `About`.
pub extend About with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `About`, for debug output.
pub extend About with @debug.Debug::{to_repr}

///|
/// What a version says about its module, for tests and tools that build
/// records; every field is absent or empty when omitted.
pub fn About::new(
  description? : String,
  repository? : String,
  license? : String,
  keywords~ : Array[String] = [],
  yanked_reason? : String,
) -> About {
  { description, repository, license, keywords, yanked_reason, }
}

///|
/// One line of the index: one published version of one module.
pub struct VersionRecord {
  name : String
  version : String
  deps : Array[Dep]
  /// Missing on some early versions.
  created_at : String?
  yanked : Bool
  deprecated : String?
  about : About
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `VersionRecord`.
pub extend VersionRecord with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `VersionRecord`, for debug output.
pub extend VersionRecord with @debug.Debug::{to_repr}

///|
/// One published version of module `name`, for tests and tools that build
/// records: no dependencies, not yanked and nothing in `about` unless given.
pub fn VersionRecord::new(
  name : String,
  version~ : String,
  deps~ : Array[Dep] = [],
  created_at? : String,
  yanked~ : Bool = false,
  deprecated? : String,
  about~ : About = About::new(),
) -> VersionRecord {
  { name, version, deps, created_at, yanked, deprecated, about, }
}

///|
/// A line that is not a version record.
pub(all) suberror ParseError {
  InvalidJson(message~ : String)
  MissingField(field~ : String)
} derive(Eq, Debug)

///|
/// Exposes `equal` and `not_equal` as methods of `ParseError`.
pub extend ParseError with Eq::{equal, not_equal}

///|
/// Exposes `to_repr` as a method of `ParseError`, for debug output.
pub extend ParseError with @debug.Debug::{to_repr}

///|
/// Parses one line of the index, or one line of the natural JSONL that
/// `VersionRecord::to_json` writes; the latter is a subset of the former.
///
/// Fields other than the ones in `VersionRecord` and `About` are ignored;
/// empty strings in `About` read as absent. A dependency is either
/// `"name": "version"` or an object with any of `version`, `alias` and
/// `path`.
pub fn parse_line(line : StringView) -> VersionRecord raise ParseError {
  let json = @json.parse(line) catch {
    e => raise InvalidJson(message=e.to_string())
  }
  guard json is Object(obj) else { raise InvalidJson(message="not an object") }
  guard obj.get("name") is Some(String(name)) else {
    raise MissingField(field="name")
  }
  guard obj.get("version") is Some(String(version)) else {
    raise MissingField(field="version")
  }
  let deps = []
  if obj.get("deps") is Some(Object(map)) {
    for dep, req in map {
      let field = fn(o : Map[String, Json], key : String) -> String? {
        if o.get(key) is Some(String(v)) {
          Some(v)
        } else {
          None
        }
      }
      deps.push(
        match req {
          String(v) =>
            { name: dep, version: Some(v), imported_as: None, path: None, }
          Object(o) =>
            {
              name: dep,
              version: field(o, "version"),
              imported_as: field(o, "alias"),
              path: field(o, "path"),
            }
          _ => { name: dep, version: None, imported_as: None, path: None, }
        },
      )
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
  let text = fn(key : String) -> String? {
    match obj.get(key) {
      Some(String(v)) if !v.trim().is_empty() => Some(v)
      _ => None
    }
  }
  let keywords = []
  if obj.get("keywords") is Some(Array(list)) {
    for k in list {
      if k is String(k) && !k.trim().is_empty() {
        keywords.push(k)
      }
    }
  }
  let about = {
    description: text("description"),
    repository: text("repository"),
    license: text("license"),
    keywords,
    yanked_reason: text("yanked_reason"),
  }
  { name, version, deps, created_at, yanked, deprecated, about, }
}

///|
/// The fields that are present, under their index names.
pub impl ToJson for About with fn to_json(self) {
  let obj : Map[String, Json] = Map([])
  let put = fn(key : String, value : String?) {
    if value is Some(v) {
      obj[key] = Json::string(v)
    }
  }
  put("description", self.description)
  put("repository", self.repository)
  put("license", self.license)
  if !self.keywords.is_empty() {
    obj["keywords"] = Json::array(self.keywords.map(Json::string))
  }
  put("yanked_reason", self.yanked_reason)
  Json::object(obj)
}

///|
/// Exposes `to_json` as a method of `About`.
pub extend About with ToJson::{to_json}

///|
/// The natural JSONL shape:
/// `{"name","version","created_at","deps":{…},"yanked","deprecated"?}`
/// followed by the `About` fields that are present. A dependency is its
/// version (or `null`), or, when it has another import name or a path, an
/// object of the fields it has, under the index's names.
pub impl ToJson for VersionRecord with fn to_json(self) {
  let deps : Map[String, Json] = Map([])
  for dep in self.deps {
    deps[dep.name] = match dep {
      { imported_as: None, path: None, version: Some(v), .. } => Json::string(v)
      { imported_as: None, path: None, version: None, .. } => Json::null()
      _ => {
        let o : Map[String, Json] = Map([])
        for
          field in [
            ("version", dep.version),
            ("alias", dep.imported_as),
            ("path", dep.path),
          ] {
          if field.1 is Some(v) {
            o[field.0] = Json::string(v)
          }
        }
        Json::object(o)
      }
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
  if self.about.to_json() is Object(about) {
    for key, value in about {
      obj[key] = value
    }
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
/// Exposes `to_json` as a method of `VersionRecord`.
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

///|
/// Semantic-version order: numeric `major.minor.patch`, a pre-release before
/// its release, pre-release identifiers numerically when both are numbers,
/// and build metadata ignored. Versions that are not `x.y.z` fall back to
/// `compare_names`.
pub fn compare_versions(a : String, b : String) -> Int32 {
  match (parse_version(a), parse_version(b)) {
    (Some((ca, pa)), Some((cb, pb))) => {
      for i in 0..<3 {
        let c = ca[i].compare(cb[i])
        if c != 0 {
          return c
        }
      }
      match (pa, pb) {
        ([], []) => 0
        ([], _) => 1
        (_, []) => -1
        _ => {
          let n = if pa.length() < pb.length() {
            pa.length()
          } else {
            pb.length()
          }
          for i in 0..<n {
            let c = compare_identifiers(pa[i], pb[i])
            if c != 0 {
              return c
            }
          }
          pa.length().compare(pb.length())
        }
      }
    }
    _ => compare_names(a, b)
  }
}

///|
/// Whether `v` is a semantic version, so `compare_versions` orders it as one.
/// Requirements such as `*` or `^0.1.0` are not.
pub fn is_version(v : String) -> Bool {
  parse_version(v) is Some(_)
}

///|
/// The release line semantic versioning keeps compatible within: `"0.22"`
/// for `0.22.5` (a minor bump breaks before 1.0), `"2"` for `2.3.1`.
pub fn release_line(v : String) -> String? {
  guard parse_version(v) is Some((n, _)) else { return None }
  Some(if n[0] == 0L { "0.\{n[1]}" } else { "\{n[0]}" })
}

///|
fn parse_version(v : String) -> (FixedArray[Int64], Array[String])? {
  let v = match v.find("+") {
    Some(i) => v[:i]
    None => v[:]
  }
  let (core, pre) = match v.find("-") {
    Some(i) => (v[:i], v[i + 1:].split(".").map(s => s.to_owned()).collect())
    None => (v, [])
  }
  let parts = core.split(".").collect()
  guard parts.length() == 3 else { return None }
  let nums = FixedArray::make(3, 0L)
  for i, p in parts {
    guard !p.is_empty() && p.iter().all(c => c >= '0' && c <= '9') else {
      return None
    }
    nums[i] = @string.parse_int64(p) catch { _ => return None }
  }
  Some((nums, pre))
}

///|
fn compare_identifiers(a : String, b : String) -> Int32 {
  let numeric = fn(s : String) {
    !s.is_empty() && s.iter().all(c => c >= '0' && c <= '9')
  }
  match (numeric(a), numeric(b)) {
    (true, true) =>
      if a.length() != b.length() {
        a.length().compare(b.length())
      } else {
        compare_names(a, b)
      }
    (true, false) => -1
    (false, true) => 1
    (false, false) => compare_names(a, b)
  }
}
