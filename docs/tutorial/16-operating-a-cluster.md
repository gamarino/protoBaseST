# 16. Operating a cluster

<!-- example: examples/cluster/16_configuration.st -->
Program: [examples/cluster/16_configuration.st](../../examples/cluster/16_configuration.st).
Previous: [15. Failures and recovery](15-failures-and-recovery.md).

This chapter is the reference an operator needs: the options and the rules among them, the timers,
what `stats` reports, how to choose the durations, and an honest account of what the port does not
do and what is not tested yet. The full API is in [reference.md](../reference.md), and every
difference from `proto_db` is in [deviations.md](../deviations.md#cluster-mode).

## The options

`PBClusterCoordinator nodeId:peers:options:` takes a `Dictionary` of options, named as
`proto_db`'s keyword arguments in camelCase, with two exceptions: `#authKey` is a protoBaseST
addition (a keyed cluster is not protocol 13 and cannot mix with `proto_db` nodes), and `#seed`
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
| `#persistInterval`, `#persistLag` | 50, 1000 | The persister's passes, and when a node persists another's commits (Task 25; nothing reads them yet). |
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
ones are internal: you cannot set them and need not.

| Timer | Set by | Default | Drives (liveness only) |
|---|---|---|---|
| leaseDuration | `#leaseDuration` | 2000 ms | How long a grant blocks other holders on the granter's timer. |
| driftMargin | `#driftMargin` | ⌈2/3 × leaseDuration⌉, the minimum | The holder's belief is leaseDuration − driftMargin, a third of the promise. |
| renewal | derived: half the belief | at half the belief left | When the owner renews while it has demand; a failed renewal ends the term only when a majority fenced it (chapter 13). |
| permitFloor | derived: a quarter of the belief | a quarter of the belief left | No permission is issued with less; the owner renews first. |
| renewBackoff | derived from `#requestTimeout` | requestTimeout / 4, at least 1 ms | After a renewal round neither won nor fenced, no renewal before the refusals' remaining, at least this, within the lease. |
| idleEnd | derived: leaseDuration / 4 | 500 ms | How long an owner without demand keeps its term before releasing it. |
| ownerIdleRelease | `#ownerIdleRelease` | nil (off) | Ends a term whose own threads stopped asking. |
| requestTimeout | `#requestTimeout` | 250 ms | How long an attempt, a renewal, a recovery round or a query waits. |
| sendReserve | `#sendReserve` | min(requestTimeout, belief // 4) | Least validity left before anything acceptable is sent; less gives a retryable conflict. |
| permissionDeadline | derived: valid + requestTimeout | | An owner without a done by then abandons the term. |
| startupGrace | `#startupGrace` | leaseDuration + driftMargin | Grants refused after a start (efficiency). |
| backoff | `#backoff` | `#(1 50)` ms | Jittered delay between lost attempts. |
| wakeSpread | fixed (internal) | 3 ms | A random spread, so that the members one release wakes do not all ask at the same instant. |
| straggle | fixed (internal) | 5 ms, factor 4 | Once a majority answered an attempt that is still undecided, how long the remaining answers are awaited. |
| turnSilence | fixed (internal), capped by requestTimeout | 50 ms | A release may name the member whose turn is next; the others keep quiet this long so that it can ask first. |
| acquireTimeout | `#acquireTimeout` | 30000 ms | When a permit request gives up with a timeout. |
| gatherAttempts | fixed (internal) | 3 | How many times a rejoin round asks a silent member again. |
| persist | `#persistInterval`, `#persistLag` | 50 ms, 1000 ms | Persister passes; when any node persists another's commits. |
| retryHold | fixed (internal) | hold 100 ms, wait 5 ms, 3 retries | How long a round keeps its permission for a conflicting transaction that `run:` is about to retry (chapter 14). |

The claim that timers decide only liveness is meant to be tested, not just stated. The timer audit
(`tests/audit`, indexed by `tests/unit/sim_timer_audit.st`) runs a mixed workload with each row at a
tenth of its default, at ten times, and skewed between members, 3420 simulator runs in all, and the
safety checker must pass every one. Its state today, honestly:

- the audit's per-part figures were measured when it was built; since the renewal back-off
  changed, the full run is not repeated task by task: it runs once, in the final verification
  phase (Task 30), on the commit that is to be released;
- the *renewBackoff* parts have no measured floors yet: they are measured in Task 30;
- the *persist* row tests nothing until the persister exists (Task 25): no rule reads it, so its
  runs equal the runs at the defaults.

What the default test run does check is the audit's configuration: every row has its files, and
each row's knob changes what the rules read (`sim_timer_audit.st`).

## Choosing the durations

- **Start with `proto_db`'s defaults.** The maintainer chose to keep them, configurable; this port
  has no measurement of its own to tune them by yet.
- **The belief must hold a whole round.** With a 2 s lease the belief is about 667 ms and the send
  reserve 167 ms. A round builds every queued commit of its node inside that window, and
  protoBaseST's build is slow (a design estimate of 50 to 70 ms per commit, not a measurement of
  the cluster). A round of one commit fits; a round of ten does not. The port stops adding commits
  to a round when the time left falls below the reserve plus the longest build measured in the
  round (a liveness-only addition to `proto_db`); the rest wait for the next permission. If a
  single transaction's build exceeds the belief, every round is refused, and the conflict says so,
  naming the build time and `leaseDuration`: lengthen the lease.
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
| `'healthy'` | no fence and no failed tier |
| `'fenced'` | fenced for the life of the process by an internal error (chapter 13) |
| `'tier_failed'` | a write to the log failed: everything refused until reopened |
| `'failure'` | the reason of either, nil when healthy |
| `'rejoining'` | attached, healthy, rejoined marker not logged yet |
| `'rejoin_blocked'` | while rejoining, why a rejoin that has its answers cannot complete (its ballot not confirmed by enough witnesses, an unreadable adopted root, a failed write); nil while it is still gathering answers, for example with too few live witnesses (chapter 15) |
| `'persisting'` | always true until the persister exists (Task 25) |
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
- **Slow steps:** `'dispatch_slow'`, dispatcher steps over 10 ms.

## What the port does not do

- **Commits and reads through the coordinator, and the persister** are Tasks 23 to 25: until they
  land, a cluster forms, elects owners and issues permissions, but cannot commit a database.
  Chapters 14 and 15 mark every block that waits for them.
- **Tiered storage** (`proto_db`'s per-node local logs plus an object store, bounded replication,
  `'fetch'`, `'warm'`, the kind-5 and kind-6 log entries) is Phase D, not approved yet. Every member
  shares one directory; its options are refused, and a log written by a tiered node is refused.
  Multi-host deployments need a shared file system whose `flock` is reliable.
- **Pipelined permissions** (`proto_db`'s DEPTH 1) are not ported: one permission at a time.
- **The runtime registry and format 5** of `proto_db` 2.0.0rc4 come later; the cluster writes
  format 4, which rc4 still reads.
- **Mixed clusters** of protoBaseST and `proto_db` nodes are a non-goal (maintainer ruling): the
  on-disk format and the protocol-13 frames are shared, the behaviour is not tested across
  implementations, and a cluster with `#authKey` cannot mix at all.
- **No encryption.** Frames are plaintext; `#authKey` authenticates them. Run on a trusted network.
- **Static membership**, at most 4096 members, and in practice about 16 (a planning estimate, not
  measured): every connection has its own reader actor.
- **No read-only barrier** (a barrier is a commit that writes), and no notify.
- **A plain process must not open a member's directory.** protoBaseST refuses it; a `proto_db`
  `FileStorage` without a coordinator does not, and a root it published outside the cluster would be
  replaced by the next persisted cluster root, its write silently lost.

## What is not tested yet

Be as sceptical as the design is:

- The protocol has been tested in the **simulator** and through the **coordinator shell in one
  process**, not yet with real processes killed with `kill -9` (Tasks 27 and 28), and not with the
  commit path, which does not exist yet.
- `proto_db`'s 261 cluster tests are checked off one by one in `tests/unit/cluster_checklist.tsv`;
  the rows that need Tasks 23 to 28 are still marked deferred.
- The full timer audit runs in the final verification phase (Task 30), which also measures the
  *renewBackoff* floors (above).
- **No throughput or latency figure exists** for a protoBaseST cluster (Task 29). Expect it to be
  slower than standalone mode, with more syncs per commit. With one permission at a time across the
  whole cluster, its throughput is at most one round per permission round trip plus the round's
  builds, whatever the number of members.
- The work is one implementer's, reviewed task by task, against a reference implementation that
  itself is a release candidate.

## What to take away

- Options are Integer milliseconds, validated at construction; the lease, the request timeout and
  the reserve must fit inside each other. The other timers are derived or fixed.
- Timers decide liveness only; the audit is built to test it and runs in full before the release.
  Choose the durations for your build times and for how long a failover may take.
- `stats` names health, leases, permissions, replication and misconfiguration as `proto_db` does,
  with a few counters of its own.
- The port is the protocol over one shared directory; tiered storage, pipelining, format 5 and
  measurements are still to come.
