# protoBaseST cluster mode: analysis and design proposal

- **Date:** 2026-11-13
- **Status:** APPROVED in direction by the maintainer on 2026-11-13 (answers to Q1-Q8 in section
  8.4). Implementation is planned for the release after the first public protoBaseST (0.1.0), which
  ships without cluster mode. No code is written yet.
- **Maintainer's request:** "analizar también la implementación de clusters, tal como lo hace
  protoBase. no veo razón para no cubrirlo."
- **Maintainer's ruling (2026-11-13, received during the analysis):** mixed Python/Smalltalk
  clusters are **not a goal**, at least not initially. The goal is a **protoBaseST-only cluster
  that follows `proto_db`'s path**: its decisions, the mistakes it fixed, the approaches it
  reverted (D5), its failure model, its tests and its conformance vectors, so that protoBaseST does
  not repeat those errors. The on-disk format stays shared, as it is today. The wire protocol does
  not have to be byte-identical unless that costs nothing.
- **Reference read:** `ProtoBase` at `7786974` (tag `v2.0.0rc3`). Between `v2.0.0rc2` (the tag
  protoBaseST pins) and `v2.0.0rc3`, `proto_db/cluster/`, `proto_db/storage/logfile.py`,
  `proto_db/storage/tiered.py` and `tests/conformance/vectors/` are unchanged
  (`git diff --stat v2.0.0rc2 HEAD` over those paths is empty), and `PROTOCOL_VERSION` is 13 in
  both. Everything below holds for both tags.
- **protoBaseST** at `7ef11d7` (branch `feat/prototype`). **protoST** at `bc0ce63` (branch
  `feat/protobase-support`). **protoIO** at `fe9130b` (0.5.0).

Contents:
[0. Summary](#0-summary) |
[1. How proto_db's cluster works](#1-how-proto_dbs-cluster-works) |
[2. Lessons from proto_db's cluster history](#2-lessons-from-proto_dbs-cluster-history) |
[3. Gap analysis](#3-gap-analysis) |
[4. Interoperability: a short note](#4-interoperability-a-short-note) |
[5. Design proposal](#5-design-proposal) |
[6. Test strategy](#6-test-strategy) |
[7. Interaction with the commit-performance work](#7-interaction-with-the-commit-performance-work) |
[8. Phased plan, risks and open questions](#8-phased-plan-risks-and-open-questions)

---

## 0. Summary

- **It is feasible without any protoCore change and without any protoIO change** for the
  recommended first scope. protoST 0.10.0 already provides what the coordinator needs: TCP
  sockets (`net`), actors with three priority bands, `Future after:`/`within:` timers on a
  monotonic clock, `Atom` compare-and-swap, `BinaryFile` with positioned writes, `append:`,
  `sync`, `truncateTo:` and `flock` (`tryLock`), `FileSystem syncDirectory:`, `MessagePack`
  (ordered maps), `crc32` and `ByteArray randomBytes:`.
- **Recommended scope (Phases A-C): a cluster over a shared `PBFileStorage`**, the port of
  `proto_db`'s `PlainTier` (`proto_db/cluster/persister.py:110-245`). Every member reads and
  writes one directory; each member keeps its acceptor log in `cluster/<node>.roots`. This gives the
  whole coordination protocol (lease, terms, permissions, acceptance, recovery, rejoin, unknown
  outcomes, held retries, persister) without tiered storage, record shipping or an object store.
- **Deferred (Phase D, separately approved): tiered storage with an object store.** It is the
  bigger half of `proto_db`'s cluster (`storage/tiered.py` is 2,353 lines; bounded replication,
  kind-5/6 acceptor entries, redo, checkpoints, parts and sealed markers) and it needs protoST/protoIO
  work (HTTP binary bodies and keep-alive for S3; RSA signing for GCS).
- **The biggest gaps** are all in protoBaseST: the framed log (removed by R14, must be re-ported
  with the linear search), the acceptor log, the wire messages, the coordinator itself (4,279 lines
  of Python, to be rewritten in a different shape, not translated), a group-commit round runner
  that replaces the single publisher in cluster mode, and a deterministic simulation harness.
- **Shape of the port:** a *sans-IO* core. Every rule is a pure transition over immutable state
  values (`state, event, now -> state', effects`), and actors are thin shells that hold one state
  value each, perform the effects (sends, log appends, timer requests) and never wait (ruling R19).
  The same core runs in a single-threaded, seeded, virtual-time simulator for the safety tests, so
  **no test depends on timing**.
- **Effort, honestly:** about 47 engineering days for Phases A-C (about 10 weeks for one person),
  plus about 21 days for Phase D. `proto_db` needed tasks 8.3c to 8.3n and dozens of review fix
  rounds to reach its current protocol. Porting the end state skips the design iterations, but not
  the reviews. The estimate has a wide error bar (section 8).
- **Performance interaction:** in cluster mode the build of a commit (validation, merge, path
  copy, new root) runs under a cluster-wide permission. Its cost bounds the throughput of the
  *whole cluster*, not of one process. The 50-70 ms per commit reported by the profiling work
  (figure from the brief, not measured here) would cap a protoBaseST cluster at roughly 10-15
  commit rounds per second. Cluster mode makes the profiling work more important, not less
  (section 7).

---

## 1. How proto_db's cluster works

This is a digest for porting. The normative documents are
`ProtoBase/docs/source/coordinator-protocol.rst` (written explicitly "for an implementer
(protoBaseST, for example) who must reproduce the behaviour without reading the Python code",
lines 4-6), the byte layouts in `ProtoBase/docs/source/format-spec.rst` lines 1434-1662, and
decisions D44-D55 in `ProtoBase/docs/decisions.md` (D44 at line 318, D45 at 328, D46 at 343, D50 at
658, D54 at 859, D55 at 872). Where this digest and those documents differ, they win.

### 1.1 The premise and the governing principle

Several processes, each with the database embedded, write one database. A commit builds a new
root on the root it read, after validating the read set (D34) and merging intents (D33). Two
processes must never both publish a root built on the same predecessor, and an acknowledged
commit must never disappear (coordinator-protocol.rst:33-42).

**P5 / ruling R82: timing never decides safety.** Every safety argument must hold under arbitrary
delay, loss, duplication and reordering of messages, arbitrary process pauses and timers running at
different rates. Timers drive liveness only, and when one fires the result is a conservative
failure: a timeout, an abandoned term, a refused or retried commit, or an unknown outcome
(coordinator-protocol.rst:14-18, 873-951).

### 1.2 Roles and membership

- **Static membership**: a list of peers `(node_id, host, port)`; no dynamic membership (D54).
  The **rank** of a member is its index in the member ids sorted in code-point order.
- **Voters**: a fixed, odd set of `V = 2f + 1` members (default: the first three ids; every
  member of a smaller cluster). A majority is `f + 1` voters. The others are **learners**: they
  never grant, accept or count, but may own a term and commit. Messages carry `vs`, the CRC-32 of
  the voter ids sorted and joined with `","`; a member configured with another voter set drops
  them (coordinator-protocol.rst:66-79; format-spec.rst "Values a member must compute").
- **Owner**: the member holding the lease of a term; it hands out **write permissions**, first
  come first served, its own threads included. It never commits another member's transactions
  (P3, R66d).
- **Holder**: a member that holds a permission and runs one commit round of its own transactions.
- **Data replica** (tiered storage only): the `f` members following the committer in id order.
- **Witness**: a voter whose answers count: log loaded, rejoined marker present, tier healthy,
  not fenced.

### 1.3 State

In memory, under one lock in `proto_db` (coordinator-protocol.rst:98-119): grant state
(`PeerGrants`: highest term seen, highest term granted or closed, `granted_top`, the active grant,
end of startup grace); the **accepted** root and the **committed** root, each with its label;
suspicion (`_suspect_term`); the **incarnation** `inc` (random 62 bits per start; replies to
another incarnation are dropped); hints (highest term heard of, owner hint learnt only from
messages that prove a term was won); ownership (lease, queue, pipeline of issued permissions,
next base); the current permission; rejoin state.

On disk per node: the **acceptor log** (`roots.log` in tiered storage, `cluster/<name>.roots` in a
shared `FileStorage`). It is `fsync`-ed before the reply it justifies **in every durability mode**
(defect D-SAFE-2): the promise before the grant, the acceptance before the acknowledgement, the
rejoined marker before the node votes. A *committed* entry is knowledge, appended without its own
sync (R67) (coordinator-protocol.rst:121-137).

In storage: segments, and the **persisted root**, written later by each node's persister by
compare-and-swap and never moved backwards in root order. Nothing is deleted.

### 1.4 Invariants

Promise rule; ballot rule; S1 (one owner per term); S2 (one chain per term, resting on the owner's
sequencing code, R79); S3 (chain rule); S4 (committed roots survive terms); S5 (superseded holders
are fenced); V1 (`store` is never an acceptance); V2' (Raft log matching on roots); copies rule;
"root and records together"; atomic acceptor steps (decision, log write and in-memory publication
in one step, reply after); outcome truth H7; root order `(label, epoch, segment, offset)`, with two
different roots of equal label and epoch being `ProtoCorruptionError`
(coordinator-protocol.rst:153-228). The timing exclusion of the lease and the pipelined gate (H5)
are deliberately **not** invariants.

### 1.5 Lease, terms and fencing (phase 1)

`coordinator-protocol.rst:252-318`, D45, D46, D50:

1. Local threads queue on a local lock; only the head asks. Fairness hints (`next`, `more`,
   `want`) time requests only.
2. **Ballot**: `term = ballot_after(max(highest seen, hint, accepted label, committed label),
   rank)`, the smallest term above everything known whose low 12 bits (`RANK_BITS`) are the
   proposer's rank: `((floor - r) // 4096 + 1) * 4096 + r`. Two proposers never ask for the same
   term.
3. Own vote under the acceptor-log lock; `request(term, rid, inc, vs)` to the other voters; own
   promise made durable (failure withdraws the own vote).
4. A voter refuses when fenced, learner, no log, tier failed, rejoining, `bad_ballot`, `starting`
   (startup grace), `stale_term`, `busy` (with the remaining promise) or `term_taken`. Otherwise it
   `fsync`s the promise, then sends `grant` carrying its accepted root (with label), its committed
   root and `certain`.
5. **Winning**: grants from a majority received before `valid_until = sent_at + lease_duration -
   drift_margin`, on the requester's clock **measured from the send**. The highest reported root
   in root order is the **phase-1 value** (`lease.root`). The lease is *certain* when every granter
   knows a root, none is suspect and the requester is not suspect.
6. **Losing**: cancel (`release`, `held=False`), jittered back-off, ended early by any release.
   *Erratum (Task 11):* `proto_db`'s code (`coordinator.py` `_back_off`, N7/M2) ends the back-off
   itself only on progress (a held release, a newly learnt owner); any release ends only its busy
   extension. protoBaseST follows the code, as the ruling of Task 5 (code over spec wording).
7. **Owning**: an ownership thread renews at half the belief while there is demand (`renew`; no
   log write: the promise is already durable).
8. **Releasing**: idle for `lease_duration / 4`; the release closes the term at every receiver and
   carries the committed root and `certain`.

Timing argument (not a safety premise): `drift_margin >= 2/3 lease_duration` (R78b), so the
holder believes for at most a third of the promise. **The fencing token is the term itself**: the
ballot rule at the voters refuses any root labelled below `granted_top`, and the persisted-root
compare-and-swap never replaces a root that orders at or above its own (coordinator-protocol.rst:
305-317). The storage CAS is fencing only (D44 reverted D5).

### 1.6 Choosing the base of a term's first root

The holder's choice of base decides what the history keeps (`_lease_base`,
`proto_db/transactions.py:1243`; coordinator-protocol.rst:327-405):

1. certain lease or permit, or a permit on a proposal: `lease.root`;
2. uncertain: a **recovery round** (`query`, ballot 0) to the voters, ending at a majority of
   witnesses;
3. **phase-1 floor** (R127): the base is the higher of `lease.root` and the recovery result
   (`_phase_1_floor`, `transactions.py:1321`);
4. nothing known anywhere: **refound** from the persisted root, terms raised by `2**44`;
5. stale base: the round sends nothing, its commits go back to the head of the queue, the
   permission ends `unknown` and the owner abandons the term;
6. hard guard: the base never orders below the known committed root (else refound or
   `ProtoCorruptionError` naming `force_rejoin()`);
7. re-commit an uncommitted base first (`_commit_base`, `transactions.py:1397`, R50);
8. an unreachable base abandons the term (R133).

### 1.7 Phase 2: permissions and the commit point

`coordinator-protocol.rst:427-491` (figure `seq-commit`):

1. New atoms are written to the local tier before any permission. Commits join the node's
   **group**: one round per node at a time; the thread that finds none running takes everything
   queued (D50, D52).
2. `permit_req(term, rid, inc)` to the known owner; none known: try to own.
3. The owner issues under rule O1: queue not empty, term serving, at least a quarter of the
   belief left (else renew first), pipeline within `DEPTH`. `permit(term, rid, seq, inc, root,
   certain, valid, after)` carries the base and the owner's remaining lease.
4. The holder measures `valid` from its *send* of the request.
5. Base (1.6), then each queued transaction is built in turn on the root the previous one
   produced; a conflicting transaction fails alone.
6. **Reserve** (R121): with less than `send_reserve` left, nothing is sent and the round ends with
   a retryable `ProtoConflictError` (H7).
7. `replicate(term, rid, inc, root, committed, records, chunks, base, base_ranges, seq, pred, vs,
   copies, ranges)` to the voters (tiered: first to the `f` data replicas, then the root alone).
8. A voter accepts when: running, ballot rule, `label == term`, root order not below its accepted
   root, V2', `seq` not below the highest it accepted in the term, no sibling, copies rule. One
   synced append, publish, then `ack(ok, stored)`.
9. **The commit point**: a majority of voters (holder included) acknowledged, observed within the
   permission.
10. `done(term, seq, inc, outcome, root, copies, ranges)` is broadcast; the owner sequences on it;
    every member learns the committed root.
11. The persister writes the newest committed root later, by CAS, never backwards.

**Owner rules O1-O8** and **holder rules H1-H7** (pipelined permissions, `DEPTH = 1`, gate H5):
coordinator-protocol.rst:493-576.

**Held retries** (D50 amendment, D-LIVE-2): when a transaction of a round conflicts and
`Database.run` will retry it, the round keeps the permission (up to `_PERMIT_RETRIES = 3` extra
rounds while valid, `transactions.py:851`) and waits up to `_RETRY_HOLD = 0.1 s`
(`transactions.py:857`) for the retry, which starts from the root just committed. The conflict is
marked `permit_held` and retried at once (`transactions.py:1208`).

### 1.8 Outcomes

Every permission ends `committed`, `none` (nothing acceptable left the node: retryable
`ProtoConflictError`) or `unknown` (`ProtoOutcomeUnknownError`, never retried automatically; the
owner abandons the term and the next phase 1 decides). After convergence every acknowledged commit
is present and every unknown one is present everywhere or absent everywhere
(coordinator-protocol.rst:579-621).

### 1.9 Failure handling

- **Owner loss / partition**: a member whose `permit_req` gets no answer within one
  `lease_duration` forgets the owner and tries to own; voters refuse `busy` until the old grant
  expires on their clocks, then promise the new term; from each promise on they refuse the old
  term's roots, so the minority side cannot complete a majority (ballot rule) and its
  `acquire` times out (coordinator-protocol.rst:407-424).
- **Process crash, disk intact**: new incarnation; the log restores the promise and accepted root;
  startup grace (efficiency since R82); a **confirmation commit** (an empty commit under a
  permission) runs before the first snapshot after every attach, so reads never go backwards
  (coordinator-protocol.rst:652-672).
- **Disk lost**: the **rejoin ballot** (R78a): plain round, decision `new` / `rootless` /
  `witnesses`, then a ballot above everything reported, answered by `V - majority + 1` witnesses,
  then fetch records, then log promise, accepted root, rejoined marker (coordinator-protocol.rst:
  674-715). Losing a majority of logs is outside the failure model; `force_rejoin()` after an
  operator's decision.
- **Tier failure** (R57): a failed write is never acknowledged; the node refuses everything until
  reopened on a healthy disk. **Fenced**: an unexpected exception in a lane fences the node for the
  life of the process.
- **Torn writes**: framed logs drop a torn tail and refuse mid-log corruption (1.10). Segments are
  repaired record by record (tiered).

### 1.10 Framed logs and the acceptor log

`format-spec.rst:1434-1552`. Header (14 bytes): `PDB2LOG\0`, `u16` version 2, 4-byte kind (`ROOT`,
`RANG`, `SEGS`). Frames: magic `C1 F7`, `u32` length > 0, CRC-32 of the payload, CRC-32 of the 10
bytes before it, payload. At the first invalid position a reader decides **torn tail** (dropped)
versus **mid-log corruption** (`ProtoCorruptionError`) by searching for any later valid frame; a
writer truncates a torn tail and `fsync`s before appending. Acceptor-log entry kinds: 1 accepted,
2 committed, 3 promise, 4 rejoined (41 bytes each), 5 accepted root with every record of its
replication, 6 replica entry with ranges and a flag (tiered). A log without kind 4 is *empty*: the
node must rejoin. Two entries with different roots and equal `(label, epoch)` are corruption.

### 1.11 Wire protocol

`format-spec.rst:1554-1661`, `proto_db/cluster/protocol.py:169-175`, protocol version 13:

- Frames: 4-byte **big-endian** length, then one msgpack map. `MAX_FRAME_BYTES` 64 MiB, records
  chunked at 16 MiB. No handshake.
- **Connections are one-way**: each node sends only on its own outbound connections and reads only
  from accepted ones; a reply travels on the replier's outbound connection.
- **Errors drop the connection** (malformed frame, missing or ill-typed field, unknown type, other
  version, non-string key), together with every message decoded from the same read. Extra fields
  are ignored.
- 22 message types: `request grant reject release records warm replicate store propose renew
  permit_req permit permit_no done ack want query answer fetch fetched commit_query commit_info`.
- **No authentication and no TLS.** `TcpTransport` (`transport.py:1-30`) is plaintext length-prefixed
  msgpack; nothing in `proto_db/cluster/` mentions TLS, HMAC or auth. A trusted network is
  assumed (not stated in the docs; an omission worth reporting upstream).
- `TcpTransport`: one listener thread with a selector over all accepted connections; one sender
  thread **per peer** (R39: a black-holed peer must not delay the others), each queue with two
  lanes (control first; best-effort `warm` bounded by bytes, dropped first).

### 1.12 Reads

A local snapshot read takes the newest root the node knows committed; it sends nothing and may
miss a commit acknowledged elsewhere a moment ago. A linearizable read is a **barrier commit**
(write something, then read). `sync()` is a durability barrier, not a visibility barrier
(coordinator-protocol.rst:783-811).

### 1.13 Notify

**Not present** in `proto_db` at `v2.0.0rc3`: no code in `proto_db/cluster/` and no decision in
`decisions.md`. It is a planned feature (cluster-wide topics, transactional, commit-only,
non-persistent). Section 5.9 only keeps a place for it.

### 1.14 Conformance vectors

`ProtoBase/tests/conformance/` (vendored in protoBaseST under `tests/conformance/vectors/`, pinned
by `vectors.sha256`), section `cluster` of `manifest.json`:

- `cluster/5eed...2002.seg`: a SpaceRoot stamped with `cluster_term`, `cluster_epoch`,
  `cluster_previous`;
- `cluster/roots.log`: every acceptor-log entry kind (4, 3, 5, 2, 1, 6 accepted, 6 stored), decoded
  field by field; `roots-torn.log` (torn tail versus mid-log corruption); `ranges.log`;
  `segments.log`;
- `cluster/messages/*.frame`: one frame of each of the 22 types, plus `unknown-root.frame`;
- the `invalid` section entries of layers `log`, `roots_log` and `message`.

Today protoBaseST prints each of these as a visible skip (`tests/conformance/cluster.st`).

### 1.15 Configuration (proto_db names)

`ClusterCoordinator(node_id, peers, *, transport, lease_duration=2.0, drift_margin=None (2/3 D),
request_timeout=0.25, send_reserve=None, acquire_timeout=30.0, backoff=(0.001, 0.05),
startup_grace=None, fetch_timeout=None, persist_interval=0.05, persist_lag=1.0,
owner_idle_release=None, voters=None, clock=None, seed=None)` (`coordinator.py:559-630`);
`ObjectSpace(storage, *, lock_timeout=None, coordinator=None)`; `stats()`, `force_rejoin()`,
`Database.sync()`, `committed_epoch`, `persisted_epoch`.

---

## 2. Lessons from proto_db's cluster history

Each row is a decision, reversal or defect of `proto_db`'s cluster work, what went wrong, the fix,
and how protoBaseST adopts the fix **from day one**. Sources: `docs/decisions.md` (D-numbers,
amendments, rulings), the design guide (`docs/source/design-guide/coordinator.rst`,
`unknown-outcomes.rst`, `pipelined-permits.rst`) and the git log (fix-round commits named).

| # | What happened in proto_db | What went wrong | The fix | protoBaseST from day one |
|---|---|---|---|---|
| L1 | 0.1 cluster: UDP voting per time window | A crashed holder or a partition could give two writers; UDP loses messages silently (D5, D44) | Removed; TCP only, majority lease with terms | No UDP. TCP only, majority grants, terms as ballots. |
| L2 | **D5/D43: storage CAS as the arbiter** of all writers | Every lost race cost object-store round trips and a retry; the write ceiling was the store's latency (D44 maintainer reversal, 2026-11-01) | Contention resolved among the processes; CAS kept only as fencing | The shared `space.root` CAS is written only by the persister, as fencing. Commits never contend on `flock`. |
| L3 | D43: trusting a failed precondition without read-back | An SDK-level retry of an applied write looked like a lost race; `Database.run` applied a transaction twice (reproduced, n=5 instead of 4) | `ProtoOutcomeUnknownError` (never retried) and the read-back rule (R35) | Already in protoBaseST's publisher (step 8). Cluster mode keeps the rule: any failure after something acceptable left is `PBOutcomeUnknownError`. |
| L4 | D45: a lease **object** rejected for CAS-only mode | A lease can expire while its holder is paused (GC, VM freeze) | The lease never carries safety; fencing does | protoST has GC pauses too. The lease is an efficiency device; the ballot rule fences. |
| L5 | D45: holder's window counted from the *win* | Grants delayed 0.3 s let two beliefs overlap (planted test) | Window measured from the **send** of the request | `validUntil := sentAt + belief`, from the send. Planted-mutation test ported. |
| L6 | D45 drift margin 0.1 D | Exclusion held only for clock rates within ~5 % | R78b: `drift_margin >= 2/3 D` | Same minimum, enforced in the constructor. |
| L7 | D45: one shared sender thread | A black-holed peer stalled every message: 8 commits/s instead of 359 (R39) | One sender per peer, connect/send timeouts | One sender **actor** per peer with its own queue (5.4). |
| L8 | D45: "certain" roots on release-carried propagation | Four schedules made a stale root "certain" (D45 amendment 6) | D46: majority-acknowledged replication is the commit point | No release-carried commit point. Commit = majority of synced acceptances. |
| L9 | Root order `(epoch, term)` | Shown unsafe with a fork (D46) | Order `(label, epoch, segment, offset)`, as Raft `(term, index)` | One `PBRootOrder` function used everywhere; equal `(label, epoch)` with different roots is `PBCorruptionError`. |
| L10 | **D-SAFE-2**: acceptor log synced only in `fsync` mode | A power loss could make a node forget a promise while its rejoined marker survived; one-holder-per-term void (reasoned) | Acceptor log `fsync`-ed in every mode, file, directory and parent directory | protoBaseST has only `fsync` today; the acceptor log syncs unconditionally anyway, and its directory on creation. |
| L11 | **D-AVAIL-1**: a durable root whose records were lost | Majority power loss in `flush`/`none` left the cluster stuck | One self-describing append (kind 5): root and records together | Shared storage (Phase C): records are `fsync`-ed in the shared segment **before** the acceptance is logged (`flush_local` before `replicate`). Phase D: kind 5 from the start. |
| L12 | Owner rule "issue on request" without incarnations | A `done` from a restarted holder's new incarnation retired a permission it never held (8.3f review C1, `0422502`) | `inc` in every request; replies and dones of another incarnation dropped; protocol 9-12 | `inc` from the start; every handler checks it. |
| L13 | **Rejoin by waiting** `restart_grace` | Lost an acknowledged commit with the wiped node's timer 1.3x fast (R78a; design-guide `coordinator.rst` "A mistake"; 1.3x under the margin of the time, about (D + m)/(D - m) = 11/9 with m = D/10; under R78b's margin m >= 2/3 D the boundary is 5x with the holder's clock running, and every rate with the holder's clock stalled, P5) | Rejoin is a **ballot** (`9ef6307`) | Rejoin ballot only. No code path waits for time to make something safe. |
| L14 | Replication under a term the node promised to refuse | A rejoined node could replicate below its rejoin ballot (`af2f837`, `9164a4d`) | Refuse to replicate below `rejoinBallot` | Same guard in the holder's send step. |
| L15 | **Recovery round ended at a majority** (8.3n round 3, `1b3a188`) | Lost an acknowledged root R' with a slow timer and a delayed message (finding C1; coordinator-protocol.rst:725-780) | **Phase-1 floor** (R127, `276a256`): base = max(phase-1 value, recovery result) | Floor from the first version; the C1 schedule is a deterministic simulator test (5.8). |
| L16 | Floor root whose records live only on dead members | Stalled every round of the term (re-review 3, I1) | Abandon the term (R133, `db1a4c8`) | Same, as a retryable conflict plus `unknown` permission. |
| L17 | Startup grace as a safety device | Restarted node could overlap a previous-life grant | Promise persisted; grace kept as efficiency (R82) | Promise restored from the log; grace only for efficiency; `attach` refuses a shorter grace on a non-empty log. |
| L18 | Reads after restart | A node's own committed entry may be lost in power loss (R67) | **Confirmation commit** after every attach | Same, run by the space on the first snapshot after attach. |
| L19 | **D-LIVE-1**: unfair lease turns | With fsync, the releasing process re-won 98.5 % of leases (measured 0.17 ms vs 3.3 ms) | Releases name the member waiting longest (`next`) | Port the hints; fairness tests on the simulator, not on wall-clock runs. |
| L20 | **D-LIVE-2**: hot-key read-modify-write starved whole members | Retry outside the lease waited a full round of turns; snapshot stale again | **Held retries** (`permit_held`, `_PERMIT_RETRIES`, `_RETRY_HOLD`) | Ported in the round runner (5.6). Today's "not ported" entry in `deviations.md` goes away. |
| L21 | Every commit acquired the majority lease (D45/D46) | 12.6 syncs per commit cluster-wide; 61 commits/s at 3 TCP peers vs rqlite 588 (D50 context) | **D50**: owner grants permissions; per-node group commit | Owner and permissions from the start; per-node group commit is the round runner. |
| L22 | Sends that could not finish in the time left | Ended `unknown` and abandoned whole terms | **Send reserve** (R121): refuse to send, truthful conflict | Same rule, same default. |
| L23 | Transport thread decided grants and wrote promises inline | Promise `fsync` blocked every other message (renew p95 7.5 ms); `done` waited behind a replication (R81) | **Message lanes**: memory-only dispatcher never blocks; acceptor lane does the syncs | Natural in protoST: the dispatcher actor never does I/O; the acceptor actor owns the log (5.4). |
| L24 | Two proposers asking for the same term | Ballot collisions (D46 fix round 2) | Proposer-qualified ballots (low 12 bits = rank) | Same formula. |
| L25 | Misconfigured voter sets | A misconfigured member could form a quorum of its own | `vs` fingerprint in requests, renewals, queries, replications | Same fingerprint (CRC-32, as proto_db, since it is free). |
| L26 | Failed tier writes | A failed write could still be acknowledged | R57: tier failed state refuses everything | `PBFileStorage isFailed` exists already; the coordinator observes it and refuses. |
| L27 | Copying a node directory onto another node | The copy promises and accepts on the other node's behalf (D46 fix round 12, item 8) | Documented prohibition | Documented; the acceptor log records the node id and refuses to load under another id (a protoBaseST addition, cheap). |
| L28 | Owner issuing one base twice | S4 then rests on the owner's code (R79) | Accepted boundary; strict expected-failure test | Same boundary, same planted test. |
| L29 | A dying holder vs `done` | Late `done` from a dead permission | O6: deadline `valid + request_timeout`, abandon | Same. |
| L30 | Framed log reader quadratic (protoBaseST's own R14) | Worst case quadratic search | Linear prefix-checksum search | Re-port with the linear search (Phase A task). |
| L31 | Editing protocol code with background mutation tools | A mutation run restored an old `coordinator.py` over new edits (D46 amendment 12) | Process lesson | Mutation tests run on a copy (worktree), never in place. |
| L32 | Claims of fairness without the right workload | "No starvation" did not hold with `fsync` (D45 amendment, Task 9) | Measure with the real durability mode | protoBaseST is `fsync` only: every liveness claim is measured that way. |

Two habits run through all of these and are adopted as rules of this design:

- **Every safety argument is checked against P5** (arbitrary delays, pauses, clock rates). A
  sentence of the form "by the time X happens, Y has ended" is not an argument (L13, L15).
- **Every fix keeps its counterexample as a test**, preferably a *planted defect* that makes the
  test fail (`ProtoBase/tests/support/plant_defects.py`, 30 plants). protoBaseST ports the
  schedules, not only the assertions.

---

## 3. Gap analysis

### 3.1 What protoBaseST already has

| Component | State | Where |
|---|---|---|
| Format 4 codec, records, segments, root records | Complete for every layer it implements | `src/protobase/codec.st`, `framing.st` |
| SpaceRoot cluster fields | **Read** (`clusterTerm`, `clusterEpoch`, `clusterPrevious`); never written | `src/protobase/roots.st:52-60` |
| File storage: own segments (`O_CREAT|O_EXCL`), `fsync`, directory sync, `flock` on `space.lock`, atomic root replace | Complete; `replaceRoot:` checks lock, SpaceRoot and epoch + 1 | `src/protobase/store.st` |
| Refusal of cluster spaces | `PBNotSupportedError` for `cluster/` or a `cluster_term` | `store.st:399-401`, `640-646` |
| Transactions: read sets, merges (D33), rebase, `run:` with retries | Complete, same rules as `proto_db` | `src/protobase/transactions.st` |
| Publisher actor (never waits, R19); unknown-outcome read-back | Group of one | `src/protobase/publisher.st` |
| Errors: `PBConflictError`, `PBOutcomeUnknownError`, `PBTimeoutError`, `PBCorruptionError` | Present | `src/protobase/errors.st` |
| Conformance runner with visible skips | Cluster section skipped | `tests/conformance/cluster.st` |
| Multi-process test patterns (nested runs, Python drivers) | For concurrency and locks | `tests/interop/` |

### 3.2 What protoST and protoIO already provide

| Need | Provided | Notes |
|---|---|---|
| TCP client and server | `Socket connectTo:port:timeout:`, `ServerSocket listenOn:host:`, `accept`, `acceptTimeout:` (LANGUAGE.md §12.11.5); protoIO sets `TCP_NODELAY` (`net.h:28`) | No multiplexing: **one actor per connection** (documented). Blocking I/O in an actor makes the runtime add a worker (up to 256 threads). |
| Read/write timeouts | `IOStream >> timeout: ms` | |
| Exact-length reads | `nextBytes: n` | **To check (week-0)**: whether it can answer fewer than `n` bytes before EOF on a socket; the frame reader must loop if so. |
| Monotonic clock | `Time microsecondClockValue` | Wall clock `Time utcMicroseconds` is not used for leases. |
| Timers | `Future after: ms`, `within:`, one timer thread per runtime | A timer settles on a worker; if every worker is blocked the settle waits (liveness only). |
| Actors, priorities | `asActor`, `asHighPriorityActor` | Control-plane actors on the high band. |
| CAS cell | `Atom value:ifCurrent:`, `swap:` | Publishes the committed root to readers without messages. |
| Durable appends | `BinaryFile append:`, `writeAt:bytes:`, `sync`, `dataSync`, `truncateTo:`, `tryLock`; `FileSystem syncDirectory:`, `replace:with:` | Same `flock` as `proto_db`'s `OwnerLock`. |
| msgpack with ordered maps | `MessagePack encode:`, `decodeOrdered:strictKeys:`, `MessagePackMap` | Byte-identical with msgpack-python. Integers to 2^64 - 1. |
| CRC-32, random bytes | `crc32`, `crc32Continuing:`, `ByteArray randomBytes:` | |
| Processes for tests | `OSProcess spawn:arguments:`, `kill:signal:`, `waitFor:` | For kill -9 tests. |
| Authentication primitives (optional) | `HMAC sha256Key:message:`, `blake2b:key:` | Only if section 8 Q5 asks for frame authentication. |

### 3.3 What is missing

**In protoBaseST (all phases; this is the bulk of the work):**

1. `PBFramedLog`: re-port with `proto_db`'s linear search (R14's condition).
2. `PBAcceptorLog`: entry kinds 1-4 written, 5-6 decoded (vectors), lock file, unconditional sync.
3. Root order, ballots, voter fingerprint, writing SpaceRoot cluster fields.
4. Wire messages: encode, decode and validate all 22 types (all must be *decoded and validated*
   even where unused, since an invalid message drops the connection; the vectors test it).
5. The coordinator: grants, acquiring, ownership, permits (O1-O8), acceptance (V2', ballot rule),
   base choice (floor, recovery, refound, hard guard, re-commit), rejoin ballot, outcomes,
   fencing, tier-failed state, stats.
6. Transport actors (listener, per-peer sender, per-connection reader) and an in-process transport.
7. Cluster tier over the shared `PBFileStorage` (port of `PlainTier`), and lifting the cluster
   refusal *only* when a coordinator is attached.
8. The round runner: per-node group commit under a permission, held retries; snapshots from the
   committed root; confirmation commit; barrier commit helper; `sync:`.
9. The persister actor.
10. The deterministic simulator and fault injector (no equivalent exists in protoBaseST).
11. Phase D only: tiered storage, bounded replication, object-store adapters.

**In protoST (none blocks Phases A-C):**

- Week-0 verification of `nextBytes:` semantics on sockets, of timer settlement under a pool of
  workers blocked in socket reads, and of K23 (the open question whether a caller waiting on a
  `Future` resolved by another actor can be flagged `deadlock:` falsely). K23 matters more here,
  because every commit in cluster mode waits on a `Future` settled by network events.
- Phase D: `HTTPClient` with binary (`ByteArray`) bodies, response headers (ETag), keep-alive (an
  S3 PUT per segment upload without connection reuse costs a TLS handshake each). No evidence was
  found in `lib/http.st` of binary body support; to be confirmed.
- Optional: a TLS **server** (`LANGUAGE.md` §12.11.6: "Not provided: ... a TLS server") if
  section 8 Q5 wants encrypted peer links. `proto_db` has none either.

**In protoIO:**

- Phases A-C: nothing.
- Phase D: RSA-SHA256 signing (GCS service-account JWT); keep-alive or a connection pool in the
  HTTP layer.

**In protoCore:** nothing is needed. No proposal is made. (If a stop-the-world GC pause long enough
to exhaust `send_reserve` shows up in measurements, it costs liveness, never safety; any protoCore
response would be a separate proposal, subject to the maintainer's permission.)

---

## 4. Interoperability: a short note

Per the maintainer's ruling, a protoBaseST node joining a `proto_db` cluster is **not a goal**.
What keeps the door open at low cost:

- **Kept, because it is shared on disk anyway:** the SpaceRoot cluster fields, the framed log
  format (`LOG_FORMAT_VERSION` 2), the acceptor-log entry kinds, the `cluster/<name>.roots` layout
  and naming rule, and the persisted-root rules. These are part of the format specification
  protoBaseST already conforms to, and the vectors test them.
- **Kept because it is free:** the protocol-13 message set, field names, field order (written
  with `MessagePackMap`) and frame layout. The message set is the minimum `proto_db` converged to
  after its fix rounds (each of `inc`, `vs`, `certain`, `committed`, `pred`, `seq`, `after` exists
  because of a defect, section 2), and reusing it gives 23 message vectors as free decoder tests.
  The vectors pin the encoding; protoBaseST does not commit to follow later protocol versions.
- **Not attempted:** behavioural identity with `proto_db`'s timers and liveness details, tiered
  interop, mixed-implementation test suites.

If mixed clusters are ever wanted, the remaining work would be behavioural conformance (every
rule O1-O8, H1-H7, V1, V2', the pipelined gate, the `store`/`warm`/`fetch` paths of tiered tiers)
plus a test harness of real mixed nodes. That is not in this plan.

**A related risk, independent of mixed clusters:** a protoBaseST cluster space can be opened by a
plain `proto_db` process *without* a coordinator. `proto_db`'s `FileStorage` does not refuse a
cluster space (only the "minimal external writer" of the format spec must, step 6). Such a
process could publish a root outside the cluster, which the cluster's persister would later
replace (its label 0 orders below every cluster root), silently losing that write. See section 8
Q7.

---

## 5. Design proposal

### 5.1 Principles applied

1. **Immutable state, one mutable slot per actor.** Every component's state is one immutable
   value (`PBGrantState`, `PBAcceptorState`, `PBOwnership`, `PBPermission`, ...). Transitions are
   pure class-side functions answering a new state and a list of effects. An actor holds its
   current state in one instance variable and replaces it per message: that is protoST's mechanism
   for mutable state over protoCore objects. Knowledge that readers need without messaging (the
   committed root, `stats`) is published through an `Atom`.
2. **Sans-IO core.** No rule touches a socket, a file, a clock or a timer. The core takes `now`
   as an argument and answers effects: `Send(to, message)`, `Append(entry, sync)`,
   `After(ms, event)`, `Resolve(futureId, outcome)`, `Publish(committedRoot)`. The shells perform
   them.
3. **Actors never wait** (ruling R19, protoST K23). A shell sends, appends (blocking file I/O is
   allowed; the runtime adds a worker), schedules timers with `Future after:` and `thenDo:`, and
   returns. Commit callers wait on a `Future` at their own level, never inside a protoBaseST actor.
4. **Safety never depends on timing** (P5). Every timer is listed with the conservative failure
   it can cause (5.8), and the simulator runs every safety test under skewed clocks.
5. **Refuse, never diverge** (protoBaseST's rule). A configuration or state the port cannot handle
   exactly is an explicit error.

### 5.2 Module structure

New files under `src/protobase/cluster/` (one module per `proto_db` concern, so a reader can put
them side by side):

| Module | Contents | proto_db counterpart |
|---|---|---|
| `log.st` | `PBFramedLog` (header, frames, linear torn-tail search, truncate-and-sync on open) | `storage/logfile.py` |
| `rootlog.st` | `PBRootOrder` (`rootKey`, compare), `PBAcceptorLog` (kinds 1-6), `PBLoggedRoots` | `cluster/rootlog.py` |
| `protocol.st` | `PBClusterMessage` encode/decode/validate (22 types), `PBFrameDecoder`, ballots, voter fingerprint, `PBClusterProtocolError` | `cluster/protocol.py` |
| `lease.st` | `PBGrantState` (pure grant rules), `PBAttempt`, `PBLease`, `PBPermission`, `bestRoot` | `cluster/lease.py` |
| `core.st` | `PBCoordinatorCore`: the pure transitions of the coordinator (grants, attempts, ownership and O1-O8, acceptance, recovery, rejoin, outcomes) | `cluster/coordinator.py` (logic only) |
| `coordinator.st` | `PBClusterCoordinator`: the public object and its actors (dispatcher, acceptor, owner timer), configuration, `stats` | `cluster/coordinator.py` (shell) |
| `transport.st` | `PBTcpTransport` (listener, per-peer sender, per-connection reader actors), `PBInProcessTransport` | `cluster/transport.py` |
| `tier.st` | `PBSharedTier` (port of `PlainTier`) | `cluster/persister.py:110-245` |
| `persister.st` | `PBPersister` actor | `cluster/persister.py` |
| `round.st` | `PBRoundRunner`: per-node group commit under a permission, base choice, held retries | `transactions.py` (`_run_round`, `_permit_round`, `_lease_base`, `_phase_1_floor`, `_commit_base`) |

Test support (not in `src/`): `tests/cluster/sim/` with `PBSimNetwork`, `PBSimClock`,
`PBSimDisk`, the scheduler and the invariant checker.

Changes to existing modules: `roots.st` (write cluster fields), `store.st` (a coordinator-owned
handle that may write a cluster space; refusal unchanged otherwise), `space.st` (`storage:
coordinator: lockTimeout:`, snapshots from the committed root, confirmation commit, `sync:`),
`transactions.st` (commit through the round runner when a coordinator is attached, `permitHeld`
on `PBConflictError`).

### 5.3 State values

- `PBGrantState`: `highestSeen`, `highestGranted`, `grantedTop`, `activeGrant` (holder, inc, term,
  expiry), `graceEnd`. Pure rules `decideRequest:now:`, `renew:now:`, `release:`, `restore:`.
- `PBAcceptorState`: accepted `(label, root)`, committed `(label, root)`, highest `seq` per term,
  `suspectTerm`, `rejoined`, `rejoinBallot`, `tierFailed`, `fenced`.
- `PBOwnership`: lease, queue, pipeline (at most `DEPTH + 1` `PBIssued`), base, flags.
- `PBNodeState`: the whole node: the three above, hints, incarnation, request ids, waiters.
  `PBCoordinatorCore handle: event in: aNodeState now: t` answers `{newState. effects}`.

Roots are `PBRootRecord`s plus a label; `PBRootOrder` is the only comparison.

### 5.4 Actors and threads

| Actor | Band | Holds | Does |
|---|---|---|---|
| Dispatcher | high | `PBNodeState` minus the acceptor part | Every memory-only message (permits, grant/reject replies, queries, releases, `want`, timers). Never does I/O (lesson L23). |
| Acceptor | high | `PBAcceptorState`, the `PBAcceptorLog` | Promise, acceptance, rejoined marker: decide, append, `sync`, publish, then hand the reply to the sender actor (atomic acceptor steps). The dispatcher forwards requests, renewals needing state, `replicate`, rejoin ballots. |
| Sender (one per peer) | high | an immutable queue value | Connects on demand with a timeout, writes frames, drops on failure, reconnects with back-off (L7). Control lane only in Phases A-C (`warm` is tiered-only). |
| Listener | high | the `ServerSocket` | Accepts and spawns one reader per connection. |
| Reader (one per inbound connection) | high | the socket | Reads frames (blocking), validates, forwards to the dispatcher; on any invalid frame closes the connection and discards the batch (protocol rule). |
| Round runner | medium | the node's commit queue | Group commit under a permission (5.6). CPU-heavy (the build). |
| Persister | low | persisted root known | Persists the newest committed root by CAS on `space.root`; never on the commit path. |

The split between dispatcher and acceptor needs care: `proto_db`'s "atomic acceptor steps"
(R55, R81, R81b) require that the decision, the log write and the in-memory publication form one
step. In this design the acceptor actor owns all three and the dispatcher only reads the
acceptor's published state through an `Atom` (never decides an acceptance from it). That mapping
is a review point of Phase B.

Thread count per node: 3-5 members give about 4 + 2(N - 1) actors; blocked readers consume
workers (the runtime adds them). Acceptable for the recommended sizes; documented as a limit
beyond about 16 members.

### 5.5 Fit with the existing commit and publisher path

- **Without a coordinator nothing changes**: `PBPublisher` keeps the standalone path, the
  `flock`, and the refusal of cluster spaces.
- **With a coordinator** (`PBObjectSpace storage: s coordinator: c`), `PBTransaction >> commit`
  enqueues on the round runner and answers when the commit's `Future` settles. The publisher is
  not used for commits; `space.root` is written only by the persister.
- Atoms a transaction wrote are saved **before** the permission (root-independent work, D44
  amendment), as the publisher already does ("step 0").
- `newDatabase:` is a commit like any other in cluster mode.
- Snapshots read the committed root from the coordinator's `Atom` (the storage root only when
  nothing is known yet), as `proto_db` does.

### 5.6 The commit round

The round runner, per node, one round at a time:

1. Take everything queued (group commit). Ask the coordinator for a permission (`Future`).
2. On the permit: choose the base (the rules of section 1.6, including a recovery round as a
   `Future` when uncertain). Stale base: requeue, permission ends `unknown`.
3. Build each transaction in turn on the root the previous produced (existing `_buildOn:`);
   a conflicting one fails alone.
4. Save new atoms, `flushSegment` (records `fsync`-ed in the shared storage before anything
   acceptable leaves, lesson L11).
5. Reserve check (R121); refuse to send below `rejoinBallot` (L14).
6. Hand the root to the coordinator: own acceptance (acceptor actor) plus `replicate` to the
   voters; the coordinator settles the round's `Future` with `committed`, `none` or `unknown`.
7. Settle each transaction: committed; `PBConflictError` (retryable, `permitHeld` when the round
   keeps the permission for a held retry, D-LIVE-2); `PBOutcomeUnknownError`.
8. Send `done`.

A **group-size bound** is proposed as a protoBaseST liveness addition: the runner stops adding
transactions to a round when the permission's time left falls below the reserve plus the measured
build time of one transaction, and leaves the rest queued. It never decides safety. It is a
departure from `proto_db` (which takes everything queued) motivated by protoBaseST's build cost
(section 7), and is listed as open question Q4.

### 5.7 Error model

| Situation | Error | Retried by `run:` |
|---|---|---|
| Conflict, reserve refusal, permission ended before sending, unreachable base | `PBConflictError` (`permitHeld` true when held) | yes |
| Something acceptable left and the majority was not observed in time, or a failure after the send | `PBOutcomeUnknownError` | no |
| No permission within `acquireTimeout` (minority side, no quorum) | `PBTimeoutError` | no |
| Invalid frame or message | `PBClusterProtocolError` (a `PBCorruptionError`), logged; the connection is dropped | n/a |
| Base below the known committed root, acceptor logs lost beyond the model | `PBCorruptionError` naming `forceRejoin` | no |
| Tier failed (a failed log or segment write) | node refuses; commits get `PBUnexpectedError` | no |
| Unexpected error in an actor | node fenced for the life of the process; commits get `PBUnexpectedError` | no |
| Two roots with equal `(label, epoch)` | `PBCorruptionError` | no |

### 5.8 Timers

The `proto_db` list (coordinator-protocol.rst:880-951) is ported one for one, with the same
defaults expressed in milliseconds (protoST convention, deviations.md "Timeouts"). Each is a
`Future after:` whose firing becomes an event in the core; each has a line in the test that
mutates its value (shorter, longer, skewed per node) under the simulator and checks the safety
invariants still hold.

### 5.9 Configuration API

Mirrors `proto_db`'s names in camelCase, milliseconds for durations:

```smalltalk
peers := { PBPeer nodeId: 'n0' host: '10.0.0.1' port: 7400.
           PBPeer nodeId: 'n1' host: '10.0.0.2' port: 7400.
           PBPeer nodeId: 'n2' host: '10.0.0.3' port: 7400 }.
coordinator := PBClusterCoordinator nodeId: 'n0' peers: peers options: (Dictionary new
    at: #leaseDuration put: 2000;      "driftMargin, requestTimeout, sendReserve, acquireTimeout,"
    at: #requestTimeout put: 250;      "backoff, startupGrace, persistInterval, persistLag,"
    yourself).                         "ownerIdleRelease, voters, clock, seed"
coordinator start.
space := PBObjectSpace storage: (PBFileStorage path: '/shared/space') coordinator: coordinator.
```

`coordinator stats`, `coordinator forceRejoin`, `space sync: ms`, `space committedEpoch`,
`space persistedEpoch`, `coordinator stop`. `transport:` and `clock:` are test seams, as in
`proto_db`. Notify (not in `proto_db` yet): when it lands upstream, topics would ride on `done`
after the commit point; nothing in this design blocks it.

---

## 6. Test strategy

### 6.1 Conformance vectors to un-skip

| Item | Phase | Test |
|---|---|---|
| `invalid` entries of layer `log`; `segments.log`, `ranges.log`, `roots-torn.log` | A | `tests/conformance/framing_logs.st` |
| `roots.log` (kinds 1-6, field by field), `invalid` layer `roots_log` | A | `tests/conformance/rootlog.st` |
| `messages/*.frame` (23 files), `invalid` layer `message` | A | `tests/conformance/messages.st` (decode, validate, re-encode byte for byte) |
| `segment` (SpaceRoot with cluster fields) | A | write the same SpaceRoot, compare bytes |

`tests/conformance/cluster.st` then prints no skip. `proto_db`'s verifier also checks a space a
protoBaseST cluster wrote (the shared on-disk format).

### 6.2 Deterministic simulation (the core of the safety tests)

`PBSimNetwork` runs N `PBCoordinatorCore`s in one protoST thread, with a virtual clock and a
seeded scheduler: message drop, duplication, delay, reordering, partitions, crashes with the disk
kept, crashes with the disk lost, torn log tails, per-node clock rates. An invariant checker runs
after every step: at most one owner per term (S1); no two different roots with equal
`(label, epoch)`; every acknowledged commit present in the final committed chain of every node
(S4); unknown outcomes present everywhere or absent everywhere after convergence; no reply sent
before its log entry is synced. Every test is a seed; a failure prints the seed and the schedule.
No test reads a wall clock or sleeps.

**Checklist from proto_db's tests.** `ProtoBase/tests/unit/` holds 27 `test_cluster_*.py` files
with 261 test functions, plus 6 tier files (Phase D). Each is ported as a scenario family:

| proto_db test file | protoBaseST scenario family | Phase |
|---|---|---|
| `test_cluster_lease`, `test_cluster_terms`, `test_cluster_renewal` | grant rules, ballots, renewal, startup grace | B |
| `test_cluster_coordinator`, `test_cluster_dispatcher` | event handling, lanes | B |
| `test_cluster_acceptor_writes`, `test_cluster_acceptor_durability`, `test_cluster_durability` | atomic acceptor steps, sync-before-reply, power loss | B |
| `test_cluster_chain_rule`, `test_cluster_voters` | V2', S3, `vs`, learners | B |
| `test_cluster_permit_*` (backoff, deferral, incarnations), `test_cluster_send_reserve` | O1-O8, incarnations, reserve | B |
| `test_cluster_pipeline_holder`, `test_cluster_pipeline_owner` | H1-H7, gate (only if Q3 says DEPTH 1) | B |
| `test_cluster_recovery_base`, `test_cluster_root_certainty` | phase-1 floor, C1 schedule, I1, the four certainty schedules | B |
| `test_cluster_rejoin`, `_rejoin_fresh`, `_rejoin_records` | rejoin ballot, `new`/`rootless`/`witnesses`, R51 late first start | B |
| `test_cluster_tier_failures` | tier failed, fenced | C |
| `test_cluster_transactions`, `test_cluster_fairness` | commit path, held retries, D-LIVE-1/2 workloads | C |
| `test_cluster_persistence` | persister CAS, never backwards, `persistLag` | C |
| `test_cluster_protocol`, `test_cluster_transport` | framing, connection dropping, one-way links | A, C |
| `test_tier_*`, `test_tiered_storage` | tiered storage | D |

**Planted defects.** The relevant plants of `ProtoBase/tests/support/plant_defects.py` (for example
`c1_no_floor`, `unreachable_base_none`) are reproduced as test-only subclasses that override one
rule; each must make its scenario fail. This proves the tests can see the defect they guard
against (the protoBaseST precedent is plan call C17: test-only subclasses, no product flags).

### 6.3 Real processes

Three protoST processes on loopback with real TCP and a shared directory: commits from every
node, `kill -9` of the owner, of a holder mid-round and of a voter; restart with the disk kept;
restart with the acceptor log deleted (rejoin). These tests assert **outcomes** (every
acknowledged commit present, counts verified after reopening), never durations. Deadlines exist
only as generous test timeouts that turn a hang into a failure.

### 6.4 Interop that remains

Only the on-disk format: `proto_db`'s verifier and dump on a space written by a protoBaseST
cluster, and `proto_db` reading it (read only). No mixed-cluster tests (section 4).

---

## 7. Interaction with the commit-performance work

The profiling under way reports a single publisher actor, CPU-bound, at about 50-70 ms per commit
(figure from the brief; not measured for this document).

1. **In cluster mode the build is a cluster-wide critical section.** Validation, merge, path copy
   and the new root run under a permission, and permissions are issued one at a time (pipelining
   overlaps one build with the previous round's replication, not two builds). The cluster's
   ceiling is about `1 / (build + RTT + acceptor fsync)` rounds per second **for all members
   together**: with 50-70 ms of build, about 12-15 rounds per second, against about 200 commits per
   second measured by `proto_db` at 3 peers (`design-guide/pipelined-permits.rst:26`). Adding nodes
   does not raise it (D44 "scaling limit").
2. **The profiling should split the commit cost into two buckets**: root-independent work
   (encoding and saving the transaction's own atoms, segment `fsync`), which cluster mode moves
   *before* the permission, and root-dependent work (`_buildOn:`: validation, rebase, path copy,
   SpaceRoot), which stays inside. Only the second bounds cluster throughput. A request to the
   profiling work: report that split.
3. **Group commit** amortizes the permission round trip across the transactions of a node, but
   the builds inside a round are still serial. Group commit in standalone mode (D52, not
   implemented in protoBaseST) would share the round runner; it is worth doing once, for both
   modes.
4. **Timers versus build time.** With `lease_duration` 2 s the holder's belief is about 667 ms and
   `send_reserve` about 167 ms. A round of one transaction fits comfortably; a round of ten at
   60 ms does not, and would end in reserve refusals (retryable, wasted). Hence the group-size bound
   (5.6, Q4) and, if needed, a longer `leaseDuration` for protoBaseST clusters (liveness only).
5. **GC pauses** of protoST delay replies and builds. Under P5 they cost liveness (unknown
   outcomes, abandoned terms), never safety. The simulator covers pauses; the real-process tests
   will show whether they matter in practice.
6. **The single publisher actor stays** for standalone mode; in cluster mode the round runner
   replaces it for commits. If the profiling work changes the publisher's structure (for example,
   moving encoding out of the actor), the same change applies to the round runner's step 4.

---

## 8. Phased plan, risks and open questions

### 8.1 Plan

Task sizes follow `docs/superpowers/plans/2026-11-10-protobasest-prototype.md`. Estimates are
engineering days for one implementer, including tests and one review fix round each.

**Phase 0: rulings and week-0 checks (1 day)**

- T0. Maintainer answers to section 8.3; protoST checks: `nextBytes:` on sockets, timers settling
  with workers blocked in reads, K23 with a waiting caller, 62-bit integers through
  `MessagePack`. (1 d)

**Phase A: format and wire layers, no network (8.5 days)**

- T1. `PBFramedLog` with the linear torn-tail search; log-layer vectors. (1.5 d)
- T2. `PBAcceptorLog`, kinds 1-6, lock file, unconditional sync and directory sync; roots-log
  vectors. (2 d)
- T3. Root order, ballots, voter fingerprint; writing SpaceRoot cluster fields; segment vector.
  (1 d)
- T4. The 22 messages, frame decoder, validation; message vectors. (2 d)
- T5. Pure grant rules, attempts, `PBLease`, `PBPermission` as immutable values. (2 d)

**Phase B: the coordinator core and the simulator (20 days)**

- T6. Simulator: virtual clock, seeded network faults, crashes, disks, invariant checker. (3 d)
- T7. Phase 1: request, grant, reject, release, renew, grace, suspicion, incarnations, fairness
  hints. (3 d)
- T8. Ownership and permissions, O1-O8, `DEPTH = 0`. (3 d)
- T9. Acceptance: ballot rule, V2', `seq`, siblings, atomic acceptor steps, `ack`, `done`,
  committed knowledge. (2 d)
- T10. Base choice: certain and uncertain leases, recovery, phase-1 floor, refound, hard guard,
  re-commit, stale base, unreachable base. (3 d)
- T11. Rejoin ballot (`new`, `rootless`, `witnesses`), `forceRejoin`, confirmation commit. (3 d)
- T12. Pipelined permits (`DEPTH = 1`): propose, gate H5, H1-H7. Only if Q3 says so. (3 d)

**Phase C: integration over a shared `PBFileStorage` (18 days)**

- T13. Transport actors and the in-process transport. (2.5 d)
- T14. `PBSharedTier`; cluster acceptor logs in `cluster/<name>.roots`; the cluster refusal lifted
  only with a coordinator. (1.5 d)
- T15. Round runner: group commit, base, build, reserve, replicate, outcomes, held retries;
  snapshots from the committed root; `run:` integration; barrier commit. (4 d)
- T16. Persister actor, `sync:`, `persistedEpoch`. (1.5 d)
- T17. Port the scenario checklist (6.2) and the planted defects. (5 d)
- T18. Real-process tests (6.3). (2 d)
- T19. Documentation: deviations, decisions, not-done, a tutorial chapter, dated measurements.
  (1.5 d)

**Total Phases 0-C: about 47.5 days** (about 44.5 without T12).

**Phase D (separately approved): tiered storage and an object store (about 21 days plus
protoST/protoIO work)**

- T20. Tiered storage: local WAL, kind-5/6 entries, redo, checkpoints, own-segment repair. (5 d)
- T21. Bounded replication: data replicas, `records`, `store`, `warm`, `fetch`, `commit_query`,
  copies rule, locator. (4 d)
- T22. Object-store protocol and an S3 adapter (SigV4 with `HMAC`, conditional writes, the
  unknown-outcome read-back). Needs protoST HTTP binary bodies and keep-alive. (4 d + protoST
  work)
- T23. Persister upload path: sealed markers, parts, ranges, backlog limits. (3 d)
- T24. Tier scenario families and real-process tests with a local S3-compatible server. (5 d)

### 8.2 Risks

| Risk | Effect | Mitigation |
|---|---|---|
| The sans-IO rewrite departs from `proto_db`'s code structure | A rule is ported with a subtle difference the vectors cannot see | Scenario checklist from all 261 tests; planted defects; each rule cites its D/R source; independent review per phase |
| Safety bugs the simulator does not reach | A lost acknowledged commit in production | P5 audit of every timer; seeded runs at volume in CI; the C1 and R78a schedules as fixed tests |
| protoST K23 (false `deadlock:`) | Commits rejected spuriously under load | Week-0 check; callers wait at top level of their method; report to protoST if reproduced |
| One actor per connection, blocking reads | Worker growth with cluster size | Documented limit (about 16 members); multiplexing is a protoST/protoIO proposal only if needed |
| Build cost (section 7) | Low cluster throughput, reserve refusals | Profiling split, group-size bound, longer lease if needed |
| `flock` on network file systems | The shared-storage cluster's persister CAS relies on `flock`; NFS semantics vary | Document: shared storage on a local file system or one with reliable `flock`; Phase D for multi-host deployments |
| A plain `proto_db` writer on a cluster space | Silent loss of that write (section 4) | Q7; protoBaseST itself keeps refusing without a coordinator |
| Estimate | `proto_db` needed 8.3c-8.3n and many fix rounds | Phase gates with review; Phase D only after C is measured |

### 8.3 Open questions for the maintainer

- **Q1. Scope.** Approve Phases A-C (shared `PBFileStorage`) as the first target, with Phase D
  decided after C is measured? Multi-host deployments would wait for Phase D, or run on a shared
  file system with reliable `flock`.
- **Q2. Wire protocol.** Keep protocol-13 bytes (free, vectors as tests, section 4), with the
  explicit statement that protoBaseST does not track later `proto_db` protocol versions? Or define
  a protoBaseST protocol from the start?
- **Q3. Pipelined permits.** `proto_db` measured a gain with `DEPTH = 1` (D55, pipelined-permits
  guide), but it adds the gate and rules H1-H7. Ship `DEPTH = 0` first and add T12 after
  measurement?
- **Q4. Group-size bound** (5.6): accept this liveness-only departure from `proto_db`?
- **Q5. Security.** `proto_db`'s cluster is plaintext and unauthenticated (1.11). Follow it and
  document "trusted network only", or add frame authentication (HMAC with a shared key; protoST
  has the primitive) at the cost of diverging from protocol-13 bytes? Encrypted links would need a
  TLS server in protoST.
- **Q6. Timer defaults** for protoBaseST: `proto_db`'s (2 s lease) or longer, given protoST's
  build cost and GC pauses? Liveness only.
- **Q7. Upstream proposals for `proto_db`** (proposals, not changes): (a) `FileStorage` should
  refuse to write a cluster space without a coordinator, as the external-writer rule does; (b) the
  docs should state that the cluster transport assumes a trusted network.
- **Q8. Group commit in standalone mode** (D52): do it together with the round runner, since
  they share the mechanism?

### 8.4 Maintainer's answers (2026-11-13)

The maintainer accepted the recommendation on every question:

- **Q1:** yes. Phases A-C over a shared `PBFileStorage` first; Phase D (tiered storage) is decided
  after C is measured.
- **Q2:** yes. Keep protocol-13 bytes, so `proto_db`'s message vectors serve as tests, with the
  explicit statement that protoBaseST does not track later `proto_db` protocol versions.
- **Q3:** yes. Ship `DEPTH = 0`; add pipelined permits only after measurement.
- **Q4:** yes. Accept the group-size bound per round (a liveness-only departure).
- **Q5:** optional HMAC frame authentication with a shared key from the start. With it disabled the
  bytes are protocol 13; with it enabled the frames diverge, as documented. The trusted-network
  assumption is stated in either case.
- **Q6:** `proto_db`'s defaults (2 s lease), all configurable.
- **Q7:** yes, both proposals go to `proto_db` (the maintainer owns that repository).
- **Q8:** yes. Standalone group commit (D52) is built together with the round runner.
