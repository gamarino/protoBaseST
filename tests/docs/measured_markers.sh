#!/usr/bin/env bash
# The figures the documentation owes (plan call IP6). The indexed-query documentation is written
# before the code it describes, so a figure that has not been measured yet is never invented: it is
# a marker "[measured in T<n>: <what is measured>]", where T<n> is the plan task (T0-T10) whose
# benchmark will fill it (spec section 7.3), and the task that measures it replaces the marker with
# the figure. The vectors phase (Addendum V, docs/superpowers/specs/2026-11-19-vectors-addendum.md)
# writes its drafts the same way, naming its own tasks: "[measured in V<n>: <text>]" for V0-V10 and
# "[measured in V-pin: <text>]" (the addendum's task names, section 7; the execution plan
# docs/superpowers/plans/2026-11-20-vectors.md numbers them otherwise and keeps these names). This
# guard lists every marker of docs/*.md, docs/tutorial/*.md and README.md and prints the count per
# task. It fails on a malformed marker (anything that opens "[measured" and is not one of the two
# forms) and on a task outside T0-T10, V0-V10 and V-pin. With MARKERS_FINAL=1 (the final task: T10
# for the queries, V9 for the vectors) any marker left is a failure.
# Scope: fenced code blocks and inline code spans are skipped, so a document can name the
# convention itself (`[measured in T<n>: ...]`); docs/superpowers (the specs and plans, which
# describe the convention) is not documentation of the library and is not scanned.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the marker guard cannot run"; exit 1; }
MARKERS_FINAL="${MARKERS_FINAL:-}" python3 -I - "$REPO" <<'PY'
import glob, os, re, sys
repo = sys.argv[1]
docs = sorted(glob.glob(repo + "/docs/*.md") + glob.glob(repo + "/docs/tutorial/*.md")) + [repo + "/README.md"]
marker = re.compile(r"\[measured\s+in\s+(T(\d+)|V(\d+)|V-pin):\s+[^\[\]]+\]")
bad, counts, total = [], {}, 0
for path in docs:
    rel = os.path.relpath(path, repo)
    text = open(path, encoding="utf-8").read()
    # blank out code, keeping line numbers and offsets
    text = re.sub(r"```.*?```", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    text = re.sub(r"`[^`\n]+`", lambda m: " " * len(m.group(0)), text)
    for m in re.finditer(r"\[measured\b", text):
        line = text.count("\n", 0, m.start()) + 1
        found = marker.match(text, m.start())
        if not found:
            bad.append("%s:%d: malformed marker (want [measured in T<n>: <text>] or [measured in V<n>: <text>]): %s"
                       % (rel, line, " ".join(text[m.start():m.start() + 60].split())))
            continue
        task = found.group(1)
        number = found.group(2) or found.group(3)
        if number is not None and int(number) > 10:
            bad.append("%s:%d: marker names %s, outside T0-T10 and V0-V10" % (rel, line, task))
            continue
        counts[task] = counts.get(task, 0) + 1
        total += 1
        if os.environ.get("MARKERS_FINAL") == "1":
            bad.append("%s:%d: marker left for %s, and MARKERS_FINAL=1: %s"
                       % (rel, line, task, " ".join(found.group(0)[:80].split())))
def task_order(task):
    # T0-T10 first, then V-pin, then V0-V10, each in task order
    if task.startswith("T"):
        return (0, int(task[1:]))
    return (1, -1) if task == "V-pin" else (1, int(task[1:]))
for task in sorted(counts, key=task_order):
    print("%s %d" % (task, counts[task]))
if bad:
    print("\n".join(bad)); sys.exit(1)
print("%d markers in %d documents, every one well formed" % (total, len(docs)))
PY
