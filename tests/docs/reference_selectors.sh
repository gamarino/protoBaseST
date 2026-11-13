#!/usr/bin/env bash
# Guards docs/reference.md, the README, the chapters of docs/tutorial/ and examples/tutorial/README.md
# against invented API: every backticked selector in them
# must be defined in src/protobase/*.st (as `Class >> selector` or `Class class >> selector`), or be
# on the short allow-list of names that are not protoBaseST's (Python names, protoST kernel
# selectors, words that are not selectors). Keyword selectors are checked part by part
# (`setAt:value:` needs both `setAt:` and `value:` to exist in one defined selector's parts, and the
# whole selector to exist when it has two or more parts), unary ones as written. It does not check
# behaviour: tests/docs/tutorial_snippets.st does for the tutorial, and the programs of
# examples/tutorial (which the chapters quote, tutorial_chapters_sync.sh) run as tests.
# The two orientation chapters, docs/tutorial/gemstone.md and soil.md, name the selectors of
# GemStone/S and Soil to compare them; those foreign names are listed below, per file, and are
# allowed only there.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the selector guard cannot run"; exit 1; }
python3 -I - "$REPO" <<'PY'
import re, sys, glob, os
repo = sys.argv[1]
defined = set()
for f in glob.glob(repo + "/src/protobase/*.st") + [repo + "/src/protobase.st"]:
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
extend slice head tail has union intersection difference count_of index_names get_index items
register_atom_class is_active committed_at lock_timeout retries backoff keys values
asFrozenDict asOf: tr: asActor wait EXPECT: protost bytes date
flock fsync nil true false proto_db remove aName atom_pointer context cluster_term current pair n i v repr
avl calendar codec collections decimal errors framing notation publisher registry roots store transactions uuid zonekeys
""".split())
# selectors of GemStone/S and Soil, cited from their documentation by the chapters of
# docs/tutorial/ (mainly gemstone.md and soil.md) to compare them; they are not protoBaseST's and
# are allowed only in docs/tutorial/
foreign = set("""
commitTransaction abortTransaction continueTransaction migrateTo: migrateInstancesTo:
migrateFrom:instVarMap: cluster clusterDepthFirst markForCollection
createOnPath: openOnPath: root: makeRoot: markDirty: commitAndContinue
newTransactionForVersion: allVersionsOf: garbageCollect renameClassNamed:to: isFsyncEnabled
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
docs = ["docs/reference.md", "README.md", "examples/tutorial/README.md"]
docs += sorted(os.path.relpath(f, repo) for f in glob.glob(repo + "/docs/tutorial/*.md"))
bad = []
for doc in docs:
    allow_here = allow | (foreign | lessons if doc.startswith(("docs/tutorial/", "examples/tutorial/")) else set())
    text = open(repo + "/" + doc, encoding="utf-8").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for span in re.findall(r"`([^`\n]+)`", text):
        # a message pattern: keep the keyword parts (drop arguments), e.g. "setAt: k value: v"
        bare = re.sub(r"'[^']*'|\"[^\"]*\"|<[^>]*>", "", span)   # string literals are not selectors
        for tok in re.findall(r"(?:[A-Za-z_]\w*:)+", bare):
            if tok in defined or tok in allow_here:
                continue
            if all(p in parts or p in allow_here for p in re.findall(r"[A-Za-z_]\w*:", tok)) and tok.count(":") == 1:
                continue
            bad.append("%s: `%s` has no definition of %s in src/protobase" % (doc, span, tok))
        if re.fullmatch(r"[a-z]\w*", span) and span not in defined and span not in allow_here:
            bad.append("%s: `%s` is not a unary selector defined in src/protobase" % (doc, span))
if bad:
    print("\n".join(sorted(set(bad)))); sys.exit(1)
print("every backticked selector of %d documents is defined in src/protobase" % len(docs))
PY
