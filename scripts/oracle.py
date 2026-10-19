#!/usr/bin/env python3
"""Independent reference reader for the mooncakes index.

Used for the M1 number gates and, until `mooncakes-graph versions` exists,
as the data source for the web spike.

  oracle.py versions        # natural JSONL, one line per version
  oracle.py stats           # gate numbers as JSON
"""
import glob
import json
import os
import sys


def index_dir():
    home = os.environ.get("MOON_HOME") or os.path.expanduser("~/.moon")
    return os.path.join(home, "registry", "index", "user")


def records():
    for path in sorted(glob.glob(os.path.join(index_dir(), "*", "*.index"))):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue


def dep_version(v):
    # Object form: {"version", "alias"?} or a local {"path"} with no version.
    return v.get("version") if isinstance(v, dict) else v


def natural(d):
    out = {
        "name": d["name"],
        "version": d["version"],
        "created_at": d.get("created_at"),
        "deps": {k: dep_version(v) for k, v in (d.get("deps") or {}).items()},
        "yanked": bool(d.get("yanked")),
    }
    if d.get("deprecated"):
        out["deprecated"] = d["deprecated"]
    return out


def current(rows):
    """Latest non-yanked version per module (latest version if all yanked)."""
    by = {}
    for d in rows:
        by.setdefault(d["name"], []).append(d)
    cur = {}
    for name, vs in by.items():
        live = [v for v in vs if not v["yanked"]]
        cur[name] = (live or vs)[-1]
    return by, cur


def stats(rows):
    by, cur = current(rows)
    names = set(by)
    edges = [(m, t) for m, d in cur.items() for t in d["deps"]]
    direct = {}
    for m, t in edges:
        direct[t] = direct.get(t, 0) + 1
    return {
        "versions": len(rows),
        "modules": len(names),
        "modules_with_deps": sum(1 for d in cur.values() if d["deps"]),
        "edges": len(edges),
        "dangling_edges": sum(1 for _, t in edges if t not in names),
        "all_yanked": sum(1 for vs in by.values() if all(v["yanked"] for v in vs)),
        "direct_dependents": {
            k: direct.get(k, 0) for k in ("moonbitlang/x", "moonbitlang/async")
        },
    }


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stats"
    rows = [natural(d) for d in records()]
    if cmd == "versions":
        for r in rows:
            sys.stdout.write(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n")
    elif cmd == "stats":
        json.dump(stats(rows), sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
