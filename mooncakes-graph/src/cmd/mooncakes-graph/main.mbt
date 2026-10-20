///|
/// Exit codes follow grep: 0 success, 1 a module was not found, 2 a usage
/// error or a failure such as an unreadable index.
const USAGE : String =
  #|usage: mooncakes-graph <command> [options]
  #|
  #|commands:
  #|  dependents MODULE...   modules that depend on MODULE, as a tree
  #|  deps MODULE...         modules that MODULE depends on, as a tree
  #|                -L N        descend at most N levels
  #|                --noreport  omit the module count
  #|                -J          tree's JSON layout
  #|  versions    every published version as JSONL, one per line
  #|  modules     every module's description, repository, license and
  #|              keywords from its current version, as JSONL
  #|  stats       counts and the index's fetch time, as JSON
  #|  top         modules ranked by how much they are depended on, as TSV
  #|                -n N        rows to print (default 20, 0 for all)
  #|                --by KEY    direct | transitive | owners (default transitive)
  #|
  #|options:
  #|  --index DIR   registry index directory (default: $MOON_HOME/registry/index)
  #|
  #|exit status: 0 ok, 1 module not found, 2 usage error or failure

///|
fn main {
  let args = @env.args()
  let code = run(args[1:]) catch {
    @args.CliError(option~, message~, ..) => {
      let flag = if option.is_empty() {
        ""
      } else if option.length() == 1 {
        "-\{option}: "
      } else {
        "--\{option}: "
      }
      eprintln("mooncakes-graph: \{flag}\{message}")
      eprintln(USAGE)
      2
    }
    Fatal(message) => {
      eprintln("mooncakes-graph: \{message}")
      2
    }
    e => {
      eprintln("mooncakes-graph: \{e}")
      2
    }
  }
  if code != 0 {
    @sys.exit(code)
  }
}

///|
/// A failure with a message meant for the user.
suberror Fatal {
  Fatal(String)
}

///|
fn run(args : ArrayView[String]) -> Int32 raise {
  guard args is [command, .. rest] else {
    eprintln(USAGE)
    return 2
  }
  match command {
    "dependents" => tree_command(Dependents, rest)
    "deps" => tree_command(Deps, rest)
    "versions" => versions(rest)
    "modules" => modules(rest)
    "stats" => stats(rest)
    "top" => top(rest)
    "-h" | "--help" | "help" => {
      println(USAGE)
      0
    }
    _ => {
      eprintln("mooncakes-graph: unknown command '\{command}'")
      eprintln(USAGE)
      2
    }
  }
}

///|
let common_options : Array[@args.OptionSpec] = [@args.option("index")]

///|
/// The index as the commands see it.
struct Loaded {
  graph : @graph.Graph
  /// When `moon update` last moved the index (Unix seconds), if known.
  fetched_at : Int64?
}

///|
fn load_index(parsed : @args.ParsedArgs) -> Loaded raise {
  let dir = match parsed.last_value("index") {
    Some(d) => d
    None =>
      match @index_fs.index_dir() {
        Some(d) => d
        None => raise Fatal("cannot locate the index: set MOON_HOME or HOME")
      }
  }
  let index = @index_fs.read(dir) catch {
    NotFound(..) =>
      raise Fatal("no index at \{dir} (run `moon update` to fetch it)")
    Unreadable(path~, message~) =>
      raise Fatal("cannot read the index at \{path}: \{message}")
  }
  if index.skipped > 0 {
    eprintln("mooncakes-graph: skipped \{index.skipped} unreadable index lines")
  }
  { graph: @graph.Graph::new(index.modules), fetched_at: index.fetched_at, }
}

///|
fn versions(args : ArrayView[String]) -> Int32 raise {
  let parsed = @args.parse(args, common_options)
  if parsed.operands.length() > 0 {
    raise @args.CliError(
      kind=UnexpectedOptionValue,
      option="",
      message="versions takes no operands",
    )
  }
  let graph = load_index(parsed).graph
  let out = StringBuilder()
  let mut first = true
  for node in 0..<graph.size() {
    for record in graph.history(node) {
      if !first {
        out.write_char('\n')
      }
      first = false
      // The graph fields only; `modules` carries the rest once per module.
      let record = @mooncakes_index.VersionRecord::new(
        record.name,
        version=record.version,
        deps=record.deps,
        created_at?=record.created_at,
        yanked=record.yanked,
        deprecated?=record.deprecated,
      )
      out.write_string(record.to_json().stringify())
    }
  }
  if !first {
    println(out.to_string())
  }
  0
}

///|
/// One line per module: its name and current version, then the `About`
/// fields of that version that are present.
fn modules(args : ArrayView[String]) -> Int32 raise {
  let parsed = @args.parse(args, common_options)
  if parsed.operands.length() > 0 {
    raise @args.CliError(
      kind=UnexpectedOptionValue,
      option="",
      message="modules takes no operands",
    )
  }
  let graph = load_index(parsed).graph
  let out = StringBuilder()
  for i in 0..<graph.size() {
    let record = graph.current(i)
    let obj : Map[String, Json] = Map([
      ("name", Json::string(record.name)),
      ("version", Json::string(record.version)),
    ])
    if record.about.to_json() is Object(about) {
      for key, value in about {
        obj[key] = value
      }
    }
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string(Json::object(obj).stringify())
  }
  if graph.size() > 0 {
    println(out.to_string())
  }
  0
}

///|
/// The index at a glance: when it was fetched and what the graph holds.
/// `edges` are the graph's (dependencies on other modules in the index);
/// `dangling_edges` are dependencies on modules missing from it.
fn stats(args : ArrayView[String]) -> Int32 raise {
  let parsed = @args.parse(args, common_options)
  if parsed.operands.length() > 0 {
    raise usage_error("", "stats takes no operands")
  }
  let index = load_index(parsed)
  let s = index.graph.stats()
  let count = fn(n : Int32) { Json::number(n.to_double()) }
  let out = Json::object(
    Map([
      (
        "index_fetched_at",
        match index.fetched_at {
          Some(t) => Json::string(format_time(t))
          None => Json::null()
        },
      ),
      ("modules", count(s.modules)),
      ("versions", count(s.versions)),
      ("modules_with_deps", count(s.modules_with_deps)),
      ("edges", count(s.edges)),
      ("dangling_edges", count(s.dangling_edges)),
      ("all_yanked", count(s.all_yanked)),
    ]),
  )
  println(out.stringify(indent=2))
  0
}

///|
fn usage_error(option : String, message : String) -> Error {
  @args.CliError(kind=InvalidValue, option~, message~)
}

///|
fn top(args : ArrayView[String]) -> Int32 raise {
  let parsed = @args.parse(
    args,
    [
      ..common_options,
      @args.option("n", short='n', allow_attached=true),
      @args.option("by"),
    ],
  )
  if parsed.operands.length() > 0 {
    raise usage_error("", "top takes no operands")
  }
  let limit = match parsed.last_value("n") {
    Some(v) =>
      @string.parse_int(v) catch {
        _ => raise usage_error("n", "not a number")
      }
    None => 20
  }
  let by : @graph.Metric = match parsed.last_value("by") {
    None | Some("transitive") => Transitive
    Some("direct") => Direct
    Some("owners") => Owners
    Some(_) => raise usage_error("by", "expected direct, transitive or owners")
  }
  let graph = load_index(parsed).graph
  let m = graph.metrics()
  let order = m.ranking(by)
  let rows = if limit <= 0 || limit > order.length() {
    order.length()
  } else {
    limit
  }
  let out = StringBuilder()
  out.write_string("module\tdirect\ttransitive\towners")
  for i in order[:rows] {
    out.write_string(
      "\n\{graph.name(i)}\t\{m.get(i, Direct)}\t\{m.get(i, Transitive)}\t\{m.get(i, Owners)}",
    )
  }
  println(out.to_string())
  0
}

///|
fn tree_command(
  direction : @graph.Direction,
  args : ArrayView[String],
) -> Int32 raise {
  let parsed = @args.parse(
    args,
    [
      ..common_options,
      @args.option("L", short='L', allow_attached=true),
      @args.flag("noreport"),
      @args.flag("J", short='J'),
    ],
  )
  if parsed.operands.is_empty() {
    raise usage_error("", "expected at least one module")
  }
  let max_depth = match parsed.last_value("L") {
    Some(v) => {
      let n = @string.parse_int(v) catch {
        _ => raise usage_error("L", "not a number")
      }
      if n < 1 {
        raise usage_error("L", "must be at least 1")
      }
      Some(n)
    }
    None => None
  }
  let index = load_index(parsed)
  let graph = index.graph
  let roots = []
  let mut missing = false
  for name in parsed.operands {
    match graph.find(name) {
      Some(i) => roots.push(i)
      None => {
        eprintln("mooncakes-graph: \{name}: no such module")
        missing = true
      }
    }
  }
  if roots.is_empty() {
    return 1
  }
  let forest = graph.forest(roots, direction, max_depth?)
  let noreport = parsed.contains("noreport")
  let as_of = index.fetched_at.map(format_time)
  if parsed.contains("J") {
    let report = if noreport {
      None
    } else {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("report")),
        ("modules", Json::number(forest.modules.to_double())),
      ])
      if as_of is Some(t) {
        fields["index_fetched_at"] = Json::string(t)
      }
      Some(Json::object(fields))
    }
    print_raw(render_json(graph, forest, graph.metrics(), report))
  } else {
    let report = if noreport {
      None
    } else {
      match as_of {
        Some(t) => Some("\{module_count(forest.modules)} (index as of \{t})")
        None => Some(module_count(forest.modules))
      }
    }
    print_raw(render_text(graph, forest, report))
  }
  if missing {
    1
  } else {
    0
  }
}

///|
/// Prints text that already ends with a newline.
fn print_raw(text : String) -> Unit {
  if text.has_suffix("\n") {
    println(text[:text.length() - 1].to_owned())
  } else {
    println(text)
  }
}

///|
/// Unix seconds as `YYYY-MM-DDTHH:MMZ`.
fn format_time(secs : Int64) -> String {
  let days = (secs / 86400L).to_int()
  let rem = (secs % 86400L).to_int()
  // Howard Hinnant's civil_from_days.
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 })
  let pad = fn(n : Int32) { if n < 10 { "0\{n}" } else { "\{n}" } }
  "\{y}-\{pad(m)}-\{pad(d)}T\{pad(rem / 3600)}:\{pad(rem % 3600 / 60)}Z"
}
