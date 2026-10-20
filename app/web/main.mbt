///|
using @rabbita {type Cmd, type Emit, type Html, type Val}

///|
using @html {div, text}

///|
/// Rabbita's http joins a relative path onto `document.baseURI` as a string,
/// which breaks once the page URL carries `?m=`. Resolve it ourselves.
extern "js" fn resolve_url(path : String) -> String =
  #|(p) => new URL(p, document.baseURI).href

///|
extern "js" fn page_path() -> String = "() => location.pathname"

///|
extern "js" fn decode_component(s : String) -> String =
  #|(s) => { try { return decodeURIComponent(s.replace(/\+/g, " ")); } catch { return s; } }

///|
extern "js" fn encode_module(s : String) -> String =
  #|(s) => encodeURIComponent(s).replace(/%2F/g, "/")

///|
extern "js" fn capture_pointer(id : String, pointer : Int32) -> Unit =
  #|(id, p) => { try { document.getElementById(id)?.setPointerCapture(p); } catch {} }

///|
fn pointer_id(e : @dom.MouseEvent) -> Int32 {
  match e.to_pointer_event() {
    Some(p) => p.get_pointer_id()
    None => 0
  }
}

///|
/// Rabbita turns every link click into a request for the app, so external
/// links open their own tab here, as their `target` asks.
extern "js" fn open_tab(href : String) -> Unit =
  #|(h) => { window.open(h, "_blank", "noopener"); }

///|
extern "js" fn console_warn(s : String) -> Unit = "(s) => console.warn(s)"

///|
/// The `modules` data (descriptions, repositories, ...), fetched the first
/// time a module is selected.
enum AboutStatus {
  Idle
  Fetching
  Fetched
  Unavailable
} derive(Eq)

///|
let abouts : Map[String, @mooncakes_index.About] = Map([])

///|
/// A browsable URL for a `repository` field: https as is, `git+https` and
/// `git@host:path` rewritten, a bare `host.tld/path` given https. Anything
/// else (`add`, a `javascript:` URL) gets no link.
fn source_url(repo : String) -> String? {
  let repo = repo.trim().to_owned()
  let url = if repo.has_prefix("https://") || repo.has_prefix("http://") {
    repo
  } else if repo.has_prefix("git+https://") {
    repo[4:].to_owned()
  } else if repo.has_prefix("git@") && repo.contains(":") {
    let rest = repo[4:].to_owned()
    guard rest.find(":") is Some(i) else { return None }
    "https://\{rest[:i]}/\{rest[i + 1:]}"
  } else if repo.split("/").next() is Some(host) &&
    host.contains(".") &&
    !host.contains(":") {
    "https://" + repo
  } else {
    return None
  }
  let url = if url.has_suffix(".git") {
    url[:url.length() - 4].to_owned()
  } else {
    url
  }
  // Something after the scheme, and no whitespace that would break the link.
  guard url.find("://") is Some(i) && url.length() > i + 3 && !url.contains(" ") else {
    return None
  }
  Some(url)
}

///|
/// The host of an http(s) URL, for link text.
fn host_of(url : String) -> String {
  guard url.find("://") is Some(i) else { return url }
  let rest = url[i + 3:]
  match rest.find("/") {
    Some(j) => rest[:j].to_owned()
    None => rest.to_owned()
  }
}

///|
enum Status {
  Loading
  Ready
  Failed(String)
} derive(Eq)

///|
struct Model {
  status : Status
  show_yanked : Bool
  show_isolated : Bool
  focused : Bool
  /// The module in the URL, kept until the data arrives.
  wanted : String?
  selected : String?
  hovered : String?
  /// Bumped whenever the scene's metrics change, so views that read the
  /// scene re-render.
  revision : Int32
  about : AboutStatus
} derive(Eq)

///|
enum Msg {
  Loaded(Result[String, Error])
  AboutLoaded(Result[String, Error])
  Frame
  UrlChanged(@url.Url)
  LinkClicked(@url.UrlRequest)
  KeyDown(String)
  Wheel(@dom.WheelEvent)
  PointerDown(@dom.MouseEvent)
  PointerMove(@dom.MouseEvent)
  PointerUp(@dom.MouseEvent)
  PointerLeave
  ToggleYanked
  ToggleIsolated
  ToggleFocus
  Pick(String)
  Clear
}

///|
fn name_of(i : Int32) -> String? {
  match scene.graph {
    Some(g) if i != NO_NODE => Some(g.names[i])
    _ => None
  }
}

///|
fn module_in_url(url : @url.Url) -> String? {
  guard url.query is Some(q) else { return None }
  for pair in q.split("&") {
    if pair.has_prefix("m=") {
      let v = decode_component(pair[2:].to_owned())
      return if v.is_empty() { None } else { Some(v) }
    }
  }
  None
}

///|
fn url_for(name : String?) -> String {
  match name {
    Some(n) => page_path() + "?m=" + encode_module(n)
    None => page_path()
  }
}

///|
/// Selects a module by name (or clears with `None`) without touching the
/// URL. A module hidden by a toggle turns that toggle on.
fn apply_selection(model : Model, name : String?) -> Model {
  guard scene.graph is Some(graph) else { return { ..model, wanted: name, } }
  let i = match name {
    Some(n) => graph.ids.get(n).unwrap_or(NO_NODE)
    None => NO_NODE
  }
  let mut model = model
  scene.selected = i
  let needs_toggle = i != NO_NODE &&
    (
      (graph.yanked[i] && !scene.show_yanked) ||
      (!scene.focused && scene.isolated[i] && !scene.show_isolated)
    )
  if needs_toggle {
    if graph.yanked[i] {
      scene.show_yanked = true
    }
    if !scene.focused && scene.isolated[i] {
      scene.show_isolated = true
    }
    rebuild()
    model = {
      ..model,
      show_yanked: scene.show_yanked,
      show_isolated: scene.show_isolated,
      revision: model.revision + 1,
    }
  } else {
    relayout()
  }
  if i == NO_NODE {
    scene.follow = NO_NODE
    scene.auto_fit = true
  } else if !scene.focused {
    focus(i)
  }
  { ..model, wanted: None, selected: name_of(i), }
}

///|
fn select_and_push(model : Model, name : String?) -> (Model, Cmd) {
  let model = apply_selection(model, name)
  (model, @nav.push_url(url_for(model.selected)))
}

///|
/// Fetches the `modules` data the first time a module is selected.
fn update(model : Model, msg : Msg, emit : Emit[Msg]) -> (Model, Cmd) {
  let (model, cmd) = step_model(model, msg)
  if model.selected is Some(_) && model.about is Idle {
    let fetch = @http.get(resolve_url("data/modules.jsonl")).expect_text(
      emit.map(r => AboutLoaded(r)),
    )
    ({ ..model, about: Fetching, }, @rabbita.batch([cmd, fetch]))
  } else {
    (model, cmd)
  }
}

///|
fn step_model(model : Model, msg : Msg) -> (Model, Cmd) {
  match msg {
    Loaded(Ok(body)) => {
      let skipped = load_graph(body)
      if skipped > 0 {
        console_warn("mooncakes-graph: skipped \{skipped} unreadable lines")
      }
      let model = { ..model, status: Ready, revision: model.revision + 1, }
      (apply_selection(model, model.wanted), @rabbita.none)
    }
    Loaded(Err(e)) => ({ ..model, status: Failed("\{e}"), }, @rabbita.none)
    AboutLoaded(Ok(body)) => {
      for line in body.split("\n") {
        if line.is_empty() {
          continue
        }
        let record = @mooncakes_index.parse_line(line) catch { _ => continue }
        abouts[record.name] = record.about
      }
      ({ ..model, about: Fetched, }, @rabbita.none)
    }
    AboutLoaded(Err(e)) => {
      console_warn("mooncakes-graph: no module details: \{e}")
      ({ ..model, about: Unavailable, }, @rabbita.none)
    }
    Frame => {
      step()
      draw()
      (model, @rabbita.none)
    }
    UrlChanged(url) => {
      let name = module_in_url(url)
      if name == model.selected && model.wanted is None {
        (model, @rabbita.none)
      } else {
        (apply_selection(model, name), @rabbita.none)
      }
    }
    LinkClicked(External(href)) => {
      open_tab(href)
      (model, @rabbita.none)
    }
    LinkClicked(Internal(url)) => (model, @nav.load(url.to_string()))
    KeyDown("Escape") =>
      if model.selected is Some(_) {
        select_and_push(model, None)
      } else {
        (model, @rabbita.none)
      }
    KeyDown(_) => (model, @rabbita.none)
    Wheel(e) => {
      e.prevent_default()
      release_camera()
      zoom_at(
        @math.exp(-e.get_delta_y() * 0.0015),
        e.get_offset_x(),
        e.get_offset_y(),
      )
      (model, @rabbita.none)
    }
    PointerDown(e) => {
      let id = pointer_id(e)
      let (x, y) = (e.get_offset_x(), e.get_offset_y())
      capture_pointer("graph", id)
      scene.pointers[id] = (x, y)
      if scene.pointers.length() == 1 {
        scene.pointer_down = true
        scene.dragged = false
        scene.down_x = x
        scene.down_y = y
        scene.last_x = x
        scene.last_y = y
      } else {
        // A second finger: this is a pinch, never a tap.
        scene.dragged = true
        release_camera()
        start_pinch()
      }
      (model, @rabbita.none)
    }
    PointerMove(e) => {
      let id = pointer_id(e)
      let (x, y) = (e.get_offset_x(), e.get_offset_y())
      if scene.pointers.contains(id) {
        scene.pointers[id] = (x, y)
      }
      if scene.pointers.length() >= 2 {
        if pinch_geometry() is Some((d, mx, my)) && scene.pinch_dist > 0.0 {
          scene.cam_x += mx - scene.pinch_x
          scene.cam_y += my - scene.pinch_y
          zoom_at(d / scene.pinch_dist, mx, my)
          scene.pinch_dist = d
          scene.pinch_x = mx
          scene.pinch_y = my
        }
        (model, @rabbita.none)
      } else if scene.pointer_down {
        if (x - scene.down_x).abs() + (y - scene.down_y).abs() > 4.0 {
          scene.dragged = true
          release_camera()
        }
        if scene.dragged {
          scene.cam_x += x - scene.last_x
          scene.cam_y += y - scene.last_y
        }
        scene.last_x = x
        scene.last_y = y
        (model, @rabbita.none)
      } else {
        let i = node_at(x, y)
        set_hovered(i)
        ({ ..model, hovered: name_of(i), }, @rabbita.none)
      }
    }
    PointerUp(e) => {
      let id = pointer_id(e)
      let was_click = scene.pointer_down &&
        !scene.dragged &&
        scene.pointers.length() == 1
      scene.pointers.remove(id)
      match scene.pointers.values().next() {
        // One finger left after a pinch: keep panning from where it is.
        Some((x, y)) => {
          scene.last_x = x
          scene.last_y = y
          (model, @rabbita.none)
        }
        None => {
          scene.pointer_down = false
          scene.dragged = false
          if was_click {
            let i = node_at(e.get_offset_x(), e.get_offset_y())
            select_and_push(model, name_of(i))
          } else {
            (model, @rabbita.none)
          }
        }
      }
    }
    PointerLeave => {
      scene.pointers.clear()
      scene.pointer_down = false
      set_hovered(NO_NODE)
      ({ ..model, hovered: None, }, @rabbita.none)
    }
    ToggleYanked => {
      scene.show_yanked = !scene.show_yanked
      rebuild()
      (
        {
          ..model,
          show_yanked: scene.show_yanked,
          revision: model.revision + 1,
        },
        @rabbita.none,
      )
    }
    ToggleIsolated => {
      scene.show_isolated = !scene.show_isolated
      rebuild()
      (
        {
          ..model,
          show_isolated: scene.show_isolated,
          revision: model.revision + 1,
        },
        @rabbita.none,
      )
    }
    ToggleFocus => {
      scene.focused = !scene.focused
      relayout()
      if !scene.focused && scene.selected != NO_NODE {
        focus(scene.selected)
      }
      ({ ..model, focused: scene.focused, }, @rabbita.none)
    }
    Pick(name) => select_and_push(model, Some(name))
    Clear => select_and_push(model, None)
  }
}

///|
fn subscriptions(_ : Model, emit : Emit[Msg]) -> @sub.Sub {
  @sub.batch([
    @sub.on_animation_frame(emit.map(_ => Frame)),
    @sub.on_url_changed(emit.map(url => UrlChanged(url))),
    @sub.on_url_request(emit.map(req => LinkClicked(req))),
    @sub.on_key_down(emit.map(k => KeyDown(k.key()))),
  ])
}

///|
fn main {
  fn app() {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          {
            status: Loading,
            show_yanked: scene.show_yanked,
            show_isolated: scene.show_isolated,
            focused: scene.focused,
            wanted: None,
            selected: None,
            hovered: None,
            revision: 0,
            about: Idle,
          },
          @http.get(resolve_url("data/versions.jsonl")).expect_text(
            emit.map(r => Loaded(r)),
          ),
        )
      },
      update~,
      subscriptions~,
    )
    view(emit, model)
  }
  @rabbita.new(app).mount("app")
}

///|
fn view(emit : Emit[Msg], model : Val[Model]) -> Val[Html] {
  let canvas_attrs = @html.Attrs::build()
    .on_wheel(e => emit(Wheel(e)))
    .on_pointerdown(e => emit(PointerDown(e)))
    .on_pointermove(e => emit(PointerMove(e)))
    .on_pointerup(e => emit(PointerUp(e)))
    .on_pointercancel(_ => emit(PointerLeave))
    .aria_label("Dependency map of mooncakes.io modules")
  let canvas = @html.canvas(id="graph", attrs=canvas_attrs, ([] : Array[Html]))
  let body = model.map(m => {
    div(class="main", [
      div(class="stage", [canvas, status_view(m)]),
      @html.aside(class="panel", [
        match m.selected {
          Some(name) => detail_view(emit, name)
          None => ranking_view(emit)
        },
      ]),
    ])
  })
  // rui's theme sets its tokens for one mode; follow the OS at load time.
  let mode : @rui.ColorMode = if prefers_dark() { Dark } else { Light }
  header_view(emit, model).view2(body, (header, body) => {
    @rui.theme(mode~, class="app", [header, body])
  })
}

///|
fn header_view(emit : Emit[Msg], model : Val[Model]) -> Val[Html] {
  // Rebuilt when the data, the metrics or the selection change, so the
  // options follow the ranking and the box empties after a pick.
  let search = model
    .map(m => {
      let selected = m.selected.unwrap_or("")
      "\{m.status is Ready}|\{m.revision}|\{selected}"
    })
    .switch_by(_ => search_view(emit), by=key => key)
  let yanked = toggle_view(
    emit,
    model.map(m => m.show_yanked),
    "yanked",
    ToggleYanked,
  )
  let isolated = toggle_view(
    emit,
    model.map(m => m.show_isolated),
    "unconnected",
    ToggleIsolated,
  )
  search.view3(yanked, isolated, (search, yanked, isolated) => {
    @html.header(class="top", [
      div(class="brand", [
        @html.span(class="title", "mooncakes graph"),
        @html.span(class="badge", "unofficial"),
      ]),
      div(class="search", [search]),
      div(class="toggles", [yanked, isolated]),
    ])
  })
}

///|
fn search_view(emit : Emit[Msg]) -> Val[Html] {
  guard scene.graph is Some(graph) else {
    return Val::constant(
      @html.input(
        input_type=Search,
        placeholder="Loading…",
        attrs=@html.Attrs::build(),
      ),
    )
  }
  let t = scene.metrics.transitive
  let order = Array::makei(graph.size(), i => i)
  order.sort_by((a, b) => {
    let c = t[b].compare(t[a])
    if c != 0 {
      c
    } else {
      @mooncakes_index.compare_names(graph.names[a], graph.names[b])
    }
  })
  @rui.combobox(
    id="search",
    options=order.map(i => {
      // Option labels are plain text, so yanked modules say so in words.
      @rui.combobox_option(
        value=graph.names[i],
        label=if graph.yanked[i] {
          graph.names[i] + " (yanked)"
        } else {
          graph.names[i]
        },
      )
    }),
    placeholder="Search modules",
    empty_text="No module matches",
    on_value_change=emit.map(v => if v.is_empty() { Clear } else { Pick(v) }),
  )
}

///|
/// A rui toggle that shows `on`. rui toggles keep their own state, so the
/// toggle is rebuilt whenever `on` changes, including when a selection turns
/// a toggle on.
fn toggle_view(
  emit : Emit[Msg],
  on : Val[Bool],
  label : String,
  msg : Msg,
) -> Val[Html] {
  on.switch_by(
    pressed => {
      @rui.toggle(
        default_pressed=pressed,
        variant=Outline,
        size=Sm,
        aria_label=label,
        on_pressed_change=emit.map(_ => msg),
        // rui marks "on" with a faint muted fill; fill it with the primary
        // colour so the state reads at a glance.
        style=if pressed {
          [
            "--rui-toggle-bg:var(--rui-primary)", "--rui-toggle-fg:var(--rui-primary-foreground)",
            "border-color:var(--rui-primary)",
          ]
        } else {
          []
        },
        label,
      )
    },
    by=pressed => pressed.to_string(),
  )
}

///|
fn status_view(m : Model) -> Html {
  match m.status {
    Loading => div(class="status", "Loading the index…")
    Failed(e) => div(class="status error", "Could not load the data: \{e}")
    Ready =>
      match scene.graph {
        Some(g) => {
          let shown = scene.sim_nodes.length()
          let hint = match (m.hovered, m.selected) {
            (Some(name), _) => name
            (None, Some(name)) if scene.focus_layout =>
              "\{shown} modules: \{name}, what depends on it (orange) and what it depends on (blue) · edges flow the way a change spreads"
            (None, _) =>
              "\{shown} of \{g.size()} modules · scroll or pinch to zoom, drag to pan"
          }
          div(class="status", hint)
        }
        None => text("")
      }
  }
}

///|
fn ranking_view(emit : Emit[Msg]) -> Html {
  guard scene.graph is Some(graph) else { return text("") }
  let order = scene.sim_nodes.copy()
  let t = scene.metrics.transitive
  order.sort_by((a, b) => {
    let c = t[b].compare(t[a])
    if c != 0 {
      c
    } else {
      @mooncakes_index.compare_names(graph.names[a], graph.names[b])
    }
  })
  let note = "Modules that depend on it, directly or not."
  let items = []
  for i in order[:order.length().min(20)] {
    let name = graph.names[i]
    items.push(
      @html.li(on_click=emit(Pick(name)), [
        @html.span(
          class=if graph.yanked[i] { "name yanked" } else { "name" },
          name,
        ),
        @html.span(class="num", "\{t[i]}"),
      ]),
    )
  }
  div(class="ranking", [
    @html.h2("Most depended on"),
    @html.p(class="note", note),
    @html.ol(items),
  ])
}

///|
fn detail_view(emit : Emit[Msg], name : String) -> Html {
  guard scene.graph is Some(graph) && graph.ids.get(name) is Some(i) else {
    return text("")
  }
  let record = graph.current[i]
  let owner = graph.owners[i]
  let m = scene.metrics
  let about = abouts.get(name).unwrap_or(@mooncakes_index.About::new())
  let day = fn(t : String?) {
    match t {
      Some(t) if t.length() >= 10 => Some(t.view(end_offset=10).to_owned())
      _ => None
    }
  }
  let published = match day(record.created_at) {
    Some(d) => " · " + d
    None => ""
  }
  let history = graph.history[i]
  let first = history.iter().filter_map(v => day(v.created_at)).head()
  let releases = if history.length() == 1 {
    "1 version"
  } else {
    "\{history.length()} versions"
  }
  let since = match first {
    Some(d) => "\{releases} since \{d}"
    None => releases
  }
  let license = match about.license {
    Some(l) => " · \{l}"
    None => ""
  }
  // Whether `v` of `t` was yanked, when `t` itself is not wholly yanked
  // (its struck-through name already says so).
  let yanked_version = fn(t : Int32, v : String?) {
    v is Some(v) && !graph.yanked[t] && graph.version_yanked(t, v)
  }
  // One row of a module list: the module, and the version asked for along
  // that edge, marked when it is from an older release line and struck
  // through when it was yanked.
  let module_row = fn(
    n : String,
    asked : String?,
    behind : Bool,
    yanked : Bool,
  ) {
    let id = graph.ids.get(n)
    let gone = id is Some(b) && graph.yanked[b]
    let version = match asked {
      Some(v) =>
        @html.span(
          class=(if behind { "ver behind" } else { "ver" }) +
            (if yanked { " yanked" } else { "" }),
          if behind {
            "\{v} (older line)"
          } else {
            v
          },
        )
      None => text("")
    }
    let label = @html.span(class=if gone { "name yanked" } else { "name" }, n)
    if id is Some(_) {
      @html.li(on_click=emit(Pick(n)), [label, version])
    } else {
      @html.li(class="missing", [@html.span(class="name", n), version])
    }
  }
  let deps = record.deps.map(d => {
    match graph.ids.get(d.name) {
      Some(b) =>
        module_row(
          d.name,
          d.version,
          graph.behind(i, b),
          yanked_version(b, d.version),
        )
      None => module_row(d.name, d.version, false, false)
    }
  })
  let dependents = graph.dependents[i].copy()
  dependents.sort_by((a, b) => m.transitive[b].compare(m.transitive[a]))
  let behind = dependents.filter(d => graph.behind(d, i)).length()
  let line = @mooncakes_index.release_line(record.version).unwrap_or(
    record.version,
  )
  let source = match about.repository {
    Some(r) => source_url(r)
    None => None
  }
  let link = fn(href : String, label : String) {
    @html.a(href~, target=Blank, rel="noopener", label)
  }
  div(class="detail", [
    div(class="detail-head", [
      @html.h2(name),
      @html.button(class="close", on_click=emit(Clear), "×"),
    ]),
    match about.description {
      Some(d) => @html.p(class="description", d)
      None => text("")
    },
    @html.p(class="meta", [
      text("\{record.version}\{published} · by \{owner}"),
      @html.br(),
      text("\{since}\{license}"),
    ]),
    if about.keywords.is_empty() {
      text("")
    } else {
      div(class="keywords", about.keywords.map(k => @html.span(k)))
    },
    if graph.yanked[i] {
      let why = match about.yanked_reason {
        Some(r) => ": \{r}"
        None => "."
      }
      @html.p(class="warn", "Every version of this module is yanked\{why}")
    } else {
      text("")
    },
    match record.deprecated {
      Some(d) => @html.p(class="warn", "Deprecated: \{d}")
      None => text("")
    },
    @html.dl(class="metrics", [
      @html.dt("Depended on by, in all"),
      @html.dd("\{m.transitive[i]}"),
      @html.dt("Directly"),
      @html.dd("\{m.direct[i]}"),
      @html.dt("Other owners"),
      @html.dd("\{m.owners[i]}"),
    ]),
    div(class="links", [
      link("https://mooncakes.io/docs/\{name}", "Docs on mooncakes.io"),
      match source {
        Some(url) => link(url, "Source on \{host_of(url)}")
        None => text("")
      },
      link("https://mooncakes.io/user/\{owner}", "More by \{owner}"),
    ]),
    @rui.button(
      variant=Outline,
      size=Sm,
      class="view-switch",
      on_click=emit(ToggleFocus),
      if scene.focused {
        "Show on the full map"
      } else {
        "Show only related modules"
      },
    ),
    @html.h2(class="sub", "Depends on (\{record.deps.length()})"),
    @html.ul(class="list", deps),
    @html.h2(class="sub", "Depended on by (\{dependents.length()})"),
    if behind > 0 {
      @html.p(
        class="note",
        "\{behind} of \{dependents.length()} ask for a release line before \{line}.",
      )
    } else {
      text("")
    },
    @html.ul(
      class="list",
      dependents.map(d => {
        let asked = graph.asked(d, i)
        module_row(
          graph.names[d],
          asked,
          graph.behind(d, i),
          yanked_version(i, asked),
        )
      }),
    ),
  ])
}
