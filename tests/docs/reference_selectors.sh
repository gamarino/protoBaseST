#!/usr/bin/env bash
# Guards docs/reference.md, the README, the chapters of docs/tutorial/ and examples/tutorial/README.md
# against invented API: every backticked selector in them
# must be defined in src/protobase/*.st and src/protobase/cluster/*.st (as `Class >> selector` or `Class class >> selector`), or be
# on the short allow-list of names that are not protoBaseST's (Python names, protoST kernel
# selectors, words that are not selectors). Keyword selectors are checked part by part
# (`setAt:value:` needs both `setAt:` and `value:` to exist in one defined selector's parts, and the
# whole selector to exist when it has two or more parts), unary ones as written. It does not check
# behaviour: tests/docs/tutorial_snippets.st does for the tutorial, and the programs of
# examples/tutorial (which the chapters quote, tutorial_chapters_sync.sh) run as tests.
# The two orientation chapters, docs/tutorial/gemstone.md and soil.md, name the selectors of
# GemStone/S and Soil to compare them; those foreign names are listed below, per file, and are
# allowed only there.
# docs/queries.md (the indexed-queries guide) is guarded too. Documentation is written before the
# API it describes (plan call IP5): tests/docs/pending_selectors.tsv lists, one per line, a
# selector the documents cite before it exists and the plan task (1-9) whose Interfaces block
# produces it ("<selector><TAB><task>"; "#" lines and blank lines are comments). A pending
# selector, and each keyword part of one, is accepted like a defined selector. A listed selector
# that is now defined in src/protobase, or that no document cites any more, is an error (a stale
# line: the task that builds it removes it), and so is a malformed line, a task outside 1-9 or a
# duplicate. With PENDING_FINAL=1 (the final task) any line left is an error. The marker
# "[measured in T<n>: ...]" (tests/docs/measured_markers.sh) and a file citation
# (`keyed.py:596-622`) are not selectors and are skipped.
# Granularity limits of the pending list: a selector is listed once, under the first task whose
# Interfaces block produces it (`describe` is Task 2's although Task 5 defines it on terms too;
# `rows` is Task 6's although Task 9's pager answers it too), so the line goes when that first
# definition lands, whatever class later ones are on. Keyword parts are matched separately, as
# above: a span `name: n keySpec: k` is accepted because `name:` and `keySpec:` are each a part of
# some defined or pending selector, without proving that `name:keySpec:` itself is either; only a
# span written as one selector (`name:keySpec:`) is checked whole.
# Citation (what keeps a pending line from being stale): a span cites a pending selector when it
# is that selector, when its keyword parts joined in order are that selector (`orderBy: aKey
# descending: aBoolean` cites orderBy:descending:, even when `descending:` is also a part of a
# defined selector), or when it is a lone keyword part of no defined selector that belongs to that
# pending selector. A lone part that some defined selector has never cites a pending one.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the selector guard cannot run"; exit 1; }
PENDING_FINAL="${PENDING_FINAL:-}" python3 -I - "$REPO" <<'PY'
import re, sys, glob, os
repo = sys.argv[1]
defined = set()
for f in glob.glob(repo + "/src/protobase/*.st") + glob.glob(repo + "/src/protobase/cluster/*.st") + [repo + "/src/protobase.st"]:
    for line in open(f, encoding="utf-8"):
        m = re.match(r"^\S+(?: class)? >> (.+)$", line.rstrip())
        if not m:
            continue
        head = m.group(1).strip()
        if re.match(r"^[A-Za-z_]\w*$", head):
            defined.add(head)
        elif re.match(r"^[A-Za-z_]\w*:", head):
            defined.add("".join(re.findall(r"[A-Za-z_]\w*:", head)))
        else:
            defined.add(head.split()[0])
# selectors of protoST's kernel, Python names and plain words that appear in backticks
allow = set("""
new name size isEmpty notEmpty at: at:ifAbsent: includesKey: do: keysAndValuesDo: keys values
asArray printOn: = hash printNl value: value ifTrue: ifFalse: close deleteAll pathString
detect:ifNone: signal: messageText on:do: wait copyWith: copyWithout: copyWithoutIndex:
get: set: abort commit isActive displayNl pid temp collect: select: includes:
withAll: with:value: remove: add:
get_root_object set_root_object remove_root_object root_names new_mutable get_mutable
set_mutable remove_mutable mutable_names new_list new_dictionary new_hash_dictionary new_set
new_counted_set new_object new_database open_database list_databases new_transaction
snapshot_at with_ has_defined_attr get_at set_at insert_at remove_at append_first append_last
recover_root bind_root force_rejoin rejoin_blocked
add_index remove_index register_extractor unregister_extractor extractor_version plan_query or:
extend slice head tail has union intersection difference count_of index_names get_index items
register_atom_class is_active committed_at lock_timeout retries backoff keys values
asFrozenDict asOf: tr: asActor wait EXPECT: protost bytes date ensure:
flock fsync nil true false proto_db remove aName atom_pointer context cluster_term current pair n i v repr
avl calendar codec collections decimal errors framing net notation publisher registry roots round store transactions uuid zonekeys
""".split())
# selectors of GemStone/S and Soil, cited from their documentation by the chapters of
# docs/tutorial/ (mainly gemstone.md and soil.md) to compare them; they are not protoBaseST's and
# are allowed only in docs/tutorial/
foreign = set("""
commitTransaction abortTransaction continueTransaction migrateTo: migrateInstancesTo:
migrateFrom:instVarMap: cluster clusterDepthFirst markForCollection
createOnPath: openOnPath: root: makeRoot: markDirty: commitAndContinue
newTransactionForVersion: allVersionsOf: garbageCollect renameClassNamed:to: isFsyncEnabled
beAutomaticWriteTracking beManualWriteTracking transactionConflicts
""".split())
# selectors the programs of examples/tutorial define themselves (Book >> isClassic...), which the
# chapters quote; allowed only in docs/tutorial/ and examples/tutorial/README.md
lessons = set()
for f in glob.glob(repo + "/examples/tutorial/*.st"):
    for line in open(f, encoding="utf-8"):
        m = re.match(r"^\S+(?: class)? >> (.+)$", line.rstrip())
        if m:
            head = m.group(1).strip()
            lessons.add(head if re.match(r"^[A-Za-z_]\w*$", head) else "".join(re.findall(r"[A-Za-z_]\w*:", head)))
parts = {p for d in defined for p in re.findall(r"[A-Za-z_]\w*:", d)}
# the pending selectors (plan call IP5)
pending, bad = {}, []
pending_file = repo + "/tests/docs/pending_selectors.tsv"
for n, line in enumerate(open(pending_file, encoding="utf-8"), 1):
    line = line.rstrip("\n")
    if not line.strip() or line.startswith("#"):
        continue
    m = re.fullmatch(r"((?:[A-Za-z_]\w*:)+|[a-z]\w*)\t([1-9])", line)
    if not m:
        bad.append("tests/docs/pending_selectors.tsv:%d: malformed line (want <selector><TAB><task 1-9>): %r" % (n, line)); continue
    sel = m.group(1)
    if sel in pending:
        bad.append("tests/docs/pending_selectors.tsv:%d: %s is listed twice" % (n, sel)); continue
    pending[sel] = int(m.group(2))
    if sel in defined:
        bad.append("tests/docs/pending_selectors.tsv:%d: %s is defined in src/protobase now: remove the stale line (task %s)" % (n, sel, m.group(2)))
    if os.environ.get("PENDING_FINAL") == "1":
        bad.append("tests/docs/pending_selectors.tsv:%d: %s is still pending (task %s), and PENDING_FINAL=1" % (n, sel, m.group(2)))
pending_parts = {}
for sel in pending:
    for p in re.findall(r"[A-Za-z_]\w*:", sel):
        pending_parts.setdefault(p, []).append(sel)
used = set()
docs = ["docs/reference.md", "docs/queries.md", "README.md", "examples/tutorial/README.md"]
# docs/tutorial/erp.md is the ERP walk-through, whose code tutorial_snippets.st runs; its prose
# names variables and roots in backticks, so it stays outside this guard, as before its move
docs += sorted(os.path.relpath(f, repo) for f in glob.glob(repo + "/docs/tutorial/*.md")
               if not f.endswith("/erp.md"))
for doc in docs:
    allow_here = allow | (foreign | lessons | {p for d in lessons for p in re.findall(r"[A-Za-z_]\w*:", d)}
                          if doc.startswith(("docs/tutorial/", "examples/tutorial/")) else set())
    text = open(repo + "/" + doc, encoding="utf-8").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    if doc == "docs/reference.md":
        # the module load list ("`Import from: 'protobase'.` loads, in order, ...") names modules,
        # not selectors: that one paragraph is skipped, and no module name is allowed elsewhere
        text = re.sub(r"`Import from: 'protobase'\.` loads, in order,.*?(?:\n\n|\Z)", "", text, flags=re.S)
    for span in re.findall(r"`([^`\n]+)`", text):
        # a message pattern: keep the keyword parts (drop arguments), e.g. "setAt: k value: v"
        if re.fullmatch(r"\[measured in T<n>: [^\]]*\]", span):
            continue   # the marker convention, not a selector
        if re.fullmatch(r"[\w./-]+\.(?:py|rst|st|md|sh)(?::\d+(?:-\d+)?)?", span):
            continue   # a file citation (keyed.py:596-622), not a selector
        bare = re.sub(r"'[^']*'|\"[^\"]*\"|<[^>]*>", "", span)   # string literals are not selectors
        # A message pattern cites the pending selector its keyword parts join into
        # (`orderBy: aKey descending: aBoolean` cites orderBy:descending:), whether or not its
        # parts are also parts of defined selectors.
        joined = "".join(re.findall(r"[A-Za-z_]\w*:", bare))
        if joined in pending:
            used.add(joined)
        for tok in re.findall(r"(?:[A-Za-z_]\w*:)+", bare):
            if tok in defined or tok in allow_here:
                continue
            if all(p in parts or p in allow_here for p in re.findall(r"[A-Za-z_]\w*:", tok)) and tok.count(":") == 1:
                continue
            if tok in pending:
                used.add(tok); continue
            if tok.count(":") == 1 and tok in pending_parts:
                used.update(pending_parts[tok]); continue
            bad.append("%s: `%s` has no definition of %s in src/protobase" % (doc, span, tok))
        if re.fullmatch(r"[a-z]\w*", span) and span not in defined and span not in allow_here:
            if span in pending:
                used.add(span); continue
            bad.append("%s: `%s` is not a unary selector defined in src/protobase" % (doc, span))
for sel in sorted(set(pending) - used - defined):
    bad.append("tests/docs/pending_selectors.tsv: %s (task %d) is cited by no document: remove the line" % (sel, pending[sel]))
if bad:
    print("\n".join(sorted(set(bad)))); sys.exit(1)
print("every backticked selector of %d documents is defined in src/protobase, or pending (%d selectors: %s)"
      % (len(docs), len(pending), ", ".join("T%d %d" % (t, sum(1 for v in pending.values() if v == t))
                                            for t in sorted(set(pending.values())))))
PY
