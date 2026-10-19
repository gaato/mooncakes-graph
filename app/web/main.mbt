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
extern "js" fn console_warn(s : String) -> Unit = "(s) => console.warn(s)"

///|
enum Status {
  Loading
  Ready
  Failed(String)
} derive(Eq)

///|
struct Model {
  status : Status
  show_hubs : Bool
  show_yanked : Bool
  show_isolated : Bool
  /// The module in the URL, kept until the data arrives.
  wanted : String?
  selected : String?
  hovered : String?
  query : String
  /// Bumped whenever the scene's metrics change, so views that read the
  /// scene re-render.
  revision : Int32
} derive(Eq)

///|
enum Msg {
  Loaded(Result[String, Error])
  Frame
  UrlChanged(@url.Url)
  KeyDown(String)
  Wheel(@dom.WheelEvent)
  PointerDown(@dom.MouseEvent)
  PointerMove(@dom.MouseEvent)
  PointerUp(@dom.MouseEvent)
  PointerLeave
  ToggleHubs
  ToggleYanked
  ToggleIsolated
  Query(String)
  Submit
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
  if i != NO_NODE && scene.hidden[i] {
    if scene.hub[i] {
      scene.show_hubs = true
    }
    if graph.yanked[i] {
      scene.show_yanked = true
    }
    if scene.isolated[i] {
      scene.show_isolated = true
    }
    rebuild()
    model = {
      ..model,
      show_hubs: scene.show_hubs,
      show_yanked: scene.show_yanked,
      show_isolated: scene.show_isolated,
      revision: model.revision + 1,
    }
  }
  select_node(i)
  if i != NO_NODE {
    focus(i)
  } else {
    scene.follow = NO_NODE
  }
  { ..model, wanted: None, selected: name_of(i), }
}

///|
fn select_and_push(model : Model, name : String?) -> (Model, Cmd) {
  let model = apply_selection(model, name)
  (model, @nav.push_url(url_for(model.selected)))
}

///|
fn search(query : String, limit : Int32) -> Array[String] {
  guard scene.graph is Some(graph) && !query.is_empty() else { return [] }
  let q = query.to_lower()
  let hits = []
  for i, name in graph.names {
    let lower = name.to_lower()
    let rank = if lower == q {
      0
    } else if lower.has_prefix(q) || lower.contains("/" + q) {
      1
    } else if lower.contains(q) {
      2
    } else {
      continue
    }
    hits.push((rank, i))
  }
  hits.sort_by((a, b) => {
    let c = a.0.compare(b.0)
    if c != 0 {
      return c
    }
    let d = scene.metrics.transitive[b.1].compare(scene.metrics.transitive[a.1])
    if d != 0 {
      d
    } else {
      @mooncakes_index.compare_names(graph.names[a.1], graph.names[b.1])
    }
  })
  hits[:limit.min(hits.length())].iter().map(h => graph.names[h.1]).collect()
}

///|
fn update(model : Model, msg : Msg, _ : Emit[Msg]) -> (Model, Cmd) {
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
    KeyDown("Escape") =>
      if model.selected is Some(_) {
        select_and_push({ ..model, query: "", }, None)
      } else {
        ({ ..model, query: "", }, @rabbita.none)
      }
    KeyDown(_) => (model, @rabbita.none)
    Wheel(e) => {
      e.prevent_default()
      release_camera()
      let k = @math.exp(-e.get_delta_y() * 0.0015)
      let k = (scene.scale * k).clamp(min=0.02, max=20.0) / scene.scale
      let ox = e.get_offset_x()
      let oy = e.get_offset_y()
      scene.cam_x = ox - (ox - scene.cam_x) * k
      scene.cam_y = oy - (oy - scene.cam_y) * k
      scene.scale = scene.scale * k
      (model, @rabbita.none)
    }
    PointerDown(e) => {
      scene.pointer_down = true
      scene.dragged = false
      scene.down_x = e.get_client_x()
      scene.down_y = e.get_client_y()
      scene.last_x = scene.down_x
      scene.last_y = scene.down_y
      (model, @rabbita.none)
    }
    PointerMove(e) => {
      let (cx, cy) = (e.get_client_x(), e.get_client_y())
      if scene.pointer_down {
        if (cx - scene.down_x).abs() + (cy - scene.down_y).abs() > 4.0 {
          scene.dragged = true
          release_camera()
        }
        if scene.dragged {
          scene.cam_x += cx - scene.last_x
          scene.cam_y += cy - scene.last_y
        }
        scene.last_x = cx
        scene.last_y = cy
        (model, @rabbita.none)
      } else {
        let i = node_at(e.get_offset_x(), e.get_offset_y())
        set_hovered(i)
        ({ ..model, hovered: name_of(i), }, @rabbita.none)
      }
    }
    PointerUp(e) => {
      let was_click = scene.pointer_down && !scene.dragged
      scene.pointer_down = false
      scene.dragged = false
      if was_click {
        let i = node_at(e.get_offset_x(), e.get_offset_y())
        select_and_push(model, name_of(i))
      } else {
        (model, @rabbita.none)
      }
    }
    PointerLeave => {
      scene.pointer_down = false
      set_hovered(NO_NODE)
      ({ ..model, hovered: None, }, @rabbita.none)
    }
    ToggleHubs => {
      scene.show_hubs = !scene.show_hubs
      rebuild()
      (
        { ..model, show_hubs: scene.show_hubs, revision: model.revision + 1, },
        @rabbita.none,
      )
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
    Query(q) => ({ ..model, query: q, }, @rabbita.none)
    Submit =>
      match search(model.query, 1) {
        [name] => select_and_push({ ..model, query: "", }, Some(name))
        _ => (model, @rabbita.none)
      }
    Pick(name) => select_and_push({ ..model, query: "", }, Some(name))
    Clear => select_and_push(model, None)
  }
}

///|
fn subscriptions(_ : Model, emit : Emit[Msg]) -> @sub.Sub {
  @sub.batch([
    @sub.on_animation_frame(emit.map(_ => Frame)),
    @sub.on_url_changed(emit.map(url => UrlChanged(url))),
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
            show_hubs: scene.show_hubs,
            show_yanked: scene.show_yanked,
            show_isolated: scene.show_isolated,
            wanted: None,
            selected: None,
            hovered: None,
            query: "",
            revision: 0,
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
  model.map(m => {
    div(class="app", [
      header_view(emit, m),
      div(class="main", [
        div(class="stage", [canvas, status_view(m)]),
        @html.aside(class="panel", [
          match m.selected {
            Some(name) => detail_view(emit, name)
            None => ranking_view(emit)
          },
        ]),
      ]),
    ])
  })
}

///|
fn header_view(emit : Emit[Msg], m : Model) -> Html {
  let results = search(m.query, 8)
  let form_attrs = @html.Attrs::build().on_submit(e => {
    e.prevent_default()
    emit(Submit)
  })
  @html.header(class="top", [
    div(class="brand", [
      @html.span(class="title", "mooncakes graph"),
      @html.span(class="badge", "unofficial"),
    ]),
    @html.form(class="search", attrs=form_attrs, [
      @html.input(
        input_type=Search,
        value=m.query,
        placeholder="Search modules",
        auto_complete=Off,
        on_input=emit.map(q => Query(q)),
      ),
      if results.is_empty() {
        text("")
      } else {
        @html.ul(
          class="results",
          results.map(name => @html.li(on_click=emit(Pick(name)), name)),
        )
      },
    ]),
    div(class="toggles", [
      toggle("moonbitlang/x & async", m.show_hubs, emit(ToggleHubs)),
      toggle("yanked", m.show_yanked, emit(ToggleYanked)),
      toggle("unconnected", m.show_isolated, emit(ToggleIsolated)),
    ]),
  ])
}

///|
fn toggle(label : String, on : Bool, msg : Cmd) -> Html {
  @html.button(
    class=if on { "toggle on" } else { "toggle" },
    attrs=@html.Attrs::build().aria_pressed(if on { "true" } else { "false" }),
    on_click=msg,
    label,
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
          let hint = match m.hovered {
            Some(name) => name
            None =>
              "\{shown} of \{g.size()} modules · scroll to zoom, drag to pan"
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
  let note = if scene.show_hubs {
    "Modules that depend on it, directly or not."
  } else {
    "Modules that depend on it, directly or not, with moonbitlang/x and async hidden."
  }
  let items = []
  for i in order[:order.length().min(20)] {
    let name = graph.names[i]
    items.push(
      @html.li(on_click=emit(Pick(name)), [
        @html.span(class="name", name),
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
  let published = match record.created_at {
    Some(t) if t.length() >= 10 => " · " + t.view(end_offset=10).to_owned()
    _ => ""
  }
  let module_link = fn(n : String) {
    if graph.ids.contains(n) {
      @html.li(on_click=emit(Pick(n)), n)
    } else {
      @html.li(class="missing", n)
    }
  }
  let dependents = graph.dependents[i].copy()
  dependents.sort_by((a, b) => m.transitive[b].compare(m.transitive[a]))
  div(class="detail", [
    div(class="detail-head", [
      @html.h2(name),
      @html.button(class="close", on_click=emit(Clear), "×"),
    ]),
    @html.p(class="meta", "\{record.version}\{published} · by \{owner}"),
    if graph.yanked[i] {
      @html.p(class="warn", "Every version of this module is yanked.")
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
      @html.a(
        href="https://mooncakes.io/docs/\{name}",
        target=Blank,
        rel="noopener",
        "Docs on mooncakes.io",
      ),
      @html.a(
        href="https://mooncakes.io/user/\{owner}",
        target=Blank,
        rel="noopener",
        "More by \{owner}",
      ),
    ]),
    @html.h2(class="sub", "Depends on (\{record.deps.length()})"),
    @html.ul(class="list", record.deps.map(d => module_link(d.name))),
    @html.h2(class="sub", "Depended on by (\{dependents.length()})"),
    @html.ul(class="list", dependents.map(d => module_link(graph.names[d]))),
  ])
}
