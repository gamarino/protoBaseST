#!/usr/bin/env bash
# The chapters of docs/tutorial/ quote the programs of examples/tutorial/ (and the cluster chapters,
# 13-16, those of examples/cluster/), and must keep quoting them exactly. A chapter names its
# programs in comments, "<!-- example: examples/tutorial/X -->" or "examples/cluster/X"; a cluster
# program that needs an API not built yet lives in examples/cluster/pending/ as X.st.pending, which
# the test runner does not run (its README lists them and the plan task each one waits for);
# every non-blank line of every ```smalltalk and ```python block of the chapter must appear, in
# order within the block, in one of the programs it names. A program edited without its chapter,
# or the reverse, fails here. The programs themselves run as tests (tests/run_tests.sh), so the
# quoted code runs. Every numbered chapter must name at least one program that exists, and every
# lesson of examples/tutorial and examples/cluster (pending ones included) must be named by a chapter. Scope: code blocks only, not prose.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the documentation guard cannot run"; exit 1; }
python3 -I - "$REPO" <<'PY'
import glob, os, re, sys
repo = sys.argv[1]
bad, named, blocks_checked = [], set(), 0
chapters = sorted(glob.glob(os.path.join(repo, "docs/tutorial/[0-9][0-9]-*.md")))
if not chapters:
    bad.append("no chapter found in docs/tutorial")
for chapter in chapters:
    rel = os.path.relpath(chapter, repo)
    text = open(chapter, encoding="utf-8").read()
    programs = re.findall(r"<!-- example: (examples/(?:tutorial|cluster)/[^ ]+) -->", text)
    if not programs:
        bad.append("%s names no program (<!-- example: examples/tutorial/... or examples/cluster/... -->)" % rel)
    sources = {}
    for p in programs:
        path = os.path.join(repo, p)
        if not os.path.isfile(path):
            bad.append("%s names %s, which does not exist" % (rel, p)); continue
        named.add(p)
        sources[p] = [l.rstrip() for l in open(path, encoding="utf-8").read().split("\n")]
    blocks, cur = [], None
    for n, line in enumerate(text.split("\n"), 1):
        if cur is None and (line.startswith("```smalltalk") or line.startswith("```python")):
            cur = []
        elif cur is not None and line.startswith("```"):
            blocks.append(cur); cur = None
        elif cur is not None and line.strip():
            cur.append((n, line.rstrip()))
    for block in blocks:
        def found_in(lines):
            pos = 0
            for _, line in block:
                try:
                    pos = lines.index(line, pos) + 1
                except ValueError:
                    return False
            return True
        if not any(found_in(lines) for lines in sources.values()):
            first = block[0]
            bad.append("%s:%d: the block is not in %s, in order (first line: %s)"
                       % (rel, first[0], " or ".join(programs) or "any program", first[1].strip()))
        blocks_checked += 1
lessons = sorted(os.path.relpath(f, repo) for f in glob.glob(os.path.join(repo, "examples/tutorial/[0-9][0-9]_*"))
                 + glob.glob(os.path.join(repo, "examples/cluster/[0-9][0-9]_*"))
                 + glob.glob(os.path.join(repo, "examples/cluster/pending/[0-9][0-9]_*"))
                 if f.endswith(".st") or f.endswith(".sh") or f.endswith(".st.pending"))
for lesson in lessons:
    if lesson not in named and not lesson.endswith(".sh"):
        bad.append("%s is not named by any chapter" % lesson)
if bad:
    print("\n".join(bad)); sys.exit(1)
print("docs/tutorial: %d blocks in %d chapters are in their programs" % (blocks_checked, len(chapters)))
PY
