// Everything that changes every frame lives here, outside the Rabbita model:
// the graph, the simulation, the camera and the highlight sets. The model
// only holds what the DOM shows, so a frame does not re-render the page.

///|
const NO_NODE : Int32 = -1

///|
struct Scene {
  mut graph : @graph.Graph?
  mut show_hubs : Bool
  mut show_yanked : Bool
  mut show_isolated : Bool
  /// Per node: no edge to any node the other toggles leave visible.
  mut isolated : Array[Bool]
  /// Per node: left out of the layout and the metrics.
  mut hidden : Array[Bool]
  mut hub : Array[Bool]
  mut metrics : @graph.Metrics
  mut radius : Array[Double]
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
  mut width : Double
  mut height : Double
  mut hovered : Int32
  /// Hovered node and its direct neighbours.
  mut near : Array[Bool]
  mut selected : Int32
  /// Selected node and everything that depends on it.
  mut impact : Array[Bool]
  mut impact_count : Int32
  mut pointer_down : Bool
  mut dragged : Bool
  mut down_x : Double
  mut down_y : Double
  mut last_x : Double
  mut last_y : Double
}

///|
let scene : Scene = {
  graph: None,
  show_hubs: false,
  show_yanked: true,
  show_isolated: false,
  isolated: [],
  hidden: [],
  hub: [],
  metrics: { direct: [], transitive: [], owners: [], },
  radius: [],
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
  width: 0.0,
  height: 0.0,
  hovered: NO_NODE,
  near: [],
  selected: NO_NODE,
  impact: [],
  impact_count: 0,
  pointer_down: false,
  dragged: false,
  down_x: 0.0,
  down_y: 0.0,
  last_x: 0.0,
  last_y: 0.0,
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
  scene.hub = graph.mask(@graph.default_hubs)
  scene.px = Array::make(n, 0.0)
  scene.py = Array::make(n, 0.0)
  scene.placed = Array::make(n, false)
  scene.impact = Array::make(n, false)
  scene.near = Array::make(n, false)
  rebuild()
  skipped
}

///|
/// Recomputes visibility, metrics, sizes and colours, and restarts the
/// layout from the current positions.
fn rebuild() -> Unit {
  guard scene.graph is Some(graph) else { return }
  let n = graph.size()
  save_positions()
  let toggled = Array::makei(n, i => {
    (!scene.show_hubs && scene.hub[i]) ||
    (!scene.show_yanked && graph.yanked[i])
  })
  scene.isolated = Array::makei(n, i => {
    !graph.deps[i].iter().any(j => !toggled[j]) &&
    !graph.dependents[i].iter().any(j => !toggled[j])
  })
  scene.hidden = Array::makei(n, i => {
    toggled[i] || (!scene.show_isolated && scene.isolated[i])
  })
  scene.metrics = graph.metrics(excluded=scene.hidden)
  scene.radius = Array::makei(n, i => {
    let r = 2.5 + 1.6 * Double::from_int(scene.metrics.transitive[i]).sqrt()
    if r > 40.0 {
      40.0
    } else {
      r
    }
  })
  assign_colors(graph)
  let nodes = []
  let index = Array::make(n, NO_NODE)
  for i in 0..<n {
    if !scene.hidden[i] {
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
  let sim = @force.Simulation::new(nodes.length(), seed=1)
  let mut resumed = false
  for k, i in nodes {
    if scene.placed[i] {
      sim.set_position(k, scene.px[i], scene.py[i])
      resumed = true
    }
  }
  sim.add_force(@force.link(links, distance=30.0))
  sim.add_force(
    @force.many_body(
      strengths=nodes.map(i => -20.0 - 4.0 * scene.radius[i]),
      distance_max=600.0,
    ),
  )
  sim.add_force(@force.collide(nodes.map(i => scene.radius[i] + 1.5)))
  sim.add_force(@force.x(strength=0.03))
  sim.add_force(@force.y(strength=0.03))
  if resumed {
    sim.set_alpha(0.5)
  }
  scene.sim = Some(sim)
  scene.sim_nodes = nodes
  scene.sim_index = index
  if scene.selected != NO_NODE {
    select_node(scene.selected)
  }
}

///|
fn save_positions() -> Unit {
  guard scene.sim is Some(sim) else { return }
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
  if scene.auto_fit {
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
}

///|
/// Centres the camera on a node, keeping the zoom unless it is too far out
/// to see the node.
fn focus(i : Int32) -> Unit {
  guard position(i) is Some((x, y)) else { return }
  scene.auto_fit = false
  scene.scale = scene.scale.max(0.6)
  scene.cam_x = scene.width / 2.0 - x * scene.scale
  scene.cam_y = scene.height / 2.0 - y * scene.scale
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
