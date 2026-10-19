///|
/// Exit codes: 0 success, 1 failure (e.g. the index cannot be read),
/// 2 usage error.
const USAGE : String =
  #|usage: mooncakes-graph <command> [options]
  #|
  #|commands:
  #|  versions    every published version as JSONL, one per line
  #|  top         modules ranked by how much they are depended on, as TSV
  #|                -n N        rows to print (default 20, 0 for all)
  #|                --by KEY    direct | transitive | owners (default transitive)
  #|
  #|options:
  #|  --index DIR   registry index directory (default: $MOON_HOME/registry/index)

///|
fn main {
  let args = @env.args()
  let code = run(args[1:]) catch {
    @args.CliError(option~, message~, ..) => {
      let detail = if option.is_empty() { "" } else { " '\{option}'" }
      eprintln("mooncakes-graph: \{message}\{detail}")
      eprintln(USAGE)
      2
    }
    Fatal(message) => {
      eprintln("mooncakes-graph: \{message}")
      1
    }
    e => {
      eprintln("mooncakes-graph: \{e}")
      1
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
    "versions" => versions(rest)
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
fn load_index(parsed : @args.ParsedArgs) -> @index_fs.Index raise {
  let dir = match parsed.last_value("index") {
    Some(d) => d
    None =>
      match @index_fs.index_dir() {
        Some(d) => d
        None => raise Fatal("cannot locate the index: set MOON_HOME or HOME")
      }
  }
  let index = @index_fs.read(dir) catch {
    @index_fs.NotFound(_) =>
      raise Fatal("no index at \{dir} (run `moon update` to fetch it)")
    e => raise Fatal("cannot read the index at \{dir}: \{e}")
  }
  if index.skipped > 0 {
    eprintln("mooncakes-graph: skipped \{index.skipped} unreadable index lines")
  }
  index
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
  let index = load_index(parsed)
  let out = StringBuilder()
  let mut first = true
  for module_ in index.modules {
    for record in module_.1 {
      if !first {
        out.write_char('\n')
      }
      first = false
      out.write_string(record.to_json().stringify())
    }
  }
  if !first {
    println(out.to_string())
  }
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
  let index = load_index(parsed)
  let graph = @graph.Graph::new(index.modules)
  let m = graph.metrics()
  let key = match parsed.last_value("by") {
    None | Some("transitive") => m.transitive
    Some("direct") => m.direct
    Some("owners") => m.owners
    Some(_) => raise usage_error("by", "expected direct, transitive or owners")
  }
  let order = Array::makei(graph.size(), i => i)
  order.sort_by((a, b) => {
    let c = key[b].compare(key[a])
    if c != 0 {
      c
    } else {
      @mooncakes_index.compare_names(graph.names[a], graph.names[b])
    }
  })
  let rows = if limit <= 0 || limit > order.length() {
    order.length()
  } else {
    limit
  }
  let out = StringBuilder()
  out.write_string("module\tdirect\ttransitive\towners")
  for i in order[:rows] {
    out.write_string(
      "\n\{graph.names[i]}\t\{m.direct[i]}\t\{m.transitive[i]}\t\{m.owners[i]}",
    )
  }
  println(out.to_string())
  0
}
