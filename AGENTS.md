# Agent notes for mooncakes-graph

## Documentation

- Each published module (`mooncakes-graph/`, `mooncakes_index/`, `force/`)
  has a `README.md` that is a symbolic link to its `src/overview.mbt.md`, and
  mooncakes.io renders it as the module page. Write it for visitors: what the
  module is, how to install and use it, and what a caller must know. Keep
  design rationale, internal mechanics, verification procedures and facts
  that go stale (version pins, counts from the live index) out of it, because
  a visitor reads the page to decide whether and how to use the module. The
  repository's own `README.md` and the site are not module pages.
- Keep examples in `mbt check` fences: the file compiles with the package's
  tests, so a stale example fails `moon check` instead of misleading a reader.
- Link with absolute `https://` URLs inside the module directories: mooncakes
  serves those files away from the repository, where relative links break.
- Run `moon run scripts/docs_audit.mbtx --self-test` (also run by
  `scripts/gates.sh` and CI) after changing docs or public declarations.
- `scripts/docs_audit.mbtx` is identical in every gaato MoonBit repository.
  Copy it from gaato/discord.mbt rather than editing it here, so the repos do
  not drift; put repository differences in `scripts/docs_audit.json` and
  `scripts/docs_audit.allow`.
