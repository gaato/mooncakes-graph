#!/usr/bin/env python3
"""Independent reference reader for the mooncakes index.

Used for the M1 number gates and, until `mooncakes-graph versions` exists,
as the data source for the web spike.

  oracle.py versions        # natural JSONL, one line per version
  oracle.py modules         # current version's description etc., per module
  oracle.py stats           # gate numbers as JSON
  oracle.py top KEY         # every module ranked by KEY, TSV like `top -n 0`
"""
import glob
import json
import os
import sys


def index_dir():
    home = os.environ.get("MOON_HOME") or os.path.expanduser("~/.moon")
    return os.path.join(home, "registry", "index", "user")


# Index-only test data that mooncakes.io does not have.
ABSENT_OWNERS = {"test"}


def records():
    """All versions, modules sorted by name, versions in file order."""
    modules = []
    for path in glob.glob(os.path.join(index_dir(), "*", "*.index")):
        if os.path.basename(os.path.dirname(path)) in ABSENT_OWNERS:
            continue
        versions = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    versions.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        if versions:
            modules.append((versions[0]["name"], versions))
    modules.sort(key=lambda m: m[0])
    for _, versions in modules:
        yield from versions


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


def text(v):
    # Blank means absent; the CLI trims tab, newline, CR and space only.
    return v if isinstance(v, str) and v.strip("\t\n\r ") else None


def about(d):
    out = {"name": d["name"], "version": d["version"]}
    for key in ("description", "repository", "license"):
        if text(d.get(key)):
            out[key] = d[key]
    kw = [k for k in d.get("keywords") or [] if text(k)] if isinstance(d.get("keywords"), list) else []
    if kw:
        out["keywords"] = kw
    if text(d.get("yanked_reason")):
        out["yanked_reason"] = d["yanked_reason"]
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
    deps = [(m, t) for m, d in cur.items() for t in d["deps"]]
    return {
        "modules": len(names),
        "versions": len(rows),
        "modules_with_deps": sum(1 for d in cur.values() if d["deps"]),
        # Graph edges: to other modules in the index.
        "edges": sum(1 for m, t in deps if t in names and t != m),
        "dangling_edges": sum(1 for _, t in deps if t not in names),
        "all_yanked": sum(1 for vs in by.values() if all(v["yanked"] for v in vs)),
    }


def metrics(rows):
    by, cur = current(rows)
    names = set(by)
    rev = {n: set() for n in names}
    for m, d in cur.items():
        for t in d["deps"]:
            if t in names and t != m:
                rev[t].add(m)

    def owner(n):
        return n.split("/", 1)[0]

    out = {}
    for t in names:
        seen, stack = {t}, [t]
        while stack:
            x = stack.pop()
            for y in rev[x]:
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        out[t] = {
            "direct": len(rev[t]),
            "transitive": len(seen) - 1,
            "owners": len({owner(d) for d in rev[t]} - {owner(t)}),
        }
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stats"
    raw = list(records())
    rows = [natural(d) for d in raw]
    if cmd == "modules":
        _, cur = current([{**d, "yanked": bool(d.get("yanked"))} for d in raw])
        for name in sorted(cur, key=str.encode):
            line = json.dumps(about(cur[name]), ensure_ascii=False, separators=(",", ":"))
            sys.stdout.write(line + "\n")
    elif cmd == "versions":
        for r in rows:
            sys.stdout.write(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n")
    elif cmd == "stats":
        json.dump(stats(rows), sys.stdout, indent=2)
        sys.stdout.write("\n")
    elif cmd == "top":
        key = sys.argv[2] if len(sys.argv) > 2 else "transitive"
        m = metrics(rows)
        # Byte order on names, like the CLI.
        order = sorted(m, key=lambda n: (-m[n][key], n.encode()))
        sys.stdout.write("module\tdirect\ttransitive\towners\n")
        for n in order:
            r = m[n]
            sys.stdout.write(f"{n}\t{r['direct']}\t{r['transitive']}\t{r['owners']}\n")
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
