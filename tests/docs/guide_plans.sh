#!/usr/bin/env bash
# The guide's worked plans equal proto_db's (ruling CR10; indexed queries, plan Task 7 Step 5b).
# Every model estimate the guide quotes for a worked plan must be proto_db's own planner output for
# the same data: tests/interop/py_guide_plans.py builds that data with proto_db v2.0.0rc4 and prints
# '<key> <value>' for each figure (the costs and rows of its plans, of the rejected candidates, and
# the differences the text quotes). The table below ties each quoted figure to its key: an entry is
# a file, the keys, and the text around the figure(s), each figure written {} (whitespace, line
# breaks included, compares as one space). An entry whose text is not in the file fails, and so
# does a figure that differs: one written with 10 or more decimals must equal the key's value
# within plan call IP8 (|a - b| <= 1e-12 * max(|a|, |b|)), a shorter one must equal the value
# rounded to as many decimals as it shows. Coverage: in the worked-plan sections (docs/queries.md
# from "### Plan 1" to "## Ordered reads" and its paragraph "The crossover where scanning wins";
# chapter 18's section "Why the planner sometimes scans"), every number written with a decimal point
# must be one of the table's figures, so a new hand-computed figure fails until it is tied to a key.
# Figures are corrected from the generated output, never by hand. The plan each tiny collection
# gets (the text says the planner scans one element and looks two up) is checked too.
# Limits: coverage enforces only figures written with a decimal point; an integer figure (1200,
# 1261) is checked only when an entry ties it, so a new hand-written integer passes unnoticed. And a
# figure shown with fewer decimals passes when the value rounds to it ('2.6' for 2.585), by design:
# the text may round, but never to another number.
# Once examples/queries/reading_plans.st exists (Task 8 moves it out of pending/), its literal
# figures are checked by the same entries and the program is run: its last line must be its EXPECT
# line, so protoBaseST's planner computes the same figures. Until then only the text is checked.
# The worked vector plan (docs/queries.md, "A worked vector plan", vectors task V9) is checked the
# same way against examples/queries/vector_plans.st, which must exist.
# Needs the interop venv: without it, 'SKIP: no interop venv' and exit 77.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[[ -x "$REPO/tests/interop/.venv/bin/python" && -d "$REPO/tests/interop/.venv/protobase/proto_db" ]] || {
    echo "SKIP: no interop venv"; exit 77; }
# shellcheck source=../interop/env.sh
source "$REPO/tests/interop/env.sh"
generated="$("$PY" "$REPO/tests/interop/py_guide_plans.py")" || { echo "FAIL: py_guide_plans.py failed"; exit 1; }
PROGRAM="$REPO/examples/queries/reading_plans.st"
VPROGRAM="$REPO/examples/queries/vector_plans.st"
"$PY" -I - "$REPO" "$generated" "$PROGRAM" "$VPROGRAM" <<'PY' || exit 1
import os, re, sys
repo, generated, program, vprogram = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
values = {}
for line in generated.splitlines():
    key, value = line.split(" ", 1)
    values[key] = value
Q, C = "docs/queries.md", "docs/tutorial/18-queries-and-plans.md"
CODE = (Q, "@program")  # the program's literal figures are the guide's code block's
VCODE = (Q, "@vprogram")  # the same for the worked vector plan and examples/queries/vector_plans.st
VP = ("@vprogram",)  # a figure the program checks and the guide's code blocks do not quote
TABLE = [
    # Plan 1
    (CODE, ["plan1.rows"], "'rows: the size of the Oslo group' is: ((plan at: 'estimate') at: 'rows') equals: {}."),
    (CODE, ["plan1.cost"], "isTrue: (close value: ((plan at: 'estimate') at: 'cost') value: {})."),
    ((Q,), ["plan1.rows"], "The lookup produces the Oslo group, {} rows, exactly"),
    ((Q,), ["plan1.descent"], "one descent of `log2 (4 + 2)` ≈ {}."),
    ((Q,), ["plan1.scan.cost", "plan1.scan.rows"], "costs 600 + 600 = {} and would produce an estimated {} rows."),
    # Plan 2
    (CODE, ["plan2.range.rows"], "'the range: 7 keys of 10 rows' is: ((range at: 'estimate') at: 'rows') equals: {}."),
    (CODE, ["plan2.range.cost"], "isTrue: (close value: ((range at: 'estimate') at: 'cost') value: {})."),
    (CODE, ["plan2.filter.rows"], "'the filter halves the rows, per term' is: ((filter at: 'estimate') at: 'rows') equals: {}."),
    (CODE, ["plan2.filter.cost"], "isTrue: (close value: ((filter at: 'estimate') at: 'cost') value: {})."),
    (CODE, ["plan2.city.cost"], "isTrue: (close value: ((withoutAge explain at: 'estimate') at: 'cost') value: {})."),
    (CODE, ["plan2.scan.cost"], "is: ((scanOnly explain at: 'estimate') at: 'cost') equals: {}."),
    ((Q,), ["plan2.range.rows", "plan2.range.rows", "plan2.range.cost"],
     "it estimates 10 rows per key, {} rows, at a cost of {} + `log2 (60 + 2)` + 7 ≈ {}."),
    ((Q,), ["plan2.range.rows", "plan2.filter.cost", "plan2.filter.rows"],
     "tests `city == 'Oslo'` on those {} rows: it pays one unit per row read (cost ≈ {}) and is estimated to keep half ({} rows)."),
    ((Q,), ["plan2.filter.cost"], "| `Filter (city) <- IndexRange (age > 70)` | ≈ {}, chosen |"),
    ((Q,), ["plan2.city.cost"], "| `Filter (age) <- IndexLookup (city == 'Oslo')` | ≈ {} |"),
    ((Q,), ["plan2.scan.cost"], "| `Filter (both) <- CollectionScan` | {} |"),
    ((Q,), ["plan2.answer", "plan2.filter.rows"], "The query really answers {} rows, not {}:"),
    # Plan 3
    (CODE, ["plan3.sort.cost"], "'the sort pays n log2 n on 60 rows' isTrue: (close value: ((sort at: 'estimate') at: 'cost') value: {})."),
    (CODE, ["plan3.limit.cost"], "isTrue: (close value: ((window at: 'estimate') at: 'cost') value: {})."),
    ((Q,), ["plan3.range.rows", "plan3.range.rows", "plan3.range.cost"],
     "covers 6 keys, {} rows, at {} + `log2 62` + 6 ≈ {}."),
    ((Q,), ["plan3.sort.increment", "plan3.sort.cost"], "adds 60 × `log2 60` ≈ {}, for ≈ {}."),
    ((Q,), ["plan3.limit.cost"], "is charged its whole source, ≈ {} (the model's known"),
    ((Q,), ["plan3.ordered_filter.cost"], "at a model estimate of (600 + 60 + 1) + 600 = {}."),
    ((Q,), ["plan3.unconditioned.cost", "plan3.sort_all.cost"],
     "the ordered scan ({}) would beat sorting all 600 rows (600 + 600 × `log2 600` ≈ {})"),
    # The crossover
    ((Q,), ["tiny1.lookup.cost", "tiny1.scan.cost"], "a matching lookup costs 1 + log2 3 ≈ {} against the scan's {} (model estimates)"),
    ((Q,), ["tiny2.lookup.cost", "tiny2.scan.cost"], "with two elements in two groups the lookup costs {} and the scan {}, and it looks up."),
    ((C,), ["tiny1.scan.cost"], "the scan and its filter cost {} units"),
    ((C,), ["tiny1.lookup.cost"], "the lookup costs 1 row plus one descent of `log2 (1 + 2)`, about {} (model estimates"),
    ((C,), ["tiny2.lookup.cost", "tiny2.scan.cost"], "two cities the lookup costs {} and the scan {}."),
    # A worked vector plan (Addendum V, section 6.3)
    (VCODE, ["vplan1.cost"], "is: (est value: plan value: 'cost') equals: {}."),
    (VP, ["vplan1.rows"], "'rows: k' is: (est value: plan value: 'rows') equals: {}."),
    (VCODE, ["vplan1.exact.cost"], "is: (est value: exactOnly explain value: 'cost') equals: {}."),
    (VCODE, ["vplan2.cost"], "is: (est value: filtered value: 'cost') equals: {}."),
    (VP, ["vplan2.exact.cost"], "eq: 'music'))) explain value: 'cost') equals: {}."),
    (VP, ["vplan3.rows"], "'plan 3: half the members' is: (est value: close value: 'rows') equals: {}."),
    (VP, ["vplan3.cost"], "'its cost: 8 + 75 + 150 + 1' is: (est value: close value: 'cost') equals: {}."),
    (VP, ["vplan3.exact.cost"], "(vec near: query threshold: 0.6)) explain value: 'cost') equals: {}."),
    (VP, ["vplan1.overlap"], "exactFive includes: (d at: 'i')]) size equals: {}."),
    ((Q,), ["vplan1.rows", "vplan1.cost"], "is estimated at {} rows (k) and a cost of {}:"),
    ((Q,), ["vplan1.exact.cost"], "is the exact search: 300 + 5 + 1 = {}."),
    ((Q,), ["vplan2.cost", "vplan2.exact.cost"], "8 + 150 + 3 + 1 = {} for the IVF index, 2 × 300 + 3 + 1 = {} for the exact one."),
    ((Q,), ["vplan3.rows", "vplan3.cost", "vplan3.exact.cost"],
     "the model guesses half the members, {} rows: 8 + 75 + 150 + 1 = {} against 300 + 150 + 1 = {}."),
    ((Q,), ["vplan1.overlap"], "in this data, {} of the IVF search's 5 documents are among the exact 5"),
]
REGIONS = {Q: [(r"### Plan 1", r"\n## Ordered reads"), (r"\*\*The crossover where scanning wins\.\*\*", r"\n\n"),
               (r"### A worked vector plan", r"\n### Writes, merges and the cluster")],
           C: [(r"## Why the planner sometimes scans", r"\n## ")]}
NUMBER = r"([0-9]+(?:\.[0-9]+)?)"
fails = []
if values.get("tiny1.chosen") != "Filter" or values.get("tiny2.chosen") != "IndexLookup":
    fails.append(f"the tiny collections: proto_db chooses {values.get('tiny1.chosen')} for one element and "
                 f"{values.get('tiny2.chosen')} for two; the guide says it scans one and looks two up")


def same(written, value):
    v = float(value)
    decimals = len(written.split(".")[1]) if "." in written else 0
    if decimals >= 10:
        a = float(written)
        return abs(a - v) <= 1e-12 * max(abs(a), abs(v))
    return round(v, decimals) == float(written)


def normalise(text):
    """Whitespace runs as one space, and a map from each normalised offset to the original's."""
    out, offsets, space = [], [], False
    for i, ch in enumerate(text):
        if ch.isspace():
            if not space:
                out.append(" ")
                offsets.append(i)
            space = True
        else:
            out.append(ch)
            offsets.append(i)
            space = False
    return "".join(out), offsets


files = {Q: Q, C: C}
if os.path.isfile(program):
    files["@program"] = program
files["@vprogram"] = vprogram
covered = {name: [] for name in files}
checked = 0
for where, keys, text in TABLE:
    for name in where:
        if name not in files:
            continue
        raw = open(os.path.join(repo, files[name]) if not os.path.isabs(files[name]) else files[name], encoding="utf-8").read()
        norm, offsets = normalise(raw)
        pattern = re.escape(" ".join(text.split())).replace(re.escape("{}"), NUMBER)
        found = list(re.finditer(pattern, norm))
        if not found:
            fails.append(f"{files[name]}: not found: {text}")
            continue
        for m in found:
            for i, key in enumerate(keys):
                written = m.group(i + 1)
                covered[name].append((offsets[m.start(i + 1)], offsets[m.end(i + 1) - 1] + 1))
                if key not in values:
                    fails.append(f"no generated figure {key}")
                elif not same(written, values[key]):
                    fails.append(f"{files[name]}: {written} in '{text}' is not proto_db's {key} = {values[key]}")
                checked += 1
for name, regions in REGIONS.items():
    raw = open(os.path.join(repo, name), encoding="utf-8").read()
    for start, stop in regions:
        s = re.search(start, raw)
        if not s:
            fails.append(f"{name}: no section {start}")
            continue
        e = re.compile(stop).search(raw, s.end())
        end = e.start() if e else len(raw)
        for m in re.finditer(r"(?<![\w.])[0-9]+\.[0-9]+(?![\w.])", raw[s.start():end]):
            a, b = s.start() + m.start(), s.start() + m.end()
            if not any(x <= a and b <= y for x, y in covered[name]):
                line = raw.count("\n", 0, a) + 1
                fails.append(f"{name}:{line}: {m.group(0)} is a figure no entry ties to proto_db's output")
for f in fails:
    print("FAIL: " + f)
if fails:
    sys.exit(1)
print(f"guide plans: {checked} figures equal proto_db's"
      + (", the program's included" if "@program" in files else " (examples/queries/reading_plans.st not yet in place)"))
PY
for prog in "$PROGRAM" "$VPROGRAM"; do
    [[ -f "$prog" ]] || { [[ "$prog" == "$PROGRAM" ]] && continue; echo "FAIL: $prog is missing"; exit 1; }
    expect="$(sed -n '1s/^"EXPECT: \(.*\)"$/\1/p' "$prog")"
    last="$(cd "$(dirname "$prog")" && STPATH="$REPO/src" "$PROTOST" "$(basename "$prog")" 2>&1 | tail -n 1)"
    [[ -n "$expect" && "$last" == "$expect" ]] || { echo "FAIL: $prog printed '$last', not '$expect'"; exit 1; }
    echo "the program's plans equal them: $last"
done
echo "guide plans ok"
