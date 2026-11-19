# Pending query examples

> **Draft.** Indexed queries are planned for protoBaseST 0.3.0 and **not implemented**. Every
> program here is written against the approved API of the
> [indexed-queries spec](../../../docs/superpowers/specs/2026-11-18-indexed-queries-design.md)
> (section 5) and **has never run**.

This directory holds the programs of the query chapters, written before the API they need, as
the cluster chapters' programs were (`examples/cluster/pending/`). Their extensions,
`.st.pending`, `.sh.pending` and `.py.pending`, keep them out of `tests/run_tests.sh`, which runs
only `*.st` and `*.sh` files.

| Program | Quoted by | Waits for (spec section 11) | Moves to |
|---|---|---|---|
| `17_indexes.st.pending` | [chapter 17](../../../docs/tutorial/17-indexes.md) | T2, T3, T4, T8 | `examples/tutorial/17_indexes.st` |
| `18_queries_and_plans.st.pending` | [chapter 18](../../../docs/tutorial/18-queries-and-plans.md) | T5, T6, T7, T8 | `examples/tutorial/18_queries_and_plans.st` |
| `19_ordered_reads_and_pages.st.pending` | [chapter 19](../../../docs/tutorial/19-ordered-reads-and-pages.md) | T9 | `examples/tutorial/19_ordered_reads_and_pages.st` |
| `11_indexed_interop.sh.pending`, `_indexed_change.st.pending`, `11_indexed_python_side.py.pending` | [chapter 11](../../../docs/tutorial/11-python-interop.md), "Indexes, from both sides" | T4, T8 | `examples/tutorial/` (same names, without `.pending`) |
| `reading_plans.st.pending` | [docs/queries.md](../../../docs/queries.md), "Reading a plan" | T6, T7, T8 | `examples/queries/reading_plans.st` |

Each program checks its own results in the house style (`lesson check:`, chapter 1), so once it
runs it proves what its chapter shows. The tutorial programs import `_lesson` as they will from
`examples/tutorial/`; `reading_plans` imports `../tutorial/_lesson` as it will from
`examples/queries/`.

**The figures in these programs are not measurements.** The counts follow from the data each
program builds; the plan estimates of `reading_plans` are computed by hand from `proto_db`'s cost
model (`proto_db/indexing/keyed.py`, `KeyGroupIndex.estimate`; `proto_db/query/plans.py`, the
estimate of each node), and the program checks that protoBaseST's planner computes the same. Every
timing the chapters need is a placeholder in the chapter, `[measured in T<n>: ...]`, filled from
the benchmarks of spec section 7.3.

**Not yet checked by the documentation guards.** `tests/docs/tutorial_chapters_sync.sh` reads
`<!-- example: -->` lines under `examples/tutorial/` and `examples/cluster/` only, and
`tests/docs/reference_selectors.sh` has no list of pending selectors. Extending both is task T0
of the plan; until then the new chapters fail those two checks, as listed in the plan.

When the API a program needs is merged: move it without the `.pending` suffix to the place in the
table, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh <its new path>`, and correct the program and the chapter together wherever the
built API differs from the spec. A chapter section that quotes a pending program says so.
