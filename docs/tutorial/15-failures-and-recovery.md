# 15. Failures and recovery

<!-- example: examples/cluster/15_losing_members.st -->
<!-- example: examples/cluster/15_wiped_disk.st -->
<!-- example: examples/cluster/pending/15_majority_loss.st.pending -->
Programs: [examples/cluster/15_losing_members.st](../../examples/cluster/15_losing_members.st),
[15_wiped_disk.st](../../examples/cluster/15_wiped_disk.st), and, pending,
[pending/15_majority_loss.st.pending](../../examples/cluster/pending/15_majority_loss.st.pending).
Previous: [14. A three-node cluster](14-a-three-node-cluster.md). Next: [16. Operating a cluster](16-operating-a-cluster.md).

A cluster exists for the bad days. This chapter takes the failures one at a time: what happens,
what is guaranteed, and which test proves it. The programs show the failures that today's code can
show; the commit-level guarantees are proven by the simulator (`tests/unit/sim_*.st`), which runs
the same rules under seeded faults in virtual time, and by the coordinator's own tests
(`tests/unit/cluster_coordinator_*.st`). The real-process tests, with `kill -9`, are Tasks 27 and
28 of the [cluster plan](../superpowers/plans/2026-11-13-cluster-mode.md) and do not exist yet.

In these programs **stopping a coordinator is a crash**: its endpoint stops, so the member neither
sends nor receives, and its disk stays as it was. A wait is always a condition with a deadline.

## The map

| Situation | Guarantee | Proved by |
|---|---|---|
| A voter dies | the others go on while a majority of voters lives | `15_losing_members.st`; `sim_acceptance.st` (1) |
| The owner dies | after its lease, another member owns a higher term; no acknowledged commit is lost | `15_losing_members.st`; `cluster_coordinator_attach.st` (8); `sim_leases.st` (3), (4) |
| A minority is cut off | it gets no permission and commits nothing (`PBTimeoutError`) | `15_losing_members.st`; `sim_permits.st` (4); `sim_round_rules.st` (11) |
| A paused holder wakes up | nothing it sends under its old term is accepted | `sim_acceptance.st` (3) |
| A holder dies mid-round | its commit is committed or absent everywhere, never on some nodes only | `sim_acceptance.st` (1); `sim_base_seeds_a.st`, `_b.st`; `cluster_coordinator_shell.st` (9) |
| A member restarts on its disk | its promises and accepted root come back; grants wait for the grace | `15_losing_members.st`; `sim_grants.st` (4); `sim_rejoin.st` (11), (12) |
| A member loses its disk | it rejoins by a ballot, never by a timer | `15_wiped_disk.st`; `sim_rejoin.st` (1), (2); `cluster_coordinator_attach.st` (6) |
| A majority of logs is lost | outside the model: the operator decides with `forceRejoin` | `sim_rejoin.st` (6); pending `15_majority_loss.st.pending` |
| An internal error | the node fences itself for the life of its process | `cluster_coordinator_shell.st` (5); `cluster_coordinator_faults.st` (1), (6) |
| A failed write | the node refuses everything until reopened (R57) | `cluster_coordinator_shell.st` (6), (10) |
| A second process with a live member's id | refused at the log's lock | `15_wiped_disk.st`; `cluster_tier.st` (2) |

## A voter dies

Three voters, n0 owning the first term because it asked first. n2 dies:

```smalltalk
(nodes at: 3) stop waitWithin: 60000.
second := (nodes at: 2) _permit waitWithin: 60000.
((nodes at: 2) _done: second outcome: #none) waitWithin: 60000.
lesson check: 'with one voter down a permission is still issued' isTrue: second term >= first term.
```

Nothing happens that anybody notices: n0 and n1 are two of three, a majority for renewals and
for acceptances. This is what three voters buy: one failure, any one.

## The owner dies too

```smalltalk
(nodes at: 1) stop waitWithin: 60000.
outcome := [(nodes at: 2) _permit waitWithin: 60000. #granted]
  on: PBTimeoutError do: [:e | e return: #timeout].
lesson check: 'a minority gets no permission: PBTimeoutError' is: outcome equals: #timeout.
```

n1 asks its owner and gets no answer. After a lease's time without an answer it forgets the
owner and tries to own a term itself; but it is one voter of three, so it can never collect a
majority of promises, and its request ends with `PBTimeoutError` at its `acquireTimeout` (2 s in
the lesson, 30 s by default). That is a minority's fate in every partition: it waits, then gives
up, and never writes. A commit that never got a permission sent nothing, and `run:` does not retry
a timeout (it is not a conflict).

Had only the owner died, with n2 alive, n1 and n2 would have elected a new owner once the
old grant expired on their clocks: until then a voter refuses with `'busy'` and the remaining
promise. The new term is higher, and from the moment a voter promises it, the voter refuses every
root of the old term: the old owner, if it was only paused, cannot get anything accepted after it
wakes up (`sim_acceptance.st` (3), whose planted rule without the ballot rule is caught).

## A restart on an intact disk, and the startup grace

n0 comes back on its disk: a new coordinator, a new space over the same directory.

```smalltalk
(spaces at: 1) close.
restarted := make value: 'n0'.
restarted start.
spaces at: 1 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: restarted).
lesson check: 'its acceptor log is restored, no rejoin needed'
  isTrue: (until value: [(restarted stats at: 'rejoining') not]).
lesson check: 'its restored log needs no rejoin ballot' is: (restarted stats at: 'rejoin_ballots') equals: 0.
```

Its log holds the rejoined marker, its promises and its accepted root: it is a voter again at once,
under a new incarnation, so replies meant for its previous life are ignored. But for its
`startupGrace` it refuses to grant (`'starting'`), in case a lease its previous life granted is still
running somewhere. n1 therefore asks until a permission comes:

```smalltalk
third := nil.
attempt := 0.
[third isNil and: [attempt < 20]] whileTrue: [
  attempt := attempt + 1.
  third := [(nodes at: 2) _permit waitWithin: 60000] on: PBTimeoutError do: [:e | e return: nil]].
lesson check: 'n0 and n1 issue permissions again, under a higher term'
  isTrue: (third notNil and: [third term > second term]).
```

A run printed the terms `#(12288 12288 69633)`: the old owner's term, still the same after the
voter died, and a new term of rank 1 once n1 owned. Terms only grow; a member never grants a term
at or below one it promised, and it remembers what it promised because the promise was synced
before the grant.

The grace is efficiency, not safety (chapter 13): `sim_rejoin.st` (12) shows that with a grace of
0 two leases can be *valid at once*, and that the commits stay safe anyway. That is also why a
member restarted over a log that served refuses, at attach, a grace shorter than the default
(chapter 16 shows the refusal).

## A holder dies in the middle of a round

This one cannot be shown by a program yet (the commit path is Task 23, the real `kill -9` tests
Task 28), so here is what the rules guarantee and where it is tested. A holder can die at three
moments:

- **before anything acceptable left it**: nothing happened; the owner gets no `'done'`, abandons the
  term at `valid + requestTimeout` (O6), and its commits are simply lost with the process, as a
  standalone commit is when its writer dies before the rename (chapter 10);
- **after the root left, before a majority synced it**: the root may be accepted by a minority. The
  next owner's phase 1 decides: if some granter reports it, the new term may adopt it, and then it
  is committed everywhere; otherwise it is absent everywhere;
- **after a majority synced it, before the `'done'`**: it is committed. The next phase 1 meets at
  least one voter that accepted it (any two majorities intersect) and builds on it.

The simulator checks the shape of every outcome after every run: no acknowledged commit missing
from any member's chain (S4), every unknown commit present on all members or on none, no two roots
of one label and epoch, no fork (`sim_base_seeds_a.st` and `_b.st`, 200 seeds with drops,
duplicates, delays, reordering, clocks 10 % fast and slow, and a member crashing).
`cluster_coordinator_shell.st` (9) checks the shell's half: a coordinator stopped with a
replication in flight answers it `#unknown`, never `#none`.

## Outcome unknown, and what `run:` does with it

The caller of a commit whose holder lost track of it gets `PBOutcomeUnknownError`: *the commit may
or may not take effect*. `run:` retries a `PBConflictError` and nothing else, and above all never an
unknown outcome: if the first attempt took effect, the retry would apply the work a second time.

The application settles it the way `proto_db`'s own tests do: each commit writes a value no other
commit writes, a token, and a later read looks for it (chapter 14 writes them):

- found, in the current state or in an older version (`history`): the commit took effect;
- not found: nothing can be concluded yet, because a later commit may have overwritten it, or the
  root may still be adopted; read again later.

What the guarantees allow you to assert, and all the programs and tests assert, is a bound, never
an exact count: every acknowledged token is present, the counter is at least the acknowledged
commits and at most the acknowledged plus the unknown ones, and no token is present twice.

## A wiped disk: rejoin by ballot

The second program loses n2's acceptor log. First, a term is promised and served, so that the
voters' logs hold something to remember:

```smalltalk
permit := (nodes at: 1) _permit waitWithin: 60000.
((nodes at: 1) _done: permit outcome: #none) waitWithin: 60000.
```

Then n2 crashes and its log is lost. The program moves the file aside, which is what a wiped disk
looks like to the protocol:

```smalltalk
(nodes at: 3) stop waitWithin: 60000.
(spaces at: 3) close.
log := dir / 'cluster' / 'n2.roots'.
log renameTo: 'n2.roots.lost'.
lesson check: 'n2''s log is gone' isTrue: log exists not.
```

n2 restarts over an empty log:

```smalltalk
fresh := make value: 'n2'.
fresh start.
spaces at: 3 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: fresh).
lesson check: 'n2 rejoins' isTrue: (until value: [(fresh stats at: 'rejoins') >= 1]).
stats := fresh stats.
lesson check: 'the rejoin was a ballot, not a first start' isTrue: (stats at: 'rejoin_ballots') >= 1.
ballot := fresh acceptorState rejoinBallot.
```

Until it has rejoined, n2 grants nothing and acknowledges nothing. Its first round learns that
the others promised a term, so this is no first start: it chooses a ballot above everything they
reported (a run printed `12290`, rank 2, above the term `12288`), the witnesses promise it durably,
and n2 logs the promise, the accepted root and the rejoined marker. Whatever n2 may have
acknowledged before its disk died, a witness that answered either reported it or will never accept
it, because its term is now below a promised ballot. The term the owner held is over too: the
witnesses' promise of the ballot ended its grant.

```smalltalk
later := fresh _permit waitWithin: 60000.
(fresh _done: later outcome: #none) waitWithin: 60000.
lesson check: 'a permission after the rejoin' isTrue: later term > permit term.
```

The test that proves the point is `sim_rejoin.st` (1) and (2): a wiped acknowledger restarts with
its timer 1.3, 2 and 3 times as fast as the holder's, the holder's timer running or standing still,
and no acknowledged commit is lost; the planted rule that waits *restartGrace* instead of asking for
a ballot loses one, exactly as `proto_db`'s did (lesson L13). Case (8) is `proto_db`'s literal check:
with every clock stopped, the ballot rejoin completes and the waiting one never does.

## A double start

The same program shows a mistake operators make: a second process started with the id of a live
member (a copied service file, a restart that did not wait for the old process):

```smalltalk
second := PBFileStorage clusterPath: dir pathString.
lesson check: 'a double start is refused at the log''s lock'
  signals: PBUserError containing: 'cluster/n0.roots.lock'
  during: [PBObjectSpace storage: second coordinator: (nodes at: 1)].
second close.
```

Two processes voting from one log would each promise and accept on the other's behalf. The log's
own `flock` refuses the second one, and the first is unaffected. (Copying a member's directory onto
another member is the same mistake, and `proto_db` documents it as forbidden.)

## A majority of logs lost: `forceRejoin`

> **Runs once Tasks 23 and 24 land.** The blocks come from
> `examples/cluster/pending/15_majority_loss.st.pending`. Today `forceRejoin` exists and is tested
> by the simulator (`sim_rejoin.st` (6)) and by `cluster_rejoin_rules.st` (7) and (14); the program
> needs commits to have something to lose.

Losing the logs of a majority of voters is outside the failure model. The wiped members cannot
rejoin by themselves: a ballot needs `V - majority + 1` witnesses, and too few are left. They stay
rejoining and say why:

```smalltalk
lesson check: 'the wiped members report why they cannot rejoin'
  isTrue: (until value: [fresh allSatisfy: [:node | (node stats at: 'rejoin_blocked') notNil]]).
```

Only an operator can decide that what is left is good enough:

```smalltalk
fresh do: [:node | node forceRejoin].
lesson check: 'forced, they rejoin' isTrue: (until value: [fresh allSatisfy: [:node | (node stats at: 'rejoining') not]]).
```

A forced rejoin completes with the answers of `majority - 1` loaded members after a plain round. On
a survivor, `forceRejoin` forgets a committed root it knows of but never accepted itself, and asks
for a confirmation before its next read. That is the price, and the reason it is a decision: a
commit acknowledged only by the lost logs is gone. When a survivor still believes in such a root,
its next commit refuses to build below it and signals `PBCorruptionError` naming `forceRejoin`,
rather than silently dropping it.

## When the node itself is at fault

Two failures are the node's own, and both end with a node that refuses to take part:

- **Fenced.** An unexpected error escaping one of its actors fences the node for the life of its
  process: it grants nothing, answers replications with `ack(ok = false)`, and its own commits get
  `PBUnexpectedError` (`'Node n2 is fenced after an internal failure: ...'`). The others go on
  (`cluster_coordinator_shell.st` (5), with an acceptor that raises on purpose).
  `cluster_coordinator_faults.st` (1) proves the harder half: a request already queued when the
  fence lands is never granted, because the acceptor reads the fence before every step. The cure
  is a restart; chapter 13 explains why the node does not try to recover in place.
- **Tier failed.** A failed write to its log is never acknowledged, and the node refuses everything
  until it is reopened on a healthy disk (`cluster_coordinator_shell.st` (6) and (10)).

`stats` tells them apart: `'fenced'`, `'tier_failed'`, and `'failure'`, the reason.

## What to take away

- A cluster of three voters survives any one failure; a minority never writes, it times out.
- A restarted member remembers its promises; its startup grace only saves wasted work.
- A wiped member rejoins by a ballot, and the tests prove it with clocks at any rate; a majority of
  lost logs needs `forceRejoin`, the operator's decision.
- An unknown outcome is never retried by `run:`; a token per commit settles it later.
- A fenced node stays out until its process restarts; a failed disk until it is replaced.
