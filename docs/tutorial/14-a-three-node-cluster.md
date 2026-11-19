# 14. A three-node cluster

<!-- example: examples/cluster/14_three_nodes.st -->
<!-- example: examples/cluster/14_three_nodes_tcp.st -->
<!-- example: examples/cluster/14_cluster_commits.st -->
Programs: [examples/cluster/14_three_nodes.st](../../examples/cluster/14_three_nodes.st) (in one
process), [14_three_nodes_tcp.st](../../examples/cluster/14_three_nodes_tcp.st) (over TCP), and
[14_cluster_commits.st](../../examples/cluster/14_cluster_commits.st) (commits, reads and
durability).
Previous: [13. The ideas behind cluster mode](13-cluster-concepts.md). Next: [15. Failures and recovery](15-failures-and-recovery.md).

> **What the programs show.** The first two programs start members, form a cluster and watch
> its permissions and `stats`; the third commits, reads and waits for durability with `sync:`.
> All three run in one process, for brevity. The same API with every member in a process of its
> own, killed with `kill -9`, is exercised by `tests/cluster/real_*.sh` (chapter 15).

## A member

A member of a cluster is a `PBClusterCoordinator`. It is built from three things: its own id, the
list of every member, and its options.

```smalltalk
ids := #('n0' 'n1' 'n2').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.
```

Every member is configured with **the same** peer list: ranks, voters and the voter fingerprint are
computed from it (chapter 13). A member configured with another voter set is ignored by the
others; other differences (a learner, a host, a port) are not detected, so keep the list identical
everywhere. A `PBPeer`
names the host and port its member listens on. The three members of this first program live in one
process, so the address is not used: their messages travel over a `PBInProcessNetwork`, which the
simulator's tests use too, and which can drop, duplicate and partition (chapter 15).

```smalltalk
options := [:id | Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #transport put: network endpoint;
  yourself].
```

Options are milliseconds. `proto_db`'s defaults (a 2000 ms lease, 250 ms requests) are the
defaults here too; the lesson shortens them so that it runs in a second. They are liveness
settings only. They are also not independent: with a 600 ms lease the belief is 200 ms, and the
default 250 ms request timeout no longer fits in it, so the lesson sets 100 ms (chapter 16 has the
rules). `#transport` gives each member its own endpoint of the network; without it a member
listens with TCP on its peer's port.

```smalltalk
nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (options value: id)].
nodes do: [:node | node start].
lesson check: 'every coordinator runs' isTrue: (nodes allSatisfy: [:node | node isRunning]).
```

`start` starts the member's actors and its transport. The member is running, but it has no disk
yet: until a log is attached it refuses every request (`'no_storage'`) and answers queries
`'unknown'`, so a half-started member never counts as a witness.

## Attaching the shared directory

Each member opens the **same** directory, in cluster mode, and gives it to its coordinator:

```smalltalk
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
lesson check: 'each node has its acceptor log in cluster/'
  isTrue: (ids allSatisfy: [:id | (dir / 'cluster' / (id , '.roots')) exists]).
lesson check: 'the space is empty' is: spaces first listDatabases equals: #().
```

`PBFileStorage clusterPath:` opens a storage that may hold a cluster's files; `PBFileStorage
path:` keeps refusing such a directory, and `PBObjectSpace storage:` refuses a cluster-mode storage:
the mode is chosen when the storage is opened, never guessed. `storage:coordinator:` opens
the member's **shared tier**, whose acceptor log is `cluster/<id>.roots`, and attaches it to the
coordinator before it answers the space. The log takes an `flock` of its own,
`cluster/<id>.roots.lock`, so a second process started with the same id is refused at once
(chapter 15) instead of voting twice.

The directory now looks like this:

```text
space/
  space.root              written only by a persister, never by a commit
  <segments>.seg          records, shared by every member
  cluster/
    n0.roots  n0.roots.lock
    n1.roots  n1.roots.lock
    n2.roots  n2.roots.lock
```

The caller owns the space: `close` detaches the tier and closes the log, and the coordinator
keeps running. Close the spaces before you stop the coordinators.

## A new cluster forms by itself

Three empty logs: each member starts *rejoining* (chapter 13). Each asks the others, finds that
every other voter answered, none holds a root and none has promised a term, and completes as a
cluster's first start, without a ballot.

That takes a moment, and the program must wait for it. It never sleeps for a fixed time; it polls
a condition:

```smalltalk
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
```

`until value: aBlock` evaluates the block every 10 ms until it answers true, for at most 60 s, and
answers its last value. That is the only way any program of these chapters waits: the deadline
turns a hang into a failure, and no check reads a duration.

```smalltalk
lesson check: 'every node finishes joining'
  isTrue: (until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]).
stats := nodes collect: [:node | node stats].
lesson check: 'every node is healthy' isTrue: (stats allSatisfy: [:s | (s at: 'healthy') and: [(s at: 'fenced') not]]).
lesson check: 'no rejoin needed a ballot' isTrue: (stats allSatisfy: [:s | (s at: 'rejoin_ballots') = 0]).
```

A member's `stats` is a `Dictionary` with `proto_db`'s names: the health keys (`'healthy'`,
`'fenced'`, `'tier_failed'`, `'rejoining'`, `'rejoin_blocked'`, `'failure'`) and the counters
(chapter 16).

## A write permission, by hand

Commits ask for permissions themselves (see *Committing*). To watch the owner at work, the lesson
sends the message the commit path sends, `_permit`. The underscore marks it private: an
application never sends it.

```smalltalk
permit := nodes first _permit waitWithin: 60000.
lesson say: 'term ' , permit term printString , ', owner ' , permit owner.
lesson check: 'the low 12 bits of the term are the owner''s rank'
  is: permit term \\ 4096 equals: (ids indexOf: permit owner) - 1.
```

`_permit` answers a `Future`. Nobody owned a term, so n0 tried to own one: it asked the voters
for a ballot of rank 0, won two promises of three, and issued itself the permission. A run printed
`term 12288, owner n0`: 12288 is 3 × 4096 + 0, the third ballot of rank 0. The earlier attempts
did not win because of the startup grace: for its `startupGrace` after `start` (1 s with this
lesson's 600 ms lease) every member, including one at a cluster's first start, refuses grants as
`'starting'`. `proto_db` does the same; its own tutorial starts its first cluster with a grace of
0, which fresh logs allow. The lessons keep the default, so that what you see here is what a
restarted member does. The number varies from run to run; the rank in its low bits does not.

```smalltalk
done := (nodes first _done: permit outcome: #none) waitWithin: 60000.
lesson check: 'the permission is ended' is: done equals: true.
```

Every permission ends with a report to the owner: `#committed`, `#unknown`, or `#none` (nothing
acceptable was sent). Until it ends the owner issues no other permission (DEPTH 0), and a holder
that never reports is timed out at `valid + requestTimeout`, when the owner abandons the term:
an owner never waits for ever on a dead holder.

## The same cluster over TCP

The second program changes one thing: the transport. A deployment writes fixed ports in its peer
list and lets each coordinator listen on its own; the lesson asks the operating system for free
ports first, so that it can run anywhere, and hands each coordinator its listening transport:

```smalltalk
transports := ids collect: [:id | PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1')].
peers := (1 to: 3) collect: [:i | PBPeer nodeId: (ids at: i) host: '127.0.0.1' port: (transports at: i) port].
```

```smalltalk
nodes := (1 to: 3) collect: [:i |
  PBClusterCoordinator nodeId: (ids at: i) peers: peers options: (Dictionary new
    at: #leaseDuration put: 600;
    at: #requestTimeout put: 100;
    at: #transport put: (transports at: i);
    yourself)].
```

Everything else is the first program. Frames are a 4-byte length and a msgpack map, protocol 14
of `proto_db` (`v2.0.0rc4`), byte for byte. Connections are one-way: a member writes only on the connections it
opened and reads only from those it accepted, with one sender actor per peer, so a dead peer
delays nobody else. The transport counts its frames:

```smalltalk
sent := transports inject: 0 into: [:sum :t | sum + (t stats at: 'frames_sent')].
lesson check: 'frames travelled' isTrue: sent > 0.
lesson check: 'no frame was rejected'
  is: (transports inject: 0 into: [:sum :t | sum + (t stats at: 'frames_rejected')]) equals: 0.
```

The link is plaintext and, without a key, unauthenticated, exactly as `proto_db`'s: run a cluster
on a trusted network only. The optional `#authKey` adds an HMAC to every frame (chapter 16); it
authenticates, it does not encrypt.

## Committing

> The blocks of this section come from `examples/cluster/14_cluster_commits.st`. It uses a 3000 ms lease: a commit's
> build and replication must fit within the belief, and the 200 ms belief of a 600 ms lease is
> shorter than a build may take on a loaded machine (CC18, `PBConflictError` naming `sendReserve`).

In cluster mode a commit looks exactly like a standalone one. `newDatabase:` is a commit too:

```smalltalk
shop := (spaces at: 1) newDatabase: 'shop'.
shop run: [:t |
  t setRootObject: 'counter' value: 0.
  t setRootObject: 'tokens' value: t newDictionary].
```

Behind it, the commit is queued on the space's round runner, which follows the diagram of
chapter 13:

1. the transaction's new records are written to the shared segment;
2. the runner asks the owner for a write permission;
3. it builds every commit queued on the node on the permission's base, one after the other;
4. it makes every record durable, with one sync of the shared segment;
5. it sends the new root to the voters (`'replicate'`);
6. it waits for a majority of acknowledgements, within the permission;
7. it reports the `'done'` to every member, and answers the waiting commits.

Your code waits only on the commit itself.

Those steps are not free, and it helps to know where the time goes. In a first, indicative
measurement (chapter 16 has the conditions and the table), a small commit on three member
processes cost about 6 ms in step 1, which needs no permission, about 18 ms in step 3, the build
under the permission, and about 12 ms in steps 5 and 6, from the replicate's send to the commit
settled. Step 4, the segment sync, is not in any measured column. These are costs per commit,
not a latency: each is the mean of one stage, and the wait for a permission and the queueing are
in no column, so they do not add up to how long a commit takes. Steps 3 to 6 run under the
cluster's one permission, so they bound how many commits the whole cluster makes per second;
step 1 does not, which is why the commit path saves the records *before* asking.

A commit now has **three** outcomes, so a careful workload writes a value unique to each commit,
a token, and keeps the unknown ones apart:

```smalltalk
1 to: 10 do: [:i |
  (1 to: 3) do: [:k |
    token := (ids at: k) , '-' , i printString.
    [(dbs at: k) run: [:t |
        t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1.
        t setRootObject: 'tokens' value: ((t getRootObject: 'tokens') setAt: token value: k)]
       retries: 100.
     acked add: token]
      on: PBOutcomeUnknownError do: [:e | unknown add: token. e return: nil].
    epochs add: (spaces at: k) committedEpoch]].
```

`run:` retries a `PBConflictError` (nothing left the node, so a retry cannot apply the work twice)
and never retries a `PBOutcomeUnknownError`. Chapter 15 shows how the tokens settle the unknown
ones. Both roots are read and written, so concurrent commits conflict and `run:` retries them,
exactly as in chapter 5. Under a hot key a
round keeps its permission for a conflicting transaction that `run:` is about to retry, so the
retry builds on the root just committed instead of losing the next turn (held retries).

## Reading

> Reads through the coordinator are tested by `tests/unit/cluster_reads.st`,
> `cluster_reads_restarts.st` and `cluster_reads_majority.st`.

A read in cluster mode takes the newest root **its node knows committed**. It sends nothing and
never waits, apart from two cases (below): the confirmation after an attach, or after
`forceRejoin` on a survivor, and a recovery from the peers when the node knows no committed root
at all. The price: it may miss a commit another node acknowledged a moment ago, because the
node learns that commit from a `'done'` message, asynchronously, and no bound on that delay is
promised. The snapshot is always a state that was committed, never a mixture.

When a read must see every commit acknowledged before it started, make a commit first: any
commit that writes something and returns normally is a **barrier**, because its permission round
makes the node learn the newest root before it builds (a base below an acknowledged commit would
lose it, which the protocol forbids). `newDatabase:` is one too: as in `proto_db` it is a commit
under a permission, so n1 creating a database of its own sees the one n0 created, and this check
confirms it:

```smalltalk
(spaces at: 2) newDatabase: 'n1-scratch'.
lesson check: 'after its own commit n1 sees the database n0 made'
  isTrue: ((spaces at: 2) listDatabases includes: 'shop').
```

The usual barrier is a `run:` that writes the root `'_read_barrier'`, as in `proto_db`; then the
read:

```smalltalk
(dbs at: 3) run: [:t | t setRootObject: '_read_barrier' value: true].
tr := (dbs at: 3) newTransaction.
counter := tr getRootObject: 'counter'.
tokens := tr getRootObject: 'tokens'.
tr abort.
lesson check: 'every acknowledged commit is present' isTrue: (acked allSatisfy: [:t | (tokens getAt: t) notNil]).
lesson check: 'acknowledged <= counter <= acknowledged + unknown'
  isTrue: (counter >= acked size and: [counter <= (acked size + unknown size)]).
lesson check: 'the counter is the number of tokens: no commit applied twice' is: counter equals: tokens count.
```

Two conditions make a barrier a barrier. It must **write** something: a transaction that writes
nothing commits at once without a permission and teaches the node nothing. And it must **return
normally**: an unknown outcome or a timeout means the barrier did not hold. Its cost is permanent:
every barrier is a version in `history`. Use it where the guarantee is worth a commit, and plain
local reads elsewhere. (There is no read-only barrier; `proto_db` does not have one either.)

A node that attaches its log knows only what the log recorded; its own last "committed" entry is
not synced on its own and may have been lost in a power loss (chapter 13). So the space's first snapshot
after every attach runs a **confirmation commit**, an empty round under a permission, before it
reads. A node that knows no committed root (that lost entry was its only one) first asks its
peers for theirs, and reads the persisted root only when a majority does not answer. Reads never
go backwards across a restart. `committedEpoch`, on the space or on its coordinator, is the
epoch of the newest root the node knows committed. It never goes down, except after `forceRejoin` on a survivor, which is outside the failure model
(chapter 15).

## Durability: the persister

> The persister and `sync:` are tested by `tests/unit/cluster_persister.st` and
> `cluster_persister_recovery.st`.

`space.root` is written by each node's persister, after the commit, under the storage's root
lock, never backwards. The commit point does not need it: acknowledged commits are durable in
the voters' synced logs. Every `persistInterval` (50 ms) the persister of each space looks at the newest root
its node knows committed. It writes it when its own node committed that root, or, when the root
has waited `persistLag` (1000 ms) unpersisted, whoever committed it: a crashed or cut-off
committer's commits are still persisted by another member. Only the newest root is written, so a
burst of commits costs one write. The write goes through the space's round runner, the one actor
that writes the node's storage, so it never overlaps a commit's own writes; when another member
holds the root lock at that moment, the persister simply tries again on its next pass.
`persistedEpoch` is the epoch of the newest root the node knows persisted, and `sync:` waits until
it reaches the committed one, `PBTimeoutError` after the milliseconds given:

```smalltalk
(spaces at: 1) sync: 10000.
lesson check: 'after sync: the persisted epoch reached the committed one'
  isTrue: (spaces at: 1) persistedEpoch >= (spaces at: 1) committedEpoch.
```

`sync:` is a **durability** barrier, not a visibility barrier: it says nothing about commits this
node has not learnt. Use it when a reader of `space.root` alone (a plain `proto_db` reader, a
backup) must see the commit, for example before reporting "saved" to such a reader; it does not
mean "I now see everything".

## Closing

```smalltalk
spaces do: [:space | space close].
nodes do: [:node | node stop waitWithin: 60000].
```

Spaces first, then the coordinators. `stop` settles every pending request (a replication in flight
as unknown, the rest `PBClosedError`) and answers a `Future` that resolves once the transport has
stopped.

## What to take away

- A member is a `PBClusterCoordinator` (`nodeId:peers:options:`, then `start`); every member gets
  the same peer list.
- Each member opens the same directory with `clusterPath:` and attaches it with
  `storage:coordinator:`; its log is `cluster/<id>.roots`, locked against a double start.
- A fresh cluster forms by itself; `stats` tells you when it is healthy.
- Commits look like standalone ones but have a third outcome; local reads may lag, a commit that
  writes something is the barrier, and `space.root` is written later, by the persister.
