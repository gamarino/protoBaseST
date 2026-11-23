#!/usr/bin/env bash
# Guards the protoST floor statements (final review M2): the README states the floor ("protoST
# X.Y.Z is the floor"), and no other tracked document, module or test may state an older one as
# current. A sentence fails when it says "protoST <older> or newer/later", "<older> floor", or
# "floor (protoST <older>)" / "floor is <older>" / "floor of <older>", unless it is about the past
# (it says was, were, when, while, had, moved, replacing or earlier). The history is exempt:
# CHANGELOG.md, docs/changelog-*.md, docs/decisions.md, docs/deviations.md, docs/not-done.md and
# the specs and plans (docs/superpowers/, .superpowers/), as are tests/audit/ and the runner's
# fixtures. Only these phrasings are checked; a stale statement in other words is the review's to
# find.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the floor guard cannot run"; exit 1; }
cd "$REPO" || exit 1
git ls-files '*.md' '*.st' '*.sh' | python3 -I -c '
import re, sys
files = [l.strip() for l in sys.stdin if l.strip()]
m = re.search(r"protoST (\d+)\.(\d+)\.(\d+) is the floor", open("README.md", encoding="utf-8").read())
if not m:
    print("FAIL: README.md does not state the floor (\"protoST X.Y.Z is the floor\")"); sys.exit(1)
floor = tuple(map(int, m.groups()))
skip = {"CHANGELOG.md", "docs/decisions.md", "docs/deviations.md", "docs/not-done.md"}
skip_prefixes = ("docs/superpowers/", ".superpowers/", "docs/changelog-", "tests/audit/", "tests/runner/fixtures/")
past = re.compile(r"\b(was|were|when|while|had|moved|replacing|earlier)\b", re.I)
V = r"(\d+\.\d+\.\d+)"
patterns = [re.compile(r"protoST(?: binary, version)? " + V + r",? or (?:newer|later)"),
            re.compile(V + r" floor\b"),
            re.compile(r"\bfloor\b,? (?:\(|is |of )?(?:protoST )?" + V)]
bad, checked = [], 0
for path in files:
    if path in skip or path.startswith(skip_prefixes):
        continue
    checked += 1
    text = re.sub(r"\s+", " ", open(path, encoding="utf-8", errors="replace").read())
    for sentence in re.split(r"(?<=[.;])\s", text):
        for p in patterns:
            for hit in p.finditer(sentence):
                version = tuple(map(int, hit.group(1).split(".")))
                if version < floor and not past.search(sentence):
                    bad.append("%s: states %s as the floor (README: %s): %s" % (path, hit.group(1), ".".join(map(str, floor)), sentence[:200]))
for line in bad:
    print("FAIL: " + line)
if bad:
    sys.exit(1)
print("ok: %d files, no floor below %s stated as current" % (checked, ".".join(map(str, floor))))
'
