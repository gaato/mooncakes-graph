// Everything that changes every frame lives here, outside the Rabbita model:
// the graph, the simulation, the camera and the highlight sets. The model
// only holds what the DOM shows, so a frame does not re-render the page.

///|
const NO_NODE : Int32 = -1

///|
struct Scene {
  mut graph : @graph.Graph?
  mut show_yanked : Bool
  mut show_isolated : Bool
  /// With a selection, lay out only the modules related to it.
  mut focused : Bool
  /// The current simulation is a focus layout (its positions are not the
  /// full map's, so they are not saved over it).
  mut focus_layout : Bool
  /// Per node: no edge to any node the other toggles leave visible.
  mut isolated : Array[Bool]
  /// Per node: left out of the layout and the metrics.
  mut hidden : Array[Bool]
  mut metrics : @graph.Metrics
  /// Drawn radius: `base_radius`, capped lower in a focus layout where a
  /// hub would otherwise cover the few modules around it.
  mut radius : Array[Double]
  mut base_radius : Array[Double]
  mut color : Array[String]
  /// Last known position per node, carried across simulation rebuilds.
  mut px : Array[Double]
  mut py : Array[Double]
  mut placed : Array[Bool]
  mut sim : @force.Simulation?
  /// Simulation index -> node, and node -> simulation index (or NO_NODE).
  mut sim_nodes : Array[Int32]
  mut sim_index : Array[Int32]
  mut cam_x : Double
  mut cam_y : Double
  mut scale : Double
  /// Keep the whole map in view until the user pans or zooms.
  mut auto_fit : Bool
  /// Keep this node centred (while the layout still moves it) until the
  /// user pans or zooms.
  mut follow : Int32
  mut width : Double
  mut height : Double
  mut hovered : Int32
  /// Hovered node and its direct neighbours.
  mut near : Array[Bool]
  mut selected : Int32
  /// Selected node and everything that depends on it.
  mut impact : Array[Bool]
  /// Everything the selected node depends on, toggles notwithstanding.
  mut upstream : Array[Bool]
  /// Transitive dependents counted over the whole graph, for sizing nodes
  /// that a toggle leaves out of `metrics`.
  mut full_transitive : Array[Int32]
  mut impact_count : Int32
  mut pointer_down : Bool
  mut dragged : Bool
  mut down_x : Double
  mut down_y : Double
  mut last_x : Double
  mut last_y : Double
  /// Active pointers (touches) by pointerId, in canvas CSS pixels.
  pointers : Map[Int32, (Double, Double)]
  /// Finger distance and midpoint at the previous pinch step.
  mut pinch_dist : Double
  mut pinch_x : Double
  mut pinch_y : Double
}

///|
let scene : Scene = {
  graph: None,
  show_yanked: true,
  show_isolated: false,
  focused: true,
  focus_layout: false,
  isolated: [],
  hidden: [],
  metrics: { direct: [], transitive: [], owners: [], },
  radius: [],
  base_radius: [],
  color: [],
  px: [],
  py: [],
  placed: [],
  sim: None,
  sim_nodes: [],
  sim_index: [],
  cam_x: 0.0,
  cam_y: 0.0,
  scale: 1.0,
  auto_fit: true,
  follow: NO_NODE,
  width: 0.0,
  height: 0.0,
  hovered: NO_NODE,
  near: [],
  selected: NO_NODE,
  impact: [],
  upstream: [],
  full_transitive: [],
  impact_count: 0,
  pointer_down: false,
  dragged: false,
  down_x: 0.0,
  down_y: 0.0,
  last_x: 0.0,
  last_y: 0.0,
  pointers: Map([]),
  pinch_dist: 0.0,
  pinch_x: 0.0,
  pinch_y: 0.0,
}

///|
/// Distinct colours for the owners with the most visible modules; everyone
/// else is grey.
let palette : Array[String] = [
  "#2563eb", "#dc2626", "#16a34a", "#d97706", "#9333ea", "#0891b2", "#db2777", "#65a30d",
  "#ea580c", "#4f46e5", "#0d9488", "#c026d3",
]

///|
let other_color : String = "#9ca3af"

///|
fn load_graph(text : String) -> Int32 {
  let records = []
  let mut skipped = 0
  for line in text.split("\n") {
    if line.is_empty() {
      continue
    }
    records.push(@mooncakes_index.parse_line(line)) catch {
      _ => skipped += 1
    }
  }
  let graph = @graph.Graph::from_records(records)
  let n = graph.size()
  scene.graph = Some(graph)
  scene.px = Array::make(n, 0.0)
  scene.py = Array::make(n, 0.0)
  scene.placed = Array::make(n, false)
  scene.impact = Array::make(n, false)
  scene.upstream = Array::make(n, false)
  scene.full_transitive = graph.metrics().transitive
  scene.near = Array::make(n, false)
  rebuild()
  skipped
}

///|
/// Recomputes visibility, metrics, sizes and colours after a toggle, then
/// lays the map out again.
fn rebuild() -> Unit {
  guard scene.graph is Some(graph) else { return }
  let n = graph.size()
  let toggled = Array::makei(n, i => !scene.show_yanked && graph.yanked[i])
  scene.isolated = Array::makei(n, i => {
    !graph.deps[i].iter().any(j => !toggled[j]) &&
    !graph.dependents[i].iter().any(j => !toggled[j])
  })
  scene.hidden = Array::makei(n, i => {
    toggled[i] || (!scene.show_isolated && scene.isolated[i])
  })
  scene.metrics = graph.metrics(excluded=scene.hidden)
  scene.base_radius = Array::makei(n, i => {
    let t = if scene.hidden[i] {
      scene.full_transitive[i]
    } else {
      scene.metrics.transitive[i]
    }
    let r = 2.5 + 1.6 * Double::from_int(t).sqrt()
    if r > 40.0 {
      40.0
    } else {
      r
    }
  })
  assign_colors(graph)
  relayout()
}

///|
/// Restarts the layout for the current selection: the full map, or in focus
/// mode the selected module, everything that depends on it and what it
/// depends on directly.
fn relayout() -> Unit {
  guard scene.graph is Some(graph) else { return }
  let n = graph.size()
  save_positions()
  select_node(scene.selected)
  let focus = scene.focused && scene.selected != NO_NODE
  scene.radius = if focus {
    scene.base_radius.map(r => r.min(14.0))
  } else {
    scene.base_radius
  }
  let in_layout = if focus {
    Array::makei(n, i => scene.impact[i] || scene.upstream[i])
  } else {
    scene.hidden.map(h => !h)
  }
  let nodes = []
  let index = Array::make(n, NO_NODE)
  for i in 0..<n {
    if in_layout[i] {
      index[i] = nodes.length()
      nodes.push(i)
    }
  }
  let links = []
  for a in nodes {
    for b in graph.deps[a] {
      if index[b] != NO_NODE {
        links.push((index[a], index[b]))
      }
    }
  }
  // Every setting below has one value per node and every link joins two
  // laid-out nodes, so the forces always fit.
  let sim = new_simulation(nodes, links) catch {
    e => abort("mooncakes-graph: layout rejected: \{(e : Error)}")
  }
  let mut resumed = false
  for k, i in nodes {
    if scene.placed[i] {
      sim.set_position(k, x=scene.px[i], y=scene.py[i])
      resumed = true
    }
  }
  if resumed && !focus {
    sim.set_alpha(0.5)
  }
  scene.sim = Some(sim)
  scene.sim_nodes = nodes
  scene.sim_index = index
  scene.focus_layout = focus
  if focus {
    // The related modules gather from where they sat on the full map.
    scene.follow = NO_NODE
    scene.auto_fit = true
  }
}

///|
/// The map's layout: linked modules pull together, all repel, none overlap,
/// and a weak pull to the origin keeps islands from drifting off.
fn new_simulation(
  nodes : Array[Int32],
  links : Array[(Int32, Int32)],
) -> @force.Simulation raise @force.ForceError {
  let sim = @force.Simulation::new(nodes.length(), seed=1)
  sim.add_force(@force.link(links, distance=All(30)))
  sim.add_force(
    @force.many_body(
      strength=Each(nodes.map(i => -20.0 - 4.0 * scene.radius[i])),
      distance_max=600.0,
    ),
  )
  sim.add_force(
    @force.collide(radius=Each(nodes.map(i => scene.radius[i] + 1.5))),
  )
  sim.add_force(@force.x(strength=All(0.03)))
  sim.add_force(@force.y(strength=All(0.03)))
  sim
}

///|
fn save_positions() -> Unit {
  guard scene.sim is Some(sim) && !scene.focus_layout else { return }
  let xs = sim.xs()
  let ys = sim.ys()
  for k, i in scene.sim_nodes {
    scene.px[i] = xs[k]
    scene.py[i] = ys[k]
    scene.placed[i] = true
  }
}

///|
fn assign_colors(graph : @graph.Graph) -> Unit {
  let counts : Map[String, Int32] = Map([])
  for i, owner in graph.owners {
    if !scene.hidden[i] {
      counts[owner] = counts.get(owner).unwrap_or(0) + 1
    }
  }
  let ranked = counts.to_array()
  ranked.sort_by((a, b) => {
    let c = b.1.compare(a.1)
    if c != 0 {
      c
    } else {
      @mooncakes_index.compare_names(a.0, b.0)
    }
  })
  let color_of : Map[String, String] = Map([])
  for k, entry in ranked {
    if k >= palette.length() {
      break
    }
    color_of[entry.0] = palette[k]
  }
  scene.color = graph.owners.map(o => color_of.get(o).unwrap_or(other_color))
}

///|
fn step() -> Unit {
  guard scene.sim is Some(sim) else { return }
  if sim.alpha >= sim.alpha_min {
    sim.tick()
  }
  if scene.follow != NO_NODE {
    follow_node(scene.follow, 0.2)
  } else if scene.auto_fit {
    fit_view(0.15)
  }
}

///|
/// Moves the camera toward a view of every visible node; `ease` 1 jumps.
fn fit_view(ease : Double) -> Unit {
  guard scene.sim is Some(sim) && sim.node_count() > 0 else { return }
  guard scene.width > 0.0 && scene.height > 0.0 else { return }
  let xs = sim.xs()
  let ys = sim.ys()
  let mut x0 = xs[0]
  let mut x1 = xs[0]
  let mut y0 = ys[0]
  let mut y1 = ys[0]
  for k in 0..<xs.length() {
    let r = scene.radius[scene.sim_nodes[k]]
    x0 = x0.min(xs[k] - r)
    x1 = x1.max(xs[k] + r)
    y0 = y0.min(ys[k] - r)
    y1 = y1.max(ys[k] + r)
  }
  let pad = 24.0
  let s = ((scene.width - 2.0 * pad) / (x1 - x0)).min(
    (scene.height - 2.0 * pad) / (y1 - y0),
  )
  let target_scale = s.min(4.0)
  let target_x = scene.width / 2.0 - (x0 + x1) / 2.0 * target_scale
  let target_y = scene.height / 2.0 - (y0 + y1) / 2.0 * target_scale
  scene.scale += (target_scale - scene.scale) * ease
  scene.cam_x += (target_x - scene.cam_x) * ease
  scene.cam_y += (target_y - scene.cam_y) * ease
}

///|
/// Node position in world coordinates, if the node is laid out.
fn position(i : Int32) -> (Double, Double)? {
  guard scene.sim is Some(sim) && scene.sim_index[i] != NO_NODE else {
    return None
  }
  let k = scene.sim_index[i]
  Some((sim.xs()[k], sim.ys()[k]))
}

///|
/// The visible node under a point in CSS pixels, nearest first.
fn node_at(sx : Double, sy : Double) -> Int32 {
  guard scene.sim is Some(sim) else { return NO_NODE }
  let wx = (sx - scene.cam_x) / scene.scale
  let wy = (sy - scene.cam_y) / scene.scale
  let slack = 4.0 / scene.scale
  let xs = sim.xs()
  let ys = sim.ys()
  let mut best = NO_NODE
  let mut best_d = 1.0e300
  for k in 0..<xs.length() {
    let i = scene.sim_nodes[k]
    let dx = xs[k] - wx
    let dy = ys[k] - wy
    let d = (dx * dx + dy * dy).sqrt()
    if d <= scene.radius[i] + slack && d < best_d {
      best = i
      best_d = d
    }
  }
  best
}

///|
fn select_node(i : Int32) -> Unit {
  guard scene.graph is Some(graph) else { return }
  scene.impact.fill(false)
  scene.upstream.fill(false)
  scene.selected = i
  scene.impact_count = 0
  if i == NO_NODE {
    return
  }
  scene.impact[i] = true
  for d in graph.transitive_dependents(i, excluded=scene.hidden) {
    scene.impact[d] = true
    scene.impact_count += 1
  }
  for d in graph.transitive_deps(i) {
    scene.upstream[d] = true
  }
}

///|
/// Starts following a node: the camera glides to it and keeps it centred.
fn focus(i : Int32) -> Unit {
  scene.auto_fit = false
  scene.follow = i
}

///|
/// Stops any automatic camera movement; called when the user takes over.
fn release_camera() -> Unit {
  scene.auto_fit = false
  scene.follow = NO_NODE
}

///|
fn follow_node(i : Int32, ease : Double) -> Unit {
  guard position(i) is Some((x, y)) else { return }
  // Zoom in far enough to tell the node's neighbourhood apart.
  let target_scale = scene.scale.max(0.6)
  scene.scale += (target_scale - scene.scale) * ease
  let target_x = scene.width / 2.0 - x * scene.scale
  let target_y = scene.height / 2.0 - y * scene.scale
  scene.cam_x += (target_x - scene.cam_x) * ease
  scene.cam_y += (target_y - scene.cam_y) * ease
}

///|
fn set_hovered(i : Int32) -> Unit {
  if i == scene.hovered {
    return
  }
  guard scene.graph is Some(graph) else { return }
  scene.near.fill(false)
  scene.hovered = i
  if i == NO_NODE {
    return
  }
  scene.near[i] = true
  for j in graph.deps[i] {
    scene.near[j] = true
  }
  for j in graph.dependents[i] {
    scene.near[j] = true
  }
}

///|
/// Zooms by `k` about a point in canvas CSS pixels.
fn zoom_at(k : Double, ox : Double, oy : Double) -> Unit {
  let k = (scene.scale * k).clamp(min=0.02, max=20.0) / scene.scale
  scene.cam_x = ox - (ox - scene.cam_x) * k
  scene.cam_y = oy - (oy - scene.cam_y) * k
  scene.scale = scene.scale * k
}

///|
/// Distance and midpoint of the first two active pointers.
fn pinch_geometry() -> (Double, Double, Double)? {
  let pts = scene.pointers.values().take(2).collect()
  guard pts is [(x0, y0), (x1, y1)] else { return None }
  let d = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
  Some((d, (x0 + x1) / 2.0, (y0 + y1) / 2.0))
}

///|
fn start_pinch() -> Unit {
  if pinch_geometry() is Some((d, mx, my)) {
    scene.pinch_dist = d
    scene.pinch_x = mx
    scene.pinch_y = my
  }
}
