#!/usr/bin/env bash
# Release helper for the library modules, adapted from gaato/mbt-sdk.
#
#   scripts/release.sh bump <module> <version>   set a module's version and every
#                                                sibling import of it, and move
#                                                its CHANGELOG [Unreleased]
#                                                entries under <version> (local edit)
#   scripts/release.sh check                     every published module has a
#                                                CHANGELOG with [Unreleased] first
#                                                and a heading for its version
#   scripts/release.sh publish [--dry-run]       publish, bottom-up, every listed
#                                                module whose version is not yet
#                                                in the mooncakes index
#
# Publishing is idempotent: a version already in the index is skipped, so only
# a version bump releases anything.
set -euo pipefail
cd "$(dirname "$0")/.."

# Bottom-up: a module is listed after everything it imports. The app module is
# `private = true` and never published.
PUBLISH_MODULES=(mooncakes_index force)

module_name() { sed -nE 's/^name = "(.*)"$/\1/p' "$1/moon.mod"; }
module_version() { sed -nE 's/^version = "(.*)"$/\1/p' "$1/moon.mod"; }

moon_home() { echo "${MOON_HOME:-$HOME/.moon}"; }

UNRELEASED='## [Unreleased]'

# Turns the [Unreleased] heading into [Unreleased] followed by a dated heading
# for <version>, so the entries that were under it now belong to <version>.
changelog_release() { # <module> <version>
  local file="$1/CHANGELOG.md" date; date=$(date +%F)
  [ -f "$file" ] || return 0
  if ! grep -qxF "$UNRELEASED" "$file"; then
    echo "warning: $file has no '$UNRELEASED' heading; not updated" >&2; return 0
  fi
  if grep -qF "## [$2] - " "$file"; then
    echo "  $file already has [$2]"; return 0
  fi
  awk -v u="$UNRELEASED" -v v="## [$2] - $date" '
    $0 == u { print; print ""; print v; inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && NF { entries = 1 }
    { print }
    END { if (!entries) print "warning: no entries under [Unreleased] for " v > "/dev/stderr" }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "  $file: [Unreleased] -> [$2] - $date"
}

index_has() { # <name> <version>
  local file="$(moon_home)/registry/index/user/$1.index"
  [ -f "$file" ] && grep -Eq "\"version\"[[:space:]]*:[[:space:]]*\"$2\"" "$file"
}

cmd=${1:-}; shift || true
case "$cmd" in
  bump)
    module=${1:?module}; version=${2:?version}
    name=$(module_name "$module")
    sed -i -E "s/^version = \".*\"$/version = \"$version\"/" "$module/moon.mod"
    for mod in */moon.mod; do
      sed -i -E "s|\"$name@[0-9][^\"]*\"|\"$name@$version\"|" "$mod"
    done
    echo "$name -> $version"; grep -l "$name@$version" */moon.mod | sed 's/^/  /'
    changelog_release "$module" "$version"
    ;;
  check)
    status=0
    for module in "${PUBLISH_MODULES[@]}"; do
      file="$module/CHANGELOG.md"; version=$(module_version "$module")
      if [ ! -f "$file" ]; then
        echo "$file is missing" >&2; status=1; continue
      fi
      if [ "$(grep -m1 '^## ' "$file")" != "$UNRELEASED" ]; then
        echo "$file: the first section must be '$UNRELEASED'" >&2; status=1
      fi
      if ! grep -qF "## [$version] - " "$file"; then
        echo "$file: no '## [$version] - <date>' heading for the version in moon.mod (use 'scripts/release.sh bump')" >&2; status=1
      fi
    done
    exit "$status"
    ;;
  publish)
    dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
    moon update >/dev/null
    pending=()
    for module in "${PUBLISH_MODULES[@]}"; do
      name=$(module_name "$module"); version=$(module_version "$module")
      if index_has "$name" "$version"; then
        echo "skip    $name@$version (already published)"; continue
      fi
      if [ "$dry" = 1 ]; then
        # `moon publish --dry-run` exits non-zero even when the server accepts
        # the dry run, so judge it by its output. A dependant of a module that
        # this run would publish first cannot be checked yet: its packaged copy
        # resolves dependencies from the registry.
        out=$(moon -C "$module" publish --dry-run 2>&1) || true
        if echo "$out" | grep -q 'Dry run completed successfully'; then
          echo "would   $name@$version"
        # moon says "not found in the registry" for a module that was never
        # published and "no version satisfies" for a new version of one that was.
        elif [ "${#pending[@]}" -gt 0 ] && echo "$out" | grep -qE "dependency \`($(IFS='|'; echo "${pending[*]}"))\`.*(not found in the registry|no version satisfies)"; then
          echo "would   $name@$version (after ${pending[*]}; not checkable before they exist)"
        else
          echo "$out"; exit 1
        fi
        pending+=("$name")
      else
        echo "publish $name@$version"
        moon -C "$module" publish
        moon update >/dev/null   # dependants resolve the new version from the index
      fi
    done
    ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
