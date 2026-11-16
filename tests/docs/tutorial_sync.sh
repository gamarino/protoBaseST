#!/usr/bin/env bash
# The tutorial and its test must agree: every non-blank line of every ```smalltalk block of
# docs/tutorial/erp.md must appear, in order, in tests/docs/tutorial_snippets.st (which adds its own
# assertion lines between them). A tutorial edited without the test, or the reverse, fails here.
# Also: every "=> value" line must be followed in the test by an assertion that contains that value.
# Scope: code blocks and their => lines only, not prose. docs/reference.md and the README's API
# table are guarded by reference_selectors.sh.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the documentation guard cannot run"; exit 1; }
check() {
python3 -I - "$1" "$2" <<'PY'
import sys
doc, test = sys.argv[1], sys.argv[2]
blocks, cur = [], None
for n, line in enumerate(open(doc, encoding="utf-8").read().split("\n"), 1):
    if line.startswith("```smalltalk"):
        cur = []
    elif line.startswith("```") and cur is not None:
        blocks.append(cur); cur = None
    elif cur is not None and line.strip():
        cur.append((n, line.rstrip()))
lines = [l.rstrip() for l in open(test, encoding="utf-8").read().split("\n")]
pos, checked, bad = 0, 0, []
for block in blocks:
    for n, line in block:
        try:
            i = lines.index(line, pos)
        except ValueError:
            bad.append("%s:%d is not in the test (in order): %s" % (doc, n, line.strip()))
            continue
        if "\"=> " in line:
            value = line.split("\"=> ", 1)[1].rsplit("\"", 1)[0]
            nxt = lines[i + 1]
            if not (nxt.startswith("c that:") and (value in nxt or value.replace("'", "''") in nxt)):
                bad.append("%s:%d states => %s but the assertion after it does not" % (doc, n, value))
        pos = i + 1
        checked += 1
if not blocks:
    bad.append("no smalltalk block found in " + doc)
if bad:
    print("\n".join(bad)); sys.exit(1)
print("%s: %d lines in %d blocks are in the test, in order" % (doc.split("/")[-1], checked, len(blocks)))
PY
}
check "$REPO/docs/tutorial/erp.md" "$HERE/tutorial_snippets.st" || exit 1
check "$REPO/README.md" "$HERE/readme_quickstart.st" || exit 1
