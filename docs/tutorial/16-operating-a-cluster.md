# 16. Operating a cluster

<!-- example: examples/cluster/16_configuration.st -->
Program: [examples/cluster/16_configuration.st](../../examples/cluster/16_configuration.st).
Previous: [15. Failures and recovery](15-failures-and-recovery.md).

This chapter is the reference an operator needs: the options and the rules among them, the timers,
what `stats` reports, how to choose the durations, and an honest account of what the port does not
do and what is not proven. The full API is in [reference.md](../reference.md), and every
difference from `proto_db` is in [deviations.md](../deviations.md#cluster-mode).

## The options

`PBClusterCoordinator nodeId:peers:options:` takes a `Dictionary` of options, all of them named as
`proto_db`'s keyword arguments in camelCase. **Durations are Integer milliseconds** (the protoST
convention; `proto_db` takes float seconds). A configuration is validated when it is built: a bad
value, a rule broken or an unknown name is refused then, never discovered at run time.

| Option | Default | Meaning |
|---|---|---|
| `#leaseDuration` | 2000 | How long a grant blocks other holders, on the granter's clock (D). |
| `#driftMargin` | ⌈2D/3⌉ (the minimum) | The holder believes its lease for D − margin. |
| `#requestTimeout` | 250 | How long an attempt, a renewal, a recovery round or a query waits; also the TCP connect and write timeout. |
| `#sendReserve` | min(requestTimeout, belief // 4) | Least validity left before a round may send anything. |
| `#acquireTimeout` | 30000 | When a commit that cannot get a permission gives up with `PBTimeoutError`. |
| `#backoff` | `#(1 50)` | The jittered delay between lost attempts, (min, max). |
| `#startupGrace` | D + margin | Grants refused after a start. |
| `#persistInterval`, `#persistLag` | 50, 1000 | The persister's passes, and when a node persists another's commits (Task 25; nothing reads them yet). |
| `#ownerIdleRelease` | nil (off) | Ends a term whose own commits stopped asking (R80). |
| `#voters` | the first three ids | An explicit, odd voter set. |
| `#authKey` | nil | A `ByteArray` of at least 32 bytes: HMAC-SHA-256 on every frame. |
| `#transport`, `#clock`, `#seed` | nil | Test seams: a transport made by the caller, a clock block, a seeded incarnation. |

`#fetchTimeout`, `proto_db`'s option for tiered storage, is refused with `PBNotSupportedError`
naming Phase D (CC8): an option that would be accepted and ignored would be a silent divergence.

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

The rules, all from `proto_db`:

1. `driftMargin` ≥ ⌈2D/3⌉ and < D (R78b): the holder believes at most a third of the promise.
2. `requestTimeout` < the belief, D − margin: a request must be able to finish inside a lease.
3. `sendReserve` ≤ belief // 4 (R121): a larger reserve would refuse, by rule, the permissions an
   owner issues (an owner issues none with less than a quarter of the belief left).
4. `backoff` min ≤ max; `authKey` nil or at least 32 bytes; voters odd, distinct members.
5. Over a log that has served, `startupGrace` ≥ D + margin, checked when the space attaches
   (L17); a one-member cluster is exempt.

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
an abandoned term, a retried commit, an unknown outcome.

| Timer | Default | Drives (liveness only) |
|---|---|---|
| leaseDuration | 2000 ms | How long a grant blocks other holders on the granter's timer. |
| driftMargin | ⌈2/3 × leaseDuration⌉, the minimum | The holder's belief is leaseDuration − driftMargin, a third of the promise (R78b). |
| renewal | at half the belief left | When the owner renews while it has demand; a failed renewal ends the term only when a majority fenced it (R149). |
| permitFloor | a quarter of the belief left | No permission is issued with less; the owner renews first. |
| renewBackoff | requestTimeout / 4, at least 1 ms | After a renewal round neither won nor fenced, no renewal before the refusals' remaining, at least this, within the lease (R149a). |
| idleEnd | leaseDuration / 4 without demand | When an owner releases its term. |
| ownerIdleRelease | nil (off) | Ends a term whose own threads stopped asking (R80). |
| requestTimeout | 250 ms | How long an attempt, a renewal, a recovery round or a query waits. |
| sendReserve | min(requestTimeout, belief // 4) | Least validity left before anything acceptable is sent; less gives a retryable conflict (R121). |
| permissionDeadline | valid + requestTimeout | An owner without a done by then abandons the term (O6). |
| startupGrace | leaseDuration + driftMargin | Grants refused after a start (efficiency). |
| backoff | `#(1 50)` ms | Jittered delay between lost attempts. |
| wakeSpread | 3 ms | Random spread after a release wakes a requester. |
| straggle | 5 ms, factor 4 | Once a majority answered an undecided attempt, how long the rest are awaited (R39). |
| turnSilence | 50 ms, capped by requestTimeout | How long a member defers to the member a release named. |
| acquireTimeout | 30000 ms | When a permit request gives up with a timeout. |
| gatherAttempts | 3 | How many times a rejoin round asks a silent member again. |
| persist | persistInterval 50 ms, persistLag 1000 ms | Persister passes; when any node persists another's commits. |
| retryHold | hold 100 ms, wait 5 ms, 3 retries | Held retries under a permission. |

The claim that timers decide only liveness is tested, not just stated: the timer audit
(`tests/audit`, indexed by `tests/unit/sim_timer_audit.st`) runs a mixed workload with each row at a
tenth of its default, at ten times, and skewed between members, 3420 simulator runs in all, and the
safety checker must pass every one.

## Choosing the durations

- **Start with `proto_db`'s defaults** (maintainer decision Q6). They are tuned for a fast network
  and a fast build.
- **The belief must hold a whole round.** With a 2 s lease the belief is about 667 ms and the send
  reserve 167 ms. A round builds every queued commit of its node inside that window, and
  protoBaseST's build is slow (a design estimate of 50 to 70 ms per commit, not a measurement of
  the cluster). A round of one commit fits; a round of ten does not. The port stops adding commits
  to a round when the time left falls below the reserve plus the longest build measured in the
  round (CC11, a liveness-only addition to `proto_db`); the rest wait for the next permission. If
  a single transaction's build exceeds the belief, every round is refused, and the conflict says
  so, naming the build time and `leaseDuration` (CC18): lengthen the lease.
- **A longer lease costs failover time.** When an owner dies, nothing is issued until its grant
  expires on the voters' clocks: about one `leaseDuration`.
- **Short leases cost renewals and grace.** Every term renews at half its belief; every restart
  refuses grants for D + margin.
- **`acquireTimeout`** is how long a commit on the wrong side of a partition hangs before it says
  so. 30 s is gentle on transient faults and long for an interactive user.
- **Change one value, then re-check the rules above**: the configuration refuses a broken set, but
  only you know whether the set fits your build times.

## Reading `stats`

`coordinator stats` answers a fresh `Dictionary` keyed by `proto_db`'s names (CC24). The health
keys:

```smalltalk
stats := nodes first stats.
lesson check: 'the health keys'
  is: (#('healthy' 'fenced' 'tier_failed' 'rejoining' 'rejoin_blocked' 'failure') collect: [:k | stats at: k])
  equals: { true. false. false. false. nil. nil }.
```

| Key | Meaning |
|---|---|
| `'healthy'` | no fence and no failed tier |
| `'fenced'` | fenced for the life of the process by an internal error (chapter 13) |
| `'tier_failed'` | a write to the log failed: everything refused until reopened (R57) |
| `'failure'` | the reason of either, nil when healthy |
| `'rejoining'` | attached, healthy, rejoined marker not logged yet |
| `'rejoin_blocked'` | while rejoining, why the last round could not complete; nil otherwise |
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
- **Rejoins:** `'rejoins'`, `'rejoin_ballots'`.
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
  shares one directory; its options are refused (CC8), and a log written by a tiered node is refused
  (CC15). Multi-host deployments need a shared file system whose `flock` is reliable.
- **Pipelined permissions** (`proto_db`'s DEPTH 1, D55) are not ported: one permission at a time.
- **The runtime registry and format 5** of `proto_db` 2.0.0rc4 come later; the cluster writes
  format 4, which rc4 still reads.
- **Mixed clusters** of protoBaseST and `proto_db` nodes are a non-goal (maintainer ruling): the
  on-disk format and the protocol-13 frames are shared, the behaviour is not tested across
  implementations.
- **No encryption.** Frames are plaintext; `#authKey` authenticates them. Run on a trusted network.
- **Static membership**, at most 4096 members, and in practice about 16: every connection has its
  own reader actor.
- **No read-only barrier** (a barrier is a commit), and no notify.
- **A plain process must not open a member's directory.** protoBaseST refuses it; a `proto_db`
  `FileStorage` without a coordinator does not, and a root it published outside the cluster would be
  replaced by the next persisted cluster root, its write silently lost.

## What is not proven

Be as sceptical as the design is:

- The protocol has been tested in the **simulator** and through the **coordinator shell in one
  process**, not yet with real processes killed with `kill -9` (Tasks 27 and 28), and not with the
  commit path, which does not exist yet.
- `proto_db`'s 261 cluster tests are checked off one by one in `tests/unit/cluster_checklist.tsv`;
  the rows that need Tasks 23 to 28 are still marked deferred.
- The timer audit's floors must be re-measured after the R149 change (Task 30).
- **No throughput or latency figure exists** for a protoBaseST cluster (Task 29). Expect it to be
  slower than standalone mode, with more syncs per commit, and bounded for the whole cluster by one
  commit's build time.
- The work is one implementer's, reviewed task by task, against a reference implementation that
  itself is a release candidate.

## What to take away

- Options are milliseconds, validated at construction; the lease, the request timeout and the
  reserve must fit inside each other.
- Timers decide liveness only, and the audit tests it; choose them for your build times and for how
  long a failover may take.
- `stats` names health, leases, permissions, replication and misconfiguration as `proto_db` does.
- The port is the protocol over one shared directory; tiered storage, pipelining, format 5 and
  measurements are still to come.
