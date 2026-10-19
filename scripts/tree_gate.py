#!/usr/bin/env python3
"""Checks that `dependents`/`deps` draw trees exactly as tree(1) would.

For each case, the structure from `-J` is written as a tab file and drawn by
`tree --fromtabfile`; its lines (minus the file-name root level and the
report, whose wording differs) must equal the CLI's text output, and tree's
own -J of that file must nest the same names.

tree pads its "│" columns with U+00A0 in UTF-8 locales; we print plain
spaces on purpose (they grep and paste cleanly), so the comparison treats
the two as equal.

  tree_gate.py CLI
"""
import json
import subprocess
import sys
import tempfile

CASES = [
    ["dependents", "gaato/http"],
    ["dependents", "Milky2018/xml"],
    ["dependents", "moonbitlang/regexp", "-L", "2"],
    ["deps", "moonbit-community/rabbita"],
    ["deps", "mizchi/bit"],
    ["deps", "gaato/discord", "-L1"],
]


def run(*args):
    return subprocess.run(args, check=False, capture_output=True, text=True).stdout


def label(node):
    return node["name"] + (" (*)" if node.get("duplicate") else "")


def tab_lines(node, depth, out):
    out.append("\t" * depth + label(node))
    for c in node.get("contents", []):
        tab_lines(c, depth + 1, out)


def names(node):
    return [node["name"], [names(c) for c in node.get("contents", [])]]


def main():
    cli = sys.argv[1]
    failed = 0
    for case in CASES:
        ours_json = json.loads(run(cli, *case, "-J", "--noreport"))
        ours_text = run(cli, *case, "--noreport").splitlines()
        lines = []
        for root in ours_json:
            tab_lines(root, 0, lines)
        with tempfile.NamedTemporaryFile("w", suffix=".tab", delete=False) as f:
            f.write("\n".join(lines) + "\n")
            tab = f.name
        drawn = run("tree", "--noreport", "--fromtabfile", tab).splitlines()[1:]
        # Strip the level tree adds under its file-name root.
        drawn = [line[4:].replace("\u00a0", " ") for line in drawn]
        tree_json = json.loads(run("tree", "-J", "--noreport", "--fromtabfile", tab))
        tree_names = [names(c) for c in tree_json[0]["contents"]]
        def relabel(ns, src):
            return [[label(s), relabel(n[1], s.get("contents", []))] for n, s in zip(ns, src)]

        our_names = relabel([names(r) for r in ours_json], ours_json)
        ok = drawn == ours_text and tree_names == our_names
        print(("ok   " if ok else "FAIL ") + " ".join(case))
        if not ok:
            failed = 1
            for a, b in zip(drawn, ours_text):
                if a != b:
                    print(f"  tree: {a!r}\n  ours: {b!r}")
                    break
    sys.exit(failed)


if __name__ == "__main__":
    main()
