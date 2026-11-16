# What is not done

The text for the "what is not done" slide, and its detail. protoBaseST is a proposal prototype.
It is shown to start a discussion and to collect criticism, so the list of what it does not do is
as important as the list of what it does. Everything here is either a stated non-goal of the
design (spec section 2) or a cut made while building, with its reason.

## The slide

- Not a product, not production ready, and not fast.
- What is shown: one directory, opened by Python and by protoST, gives the same answers in the
  scenarios tested (below). Nothing outside those scenarios is claimed.
- Cluster mode (0.2.0, unreleased) runs over **one shared directory** only: no tiered storage
  (Phase D), no pipelined permits (DEPTH 1), no mixed clusters with `proto_db` nodes (a
  non-goal), no TLS (frames are plaintext; an optional HMAC authenticates them), no read-only
  barrier, no notify. A three-member cluster commits about half as many small transactions per
  second as one standalone process on disjoint roots, and a third as many on one hot key ([deviations.md](deviations.md#cluster-mode-commits-per-second)).
- No cloud or tiered storage, no durability mode other than `fsync`, no Windows.
- No writes to indexed collections, no merges onto them, no index queries, no vector-index
  writes or training.
- No writes to `RepeatedKeysDictionary`.
- No IANA time zones: no wall-clock conversion; a fixed pinned list of zone keys.
- No runtime registry and no symbol kind (`@sym`): format 5 (`proto_db` 2.0.0rc4, D62) is
  known, not adopted, and refused.
- No query planner or LINQ, no pagers, no `snapshot_ref` byte references, no
  residency.
- No rebuilding of format-3 indexes, no `validate()` or `rebuilt()` of misfiled format-3
  collections.
- No frozen instances: immutability is a convention, checked by a test, not enforced at run time.
- No business rules in the core: no constraints, schema checks or `ondelete` rules. Application
  classes keep them (the Odoo lesson).

## What was tested, and what was not

Tested, with the `proto_db` at `v2.0.0rc2` reference (re-run at `v2.0.0rc4`, at format 4, on the
cluster branch):

- the conformance vectors of the tag, for every layer protoBaseST implements (no vector is skipped;
  three differences are on purpose, see [deviations.md](deviations.md));
- both directions of the round trip: spaces written by `proto_db` are dumped identically by
  protoBaseST, and spaces written by protoBaseST pass `proto_db`'s verifier with an identical dump,
  including values at the integer boundaries, the boxing threshold by code points, and nesting at
  1022 and 1023 containers;
- tree shapes: 1000 seeded list operations, a larger dictionary replay, and multi-entry hash
  buckets are compared with `proto_db` node by node, byte for byte;
- concurrent commits from both languages in 27 scenarios, each run with both roles, plus the same
  table driven by two protoST actors, with `proto_db`'s recorded outcomes;
- crash states a writer can leave on disk, read by both languages, and the root lock excluded in
  both directions;
- the ERP demo, a clean-clone run included.

Not tested, or not proven:

- **Anything outside those scenarios.** No fuzzing of the codec against `proto_db` beyond the
  vectors, the seeded sequences and a few dozen hand-picked edge values.
- **Other `proto_db` releases.** The reference is `v2.0.0rc2` (the cluster branch: `v2.0.0rc4` at
  format 4, protocol 14). A newer release may differ.
- **Format 5 and the runtime registry** (`proto_db` 2.0.0rc4, D62): refused with
  `PBNotSupportedError`, not read or written. Its own plan follows the cluster branch
  (`docs/superpowers/specs/2026-11-15-rc4-delta.md`, section 3b).
- **Phase D of the cluster (peer fetch):** the fetch service, `commit_query`, their read capping
  after a lease expires (R212) and the `unknown` answers of a member that cannot tell (R240L,
  R234L-R245L) are not ported; the port ignores `fetched` and `commit_info` at DEPTH = 0. Nor
  are the local-records tier's rules: `await_records`, and `_BaseUnreachable` (I1, R133: a base
  whose records are on no reachable peer abandons the term).
- **Speed.** The AVL workload is many times slower than `proto_db`'s. The dated figures, and how
  they were measured, are in [deviations.md](deviations.md#performance); they are indicative only.
- **Memory and long runs.** A segment rolls over at 256 MiB as `proto_db`'s does; nothing was run
  near that size.
- **Heavy contention.** The lock backoff no longer blocks the caller's worker (CC10); the
  caller's single wait on its commit's `Future` still does, while the worker serves other actors
  (K23 in [deviations.md](deviations.md#known-protost-limits)). Hot keys were measured with four
  writers per process and at most three processes, nothing heavier.
- **Cluster mode, not yet proven.** The timer audit (every timer at a tenth, ten times and
  skewed, 3420 simulator runs) and the long soak (5000 seeds per family, `PBST_SIM_SEEDS`) run
  only in the final verification (Task 30); until then the claim that timers decide liveness
  only rests on the default seeds and the audit's earlier per-part runs. The real-process tests
  (Tasks 27 and 28: `kill -9` of the owner, of a voter, of a holder at three points of its
  round, of the whole cluster, and a lost log) ran three times each with drawn seeds: strong
  evidence, not a proof. Nothing ran on several hosts, on a network file system, with more than
  five members, or for hours. The cluster measurements are one machine's, indicative only.
- **The whole thing is one implementer's work, reviewed task by task.** It has not had outside
  review. That is what the workshop is for.

## The cuts

| Item | State | Why | Cost |
|---|---|---|---|
| `CountedSet` | **Done** (ruling R22), first a stretch goal | Time allowed, and cutting it would have left `PBCountedSet` mutators refusing. | None. |
| Framed log reader (`PBFramedLog`) | Written, removed (ruling R14), **re-ported** with the linear search in cluster Task A1 (`cluster/log.st`) | The spec lists framed logs as a non-goal and nothing in protoBaseST reads them; an uncalled reader is debt. Its worst case was quadratic. | Done in cluster Task A1 (linear prefix-checksum search). |
| `asOf:` | Not added | `proto_db` has none. | A three-line helper in each program. |
| Symbolic link to the acceptor log file | **Done** (cluster Task 4 follow-up, protoST 0.12.0) | `proto_db`'s `RootsLog` resolves the log path with `os.path.realpath` before it names `<path>.lock` (8.3d re-review 12, M3). Before the fix `PBAcceptorLog path:` named the lock after the path as given, and review reproduced two live handles on one log through a symbolic link (two lock files, promises 5, 3, 4 appended). `path:` now resolves `FileReference >> realPath` (protoST 0.12.0) before it names the lock and uses the real path as the log's path; `tests/unit/cluster_acceptor_log.st` case 11 is the reproduction, refused. The space's `space.lock` needs no resolution, as in `proto_db`'s `FileStorage`: it lives inside the space directory (`tests/unit/store_root_lock_alias.st`). | protoST 0.12.0 is now the floor. The in-process inode registry of `OwnerLock` (`track`) is not ported: within one process the OS lock on the one lock file already refuses a second open. |
| Hard-link check of framed logs | **Done** in cluster Task 4 | `proto_db`'s `open_log` refuses a log file with more than one hard link (`ProtoLockingError`) before reading or repairing it (`logfile.py:283-290`), because the path-named `.lock` file only excludes a second opener when a log has exactly one name. protoST 0.11.0 added `BinaryFile >> linkCount`; `PBFramedLog openAppend:kind:` refuses such a file with `PBLockingError` at the same point, after `PBAcceptorLog` took its lock. | protoST 0.11.0 was the floor then (0.12.0 now). |
| Cluster held retries | **Done** (cluster Task 23) | Ported with the commit round. | |
| Phase D: tiered storage and peer fetch | Not done | Shared storage first (Q1); `fetch`, `commit_query`, read capping (R212), `unknown` answers, the local-records rules (`await_records`, R133's `_BaseUnreachable`) and log kinds 5 and 6 belong to it. Its options are refused. | Multi-host needs a shared file system whose `flock` is reliable. |
| Pipelined permits (DEPTH 1) | Not done | Q3: DEPTH 0 first, pipelining after measurement. The measurement now exists (deviations, Performance). | One permission at a time: adding members does not add throughput. |
| Mixed clusters with `proto_db` nodes | Not a goal | Design spec section 4. The data is shared (Task 26); behaviour across implementations is not tested. | A cluster is all protoBaseST or all `proto_db`. |
| TLS | Not done | protoST has no TLS server; the optional HMAC (CC4) authenticates, it does not encrypt. | Trusted networks only. |
| Read-only barrier | Not done | `proto_db` has none either (CC9): a barrier is a commit that writes. | Every barrier is a version in `history`. |
| Notify | Not done | `proto_db`'s notify is not ported. | Readers learn new commits by reading. |
| The persister's timers at a tenth and ten times (final review M7) | Not done | The timer audit's persist row (`tests/audit/sim_timer_audit_persist_*`) scales `persistInterval` and `persistLag`, but the simulator reads neither, so those runs cannot exercise the persister's timers. The persister's liveness at those values is unaudited: its refresh period, and the lag write by a member that did not commit the root. | What would close it: count the persist parts out of the audit's run total (or drop them from the audit), and add a `tests/unit/cluster_persister.st` case at a tenth and at ten times the defaults that asserts `sync:` returns and that a non-committer persists a root once `persistLag` has passed. |
| A real-process pause test (final review M8) | Not done | `tests/cluster` kills members with `kill -9` but never pauses one (`kill -STOP`, then `kill -CONT`). That is the real-clock, real-TCP check of a stale holder or owner, the property "safety never depends on timing" rests on. It is covered only in the simulator (a stalled clock) and in one process (`cluster_commit_path.st` (9)). | What would close it: a `tests/cluster/real_pause_holder.sh` that stops the holder once its root is built, waits until the others' lease on it has passed, resumes it, and checks with the verifier that the counters are exact and that the resumed holder's commit ends `#none` or unknown and is never applied twice. |
| Index maintenance | Not done | Out of scope (design 7.4). Refused explicitly rather than done partly. | A database with indexes can be read, not changed in its indexed collections. |

## What would come next, if the workshop wants it

In the order the cost of the omission is felt:

1. Index maintenance and merges onto indexed collections. Without them protoST cannot change an
   indexed collection, which limits the shared-directory story to databases without indexes.
2. The `@sym` kind, once format 5 defines it, with the explicit symbol wrapper in protoST.
3. A time-zone database in protoST, so zoned datetimes have a wall clock.
4. Speed of the record and node paths, which is protoST VM work more than library work.
5. For the cluster: Phase D (tiered storage), once Phases A-C are reviewed, and pipelined permits
   if the measured throughput matters to someone.
6. The runtime registry (format 5), in its own plan.
