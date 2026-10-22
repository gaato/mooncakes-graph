name = "gaato/mooncakes_index"

version = "0.1.0"

import {
  "moonbitlang/x@0.5.6",
}

readme = "README.md"

repository = "https://github.com/gaato/mooncakes-graph"

license = "Apache-2.0"

keywords = [ "mooncakes", "registry", "index" ]

description = "Reader for the mooncakes.io registry index that `moon update` keeps under $MOON_HOME: one record per published version, with dependencies, dates and yank state."

source = "src"

preferred_target = "native"
