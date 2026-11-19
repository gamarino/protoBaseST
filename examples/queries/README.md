# The query examples

> **Draft: indexed queries are planned for protoBaseST 0.3.0 and not implemented.** No program of
> this directory runs yet. The programs written so far are in [pending/](pending/README.md) and
> have never run.

Programs for indexed queries: the guide [docs/queries.md](../../docs/queries.md) quotes the ones
in this directory, and the query chapters of the tutorial (17-19, and chapter 11's section
"Indexes, from both sides") quote theirs, which move to [examples/tutorial/](../tutorial/README.md)
once they run. Each one checks what it shows in the house style of the tutorial lessons
(`lesson check:`, whose `_lesson.st` they import from `../tutorial/`): a line per check and a last
line `<lesson> ok (N checks)`; a failed check exits with status 1. Once they run they are tests,
run by `tests/run_tests.sh`.

## What is planned here

Each program is written by the plan task named (the indexed-queries plan,
`docs/superpowers/plans/2026-11-18-indexed-queries.md`), fail-first through
`tests/docs/tutorial_chapters_sync.sh`: the guide quotes it before it exists.

| Program | Shows | Written or moved here by |
|---|---|---|
| `reading_plans.st` | the three worked plans of the guide's "Reading a plan" | Task 8 (moved from `pending/`) |
| `keys.st` | key specs, `MISSING` and `nil` (the guide's section "Key specs, MISSING and nil") | Task 8 |
| `expressions.st` | the expression language and the list syntax (the guide's section "The expression language") | Task 8 |
| `lookups.st` | indexes and lookups | Task 8 |
| `ranges.st` | ranges and ordered reads | Task 8 |
| `compound.st` | AND, OR and NOT, with `explain` | Task 8 |
| `merge_indexed.st` | a blind write merged onto an indexed root | Task 8 |
| `paging.st` | pagers, by rank and materialised | Task 9 |

The guide marks each section whose program is not written yet with a line
`<!-- pending example: examples/queries/X (plan task N) -->`, which the sync test checks: the
program must not exist yet, and once it does the line becomes an `example:` line and the
section's code blocks are checked against it.

## pending/

[pending/](pending/README.md) holds the programs written before the API they need, as
`X.st.pending`, `X.sh.pending` and `X.py.pending`, which `tests/run_tests.sh` does not run. Its
README lists each one, the chapter that quotes it, the plan task that moves it and where it goes.
