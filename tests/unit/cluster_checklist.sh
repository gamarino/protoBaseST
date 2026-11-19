#!/usr/bin/env bash
# The checklist of proto_db's cluster tests (spec 6.2): every test function of the
# tests/unit/test_cluster_*.py files of proto_db v2.0.0rc4 has one row in cluster_checklist.tsv,
# and every row is one of:
#   ported    <protoBaseST .st test file, repo-relative>  <family> the file exists and the family
#                                                                   is one of its check labels, whole:
#                                                                   the string of a `that: '...'` or a
#                                                                   `check value: '...'` (outside the
#                                                                   comments, '' read as '); never a
#                                                                   prefix, never comment text. A .sh
#                                                                   test (tests/cluster, real
#                                                                   processes) names its check labels
#                                                                   in lines `cluster_check '<label>'`
#                                                                   (_cluster.sh), each run once the
#                                                                   assertions of that check passed
#   deferred  <task number, 19..28, or a lettered task of that range, such as 22b, that the cluster
#              plan has as a '### Task <id>:' heading>  <reason>  Phase C ports it (the shell,
#                                                                   transport, storage, processes)
#   n/a       <tiered | DEPTH = 1 | Python-only API>  <reason>     it does not apply to the port
# Columns are tab-separated: proto_db file::function, status, then the two fields above. Blank
# lines and lines starting with '#' are comments. The check fails on a function without a row, a
# row for a function the tag does not have, a duplicate row, a malformed row, a missing file or a
# family that is not a whole check label of its file, and prints the counts, then the deferred
# rows grouped by task. With CHECKLIST_FINAL=1 (the final gate, plan Task 30) every deferred row
# is an error too. The functions are listed from the tag with git show (the protoBase checkout is
# only read). Without a checkout at the default path, and none named, it is skipped (exit 77); a
# checkout named explicitly (PROTOBASE_REPO set by the caller: PROTOBASE_REPO_EXPLICIT=1 under
# tests/run_tests.sh, which always exports PROTOBASE_REPO, or PROTOBASE_REPO set when run directly)
# that is missing or lacks the tag, or one present at the default path that lacks the tag, is a
# failure, not a skip.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PB="${PROTOBASE_REPO:-$REPO/../ProtoBase}"
TAG=v2.0.0rc4
explicit="${PROTOBASE_REPO_EXPLICIT-${PROTOBASE_REPO:+1}}"
if [[ -z "$explicit" && ! -e "$PB" ]]; then
    echo "SKIP: no protoBase checkout"
    exit 77
fi
if ! git -C "$PB" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "FAIL: $PB is not a protoBase checkout holding the tag $TAG"
    exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the checklist cannot run"; exit 1; }

files="$(git -C "$PB" ls-tree --name-only "$TAG" tests/unit/ | grep -E '^tests/unit/test_cluster_[A-Za-z0-9_]*\.py$')"
[[ -n "$files" ]] || { echo "FAIL: no tests/unit/test_cluster_*.py at $TAG"; exit 1; }
list="$(for f in $files; do
    git -C "$PB" show "$TAG:$f" | grep -E '^def test_|^    def test_' \
        | sed -E 's/^ *def (test_[A-Za-z0-9_]*).*/\1/' | sed "s|^|$(basename "$f")::|"
done)"

plan="$REPO/docs/superpowers/plans/2026-11-13-cluster-mode.md"
lettered="$(sed -n -E 's/^### Task ([0-9]+[a-z]):.*/\1/p' "$plan" 2>/dev/null | tr '\n' ' ')"

python3 -I - "$REPO" "$HERE/cluster_checklist.tsv" "$list" "$(printf '%s\n' $files | wc -l)" "${CHECKLIST_FINAL:-0}" "$lettered" <<'PY'
import os, re, sys
repo, table, listing, nfiles = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
final = sys.argv[5] == "1"
planned = set(sys.argv[6].split())       # the lettered tasks of the plan ('### Task 22b:')


def labels_of(text):
    """The check labels of a protoST test file: the string literal that follows `that:` or
    `check value:`, scanning past comments (double quotes) and other strings, '' read as '."""
    found, i, n = set(), 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = text.find('"', i + 1)
            i = n if j < 0 else j + 1
        elif ch == "'":
            j, buf = i + 1, []
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        buf.append("'")
                        j += 2
                        continue
                    break
                buf.append(text[j])
                j += 1
            before = text[max(0, i - 40):i].rstrip()
            if before.endswith("that:") or before.endswith("check value:"):
                found.add("".join(buf))
            i = j + 1
        elif ch == "$" and i + 1 < n:
            i += 2                      # a character literal ($' or $") is neither
        else:
            i += 1
    return found

def sh_labels_of(text):
    """The check labels of a .sh test: the single-quoted text of each line that is exactly
    `cluster_check '<label>'` (indentation allowed; no quote inside the label)."""
    return {m.group(1) for m in re.finditer(r"^[ \t]*cluster_check '([^'\n]+)'[ \t]*$", text, re.M)}

functions = [l.strip() for l in listing.splitlines() if l.strip()]
errors = []
seen_fn = set()
for f in functions:
    if f in seen_fn:
        errors.append("the tag defines %s twice: one row cannot tell them apart" % f)
    seen_fn.add(f)
rows = {}
counts = {"ported": 0, "deferred": 0, "n/a": 0}
NA = ("tiered", "DEPTH = 1", "Python-only API")
texts = {}
deferred = {}
if not os.path.exists(table):
    errors.append("no table: %s" % table)
else:
    for n, line in enumerate(open(table, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        where = "line %d" % n
        if len(cols) != 4 or not all(c.strip() for c in cols):
            errors.append("%s: not four non-empty tab-separated columns: %r" % (where, line))
            continue
        key, status, a, b = cols
        if key in rows:
            errors.append("%s: a second row for %s" % (where, key))
            continue
        rows[key] = status
        if key not in seen_fn:
            errors.append("%s: %s is not a test function of the tag" % (where, key))
        if status == "ported":
            path = os.path.join(repo, a)
            if not (a.endswith(".st") or a.endswith(".sh")) or not os.path.isfile(path):
                errors.append("%s: %s names a missing protoBaseST test file %s" % (where, key, a))
                continue
            if path not in texts:
                text = open(path, encoding="utf-8").read()
                texts[path] = sh_labels_of(text) if a.endswith(".sh") else labels_of(text)
            if b not in texts[path]:
                errors.append("%s: %s: %r is not a check label of %s" % (where, key, b, a))
                continue
        elif status == "deferred":
            task = re.fullmatch(r"([0-9]+)([a-z]?)", a)
            if not task or not 19 <= int(task.group(1)) <= 28:
                errors.append("%s: %s: deferred to %r, not a Phase C task (19..28, or one with a letter: 22b)" % (where, key, a))
                continue
            if task.group(2) and a not in planned:
                errors.append("%s: %s: deferred to Task %s, which the cluster plan has no heading for" % (where, key, a))
                continue
            if len(b.split()) < 6:
                errors.append("%s: %s: the deferral needs a specific reason" % (where, key))
                continue
            deferred.setdefault((int(task.group(1)), task.group(2)), []).append(key)
            if final:
                errors.append("%s: %s is still deferred to Task %s (CHECKLIST_FINAL=1)" % (where, key, a))
        elif status == "n/a":
            if a not in NA:
                errors.append("%s: %s: n/a reason %r is none of %s" % (where, key, a, ", ".join(NA)))
                continue
            if len(b.split()) < 6:
                errors.append("%s: %s: the n/a row needs a specific reason" % (where, key))
                continue
        else:
            errors.append("%s: %s: unknown status %r" % (where, key, status))
            continue
        counts[status] += 1
for f in functions:
    if f not in rows:
        errors.append("no row for %s" % f)
for e in errors:
    print("FAIL: " + e)
print("%d files, %d test functions, %d rows" % (nfiles, len(functions), len(rows)))
print("ported %d, deferred %d, n/a %d" % (counts["ported"], counts["deferred"], counts["n/a"]))
for task in sorted(deferred):
    print("deferred to Task %d%s (%d):" % (task[0], task[1], len(deferred[task])))
    for key in deferred[task]:
        print("  " + key)
if errors:
    print("FAIL: %d checklist errors" % len(errors))
    sys.exit(1)
print("ok")
PY
