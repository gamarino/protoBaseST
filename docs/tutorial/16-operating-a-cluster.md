# 16. Operating a cluster

<!-- example: examples/cluster/16_configuration.st -->
Program: [examples/cluster/16_configuration.st](../../examples/cluster/16_configuration.st).
Previous: [15. Failures and recovery](15-failures-and-recovery.md).

This chapter is the reference an operator needs: the options and the rules among them, the timers,
what a commit costs, how to choose the durations, what `stats` reports, how to bring an existing
database into a cluster, and an honest account of
what the port does not do and what is not proven yet. The full API is in [reference.md](../reference.md), and every
difference from `proto_db` is in [deviations.md](../deviations.md#cluster-mode).

## The options

`PBClusterCoordinator nodeId:peers:options:` takes a `Dictionary` of options, named as
`proto_db`'s keyword arguments in camelCase, with two exceptions: `#authKey` is a protoBaseST
addition (a keyed cluster is not protocol 14 and cannot mix with `proto_db` nodes), and `#seed`
seeds the node's incarnation rather than `proto_db`'s back-off jitter. A configuration is validated
when it is built: a bad value, a rule broken or an unknown name is refused then, except the
startup grace over a used log, which is checked when the space attaches (rule 5 below).

| Option | Default | Meaning |
|---|---|---|
| `#leaseDuration` | 2000 | How long a grant blocks other holders, on the granter's clock (D). |
| `#driftMargin` | ⌈2D/3⌉ (the minimum) | The holder believes its lease for D − margin. |
| `#requestTimeout` | 250 | How long an attempt, a renewal, a recovery round or a query waits; also the TCP connect and write timeout of the transport the coordinator builds (a transport given by `#transport` keeps its own, 1000 ms by default). |
| `#sendReserve` | min(requestTimeout, belief // 4) | Least validity left before a round may send anything. |
| `#acquireTimeout` | 30000 | When a commit that cannot get a permission gives up with `PBTimeoutError`. |
| `#backoff` | `#(1 50)` | The jittered delay between lost attempts, (min, max). |
| `#startupGrace` | D + margin | Grants refused after a start. |
| `#persistInterval`, `#persistLag` | 50, 1000 | The persister's passes, and how long a committed root waits unpersisted before a node that did not commit it persists it (chapter 14, *Durability*). |
| `#ownerIdleRelease` | nil (off) | Ends a term whose own commits stopped asking. |
| `#voters` | the first three ids (every member of a cluster of fewer than three) | An explicit voter set. |
| `#authKey` | nil | A `ByteArray` of at least 32 bytes: HMAC-SHA-256 on every frame. A protoBaseST addition. |
| `#transport`, `#clock`, `#seed` | nil | Test seams: a transport made by the caller, a clock block, a seed for the incarnation. |

What every option must be:

- **Durations are Integer milliseconds** (the protoST convention; `proto_db` takes float
  seconds), at most `SmallInteger maxVal // 4000`. `#leaseDuration`, `#requestTimeout`,
  `#persistInterval` and, when given, `#ownerIdleRelease` must be positive; the others may be 0.
  `#backoff` is a pair of such values.
- **nil means the default**, as `proto_db`'s `None` does.
- **A key that is not a String** (or Symbol) is refused; so is a name nobody knows.
- `#fetchTimeout`, `proto_db`'s option for tiered storage, is refused with `PBNotSupportedError`
  naming Phase D: an option that would be accepted and ignored would be a silent divergence.

Everything else in the timer table below is either **derived** from these options or **fixed**:
you cannot set it, and an attempt (`#turnSilence`, say) is refused as an unknown cluster option.

## The rules among them

The program builds a configuration from the defaults and from a short test lease (the accessors of
`PBClusterConfig` answer microseconds):

```smalltalk
config := PBClusterConfig nodeId: 'n0' peers: peers options: Dictionary new.
lesson check: 'leaseDuration, requestTimeout, acquireTimeout by default'
  is: { config leaseDuration. config requestTimeout. config acquireTimeout } equals: #(2000000 250000 30000000).
```

```smalltalk
config := PBClusterConfig nodeId: 'n0' peers: peers options: (Dictionary new
  at: #leaseDuration put: 600; at: #requestTimeout put: 100; yourself).
lesson check: 'margin, belief, sendReserve, startupGrace'
  is: { config driftMargin. config belief. config sendReserve. config startupGrace }
  equals: #(400000 200000 50000 1000000).
```

The rules, `proto_db`'s except where noted:

1. `driftMargin` ≥ ⌈2D/3⌉ and < D: the holder believes at most a third of the promise.
2. `requestTimeout` < the belief, D − margin: a request must be able to finish inside a lease.
3. `sendReserve` ≤ belief // 4: a larger reserve would refuse, by rule, the permissions an owner
   issues (an owner issues none with less than a quarter of the belief left).
4. `backoff` min ≤ max. Voters: distinct members; odd and at least three in a cluster of three or
   more members; every member of a smaller one. And, a protoBaseST rule, `authKey` nil or at least
   32 bytes.
5. Over a log that has served, `startupGrace` ≥ D + margin, checked when the space attaches; a
   one-member cluster is exempt. Over fresh logs any grace is accepted.

Rule 2 is the one that surprises: shortening only the lease breaks it.

```smalltalk
lesson check: 'a 600 ms lease with the default 250 ms request timeout' signals: PBValidationError containing: 'belief'
  during: [refuse value: (Dictionary new at: #leaseDuration put: 600; yourself)].
lesson check: 'a send reserve above a quarter of the belief' signals: PBValidationError containing: 'sendReserve'
  during: [refuse value: (Dictionary new at: #leaseDuration put: 600; at: #requestTimeout put: 100; at: #sendReserve put: 60; yourself)].
```

Rule 5 is checked late because it depends on the disk, not on the configuration:

```smalltalk
restarted := make value: 'n2' value: (Dictionary new at: #startupGrace put: 0; yourself).
restarted start.
lesson check: 'a short startup grace over a log that served is refused' signals: PBValidationError containing: 'startupGrace'
  during: [PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted].
```

## The timers

`PBClusterConfig timerTable` answers one row per timer that applies at DEPTH 0 over shared storage:
its name, its default and what it drives. None of them decides an acceptance, an acknowledgement or
the truth of an outcome. Each one, when it fires, can only cause a conservative failure: a timeout,
an abandoned term, a retried commit, an unknown outcome. The column "Set by" says whether you can
change it: an option, a value derived from options, or a fixed constant of the protocol. The fixed
ones are internal: you cannot set them and need not. The Timer and Default columns are
`PBClusterConfig timerTable`'s, checked against it by `tests/docs/timer_table_sync.sh`; the table
generated from it, with its own wording of each row, is in [reference.md](../reference.md).

| Timer | Set by | Default | Drives (liveness only) |
|---|---|---|---|
| leaseDuration | `#leaseDuration` | 2000 ms | How long a grant blocks other holders on the granter's timer. |
| driftMargin | `#driftMargin` | ceiling(2/3 x leaseDuration), the minimum | The holder's belief is leaseDuration − driftMargin, a third of the promise. |
| renewal | derived: half the belief | at half the belief left | When the owner renews while it has demand; a failed renewal ends the term only when a majority fenced it (chapter 13). |
| permitFloor | derived: a quarter of the belief | a quarter of the belief left | No permission is issued with less; the owner renews first. |
| renewBackoff | derived from `#requestTimeout` | requestTimeout / 4, at least 1 ms | After a renewal round neither won nor fenced, no renewal before the refusals' remaining, at least this, within the lease. |
| idleEnd | derived: leaseDuration / 4 | leaseDuration / 4 without demand | How long an owner without demand keeps its term before releasing it. |
| ownerIdleRelease | `#ownerIdleRelease` | nil (off) | Ends a term whose own threads stopped asking. |
| requestTimeout | `#requestTimeout` | 250 ms | How long an attempt, a renewal, a recovery round or a query waits. |
| sendReserve | `#sendReserve` | min(requestTimeout, belief // 4) | Least validity left before anything acceptable is sent; less gives a retryable conflict. |
| permissionDeadline | derived: valid + requestTimeout | valid + requestTimeout | An owner without a done by then abandons the term. |
| startupGrace | `#startupGrace` | leaseDuration + driftMargin | Grants refused after a start (efficiency). |
| backoff | `#backoff` | #(1 50) ms | Jittered delay between lost attempts. |
| wakeSpread | fixed (internal) | 3 ms | A random spread, so that the members one release wakes do not all ask at the same instant. |
| straggle | fixed (internal) | 5 ms, factor 4 | Once a majority answered an attempt that is still undecided, how long the remaining answers are awaited. |
| turnSilence | fixed (internal), capped by requestTimeout | 50 ms, capped by requestTimeout | A release may name the member whose turn is next; the others keep quiet this long so that it can ask first. |
| acquireTimeout | `#acquireTimeout` | 30000 ms | When a permit request gives up with a timeout. |
| gatherAttempts | fixed (internal) | 3 | How many times a rejoin round asks a silent member again. |
| persist | `#persistInterval`, `#persistLag` | persistInterval 50 ms, persistLag 1000 ms | Persister passes; when any node persists another's commits. |
| retryHold | fixed (internal) | hold 100 ms, wait 5 ms, 3 retries | How long a round keeps its permission for a conflicting transaction that `run:` is about to retry (chapter 14). |

The claim that timers decide only liveness is meant to be tested, not just stated. The timer audit
(`tests/audit`, indexed by `tests/unit/sim_timer_audit.st`) runs a mixed workload with each row at a
tenth of its default, at ten times, and skewed between members, 3420 simulator runs in all, and the
safety checker must pass every one. Its state today, honestly:

- in the final verification the full timer audit (81 parts, 3420 simulator runs) ran twice at the
  final code: the first run had no violation but missed 36 floors by 1 to 7 commits, because 02d9826
  changes every schedule (bisected), so the floors were re-measured from it (7cbac4a); the second
  run passed whole at 7cbac4a in 2 h 22 min, serially;
- the *renewBackoff* parts got their floors in Task 30, re-measured with the others in Task 31;
- the *persist* row tests nothing: the persister is a shell outside the simulator (Task 25), so no
  rule reads its knobs and its runs equal the runs at the defaults; `cluster_persister.st` tests
  the persister itself.

What the default test run does check is the audit's configuration: every row has its files, and
each row's knob changes what the rules read (`sim_timer_audit.st`).

## What a commit costs

The obvious way to make a database faster is to add machines. A cluster that shares one database
cannot do that for writes, and the reason is in chapter 13: commits are ordered by one permission
at a time, across the whole cluster. The measurement below shows the price and where it goes.

It was taken with `bench/run_cluster.sh` on one machine, so read it as **indicative only**: an
AMD Ryzen 5 5500U (6 cores), Linux, a ZFS disk with real `fsync`, protoST 0.12.0, protoBaseST at
commit f5ec4b2, 2026-11-16, five interleaved runs of 120 transactions each, every cluster member a
protost process of its own on 127.0.0.1 with the default options. Every process counted the
commits it made and a verifier counted them again; a run whose counts differed would have been
refused. The full table and its caveats are in
[deviations.md](../deviations.md#cluster-mode-commits-per-second). Commits per second, from the
fastest of the five runs:

| Workload | Standalone | 1 member | 3 members |
|---|---|---|---|
| *tiny*: one writer per process, each on its own root | 46 commits/s | 28 commits/s | 26 commits/s |
| *conc-hot*: four writers per process, one shared key | 51 commits/s | 30 commits/s | 17 commits/s |

Three things to read in it:

- **A one-member cluster already pays most of the price** (0.60 of standalone on *tiny*). The
  design's expectation, not measured separately, is that each commit adds a synced append to the
  acceptor log and the round's actor messages to the same segment `fsync`.
- **Two more members add nothing, and on a hot key they cost a lot**: on disjoint roots three
  members make 0.93 times the commits of one, and on one hot key 0.57 times. Each commit waits for
  the one permission.
- **Where the time goes**, per commit at three members (medians): about 6 ms saving the
  transaction's records before asking (no permission held), about 18 ms building under the
  permission (11 ms on the hot key), about 12 ms from the replicate's send to the commit settled.
  These are costs per commit, not a latency: each is the mean of one stage, and the wait for a
  permission, the queueing and the segment sync are in no column. The build at three members is
  more than twice the build at one (7.4 ms); the likely cause, not established, is that a member
  builds on roots other members wrote, whose records it must read from disk.

Contention costs more in a cluster: the hot key needed 392 to 446 retries per 120 commits at three
members, against 86 to 106 standalone, and 51 rounds in 600 commits were refused by the send
reserve (retryable, nothing sent, retried by `run:`). Why those permissions ran short at the send
was not measured. No `proto_db` figure is shown: its cluster was not run on this workload, and
figures from other workloads do not compare.

## Choosing the durations

- **Start with `proto_db`'s defaults.** The maintainer chose to keep them, configurable. The
  measurement above used them; no study of other values has been made.
- **The belief must hold a whole round.** With a 2 s lease the belief is about 667 ms and the send
  reserve 167 ms, which leaves about 500 ms of builds per permission. Measured above, a small
  commit's build takes about 7 to 18 ms, so a round of about two dozen small commits fits
  (500 / 18 ≈ 28); a round of large transactions may not. The port stops adding commits
  to a round when the time left falls below the reserve plus the longest build measured in the
  round (a liveness-only addition to `proto_db`); the rest wait for the next permission. If a
  single transaction's build alone exceeds the belief, every round is refused, and the conflict
  says so, naming the build time and `leaseDuration`. The reserve refusals measured above are not
  that case: their builds were about 11 ms, and their cause was not measured.
- **A longer lease costs failover time.** When an owner dies, nothing is issued until its grant
  expires on the voters' clocks: about one `leaseDuration`.
- **Short leases cost renewals and grace.** Every term renews at half its belief; every restart
  refuses grants for D + margin.
- **`acquireTimeout`** is how long a commit on the wrong side of a partition hangs before it says
  so. 30 s is gentle on transient faults and long for an interactive user.
- **Change one value, then re-check the rules above**: the configuration refuses a broken set, but
  only you know whether the set fits your build times.

## Reading `stats`

`coordinator stats` answers a fresh `Dictionary` keyed by `proto_db`'s names, plus a few of
protoBaseST's own (`'messages_ignored'`, and the transports' frame counters). The program asks for
one permission by hand, so that the counters have something to count, and then reads the health
keys:

```smalltalk
permit := nodes first _permit waitWithin: 60000.
(nodes first _done: permit outcome: #none) waitWithin: 60000.
stats := nodes first stats.
lesson check: 'the health keys'
  is: (#('healthy' 'fenced' 'tier_failed' 'rejoining' 'rejoin_blocked' 'failure') collect: [:k | stats at: k])
  equals: { true. false. false. false. nil. nil }.
lesson check: 'the counters count what happened: grants given, a permission issued'
  isTrue: ((nodes inject: 0 into: [:sum :node | sum + (node stats at: 'grants_given')]) > 0
    and: [(nodes inject: 0 into: [:sum :node | sum + (node stats at: 'permits_issued')]) > 0]).
```

| Key | Meaning |
|---|---|
| `'healthy'` | no fence, no failed tier, and a persister that did not stop |
| `'fenced'` | fenced for the life of the process by an internal error (chapter 13) |
| `'tier_failed'` | a write to the log failed: everything refused until reopened |
| `'failure'` | the reason of any of them, nil when healthy |
| `'rejoining'` | attached, healthy, rejoined marker not logged yet |
| `'rejoin_blocked'` | while rejoining, why a rejoin that has its answers cannot complete (its ballot not confirmed by enough witnesses, an unreadable adopted root, a failed write); nil while it is still gathering answers, for example with too few live witnesses (chapter 15) |
| `'persisting'` | false once the persister of the node's space stopped after an unexpected internal error; the node still grants, acknowledges and commits (persistence is off the commit path), and `sync:` fails at once with `PBUnexpectedError` |
| `'dispatch_seconds_max'` | the longest single dispatcher step, in seconds |

The counters start at zero. The ones to watch:

- **Leases:** `'attempts'`, `'acquired'`, `'lost_attempts'`, `'ownerships'`, `'renewals'`,
  `'renewal_failures'`, `'terms_fenced'`, `'terms_abandoned'`, `'terms_released_idle_local'`; at
  the voters, `'grants_given'`, `'refused'`, `'grants_refused_no_storage'`.
- **Permissions:** `'permits_issued'`, `'permits_refused'`, `'permits_held'`,
  `'permit_requests_sent'`, `'permit_requests_retried'`, `'sends_refused_reserve'` (a rising count
  means builds do not fit the belief).
- **Replication:** `'replications'`, `'accepted'`, `'replication_failures'`, `'recoveries'`,
  `'storage_root_reads'`.
- **Rejoins:** `'rejoins'` (completed), `'rejoin_ballots'` (completed by a ballot).
- **Misconfiguration:** `'config_mismatches'` (a member with another voter set),
  `'messages_ignored'` (a sender that is not a member, or the node itself), `'stale_replies'` (a
  reply to another incarnation), and the transports' `'frames_rejected'` and
  `'connections_dropped'` (malformed frames, or a key on one side only). A misconfigured member is
  dropped and counted, never allowed into a quorum.
- **Two names that look alike:** `'messages_ignored'` counts messages whose *sender* is not
  another member; `'ignored_messages'` counts valid messages from a member whose *type* a node
  never sends at DEPTH 0 over shared storage (`'records'`, `'warm'`, `'store'`, `'propose'`,
  `'fetch'`, `'fetched'`, `'commit_query'`, `'commit_info'`: tiered storage and pipelining). In a protoBaseST
  cluster both stay at 0; a rising `'ignored_messages'` means a member speaks a protocol this
  port does not (a `proto_db` node with tiered storage, say).
- **Slow steps:** `'dispatch_slow'`, dispatcher steps over 10 ms.

## Bringing an existing database into a cluster

Most clusters start from a database that already exists. Stop every process that has the
directory open, then open it on every member as chapter 14 does: `PBFileStorage clusterPath:` on
the same directory, and `PBObjectSpace storage:coordinator:` with each member's coordinator. Nothing
has to be exported or converted first:

- The current root of a standalone space has no cluster fields. The members read it as a root of
  term 0, at the storage's epoch, which is `proto_db`'s rule too.
- The first member to obtain a lease takes that root as its base. Its first commit becomes the
  first cluster root, and that root's `clusterPrevious` link is the old plain root. The history
  of every database is kept.
- Every member reads the old data at once, and `proto_db` 2.0.0rc4 reads the converted directory
  like any other cluster space.

`tests/unit/cluster_standalone_into_cluster.st` does this with a space written by protoBaseST.
`tests/interop/standalone_into_cluster.sh` does it with a space written by protoBaseST and with
one written by `proto_db`, and then has `proto_db` read the result.

**The move is one way.** As soon as a member opens the directory, the directory holds `cluster/`,
where the members keep their acceptor logs. From then on, `PBFileStorage path:` refuses the
directory with `PBNotSupportedError`. A plain space also refuses a current root that carries a
`cluster_term`. There are two reasons:

- A standalone writer takes no write permission, so the root it publishes is outside the
  cluster's order of roots.
- The acceptor logs in `cluster/` still hold the leases the members granted and the roots they
  accepted. The next cluster commit would build on those logs, and the next persisted cluster
  root would replace the standalone write: that write would be silently lost.

To get the data back into a standalone space, copy it: read each database through a cluster
member, and write its root objects into a fresh directory opened with `PBFileStorage path:`. The
copy starts a new history. `proto_db`'s own `FileStorage` does not refuse a cluster directory.
That route is not tested here, and it is safe only when every member is stopped for good.

## What the port does not do

- **Tiered storage** (`proto_db`'s per-node local logs plus an object store, bounded replication,
  `'fetch'`, `'warm'`, the kind-5 and kind-6 log entries) is Phase D, not approved yet. Every member
  shares one directory; its options are refused, and a log written by a tiered node is refused.
  Multi-host deployments need a shared file system whose `flock` is reliable.
- **Pipelined permissions** (`proto_db`'s DEPTH 1) are not ported: one permission at a time, the
  limit measured above.
- **The runtime registry and format 5** of `proto_db` 2.0.0rc4 (its decision D62) are known and
  not adopted: protoBaseST writes format 4, which rc4 still reads and writes for data without the
  feature, and **refuses format 5** with `PBNotSupportedError` rather than misread it. The registry
  gets its own plan after the cluster work merges.
- **Mixed clusters** of protoBaseST and `proto_db` nodes are a non-goal (maintainer ruling): the
  on-disk format and the protocol-14 frames are shared, the behaviour is not tested across
  implementations, and a cluster with `#authKey` cannot mix at all.
- **No encryption.** Frames are plaintext; `#authKey` authenticates them. Run on a trusted network.
- **Static membership**, at most 4096 members, and in practice about 16 (a planning estimate, not
  measured): every connection has its own reader actor.
- **No read-only barrier** (a barrier is a commit that writes), and no notify.
- **A plain process must not open a member's directory.** protoBaseST refuses it; a `proto_db`
  `FileStorage` without a coordinator does not, and a root it published outside the cluster would be
  replaced by the next persisted cluster root, its write silently lost.

## What is not proven yet

Be as sceptical as the design is:

- The protocol is tested in the **simulator**, through the **coordinator shell in one process**,
  and with **real processes** killed with `kill -9` (chapter 15). The real-process tests ran three
  times each, with drawn seeds: evidence, not proof. Nothing ran on several hosts, on a network
  file system, with more than five members, or for hours.
- `proto_db`'s 298 cluster tests at `v2.0.0rc4` each have a row in
  `tests/unit/cluster_checklist.tsv`: 223 ported, 75 not applicable (tiered storage, DEPTH 1, a
  Python-only API), none deferred. A ported row is a check of the same property, not the same code.
- **The final verification passed, in a simulator:** the long soak ran every simulator family at
  commit 02d9826 on protoCore 3.6.0 and protoST 0.12.0: sim_harness, sim_base_choice, sim_rejoin,
  sim_base_seeds_a, sim_base_seeds_b and sim_grants at 5000 seeds each, sim_leases_terms_a and
  sim_leases_terms_b at 2000, sim_acceptance and sim_permits at 1000, sim_round_rules at 400 and
  sim_leases at 100 (five families one after another, then the other seven at once; each run is
  deterministic per seed), and every one passed. An earlier soak (Task 30) failed one check of
  sim_rejoin at 7 of its 5000 seeds, with no safety violation: the simulator let the acceptor's
  reports reach the dispatcher out of order, which no real shell does. It was fixed in 02d9826 and
  the whole soak ran again. The timer audit passed as described above. "Timers decide liveness
  only" rests on those seeds, not on a proof.
- The figures above are one machine's, on one workload shape, with at most three members. Failover
  time and latency per commit were not measured, and nothing heavier than four writers per
  process was tried.
- The work is one implementer's, reviewed task by task, against a reference implementation that
  itself is a release candidate.

## What to take away

- Options are Integer milliseconds, validated at construction; the lease, the request timeout and
  the reserve must fit inside each other. The other timers are derived or fixed.
- Timers decide liveness only; the audit is built to test it and runs in full before the release.
  Choose the durations for your build times and for how long a failover may take.
- `stats` names health, leases, permissions, replication and misconfiguration as `proto_db` does,
  with a few counters of its own.
- A cluster costs throughput (on one machine, about half of standalone for small commits on
  disjoint roots, a third on a hot key) and buys survival of a member's failure; more members add
  safety, not speed.
- The port is the protocol over one shared directory; tiered storage and pipelining are still to
  come, and format 5 is refused.
