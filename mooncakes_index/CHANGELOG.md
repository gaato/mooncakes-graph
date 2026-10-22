# Changelog

All notable changes to `gaato/mooncakes_index` are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the
version is 0.x, a minor release (0.x → 0.y) may contain breaking changes; a
patch release never does. Every breaking change is listed with a migration
note.

## [Unreleased]

### Changed

- Depends on `moonbitlang/x` 0.5.6 (was 0.5.5). No API change.

## [0.1.0] - 2026-10-20

### Added

- **A reader for the registry index that `moon update` keeps.** `parse_line`
  reads a line into a `VersionRecord` (dependencies with their version, import
  name and path; dates; yank state; and the description, repository, license
  and keywords from `moon.mod`). `fs.read` reads the whole directory into
  `Module`s, counting broken lines instead of failing, and raises a typed
  `IndexError`.
- **Version helpers.** `Module::current` picks the version that stands for a
  module now; `compare_versions` and `release_line` order semantic versions
  and give the line they stay compatible within.
