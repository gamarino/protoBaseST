# Pending query examples

> **Empty.** Every program written here before its API was moved out once the API landed, and runs
> as a test: the programs of chapters 11, 17 and 18 and `reading_plans` by plan Task 8, chapter 19's
> by plan Task 9. The table below records where each went.

This directory holds the programs of the query chapters, written before the API they need, as
the cluster chapters' programs were (`examples/cluster/pending/`). Their extensions,
`.st.pending`, `.sh.pending` and `.py.pending`, keep them out of `tests/run_tests.sh`, which runs
only `*.st` and `*.sh` files.

| Program | Quoted by | Waited for (spec section 11) | Moved by (plan) | Moved to |
|---|---|---|---|---|
| `19_ordered_reads_and_pages.st.pending` | [chapter 19](../../../docs/tutorial/19-ordered-reads-and-pages.md) | T9 | Task 9 | [examples/tutorial/19_ordered_reads_and_pages.st](../../tutorial/19_ordered_reads_and_pages.st) |

Each program checks its own results in the house style (`lesson check:`, chapter 1), so once it
runs it proves what its chapter shows. A tutorial program imports `_lesson` as it will from
`examples/tutorial/`.

**The figures in these programs are not measurements.** The counts follow from the data each
program builds. Every timing the chapters need is a placeholder in the chapter,
`[measured in T<n>: ...]`, filled from the benchmarks of spec section 7.3.

**Checked by the documentation guards.** `tests/docs/tutorial_chapters_sync.sh` checks every code
block of the query chapters and of `docs/queries.md` against these programs, and requires each
program here to be named by one of them. `tests/docs/reference_selectors.sh` accepts the selectors
the drafts cite before they exist only from `tests/docs/pending_selectors.tsv`, each with the plan
task that builds it; `tests/docs/measured_markers.sh` counts the `[measured in T<n>: ...]` markers
per task.

When the API a program needs is merged: move it without the `.pending` suffix to the place in the
table, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh <its new path>`, and correct the program and the chapter together wherever the
built API differs from the spec. A chapter section that quotes a pending program says so.
