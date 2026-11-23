# protoBaseST tutorial

A chaptered tutorial: twelve chapters, one concept each, each walking one program of
[examples/tutorial/](../../examples/tutorial/README.md); four chapters on cluster mode, with the
programs of [examples/cluster/](../../examples/cluster/README.md); and two orientation chapters for
readers who know an object database already.

protoBaseST is a Smalltalk implementation, on protoST, of the Python object database `proto_db`
(developed in the [protoBase repository](https://github.com/gamarino/ProtoDB)); it reads and writes
the same files. It stands in the tradition GemStone opened: objects persist as objects, reachable
from named roots. **It is a proposal prototype for the FAST Smalltalk workshop (2026-12-03), not a
product.** It is small, meant to be correct, and slow (the measured figures are in
[deviations.md](../deviations.md#performance)). Read [not-done.md](../not-done.md) before you
judge it.

## If you come from another object database

- [Coming from GemStone/S](gemstone.md): sessions, `commitTransaction`, persistence by
  reachability, indexes, class history, the Stone and the shared page cache, mapped one by one to
  what protoBaseST does, does differently, or does not do.
- [Coming from Soil](soil.md): Soil's root, `markDirty:` and change detection, MVCC with a global
  commit lock, append-only heap and journal, behaviour descriptions, mapped the same way.

Both chapters cite their sources and mark what could not be confirmed. Both systems are mature and
in production; protoBaseST is not offered as a better one. What it offers is Smalltalk code reaching
where it could not before: a file format shared with Python, immutable values, and a multi-core
runtime.

## The chapters

Every chapter quotes its program. The quoted code is checked against the program by
`tests/docs/tutorial_chapters_sync.sh`, and the programs are run by `tests/run_tests.sh`, so the
code you read here runs. The prose is not checked by a machine.

| # | Chapter | Program |
|---|---|---|
| 1 | [A space, a database and a first commit](01-first-commit.md) | `01_first_commit.st` |
| 2 | [Values and versions](02-values-and-versions.md) | `02_values_and_versions.st` |
| 3 | [Records](03-records.md) | `03_records.st` |
| 4 | [Collections and queries](04-collections-and-queries.md) | `04_collections_and_queries.st` |
| 5 | [Transactions and conflicts](05-transactions-and-conflicts.md) | `05_transactions_and_conflicts.st` |
| 6 | [Blind writes merge](06-blind-writes.md) | `06_blind_writes.st` |
| 7 | [Mutable objects and history](07-mutables-and-history.md) | `07_mutables_and_history.st` |
| 8 | [Bytes and the cost of a version](08-bytes.md) | `08_bytes.st` |
| 9 | [Actors](09-actors.md) | `09_actors.st` |
| 10 | [Crashes and reopening](10-crash-recovery.md) | `10_crash_recovery.st` |
| 11 | [One directory, two languages](11-python-interop.md) | `11_python_interop.sh` |
| 12 | [What is refused, and why](12-refusals.md) | `12_refusals.st` |

### Cluster mode (0.2.0)

Several protoST processes sharing one database directory: a peer lease elects an owner, the owner
issues write permissions, commits are acknowledged by a majority, faulty nodes are fenced, and a
node that lost its disk rejoins by a ballot, and each node's persister writes the committed root
to `space.root` afterwards (`sync:` waits for it). Chapter 13 needs no code; every program of
chapters 14 to 16 runs. What a cluster costs, measured on one machine, is in chapter 16.

| # | Chapter | Programs (in `examples/cluster/`) |
|---|---|---|
| 13 | [The ideas behind cluster mode](13-cluster-concepts.md) | `13_terms_and_majorities.st` |
| 14 | [A three-node cluster](14-a-three-node-cluster.md) | `14_three_nodes.st`, `14_three_nodes_tcp.st`, `14_cluster_commits.st` |
| 15 | [Failures and recovery](15-failures-and-recovery.md) | `15_losing_members.st`, `15_wiped_disk.st`, `15_majority_loss.st` |
| 16 | [Operating a cluster](16-operating-a-cluster.md) | `16_configuration.st` |

### Indexed queries (0.3.0)

> These chapters were written before the code, from the approved
> [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md), and made
> runnable task by task. The programs of chapters 17, 18 and 19 run as tests, and every figure is
> quoted from [deviations.md](../deviations.md#queries-and-indexes). The concepts are in
> [queries.md](../queries.md).

| # | Chapter | Program |
|---|---|---|
| 17 | [Indexes](17-indexes.md) | `17_indexes.st` |
| 18 | [Queries and the planner](18-queries-and-plans.md) | `18_queries_and_plans.st` |
| 19 | [Ordered reads and pages](19-ordered-reads-and-pages.md) | `19_ordered_reads_and_pages.st` |

Chapter 11 also gains a section, "Indexes, from both sides" (`11_indexed_interop.sh`).

### Vector search (0.4.0)

> Chapter 20 was written before the code, from
> [Addendum V](../superpowers/specs/2026-11-19-vectors-addendum.md) to the indexed-queries spec,
> and made runnable by the vectors tasks; its program runs as a test, and every figure is quoted
> from [deviations.md](../deviations.md#vectors). The concepts are in
> [queries.md, Vector search](../queries.md#vector-search).

| # | Chapter | Program |
|---|---|---|
| 20 | [Vector search](20-vector-search.md) | `20_vector_search.st` |

Chapter 11's section "Indexes, from both sides" covers a vector index too (`11_indexed_interop.sh`).

## Running the programs

You need protoST 0.14.1 or newer and this repository's `src/` on the module path (README,
"Requirements"):

```sh
export PROTOST=../protoST/build_release/protost
cd examples/tutorial
STPATH=$PWD/../../src $PROTOST 01_first_commit.st
```

Each program prints `ok - ...` per check and ends with `<lesson> ok (N checks)`; a failed check
prints `FAIL - ...` and exits with status 1. Chapter 11 also needs the Python venv
(`tests/interop/setup_venv.sh`).

## Two rules to read first

Both are explained in chapter 2, and both surprise Smalltalk programmers:

- **Every collection message answers a new version.** `add:`, `remove:`, `removeAt:` and
  `setAt:value:` leave the receiver unchanged. A statement that discards the answer changes
  nothing, and nothing fails.
- **`PBList` positions are zero-based**, as in `proto_db`. Every other collection is one-based.

## Other documentation

- [erp.md](erp.md): the guided build of a small ERP in one script, with the reasoning
  behind each design choice. These chapters split the same ground into small programs and add
  bytes, actors, crashes and the refusals; read either first.
- [reference.md](../reference.md): every public class and message, the indexed-query API
  included.
- [queries.md](../queries.md): indexed queries and the query planner, the conceptual guide
  (0.3.0), with its section on vector search (0.4.0).
- [deviations.md](../deviations.md): every difference from `proto_db`, every refusal, and the
  performance figures.
- [decisions.md](../decisions.md): the choices, with what each costs if it is wrong.
