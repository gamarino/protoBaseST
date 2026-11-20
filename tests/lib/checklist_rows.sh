# Shared by tests/unit/cluster_checklist.sh and tests/unit/queries_checklist.sh: the table parser
# and the row rules of a checklist of proto_db's tests (a source file, not a test; the runner skips
# it). A table row is `proto_db file::function <TAB> status <TAB> a <TAB> b`, and the status is:
#   ported    <protoBaseST .st/.sh test file, repo-relative>  <check label>
#   deferred  <task id the plan has a '### Task <id>:' heading for>  <reason of at least six words>
#   n/a       <one of the caller's n/a reasons>  <reason of at least six words>
# The check fails on a function without a row, a row for a function the tag does not have, a
# duplicate row, a malformed row, a missing file or a label that is not a whole check label of its
# file; it prints the counts and the deferred rows by task. CHECKLIST_FINAL=1 makes every deferred
# row an error. The protoBase checkout is only read (git show, ls-tree).
#
# The caller sets TAG, then calls:
#   checklist_prepare                 skip (77) / fail on a missing checkout or tag, needs python3
#   checklist_list <repo path>...     the test functions of those files at the tag, as file::function
#                                     (sets CHECKLIST_LISTING, CHECKLIST_NFILES)
#   checklist_run <table> <plan> <min> <max> <strict 0|1> <n/a reasons, '|' separated> <sh check command>
#                                     the task ids are min..max (numbers need no plan heading unless
#                                     strict; lettered ids always need one)
# and reads REPO (the repository root) and PB (the protoBase checkout).

checklist_prepare() {
    PB="${PROTOBASE_REPO:-$REPO/../ProtoBase}"
    local explicit="${PROTOBASE_REPO_EXPLICIT-${PROTOBASE_REPO:+1}}"
    if [[ -z "$explicit" && ! -e "$PB" ]]; then
        echo "SKIP: no protoBase checkout"
        exit 77
    fi
    if ! git -C "$PB" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        echo "FAIL: $PB is not a protoBase checkout holding the tag $TAG"
        exit 1
    fi
    command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the checklist cannot run"; exit 1; }
}

checklist_list() {
    local f
    CHECKLIST_NFILES=$#
    CHECKLIST_LISTING="$(for f in "$@"; do
        git -C "$PB" show "$TAG:$f" | grep -E '^def test_|^    def test_' \
            | sed -E 's/^ *def (test_[A-Za-z0-9_]*).*/\1/' | sed "s|^|$(basename "$f")::|"
    done)"
}

checklist_run() {
    local table="$1" plan="$2" tmin="$3" tmax="$4" strict="$5" na="$6" shcheck="$7" lettered
    lettered="$(sed -n -E 's/^### Task ([0-9]+[a-z]?):.*/\1/p' "$plan" 2>/dev/null | tr '\n' ' ')"
    python3 -I - "$REPO" "$table" "$CHECKLIST_LISTING" "$CHECKLIST_NFILES" "${CHECKLIST_FINAL:-0}" \
        "$lettered" "$tmin" "$tmax" "$strict" "$na" "$shcheck" <<'PY'
import os, re, sys
repo, table, listing, nfiles = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
final = sys.argv[5] == "1"
planned = set(sys.argv[6].split())       # the tasks the plan has a '### Task <id>:' heading for
tmin, tmax, strict = int(sys.argv[7]), int(sys.argv[8]), sys.argv[9] == "1"
NA = tuple(sys.argv[10].split("|"))
shcheck = sys.argv[11]                   # the command whose argument names a check of a .sh test


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
    `<shcheck> '<label>'` (indentation allowed; no quote inside the label), <shcheck> being
    the command the caller names."""
    pattern = r"^[ \t]*" + re.escape(shcheck) + r" '([^'\n]+)'[ \t]*$"
    return {m.group(1) for m in re.finditer(pattern, text, re.M)}

functions = [l.strip() for l in listing.splitlines() if l.strip()]
errors = []
seen_fn = set()
for f in functions:
    if f in seen_fn:
        errors.append("the tag defines %s twice: one row cannot tell them apart" % f)
    seen_fn.add(f)
rows = {}
counts = {"ported": 0, "deferred": 0, "n/a": 0}
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
            if not task or not tmin <= int(task.group(1)) <= tmax:
                errors.append("%s: %s: deferred to %r, not a task of the plan (%d..%d, or one with a letter)" % (where, key, a, tmin, tmax))
                continue
            if (task.group(2) or strict) and a not in planned:
                errors.append("%s: %s: deferred to Task %s, which the plan has no heading for" % (where, key, a))
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
}
