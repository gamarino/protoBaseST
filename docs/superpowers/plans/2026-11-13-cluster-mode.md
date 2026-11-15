# protoBaseST Cluster Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a protoBaseST-only cluster over one shared `PBFileStorage` directory (Phases 0, A, B and C
of the spec), following `proto_db`'s coordination protocol, its fixes and its tests, with the
on-disk format shared byte for byte with `proto_db`, plus standalone group commit (D52) built on
the same round runner.

**Architecture:** a *sans-IO* core. Every protocol rule is a method of one stateless rules object,
`PBCoordinatorCore`, answering a new immutable state value and a list of effect values for an
event and a time `now`. Thin actor shells (dispatcher, acceptor, senders, readers, round runner,
persister) hold one state value each in an `Atom`, perform the effects and never wait. The same
core runs in a seeded, single-threaded, virtual-time simulator that carries every safety test.

**Tech Stack:**
- protoST 0.10.0 (`net`, actors with three bands, `Future after:`/`within:`, `Atom`, `BinaryFile`,
  `MessagePack`/`MessagePackMap`, `crc32`, `HMAC sha256Key:message:`, `ByteArray randomBytes:`,
  `Random seed:`, `Time microsecondClockValue`, `OSProcess spawn:arguments:`/`kill:signal:`);
- protoBaseST at `c0915cf` (branch `feat/cluster`, off `feat/prototype`);
- CPython ≥ 3.11 with `proto_db` from the existing interop venv, for Task 26 only.

**Spec:** `docs/superpowers/specs/2026-11-13-cluster-design.md` (read all of it, including §8.4,
the maintainer's answers Q1–Q8). The normative protocol and format are `proto_db` at `v2.0.0rc4`
(`8e6127f`, since Task 22a; before it `v2.0.0rc3`, `7786974`). What changed from rc3 is listed, item by
item, in `docs/superpowers/specs/2026-11-15-rc4-delta.md`; protoBaseST follows rc4 at format 4
(protocol 14, format 5 refused):
- `docs/source/coordinator-protocol.rst` ("CP" below; written for an implementer of protoBaseST);
- `docs/source/format-spec.rst` lines 1434-1662 ("FS-log", "FS-wire");
- `docs/decisions.md` D44-D55 and the rulings they cite;
- `proto_db/cluster/*.py`, `proto_db/storage/logfile.py`, `proto_db/transactions.py`
  (`_run_round`, `_permit_round`, `_lease_base`, `_phase_1_floor`, `_commit_base`,
  `Database.run`);
- `tests/unit/test_cluster_*.py` (29 files, 298 functions at rc4; 27 and 261 at rc3),
  `tests/support/plant_defects.py`.

Read every `proto_db` file with `git -C "$PROTOBASE_REPO" show v2.0.0rc4:<path>` (rc3 for the tasks done
before Task 22a); never modify
that repository. **When a rule is unclear, `proto_db`'s code at the tag is the reference**; read it
before guessing. Every rule in the core carries a comment citing its source (D/R number, CP
section, or `proto_db` function), as the spec's first risk asks.

## Global Constraints

Carried verbatim from the maintainer's brief:

- Tests never depend on timing (seeded virtual-time simulator for protocol logic; real-socket
  tests only for wiring, with no timing assertions).
- Safety never depends on timing (leases need fencing exactly as `proto_db` D44; storage CAS only
  as fencing).
- Everything immutable, mutable state only via protoCore's mechanism as protoST exposes it
  (`Atom swap:`).
- No locks held across allocation.
- On-disk format shared with `proto_db` (same bytes).
- Correctness over speed.
- No technical debt (no uncalled code, cheap reviewer items get fixed).
- Docs in professional English.
- TDD with fail-first evidence.
- Commits end `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Suite `PROTOST=<protost> tests/run_tests.sh` stays green after every task.
- protoCore must never be changed (protoCore ideas are proposals only).
- protoST/protoIO changes, if any are needed, are separate tasks flagged for the maintainer.

Project rules that apply to every task:

- **Environment.** `export PROTOST=<absolute path of protoST 0.10.0 build_release/protost>` and
  `export PROTOBASE_REPO=<absolute path of the ProtoBase checkout>`. In this worktree the
  runner's default `../ProtoBase` does not resolve, so both are always set explicitly.
- **Branch.** All work is on `feat/cluster`. Do not push, merge, tag or publish. ProtoBase is
  read only.
- **Fail-first evidence.** Every "run, expect FAIL" step records the failing line of the runner
  output in the task's commit message body (`fail-first: <line>`).
- **Commit trailer.** Every commit step means
  `git commit -m "<subject>" -m "<body>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.
- **State.** No method assigns an instance variable after construction (decision 3,
  `tests/unit/values_immutable.st`). An actor shell keeps its state value in one `Atom` created
  by its initialiser and replaces it with `value:ifCurrent:` (or `swap:`) per message; nothing is
  added to `_ivar_allowlist.txt` except one-shot initialisers.
- **No mutexes.** Synchronisation is actors, `Future` and `Atom` only. The two `flock`s
  (`space.lock`, `cluster/<name>.roots.lock`) are the format's inter-process protocol.
- **Actors never wait** (ruling R19, K23). A shell schedules with `Future after:` and
  `thenDo:`/`catch:`, never `wait` inside an actor method.
- **Time.** The core reads no clock: `now` is an argument, an Integer of microseconds of the
  monotonic clock (`Time microsecondClockValue` in the shells, `PBSimClock` in the simulator).
  Options are SmallInteger **milliseconds** (protoST convention); the configuration converts
  them once. No cluster code reads `Time utcMicroseconds` or `DateTime nowUTC` except
  `PBDatabaseRoot committedAfter:` (an existing, monotonic-per-database rule).
- **Refuse, never diverge.** A configuration, message or state the port cannot handle exactly is
  an explicit error naming it.
- **Visible skips only.** A test that cannot run prints `SKIP: <reason>` as its last line (exit
  77 for `.sh`). The final gate (Task 30) accepts no skip in `tests/conformance/cluster.st`.
- **Planted defects** are test-only subclasses of `PBCoordinatorCore` (or of a shell) overriding
  one rule method, defined in test files; no product flag or hook (plan call C17 precedent).
  Each must make its target scenario fail; a plant that does not fail proves nothing.
- **Documentation in the same task.** A task that adds public API updates `docs/reference.md`
  and `CHANGELOG.md` (`## 0.2.0 (unreleased)`) in that task.
- **protoST defects** found while working go to protoST `KNOWN_ISSUES.md` and become a flagged
  task (pattern of Task 1b); they are never worked around here.

## Calls made by the planner (review at Task 30)

Rulings on points the spec leaves open. Entries marked **(maintainer)** change something the
spec states or need an owner's answer; Task 29 copies the whole table into `docs/decisions.md`.

| # | Call | Why |
|---|---|---|
| CC1 | The node's own vote and own acceptance are local events to its own acceptor (`PBToAcceptor`), decided by the same rule methods as a peer's request, never through the transport | One decision path; spec 5.4 leaves the dispatcher/acceptor mapping as a Phase B review point |
| CC2 | `PBGrantState` lives inside `PBAcceptorState`: promises are durable acceptor state. The dispatcher reads the acceptor's published snapshot (an `Atom`) for hints only and never decides a grant or an acceptance from it | Atomic acceptor steps (R55, R81, R81b) |
| CC3 | The core counts integer microseconds; options are milliseconds. Defaults: `driftMargin` = ⌈2D/3⌉, belief = D − margin, `sendReserve` = min(`requestTimeout`, belief // 4), `startupGrace` = D + margin, idle end D // 4 | No rounding of `proto_db`'s float seconds can make the margin fall below 2/3 D (R78b) |
| CC4 | **(maintainer)** HMAC frame authentication layout: the frame body is the msgpack map followed by a 32-byte tag, HMAC-SHA-256(key, UTF-8(receiver id) ‖ 0x00 ‖ msgpack bytes); the 4-byte length covers both; `MAX_FRAME_BYTES` unchanged; a key is a `ByteArray` of at least 32 bytes; a missing or wrong tag drops the connection like an invalid message; the tag is compared over all 32 bytes without an early exit. Replay needs no counter: duplication and reordering are inside the failure model (P5), and the receiver id in the tag stops delivery to another member. Disabled, the bytes are protocol 13 | Q5 asks for optional HMAC "from the start" but fixes no layout |
| CC5 | The reader delivers each valid frame as it is read. `proto_db`'s "messages decoded from the same 64 KiB read as a bad frame are lost with it" is a property of its reads, not reproduced | Delivery and loss are both inside the failure model; the connection is still dropped at the first invalid frame |
| CC6 | **(maintainer)** The node-id binding of the acceptor log proposed in lesson L27 is **not** added in Phases A-C: it needs a new entry kind, which would change the shared format. In shared storage the file name `cluster/<name>.roots` binds the id. Kept as a proposal to `proto_db` for Phase D | "Same bytes" outranks a cheap addition |
| CC7 | Message types never sent at `DEPTH = 0` over shared storage (`records warm store propose fetch fetched commit_query commit_info`) are decoded and validated (an invalid one drops the connection), then ignored and counted in `stats` (`ignored_messages`) | All 22 types must be validated (spec 3.3 item 4); answering them would be code for Phase D |
| CC8 | `#fetchTimeout` and every tier option are refused (`PBNotSupportedError` naming Phase D), not accepted silently | No uncalled code; refuse, never diverge |
| CC9 | The barrier commit is a documented pattern (a `run:` that writes a root), not an API, as in `proto_db` (CP 1.12; the read-only barrier is not implemented there either) | No invented API |
| CC10 | **(maintainer)** Standalone group commit (D52, Q8): the round runner retries a busy root lock with `Future after:` timers and never waits; each queued commit keeps its own `lockTimeout` deadline from the moment it was queued; the caller waits only on its commit's Future. This supersedes the "caller owns the backoff" half of R19 (the "never waits" half stays) and removes the deviation "the lock backoff blocks the caller's worker" | The runner owns the queue, so it owns the retry; one place instead of every caller |
| CC11 | Group-size bound (Q4): the first queued commit of a round is always built; before building commit k+1, the runner continues only if the permission's time left is at least `sendReserve` + the longest build measured in this round. The rest go back to the head of the queue, not counted as attempts | Spec 5.6 states the bound, not the formula |
| CC12 | Test layout: cluster unit and simulator tests live flat in `tests/unit/` (`cluster_*.st`, `sim_*.st`, helpers `_sim.st`, `_plants.st`), because the runner sets the working directory to the test's directory and `_check.st` lives there; real-process tests live in `tests/cluster/` | Spec 5.2 named `tests/cluster/sim/`; the runner's import rule decides |
| CC13 | The simulator takes the rules object as a parameter (`rules:`); plants override one method of `PBCoordinatorCore` | C17 precedent: no product flags |
| CC14 | Each scenario family runs a fixed list of seeds in the default suite (sized to fit `RUN_TIMEOUT`); `PBST_SIM_SEEDS=n` raises it for the soak run of Task 30. A failure prints the seed and the event trace | "Seeded runs at volume" without a slow default suite |
| CC15 | Acceptor-log kinds 5 and 6 are decoded on load (the format says a reader takes them) and never written; `PBSharedTier` refuses a log holding one (`PBNotSupportedError`: a tiered node's log) | A shared-storage node never writes them |
| CC16 | `ranges.log` and `segments.log` are verified at the framed-log layer (header, frame count, payload bytes); their entry decoders are Phase D | No uncalled decoders |
| CC17 | Wire roots: `[0, nil, nil, label]` is the known empty space; the 3-item form is decoded with label 0 and never written | FS-wire field types |
| CC18 | A reserve refusal is `PBConflictError` whose text names the longest build of the round, the time the permission had left, `sendReserve` and `leaseDuration` | Review Focus 2 |
| CC19 | The persister writes `space.root` with `tryLockRoot`, `readRoot`, root-order check, then `replaceRoot:` (epoch + 1 is the CAS); a busy lock reschedules it after `persistInterval` | Port of `PlainTier.persist`; the persister never waits |
| CC20 | `PBFileStorage class >> clusterPath:` opens a storage that may write a cluster space; `PBObjectSpace storage:coordinator:` requires one, `PBObjectSpace storage:` refuses one. `PBFileStorage path:` keeps refusing cluster spaces | Spec 5.2 "a coordinator-owned handle"; no mode flag on an open storage |
| CC21 | A node id that is not `[A-Za-z0-9._-]{1,64}` is not refused: its log is `cluster/<hex of the UTF-8 bytes>.roots`, `proto_db`'s `_node_log` rule | Same file name as `proto_db` would pick |
| CC22 | `PBRoundRunner` is shared by both modes and lives in `src/protobase/round.st`; the cluster round's shell is `PBClusterRound` in `src/protobase/cluster/round.st`. `PBPublisher` stays as the standalone strategy (one group per call) | Q8: one mechanism for both modes |
| CC23 | Membership values (`PBPeer`, `PBMembership`: ranks, ballots, voters, fingerprint) get their own module `cluster/members.st` | One responsibility per file; spec 5.2 spread them over `protocol.st` and `lease.st` |
| CC24 | `coordinator stats` answers a `Dictionary` keyed by `proto_db`'s stat names (snake_case Strings) for the counters protoBaseST has | One vocabulary in both projects' docs |
| CC25 | Release number: 0.2.0, `## 0.2.0 (unreleased)` in the CHANGELOG | Spec header: "the release after the first public protoBaseST (0.1.0)" |

## Review Focus

1. **Closing the space or stopping the coordinator with commits queued, building, or sent.** A
   commit nothing of which left the node ends `PBClosedError`; one whose root was sent ends
   `PBOutcomeUnknownError`; nothing hangs, and a restarted node's committed chain decides the
   unknown ones. Test: Task 23, `tests/unit/cluster_close_inflight.st`.
2. **A transaction whose build alone exceeds the permission window.** Every round ends in a
   reserve refusal; the `PBConflictError` names the build time, the time left and
   `leaseDuration` (CC18), and `run:` ends with that text after its retries instead of looping
   silently. Test: Task 15 (`sim_round_rules.st`, case `build longer than the belief`) and
   Task 23 (`cluster_commit_path.st`, the message).
3. **A second process started with the node id of a live one** (double start, copied unit
   file). The second attach is refused at start with `PBUserError` naming
   `cluster/<name>.roots.lock`; the first node is unaffected. Test: Task 21,
   `tests/unit/cluster_tier.st`.
4. **Misconfigured members.** Self id missing from the peers, duplicate ids, more than 4096
   members, an even explicit voter set, a key shorter than 32 bytes: refused at construction.
   Remote mismatches (another voter set, a key on one node only, two different keys): messages
   dropped and counted (`config_mismatches`, `frames_rejected`), never a quorum, never a split.
   Tests: Task 7 (`cluster_config.st`), Task 13 (`sim_acceptance.st`, case `vs mismatch`),
   Task 19 (`cluster_transport_tcp.st`, key cases).
5. **Node ids that are not file-name safe** (`'nœud'`, `'a/b'`, `'..'`, 65 characters). The log
   file is the one `proto_db`'s `_node_log` names, always inside `cluster/`. Test: Task 21,
   `tests/unit/cluster_tier.st`, with the expected names computed by `proto_db` in Task 26.

---

## Phase 0: week-0 checks (spec 8.1 T0)

The maintainer's answers (§8.4) are in. What remains is to verify protoST's behaviour that later
tasks build on. **If a check fails, stop**: record the defect in protoST `KNOWN_ISSUES.md` and do
Task 1b before Task 2.

### Task 1: Week-0 checks of protoST for cluster mode

**Files:**
- Create: `tests/week0/socket_short_reads.st`, `tests/week0/timers_with_blocked_readers.st`,
  `tests/week0/k23_network_settled_futures.st`, `tests/week0/cluster_values.st`.
- Modify: `docs/deviations.md` ("Known protoST limits", the K23 entry), `docs/decisions.md`
  (a dated note under "What is still open").

**Interfaces:**
- Consumes: protoST 0.10.0 only (no protoBaseST code).
- Produces: the recorded semantics of `nextBytes:` on a socket (short read mid-stream: yes or no;
  at end of stream: what it answers), which Task 19's `_readExactly:from:` documents. Task 19
  loops until `n` bytes whatever the answer, so neither outcome blocks the plan.

- [ ] **Step 1: write the checks.**
  - `socket_short_reads.st` (`"EXPECT: ok"`): listener on `127.0.0.1` port 0; a reader actor
    resolves a `started` Future, then calls `nextBytes: 10`; the main thread waits for
    `started`, writes 4 bytes, `(Future after: 200) wait`, writes 6 bytes. It prints
    `NOTE: nextBytes: answered N bytes mid-stream` with N = 4 or 10 (both pass: the outcome is
    recorded, not asserted). Second case: write 4 bytes then close; print what `nextBytes: 10`
    answers at end of stream (`4 bytes`, `nil`, or the error class). Last line `ok`.
  - `timers_with_blocked_readers.st` (`"EXPECT: ok 3"`): 64 reader actors, each blocked in
    `nextBytes: 1` on a connected socket whose writer never writes (more than any initial
    worker pool). Then, from the main thread: `(Future after: 1) wait` answers nil; a
    `thenDo:` chain on `Future after: 1` resolves a second Future that the main thread waits
    for; closing the 64 writers settles all 64 reader Futures (count them through an `Atom`).
  - `k23_network_settled_futures.st` (`"EXPECT: ok 128 0"`): a hub actor answers, for request
    `i`, a pending Future it keeps in a `Dictionary` (its own state, in an `Atom`); a reader
    actor blocked on a socket resolves Future `i` when it reads the 4-byte id `i`. 64 caller
    actors wait **nested** (`[(hub request: i) wait] ensure: []`, which blocks the worker) and
    64 wait at the top level of their method (which suspends the actor). The main thread
    writes the 128 ids to the socket after an `Atom` counter shows 128 registrations. It prints
    the number of callers that answered and the number of `deadlock:` errors caught.
  - `cluster_values.st` (`"EXPECT: ok 10"`): `MessagePack` round trip of 2^56, 2^62 - 1, 2^63
    and 2^64 - 1 (decode of encode equals, and `<` against 2^56 - 1 is right);
    `-5 // 4096 = -1` and `(0 - 5) // 4096 + 1 * 4096 + 5 = 5` (floor division, the ballot
    formula); two `Random seed: 42` generators give equal 100-value sequences;
    `(HMAC sha256Key: 'Jefe' utf8Encoded message: 'what do ya want for nothing?' utf8Encoded) hex`
    is `'5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'` (RFC 4231 case 2);
    `(ByteArray randomBytes: 8)` read as an unsigned integer and masked with `2^62 - 1` is a
    non-negative Integer below 2^62; `Atom value:ifCurrent:` answers true on the current value
    and false on a stale one.
- [ ] **Step 2:** run `tests/run_tests.sh tests/week0`. Expected: every check PASS. These
  check protoST itself, so there is no implementation step: a FAIL is a protoST defect. **On a
  FAIL, stop** and open Task 1b with the failing line.
- [ ] **Step 3:** record the results. In `docs/deviations.md`, update the K23 entry with
  "not reproduced with Futures settled by network events (Task 1 of the cluster plan,
  2026-11-xx)" or the reproduction. In `docs/decisions.md` "What is still open", add the
  `nextBytes:` semantics as observed.
- [ ] **Step 4:** run the whole suite. Expected: all PASS.
- [ ] **Step 5:** commit `Cluster week 0: socket reads, timers under blocked readers, K23 with network-settled futures, large integers`.

### Task 1b (conditional, flagged for the maintainer): protoST fix for a Phase 0 defect

Only if a Task 1 check failed. It is a protoST task, on protoST's branch, with its own test in
protoST's conformance suite and a `KNOWN_ISSUES.md` entry. It needs the maintainer's approval
before it starts (protoST changes are separate tasks). protoBaseST work resumes at Task 2 only
when the failing check passes against the rebuilt binary (`ldd` the binary and record the
protoCore it links). If the defect is in protoCore, nothing is changed there: write a proposal
and stop.

---

## Phase A: format and wire layers, no network (spec 8.1 T1-T5)

Tests use `tests/unit/_check.st` (`Check new`, `that:is:equals:`, `that:signals:containing:during:`,
`report`). Vector tests use `tests/conformance/_vectors.st` (`Vectors manifest`,
`Vectors bytesOf:`). Each Phase A task removes its items from the skip lines of
`tests/conformance/cluster.st`; by the end of Task 6 the file prints no skip, and its
`PBNotSupportedError` check of a plain `path:` storage stays.

### Task 2: `PBFramedLog` with the linear torn-tail search

**Files:**
- Create: `src/protobase/cluster/log.st`.
- Modify: `src/protobase.st` (import `protobase/cluster/log` after `store`);
  `tests/unit/values_immutable.st` and `tests/docs/reference_selectors.sh` (scan
  `src/protobase/cluster/*.st` too); `tests/conformance/cluster.st` (drop the `log`-layer,
  `ranges_log`, `segments_log` and `roots_log_torn` skips).
- Test: `tests/unit/cluster_framed_log.st`, `tests/conformance/framing_logs.st`.

**Interfaces:**
- Produces:
  - `PBFramedLog class >> header: aKind` → 14-byte `ByteArray` (`'PDB2LOG'` + 0x00, u16 LE 2,
    4 ASCII bytes); kinds `'ROOT' 'RANG' 'SEGS'`.
  - `PBFramedLog class >> frame: aPayload` → `C1 F7`, u32 LE length (> 0), CRC-32 of the
    payload, CRC-32 of the 10 bytes before it, payload (LE throughout).
  - `PBFramedLog class >> scan: aByteArray kind: aKind path: aString` → `PBLogScan`
    (`payloads` Array of ByteArray, `validEnd` Integer, `isTorn` Boolean). A header that is a
    prefix of the expected one (optionally followed by zero bytes only) is a new log; another
    header is `PBCorruptionError`, another version `PBNotSupportedError`.
  - `PBFramedLog class >> read: aPath kind: aKind` → `PBLogScan` (never writes).
  - `PBFramedLog class >> openAppend: aPath kind: aKind` → a `PBFramedLog`: creates the file
    with its header when absent, then `sync`s the file, its directory and the parent directory;
    truncates a torn tail and `sync`s before answering. `payloads` (read at open),
    `append: aPayload sync: aBoolean`, `close`, `isClosed`, `path`.
  - `PBFramedLog class >> crcOf: aByteArray from: start to: end` — the one place CRCs are
    computed (a seam the complexity test counts through).
- Algorithm (FS-log, `logfile.py` `scan`, `_first_valid_frame`): at the first invalid position,
  torn tail when fewer than 14 bytes remain, or the header is valid and its frame extends past
  the end, or no valid frame starts later (after the frame's extent when its header is valid, at
  any later offset when not); otherwise `PBCorruptionError` naming the offset. The search for a
  later valid frame visits candidate `C1 F7` positions once and checks payload CRCs with prefix
  checksums at 4096-byte checkpoints (`_CRC_CHECKPOINT`) and `CRC32 combine:with:length:`,
  direct CRC up to 16384 bytes (`_CRC_DIRECT`): linear in the file size, never quadratic (R14).

- [ ] **Step 1: write the failing tests.**
  - `cluster_framed_log.st` (`"EXPECT: ok 11"`): header and frame bytes of a 3-byte payload
    equal the hex computed in the test from the FS-log table; scan of header + 3 frames answers
    the 3 payloads; a file cut inside its last frame is torn (`validEnd` = end of frame 2, 2
    payloads); damaged frame 2 followed by valid frame 3 is `PBCorruptionError` containing
    `'mid-log'`; a header prefix `'PDB2'` is a new log with no payload; `openAppend:` on a torn
    file truncates to `validEnd` and the next `append:sync:` lands at `validEnd`; a zero-length
    payload is refused (`PBValidationError`). **Linearity:** a test subclass of `PBFramedLog`
    overriding `crcOf:from:to:` to add the byte count to an `Atom` scans a 1 MiB file made of one
    valid frame followed by `C1 F7` repeated with random bytes between; the bytes CRC'd are at
    most 3 × the file size.
  - `framing_logs.st` (`"EXPECT: framed logs ok"`): `roots-torn.log` scans to 6 payloads and
    `validEnd` 671 (manifest `roots_log_torn`); `segments.log` holds one payload equal to the
    listed UUID's 16 bytes; `ranges.log` holds one payload equal to the 44 + 32 bytes the test
    builds from the manifest entry (CC16); the `invalid` entries of layer `log` signal the
    manifest's error (`not_supported` → `PBNotSupportedError`, `corruption` →
    `PBCorruptionError`).
- [ ] **Step 2:** run `tests/run_tests.sh tests/unit/cluster_framed_log.st tests/conformance/framing_logs.st`.
  Expected: FAIL (`PBFramedLog` not understood).
- [ ] **Step 3:** implement `log.st` as specified, after reading `logfile.py` at the tag.
- [ ] **Step 4:** run both tests, then the whole suite. Expected: PASS; `cluster.st` prints no
  `log`-layer skip.
- [ ] **Step 5:** reference ("Lower layers": `PBFramedLog`), CHANGELOG (first `0.2.0` entry,
  noting R14's condition is met); commit `Cluster A1: framed logs with the linear torn-tail search`.

### Task 3: Membership, ballots, voter fingerprint, root order; SpaceRoot cluster fields written

**Files:**
- Create: `src/protobase/cluster/members.st` (CC23), `src/protobase/cluster/rootlog.st` (order
  part only).
- Modify: `src/protobase/roots.st` (`PBSpaceRoot class >> databases:term:epoch:previous:`);
  `src/protobase.st`; `tests/conformance/cluster.st` (drop the `segment` skip).
- Test: `tests/unit/cluster_members.st`, `tests/unit/cluster_root_order.st`,
  `tests/conformance/cluster_segment.st`.

**Interfaces:**
- Produces:
  - `PBPeer class >> nodeId: aString host: aString port: anInteger`; `nodeId`, `host`, `port`.
  - `PBMembership class >> peers: anArrayOfPBPeer voters: anArrayOrNil` with `_voter_set`'s
    rules (default: the first three sorted ids, every member of a smaller cluster; explicit:
    distinct members, odd and at least 3 when the cluster has 3 or more). Refuses an empty or
    non-String id, duplicate ids, more than 4096 members (`PBValidationError`). `ids` (code
    point order), `rankOf: anId`, `voters`, `isVoter: anId`, `majority` (`V // 2 + 1`),
    `fingerprint` (CRC-32 of the UTF-8 of the sorted voter ids joined with `','`),
    `peerNamed: anId`.
  - `PBMembership class >> ballotAfter: aFloor rank: r` → `((aFloor - r) // 4096 + 1) * 4096 + r`;
    `rankBits` 12; `refoundStep` 2^44.
  - `PBLabeledRoot class >> label: anInteger record: aPBRootRecordOrNil` (record nil: the empty
    space, known); `label`, `record`, `epoch` (0 for the empty space), `key` →
    `{label. epoch. segmentBytes (16 zero bytes when empty). offset}`. An unknown root is `nil`,
    never a `PBLabeledRoot`.
  - `PBRootOrder class >> compare: a with: b` → -1, 0, 1 on `key` (nil orders below every
    known root); two different roots with equal `(label, epoch)` signal `PBCorruptionError`.
    `max: a with: b`. The only root comparison in the code base (L9).
  - `PBSpaceRoot class >> databases: aDictionary term: anInteger epoch: anInteger previous: aSpaceRootOrNil`
    → unsaved root with state keys in the order `databases cluster_term cluster_epoch cluster_previous`
    (the vector's order).

- [ ] **Step 1: write the failing tests.**
  - `cluster_members.st` (`"EXPECT: ok 13"`): ranks of `#('n2' 'n0' 'n1')` are 0, 1, 2 for
    `n0 n1 n2`; code point order puts `'Z'` before `'a'`; default voters of 5 members are the
    first three; voters of a 2-member cluster are both; explicit voters of 4 are refused;
    duplicate ids refused; 4097 members refused; `majority` of 3 voters is 2;
    `fingerprint` of `#('n0' 'n1' 'n2')` equals `'n0,n1,n2' utf8Encoded crc32`;
    `ballotAfter: 0 rank: 5` = 5; `ballotAfter: 4101 rank: 5` = 8197; `ballotAfter: 4100 rank: 5` = 4101;
    two ranks never produce the same ballot for 200 random floors (`Random seed: 7`).
  - `cluster_root_order.st` (`"EXPECT: ok 7"`): label dominates epoch; epoch dominates
    segment; segment bytes dominate offset; nil below the empty space; empty space of label 3
    above a root of label 2; equal `(label, epoch)` with different offsets signals
    `PBCorruptionError`; `max:with:` symmetric.
  - `cluster_segment.st` (`"EXPECT: cluster segment ok"`): with the segment id, oid and offsets of
    manifest `cluster.segment` fixed through the existing seams (as `bytes_pinned.st` does),
    writing `PBSpaceRoot databases:term: 7 epoch: 4 previous:` gives the record bytes of the
    vector; reading the vector answers `clusterTerm` 7, `clusterEpoch` 4.
- [ ] **Step 2:** run the three tests. Expected: FAIL.
- [ ] **Step 3:** implement, after reading `rootlog.py` `root_key`/`compare_roots`,
  `coordinator.py` `_voter_set`, and FS-wire "Values a member must compute".
- [ ] **Step 4:** run them, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster A2: membership, ballots, voter fingerprint, root order, cluster SpaceRoot fields`.

### Task 4: `PBAcceptorLog`

**Files:**
- Modify: `src/protobase/cluster/rootlog.st`; `tests/conformance/cluster.st` (drop the
  `roots_log` and `roots_log` invalid-layer skips).
- Test: `tests/unit/cluster_acceptor_log.st`, `tests/conformance/rootlog.st`.

**Interfaces:**
- Consumes: Task 2 `PBFramedLog`, Task 3 `PBLabeledRoot`, `PBRootOrder`.
- Produces:
  - `PBAcceptorLog class >> path: aPath` → opens or creates the `ROOT` log, after taking
    `tryLock` on `aPath , '.lock'` (`LOCK_SUFFIX`); a held lock is `PBUserError` naming the lock
    file (Review Focus 3). Creation syncs file, directory and parent directory (L10).
  - `append: aKind label: anInteger root: aPBRootRecordOrNil` for `#accepted #committed`,
    `promise: aTerm`, `markRejoined`. Every entry is synced before the call answers, except
    `#committed` (knowledge, R67); a sync failure is `PBUnexpectedError` and the log refuses
    every later call (`isFailed`).
  - `load` → `PBLoggedRoots`: `accepted`, `committed` (`PBLabeledRoot` or nil), `promise`
    (Integer, 0 when none), `top` (highest label or term of any entry but kind 4), `isRejoined`,
    `dataEntryCount` (kinds 5 and 6), `entries` (Array of `PBLogEntry`: `kind label root seq
    pred records ranges flags`, for the vectors).
  - `PBAcceptorLog class >> decode: anArrayOfPayloads path: aString` → `PBLoggedRoots` (pure;
    41-byte kinds 1-4 `<BQQ16sQ>`; kind 5 head 93 bytes `<BQQ16sQQQQ16sQI>` + items
    `<16sQI>` + bytes; kind 6 head 98 bytes `<BBQQ16sQQQQ16sQII>`, ranges `<16sQQ>`, flag bit 0
    `ACCEPTED`). Corruption: another size of kinds 1-4, unknown kind, kind 5/6 cut inside an
    item or with trailing bytes, other flag bits, a range with start > end, two different roots
    with equal `(label, epoch)` (via `PBRootOrder`).
  - `PBAcceptorLog class >> encode: aKind label: anInteger root: aRootOrNil` → 41-byte payload.

- [ ] **Step 1: write the failing tests.**
  - `rootlog.st` (`"EXPECT: roots log ok"`): decoding `cluster/roots.log` gives the manifest's
    entries field by field (kind, label, root, seq, pred, records, ranges, flags) in order;
    `load` of a copy answers the manifest's `root`, `label`, `loaded` values; re-encoding each
    kind 1-4 entry gives its payload bytes; each `invalid` entry of layer `roots_log` signals
    `PBCorruptionError`.
  - `cluster_acceptor_log.st` (`"EXPECT: ok 9"`): a fresh log loads empty (`isRejoined`
    false); promise 7, accepted, committed, rejoined appended and reloaded in a new instance;
    `top` ignores the rejoined marker; a second `path:` on the same file while the first is
    open is `PBUserError` containing `'.lock'`; after `close` it opens. A test subclass whose
    `PBFramedLog` fails `sync` once makes `append:` signal `PBUnexpectedError` and the next call
    `PBUnexpectedError` containing `'failed'`. The syncs a promise makes are counted through a
    seam subclass: one file sync per `promise:`, zero per `#committed`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `rootlog.py` (`_decode`, `RootsLog`) at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster A3: the acceptor log, kinds 1-4 written, 1-6 read`.

### Task 5: Wire messages: 22 types, validation, message vectors

**Files:**
- Create: `src/protobase/cluster/protocol.st`.
- Modify: `src/protobase/errors.st` (`PBClusterProtocolError`, a `PBCorruptionError`);
  `tests/unit/errors_hierarchy.st`; `tests/conformance/cluster.st` (drop the message skips
  except `message-oversized`, which Task 6 owns).
- Test: `tests/unit/cluster_messages.st`, `tests/conformance/messages.st`.

**Interfaces:**
- Consumes: Task 3 `PBLabeledRoot`.
- Produces:
  - `PBClusterMessage class >> protocolVersion` → 13; `schema` → `Dictionary` from type to the
    Array of `name -> fieldKind` in the order of the FS-wire table, copied verbatim, with kinds
    `#int #number #str #bool #root #records #uuid #optBytes #optStr #ranges #strs #after`.
  - `PBClusterMessage class >> type: aString from: anId fields: anArrayOfAssociations` →
    validated message (`PBValidationError` when built wrong: a bug of ours, not a peer's).
  - `type`, `from`, `at: aFieldName`, `encode` → msgpack bytes of a `MessagePackMap` in the order
    `v type from <fields>`.
  - `PBClusterMessage class >> decode: aByteArray` → validated message, or
    `PBClusterProtocolError` for: not one map, a non-String key, missing `v`/`type`/`from`,
    another version, unknown type, a missing or ill-typed field (extra fields ignored).
  - `PBClusterMessage class >> rootValue: aLabeledRootOrNil` and `rootFrom: aWireValue` (CC17);
    `rangesValue:`/`rangesFrom:`, `afterFrom:` (DEPTH 0 never sends a non-nil `after`).

- [ ] **Step 1: write the failing tests.**
  - `messages.st` (`"EXPECT: messages ok 23"`): for each of the 23 frames of the manifest
    (22 types + `unknown-root`), strip the 4-byte length, `decode:`, compare each field with
    the manifest's typed value, and `encode` equals the body byte for byte; each `invalid`
    entry of layer `message` except `message-oversized` signals `PBClusterProtocolError`.
  - `cluster_messages.st` (`"EXPECT: ok 10"`): a `request` with an extra field decodes (extra
    ignored) and re-encodes without it; `term` as a Float is refused; `remaining` as a Float
    is accepted (`#number`); `root` `[0, nil, nil, 9]` decodes to the empty space of label 9;
    the 3-item root decodes with label 0; a root of a 15-byte segment is refused; `ranges`
    with start > end refused; a map with an integer key refused; `PBClusterProtocolError
    inheritsFrom: PBCorruptionError`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `protocol.py` (`MESSAGE_TYPES`, `_check_field`,
  `validate_message`, `encode_root`, `decode_labeled_root`) at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster A4: the 22 protocol-13 messages, validated`.

### Task 6: Frames and optional HMAC authentication

**Files:**
- Modify: `src/protobase/cluster/protocol.st`; `tests/conformance/cluster.st` (last skip
  dropped; the file now prints `cluster vectors ok` and keeps its refusal check).
- Test: `tests/unit/cluster_frames.st`.

**Interfaces:**
- Consumes: Task 5 `PBClusterMessage`.
- Produces:
  - `PBClusterFrame class >> maxFrameBytes` → 67108864; `tagSize` → 32.
  - `PBClusterFrame class >> encode: aMessage to: aNodeId key: aKeyOrNil` → 4-byte big-endian
    length + body; with a key the body is msgpack ‖ tag (CC4).
  - `PBClusterFrame class >> lengthFrom: aFourByteArray` → Integer;
    `PBClusterProtocolError` above `maxFrameBytes` (read before any allocation).
  - `PBClusterFrame class >> decodeBody: aByteArray to: aNodeId key: aKeyOrNil` → message;
    with a key: a body shorter than 32 bytes, or a wrong tag, is `PBClusterProtocolError`
    containing `'authentication'`.
  - `PBClusterFrame class >> decode: aFrame to: aNodeId key: aKeyOrNil` (length + body).

- [ ] **Step 1: write the failing tests.** `cluster_frames.st` (`"EXPECT: ok 9"`): without a key,
  `encode:to:key:` of the decoded `request.frame` equals the vector frame byte for byte
  (protocol-13 bytes); `message-oversized.bin`'s length is refused by `lengthFrom:`; with a
  32-byte key, a frame round-trips; the tag equals
  `HMAC sha256Key: key message: ('n1' utf8Encoded , #[0] , body)` (computed in the test); the
  same frame decoded `to: 'n2'` is refused (receiver binding); a flipped tag byte is refused;
  a keyed frame read without a key is refused (the tag bytes are not msgpack) and an unkeyed
  frame read with a key is refused; a key of 31 bytes is refused (`PBValidationError`).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement; the tag comparison accumulates the XOR of all 32 bytes and tests
  it once (CC4).
- [ ] **Step 4:** run, then the suite. Expected: PASS; `cluster.st` prints no skip.
- [ ] **Step 5:** reference, CHANGELOG, `docs/deviations.md` (new section "Cluster mode" with
  the frame authentication divergence and the trusted-network statement, both cases, Q5);
  commit `Cluster A5: frames, size limit and optional HMAC frame authentication`.

### Task 7: Cluster configuration and the timer table

**Files:**
- Create: `src/protobase/cluster/config.st`.
- Test: `tests/unit/cluster_config.st`.

**Interfaces:**
- Consumes: Task 3 `PBMembership`, Task 6 key rule.
- Produces: `PBClusterConfig class >> nodeId: anId peers: anArrayOfPBPeer options: aDictionary`.
  Options (milliseconds unless stated): `#leaseDuration` 2000, `#driftMargin` (default ⌈2D/3⌉,
  refused below it, R78b, L6), `#requestTimeout` 250 (refused unless below the belief),
  `#sendReserve` (default min(requestTimeout, belief // 4); refused above belief // 4, plant
  `reserve_uncapped`), `#acquireTimeout` 30000, `#backoff` `#(1 50)`, `#startupGrace` (default
  D + margin), `#persistInterval` 50, `#persistLag` 1000, `#ownerIdleRelease` nil,
  `#voters` nil, `#authKey` nil (`ByteArray` ≥ 32 bytes), `#seed` nil, `#transport` and
  `#clock` (test seams). An unknown option is `PBValidationError` naming it; `#fetchTimeout`
  and tier options are `PBNotSupportedError` naming Phase D (CC8). The node id must be a member.
  Accessors answer microseconds (CC3): `leaseDuration driftMargin belief requestTimeout
  sendReserve acquireTimeout backoffLow backoffHigh startupGrace idleEnd persistInterval
  persistLag ownerIdleRelease`; constants `wakeSpread` 3000, `minStraggle` 5000,
  `straggleFactor` 4, `turnSilence` (min 50000, requestTimeout), `gatherAttempts` 3,
  `retryHold` 100000, `retryWait` 5000, `permitRetries` 3, `depth` 0; `membership`, `nodeId`,
  `rank`, `authKey`, `seed`.
- `PBClusterConfig class >> timerTable` → Array of `{name. default description. what it drives}`
  with one row per timer of CP "Timers" that applies at `DEPTH = 0` over shared storage
  (rows `fetch_timeout`, data replica hedge and gate fallback are absent). Task 17's audit
  iterates it, and Task 29 generates the docs table from it.

- [ ] **Step 1: write the failing test.** `cluster_config.st` (`"EXPECT: ok 13"`): defaults in µs
  (`belief` 666666, `sendReserve` 166666, `startupGrace` 3333334, `idleEnd` 500000);
  `driftMargin: 1333` refused, `1334` accepted; `sendReserve: 200` refused (above belief // 4);
  `requestTimeout: 700` refused; unknown `#lease` refused naming it; `#fetchTimeout` is
  `PBNotSupportedError` containing `'Phase D'`; self id missing refused; `#authKey` of 31
  bytes refused; `timerTable` has one row per expected name (list in the test).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `ClusterCoordinator.__init__` (`coordinator.py:559-630`).
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference (configuration table), CHANGELOG; commit `Cluster A6: configuration, defaults in microseconds, the timer table`.

### Task 8: Lease values: grant state, attempts, leases, permissions

**Files:**
- Create: `src/protobase/cluster/lease.st`.
- Test: `tests/unit/cluster_lease_values.st`.

**Interfaces:**
- Consumes: Tasks 3 and 7.
- Produces (immutable values; every "with" answers a new value):
  - `PBGrantState class >> initial: aConfig now: t` (grace end = t + startupGrace);
    `restore: aLoggedRoots` (max of the logged promise and the accepted label; reads no clock);
    `restore: aTerm seen: aSeen` (lease.py `restore(term, seen=)`, coordinator.py:1434: the
    rejoin's form, `termsSeen` rising only to `min(seen, term)`; consumed by Task 16);
    `promise: aTerm` → `{ newState. endedTerm }` (lease.py:155-167, `PeerGrants.promise`, R78a:
    a rejoin witness promises the ballot, ending a grant of a lower term; called from
    `_on_ballot_query`, coordinator.py:1874, so consumed by Task 16's witness side);
    `decideRequest: aHolder inc: anInc term: aTerm now: t config: c`
    → `PBGrantDecision` (`verdict` `#grant | #reject`, `reason` (the wire strings of
    `lease.py`/`coordinator.py`, verbatim: `granted bad_ballot starting stale_term busy term_taken`),
    `highest`, `remaining` µs, `promiseToLog` (the term on every grant, renewals included; nil on a
    refusal; the acceptor log writes nothing at or below its durable promise), `endedTerm` (a grant
    ended without its holder's release, 0 when none: the node is suspect for it), `newState`);
    `renew:inc:term:now:config:`; `release:inc:term:now:` → `{ newState. endedTerm }` (settles
    an expired grant first, closes the term at this receiver);
    `highestSeen`, `termsSeen` (lease.py `terms_seen`, R51: lease activity only; Task 10's query
    answers use it), `highestGranted`, `grantedTop`, `activeGrant` (a `PBActiveGrant`: `holder inc
    term expiry`, or nil), `isStarting: t`.
  - `PBAttempt class >> term: t rid: r sentAt: s voters: v` (`needed` = v // 2 + 1); `withGrant: peer
    root: aRoot committed: aRoot certain: aBoolean`, `withReject: peer reason: r highest: h
    remaining: m` (a peer counts once; a refusal's highest always counts);
    `state` (`#pending #won #lost`), `bestRoot: ownRootOrNil suspect: aBoolean` →
    `{PBLabeledRoot-or-nil. certain}` (CP 1.5 step 5: highest in root order of the granters' roots
    and the requester's own; certain when every granter knows a root, none is suspect and the
    requester is not), `busyRemaining`, `highestSeen`, `needed`, `replies` (R39's straggler
    rule: `replies >= needed`), `committedRoots`, `validUntil: aConfig` (`sentAt + belief`,
    lease.py `valid_until`).
  - `PBLease class >> term: t validUntil: v root: r certain: c` with `validUntil = sentAt +
    belief` **from the send** (L5); `remainingAt: now`, `isValidAt: now`.
  - `PBPermission class >> term: t seq: s rid: r owner: anId root: aRoot certain: c sentAt: aSent
    valid: v` (a `PBLease`; `validUntil` = request send + `valid`; certain only when the root is
    known; `after` always nil at DEPTH 0).

- [ ] **Step 1: write the failing test.** `cluster_lease_values.st` (`"EXPECT: ok 16"`): one row
  per rule of `lease.py` `PeerGrants.on_request` (refusals `starting` during grace, `stale_term`,
  `busy` with the remaining promise, `term_taken`; a grant above `granted_top` with
  `promiseToLog`; a renew of the active grant; a release closing the term; `restore:` from a
  logged promise refuses below it); attempt reaching `needed` grants is `#won`; best root by
  root order; uncertain when one granter reports a nil root; a lease valid at `sentAt + belief - 1`
  and invalid at `sentAt + belief` even when the grants arrived late (L5's planted case:
  measured from the win it would still be valid); `promise:` ends a lower grant; term 0 and
  `restore: 0 seen: 0` decided as proto_db; nil arguments refused.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `lease.py` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference (lower layers), CHANGELOG; commit `Cluster A7: grant state, attempts, leases and permissions as values`.

---

## Phase B: the coordinator core and the simulator (spec 8.1 T6-T11)

Every rule is a method of `PBCoordinatorCore` (stateless; `PBCoordinatorCore new` is the
product rules object), defined in the module of its concern (`core.st`, `acceptor.st`,
`proposer.st`, `owner.st`, `holder.st`, `rejoin.st` under `src/protobase/cluster/`, each
importing the previous). A method's comment cites its source. Tests of Phase B are scenario
families in the simulator: each is a seed list (CC14) plus fixed schedules, and the checker runs
after every step. Pipelined permits (spec T12) are **not** in this plan (Q3: `DEPTH = 0`).

### Task 9: Core vocabulary and the deterministic simulator

**Files:**
- Create: `src/protobase/cluster/core.st` (events, effects, `PBStep`, `PBAcceptorStep`,
  `PBNodeState`, `PBCoordinatorCore` with `dispatch:in:now:` and `accept:in:now:` routing to
  `doesNotUnderstand`-free per-event methods); `tests/unit/_sim.st`.
- Test: `tests/unit/sim_harness.st`.

**Interfaces:**
- Produces (product, `core.st`):
  - Events: `PBReceived message:`, `PBTimerFired token: event:`, `PBStartNode`,
    `PBPermitWanted waiter:`, `PBBaseWanted permission: waiter:`, `PBReplicateWanted
    permission: root: waiter:`, `PBDoneReport permission: outcome:`, `PBRejoinWanted`,
    `PBStopNode`, `PBAcceptorDecided step:` (acceptor → dispatcher).
  - Effects: `PBSend to: message:`, `PBToAcceptor event:` (CC1), `PBLogAppend kind: label:
    root: sync:` (acceptor steps only), `PBTimer after: µs token: event:` (a token per timer;
    a stale token is ignored), `PBSettle waiter: outcome:`, `PBPublishCommitted root:`,
    `PBPublishAcceptor state:`, `PBFence reason:`.
  - `PBStep state: effects:`; `PBAcceptorStep state: appends: reply:` (the reply effects are
    performed only after every append is durable).
  - `PBNodeState class >> config: aConfig inc: anInteger` (with `acceptorView`, `hints`,
    `proposer`, `ownership`, `waiters`, `suspectTerm`, `fenced`, `rejoin`, `nextRid`);
    `PBAcceptorState class >> config: aConfig logged: aLoggedRoots now: t`.
  - `PBCoordinatorCore >> dispatch: anEvent in: aNodeState now: t` → `PBStep`;
    `accept: anEvent in: anAcceptorState now: t` → `PBAcceptorStep`.
- Produces (test support, `_sim.st`): `PBSim class >> seed: n ids: anArray rules: aRules options: aDictionary`;
  `faults: (PBSimFaults drop: p duplicate: p delay: maxµs reorder: aBoolean)`, `partition:`,
  `heal`, `clockRate: id rate: aFraction` (`PBSimClock`), `crash: id keepDisk: aBoolean`,
  `restart: id`, `tearLog: id`, `commit: aToken at: id` (a synthetic transaction),
  `step`, `runUntil: aBlock steps: n`, `converge: n`, `checker` (`PBSimChecker`), `trace`.
  `PBSimDisk` keeps synced and unsynced appends per node (a crash drops the unsynced; `tearLog:`
  cuts the last synced frame). The scheduler draws every choice from one `Random seed: n`.
  `PBSimChecker` checks after every step: at most one owner per term (S1); no two different
  roots with equal `(label, epoch)` anywhere; no acceptor reply delivered before its append is
  synced; and at `checkConverged`: every acknowledged commit is in every live node's committed
  chain (S4, walked through the sim's `pred` links), every unknown commit present everywhere or
  absent everywhere. A violation signals `Error` whose text holds the seed and the last 200 trace
  lines.

- [ ] **Step 1: write the failing test.** `sim_harness.st` (`"EXPECT: ok 7"`): with a test rules
  subclass that only echoes a `want` to every peer on `PBStartNode`: two runs of seed 11 give
  identical traces; seeds 11 and 12 differ; a partition stops delivery and `heal` resumes it;
  `clockRate: 'n1' rate: 3/2` makes `n1`'s timers fire earlier in virtual time; an unsynced
  append is gone after `crash:keepDisk: true`; the checker reports a planted equal-`(label,
  epoch)` pair with the seed in the text; no step reads a wall clock (the test greps
  `_sim.st` and `src/protobase/cluster/*.st` for `millisecondClockValue`,
  `microsecondClockValue`, `utcMicroseconds`, `nowUTC`: none).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement `core.st` vocabulary and `_sim.st`.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference (lower layers: the core's entry points), CHANGELOG; commit `Cluster B1: core vocabulary and the seeded virtual-time simulator`.

### Task 10: Acceptor core, phase 1: grants, refusals, renewals, releases, restore

**Files:**
- Create: `src/protobase/cluster/acceptor.st`.
- Test: `tests/unit/sim_grants.st`.

**Interfaces:**
- Consumes: Tasks 8, 9.
- Produces: `PBCoordinatorCore` acceptor methods: `acceptRequest:in:now:`,
  `acceptRenew:in:now:`, `acceptRelease:in:now:`, `acceptQuery:in:now:` (the `answer` of a
  plain query: `state` `ok`/`empty`/`unknown`, `promised`, ballot 0), `acceptStart:in:now:`
  (the start's acceptor work beyond the grace and the restore), `acceptSuspect:in:now:`. A grant appends
  `PBLogAppend kind: #promise sync: true` and its `grant` reply carries the accepted and
  committed roots and `certain`. Refusals: `fenced`, learner, no log, tier failed, rejoining
  (log without kind 4), `bad_ballot`, `starting`, `stale_term`, `busy` (with remaining),
  `term_taken`, `promise_failed` (an append failure withdraws the grant). A grant answers `promiseToLog` on every grant, renewals included: the
  scenario `renew keeps the term without a log write` counts real acceptor-log writes (the
  `PBSimDisk` appends), not `promiseToLog` or `PBLogAppend` effects. A request, renewal or
  release from a sender that is not a member is dropped before `decideRequest:`/`renew:`
  (`rankOf:` signals `PBValidationError` for it; proto_db drops it in the dispatcher). A query
  answer's `promised` is `max(termsSeen, accepted label)` (coordinator.py:1852, 1884), 0 when
  `state` is `unknown`. Controller ruling (Task 9 review): `PBAcceptorState config:logged:now:` owns building
  the startup grace (`PBGrantState initial:now:`) and restoring the log (`restore:`), once, when
  the node starts; `acceptStart:in:now:` must rebuild neither, and a re-attach of a running node
  reuses the existing state (coordinator.py:977 versus 1134: the grace is not restarted). The wire `remaining` is a
  number of seconds (`#number`, a float in proto_db): the core converts it when it builds a
  reject (`PBCoordinatorCore class >> wireSeconds:`, `(µs / 1000000) asFloat`, bit-exact with
  Python's `µs / 1e6` below 2^53 µs); the inbound direction (a received reject's `remaining` to
  µs for `PBAttempt withReject:`) is Task 11's. `vs` mismatch drops
  the request and counts `config_mismatches`; another `inc` than the active grant's is a new
  holder.
- Scenario families (proto_db `test_cluster_lease`, `_terms`, `_renewal`, `_voters`):
  `grant then busy for another holder`, `release ends busy at once`, `startup grace refuses
  (efficiency only)`, `restart restores the promise from the log, never below it` (L17),
  `learner never grants`, `renew keeps the term without a log write`, `a refused higher request
  does not end the owner's renewals` (plant `renew_stale`), `no reply before the promise is
  synced` (checker).

- [ ] **Step 1: write the failing test** `sim_grants.st` (`"EXPECT: ok 9"`: one check per
  family above over seeds 1-40, plus one check that `PlantRenewStale` makes its family fail).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `coordinator.py` `_on_request`, `_on_renew`,
  `_on_release`, `_answer_query` and `lease.py` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B2: acceptor phase 1, grants and refusals as pure rules`.

### Task 11: Proposer core: acquiring, owning, renewing, releasing, fairness hints

**Files:**
- Create: `src/protobase/cluster/proposer.st`.
- Create: `tests/unit/_plants.st` (planted rules, grows in later tasks).
- Test: `tests/unit/sim_leases.st`.

**Interfaces:**
- Consumes: Tasks 8-10.
- Produces: `PBCoordinatorCore` proposer methods (CP 1.5): local head-of-queue asks only;
  `ballotFor: aNodeState` (`ballotAfter:` of max(highest seen, hint, accepted label, committed
  label)); own vote through `PBToAcceptor` (CC1); `request` to the other voters with `vs`;
  **Task 10 carry-overs:** (a) lift the acceptor's drop of this node's own messages
  (`PBCoordinatorCore >> acceptReceived:in:now:` in `core.st`, the `_fromPeer:in:` check, which
  also drops `from = nodeId`), so the own vote is decided by `acceptRequest:in:now:` as CC1 says,
  and replace check 2 of `tests/unit/cluster_acceptor_rules.st` (which pins that drop). (b) How
  the dispatcher learns its own vote, following proto_db (`_open_attempt` decides the own vote
  with `_decide` and records it in the attempt; `_promise` then makes it durable and, on failure,
  `granted_by.pop(self._node)` and `on_reject(self._node, "promise_failed", term, 0.0)`): the
  acceptor's step for an own request answers no `PBSend` (a node never sends to itself); the
  dispatcher reads the vote from the step handed back in `PBAcceptorDecided` (the grant or
  reject message the step carries, a field this task adds to `PBAcceptorStep`), and when the
  shell reports the step's append failed (`PBAppendFailed`, the step discarded) the dispatcher
  records `withReject: nodeId reason: 'promise_failed' highest: term remaining: 0` (the shell
  hands the dispatcher that outcome with the discarded step). (c) The inbound `remaining`: a
  Float of seconds to Integer µs as `(seconds * 1000000) rounded`, the exact inverse of
  `wireSeconds:` for every value it produces. (d) Message routing: add `received<Type>:in:now:`
  handlers (grant, reject, answer, want, ...) next to acceptor.st's; never redefine
  `dispatchReceived:in:now:` (core.st, it holds the peer and `vs` checks). Likewise extend
  `dispatchStartNode:in:now:` (core.st) by keeping its `PBToAcceptor` start effect. (e)
  `PBSuspect term:` (acceptor.st) has no product caller yet: the dispatcher emits it whenever
  proto_db raises `_suspect_term` outside the acceptor (an abandoned term, Task 12; a
  replication outcome it cannot know, Task 13), else it stays dead code and is removed;
  winning before `validUntil` measured from the send; losing: cancel with `release`
  (`held=false`), jittered back-off in `[backoffLow, backoffHigh]` drawn from the seeded
  `Random`, ended early by any release, `_WAKE_SPREAD`; once a majority answered an undecided
  attempt, wait `max(minStraggle, straggleFactor × observed)` for the rest (R39); owning:
  renew at half the belief left while there is demand; idle end after `idleEnd` without demand;
  `ownerIdleRelease`; releases carry the committed root, `certain`, `next` (the member waiting
  longest), `more`; `want` and `_TURN_SILENCE` deferral (D-LIVE-1); owner hint learnt only from
  messages proving a term was won; incarnation checks on every reply (L12); a reply from a
  member that is not a voter is never recorded with `withGrant:`/`withReject:` (`PBAttempt`
  does not filter, as proto_db's `LeaseAttempt`; `_on_reply` drops it, coordinator.py:2001, D54);
  the lease's end is `PBAttempt validUntil:`.
- Scenario families (`test_cluster_terms`, `_renewal`, `_fairness`, `_coordinator`): `one
  owner per term under drop/dup/reorder` (seeds 1-200), `two proposers never share a ballot`,
  `a grant delayed past the belief is not a win` (L5, plant `PlantWindowFromWin` must fail),
  `clock rates 2/3 to 3/2 keep S1` (skew per node), `releases name the longest waiter and the
  turns rotate` (D-LIVE-1: over 300 virtual leases with fsync-cost appends modelled as 3 ms,
  no member wins more than 60 %), `cancel does not end the back-off of a refused request`
  (plant `cancel_wakes`), `replies of another incarnation are dropped`.

- [ ] **Step 1: write the failing test** `sim_leases.st` (`"EXPECT: ok 9"`: the seven families,
  plus one check per plant (`PlantWindowFromWin`, `PlantCancelWakes`) that runs the family with
  the plant and expects the checker's error).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `coordinator.py` `acquire`, `_attempt`, `_own_loop_body`,
  `_release`, `_back_off` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B3: proposer, ownership, renewal and fairness hints`.

### Task 12: Owner core: permits O1-O8 at `DEPTH = 0`, abandoning a term

**Files:**
- Create: `src/protobase/cluster/owner.st`.
- Test: `tests/unit/sim_permits.st`.

**Interfaces:**
- Consumes: Tasks 9-11.
- Produces: `PBCoordinatorCore` owner methods: `permit_req(term, rid, inc)` handling; issue
  under O1 (queue not empty, term serving, at least a quarter of the belief left, else renew
  first; pipeline empty at `DEPTH = 0`); `permit(term, rid, seq, inc, root, certain, valid,
  after=nil)`; `permit_no` (reasons `not_owner`, `abandoned`, verbatim); O3 (a `committed` done
  retires the entry and its root becomes the committed base); O5 (a `none` from the only entry
  reuses the committed base); O6 (abandon on `unknown`, a done of another incarnation, no done
  by `valid + requestTimeout`, the lease expiring with a permission out); O7 (a retried request
  gets the same permit); O8 (the term ends only with an empty pipeline). Abandoning: suspect for
  the term, `permit_no` `abandoned` to the queue, release as uncertain. Holder side: the permit's
  `valid` measured from the send of `permit_req`; no answer within one `leaseDuration` forgets
  the owner **only for the term asked under** (plants `silence_forgets`, `hint_forgotten`);
  `acquireTimeout` settles the waiter with `PBTimeoutError`.
- Carried from Task 11 (proposer.st leaves these to this task): `_permission_from_owner` (a
  waiter asks the owner the hint names before it acquires), `_await_turn`'s `yield_to_owner`,
  the `acquireTimeout` deadline in `_awaitTurn:now:effects:` (`now >= deadline`) and in
  `_backOff:busy:now:effects:` (`min(…, remaining)`), and `_issue:now:effects:` (issues none in
  Task 11). Task 11 already hands the waiters that arrived while a lease had lapsed to the queue
  of a won renewal (`_closeRenewal:now:effects:`).
- Scenario families (`test_cluster_permit_backoff`, `_deferral`, `_incarnations`,
  `test_cluster_coordinator`): `first come first served, own threads included`, `a restarted
  holder's done never retires a permission it did not hold` (L12), `a dead holder's late done`
  (L29, O6), `minority side times out` (`PBTimeoutError`, no commit), `a faulty owner issuing
  one base twice` (R79, L28: plant `PlantBaseTwice`; the test asserts the checker **does**
  report S4, a strict expected failure as `proto_db` keeps it).

- [ ] **Step 1: write the failing test** `sim_permits.st` (`"EXPECT: ok 7"`: the five families,
  `PlantBaseTwice` inside its own, plus `PlantSilenceForgets` and `PlantHintForgotten` each
  failing the deferral family).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading CP "The owner's rules, O1 to O8" and `coordinator.py`
  `_dispatch`, `_permit_outcome`, `_abandon_term`.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B4: owner rules O1-O8 at depth 0, abandoned terms`.

### Task 13: Acceptance and the commit point

**Files:**
- Modify: `src/protobase/cluster/acceptor.st`, `src/protobase/cluster/owner.st`.
- Create: `src/protobase/cluster/holder.st` (replication side).
- Test: `tests/unit/sim_acceptance.st`.

**Interfaces:**
- Consumes: Tasks 9-12.
- Produces:
  - `acceptReplicate:in:now:`: accept when running, ballot rule (label not below
    `grantedTop`), `label == term`, root order not below the accepted root, V2' (log matching
    on `pred`), `seq` not below the highest accepted in the term, no sibling, copies rule (empty
    `copies` over shared storage); one synced `#accepted` append, `PBPublishAcceptor`, then
    `ack(ok, stored=false)`. A refusal is `ack(ok=false)`. Never an acceptance from a `store`
    (V1; `store` is ignored at DEPTH 0, CC7).
  - Holder: `PBReplicateWanted` (as built, `permission:root:pred:waiter:`: Task 13 adds the
    pred, the root the build started from; Task 14's commit path supplies it) → `replicate(...)`
    to every voter plus own acceptance (CC1);
    the commit point is a majority of voters' acks (holder included) observed within the
    permission; otherwise `unknown` once anything acceptable left, `none` if nothing did (H7).
    `done(term, seq, inc, outcome, root, copies, ranges)` broadcast; every member appends
    `#committed` (no sync) and `PBPublishCommitted` the higher root in root order.
  - `vs` mismatch on `replicate` dropped and counted (Review Focus 4).
- Scenario families (`test_cluster_acceptor_writes`, `_acceptor_durability`, `_durability`,
  `_chain_rule`, `_voters`): `ack only after the synced append` (crash between append and
  reply: the root is accepted, the reply lost); `power loss drops only unsynced committed
  knowledge`; `the old term's roots are refused after a promise` (ballot rule fences a paused
  holder: pause a holder's clock for 10 belief periods, it resumes and replicates, nothing it
  sends is accepted); `log matching refuses a root not built on the accepted chain`; `learners
  never count`; `vs mismatch` (a member configured with another voter set never helps a
  quorum); `release-carried certainty is never a commit point` (L8, the four certainty
  schedules of `test_cluster_root_certainty` as fixed schedules).
- Carried from Task 12 (review m3, m5): port `_learn_label` (`coordinator.py` 1684-1688): a
  known committed label at or above it clears the dispatcher's `suspectTerm` (set by
  `_abandon:why:now:effects:`) and the acceptor's `suspectTerm` (set at grant expiry, Task 10);
  until then every lease after an abandon stays uncertain. Port `_observe_committed` on a
  certain permit (`_permission_from_owner`: `if reply.root_certain: self._observe_committed(...)`):
  `receivedPermit:in:now:` hands the permit's root, certain, to the acceptor as committed
  knowledge (a `PBToAcceptor` learn-committed event), so that a holder that later owns sees its
  lease root committed (`_own:` reads `acceptorView committed`).

- [ ] **Step 1: write the failing test** `sim_acceptance.st` (`"EXPECT: ok 7"`, one check per
  family).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading CP 1.7 steps 7-10 and `coordinator.py`
  `_accept_replication`, `replicate`, `_on_done`.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B5: acceptance, the commit point and committed knowledge`.

### Task 14: Base choice

**Files:**
- Modify: `src/protobase/cluster/holder.st`.
- Test: `tests/unit/sim_base_choice.st`.

**Interfaces:**
- Consumes: Tasks 9-13.
- Produces: `PBCoordinatorCore >> leaseBase: aPermission in: aNodeState now: t` → effects
  ending in `PBSettle` of a `PBBaseDecision` (`base` `PBLabeledRoot`, `needsCommit` Boolean,
  `outcome` `#ok | #stale | #unreachable`), via, in order (CP 1.6, `_lease_base`):
  1. certain lease or permit: `lease.root`;
  2. uncertain: a recovery round (`query`, ballot 0) to the voters ending at a majority of
     witnesses (`recoveryDone:` — plant `recovery_waits_all`), or every voter when asked
     (`every`, plant `recovery_every_ignored`);
  3. `phase1Floor:` the higher of `lease.root` and the recovery result (R127; plant
     `c1_no_floor`);
  4. nothing known anywhere: refound from the persisted root, terms raised by `refoundStep`;
  5. stale base: `#stale` (the round requeues, the permission ends `unknown`);
  6. hard guard: never below the known committed root, else refound or `PBCorruptionError`
     naming `forceRejoin`;
  7. `needsCommit` when the base is not known committed (re-commit first, R50, `_commit_base`);
  8. a base whose SpaceRoot the shared storage cannot read: `#unreachable`, the term is
     abandoned (R133; plant `unreachable_base_none`). The simulator models it with a
     `PBSimDisk` unreadable-root fault.
- Scenario families (`test_cluster_recovery_base`, `_root_certainty`): the C1 schedule of CP
  725-780 (slow timer + delayed message) as a fixed schedule — an acknowledged R' is never
  dropped; I1 unreachable floor abandons the term; M6 `every` waits for the holder that knows the
  commit; refound only when nothing is known; seeds 1-200 under drops and clock skew.
- Carried from Task 12 (review m2): the strict form of R79/L28 (`proto_db` keeps it as an
  expected failure). Task 12's family 5 only shows its stand-in form, the checker's sibling-roots
  rule on two roots of one label and epoch. With the real replication and base choice, a faulty
  owner issuing one base twice (`PlantBaseTwice`) must let phase 1 rank the uncommitted sibling
  of a higher epoch above the commit, and the run must then fail S4 at convergence
  (`converge:`), with the sibling-roots rule disabled for that check.
- Carried from Task 13 (review m7), a **safety obligation**: acceptors trust the pred a
  `PBReplicateWanted permission:root:pred:waiter:` names (V2' compares it with their own accepted
  root and cannot detect a pred that lies about the build base). The commit path follows
  `proto_db`'s `lease.sent` rules (`replicate` 3622, 3725, 3873-3875): the pred of the first root
  under a permission is the permission's root (the base); the pred of each later root is the
  root last *sent* under that permission, even when its outcome was `#unknown`; a round that
  ended `#none` (nothing acceptable left) does not move it. The root is built on **exactly**
  that pred. A test pins it (a commit after an `#unknown` and after a `#none` round names the
  right pred), or the core keeps `sent` per permission in `PBHolder` and refuses a
  `PBReplicateWanted` whose pred differs (preferred: a wrong caller is refused, not trusted).

- [ ] **Step 1: write the failing test** `sim_base_choice.st` (`"EXPECT: ok 9"`: the five
  families, plus one check per plant `PlantRecoveryWaitsAll`, `PlantRecoveryEveryIgnored`,
  `PlantC1NoFloor`, `PlantUnreachableBaseNone` failing its schedule).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `transactions.py` `_lease_base`, `_phase_1_floor`,
  `_commit_base`, `_BaseUnreachable` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B6: base choice, recovery, phase-1 floor, refound, guards`.

### Task 15: The round state machine

**Files:**
- Modify: `src/protobase/cluster/holder.st`.
- Test: `tests/unit/sim_round_rules.st`.

**Interfaces:**
- Consumes: Tasks 9-14.
- Produces: `PBRoundState` (queue of `PBRoundEntry` (`token`, `willRetry`, `deadline`), current
  permission, built list, longest build µs, held flag, rounds under the permission) and
  `PBCoordinatorCore >> round: anEvent in: aRoundState now: t` → `PBStep`. Events:
  `PBRoundEnqueued entry:`, `PBPermitted permission:`, `PBBaseDecided decision:`,
  `PBBuilt entry: root: micros:`, `PBBuildConflict entry: error:`, `PBBuildFailed entry: error:`,
  `PBReplicated outcome:`, `PBHoldExpired`, `PBDropKept`. Effects: `PBAskPermit`,
  `PBAskBase permission:`, `PBBuild entry: base: stamp:` (stamp = `{term. epoch + 1}`),
  `PBReplicate permission: root:`, `PBSettle waiter: outcome:`, `PBReportDone permission:
  outcome:`, `PBTimer` (hold). Rules, in order:
  - one round at a time; a new round takes the whole queue;
  - `needsCommit`: re-commit the base first (one replicate of an unchanged root on top);
  - build each entry in turn on the previous root; a conflict fails alone; the group-size bound
    of CC11 before each build after the first (`groupBoundAllows:`);
  - before `PBReplicate`: reserve check R121 (`mayReplicate:`; plant `no_reserve`) and never
    below `rejoinBallot` (L14) — refusal is a conflict with the CC18 text, nothing sent;
  - outcomes (H7): `committed` → settle built entries true, report `committed`; `none` → retryable
    conflict; `unknown` → `PBOutcomeUnknownError` for every built entry, report `unknown`;
  - held retries (D-LIVE-2): a conflicted entry with `willRetry` gets `permitHeld` when the
    permission stays valid, not unknown, and rounds ≤ `permitRetries`; the permission is kept for
    `min(retryHold, remaining)` (a `PBTimer`); a commit enqueued meanwhile starts a round under it
    (plant `nokeep`); `PBDropKept` or the timer ends it with `done`.
- Scenario families (`test_cluster_transactions`, `_send_reserve`, `_fairness`, hot key):
  `hot-key read-modify-write on 3 nodes does not starve a member` (D-LIVE-2: every member
  commits at least once per 50 virtual rounds); `reserve refusal sends nothing and is
  retryable`; **`build longer than the belief`** (Review Focus 2: build of 700 ms virtual,
  every round refused, the conflict text contains `'leaseDuration'`, `'sendReserve'` and the
  build time); `the group bound leaves the rest queued and they commit next round`;
  `a stale base requeues and abandons the term`; `unknown is never retried`.

- [ ] **Step 1: write the failing test** `sim_round_rules.st` (`"EXPECT: ok 8"`: the six
  families, plus `PlantNoReserve` and `PlantNoKeep` each failing its family).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `_run_round`, `_permit_round`, `_hold_permission` at
  the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B7: the commit round as a pure state machine, held retries, group bound`.

### Task 16: Rejoin ballot, `forceRejoin`, confirmation flag

**Files:**
- Create: `src/protobase/cluster/rejoin.st`.
- Test: `tests/unit/sim_rejoin.st`.

**Interfaces:**
- Consumes: Tasks 9-15.
- Produces: `PBCoordinatorCore` rejoin methods (CP "A node that lost its disk"): a node whose
  log lacks kind 4 grants nothing, acknowledges nothing, answers `state=empty`; a plain round
  learns the highest term; decision `new` (every other voter answered, none accepted a root or
  reports a term: complete at once, R51), `rootless`, `witnesses` (at least `min(V - 1, V -
  majority + 1)` answered); ballot above everything reported, answered by `V - majority + 1`
  witnesses echoing it, re-asking up to `gatherAttempts`; then append promise, accepted root,
  rejoined marker, in that order. Records need no fetch over shared storage (they are in the
  directory); a root the storage cannot read leaves the node rejoining with
  `rejoin_blocked` in stats. `forceRejoin` (operator's decision; writes the marker after a
  plain round, as `force_rejoin()`). `needsConfirmation` true after every attach, cleared by
  the first permission round (L18). No code path waits for time (L13). The grant-state
  transitions are Task 8's: the witness promises a ballot with `PBGrantState promise:`
  (ending a lower grant: suspect for `endedTerm`), and the rejoining node adopts what it learnt
  with `restore:seen:` (the floor every term and label learnt, `seen` the promises only), so
  `termsSeen` stays 0 for a cluster's first start (R51).
  Task 10 carry-over: the start reaches the acceptor (`dispatchStartNode:in:now:` in core.st
  hands `PBStartNode` to `acceptStart:in:now:`), which marks a learner's or a lone voter's empty
  log and leaves a voter with other voters rejoining; the rejoin starts from that start step,
  and its own ballot query goes to `acceptQuery:in:now:` (which leaves `ballot` > 0 unanswered
  until this task).
- Scenario families (`test_cluster_rejoin`, `_rejoin_fresh`, `_rejoin_records`): the R78a
  schedule (wiped node's timer 1.3× fast) never loses an acknowledged commit, and the plant
  `PlantRejoinByWaiting` (waits `restartGrace` instead of the ballot) makes it fail; late first
  start; a rejoined node never replicates below its ballot (L14, plant); losing a majority of
  logs is detected as `PBCorruptionError` naming `forceRejoin`.

- [ ] **Step 1: write the failing test** `sim_rejoin.st` (`"EXPECT: ok 6"`: the four families,
  plus `PlantRejoinByWaiting` and `PlantReplicateBelowBallot` each failing its family).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `_rejoin_decision`, `_rejoin_answers`,
  `force_rejoin` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** CHANGELOG; commit `Cluster B8: rejoin ballot, forceRejoin, confirmation flag`.

### Task 17: Safety sweep: timer audit, checker self-tests, the lessons' plants

**Files:**
- Modify: `tests/unit/_plants.st`.
- Test: `tests/unit/sim_timer_audit.st`, `tests/unit/sim_checker_plants.st`,
  `tests/unit/sim_lessons.st`.

**Interfaces:**
- Consumes: Tasks 7-16, `PBClusterConfig timerTable`.

- [ ] **Step 1: write the tests.**
  - `sim_timer_audit.st` (`"EXPECT: timer audit ok"`): for each row of `timerTable`, run the mixed workload (3 and 5
    nodes, commits from every node, drops 5 %, one crash with disk kept) with the timer at
    1/10, 10× and skewed per node (rates 1/2 and 2), seeds 1-30 each; the checker passes every
    run (liveness may suffer, safety may not). Prints one line per timer.
  - `sim_checker_plants.st` (`"EXPECT: checker plants ok 8"`): the checker detects each workload plant of
    `plant_defects.py` that applies here, fed as a synthetic history: `lost`, `lost_token`,
    `fork`, `stray`, `split`, `blind_lost`, `check_lost`, an unknown commit resolved
    differently on one member.
  - `sim_lessons.st` (`"EXPECT: lessons ok 12"`): one schedule per lesson L1-L32 that has a protocol counterpart here
    (L5, L8, L12, L13, L14, L15, L16, L22, L24, L25, L28, L29), each with its plant from
    `_plants.st` failing and the product rules passing. The test prints the lesson numbers it
    covers; the others are named with the task that covers them or why they do not apply
    (L7, L23: Task 19/20; L30: Task 2; L31: not applicable, plants are subclasses).
- [ ] **Step 2:** run. Fail-first evidence here is each plant's failing run (record them in the
  commit body). A product run that FAILs is a core defect: fix it in the owning module with a
  scenario that reproduces it first, never by weakening the checker.
- [ ] **Step 3:** run the suite. Expected: all PASS.
- [ ] **Step 4:** commit `Cluster B9: timer audit, checker self-tests and the lessons' planted defects`.

### Task 18: Checklist audit against `proto_db`'s cluster tests

**Files:**
- Create: `tests/unit/cluster_checklist.tsv` (one row per test function of the 27
  `tests/unit/test_cluster_*.py` files at `v2.0.0rc3`: `file::function`, status `ported` with the
  protoBaseST test file and family, or `n/a` with the reason: tiered, `DEPTH = 1`, Python-only
  API), `tests/unit/cluster_checklist.sh`.

- [ ] **Step 1: write the failing test** `cluster_checklist.sh`: lists the test functions at the
  tag (`git -C "$PROTOBASE_REPO" show v2.0.0rc3:<file> | grep -E '^def test_|^    def test_'`),
  fails on any function without a row, any row naming a missing protoBaseST file, or any
  `ported` row whose family name does not appear in that file; prints the counts
  (`ported N, n/a M`). Without the checkout: `SKIP: no ProtoBase checkout`.
- [ ] **Step 2:** run. Expected: FAIL (rows missing).
- [ ] **Step 3:** fill the table. A function that should be `ported` and is not gets its family
  added to the owning Phase B test, fail-first.
- [ ] **Step 4:** run, then the suite. Expected: PASS, with 261 rows.
- [ ] **Step 5:** commit `Cluster B10: checklist of proto_db's 261 cluster tests, each ported or justified`.

---

## Phase C: integration over a shared `PBFileStorage` (spec 8.1 T13-T19)

### Task 19: Transport: in-process and TCP

**Files:**
- Create: `src/protobase/cluster/transport.st`.
- Test: `tests/unit/cluster_transport_inprocess.st`, `tests/unit/cluster_transport_tcp.st`.

**Interfaces:**
- Consumes: Tasks 5-7.
- Produces (one protocol, two implementations):
  - `start: aNodeId peers: aMembership key: aKeyOrNil handler: aBlock` (the block receives each
    valid `PBClusterMessage`), `send: aMessage to: aNodeId` (never blocks the caller), `stop`,
    `stats` (`frames_sent`, `frames_dropped`, `frames_rejected`, `connections_dropped`).
  - `PBInProcessNetwork new`, `endpoint` → `PBInProcessTransport`: encodes and decodes every
    frame (`PBClusterFrame`), so the codec runs; one-way semantics kept.
  - `PBTcpTransport class >> listenOn: aPort host: aHost` and `withListener: aServerSocket`
    (for tests that publish ports first). Listener actor (high band) accepts and spawns one
    reader actor per connection; a reader loops `_readExactly: n from: aSocket` (loops on short
    reads until `n` bytes or end, Task 1), checks `lengthFrom:` before reading the body, and on
    any `PBClusterProtocolError` closes the connection (CC5). One sender actor per peer (L7) with
    an immutable queue value in an `Atom`, connect on demand with `requestTimeout`, a write
    failure drops the message and reconnects after a jittered back-off; control lane only.
    The sender's queue is bounded in bytes (`MAX_FRAME_BYTES`); overflow drops the oldest and
    counts it.
- **Checklist (Task 18):** turn the 12 `deferred 19` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==19' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing tests.**
  - `cluster_transport_inprocess.st` (`"EXPECT: ok 4"`): a message from `n0` to `n1` arrives
    decoded; replies travel on the replier's own link; a keyed endpoint and an unkeyed one drop
    each other's frames (`frames_rejected` 1 each); `stop` delivers nothing more.
  - `cluster_transport_tcp.st` (`"EXPECT: ok 6"`): three transports on `127.0.0.1` port 0
    (published through `withListener:`) exchange 100 messages each, all delivered (counted
    through an `Atom`, waited for with a generous deadline that turns a hang into a failure,
    never asserted as a duration); a raw socket writing `message-not-a-map.bin` is
    disconnected and the next valid frame on a new connection arrives; an oversized length
    is disconnected without reading the body; a peer that accepts and never reads
    (black hole) does not stop the 100 messages to the live peer (L7); two different keys:
    nothing delivered, `frames_rejected` > 0 (Review Focus 4).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `transport.py` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster C1: in-process and TCP transports`.

### Task 19b: Port proto_db R149/R149a (renewal back-off and fenced term) into the core

Added 2026-11-15. `proto_db` adopted gamarino/ProtoDB#1 after rc3: merge commit `88ca21d`
(branch `fix/renew-backoff`, R149/R149a, CHANGELOG 2.0.0rc4, D50 amendment). The port follows
`proto_db`, so the core takes the change before the shell gives it real timers. This settles
Task 20 carry-over (f).

**Files:** modify `src/protobase/cluster/proposer.st` (and `lease.st` if the per-peer refusal
record needs it); tests: a new `tests/unit/cluster_renew_backoff_rules.st` porting
`tests/unit/test_cluster_renew_backoff.py` at `88ca21d`, and plants that follow
`tests/support/plant_defects.py` at `88ca21d`.

- Fenced term (R149): a refusal is permanent when its reason is `stale_term` or `term_taken`,
  or it carries `highest > own.term`. When the permanent refusals exceed `size - needed`, the
  owner stops renewing and issues no new permit, refuses the queue with `"ending"`, lets the
  outstanding permit end by its done or its deadline, then ends the ownership with reason
  `"fenced"` and releases; a stat counts fenced terms. A retry of the outstanding permit request
  (same sender, inc, rid, term) gets the same permit again.
- Back-off (R149a): every renewal round that is neither won nor fenced, including a round left
  pending after a majority answered, sets `renewAfter = now + min(remaining, max(busyRemaining,
  requestTimeout / 4, 1 ms))`; the ownership loop does not renew before it and schedules a timer
  for it; a won renewal clears it.
- Tests are fail-first, on virtual time only. Every new guard is mutation-pinned. Re-run the
  simulator families of Task 16 whose cost came from the storm (`_rejoin.st` r78a, `lagged:`,
  belowBallot, majorityLoss), and each sim test whose code path changed. Do not run the whole
  suite or the audit (Task 30). Audit floors that this change moves are re-measured in Task 30.
- `docs/deviations.md`: replace the open-item entry for ProtoDB#1 with "adopted from proto_db
  `88ca21d` (post-rc3, R149/R149a)". The Task 18 checklist stays pinned to `v2.0.0rc3`; list the
  ported `test_cluster_renew_backoff.py` functions in the report.
- Commit `Cluster C1b: renewal back-off and fenced term (proto_db R149/R149a)`.

### Task 20: Coordinator shell: actors, timers, effects, fencing, stats

**Files:**
- Create: `src/protobase/cluster/coordinator.st`.
- Test: `tests/unit/cluster_coordinator_shell.st`.

**Interfaces:**
- Consumes: Tasks 7-19.
- Produces:
  - `PBClusterCoordinator class >> nodeId: anId peers: anArray options: aDictionary`;
    `start` (opens nothing until a tier is attached: `_attach: aTier`), `stop`, `stats`
    **Task 10 carry-overs:** (a) before a tier is attached, a request is answered with a
    `reject` `no_storage` (counted `grants_refused_no_storage`) and a plain query with `state`
    `unknown`, as proto_db (`_refusal`, `_witness_state`); the core has no acceptor state then,
    so the shell (or a detached acceptor state this task adds) answers them. (b) A re-attach of
    a running node (proto_db `_attach_locked` 1113-1121) keeps the lease activity (`grants`:
    promises, terms seen, the grant running; `suspectTerm`) and takes `log`, `loggedPromise`,
    `accepted`, `committed`, `rejoined` and `tierFailed` from the **new** log: `loggedPromise`
    belongs to the log it was written to (`PBAcceptorState >> log`, proto_db
    `_logged_promise[0] is tier`), so a renewal over the new log writes its promise again (L17).
    (c) The acceptor shell discards a step whose append fails (keeps the state before it) and
    hands the acceptor `PBAppendFailed`. (d) A fenced node sends nothing (proto_db `_enqueue`
    drops lane messages once fenced; replicate and store get `ack(ok=false)`, Task 13): the
    acceptor drops request, renew and release when `fenced`; the dispatcher's fence is this
    task's. (e) `PBCount` effects (`config_mismatches`, `grants_given`) feed `stats` (CC24).
    (f) **Settled by Task 19b** (2026-11-15): `proto_db` adopted the fix upstream (`88ca21d`,
    R149/R149a), and the core follows it; nothing is left for this task. The original item:
    Carried from Task 13 (review m1, open item; Task 16 review m5): after a renewal lost
    to a majority that rejects at once (a rejoin ballot that a majority promised under a live
    holder, the most common trigger since Task 16: every disk-loss rejoin; members restarted
    inside their startup grace; or a newer term granted),
    the owner renews again immediately, as `proto_db`'s `_own_loop_body`/`_renew` do: one round
    per RTT until the lease ends (at most belief / 2), messages and acceptor-lane work only, no
    log write, safety unaffected. Decide here, with real timers and RTTs: keep `proto_db`'s
    behaviour, adopt a lost-renewal back-off as a recorded timing-only deviation (for example
    wait min(requestTimeout, remaining - belief / 4) before the next attempt), or propose it to
    `proto_db` upstream (preferred, since the behaviour is `proto_db`'s; proposed as
    gamarino/ProtoDB#1); record the decision in
    docs/deviations.md. Its cost so far: the simulator families of Task 16 cut the holder off
    before its timer resumes (`tests/unit/_rejoin.st` r78a) or run with 1 ms links (`lagged:`,
    belowBallot and majorityLoss), or the storm makes the run intractable; Tasks 17-19 will need
    the same, and if they need more, bring this decision forward. (g) Carried from Task 13 (review note): `stop` settles a replication in
    flight (`PBHolder replications`) `#unknown`, never `#none` (the root left the node;
    `proto_db` `replicate` 3895-3897). (h) Carried from Task 15 (review note, R148): the commit
    round's `_endPermission:` emits `PBReportDone` and then, when commits are queued,
    `PBAskPermit` in the same step; the shell performs them in order and issues that permit only
    once the done has freed the node's write permission, or it reproduces `proto_db`'s pre-R148
    "already holds a write permission" misuse error. (i) Carried from Task 15: the round runner
    sets each `PBRoundEntry`'s `caller` to its client (`proto_db` `entry.thread`) and sends
    `PBDropKept caller:` when a held caller will not retry (`Database.run` returned or raised).
    (j) Carried from Task 15 (re-review): the round is never driven synchronously from inside a
    held caller's own thread (its fn or its wait): the round runner is its own actor, so a kept
    permission waiting for that caller's retry never waits on the thread that must make it
    (`proto_db` excludes the runner's own thread from `held` for this reason).
    (k) Carried from Task 16 (review I1): the shell hands the dispatcher `PBLogDetached` when the
    tier is detached (proto_db `detach`, coordinator.py 1621-1650: `_rejoining` and
    `_rejoin_forced` dropped), and a re-attach reports an acceptor state over the new log; the
    core then drops the rejoin (`rejoinDetached:`, and `rejoinCheck:now:effects:` starts a fresh
    one when the reported log is not the one the rejoin ran on), so a forced rejoin never
    outlives the log it was forced for and a failed rejoin restarts over a replaced tier. The
    check is by identity (`r log == view log`, and `PBRejoinLearnt log` against the acceptor's
    log at the adoption): the shell must hand the dispatcher the acceptor's own
    `PBAcceptorState`, whose `log` object stays the same across every report of one attach, and
    build a new `PBLoggedRoots` only at an attach (a rebuilt one would drop a legitimate rejoin;
    conservative, but the operator would have to force again). Test:
    proto_db's `test_c2_audit_a_forced_rejoin_does_not_outlive_the_log_it_was_forced_for` over
    the shell (forceRejoin, detach before completion, re-attach over a new empty log: the new
    rejoin is not forced).
    Also from Task 16's second re-review: (m10) `PBLogDetached` must carry the detached log
    (the shell knows it), and the `#detached` marker takes its log from the event, not from
    the dispatcher's view. Otherwise a detach that arrives before that log's first report
    leaves the marker without a log. A late old-log report then starts a rejoin bound to the
    old log, which is safe because its adoption is refused, but the new log's first report
    drops it together with an operator's forced flag. Pin it with a rules check: detach
    before the first report, then a late old-log report, then the new log's report must keep
    a forced flag set while detached. (N4) Build a fresh `PBLoggedRoots` at every attach, even
    over the same disk. Re-attaching the very same object would leave the `#detached` marker
    in place forever, so the node would never rejoin.
    (CC24), `forceRejoin`, `committedRoot` (`PBLabeledRoot` from an `Atom`, never a message),
    `committedEpoch`, `needsConfirmation`, `isFenced`, `nodeId`, `config`.
  - For the round runner (all answer `Future`s, never wait): `_permit` → `PBPermission`
    (or rejected `PBTimeoutError`); `_baseFor: aPermission` → `PBBaseDecision`;
    `_replicate: aLabeledRoot under: aPermission` → `#committed | #none | #unknown`;
    `_done: aPermission outcome: aSymbol`; `_confirmed`.
  - Actors: `_PBDispatcher` (high; `PBNodeState` in an `Atom`; runs `dispatch:in:now:`;
    performs `PBSend`, `PBTimer` via `(Future after: µs // 1000) thenDo:` sending
    `PBTimerFired` back, `PBSettle`, `PBPublishCommitted`); `_PBAcceptor` (high; holds
    `PBAcceptorState` and the tier's log; runs `accept:in:now:`, performs the appends in order,
    then publishes its state to an `Atom`, then sends the reply effects: the atomic acceptor
    step, CC2). An exception escaping either actor fences the node for the life of the process
    (`PBFence`): every later grant, ack and permit is refused and commits get
    `PBUnexpectedError` naming the cause. A failed log append sets `tierFailed` (R57): the
    node refuses every grant and acceptance until it is restarted on a healthy disk.
  - The incarnation `inc` is drawn at `start` from `ByteArray randomBytes: 8` masked to 62
    bits (the `#seed` option seeds a `Random` instead, for tests). `_attach:` refuses a
    `#startupGrace` shorter than the default when the loaded log is not empty (L17,
    `PBValidationError`).
- Carried from Task 19 (review m7, report concerns):
  - (a) `PBTcpTransport` calls the handler on the reader actor of each inbound connection, so on
    several threads at once: the handler only forwards each message to the dispatcher actor
    (spec 5.4), which keeps the order per connection.
  - (b) Drop and count a message whose `from` is not a peer, or is the node itself
    (`coordinator.py` 1771, `_on_message`): the transport cannot check the sender (connections
    are one-way and the HMAC binds the receiver, CC4).
  - (c) `tests/unit/sim_harness.st` check 12 bans clock reads in `src/protobase/cluster/*.st`
    except the shells it exempts by name (now `transport.st`, each checked to exist): add
    `coordinator.st`, and later `round.st`, the persister and the tier if they read a clock or
    use `Future after:`.
  - (d) `stop` of a transport answers a `Future`; the coordinator's stop chains on it and never
    waits inside an actor. Pass `requestTimeout` (milliseconds) to `PBTcpTransport ...
    requestTimeout:`, or keep its default of 1000 ms, `proto_db`'s.
  - (e) A sender blocked in a connect is not woken by `stop`: stop settles at most
    `requestTimeout` later.
  - (f) A handler error that is not a `PBDBError` ends that connection's reader, which closes
    the connection and loses the frames behind it: the coordinator's handler must not signal.
  - (g) `PBInProcessNetwork` has no delays: a `proto_db` test that uses `set_faults(delay=)` or
    `set_link_delay` is ported to the simulator (`PBSimFaults delay:reorder:`, `delay:to:by:`),
    or uses real timers only through a condition with a generous deadline.
- **Checklist (Task 18):** turn the 22 `deferred 20` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==20' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing test** `cluster_coordinator_shell.st` (`"EXPECT: ok 10"`): three
  coordinators over `PBInProcessNetwork` and a memory tier test double (test file only) elect an
  owner and issue a permit (outcomes only); `committedRoot` follows a `done`; a test subclass of
  `_PBAcceptor` whose append raises fences its node, and that node's `_permit` is rejected with
  `PBUnexpectedError`; the reply of an acceptance is sent after the append (the double records
  the order); a double whose append fails puts its node in tier-failed state, which refuses
  grants (`stats` shows it) while the other two still commit; `#startupGrace: 1` with a
  non-empty log is refused at `_attach:`; `stop` settles every pending Future (rejected
  `PBClosedError`); `stats` holds `grants_given` and `permits_issued`.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference (`PBClusterCoordinator`), CHANGELOG; commit `Cluster C2: coordinator shell, dispatcher and acceptor actors, fencing`.

### Task 21: The shared tier and the cluster storage mode

**Files:**
- Create: `src/protobase/cluster/tier.st`.
- Modify: `src/protobase/store.st` (`clusterPath:`, CC20), `src/protobase/space.st`
  (`storage:coordinator:` and `storage:coordinator:lockTimeout:`; `_spaceRootAt:` accepts
  cluster roots when a coordinator is attached), `tests/unit/store_cluster_refusal.st`
  (plain `path:` still refuses).
- Test: `tests/unit/cluster_tier.st`.

**Interfaces:**
- Consumes: Tasks 3, 4, 20.
- Produces:
  - `PBFileStorage class >> clusterPath: aPath` (and `clusterPath:segmentMaxBytes:`);
    `isClusterMode`. In cluster mode `replaceRoot:` requires a SpaceRoot with `cluster_term`
    (`PBValidationError` otherwise) and does not refuse `cluster/`; every other check stays.
  - `PBSharedTier class >> storage: aClusterStorage nodeId: anId` → creates `cluster/` (synced
    with its parent), opens `PBAcceptorLog path: 'cluster/' , (self logName: anId) , '.roots'`;
    refuses a log holding kinds 5/6 (CC15). `PBSharedTier class >> logName: anId` (CC21).
    `flushLocal` (`storage flushSegment`), `logAccepted: aLabeledRoot` and `logCommitted:
    aLabeledRoot` (unpacked for the log: `append: #accepted label: r label root: r record`, the
    record a `PBRootRecord` or nil; `PBAcceptorLog` never takes a `PBLabeledRoot`), `logPromise:`,
    `logRejoined` (every write from the one actor that owns the log: `PBAcceptorLog` is not
    serialized), `loadRoots`, `readPersisted` → `PBLabeledRoot` (label and cluster epoch from
    the SpaceRoot's fields; label 0 and the storage epoch for a plain root), `persist:
    aLabeledRoot` → `true | false | #busy` (CC19), `canRead: aLabeledRoot`, `close`.
  - `PBObjectSpace class >> storage: aClusterStorage coordinator: aCoordinator`: refuses a
    storage not in cluster mode and the reverse (`PBObjectSpace storage:` of a cluster-mode
    storage); attaches `PBSharedTier storage:nodeId:` to the coordinator; `coordinator`.
- **Checklist (Task 18):** turn the 2 `deferred 21` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==21' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing test** `cluster_tier.st` (`"EXPECT: ok 13"`): log names
  `'n0'` → `n0.roots`, `'nœud'` → hex of its UTF-8, `'a/b'` → hex, `'..'` → `...roots`
  inside `cluster/`, 65 characters → hex (Review Focus 5); a second
  `PBSharedTier storage:nodeId: 'n0'` on the same directory is `PBUserError` containing
  `'n0.roots.lock'` (Review Focus 3); `persist:` writes a cluster root, refuses to go backwards
  (answers false), answers `#busy` while a test holds `space.lock`; `readPersisted` of a plain
  space is label 0; `PBObjectSpace storage: (PBFileStorage clusterPath: d)` refused;
  `PBObjectSpace storage: (PBFileStorage path: d) coordinator: c` refused; a log with a kind-5
  entry refused.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `persister.py:97-245` at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster C3: shared tier, cluster storage mode, per-node acceptor logs`.

### Task 22: Round runner shell and standalone group commit (D52)

**Files:**
- Create: `src/protobase/round.st` (`PBRoundRunner`, `PBCommitEntry`).
- Modify: `src/protobase/publisher.st` (`publishGroup:`; module comment), `src/protobase/space.st`
  (the runner replaces the publisher proxy and `_untilPublished:`), `src/protobase/transactions.st`
  (`commit` enqueues and waits on its Future; `_buildOn:` unchanged), `docs/deviations.md`
  (group commit implemented; the lock backoff no longer blocks the caller's worker, CC10),
  `docs/reference.md` (`PBPublisher`, commit paragraph).
- Test: `tests/unit/round_group_commit.st`, `tests/unit/round_lock_retry.st`.

**Interfaces:**
- Produces:
  - `PBCommitEntry class >> transaction: aTx willRetry: aBoolean deadline: µs` and
    `createDatabase: aName deadline: µs`; `future`.
  - `PBRoundRunner class >> space: aSpace` (actor, medium band); `enqueue: anEntry` → the
    entry's Future; standalone rounds: one at a time; the round takes the whole queue and calls
    `PBPublisher >> publishGroup: entries` → `#locked` or one result per entry. `#locked`
    reschedules with `Future after:` (1 ms doubling to 50 ms), settling each entry whose
    deadline passed with `PBTimeoutError` (`lockTimeout`'s message unchanged).
  - `PBPublisher >> publishGroup: entries`: atoms of every entry saved first (step 0), lock
    once, read root once, build each entry on the previous root (`_buildOn:` of the record the
    previous build saved), a build error fails that entry alone, one `flushSegment`, one
    `replaceRoot:` with epoch + 1, step 8 outcome rule applied to the round; a failure of the
    flush, the publish or the lock reaches every built entry; a lone entry runs exactly the
    single-commit protocol (D52).
- **Carried from Task 20 (review I4; origin Task 15 re-review, carry-over (j) of Task 20):**
  `PBRoundRunner` is its own actor, and no round is ever driven synchronously from inside a
  caller's own thread (its fn or its wait): `enqueue:` only adds the entry and answers its
  Future, so a kept permission waiting for a held caller's retry never waits on the thread that
  must make it (`proto_db` excludes the runner's own thread from `held` for this reason). The
  source scan of Step 1 covers it: no method reachable from `enqueue:` calls `wait`.
- **Checklist (Task 18):** no row of `tests/unit/cluster_checklist.tsv` is deferred to this task (0 rows); a row this task ports is turned into `ported`, and none is deferred to it.
- [ ] **Step 1: write the failing tests.** `round_group_commit.st` (`"EXPECT: ok 5"`): 20
  transactions committed from 20 actors all succeed, the history holds 20 versions, the storage
  epoch advanced by fewer than 20 (counted through a seam subclass counting `replaceRoot:`
  calls: fewer calls than commits); a conflicting member of a group fails alone with
  `PBConflictError`; a seam storage failing the publish gives every built entry the outcome
  of step 8. `round_lock_retry.st` (`"EXPECT: ok 2"`): with `space.lock` held by a peer process
  (`tests/interop/hold_lock.py` pattern: never released while protoST waits) and
  `lockTimeout: 50`, the commit ends `PBTimeoutError`; no actor method of the runner calls
  `wait` (a source scan of `round.st`).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading D52 and `_standalone_round` at the tag.
- [ ] **Step 4:** run the whole suite, `tests/unit/bytes_pinned.st` and
  `tests/interop/concurrency.sh` included. Expected: all PASS (bytes unchanged).
- [ ] **Step 5:** CHANGELOG; commit `Cluster C4: group commit on a standalone storage (D52) with the shared round runner`.

### Task 22a: proto_db rc4 baseline (format 4, protocol 14)

Added 2026-11-15 after proto_db 2.0.0rc4 (8e6127f). The maintainer's ruling: do the minimum now, as
proto_db does when the registry is unused. Keep writing format 4, refuse format 5 cleanly, and give the
full registry (D62) its own plan after this branch merges. The authority is
`docs/superpowers/specs/2026-11-15-rc4-delta.md`, items by id.

**Files:** the Task 5 wire files (`protocol.st` and peers), `framing.st`, `types.st` (registry),
`transactions.st`, `object.st`, `tests/conformance/*`, `tests/interop/setup_venv.sh`,
`tests/unit/cluster_checklist.tsv`, `cluster_checklist.sh`, docs.

- [x] W1, W2, W4: PROTOCOL_VERSION 14, the optional `unknown` reply field on `fetched` and
  `commit_info` (read and carried; the port never sends a peer fetch, so it never sets it), the
  five-item root, and log format 3 refused with `PBNotSupportedError`.
- [x] F5: type aliases 22 `proto_db.registry.ModuleList` and 23 `proto_db.registry.Catalog`, with
  no class (`builtinCount` 24).
- [x] F6: refuse creating fields named `parents` or `with_parents`; a stored field of either name
  still loads, reads and carries over (R157).
- [x] S1: `removeRootObject:` refuses `__` names.
- [x] F7: re-vendor the rc4 vectors. `_vectors.st` learns the `segments` list, and
  `parents_database`, `registry_database` and `roots_log_v5` become expected
  `PBNotSupportedError`. The F4 check: a version-5 segment header is refused before any record
  decode, so a four-key envelope never reaches `framing.st:375`.
- [x] T1: re-pin the checklist to rc4 (298 rows, per the delta doc's classification). T3: bump
  the venv to rc4.
- [x] Docs: C5 and C6 (spec normative tag rc4, deviations: format 5 refused, registry not
  supported).
- Tests: the conformance and interop files touched, `bytes_pinned`, the checklist both with and
  without `PROTOBASE_REPO`, and the wire unit tests. Not the whole suite.
- Commit `rc4 baseline: protocol 14, format 5 refused, aliases 22-23, vectors at rc4`.

### Task 22b: Core follow-up for rc4 C3 (R212, R231, R233)

A base read that fails with exactly `PBUnexpectedError` after the write permission expired, with
nothing sent and the tier not failed, gives a retryable `PBConflictError`. A failed read of the
base a round must first re-commit is "nothing sent", so outcome `#none` and not unknown. This changes
`roundBuildFailed:in:now:` (`holder.st`, Task 15). The six rc4 plants and their sim cases come
first and fail first. Tests: `sim_round_rules.st` families and the new checks only. The shell half
(the tier's failed flag into `PBBuildFailed`) and the C1 timeout text land in Task 23.

### Task 23: Cluster commits

**Files:**
- Create: `src/protobase/cluster/round.st` (`PBClusterRound`: performs `PBCoordinatorCore >>
  round:in:now:` effects).
- Modify: `src/protobase/round.st` (a runner with a coordinator delegates to `PBClusterRound`),
  `src/protobase/errors.st` (`PBConflictError class >> heldSignal:`, `permitHeld`),
  `src/protobase/transactions.st` (`run:` passes `willRetry`, retries at once when `permitHeld`
  and counts it as an attempt, sends `_dropKept` when it will not retry, as `Database.run`),
  `tests/unit/_ivar_allowlist.txt` (the `PBConflictError` initialiser).
- Test: `tests/unit/cluster_commit_path.st`, `tests/unit/cluster_close_inflight.st`.

**Interfaces:**
- Consumes: Tasks 15, 20-22.
- Produces: in cluster mode, `commit` enqueues; written atoms saved before the permission; each
  `PBBuild` runs `_buildOn:` and saves `PBSpaceRoot databases:term:epoch:previous:`; before
  `PBReplicate`, `tier flushLocal` (records synced in the shared storage before anything
  acceptable leaves, L11); build durations measured with `Time microsecondClockValue` feed the
  group bound and `stats` (`critical_commits`, build µs, replication µs). Each
  `PBCommitEntry` enters the core as a `PBRoundEntry` whose `token` is the entry itself;
  `PBSettle` effects settle the entry's Future.
- **Carried from Task 20 (review I4):**
  - (h), the runner's half (Task 15 review note, R148): `_endPermission:` emits `PBReportDone`
    and then, when commits are queued, `PBAskPermit` in the same step; `PBClusterRound` performs
    the effects of a step in their order and sends both into the one dispatcher mailbox
    (`PBClusterCoordinator >> _done:outcome:root:`, then `_permit`), never the permit first nor
    from another actor, so the permit is issued only once the done has freed the node's write
    permission (the coordinator's half, mailbox FIFO, is `cluster_coordinator_attach.st`
    check 4); otherwise it reproduces `proto_db`'s pre-R148 "already holds a write permission"
    misuse error.
  - (i) (Task 15 review): the runner sets each `PBRoundEntry`'s `caller` to its client
    (`proto_db` `entry.thread`) and sends `PBDropKept caller:` naming that client when a held
    caller will not retry (`run:` returned or raised: `_dropKept`).
  - (j) (Task 15 re-review): a round is never driven from a held caller's thread; the runner is
    Task 22's actor (see Task 22).
  - The shell's outcomes the round maps (Task 20): `_replicate:under:` answers `#committed`,
    `#none` (nothing sent: the permission ended, the send reserve, or a term below the rejoin
    ballot, L14) or `#unknown`, and is rejected with `PBCorruptionError` for a protocol violation
    (x4, ported in Task 20: never an unknown outcome), `PBValidationError` for a root not built
    for its permission, `PBUnexpectedError` once fenced and `PBClosedError` once stopped.
- **Checklist (Task 18):** turn the 9 `deferred 23` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==23' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing tests.**
  - `cluster_commit_path.st` (`"EXPECT: ok 5"`): three in-process nodes over one directory;
    100 `run:` increments from all nodes give 100; commits from every node appear in every
    node's `committedRoot`; a hot-key workload marks some conflicts `permitHeld` and every
    `run:` finishes; the segment holds the records before the first `#accepted` entry (seam
    storage records the order of `flushSegment` and `replicate`); a build seam taking longer
    than the belief gives, after `run:`'s retries, `PBConflictError` containing
    `'leaseDuration'` (Review Focus 2).
  - `cluster_close_inflight.st` (`"EXPECT: ok 4"`, Review Focus 1): with seams that stop a
    round before the build, after the build and after the replicate leaves, `space close`
    gives `PBClosedError`, `PBClosedError` and `PBOutcomeUnknownError` respectively; nothing
    hangs (each wait has a generous deadline turning a hang into a failure); after restart the
    unknown commit is present on every node or on none.
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference (commit in cluster mode, `permitHeld`), tutorial chapter stub
  deferred to Task 29, CHANGELOG; commit `Cluster C5: commits through the coordinator, held retries in run:`.

### Task 24: Reads in cluster mode

**Files:**
- Modify: `src/protobase/space.st` (`_snapshotRecord` reads the coordinator's committed root,
  the persisted root when none is known; confirmation commit before the first snapshot after
  attach and before any snapshot while `needsConfirmation` holds; `committedEpoch`;
  `newDatabase:` through the round runner).
- Carried from Task 16 (review I2): `proto_db`'s `_read_storage_root` (transactions.py
  1556-1575) checks `needs_confirmation` on **every** snapshot, not only after attach, so
  `forceRejoin` on a survivor (which sets it again, `PBForceRejoin`) is followed by a
  confirmation before the next snapshot. The readers' committed root must follow the acceptor
  when it drops one: `PBPublishCommitted` cannot carry nil, so either the publish carries the
  acceptor's committed knowledge (nil included) or the space reads the coordinator's current
  root, as `proto_db`'s `current_root()`.
- Test: `tests/unit/cluster_reads.st`.

**Interfaces:**
- Produces: `PBObjectSpace >> committedEpoch`; the confirmation commit (a permission round with
  no entry, through `PBRoundRunner`); a failure of it is logged and reads start from the logged
  committed root (as `_read_storage_root`).
- **Checklist (Task 18):** turn the 5 `deferred 24` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==24' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing test** `cluster_reads.st` (`"EXPECT: ok 4"`): a node that
  restarts reads at or above its last committed root before any commit of its own (L18); a
  snapshot never goes backwards across ten restarts; `newDatabase:` on one node is visible on
  the others after a barrier commit (`run:` writing `'_read_barrier'`, CC9); `committedEpoch`
  is monotonic; and (Task 16, I2) after a majority loss and `forceRejoin` on the survivor, the
  survivor's next snapshot does not start from the dropped committed root R (the confirmation
  runs first, and the readers' root is no longer R).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster C6: snapshots from the committed root, confirmation commit`.

### Task 25: Persister and `sync:`

**Files:**
- Create: `src/protobase/cluster/persister.st` (`PBPersister`, low band).
- Modify: `src/protobase/space.st` (`persistedEpoch`, `sync: ms`).
- Test: `tests/unit/cluster_persister.st`.

**Interfaces:**
- Produces: `PBPersister class >> tier: aTier coordinator: aCoordinator` (actor): every
  `persistInterval`, persists the newest committed root when this node committed it, or any
  node's after `persistLag`; never backwards (CC19); `#busy` reschedules. `persistedEpoch`;
  `PBObjectSpace >> sync: milliseconds` → nil once the persisted epoch reaches the committed
  epoch, `PBTimeoutError` after `milliseconds` (a durability barrier, not a visibility
  barrier). Never on the commit path.
- **Carry-over from Task 21 review (I1): one writer per storage.** The persister and the commit
  round write the node's one `PBFileStorage`, which takes no lock to serialise its writes
  (`_writeOperation:` refuses an overlapping one with `PBUserError`, and the root lock is per
  storage object, not re-entrant). Run side by side, they fail in two ways that `#busy` cannot
  absorb: (1) `persist:` while the node's own storage holds the root lock (a commit's
  publish, or the reverse) makes `tryLockRoot` signal `PBLockingError` ('not re-entrant', or
  'another tryLockRoot of this storage ran at the same time') instead of answering false;
  (2) `persist:`'s `ensure: [storage unlockRoot]` running while the commit path's `pushAtom:`
  (or `flushSegment`) is a write in progress is refused (logged, 'the root lock is kept'), so
  the root lock stays held by this storage for good: every later `persist:` on the node
  signals `PBLockingError`, every other node's answers `#busy` forever, `space.root` never
  advances and `sync:` times out. Required fix: every storage write of the persister
  (`persist:`, `flushLocal`) goes through the same actor as the commit round's writes on the
  node (for example the space's publisher, which then calls the tier), so `tryLockRoot`,
  `replaceRoot:` and `unlockRoot` never overlap a `pushAtom:` or `flushSegment` of the same
  storage. Treating the refusal as `#busy` is not enough (failure 2). Test (in
  `cluster_persister.st`): a commit and a persist run together on one node, with the overlap
  forced by a seam (a gated storage write, such as a gated `pushAtom:` or `replaceRoot:` that
  the test releases), never by a timing race, then
  `holdsRootLock` is false and a later `persist:` succeeds.
- **Checklist (Task 18):** turn the 8 `deferred 25` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==25' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the failing test** `cluster_persister.st` (`"EXPECT: ok 4"`): after commits
  and `sync: 10000`, `space.root` holds a cluster root whose epoch equals `committedEpoch`;
  a test that persists a higher root first sees the persister refuse to go back; `sync:` with
  the lock held by a peer ends `PBTimeoutError`; a stopped node's commits are persisted by
  another after `persistLag` (outcome only).
- [ ] **Step 2:** run. Expected: FAIL.
- [ ] **Step 3:** implement after reading `Persister` (`persister.py:255-493`) at the tag.
- [ ] **Step 4:** run, then the suite. Expected: PASS.
- [ ] **Step 5:** reference, CHANGELOG; commit `Cluster C7: the persister, persistedEpoch and sync:`.

### Task 26: Format interop with `proto_db`

**Files:**
- Create: `tests/interop/cluster_space_to_py.sh`, `tests/interop/_st_cluster_space.st`,
  `tests/interop/py_rootlog.py`, `tests/interop/rootlog_both_ways.sh`.

- **Checklist (Task 18):** no row of `tests/unit/cluster_checklist.tsv` is deferred to this task (0 rows); a row this task ports is turned into `ported`, and none is deferred to it.
- [ ] **Step 1: write the tests.**
  - `cluster_space_to_py.sh`: `_st_cluster_space.st` runs three in-process nodes on one
    directory, commits the ERP-shaped workload of `_st_write_space.st`, `sync:`s and stops;
    `py_verify.py` accepts the directory and its dump equals the protoBaseST dump
    (`compare_dumps.py`); the SpaceRoot carries `cluster_term`, `cluster_epoch`,
    `cluster_previous` as `proto_db` reads them.
  - `rootlog_both_ways.sh`: `py_rootlog.py load <file>` prints `proto_db`'s
    `RootsLog(path).load()` (accepted, committed, promise, top, rejoined) for each
    `cluster/<n>.roots` protoBaseST wrote, equal to protoBaseST's `load`; `py_rootlog.py write
    <file>` appends promise, accepted, committed, rejoined with `proto_db`'s API and
    protoBaseST loads the same values; `py_rootlog.py name <id>` prints `_node_log`'s file name
    for the five ids of Review Focus 5, equal to `PBSharedTier logName:`.
- [ ] **Step 2:** run. Expected: PASS if Tasks 2-25 are right; any FAIL is a format defect,
  fixed in the owning module with a fail-first unit test.
- [ ] **Step 3:** run the suite. Expected: all PASS.
- [ ] **Step 4:** commit `Cluster C8: proto_db reads a protoBaseST cluster space and acceptor logs, both ways`.

### Task 27: Real processes, part 1: three nodes, `kill -9` of the owner and of a voter

**Files:**
- Create: `tests/cluster/_node.st` (a node: binds port 0, writes `out/<id>.port`, waits for
  `out/peers`, runs `n` `run:` increments writing each token to `out/<id>.acked` or
  `out/<id>.unknown` with `append:` + `sync`), `tests/cluster/_cluster.sh` (start, kill, wait
  for a marker file, verify), `tests/cluster/real_commits.sh`, `tests/cluster/real_kill_owner.sh`.

- **Checklist (Task 18):** no row of `tests/unit/cluster_checklist.tsv` is deferred to this task (0 rows); a row this task ports is turned into `ported`, and none is deferred to it.
- [ ] **Step 1: write the tests.** `real_commits.sh`: three processes, 30 commits each, then a
  verifier process reads the space through a fresh node: the counter equals the number of
  acknowledged tokens plus the unknown tokens present, every acknowledged token is present.
  `real_kill_owner.sh`: after the first 10 acknowledgements of the owner (marker file), `kill
  -9` the owner; the others finish; same verification; then `kill -9` a voter of a 5-node run
  and the remaining majority finishes. No duration is asserted; the runner's timeout is the only
  deadline.
- [ ] **Step 2:** run them. Expected: PASS; a FAIL is debugged with
  superpowers:systematic-debugging and fixed fail-first in a unit or simulator test.
- [ ] **Step 3:** run the suite. Expected: all PASS.
- [ ] **Step 4:** commit `Cluster C9: real processes, commits and kill -9 of the owner and a voter`.

### Task 28: Real processes, part 2: holder killed mid-round, restarts, rejoin

**Files:**
- Create: `tests/cluster/_node_seams.st` (test-only subclasses of `PBClusterRound` writing a
  marker file at "built", "replicate sent", "done sent", then continuing),
  `tests/cluster/real_kill_holder.sh`, `tests/cluster/real_restart_rejoin.sh`.

- **Checklist (Task 18):** turn the 4 `deferred 28` rows of `tests/unit/cluster_checklist.tsv` (`awk -F'\t' '$2=="deferred" && $3==28' tests/unit/cluster_checklist.tsv`) into `ported` rows, each naming the whole check label of a test this task adds; a row this task cannot port is re-justified as `n/a` in its review, never left deferred.
- [ ] **Step 1: write the tests.** `real_kill_holder.sh`: for each of the three markers, `kill
  -9` the holder when its marker appears; restart it with the disk kept; at the end every
  acknowledged token is present and every unknown token is present on all nodes or on none.
  `real_restart_rejoin.sh`: stop a voter, delete its `cluster/<id>.roots`, restart it: it
  rejoins by ballot (`stats` `rejoin_ballots` ≥ 1) and the workload completes with the same
  verification.
- [ ] **Step 2:** run. Expected: PASS (fix fail-first as in Task 27).
- [ ] **Step 3:** run the suite. Expected: all PASS.
- [ ] **Step 4:** commit `Cluster C10: real processes, holder killed mid-round, restart and rejoin`.

### Task 29: Measurements and documentation

> Rescoped 2026-11-15: the tutorial is now chaptered (`docs/tutorial/13-16`, branch
> docs/cluster-tutorial, merged before Task 30). Task 29 promotes the `examples/cluster/pending/`
> programs into the runner, updates the chapters with measured numbers, records D62 as known and not
> adopted, and documents "format 5 refused".


**Files:**
- Create: `bench/run_cluster.sh`, `bench/cluster_workload.st`.
- Modify: `README.md` (status, cluster in one paragraph, link), `docs/tutorial.md` (chapter
  "16. A cluster on one directory", every block in `tests/docs/tutorial_snippets.st`),
  `docs/reference.md` (the cluster section complete, timer table generated from
  `PBClusterConfig timerTable`), `docs/deviations.md` ("Cluster mode": `DEPTH = 0`, the group
  bound, HMAC, CC5, CC6, CC7, shared storage only, `flock` on network file systems, limit of
  about 16 members, a plain `proto_db` writer on a cluster space), `docs/decisions.md` (section
  "4. Cluster mode": the maintainer's answers Q1-Q8, the planner's calls CC1-CC25, rulings
  taken during execution; "Proposals to `proto_db`": Q7 (a) and (b) and CC6, as text for the
  maintainer to file), `docs/not-done.md` (slide and cuts: Phase D, pipelined permits, mixed
  clusters, TLS, read-only barrier, notify), `CHANGELOG.md`.

- [ ] **Step 1:** `bench/run_cluster.sh` (`RUNS=5`, interleaved, fsync): 1 and 3 nodes on
  loopback, profiles tiny and conc-hot; every run prints the commits it made and the verifier's
  count, and the runner refuses a run whose counts differ (benchmarks self-report). It also
  prints the split of spec 7.2 from `stats` (root-independent µs, build µs, replication µs per
  commit).
- [ ] **Step 2:** run it; record the dated figures in `docs/deviations.md` "Performance",
  marked indicative, with the machine and the commit.
- [ ] **Step 3:** write the documentation; run `tests/docs/` (snippets, sync,
  `reference_selectors.sh`). Expected: PASS.
- [ ] **Step 4:** run the suite. Expected: all PASS.
- [ ] **Step 5:** commit `Cluster C11: measurements and documentation`.

### Task 30: Final verification gate

Test scope (maintainer ruling, 2026-11-15): every earlier task runs only its own tests, i.e. the
tests it adds or changes and those that exercise the code it touches. The whole default suite,
the timer audit (`tests/audit`) and the hunt for integration problems run once, here. A failure
found here is fixed in the owning module, fail-first.

- [ ] **Step 1:** run the whole suite with the venv present. Expected: all PASS, no `SKIP` under
  `tests/conformance/cluster.st`, `cluster_checklist.sh` passing with 298 rows (rc4, since Task 22a). Then run the
  checklist in final mode with the checkout named: `CHECKLIST_FINAL=1
  PROTOBASE_REPO=<a ProtoBase checkout holding v2.0.0rc4> tests/unit/cluster_checklist.sh`.
  Also the F4 audit (rc4 delta, risk 4): no path decodes a record without its segment header
  checked (opaque atoms, the atom cache, records carried in messages).
  Expected: PASS, no `deferred` row left (each is `ported` or re-justified `n/a`).
- [ ] **Step 1b:** run the timer audit: `tests/run_tests.sh tests/audit`. Expected: all parts
  PASS at their declared floors. Re-measure every floor (`AuditFamilies floors`), not only the
  ones that fail: R149/R149a (Task 19b) changed the renewal path of every row, so a floor that
  rose would otherwise pass silently below its new count. Measure the parts on
  `AuditFamilies pendingFloors` (now the three `renewBackoff` parts, "measured in Task 30"),
  declare their floors and empty that list (the index, `tests/unit/sim_timer_audit.st` check
  (8), refuses a floor of 0 on any part not on it). A part whose floor drops gets a named reason
  in the commit. Also decide whether `AcceptFamilies powerLoss` should commit once more after its
  restarts, so that its crashes can fall inside a term (`tests/unit/_accept.st` `idle:`, the
  shared liveness property recorded there; Task 19b fix round 1).
- [ ] **Step 2:** soak: `PBST_SIM_SEEDS=5000 RUN_TIMEOUT=7200 tests/run_tests.sh tests/unit/sim_*.st`.
  Expected: PASS; a failure is a seed to reproduce and fix fail-first.
- [ ] **Step 3:** re-read the planner's calls (CC1-CC25) against what was built; update
  `docs/decisions.md` where execution changed one.
- [ ] **Step 4:** request the whole-branch review (superpowers:requesting-code-review), fix
  every finding that is cheap, record the others with a reason.
- [ ] **Step 5:** commit `Cluster: final verification`; report to the maintainer. Do not merge,
  tag or push.
