# Changelog

## 0.2.0 (unreleased)

- The cluster's safety sweep (Task 17): the timer audit, `tests/audit/` (every row of
  `PBClusterConfig timerTable` at 1/10, 10 times and skewed per member, 3 and 5 members, seeds
  1-30: 3240 simulator runs with drops and a crash; helper `tests/audit/_audit.st`), a run of its
  own: `tests/run_tests.sh tests/audit`, or `--audit` with the default set, which skips it; its
  index `tests/unit/sim_timer_audit.st` stays in the default run (it fails on a missing, extra or
  stale audit file). Each audit file asserts measured floors of strict runs and acknowledged
  commits (every run strict where every measured run was) and,
  for acquireTimeout, gatherAttempts and retryHold, a probe that shows the timer read (1/10 and
  10 times differ); safety-only row-modes and persist (not exercised until Task 20) are declared.
  The checker's self-tests (`tests/unit/sim_checker_plants.st`, eight planted histories, seven
  simulator-level plants of the derived history, `checkSafe` and the audit's gate, and two of the
  commit round: a conflicted attempt's root that took effect, a commit applied twice) and one planted defect per
  applicable lesson (`tests/unit/sim_lessons.st`, twelve; L29's plant `PlantLateDoneAsNone` in
  `tests/unit/_plants.st`). The simulator checks every converged run against the history rules
  of `proto_db`'s `assert_outcomes_resolved` (`PBSimHistory`, `PBSimChecker >> checkHistory:`:
  S4, unknown alike, H7, no commit applied more than once, no stray write, nothing shown lost,
  the counter; every attempt's built root writes its token, a re-commit of an unchanged base
  credits its token nothing) and, when the members
  have not caught up, `checkSafe`; each node's configuration can be its own
  (`PBSim seed:ids:rules:configs:logs:`). `PBClusterConfig` reads its derived timers through
  `renewalLeft`, `permitFloor` and `permissionDeadline:` (same values), and the owner's late
  permission (O6) is the rule method `PBCoordinatorCore >> _permissionLate:in:now:effects:`.
- The rejoin of an empty acceptor log (`src/protobase/cluster/rejoin.st`, CP 'A node that lost
  its disk', R51, R78a, L13, L14, L18): `proto_db`'s `_rejoin`, `_rejoin_round`, `_gather`,
  `_rejoin_decision`, `_complete_rejoin`, `_on_ballot_query` and `force_rejoin` as rule methods
  of `PBCoordinatorCore` over the values `PBRejoin` (kept in `PBNodeState rejoin`) and
  `PBRejoinAnswer`. A voter whose log lacks the rejoined marker starts a rejoin from its start
  step: a plain gather (re-asked up to `gatherAttempts`), then the decision `new` (complete at
  once, termsSeen left 0), `rootless` or `witnesses`, which take a ballot round above everything
  reported, counted only from answers that echo the ballot; an unreadable adopted root blocks
  the rejoin (`rejoinBlockedIn:`) and it retries; the acceptor event `PBRejoinLearnt` appends the
  promise, the accepted root and the marker, in that order, and sets `rejoinBallot` (closing the
  L14 interim: the ballot now comes from a real rejoin). A ballot query to an 'ok' acceptor is a
  durable promise answered echoing the ballot. `PBRejoinWanted` (forceRejoin) completes a rejoin
  on majority - 1 loaded answers and, on a survivor (`PBForceRejoin`), forgets a committed root
  above the accepted one. `PBAcceptorState needsConfirmation` is true at every attach, cleared by
  `PBConfirmed`; `with:` also takes `#rejoinBallot` and `#confirmed`. `PBLogDetached` (and a
  report over another log) drops a rejoin and its forced flag, as `proto_db`'s detach; an
  adoption carries its log and an acceptor over another log refuses it. Tested by
  `tests/unit/sim_rejoin.st` (the R78a schedule at three wiped-timer rates, the holder's timer
  running or stalled, with `PlantRejoinByWaiting` caught; first and late first start; L14 with
  `PlantReplicateBelowBallot` caught; a majority log loss detected by the guard naming
  forceRejoin; families and plants in `tests/unit/_rejoin.st`) and
  `tests/unit/cluster_rejoin_rules.st` (one guard per check).
- The commit round (`src/protobase/cluster/holder.st`, spec 5.6): `proto_db`'s `_run_round`,
  `_permit_round`, `_keep`, `_take_kept` and `_await_retries` as a pure state machine,
  `PBCoordinatorCore >> round:in:now:` over a `PBRoundState` of `PBRoundEntry` commits, with the
  events `PBRoundEnqueued`, `PBPermitted`, `PBBaseDecided`, `PBBuilt`, `PBBuildConflict`,
  `PBBuildFailed`, `PBReplicated`, `PBHoldExpired`, `PBDropKept` and the effects `PBAskPermit`,
  `PBAskBase`, `PBBuild`, `PBReplicate`, `PBReportDone`. One round at a time takes the whole queue;
  a base that needs a commit is re-committed first; conflicts fail alone; the group bound (CC11)
  leaves the rest queued for the next round; the reserve check (R121, with the CC18 text naming
  `sendReserve`, the longest build and `leaseDuration`) and the rejoin ballot (L14) refuse a send
  with a retryable conflict and nothing sent; outcomes follow H7 (`#unknown` is a
  `PBOutcomeUnknownError`, never retried). Held retries (D-LIVE-2): a conflicted commit whose
  caller retries at once gets `PBConflictError` with `permitHeld` true (new `PBConflictError
  held:`), and the permission is kept for min(`retryHold`, the time left) so its retry runs the
  next round under it; the round awaits every held caller (`PBRoundEntry caller`,
  `PBDropKept caller:`). After `termRetries` (5) stale bases in a row the queued commits fail with
  a conflict (`proto_db` `_TERM_RETRIES`). `dispatchReplicateWanted:` also refuses a term below
  the acceptor's rejoin ballot at the send. `PBStep` also carries a `PBRoundState`. Tested by
  `tests/unit/sim_round_rules.st` (hot key on three nodes without starvation, reserve refusal,
  a build longer than the belief, the group bound, a stale base, unknown never retried, hot-key
  clients beside blind writers, every commit getting an outcome, and the plants `PlantNoReserve`
  and `PlantNoKeep`; the round's simulator shell in
  `tests/unit/_round.st`) and `tests/unit/cluster_round_rules.st` (one guard per check).
- The base choice (`src/protobase/cluster/holder.st`, CP 1.6): `proto_db`'s `_lease_base`,
  `recover_root`, `_phase_1_floor`, `_base_needs_commit`, the refound and the hard guard, as rule
  methods of `PBCoordinatorCore` (`leaseBase:waiter:in:now:`, the default rule of
  `PBBaseWanted`). A certain permit's root is the base; an uncertain one runs a recovery round
  (ballot 0) that ends at a majority of witnesses, or waits for every voter when asked
  (`PBRecoverWanted every:waiter:`); the phase-1 floor (R127) raises the base to the
  permission's root; with nothing known the persisted root is read and the cluster refounds
  (terms raised by `refoundStep`); a base superseded by a committed root is `#stale`; a base
  below the committed root this node knows is a `PBCorruptionError` naming the operator's
  remedy, unless the persisted root lets it refound; a base that is not the committed root must
  be committed first (R50; never the empty space), and one whose SpaceRoot the shared storage
  cannot read is `#unreachable` (R133: a retryable conflict, the term abandoned). The decision is a
  `PBBaseDecision`; new events `PBRecoverWanted`, `PBStorageRead`, `PBRootProbed`, the acceptor
  event `PBRecovered`, the effects `PBReadPersisted` and `PBProbeRoot`, and `PBHolder` gains
  `choices` and `permits`. The holder now keeps the base bound (re-bound to each root committed
  under the permission, as `bind_root`) and the root last sent under each permission and refuses a `PBReplicateWanted` whose pred is not `proto_db`'s `lease.sent` rule
  (`predFor:in:`). The simulator gains the persisted root, an unreadable-root disk fault, an
  epoch step per node and the commit path's base, re-commit and replicate stages. Tested by
  `tests/unit/sim_base_choice.st` (the C1, I1, M6 and refound schedules, the strict R79/L28 form
  and four plants; families in `tests/unit/_base.st`), `tests/unit/sim_base_seeds_a.st` and
  `tests/unit/sim_base_seeds_b.st` (200 seeds under drops and clock skew) and
  `tests/unit/cluster_base_rules.st` (one guard per check).
- Acceptance, the commit point and committed knowledge (`src/protobase/cluster/acceptor.st`, the
  new `src/protobase/cluster/holder.st`): `proto_db`'s `_may_accept`, `_apply_replicate` over a
  shared storage, `_on_done`, `_observe_accepted`, `_observe_committed`, `_learn_label`,
  `replicate` and `_on_answer` for acks, as rule methods of `PBCoordinatorCore`. An acceptor
  takes a root under the ballot rule and the chain rule (V2', log matching on roots), appends
  one synced `#accepted` entry and only then acks; a holder sends nothing past its permission
  or under `sendReserve` (`#none`), and a commit is `#committed` exactly when a majority of the
  voters acked within the permission, else `#unknown` (suspect). Committed knowledge (dones,
  held releases, certain permits, grants, the replicate's committed root) is learnt in
  `proto_db`'s order and appended `#committed` without a sync; a learnt label clears a
  suspicion at or below it. `PBReplicateWanted` is now `permission:root:pred:waiter:`,
  `PBAcceptorStep` gains `learnt`, the new acceptor event `PBLearnCommitted`, `PBHolder` gains
  `replications`, a restored acceptor accepts the higher of its logged accepted and committed
  roots and publishes its committed root at start. The simulator gains `pause:`/`resume:` (a
  paused process) and `reconfigure:options:`. Tested by `tests/unit/sim_acceptance.st`
  (families, checks and plants in `tests/unit/_accept.st`) and
  `tests/unit/cluster_acceptance_rules.st` (one guard per check, the chain-rule tests).
- The owner's rules O1-O8 at DEPTH 0 and abandoned terms (`src/protobase/cluster/owner.st`):
  `proto_db`'s `_dispatch`, `_on_permit_req`, `_permit_outcome`, `_abandon`, `_refuse_queue`,
  `_on_done_owner` and `finish`, and the holder side of a permit request
  (`_permission_from_owner`, `_on_permit_reply`), as rule methods of `PBCoordinatorCore` over the
  immutable values `PBIssued`, `PBPermitAsk` and `PBHolder`. An owner issues one permission at a
  time in arrival order, its own commits among the members'; a committed done retires it, a
  'none' from the only entry removes it, anything else (an unknown outcome, a done of another
  incarnation, no done by valid + `requestTimeout`, the lease expiring with a permission out)
  abandons the term: suspect, the queue refused 'abandoned', an uncertain release. A waiter has
  a deadline of `acquireTimeout` and ends in `PBTimeoutError`, also while queued at its own
  node's ownership; a refusal or a silence forgets an
  owner only for the term asked under. `PBOwnership` is now `lease:base:committed:now:` with a
  queue of requests and a pipeline; `PBNodeState` gains `holder`; `PBDoneReport` gains `root`
  (`permission:outcome:root:`). Tested by `tests/unit/sim_permits.st` (scenarios and plants in
  `tests/unit/_permits.st`) and `tests/unit/cluster_owner_rules.st` (one guard per check); `tests/unit/cluster_proposer_rules.st` now sees the first
  permission issued at once.
- The proposer's rules (`src/protobase/cluster/proposer.st`): acquiring, owning, renewing,
  releasing and the fairness hints of `proto_db`'s coordinator (`permit`, `_become_owner`,
  `_open_attempt`, `_on_reply`, `_close_attempt`, `_back_off`, `_own_loop_body`, `_renew`,
  `release`) as rule methods of `PBCoordinatorCore`, over the immutable values `PBHints`,
  `PBProposer` and `PBOwnership`. A lease is valid from the send of its request plus the belief
  (L5); replies of another incarnation are dropped (`stale_replies`); a lost attempt cancels and
  backs off, and only a held release or a newly learnt owner ends the back-off itself; a release
  names the member seen waiting longest and the others defer to it. The node's own vote now
  travels in the acceptor step (`PBAcceptorStep vote`), `acceptReceived:in:now:` takes the
  node's own messages, and `PBAcceptorDiscarded` reports a discarded step to the dispatcher.
  The owner's permissions follow in Task 12. The simulator gains a sync cost, fixed link delays,
  scheduled commits and the L5 lease check (`watchLeases`). Tested by `tests/unit/sim_leases.st`,
  `tests/unit/sim_leases_terms_a.st`, `tests/unit/sim_leases_terms_b.st`, `tests/unit/sim_leases_plants.st` (the planted rules of `tests/unit/_plants.st`) and
  `tests/unit/cluster_proposer_rules.st`. `tests/run_tests.sh`'s default `RUN_TIMEOUT` is now 600 s.
- The acceptor's phase-1 rules (`src/protobase/cluster/acceptor.st`), `proto_db`'s `_route`,
  `_on_request`, `_decide`, `_refusal`, `_on_release` and plain query as rule methods of
  `PBCoordinatorCore`: the dispatcher drops messages of non-members and counts voter-set
  mismatches (`config_mismatches`); `acceptRequest:in:now:` and `acceptRenew:in:now:` refuse
  (`fenced`, `learner`, `tier_failed`, `rejoining`, then the grant rules' reasons) or grant,
  appending a synced promise only above the one already logged, so a renewal writes nothing;
  `acceptRelease:in:now:`, `acceptQuery:in:now:` (promised = max(terms seen, accepted label)),
  `acceptStart:in:now:` (the rejoined marker of a learner or a lone voter),
  `acceptSuspect:in:now:` (`PBSuspect`) and `acceptAppendFailed:in:now:` (`PBAppendFailed`: the
  tier fails, the unsynced grant is never replied). A reject's `remaining` is wire seconds
  (`wireSeconds:`). `core.st` gains the `PBCount` effect and `PBAcceptorState loggedPromise`;
  the simulator gains injected messages, pre-formed logs, append failures and counters.
  The dispatcher's checks of `_route` live in `core.st`, which then calls the handler of the
  message's type (`received<Type>:in:now:`, `accept<Type>:in:now:`); the start reaches the
  acceptor; a fenced node sends nothing; every grant counts `grants_given`; `loggedPromise`
  belongs to the log it was written to (`PBAcceptorState >> log`), and a step whose append fails
  is discarded. A plain query is answered by the acceptor (`docs/deviations.md`).
  Tested by `tests/unit/sim_grants.st` (seeds 1-40, empty-log starts, plant `PlantRenewStale`)
  and `tests/unit/cluster_acceptor_rules.st`.
- The coordinator core's vocabulary (`src/protobase/cluster/core.st`): `PBCoordinatorCore`
  (`dispatch:in:now:` answering a `PBStep`, `accept:in:now:` answering a `PBAcceptorStep`, one
  rule method per event chosen by double dispatch), the events (`PBReceived`, `PBTimerFired`,
  `PBStartNode`, `PBStopNode`, `PBPermitWanted`, `PBBaseWanted`, `PBReplicateWanted`,
  `PBDoneReport`, `PBRejoinWanted`, `PBAcceptorDecided`), the effects (`PBSend`, `PBToAcceptor`,
  `PBLogAppend`, `PBTimer`, `PBSettle`, `PBPublishCommitted`, `PBPublishAcceptor`, `PBFence`) and
  the state values `PBNodeState` and `PBAcceptorState`, immutable, with time passed in
  microseconds. The protocol rules follow in later modules. The tests gain a seeded,
  virtual-time simulator (`tests/unit/_sim.st`: fake clocks with per-node rates, a faulty
  network with partitions, simulated acceptor-log disks with crashes and torn tails, synthetic
  commits, and an invariant checker), exercised by `tests/unit/sim_harness.st`.
- Lease values (`src/protobase/cluster/lease.st`): `PBGrantState` (the grant rules of
  `proto_db`'s `PeerGrants` with the ballot check of `_decide`), `PBGrantDecision`,
  `PBActiveGrant`, `PBAttempt`, `PBLease` and `PBPermission`, immutable, with time passed in
  microseconds. A lease is measured from the send of its request (L5).
- Cluster configuration (`src/protobase/cluster/config.st`): `PBClusterConfig` validates a member's options with
  `proto_db`'s defaults and refusal rules (drift margin at least 2/3 of the lease, request timeout below the belief,
  send reserve at most a quarter of it), takes milliseconds and answers microseconds, and `timerTable` lists the timers
  that apply at depth 0. `#fetchTimeout` is refused as Phase D.
- Cluster frames (`src/protobase/cluster/protocol.st`): `PBClusterFrame`, the 4-byte big-endian
  length and the 64 MiB limit of `proto_db`'s `encode_frame`/`FrameDecoder` (`encode:to:key:`,
  `lengthFrom:`, `decodeBody:to:key:`, `decode:to:key:`), with optional HMAC-SHA-256 frame
  authentication bound to the receiver (CC4): without a key the frames are protocol 13 byte for
  byte, with one they diverge (`docs/deviations.md`, "Cluster mode", which also states the
  trusted-network assumption). The invalid `message-oversized` vector is verified by
  `tests/conformance/cluster.st`, which no longer skips anything.
- The acceptor log (`src/protobase/cluster/rootlog.st`): `PBAcceptorLog`, `proto_db`'s
  `RootsLog`, with `PBLoggedRoots` and `PBLogEntry`. It writes entry kinds 1 to 4 (promise,
  accepted, committed synced or not as `proto_db`, rejoined marker) and reads kinds 1 to 6, holds
  `<path>.lock` while open (a held lock is `PBUserError` naming it) and refuses every write after
  a failed one. `roots.log` and the invalid `roots_log` vectors are verified by
  `tests/conformance/rootlog.st` and no longer skipped.
- `PBFramedLog openAppend:kind:` refuses a log file with more than one hard link
  (`PBLockingError`), before reading or repairing it, as `proto_db`'s `open_log`; `PBFramedLog >>
  sync`. protoBaseST now needs **protoST 0.12.0** (`BinaryFile >> linkCount`, `FileReference >>
  realPath`), built on protoIO 0.7.0.
- `PBAcceptorLog path:` resolves the real path before it names `<path>.lock`, as `proto_db`'s
  `RootsLog`: a symbolic link to a log no longer opens a second handle on it (the ship-blocking
  item of review is closed). A symbolic link loop is `PBUnexpectedError`.

- The wire messages of cluster protocol 13 (`src/protobase/cluster/protocol.st`):
  `PBClusterMessage`, the 22 types of `proto_db`'s `protocol.py` with its field table and
  validation (`decode:`, `encode`, `type:from:fields:`), the wire roots of CC17 (`rootFrom:`,
  `rootValue:`), `rangesFrom:`/`rangesValue:` and `afterFrom:`; `PBClusterProtocolError`, a
  `PBCorruptionError`. The 23 message frames and the invalid `message` vectors are verified by
  `tests/conformance/messages.st` and no longer skipped, except `message-oversized` (the frame
  layer, cluster Task 6).
- Cluster membership values (`src/protobase/cluster/members.st`): `PBPeer` and `PBMembership`
  (ranks in code point order, the voter set of `proto_db`'s `_voter_set`, `majority`, the
  voter-set fingerprint, `ballotAfter:rank:`); the root order (`src/protobase/cluster/rootlog.st`):
  `PBLabeledRoot` and `PBRootOrder`, the order of `proto_db`'s `root_key`/`compare_roots`; and
  `PBSpaceRoot databases:term:epoch:previous:`, which writes the cluster fields. The cluster
  segment vector is verified by `tests/conformance/cluster_segment.st` (writing and reading) and
  no longer skipped.
- `PBFramedLog` (`src/protobase/cluster/log.st`): the framed append-only log of `proto_db`'s
  `logfile.py` (headers, frames, `openAppend:kind:`, `read:kind:`), re-ported with the linear
  prefix-checksum torn-tail search; the condition of ruling R14 (cluster storage enters scope) is
  met. The `log`-layer, `ranges_log`, `segments_log` and `roots_log_torn` vectors are verified by
  `tests/conformance/framing_logs.st` and no longer skipped.

## 0.1.0 (2026-11-13)

The entries are chronological, and later entries supersede earlier ones (vectors and format
`v2.0.0rc1` became `v2.0.0rc2`; the nesting limit of 511 containers became 1022).

- Repository skeleton: error hierarchy mirroring `proto_db`, test runner, vendored
  conformance vectors (`proto_db` at `v2.0.0rc1`), Python interop venv and week-0 checks.
- Values and the canonical codec: `PBFrozenList`, `PBTuple`, `PBFrozenDict`, `PBMissing`,
  `PBMutableObject` (the handle), `PBAtomPointer`, `PBUnresolvedRef` and `PBLegacyZoneDateTime`;
  `PBCodec` with `canonical:`, `toWire:atomRef:`, `fromWire:resolver:`, `encode:` and `decode:`.
  The bytes are those of `proto_db` at `v2.0.0rc1`; every refusal of the format spec is explicit
  (`PBValidationError` when writing, `PBCorruptionError` when reading, `PBNotSupportedError`
  for what needs a time-zone database or `lib/uuid.st`).
- Time-zone keys are checked against `PBZoneKeys`, a committed list of the IANA tzdata 2026e
  keys (`tools/gen_zone_keys.py`), never against the host's zoneinfo. Instant-form datetimes are
  read and presented in UTC. Format-3 zone-datetime map keys whose conflicts need offsets are
  refused (`PBNotSupportedError`). Lone surrogates and values nested deeper than 511 msgpack
  containers are refused with `PBValidationError`. Duplicate map keys are found in linear time.
- The format-3 key refusal applies only to two keys that could conflict (equal at every other
  position under the order-key rule, so `true`, `1`, `1.0` and `Decimal 1.00` are one item there,
  and datetimes within the 24 h or 48 h offset window). Every string the codec writes
  (zone names, mutable names, reference type names) is checked for lone surrogates. Empty
  containers are charged one msgpack level less, and `canonical:enclosingDepth:` and
  `toWire:atomRef:enclosingDepth:` take the depth of an enclosing record.
- Conformance runners for the value layers: `PBNotation` (`describe:`, `build:`, `describeRaw:`,
  `floatHex:`, `floatFromHex:`) and the vector checks of `tests/conformance`.
- Framing and the type registry: `PBSegmentHeader`, `PBRecordHeader`, `PBRootRecord` and
  `PBAtomEnvelope` (`framing.st`); `PBTypeRegistry`, `PBAtom` and `PBOpaqueAtom`
  (`registry.st`). The built-in alias table now lives in `PBTypeRegistry builtinNames`;
  `PBNotation builtinAliasNames` is removed. `PBCodec` reads a `@ref` with the writer's tag: a
  format-2 built-in name becomes its alias, an application alias the declared name. The
  `framing` vectors and the invalid `record`, `segment` and `root` vectors pass, and so do
  `ref-format2`, `ref-name-of-builtin` and `ref-alias`.
- The read path (plan Task 12): AVL nodes and value boxes (`avl.st`); the collections with
  `proto_db`'s read API (`collections.st`); `PBObject` with the reserved behaviour names of DBObject
  (`records.st`); `PBOpaqueAtom` reads its fields and refuses everything else naming its type;
  the indexes, decoded and kept (`indexes.st`); `PBSpaceRoot` and `PBDatabaseRoot` (`roots.st`);
  `PBObjectSpace`, `PBDatabase`, `PBSnapshot` and `PBHistoryEntry`, read side (`space.st`);
  `PBReferenceError`; `PBNotation describeObject:`, `describeDatabase:` and `dumpSpace:to:`.
  Every built-in type now has its class. The `database`, `legacy_database` and
  `polyglot_database` contents and the invalid `atom` vectors pass; the cluster vectors are
  visible skips (clusters are outside the prototype).
- The transaction, read side (plan Task 13, `transactions.st`): `PBDatabase >> newTransaction`
  snapshots the root record, the `SpaceRoot` and the `DatabaseRoot` once; `PBTransaction` has
  `getRootObject:`, `rootNames`, `getMutable:`, `mutableNames`, `abort`, `isActive`, `database`
  and the test-visible `readSet` and `mutableReadSet`. The first read of a name records its token
  (an atom's pointer, a plain value's exact token, `#absent`) in one immutable `PBTxState` held
  in an `Atom` and replaced with `swap:`. After `abort` every other message is `PBUserError`.
  `PBMutableObject >> get:` reads a cell through a transaction.
- Atom identity as `proto_db` D21 (ruling R13): an atom that is not stored draws its oid (a
  version-4 UUID, `UUID new`) in memory on first need, published by compare-and-swap so two first
  readers agree; a stored atom's oid is its record's. `PBAtom >> =` and `hash` go by oid, so an
  unsaved atom is a map key and a lookup probe like any other (a lookup by it misses where no
  stored key has its oid). `PBKeys isUnsavedProbe:` and the `PBNotSupportedError` for an atom
  without an oid are removed.
- A record that needs itself to be decoded (a map key referring back to it) is
  `PBCorruptionError` naming its pointer, where `proto_db` recurses until Python's
  `RecursionError`: damaged data, or a writer that breaks the save-dependents-first invariant.
  The loads in progress are passed explicitly to the resolver (`_PBLoadResolver`) instead of
  through a resumable exception, which any `on: Exception do:` around a read used to catch,
  answering the handler's value instead of the data.
- Map keys `Float infinity` and its negation (and Decimal infinities) are keys again: their
  order-key payloads are private marker objects, not Symbols (a short Symbol is a String in
  protoST, STATUS D35, so their hash was refused). `proto_db`-written maps, Dictionaries and
  HashDictionaries keyed by infinities are read (`tests/unit/read_cross_kind_keys.st`).
- A transaction's read sets are persistent maps: a first read costs O(log n) instead of
  rebuilding the map.
- The ERP example's record types, `examples/erp/erp_model.st` and `erp_model.py` (`Invoice`,
  `Customer`; `demo.erp.AuditNote` is Python-only). Design spec 10.2 runs: a space `proto_db`
  writes is dumped by protoBaseST exactly as by `proto_db`'s verifier
  (`tests/interop/py_to_st.sh`).
- `proto_db` reads back the deepest attribute protoBaseST writes (509 nested lists) only with a
  raised Python recursion limit: at the default limit its reader raises `RecursionError` from
  about 333 nested lists. `tests/interop/st_deep_to_py.sh` states the workaround in a `NOTE:`
  line naming ask B12 (which the runner now shows under PASS) and fails once `proto_db` reads the
  record at the default limit. `_st_dump.st` also reads versions 2 and 1 of the ERP database.
- New versions (plan Task 15): `PBList new` and `setAt:value:`, `insertAt:value:`, `removeAt:`,
  `appendFirst:`, `appendLast:`, `extend:`, `sliceFrom:to:`, `head:`, `tail:` with `proto_db`'s
  positions (Review Focus 5); `PBDictionary new`, `setAt:value:`, `removeAt:`; `PBSet new`,
  `add:`, `remove:`; `PBObject withAll:`, `with:value:` and `withAll:` on a record. Each answers a
  new atom and leaves the receiver unchanged; values are canonical at once; a collection with an
  index refuses every change (`PBNotSupportedError` naming the indexes). `PBAvl posFromArray:`,
  `posConcat:with:` and `posSlice:from:to:` build `proto_db`'s trees for `extend:` and the slices.
- The save, dependents first (`PBAtom >> _saveInto:` over a storage answering `pushAtom:`): every
  record refers only to records written before it; the record carries the oid drawn in memory;
  the atom records its place (`pointer`, `isSaved`), so it is written once. `PBAtom >>
  _decodedTwin` is ProtoBase's `_decoded_twin`. Building an atom no longer needs its class to
  be registered; saving it does.
- The class comments of `PBList`, `PBDictionary`, `PBSet` and `PBCountedSet` start with "Every
  message answers a new version; the receiver never changes."
- The save refuses an unregistered class before writing any of its dependents, and two saves of
  one atom that race end the same way whatever the interleaving (one storage: the first pointer
  published; two storages: `PBValidationError`). `extend:` of nothing answers the receiver even
  when the list is indexed, as `proto_db`'s; `extend:` of a String is refused up front. A
  non-Integer slice bound (a Boolean included) is refused, a documented deviation from Python's
  slice rules.
- Operation logs and merges (plan Task 16, `proto_db` `ConcurrentOptimized`, D33): every
  `PBDictionary`, `PBHashDictionary` and `PBSet` version carries `opLog` (a `PBFrozenList` of
  `PBTuple`s `('set' k v)`, `('remove' k)`, `('add' e)`, kept internally as a persistent chain,
  so a mutator logs in O(1)), `logComplete`/`isMergeable` and a `consumed` cell that
  `markConsumed` sets. `rebaseOnto:` replays the net effect (the last intent per key, by order
  key, in order of last occurrence) through the public mutators; a current of another class
  is `PBValidationError`, one with an index `PBNotSupportedError`. A `PBDictionary` logs a
  large value in its stored form, so a replay reuses the `PBValueBox` (`proto_db` D51).
- `PBHashDictionary >> setAt:value:` and `removeAt:` (buckets of `(key, value)` tuples under
  the hash key); `PBSet >> union:`, `intersection:` and `difference:`, `proto_db`'s folds of
  `add:` and `remove:`.
- `PBCountedSet` and `PBRepeatedKeysDictionary` are `ConcurrentOptimized`, as in `proto_db`: a
  new empty one is mergeable and rebases to `current` unchanged (Task 16 review I1).
- `_bucketHash:` on `PBHashDictionary` and `PBHashBuckets` (`proto_db` `_bucket_hash`): lookups
  and writes file entries under it; multi-entry buckets match `proto_db` byte for byte
  (`tests/interop/bucket_collisions_identical.sh`).
- The invalid `log` vectors (framed log files, read by `proto_db` only in its cluster and
  tiered storage) are justified skips of `tests/conformance/cluster.st` (ruling R14); the
  runner prints the `SKIP:` lines of a passing test under its `PASS` line.
- Record field access in a few dispatches (plan Task 16b, ruling R15): every atom class has a
  record shape (`_PBRecordShape`: its `persistedFields` with a shared `PBMapKeyIndex`, its slot
  order, its integer fields), built from its declarations when it is registered or first
  needed and published once. Each record carries a slots Array, built once when the record is
  built or loaded and published once by compare-and-swap. A class that declares `slotFields`
  reads them through accessors with literal slot numbers (`PBPosNode`, `PBKeyNode`,
  `PBCountedKeyNode`, `PBValueBox`; an application subclass of a keyed node class inherits
  the layout, may reorder its `persistedFields` and may add fields, read with `_slotAt:`; the
  AVL writes carry such a field, present or absent, into every copy of a node); a subclass
  whose layout cannot hold, or whose `persistedFields` name a field twice, is refused when it
  is registered. Positional trees are not subclassable, as `proto_db`'s `PosNode`: their writes
  build `PBPosNode` only, and a `PBPosNode` subclass is refused when it is registered, built
  or given to a positional operation. `tests/unit/record_slots.st` holds every
  literal to `slotFields` for every registered class. Integer fields are checked once per
  record (an optional one may be absent); the AVL writes, which compute them, are not checked
  again. A loaded record in persisted order shares its class's keys and index (the decoder
  builds no index for it). The walks check each child with one send, `check:` installs one
  handler per tree, and the index and root checks of `PBAvl` use no blocks. The bytes, `=`,
  `hash` and the save are unchanged. `bench/run_avl.sh` measures the AVL workload against
  `proto_db`, interleaved, for any binary and source tree.
- The file storage's write side (plan Task 17, `store.st`): `PBFileStorage >> save:`,
  `pushAtom:` (into `PBSegmentWriter`, the segment the storage owns: a fresh UUID4 name,
  `#create #exclusive`, header and directory synced), `flushSegment`, `currentSegment`,
  `tryLockRoot` and `unlockRoot` (the OS lock on `space.lock`, `proto_db`'s `root_lock`),
  `replaceRoot:` (lock held, segment synced, SpaceRoot pointer checked, epoch + 1, cluster
  refusal, `space.root.tmp` synced, renamed, directory synced), `isCluster`, `isFailed` and
  `newSegmentId`. A file-system failure leaves the storage failed for writes, as `proto_db`'s.
  The unit tests that saved into the `SegmentSink` double now save into `PBFileStorage`, and
  `tests/unit/_sink.st` is gone. `tests/interop/st_write_to_py.sh` runs `proto_db`'s verifier on
  spaces protoST wrote, commits from each side on top of the other, and checks the root lock
  both ways; `compare_dumps.py --exact` compares dumps without the AuditNote normalisation.
- File storage write side, review fix round 1: one storage state (an Atom changed by
  compare-and-swap: idle, writing, close requested, closed), so `close` during a write is
  completed by that write and never releases the root lock under a publish, and `unlockRoot`
  during a write is refused; segment rollover as `proto_db` (`path:segmentMaxBytes:`, 256 MiB by
  default), with every segment written since its last sync synced before a root is published;
  the epoch of a publish is documented as the start epoch plus one. New tests:
  `store_close_race.st`, `store_crash_states.st`, `store_segment_rollover.st`, the seams of
  `tests/unit/_seams.st`, `tests/interop/crash_states_to_py.sh`, and the reverse lock
  exclusion (protoST holds, `proto_db` times out) in `st_write_to_py.sh`.
- `proto_db` at `v2.0.0rc2` (plan Task 17b, ruling R18; ask B12 resolved): a value nests at most
  `MAX_VALUE_DEPTH` = 1022 msgpack containers (`PBCodec maxValueDepth`), counted from the value
  as the format spec counts it (an empty container counts like any other; map keys are on the
  paths), and a record therefore at most 1024. Depth 1022 round-trips; 1023 is
  `PBValidationError` when written, naming the field, attribute or collection element, key or
  value, and `PBCorruptionError` when read. This replaces the 511-container cut (509 inside a
  record, ruling R12), which a conforming reader may no longer apply;
  `canonical:enclosingDepth:` and `toWire:atomRef:enclosingDepth:` are removed, and
  `canonical:for:`, `toWire:atomRef:for:`, `valueDepth:` and
  `check:wrapping:holder:wrapper:` are added. `PBSet` refuses an element past 1020 and
  `PBHashDictionary` a key or value past 1018, when the mutator is called. The codec's walks,
  and the order keys, hash keys, tuple comparison and map-key checks, use explicit stacks: a
  recursion through `do:` or `collect:` stops at about 1,000 levels in protoST. Needs protoST's
  MessagePack at 1024 levels (protoIO `e952077`, protoST `b412b38`).
- The conformance vectors are those of `v2.0.0rc2` (digest `6e913bcb…dfbf4`): the
  `values_depth` section (`tests/conformance/values_depth.st`), seven `value-depth-over-*`
  invalid vectors, and the regenerated database vector. The interop venv holds `proto_db`
  `v2.0.0rc2` with msgpack 1.2.4; `env.sh` fails when the venv holds another commit. The
  recursion-limit workaround of `st_deep_to_py.sh` and its `NOTE:` line are gone; the deep
  cross tests run at 1022 both ways and check the refusals of 1023 both ways.
- Transactions write side and the publisher (plan Task 18): `PBObjectSpace >> newDatabase:`
  (version 0, empty objects and mutables, a 16-byte random origin, `committedAt` now in UTC);
  `PBTransaction >> setRootObject:value:`, `setRootObject:value:replace:` (a `__` name is
  `PBValidationError`), `removeRootObject:`, `newMutable:value:`, `setMutable:value:` and
  `removeMutable:` with the D35 rules, the factories `newList`, `newDictionary`,
  `newHashDictionary`, `newSet`, `newCountedSet` and `newObject:`, `commit` (a commit with no
  writes publishes nothing; a failed commit aborts) and the write side of `abort`;
  `PBDatabase >> newTransactionDo:`; `PBMutableObject >> set:value:`. A written value passes
  `PBCodec canonical:for:` with the holder `Root 'name'` or `Mutable 'name'`. The writes and the
  sets of a transaction are persistent maps (`_PBWriteMap`, O(log n) per write), like its read
  sets. `PBPublisher` (`publisher.st`), one actor per space, runs design spec 7.3: the root lock
  retried from 1 ms doubling to 50 ms until `lockTimeout` (`PBTimeoutError`), validation against
  the root read under the lock (`PBConflictError`), the merge of blind writes (`rebaseOnto:`)
  or last writer wins, save and sync, publish with that root's epoch plus one, consumed marks
  (D33), and the outcome of a failed publish decided by reading
  `space.root` again (`PBOutcomeUnknownError` when it cannot be read). `PBObjectSpace >> close`
  closes the storage through the publisher, between commits. `PBSpaceRoot databases:`,
  `PBDatabaseRoot objects:mutables:version:committedAt:origin:previous:` and `committedAfter:`.
  New tests: `tx_commit_basic`, `tx_conflict_read`, `tx_blind_merge`, `tx_replace`,
  `tx_mutables`, `tx_after_end`, `tx_refusals`, `tx_outcome`, `tx_new_database`, and
  `tests/interop/st_commit_to_py.sh` (`proto_db` verifies and reads the publisher's records,
  whose fields are in `proto_db`'s order, and blind merges compose across the two languages).
- Task 18 review fix round 1:
  - **The publisher never waits** (ruling R19, review C1). An attempt that finds the root lock
    held answers `false` at once, and the committing caller owns the backoff
    (`PBObjectSpace >> _untilPublished:`, used by `commit` and `newDatabase:`). Before, a
    publisher waiting in its backoff inside a helping worker made other commits fail with
    protoST's `deadlock:` Error and lose their writes. New test: `tx_lock_contention.st`.
  - **Written atoms are saved before the root lock**, once, as `proto_db`'s `_commit` does.
  - **`newTransactionDo:` commits on a non-local return** (`^`), as Python's `return` inside
    `with` does.
  - **Origin.** A new database's origin is the bytes of a version-4 UUID (`UUID new`), as
    `proto_db`'s `uuid4().bytes`.
  - **Python's repr in messages.** Error texts quote names as Python's `repr` does
    (`PBCodec repr:`): the `Root`, `Mutable`, `Field` and `Attribute` holders, and the
    database messages.
  - **Unused state removed.** The space's last-known root had no reader in the spec or in
    `proto_db` outside a cluster.
  - **Comments.** The `replaceRoot:` comment and the README state the epoch rule the
    publisher follows.
  - **Interop.** New test `tests/interop/st_py_interleaved.sh`: a Python commit between a
    protoST transaction's start and its commit, and the reverse, give a conflict for the read
    root and a merge for the blind write.
- Task 18 review fix round 2 (ruling R20, review N1):
  - **`newTransactionDo:` aborts on any exception that ends the block**, as `proto_db`'s
    `__exit__`. Before, only an `Error` aborted, so a `Warning` or `Notification` ended by an
    enclosing handler (`return:`, falling off) committed the block's partial writes. The block
    now asks the enclosing handlers with `Exception>>outer` (protoST 58f1834): a resumption
    goes on from the signal and the block may still commit; an exception they end unwinds the
    block and aborts. An `Error`, or an exception that is not resumable, aborts at once and is
    passed. A `^` commits, also after a resumed exception. New test: `tx_do_exceptions.st`.
- Task 18 review fix round 3 (ruling R20b, re-review N3):
  - **A resumed `Error` no longer discards the block's writes.** Round 2 aborted at once on any
    `Error`, so a resumable one (`ZeroDivide`) that an enclosing handler resumed left the block
    running on an aborted transaction. Its writes were lost, or its next transaction message
    signalled `PBUserError`. Now the transaction is aborted exactly when an exception unwinds
    the block: a resumable `Error` goes through `outer` like any resumable exception. Only an
    exception that is not resumable aborts at once and is passed. `tx_do_exceptions.st` checks
    a resumed `ZeroDivide` (committed with its write), one the handler returns from (aborted)
    and a plain `Error` (aborted).
- `PBDatabase >> run:`, `run:retries:` and `run:retries:backoff:` with `proto_db`'s bounded
  exponential backoff with jitter (plan Task 19; `PBDatabase class >> backoffFor:low:high:random:`).
  Retries only `PBConflictError`; `PBOutcomeUnknownError` and every other error abort and propagate.
  New tests: `run_retries.st`, `run_backoff_bounds.st`, `run_no_retry.st`. A conflict-free wait is clamped to `high`; `backoff` is any two-element sequenceable collection.
- Round trip and write-side proofs (plan Task 20; tests only, no change to the library):
  - `tests/interop/st_to_py.sh`: protoST writes the shapes of spec 10.2 (three versions, every
    collection it can write, records, a mutable cell, the integer boundaries and the boxing
    threshold by code points) and `proto_db`'s verifier accepts them with an identical dump; a
    `proto_db` reader asserts the boundary keys and which strings are boxed. The helper is
    `_st_write_shapes.st`, because `_st_write_space.st` already serves the file storage tests.
  - `tests/interop/st_random_ops.sh`: seeded random operations on `PBList`, `PBDictionary`,
    `PBHashDictionary` and `PBSet` over 20 commits, `PBAvl check:` and a model comparison after
    each, then `proto_db`'s verifier over the whole space. `PBCountedSet` joined them in plan
    Task 22; `PBRepeatedKeysDictionary` writes are a non-goal of the prototype.
  - `tests/conformance/polyglot_rewrite.st`: rewriting the record that references the opaque
    atoms keeps them byte for byte at their original pointers; the commit writes no record of
    their types.
  - `tests/interop/lock_timeout.sh` with `hold_lock.py`: a protoST commit with a 50 ms
    `lockTimeout` while `proto_db` holds the lock ends in `PBTimeoutError`; with the lock
    released and 30000 ms it commits.
- The concurrency table of spec 10.4 (plan Task 21; tests only, no change to the library): the
  13 rows in `tests/interop/concurrency_cases.json`, plus row 7 with its roles swapped so that
  an unlogged remove is observable, in a neutral step vocabulary with `proto_db`'s recorded
  outcomes and final contents. Only the indexed-root case may record a refusal, and only
  `PBNotSupportedError`; both runners check it. `tests/interop/concurrency.sh` runs each row
  three times, ordered as plan call C12 (start A, start B, commit B, commit A): both transactions
  in `proto_db` (`py_case.py both`, which must give the recorded reference), protoST as A with
  `proto_db` as B, and `proto_db` as A with protoST as B (`_st_case.st`), and each language reads
  the other's final space. `tests/unit/concurrency_actors.st` runs the same table with two
  protoST actors driven step by step through Futures. Every row gives `proto_db`'s outcome, except
  the blind write onto an indexed root, where protoBaseST's documented `PBNotSupportedError`
  (spec 7.4) is asserted in place of `proto_db`'s merge.
- `PBCountedSet` writes and the D26 counter-transform merge (plan Task 22; `proto_db`
  `v2.0.0rc2` `proto_db/collections/sets.py`, `CountedSet`): `add:` and `remove:` (one
  occurrence; an absent element answers a new version with the same content) keep `count` and
  `totalCount`, file `(element, count)` entries in bucket tuples as `proto_db` does, and refuse at
  `add:` an element whose entry would nest past `MAX_VALUE_DEPTH` (wrapping 4, 1018 at most).
  Each call logs `('add' e)` or `('remove' e)`; `rebaseOnto:` composes the log per element into
  one counter transform `(removes, adds)` (`counter_net_effect`), applies it as
  `max(c - removes, 0) + adds` and logs it as `('transform' e removes adds)`, so concurrent
  increments are all kept and a rebased version rebases again. `PBIndexedCollection` gains
  `_withChanges:log:complete:` (a new version with any persisted fields changed). Tests:
  `tests/unit/counted_set_ops.st`, `tests/unit/rebase_counted_set.st`, the concurrency row
  `counted-set-blind-adds` (outcome generated by `proto_db`), and `PBCountedSet` in
  `tests/interop/_st_write_shapes.st` (with a blind merge read back by `proto_db`) and
  `tests/interop/_st_random_ops.st`.
- Task 22 review fix round 1: `_withChanges:log:complete:` refuses a field the class does not
  persist (`PBUserError` naming the fields), so a misspelled field is never dropped; the
  last-occurrence grouping of the net ops is one helper (`_PBOpLog orderKeysOf:` and
  `lastOccurrencesOf:do:`) shared by `PBIndexedCollection` and `PBCountedSet`; the concurrency
  table gains 12 counted set cases (`cs-*`: clamping, concurrent removes, replace, a
  read-modify-write conflict, mixed numbers, an absent root), with outcomes generated by
  `proto_db`, through one generic step `['counted set ops', r, blind|read|replace, op, e, ...]`
  that replaces `counted set add`; design spec 7.2 lists `proto_db`'s counted set log entries.
- Documentation (plan Task 24): the README is rewritten as the entry point of a proposal prototype
  (what it is, status, the two prominent boxes "Every collection message answers a new version"
  with the three Pharo clashes, and "`PBList` positions are zero-based", a quick start, the API
  mapping of design spec 5, how to run the tests). New: `docs/tutorial.md` (a guided ERP with the
  reasoning at each step), `docs/reference.md` (every public class and message), `docs/deviations.md`
  (every refusal and divergence, including the shapes protoBaseST cannot write), `docs/not-done.md`
  (the non-goals, the cuts and what was not proven) and `docs/decisions.md` (the maintainer's
  decisions, the planner's calls C1-C19 and every execution ruling, each with its cost). The
  detailed notes the old README carried moved to the reference and the deviations. New tests:
  `tests/docs/tutorial_snippets.st` runs every Smalltalk block of the tutorial in one session and
  asserts its `=> value` lines, `tests/docs/readme_quickstart.st` does the same for the README,
  and `tests/docs/tutorial_sync.sh` fails when a documented block is not in its test.
