///|
extern "js" fn set_alpha(
  ctx : @dom.CanvasRenderingContext2D,
  a : Double,
) -> Unit =
  #|(c, a) => { c.globalAlpha = a; }

///|
extern "js" fn prefers_dark() -> Bool =
  #|() => window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches

///|
/// Sizes the backing store to the CSS box times devicePixelRatio and returns
/// [dpr, css width, css height], or an empty array when the canvas is
/// missing.
extern "js" fn fit_canvas(id : String) -> FixedArray[Double] =
  #|(id) => {
  #|  const c = document.getElementById(id);
  #|  if (!c) return [];
  #|  const r = window.devicePixelRatio || 1;
  #|  const w = Math.round(c.clientWidth * r), h = Math.round(c.clientHeight * r);
  #|  if (c.width !== w) c.width = w;
  #|  if (c.height !== h) c.height = h;
  #|  return [r, c.clientWidth, c.clientHeight];
  #|}

///|
fn style(
  color : String,
) -> @js.Union3[String, @dom.CanvasGradient, @dom.CanvasPattern] {
  @js.Union3::from0(color)
}

///|
fn draw() -> Unit {
  guard fit_canvas("graph") is [dpr, w, h] else { return }
  scene.width = w
  scene.height = h
  guard @canvas.get_context2d("graph") is Some(ctx) else { return }
  guard scene.graph is Some(graph) && scene.sim is Some(sim) else { return }
  let dark = prefers_dark()
  ctx.reset_transform()
  ctx.clear_rect(0.0, 0.0, w * dpr, h * dpr)
  let s = scene.scale * dpr
  ctx.set_transform(s, 0.0, 0.0, s, scene.cam_x * dpr, scene.cam_y * dpr)
  let xs = sim.xs()
  let ys = sim.ys()
  let index = scene.sim_index
  let selecting = scene.selected != NO_NODE
  let hovered = scene.hovered
  let highlighted = fn(a : Int32, b : Int32) {
    if selecting {
      // An edge on a dependency path into the selection.
      scene.impact[a] && scene.impact[b]
    } else {
      a == hovered || b == hovered
    }
  }

  // Edges: one faint batch, then the highlighted ones on top.
  ctx.set_line_width(0.6 / scene.scale)
  ctx.set_stroke_style(
    style(if dark { "rgba(148,163,184,0.16)" } else { "rgba(71,85,105,0.16)" }),
  )
  ctx.begin_path()
  for a in scene.sim_nodes {
    for b in graph.deps[a] {
      if index[b] != NO_NODE && !highlighted(a, b) {
        ctx.move_to(xs[index[a]], ys[index[a]])
        ctx.line_to(xs[index[b]], ys[index[b]])
      }
    }
  }
  ctx.stroke()
  if selecting || hovered != NO_NODE {
    ctx.set_line_width(1.2 / scene.scale)
    ctx.set_stroke_style(style(if dark { "#fbbf24" } else { "#d97706" }))
    ctx.begin_path()
    for a in scene.sim_nodes {
      for b in graph.deps[a] {
        if index[b] != NO_NODE && highlighted(a, b) {
          ctx.move_to(xs[index[a]], ys[index[a]])
          ctx.line_to(xs[index[b]], ys[index[b]])
        }
      }
    }
    ctx.stroke()
  }

  // Nodes.
  for k, i in scene.sim_nodes {
    let faded = (selecting && !scene.impact[i]) ||
      (!selecting && hovered != NO_NODE && !scene.near[i])
    let fade = if faded { 0.15 } else { 1.0 }
    let alpha = fade * (if graph.yanked[i] { 0.35 } else { 1.0 })
    set_alpha(ctx, alpha)
    ctx.set_fill_style(style(scene.color[i]))
    ctx.begin_path()
    ctx.arc(xs[k], ys[k], scene.radius[i], 0.0, 6.283185307179586)
    ctx.fill()
  }
  set_alpha(ctx, 1.0)
  if selecting && index[scene.selected] != NO_NODE {
    let k = index[scene.selected]
    ctx.set_line_width(2.5 / scene.scale)
    ctx.set_stroke_style(style(if dark { "#f8fafc" } else { "#0f172a" }))
    ctx.begin_path()
    ctx.arc(
      xs[k],
      ys[k],
      scene.radius[scene.selected] + 3.0 / scene.scale,
      0.0,
      6.283185307179586,
    )
    ctx.stroke()
  }

  // Labels in screen space, so text stays the same size at any zoom.
  ctx.reset_transform()
  ctx.set_font("\{(12.0 * dpr).to_int()}px system-ui, sans-serif")
  ctx.set_fill_style(style(if dark { "#e5e7eb" } else { "#111827" }))
  let few_impacted = selecting && scene.impact_count <= 30
  for k, i in scene.sim_nodes {
    let screen_r = scene.radius[i] * scene.scale
    let wanted = i == hovered ||
      i == scene.selected ||
      (few_impacted && scene.impact[i]) ||
      (screen_r >= 10.0 && (!selecting || scene.impact[i]))
    if !wanted {
      continue
    }
    let sx = (xs[k] * scene.scale + scene.cam_x) * dpr
    let sy = (ys[k] * scene.scale + scene.cam_y) * dpr
    if sx < -200.0 || sy < -20.0 || sx > w * dpr + 20.0 || sy > h * dpr + 20.0 {
      continue
    }
    ctx.fill_text(graph.names[i], sx + (screen_r + 3.0) * dpr, sy + 4.0 * dpr)
  }
}
