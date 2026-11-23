# The tutorial examples

Small programs, one concept each, in the order of the chapters of
[docs/tutorial/](../../docs/tutorial/README.md). Each one starts with a comment that says what it
teaches and which chapter explains it. Each one **proves what it shows**: it prints a line per check
(`ok - ...`) and ends with `<lesson> ok (N checks)`. A failed check prints `FAIL - ...`, ends with
`<lesson> FAILED` and exits with status 1, so an example cannot fail silently.

protoBaseST is a proposal prototype for the FAST Smalltalk workshop (2026-12-03), not a product.
Lessons 01 to 12 use only what v0.1.0 does; lessons 17 to 19 and lesson 11's indexed part use the
indexed-query API of 0.3.0; lesson 20, and the vector index of lesson 11's indexed part, use the
vector search of 0.4.0. Where something is not supported, the example says so and
checks the refusal.

## Run them

```sh
export PROTOST=../protoST/build_release/protost        # protoST 0.16.1 or newer
cd examples/tutorial
STPATH=$PWD/../../src $PROTOST 01_first_commit.st      # one lesson
cd ../..
tests/run_tests.sh examples/tutorial                    # all of them, as tests
```

`tests/run_tests.sh` (with no arguments) runs them with everything else: the first line of each
`.st` file is its `EXPECT:` directive, and lesson 11 is a `.sh` test that is skipped (exit 77)
without the Python venv. Every lesson works in its own temporary directory under
`FileSystem temp` (`pbst-tutorial-NN-<pid>`) and deletes it when it ends normally or with a failed
check; a lesson that stops on an unexpected error leaves that directory behind.

## The lessons

| # | File | Concept | Chapter |
|---|---|---|---|
| 01 | [01_first_commit.st](01_first_commit.st) | A space, a database, roots and a first commit; reading it back from a new space | [01](../../docs/tutorial/01-first-commit.md) |
| 02 | [02_values_and_versions.st](02_values_and_versions.st) | Collections are values: every change answers a new version; zero-based lists | [02](../../docs/tutorial/02-values-and-versions.md) |
| 03 | [03_records.st](03_records.st) | Record classes (`PBObject` subclasses), type names, reserved behaviour names, new versions of records | [03](../../docs/tutorial/03-records.md) |
| 04 | [04_collections_and_queries.st](04_collections_and_queries.st) | Dictionaries, sets, counted sets, tuple keys; queries as walks and hand-kept indexes; `proto_db`'s indexes read (maintained and queried from chapter 17 on) | [04](../../docs/tutorial/04-collections-and-queries.md) |
| 05 | [05_transactions_and_conflicts.st](05_transactions_and_conflicts.st) | Snapshots, read sets, `PBConflictError`, abort, `run:` retries | [05](../../docs/tutorial/05-transactions-and-conflicts.md) |
| 06 | [06_blind_writes.st](06_blind_writes.st) | Blind writes merge; counted sets compose; `replace: true`; lists replace | [06](../../docs/tutorial/06-blind-writes.md) |
| 07 | [07_mutables_and_history.st](07_mutables_and_history.st) | `PBMutableObject` cells, history, `snapshotAt:`, as-of reads | [07](../../docs/tutorial/07-mutables-and-history.md) |
| 08 | [08_bytes.st](08_bytes.st) | A 1 MiB `ByteArray`; what a new version costs on disk; chunking | [08](../../docs/tutorial/08-bytes.md) |
| 09 | [09_actors.st](09_actors.st) | Four writer actors and an auditor actor on one database | [09](../../docs/tutorial/09-actors.md) |
| 10 | [10_crash_recovery.st](10_crash_recovery.st) | A torn tail, a torn `space.root.tmp`, and a writer killed with `SIGKILL` | [10](../../docs/tutorial/10-crash-recovery.md) |
| 11 | [11_python_interop.sh](11_python_interop.sh) | protoST and Python's `proto_db` on one directory | [11](../../docs/tutorial/11-python-interop.md) |
| 12 | [12_refusals.st](12_refusals.st) | What is refused, and what each refusal protects | [12](../../docs/tutorial/12-refusals.md) |
| 11 | [11_indexed_interop.sh](11_indexed_interop.sh) | Indexes written by Python, changed and merged onto by protoST, validated by Python (0.3.0); a vector index the same way, queried by Python (0.4.0) | [11](../../docs/tutorial/11-python-interop.md#indexes-from-both-sides) |
| 17 | [17_indexes.st](17_indexes.st) | Indexes are part of the collection version; key specs; extractors (0.3.0) | [17](../../docs/tutorial/17-indexes.md) |
| 18 | [18_queries_and_plans.st](18_queries_and_plans.st) | `PBQuery`, `PBField`, `explain`, and why the planner sometimes scans (0.3.0) | [18](../../docs/tutorial/18-queries-and-plans.md) |
| 19 | [19_ordered_reads_and_pages.st](19_ordered_reads_and_pages.st) | Ordered reads, windows by rank, the obvious paging against a pager, stable pages over one snapshot (0.3.0) | [19](../../docs/tutorial/19-ordered-reads-and-pages.md) |
| 20 | [20_vector_search.st](20_vector_search.st) | Vector indexes, nearest neighbours with and without conditions, thresholds, correctly rounded scores, `x ** 2` against `x * x`, IVF-Flat recall, hnsw refused (0.4.0) | [20](../../docs/tutorial/20-vector-search.md) |

Helpers (never run as tests, because their names start with `_`): `_lesson.st` (the checks),
`_crash_writer.st` (the process lesson 10 kills), `_interop_write.st` and `_interop_read.st` (the
protoST steps of lesson 11), `_indexed_change.st` (the protoST step of lesson 11's indexed part).
`11_python_side.py` and `11_indexed_python_side.py` are lesson 11's Python steps.

Lesson 10 starts a second protoST process; it finds the binary through the `PROTOST` environment
variable (the test runner sets it), or `protost` on the `PATH`.

## See also

- [docs/tutorial/erp.md](../../docs/tutorial/erp.md): the guided build of a small ERP, one script, with
  the reasoning behind each design choice.
- [examples/erp/](../erp/README.md): the ERP demo, Python and protoST on one directory.
