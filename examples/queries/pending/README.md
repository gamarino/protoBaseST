# Pending query examples

> **Empty since 0.4.0.** The indexed-queries programs written here before their API were moved
> out once the API landed, and run as tests: those of chapters 11, 17 and 18 and `reading_plans` by
> plan Task 8, chapter 19's by plan Task 9. The vectors phase
> ([Addendum V](../../../docs/superpowers/specs/2026-11-19-vectors-addendum.md), plan
> `docs/superpowers/plans/2026-11-20-vectors.md`) wrote two more in its task V0, against the
> addendum's API: `vector_search.st` was moved out by task V7, chapter 20's by task V9; both run as
> tests. The table records where each went.

This directory holds the programs of the query chapters, written before the API they need, as
the cluster chapters' programs were (`examples/cluster/pending/`). Their extensions,
`.st.pending`, `.sh.pending` and `.py.pending`, keep them out of `tests/run_tests.sh`, which runs
only `*.st` and `*.sh` files.

| Program | Quoted by | Waited for (spec section 11; Addendum V, section 7) | Moved by (plan) | Moved to |
|---|---|---|---|---|
| `19_ordered_reads_and_pages.st.pending` | [chapter 19](../../../docs/tutorial/19-ordered-reads-and-pages.md) | T9 | Task 9 | [examples/tutorial/19_ordered_reads_and_pages.st](../../tutorial/19_ordered_reads_and_pages.st) |
| `vector_search.st.pending` | [docs/queries.md, Vector search](../../../docs/queries.md#vector-search) | V7 (the planner's `near[]` rules and `PBField near:`) | V7 | [examples/queries/vector_search.st](../vector_search.st) |
| `20_vector_search.st.pending` | [chapter 20](../../../docs/tutorial/20-vector-search.md) | V9 (every vector task, and the chapter's measured figures) | V9 | [examples/tutorial/20_vector_search.st](../../tutorial/20_vector_search.st) |

Each program checks its own results in the house style (`lesson check:`, chapter 1), so once it
runs it proves what its chapter shows. A tutorial program imports `_lesson` as it will from
`examples/tutorial/`.

**The figures in these programs are not measurements.** The counts follow from the data each
program builds. Every timing the chapters need is a placeholder in the chapter,
`[measured in T<n>: ...]`, filled from the benchmarks of spec section 7.3, or, for vector search,
`[measured in V<n>: ...]`, filled from the benchmarks VB0 to VB5 of Addendum V, section 5.5.

**Checked by the documentation guards.** `tests/docs/tutorial_chapters_sync.sh` checks every code
block of the query chapters and of `docs/queries.md` against these programs, and requires each
program here to be named by one of them. `tests/docs/reference_selectors.sh` accepts the selectors
the drafts cite before they exist only from `tests/docs/pending_selectors.tsv`, each with the plan
task that builds it; `tests/docs/measured_markers.sh` counts the `[measured in T<n>: ...]` markers
per task (T0-T10, and V-pin and V0-V10 for the vectors phase).

When the API a program needs is merged: move it without the `.pending` suffix to the place in the
table, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh <its new path>`, and correct the program and the chapter together wherever the
built API differs from the spec. A chapter section that quotes a pending program says so.
