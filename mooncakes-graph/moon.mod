name = "gaato/mooncakes-graph"

version = "0.1.0"

import {
  "gaato/mooncakes_index@0.1.0",
  "cli/core@0.6.0",
  "moonbitlang/x@0.5.6",
}

readme = "README.md"

repository = "https://github.com/gaato/mooncakes-graph"

license = "Apache-2.0"

keywords = [ "mooncakes", "dependency-graph", "dependents", "cli" ]

description = "The mooncakes.io registry as a dependency graph: what depends on what, ranked by direct, transitive and other-owner dependents, with a tree(1)-like CLI."

source = "src"

preferred_target = "wasm"
