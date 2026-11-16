"-- cluster/persister.st: PBPersister, the node's asynchronous writer of space.root --

proto_db cluster/persister.py at v2.0.0rc4 (Persister; D44, D46) over the shared tier of
cluster/tier.st (DEPTH = 0: the records live in the shared storage, so nothing is shipped,
verified, uploaded or released, and every root is persistable at once). In cluster mode a
commit is acknowledged by majority replication; space.root is written afterwards, never on the
commit path, by one persister per space of a node.

  PBPersister tier: aTier coordinator: aCoordinator writer: aWriter
                  the persister of aCoordinator's space over aTier (a PBSharedTier, or a test
                  double answering readPersisted and persist:). aWriter is the actor that makes
                  every storage write of the node (the space's round runner, round.st): the
                  persister never calls aTier persist: itself, it sends aWriter persist:, so the
                  root lock taken and released by persist: never overlaps a pushAtom: or a
                  flushSegment of the same storage (Task 21 review I1: the storage takes no lock
                  to serialise its writes, and the root lock is per storage object and not
                  re-entrant). Answers the persister: an object whose state is in Atoms, with a
                  low band actor (asLowPriorityActor) that runs every pass. The interval and the
                  lag are the coordinator's persistInterval and persistLag.
  aPersister start          posts the first pass (a Future)
  aPersister stop           no pass after it, every waiter rejected; a Future that resolves once
                            no write of the persister is in flight (proto_db stop joins the
                            thread). Idempotent.
  aPersister waitFor: aLabeledRoot within: ms
                            a Future: nil once the persisted root orders at or above
                            aLabeledRoot (PBRootOrder), PBTimeoutError after ms milliseconds (nil:
                            no deadline), at once PBUnexpectedError when the persister failed, or
                            PBTimeoutError when it stopped (proto_db wait_persisted). A waiter
                            makes the next pass start at once.
  aPersister persistedEpoch the epoch of the newest root this node knows persisted, 0 when none
  aPersister persistedRoot  that root (a PBLabeledRoot; label 0 and no record before any)
  aPersister stats          cycles, roots_written, roots_behind, roots_busy, errors, refreshes,
                            persisted_epoch, last_error (a String or nil)
  aPersister isRunning, failure

Each pass (proto_db _advance): the newest committed root this node knows (aCoordinator
committedRoot) is behind the persisted one or not, in the order of roots. A root behind is noted
in the pending list with the node's clock (the oldest one not persisted measures the lag); the
roots at or below the persisted one leave it. A root behind is written when this node committed
it (aCoordinator _committedHere:, proto_db by == node_id) or when the oldest pending root has
waited persistLag or more (a crashed or partitioned committer: any node then writes the newest
root it knows). Only the newest root is written (coalescing). The write is aWriter persist:,
whose answer comes back to this actor: true, the root persisted (roots_written); false, the
storage holds a newer root, or that root at a version at or above its own (roots_behind; the
persisted root is read again, so the persister never goes backwards, CC19); #busy, another holder has the root lock (roots_busy, a
protoBaseST counter; the next pass, one interval later, tries again). A pass that does not write
while behind reads the persisted root (refresh), at most once per max(persistInterval,
min(250 ms, persistLag / 4)) unless a waiter forces it, so the node learns roots another node
persisted and its waiters return. A refresh hands the root read to the coordinator as committed
and not accepted (_learnPersisted:from:, proto_db observe_root(accept=False, tier=)). The first
pass forces a refresh. One pass runs at a time: while a write is in flight no other pass starts,
and its answer schedules the next one.

Errors (proto_db _run): a PBDBError or a FileSystemError of a pass is counted (errors), kept as
last_error, written to stderr and retried, the delay doubling from persistInterval up to 1 s; a
pass that ends normally resets it. Any other error stops persisting on this node only: it is
reported (aCoordinator _persistenceFailed:, which makes the node unhealthy without fencing it,
persistence being off the commit path), every waiter fails at once with PBUnexpectedError ('The
persister failed: ...'), and no pass runs again. A pass that finds the coordinator stopped stops
the persister (proto_db's coordinator stop stops its persister).

This module is a shell: it reads the node's clock (aCoordinator _now, microseconds) and uses
Future after: for its passes and its waiters' deadlines. Every value is immutable but the
persister's cells: Atoms created by its initialiser and changed only on its actor."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/rootlog'.

"=== PBPersister ============================================================="

Object subclass: #PBPersister
  instanceVariableNames: 'tier coordinator writer interval lag proxy persisted pending waiters status failure busy urgent first lastRefresh lastError delay stats timer stopping'.

"The longest delay between two passes after errors, in microseconds (proto_db _MAX_BACKOFF)."
PBPersister class >> maxBackoff
  ^ 1000000.

"The shortest period between two refreshes of a node not expected to write, in microseconds
 (proto_db _REFRESH_PERIOD)."
PBPersister class >> refreshPeriod
  ^ 250000.

"The names of the counters stats reports."
PBPersister class >> statNames
  ^ #('cycles' 'roots_written' 'roots_behind' 'roots_busy' 'errors' 'refreshes').

PBPersister class >> tier: aTier coordinator: aCoordinator writer: aWriter
  | persister zero |
  (aTier isNil or: [aCoordinator isNil or: [aWriter isNil]]) ifTrue: [
    ^ PBValidationError signal: 'PBPersister tier:coordinator:writer: needs a tier, a coordinator and a writer, not '
      , { aTier. aCoordinator. aWriter } printString].
  zero := Dictionary new.
  self statNames do: [:name | zero at: name put: 0].
  persister := self basicNew _setTier: aTier coordinator: aCoordinator writer: aWriter
    interval: aCoordinator config persistInterval lag: aCoordinator config persistLag stats: zero.
  persister _publishProxy: persister asLowPriorityActor.
  ^ persister.

PBPersister >> _setTier: aTier coordinator: aCoordinator writer: aWriter interval: anInterval lag: aLag stats: aDictionary
  "Runs once, on a fresh instance."
  tier isNil ifFalse: [^ PBUserError signal: 'PBPersister is initialised once'].
  tier := aTier.
  coordinator := aCoordinator.
  writer := aWriter.
  interval := anInterval.
  lag := aLag.
  proxy := Atom on: nil.
  persisted := Atom on: (PBLabeledRoot label: 0 record: nil).
  pending := Atom on: #().
  waiters := Atom on: #().
  status := Atom on: #new.
  failure := Atom on: nil.
  busy := Atom on: false.
  urgent := Atom on: false.
  first := Atom on: true.
  lastRefresh := Atom on: nil.
  lastError := Atom on: nil.
  delay := Atom on: anInterval.
  stats := Atom on: aDictionary.
  timer := Atom on: 0.
  stopping := Atom on: #().
  ^ self.

"Sets the actor proxy once (from nil), before the persister is answered."
PBPersister >> _publishProxy: anActor
  (proxy value: anActor ifCurrent: nil) ifFalse: [^ PBUserError signal: 'PBPersister: the proxy is set once'].

"=== the interface (any thread) =============================================="

PBPersister >> start
  ^ proxy value _start.

PBPersister >> stop
  | f |
  f := Future new.
  (proxy value _stop: f) catch: [:e | f resolve: true].
  ^ f.

PBPersister >> waitFor: aLabeledRoot within: milliseconds
  | f |
  f := Future new.
  (proxy value _waitFor: aLabeledRoot within: milliseconds future: f) catch: [:e | f rejectWith: e].
  ^ f.

PBPersister >> persistedRoot
  ^ persisted value.

PBPersister >> persistedEpoch
  ^ persisted value epoch.

PBPersister >> isRunning
  ^ status value == #running.

"The error that stopped persisting (an unexpected one), nil when none."
PBPersister >> failure
  ^ failure value.

PBPersister >> stats
  | d |
  d := stats value copy.
  d at: 'persisted_epoch' put: self persistedEpoch.
  d at: 'last_error' put: (lastError value isNil ifTrue: [nil] ifFalse: [self _describe: lastError value]).
  ^ d.

PBPersister >> tier
  ^ tier.

PBPersister >> printOn: aStream
  aStream nextPutAll: 'PBPersister('; nextPutAll: coordinator nodeId; nextPut: $).

"=== the messages (on the actor) ============================================="

PBPersister >> _start
  (status value: #running ifCurrent: #new) ifFalse: [^ nil].
  self _pass.
  ^ nil.

"A timer of the pass schedule: it runs only when it is still the current one (a pass started
 since, by a waiter or a write's answer, replaced it)."
PBPersister >> _tick: aToken
  aToken = timer value ifFalse: [^ nil].
  self _pass.
  ^ nil.

PBPersister >> _stop: aFuture
  status value == #stopped ifFalse: [self _halt: nil].
  busy value
    ifTrue: [stopping swap: [:old | old copyWith: aFuture]]
    ifFalse: [aFuture resolve: true].
  ^ nil.

PBPersister >> _waitFor: aLabeledRoot within: milliseconds future: aFuture
  | ms p |
  (milliseconds isNil or: [(milliseconds isKindOf: SmallInteger) and: [milliseconds >= 0]]) ifFalse: [
    aFuture rejectWith: (PBValidationError new messageText: 'sync: takes milliseconds, a SmallInteger >= 0, or nil, not '
      , milliseconds printString; yourself).
    ^ nil].
  (self _behind: aLabeledRoot) ifFalse: [aFuture resolve: nil. ^ nil].
  failure value isNil ifFalse: [aFuture rejectWith: self _failedError. ^ nil].
  status value == #stopped ifTrue: [aFuture rejectWith: self _stoppedError. ^ nil].
  (milliseconds notNil and: [milliseconds = 0]) ifTrue: [aFuture rejectWith: (self _timeoutFor: aLabeledRoot). ^ nil].
  waiters swap: [:old | old copyWith: { aLabeledRoot. aFuture }].
  milliseconds isNil ifFalse: [
    ms := milliseconds.
    p := proxy value.
    (Future after: ms) thenDo: [:x | p _expire: aFuture]].
  urgent swap: [:old | true].
  self _pass.
  ^ nil.

"The deadline of the waiter aFuture passed: PBTimeoutError, when it still waits."
PBPersister >> _expire: aFuture
  | entry |
  entry := waiters value detect: [:w | w last == aFuture] ifNone: [nil].
  entry isNil ifTrue: [^ nil].
  waiters swap: [:old | old reject: [:w | w last == aFuture]].
  aFuture rejectWith: (self _timeoutFor: entry first).
  ^ nil.

"The answer of the writer to the write of aRoot."
PBPersister >> _written: aResult root: aRoot
  busy swap: [:old | false].
  [aResult == true ifTrue: [
     self _count: 'roots_written'.
     self _setPersisted: aRoot].
   aResult == false ifTrue: [
     self _count: 'roots_behind'.
     self _refresh: true].
   aResult == #busy ifTrue: [self _count: 'roots_busy'].
   (aResult == true or: [aResult == false or: [aResult == #busy]]) ifFalse: [
     ^ self _error: (PBUnexpectedError new messageText: 'PBPersister: the writer answered ' , aResult printString
       , ' to persist:, not true, false or #busy'; yourself)].
   delay swap: [:d | interval].
   lastError swap: [:old | nil]]
    on: Error do: [:e | self _error: e. ^ nil].
  self _afterWrite.
  ^ nil.

"The write failed with anError (the writer's Future was rejected)."
PBPersister >> _writeFailed: anError
  busy swap: [:old | false].
  self _error: anError.
  ^ nil.

"=== the pass ================================================================="

"One pass, unless the persister is not running or a write is in flight (its answer schedules
 the next pass). The next pass is scheduled after the current delay, at once when a waiter came."
PBPersister >> _pass
  status value == #running ifFalse: [^ self].
  busy value ifTrue: [^ self].
  coordinator isRunning ifFalse: [^ self _halt: nil].
  urgent swap: [:old | false].
  [first value ifTrue: [
     first swap: [:old | false].
     self _refresh: true].
   self _cycle.
   busy value ifFalse: [
     delay swap: [:d | interval].
     lastError swap: [:old | nil]]]
    on: Error do: [:e | ^ self _error: e].
  busy value ifFalse: [self _schedule].

PBPersister >> _cycle
  | root behind waiting now persistedKey mine lagging queue |
  self _count: 'cycles'.
  waiting := waiters value notEmpty.
  root := coordinator committedRoot.
  behind := self _behind: root.
  persistedKey := persisted value key.
  now := coordinator _now.
  queue := pending value.
  behind ifTrue: [
    (queue isEmpty or: [(PBRootOrder compareKey: root key with: queue last first key) > 0]) ifTrue: [
      queue := queue copyWith: { root. now }]].
  [queue notEmpty and: [(PBRootOrder compareKey: queue first first key with: persistedKey) <= 0]]
    whileTrue: [queue := queue copyFrom: 2 to: queue size].
  pending swap: [:old | queue].
  behind ifFalse: [^ self].
  mine := coordinator _committedHere: root.
  lagging := queue notEmpty and: [now - queue first last >= lag].
  (mine or: [lagging]) ifTrue: [^ self _write: root].
  self _refresh: waiting.

"Hands the write of aRoot to the writer (never to the tier: Task 21 review I1); its answer comes
 back to this actor."
PBPersister >> _write: aRoot
  | p |
  busy swap: [:old | true].
  p := proxy value.
  (writer persist: aRoot)
    thenDo: [:v | p _written: v root: aRoot];
    catch: [:e | p _writeFailed: e].

"Reads the persisted root (at most once per refresh period unless forced) and learns it."
PBPersister >> _refresh: force
  | now root |
  now := coordinator _now.
  (force not and: [lastRefresh value notNil
      and: [now - lastRefresh value < (interval max: (self class refreshPeriod min: lag // 4))]])
    ifTrue: [^ self].
  lastRefresh swap: [:old | now].
  root := tier readPersisted.
  self _count: 'refreshes'.
  root isNil ifTrue: [^ self].
  coordinator _learnPersisted: root from: tier.
  self _setPersisted: root.

"aRoot persisted: the persisted root when it orders after it; the waiters it covers resolve."
PBPersister >> _setPersisted: aRoot
  | done |
  (self _behind: aRoot) ifFalse: [^ self].
  persisted swap: [:old | aRoot].
  done := waiters value reject: [:w | self _behind: w first].
  waiters swap: [:old | old select: [:w | self _behind: w first]].
  done do: [:w | w last resolve: nil].

"Whether aRoot (a PBLabeledRoot or nil) orders after the persisted root (proto_db _behind)."
PBPersister >> _behind: aRoot
  aRoot isNil ifTrue: [^ false].
  aRoot record isNil ifTrue: [^ false].
  ^ (PBRootOrder compare: aRoot with: persisted value) > 0.

"After a write's answer: a stop waiting for it resolves, else the next pass."
PBPersister >> _afterWrite
  | waiting |
  waiting := stopping value.
  waiting isEmpty ifFalse: [
    stopping swap: [:old | #()].
    waiting do: [:f | f resolve: true].
    ^ self].
  status value == #running ifTrue: [self _schedule].

"The next pass: at once when a waiter came meanwhile, else after the current delay."
PBPersister >> _schedule
  | token p ms |
  token := timer swap: [:t | t + 1].
  p := proxy value.
  urgent value ifTrue: [^ p _tick: token].
  ms := delay value + 999 // 1000.
  (Future after: ms) thenDo: [:x | p _tick: token].

"anError of a pass (proto_db _run's two handlers)."
PBPersister >> _error: anError
  | text |
  self _count: 'errors'.
  lastError swap: [:old | anError].
  text := self _describe: anError.
  ((anError isKindOf: PBDBError) or: [anError isKindOf: FileSystemError]) ifTrue: [
    delay swap: [:d | (d * 2 max: interval) min: self class maxBackoff].
    self _say: 'Persister of node ' , coordinator nodeId , ': ' , text , ' (retrying in '
      , (delay value // 1000) printString , ' ms)'.
    ^ self _afterWrite].
  failure value: anError ifCurrent: nil.
  self _halt: self _failedError.
  [coordinator _persistenceFailed: anError] on: Error do: [:e | e return: nil].
  self _say: 'Node ' , coordinator nodeId , ' stopped persisting after an internal failure: ' , text.
  self _afterWrite.

"No pass after this; every waiter rejected with anErrorOrNil (nil: the persister stopped)."
PBPersister >> _halt: anErrorOrNil
  | all |
  status swap: [:old | #stopped].
  timer swap: [:t | t + 1].
  all := waiters value.
  waiters swap: [:old | #()].
  all do: [:w | w last rejectWith: (anErrorOrNil isNil ifTrue: [self _stoppedError] ifFalse: [anErrorOrNil copy])].

PBPersister >> _count: aName
  stats swap: [:d | | copy | copy := d copy. copy at: aName put: (d at: aName ifAbsent: [0]) + 1. copy].

PBPersister >> _failedError
  ^ PBUnexpectedError new messageText: 'The persister failed: ' , (self _describe: failure value); yourself.

PBPersister >> _stoppedError
  ^ PBTimeoutError new messageText: 'The persister stopped before the root was persisted'; yourself.

PBPersister >> _timeoutFor: aLabeledRoot
  ^ PBTimeoutError new messageText: 'The persisted epoch is ' , self persistedEpoch printString
    , ', waiting for ' , aLabeledRoot epoch printString
    , (lastError value isNil ifTrue: [''] ifFalse: [' (last error: ' , (self _describe: lastError value) , ')']);
    yourself.

PBPersister >> _describe: anError
  ^ anError class name , ': ' , (anError messageText ifNil: ['(no message)']).

"aString on stderr; never signals (proto_db logger.info and logger.error)."
PBPersister >> _say: aString
  [Stdio stderr nextPutAll: aString; lf; flush] on: Error do: [:e | nil].
