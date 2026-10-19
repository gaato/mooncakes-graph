// M0 spike: canvas + rAF + wheel/pointer + DPR, JSONL decode time, and
// whether on_url_changed fires on the initial load. Replaced in M2.

///|
using @rabbita {type Cmd, type Emit, type Html, type Val}

///|
extern "js" fn now() -> Double = "() => performance.now()"

///|
extern "js" fn console_log(s : String) -> Unit = "(s) => console.log(s)"

///|
/// Rabbita's http joins a relative path onto `document.baseURI` as a string,
/// which breaks once the page URL carries `?m=`. Resolve it ourselves.
extern "js" fn resolve_url(path : String) -> String =
  #|(p) => new URL(p, document.baseURI).href

///|
/// Sizes the backing store to the CSS box times devicePixelRatio and returns
/// the ratio, or 0 when the canvas is missing.
extern "js" fn fit_canvas(id : String) -> Double =
  #|(id) => {
  #|  const c = document.getElementById(id);
  #|  if (!c) return 0;
  #|  const r = window.devicePixelRatio || 1;
  #|  const w = Math.round(c.clientWidth * r), h = Math.round(c.clientHeight * r);
  #|  if (c.width !== w) c.width = w;
  #|  if (c.height !== h) c.height = h;
  #|  return r;
  #|}

///|
struct Scene {
  mut xs : Array[Double]
  mut ys : Array[Double]
  mut edges : Array[Int32]
  mut cam_x : Double
  mut cam_y : Double
  mut scale : Double
  mut dragging : Bool
  mut last_x : Double
  mut last_y : Double
  mut frames : Int32
  mut window_start : Double
}

///|
let scene : Scene = {
  xs: [],
  ys: [],
  edges: [],
  cam_x: 0.0,
  cam_y: 0.0,
  scale: 1.0,
  dragging: false,
  last_x: 0.0,
  last_y: 0.0,
  frames: 0,
  window_start: 0.0,
}

///|
enum Msg {
  Frame(Double)
  Loaded(Result[String, Error])
  UrlChanged(@url.Url)
  Wheel(@dom.WheelEvent)
  Down(@dom.MouseEvent)
  Move(@dom.MouseEvent)
  Up
}

///|
struct Model {
  fps : Double
  draw_ms : Double
  status : String
  url_events : Int32
  last_url : String
} derive(Eq)

///|
fn load(text : String) -> String {
  let t0 = now()
  let ids : Map[String, Int32] = Map([])
  let latest : Map[String, Json] = Map([])
  let mut lines = 0
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    lines += 1
    let json = @json.parse(line) catch { _ => continue }
    guard json is { "name": String(name), "yanked": False, .. } else {
      continue
    }
    if !ids.contains(name) {
      ids[name] = ids.length()
    }
    latest[name] = json
  }
  let t_parse = now() - t0
  let edges = []
  for _, json in latest {
    guard json is { "name": String(name), "deps": Object(deps), .. } else {
      continue
    }
    for dep, _ in deps {
      if ids.get(dep) is Some(t) {
        edges.push(ids[name])
        edges.push(t)
      }
    }
  }
  let n = ids.length()
  let xs = Array::make(n, 0.0)
  let ys = Array::make(n, 0.0)
  // Golden-angle spiral: deterministic and spread out, enough for a draw test.
  for i in 0..<n {
    let r = 8.0 * Double::from_int(i).sqrt()
    let a = Double::from_int(i) * 2.399963
    xs[i] = r * @math.cos(a)
    ys[i] = r * @math.sin(a)
  }
  scene.xs = xs
  scene.ys = ys
  scene.edges = edges
  let msg = "lines=\{lines} modules=\{n} edges=\{edges.length() / 2} parse=\{t_parse.to_int()}ms total=\{(now() - t0).to_int()}ms"
  console_log("[spike] " + msg)
  msg
}

///|
fn draw() -> Double {
  let t0 = now()
  let dpr = fit_canvas("graph")
  guard dpr > 0.0 && @canvas.get_context2d("graph") is Some(ctx) else {
    return 0.0
  }
  ctx.reset_transform()
  ctx.clear_rect(0.0, 0.0, 1.0e6, 1.0e6)
  let s = scene.scale * dpr
  ctx.set_transform(s, 0.0, 0.0, s, scene.cam_x * dpr, scene.cam_y * dpr)
  // Slow rotation so every frame redraws the whole scene.
  let rot = Double::from_int(scene.frames) * 0.002
  let (c, sn) = (@math.cos(rot), @math.sin(rot))
  let px = fn(i : Int32) { scene.xs[i] * c - scene.ys[i] * sn }
  let py = fn(i : Int32) { scene.xs[i] * sn + scene.ys[i] * c }
  ctx.set_stroke_style(@js.Union3::from0("rgba(100,116,139,0.25)"))
  ctx.set_line_width(0.5 / scene.scale)
  ctx.begin_path()
  let edges = scene.edges
  for k = 0; k < edges.length(); k = k + 2 {
    ctx.move_to(px(edges[k]), py(edges[k]))
    ctx.line_to(px(edges[k + 1]), py(edges[k + 1]))
  }
  ctx.stroke()
  ctx.set_fill_style(@js.Union3::from0("rgb(37,99,235)"))
  ctx.begin_path()
  for i in 0..<scene.xs.length() {
    let (x, y) = (px(i), py(i))
    ctx.move_to(x + 2.0, y)
    ctx.arc(x, y, 2.0, 0.0, 6.283185307179586)
  }
  ctx.fill()
  now() - t0
}

///|
fn update(model : Model, msg : Msg, _ : Emit[Msg]) -> (Model, Cmd) {
  match msg {
    Frame(ts) => {
      let ms = draw()
      scene.frames += 1
      if scene.frames % 60 == 0 {
        let fps = 60000.0 / (ts - scene.window_start)
        scene.window_start = ts
        ({ ..model, fps, draw_ms: ms, }, @rabbita.none)
      } else {
        (model, @rabbita.none)
      }
    }
    Loaded(Ok(text)) => ({ ..model, status: load(text), }, @rabbita.none)
    Loaded(Err(e)) => ({ ..model, status: "load failed: \{e}", }, @rabbita.none)
    UrlChanged(url) => {
      console_log("[spike] on_url_changed \{url}")
      (
        {
          ..model,
          url_events: model.url_events + 1,
          last_url: url.to_string(),
        },
        @rabbita.none,
      )
    }
    Wheel(e) => {
      e.prevent_default()
      let k = @math.exp(-e.get_delta_y() * 0.0015)
      let (ox, oy) = (e.get_offset_x(), e.get_offset_y())
      // Zoom about the cursor.
      scene.cam_x = ox - (ox - scene.cam_x) * k
      scene.cam_y = oy - (oy - scene.cam_y) * k
      scene.scale = scene.scale * k
      (model, @rabbita.none)
    }
    Down(e) => {
      scene.dragging = true
      scene.last_x = e.get_client_x()
      scene.last_y = e.get_client_y()
      (model, @rabbita.none)
    }
    Move(e) => {
      if scene.dragging {
        scene.cam_x += e.get_client_x() - scene.last_x
        scene.cam_y += e.get_client_y() - scene.last_y
        scene.last_x = e.get_client_x()
        scene.last_y = e.get_client_y()
      }
      (model, @rabbita.none)
    }
    Up => {
      scene.dragging = false
      (model, @rabbita.none)
    }
  }
}

///|
fn subscriptions(_ : Model, emit : Emit[Msg]) -> @sub.Sub {
  @sub.batch([
    @sub.on_animation_frame(emit.map(ts => Frame(ts))),
    @sub.on_url_changed(emit.map(url => UrlChanged(url))),
  ])
}

///|
fn view(emit : Emit[Msg], model : Val[Model]) -> Val[Html] {
  let attrs = @html.Attrs::build()
    .on_wheel(e => emit(Wheel(e)))
    .on_pointerdown(e => emit(Down(e)))
    .on_pointermove(e => emit(Move(e)))
    .on_pointerup(_ => emit(Up))
  model.map(m => {
    @html.div(class="page", [
      @html.canvas(id="graph", attrs~, ([] : Array[Html])),
      @html.div(
        class="hud",
        @html.text(
          (
            $|fps \{m.fps.to_int()}  draw \{m.draw_ms.to_int()}ms
            $|\{m.status}
            $|on_url_changed: \{m.url_events} \{m.last_url}
          ),
        ),
      ),
    ])
  })
}

///|
fn main {
  scene.window_start = now()
  fn app() {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          {
            fps: 0.0,
            draw_ms: 0.0,
            status: "loading",
            url_events: 0,
            last_url: "",
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
