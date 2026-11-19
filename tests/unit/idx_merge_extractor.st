"EXPECT: ok 4"
"Indexed queries, plan Task 4b, ruling IQ1 (spec 9.2, plan call IP2, Review Focus 1, controller
 ruling CR8; the maintainer's decision of 2026-11-19): an extractor runs inside the commit, in
 the merge the build makes, and an exception it raises passes through unwrapped and fails only
 the commit whose merge ran it, standalone, in a group commit and in a cluster round. Standalone
 and in a group commit this is proto_db rc4's rule (KeySpec.extract, _standalone_round: one
 commit's error, even an unexpected one, is that commit's alone); in a cluster round it is a
 documented deviation, since rc4's _permit_round fails the whole round on an error that is not a
 ProtoDBError (docs/deviations.md).

 The root 'd' is a PBDictionary of five records with an equality index on the extractor 'flaky',
 which raises ZeroDivide for a record whose 'bad' is true (the exception it raised is kept, to
 compare with the one each commit reports) and answers the id otherwise. Unchanged means the
 class and the text the block raised, never a wrapper: protoST's Future wait signals an equal
 exception (same class and text), not the same object, so identity is not what a caller
 sees. Each writer blind-writes 'd' (a new dictionary holding one record; the root is never read), so the extractor runs only
 when the commit merges that write onto the current version.
 (a) Standalone: the commit of a bad record fails with ZeroDivide, the class and text the block
 raised; nothing of it is in the root; then the next commit succeeds, and its record is indexed
 (two checks). (b) Group commit (D52), one extractor fails: three writers queued one after
 the other on a storage that holds the root lock until the three have saved their atoms, so one round builds the three in
 queue order, the middle one's merge running the extractor on its bad record: the first and the
 third commit, their records in the new root, with one publish; the middle one fails with
 the block's ZeroDivide. (c) The cluster round of a one-node cluster (PBClusterRound over an
 in-process coordinator, not the simulator: the round runner itself is under test; its first
 permit is held until the three commits are queued, so they join one round; the lease is 20 s
 with the least drift margin R78b allows, so a permission is believed for 6.6 s and the send
 reserve cannot split the round (R121); the startup grace is 3 s, since its default, lease plus
 margin, would outlast the 30 s permit wait): only the middle commit fails, with ZeroDivide
 (class and text); the first and the third commit, their records in the root; the trace shows one
 permit and one replicate (one round); and the round runner still serves the next round: a fourth
 commit succeeds. Spaces go to
 out/idx_merge_extractor (git ignores out/), a new directory per run."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

"gate: n, the number of distinct dictionaries step 0 must have saved before the root lock can be
 taken; saved, how many it has seen; replaces, the publishes."
PBFileStorage subclass: #GroupGate instanceVariableNames: 'gate seen replaces'.
GroupGate >> gate: n
  gate := n.
  seen := Atom on: #().
GroupGate >> saved
  ^ seen isNil ifTrue: [0] ifFalse: [seen value size].
GroupGate >> replaces
  ^ replaces ifNil: [0].
GroupGate >> save: anAtom
  ((anAtom isKindOf: PBDictionary) and: [seen notNil])
    ifTrue: [seen swap: [:old | (old anySatisfy: [:each | each == anAtom]) ifTrue: [old] ifFalse: [old copyWith: anAtom]]].
  ^ super save: anAtom.
GroupGate >> tryLockRoot
  (gate notNil and: [self saved < gate]) ifTrue: [^ false].
  gate := nil.
  ^ super tryLockRoot.
GroupGate >> replaceRoot: aRecord
  replaces := self replaces + 1.
  ^ super replaceRoot: aRecord.
GroupGate >> _log: aString
  ^ nil.

Object subclass: #Writer.
"Blind-writes aRecord into the root 'd' of aDatabase and commits: 'ok' or { class name. text }."
Writer >> write: aRecord in: aDatabase
  ^ [aDatabase newTransactionDo: [:t | t setRootObject: 'd' value: (t newDictionary setAt: (aRecord at: 'id') value: aRecord)]. 'ok']
    on: Error do: [:e | e return: { e class name asString. e messageText }].

| c dir raised record index space db storage outcome results root writers waitFor kit seam w f before ok trace |
c := Check new.
dir := 'out/idx_merge_extractor' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
dir ensureCreateDirectory.
raised := Atom on: nil.
PBKeySpec registerExtractor: 'flaky' block: [:r |
    ((PBKeySpec path: 'bad') extract: r) == true ifTrue: [
      [1 / 0] on: ZeroDivide do: [:e | raised swap: [:old | e]. e pass]].
    (PBKeySpec path: 'id') extract: r]
  version: '1'.
record := [:id :bad | PBObject withAll: { 'id' -> id. 'bad' -> bad }].
index := PBEqualityIndex name: 'by_flaky' keySpec: (PBKeySpec extractor: 'flaky').
"The root of aDb: five good records, indexed."
root := [:aDb | aDb newTransactionDo: [:t | | d |
  d := PBDictionary new.
  1 to: 5 do: [:i | d := d setAt: i value: (record value: i value: false)].
  t setRootObject: 'd' value: (d addIndex: index)]].
"{ count. the ids. the index's count. validate } of the root 'd' read in a new transaction."
outcome := [:aDb | | d |
  d := aDb newTransaction getRootObject: 'd'.
  { d count. d keys asArray. (d getIndex: 'by_flaky') count. [d validate. true] on: PBDBError do: [:e | e return: e class name] }].
"What the block raised last, as a Writer reports an error: { class name. text }; nil when it raised
 nothing since it was cleared."
ok := [raised value isNil ifTrue: [nil] ifFalse: [{ raised value class name asString. raised value messageText }]].

"(a) and (b) standalone."
space := PBObjectSpace storage: (PBFileStorage path: (dir / 'standalone') pathString).
db := space newDatabase: 'db'.
root value: db.
results := { Writer new write: (record value: 6 value: true) in: db }.
c that: 'standalone: the commit whose merge runs the failing extractor fails with the block''s own exception, unchanged'
  is: { results first. results first = ok value. outcome value: db }
  equals: { #('ZeroDivide' 'ZeroDivide'). true. { 5. #(1 2 3 4 5). 5. true } }.
results := { Writer new write: (record value: 7 value: false) in: db }.
c that: 'standalone: then the next commit succeeds and is indexed'
  is: { results first. outcome value: db } equals: { 'ok'. { 6. #(1 2 3 4 5 7). 6. true } }.
space close.

"(b) group commit: the writers queued one after the other (each once the previous one's step 0
 has saved its dictionary), the root lock held until the three have."
storage := GroupGate path: (dir / 'group') pathString.
space := PBObjectSpace storage: storage lockTimeout: 600000.
db := space newDatabase: 'db'.
root value: db.
raised swap: [:old | nil].
before := storage replaces.
storage gate: 3.
waitFor := [:n | | deadline |
  deadline := Time millisecondClockValue + 120000.
  [storage saved >= n or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 5) wait]].
writers := OrderedCollection new.
{ record value: 10 value: false. record value: 11 value: true. record value: 12 value: false } doWithIndex: [:r :i |
  writers addLast: (Writer new asActor write: r in: db).
  waitFor value: i].
results := writers asArray collect: [:fut | [fut waitWithin: 120000] on: TimeoutError do: [:e | e return: 'no outcome within 120 s']].
c that: 'group commit: one extractor fails: only the commit whose merge ran it fails, with its exception; the others commit in one publish'
  is: { results. (results at: 2) = ok value. outcome value: db. storage replaces - before }
  equals: { { 'ok'. #('ZeroDivide' 'ZeroDivide'). 'ok' }. true. { 7. #(1 2 3 4 5 10 12). 7. true }. 1 }.
space close.

"(c) the cluster round of a one-node cluster: only the failing commit fails (maintainer, 2026-11-19)."
SeamRound setUp.
kit := CommitKit ids: #('s0') dir: dir / 'cluster'
  options: (Dictionary new at: #leaseDuration put: 20000; at: #driftMargin put: 13400; at: #startupGrace put: 3000; at: #requestTimeout put: 300; yourself).
space := kit open: 's0'.
kit waitUntil: [((kit node: 's0') stats at: 'rejoining') not].
db := space newDatabase: 'db'.
root value: db.
raised swap: [:old | nil].
seam := SeamRound resetSeamOf: 's0'.
seam permitGate swap: [:x | Future new].
before := seam permitGate value.
writers := OrderedCollection new.
{ record value: 20 value: false. record value: 21 value: true. record value: 22 value: false } doWithIndex: [:r :i |
  writers addLast: (Writer new asActor write: r in: db).
  kit waitUntil: [| rs | rs := (SeamRound roundOf: 's0') roundState. rs batch size + rs queue size = i]].
before resolve: true.
results := writers asArray collect: [:fut | kit settle: fut].
trace := seam calls: #('permit' 'replicate').
w := Writer new asActor.
f := kit settle: (w write: (record value: 23 value: false) in: db).
c that: 'cluster round: only the commit whose merge ran the failing extractor fails, with its class and text; the others commit in one round; the next round is served'
  is: { results. (results at: 2) = ok value. trace. f. outcome value: db }
  equals: { { 'ok'. #('ZeroDivide' 'ZeroDivide'). 'ok' }. true. #('permit' 'replicate').
    'ok'. { 8. #(1 2 3 4 5 20 22 23). 8. true } }.
kit shutdown.
c report displayNl.
