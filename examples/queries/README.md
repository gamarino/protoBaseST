# The query examples

> **protoBaseST 0.3.0, and vector search for 0.4.0.** Every program of this directory runs as a
> test; [pending/](pending/README.md) holds chapter 20's program (0.4.0, Addendum V), written
> before its chapter's figures and not run yet.

Programs for indexed queries: the guide [docs/queries.md](../../docs/queries.md) quotes the ones
in this directory, and the query chapters of the tutorial (17-19, and chapter 11's section
"Indexes, from both sides") quote theirs, which move to [examples/tutorial/](../tutorial/README.md)
once they run. Each one checks what it shows in the house style of the tutorial lessons
(`lesson check:`, whose `_lesson.st` they import from `../tutorial/`): a line per check and a last
line `<lesson> ok (N checks)`; a failed check exits with status 1. Once they run they are tests,
run by `tests/run_tests.sh`.

## The programs

Each program was written by the plan task named (the indexed-queries plan,
`docs/superpowers/plans/2026-11-18-indexed-queries.md`), fail-first through
`tests/docs/tutorial_chapters_sync.sh`: the guide quoted it before it existed.

| Program | Shows | Guide section | Written or moved here by |
|---|---|---|---|
| [reading_plans.st](reading_plans.st) | the three worked plans, their model estimates equal to `proto_db`'s | "Reading a plan" | Task 8 (moved from `pending/`) |
| [keys.st](keys.st) | key specs, `MISSING` and `nil`, the persisted key spec | "Key specs, MISSING and nil" | Task 8 |
| [expressions.st](expressions.st) | the builder, the list syntax, two-valued evaluation, blocks and the mixing rule | "The expression language" | Task 8 |
| [lookups.st](lookups.st) | what an equality index answers, by which plan | "Equality and range indexes" | Task 8 |
| [compound.st](compound.st) | AND, OR and NOT, with `explain` | "How the planner chooses" | Task 8 |
| [ranges.st](ranges.st) | ranges, ordered reads and windows by rank | "Ordered reads, windows and pages" | Task 8 |
| [merge_indexed.st](merge_indexed.st) | blind writes merged onto an indexed root; a concurrent index creation | "Merges of blind writes" | Task 8 |
| [paging.st](paging.st) | pagers, by rank and materialised | "Ordered reads, windows and pages" | Task 9 |
| [vector_search.st](vector_search.st) | vector indexes, near queries alone and with a condition, checked against a brute force | "Vector search" | vectors task V7 (moved from `pending/`) |

Run one with `STPATH=<repository>/src protost <program>` from this directory, or all of them with
`tests/run_tests.sh examples/queries`.

The guide marks each section whose program is not written yet with a line
`<!-- pending example: examples/queries/X (plan task N) -->`, which the sync test checks: the
program must not exist yet, and once it does the line becomes an `example:` line and the
section's code blocks are checked against it.

## pending/

[pending/](pending/README.md) holds the programs written before the API they need, as
`X.st.pending`, `X.sh.pending` and `X.py.pending`, which `tests/run_tests.sh` does not run. Its
README lists each one, the chapter that quotes it, the plan task that moves it and where it goes.
