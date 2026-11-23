"EXPECT: ok"
"Indexed queries: pagers under racing commits, the half of proto_db's
 tests/concurrency/test_pager_stability.py (v2.0.0rc4) that qry_pager_stability.st leaves out,
 where its writers take turns. Here three writer actors commit to the root 'items' in every round,
 racing (each reads 'items' and writes it back, so commits built on one version conflict and are
 retried by db run:), and a fourth commits to the root 'log', which nobody reads, so it never
 conflicts. Three reader actors each take one snapshot, once 8 commits to 'items' have landed,
 build a pager on it (an ordered scan and a descending range, by rank, and an unindexed condition,
 materialised) and read every page, one page per round. Every reader must see exactly the rows of
 its snapshot: no row twice, none skipped, rows equal to the snapshot's asArray.

 The paths this covers are those of racing commits: groups of more than one commit, each built on
 the root the previous build produced, builds that fail with a conflict inside a group, retries,
 and publishes of a group, all while pagers read older versions. That grouping happens is not left
 to chance: the space's runner runs over GatePublisher (the seam PBObjectSpace >> _newRunner,
 PBRoundRunner space:publisher:), whose publishGroup: answers #locked, deciding nothing, until all
 four writers' first commits of the round are queued; the runner retries a #locked round as it
 does for a held root lock, so the round then takes the four together. Checks: a round decided
 four commits at once, a round published two or more (fewer publishes than commits), and a
 conflict happened and was retried.

 The program thread drives the rounds, as in qry_pager_stability.st: one step to every reader
 not done and one commit to every writer, sent at once and all waited for. Every actor message is
 finite (D56, protoST LANGUAGE 10.4): a writer's message is one db run: retries: 20, whose waits
 (the commit's wait for the runner, the back-off between attempts) are nested in blocks and run
 other actors' messages on top of themselves; those are reader steps, other writers' commits and
 runner rounds, all finite, and the runner never waits. So a message run on top of a wait always
 ends, also with PROTOST_WORKERS=1 (qry_pager_racing_one_worker.sh). A writer whose 20 retries all
 conflict answers PBConflictError, which is counted, not a failure; any other error is a failure."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"A publisher that answers #locked until at least want entries are queued (want nil: open), then
 publishes them as one group and records { entries. published } for every group it publishes."
PBPublisher subclass: #GatePublisher instanceVariableNames: 'want groups'.

GatePublisher >> setUp
  want := Atom on: nil.
  groups := Atom on: #().

GatePublisher >> want: anInteger
  want swap: [:old | anInteger].

GatePublisher >> groups
  ^ groups value.

GatePublisher >> publishGroup: entries
  | wanted results |
  wanted := want value.
  (wanted notNil and: [entries size < wanted]) ifTrue: [^ entries collect: [:each | #locked]].
  want swap: [:old | nil].
  results := super publishGroup: entries.
  (results anySatisfy: [:r | r == #locked]) ifFalse: [
    groups swap: [:old | old copyWith: { entries size. results count: [:r | r == true] }]].
  ^ results.

PBObjectSpace subclass: #GateSpace instanceVariableNames: 'gate'.

GateSpace >> _newRunner
  gate := (GatePublisher space: self) setUp; yourself.
  ^ PBRoundRunner space: self publisher: gate.

GateSpace >> gate
  ^ gate.

"A writer of 'items': each commitNext commits one change drawn from QData random: aSeed, retried
 on a conflict (db run: retries: 20), and adds one to progress when it lands. Answers #inserted,
 #removed, #conflict (every retry conflicted) or the class and text of another error. attempts
 counts the attempts of the block in all."
Object subclass: #RacingWriter instanceVariableNames: 'db seed random n progress attempts'.

RacingWriter class >> on: aDb seed: aSeed progress: aProgress attempts: anAtom
  ^ self new setDb: aDb seed: aSeed progress: aProgress attempts: anAtom.

RacingWriter >> setDb: aDb seed: aSeed progress: aProgress attempts: anAtom
  db := aDb. seed := aSeed. progress := aProgress. attempts := anAtom.
  random := QData random: aSeed.
  n := 0.

RacingWriter >> commitNext
  | choice slot gone |
  n := n + 1.
  choice := random next.
  slot := (random next * 400) truncated.
  gone := random next.
  ^ [db run: [:tx | | items |
       attempts swap: [:x | x + 1].
       items := tx getRootObject: 'items'.
       choice < 0.3 ifTrue: [items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (0 - (seed * 1000) - n). 'v' -> (0 - n) })].
       (choice >= 0.3 and: [choice < 0.6]) ifTrue: [
         items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (10 * slot + 5). 'v' -> n })].
       (choice >= 0.6 and: [choice < 0.8]) ifTrue: [
         items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (100000 + (seed * 1000) + n). 'v' -> n })].
       (choice >= 0.8 and: [items count > 50]) ifTrue: [items := items removeAt: (gone * items count) truncated].
       tx setRootObject: 'items' value: items]
       retries: 20 backoff: #(1 20).
     progress swap: [:x | x + 1].
     choice < 0.8 ifTrue: [#inserted] ifFalse: [#removed]]
    on: Error do: [:e | (e isKindOf: PBConflictError) ifTrue: [#conflict] ifFalse: [e class name , ': ' , e messageText]].

"A writer of 'log', a root nobody else writes: its commits never conflict."
Object subclass: #LogWriter instanceVariableNames: 'db n'.

LogWriter class >> on: aDb
  ^ self new setDb: aDb.

LogWriter >> setDb: aDb
  db := aDb. n := 0.

LogWriter >> commitNext
  n := n + 1.
  ^ [db run: [:tx | tx setRootObject: 'log' value: n] retries: 20 backoff: #(1 20). #logged]
    on: Error do: [:e | e class name , ': ' , e messageText].

"A reader: pages through one snapshot of db, one step per message."
Object subclass: #RacingReader instanceVariableNames: 'db query size progress tx expected pager page seen first problems rank landed done'.

RacingReader class >> on: aDb query: aBlock size: aSize progress: aProgress
  ^ self new setDb: aDb query: aBlock size: aSize progress: aProgress.

RacingReader >> setDb: aDb query: aBlock size: aSize progress: aProgress
  db := aDb. query := aBlock. size := aSize. progress := aProgress.
  problems := OrderedCollection new.
  landed := 0.
  done := false.

"One step. With no pager open: once 8 commits to 'items' have landed, opens the snapshot (the
 query aBlock answers for its root, its asArray, and a pager of aSize over it); otherwise
 nothing. Then, with the pager open, reads its next page; after the last one, checks the pages
 against the snapshot and closes it. Answers true while the reader is not done."
RacingReader >> step
  | q ids |
  done ifTrue: [^ false].
  pager isNil ifTrue: [
    progress value < 8 ifTrue: [^ true].
    tx := db newTransaction.
    q := query value: (PBQuery from: (tx getRootObject: 'items')).
    expected := q asArray.
    pager := q pagerSize: size.
    rank := pager byRank.
    seen := OrderedCollection new.
    page := 0.
    first := progress value].
  seen addAll: (pager page: page).
  page := page + 1.
  page > pager pages ifFalse: [^ true].
  landed := progress value - first.
  ids := seen asArray collect: [:each | each at: 'id'].
  (seen asArray = expected) ifFalse: [problems add: 'the pages are not the snapshot''s rows'].
  ids asSet size = ids size ifFalse: [problems add: 'a row shown twice'].
  (pager rows = expected size and: [pager rows = seen size]) ifFalse: [problems add: 'rows'].
  tx abort.
  pager := nil.
  done := true.
  ^ false.

"{ problems. byRank. commits to 'items' landed while the pager was open }."
RacingReader >> result
  ^ { problems asArray. rank. landed }.

"The value of aFuture, or the class and text of its rejection (the program thread's wait blocks
 it; it never runs an actor's message)."
Object subclass: #Outcome.
Outcome class >> of: aFuture
  ^ [aFuture waitWithin: 120000] on: Error do: [:e | e class name , ': ' , e messageText].

| c dir space db progress attempts writers readers active ends rounds steps commits results report groups answers |
c := Check new.
dir := 'out/qry_pager_racing' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := GateSpace storage: (PBFileStorage path: dir pathString) lockTimeout: 600000.
db := space newDatabase: 'db'.
db run: [:tx | tx setRootObject: 'items' value: ((tx newList addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: ((0 to: 399) asArray collect: [:i | PBFrozenDict withAssociations: { 'id' -> i. 'k' -> (10 * i). 'v' -> i }]))].
progress := Atom on: 0.
attempts := Atom on: 0.
writers := ((1 to: 3) asArray collect: [:s | (RacingWriter on: db seed: s progress: progress attempts: attempts) asActor])
  copyWith: (LogWriter on: db) asActor.
readers := {
  (RacingReader on: db query: [:q | q orderBy: 'k'] size: 23 progress: progress) asActor.
  (RacingReader on: db query: [:q | (q where: ((PBField path: 'k') >= 1000)) orderBy: 'k' descending: true]
    size: 17 progress: progress) asActor.
  (RacingReader on: db query: [:q | (q where: ((PBField path: 'v') < 300)) orderBy: 'k']
    size: 31 progress: progress) asActor }.
active := (1 to: 3) asArray.
results := Array new: 3.
ends := OrderedCollection new.
rounds := 0.
[active isEmpty or: [rounds >= 1000]] whileFalse: [
  rounds := rounds + 1.
  "The four first commits of the round are decided together."
  space gate want: writers size.
  steps := active collect: [:i | (readers at: i) step].
  commits := writers collect: [:w | w commitNext].
  steps := steps collect: [:f | Outcome of: f].
  ends addAll: (commits collect: [:f | Outcome of: f]).
  1 to: active size do: [:j |
    (steps at: j) == true ifFalse: [
      results at: (active at: j) put: ((steps at: j) == false
        ifTrue: [Outcome of: (readers at: (active at: j)) result]
        ifFalse: [steps at: j])]].
  active := (1 to: active size) asArray
    inject: #() into: [:acc :j | (steps at: j) == true ifTrue: [acc , { active at: j }] ifFalse: [acc]]].
groups := space gate groups.
answers := ends reject: [:each | each == #logged].
c that: 'every reader finished within 1000 rounds'
  isTrue: active isEmpty.
c that: 'every reader saw exactly its snapshot''s rows on its pager: none twice, none skipped'
  is: (results collect: [:each | each isArray ifTrue: [each first] ifFalse: [each]])
  equals: #(#() #() #()).
c that: 'the first two readers page by rank, the third from a materialised result'
  is: (results collect: [:each | each isArray ifTrue: [each at: 2] ifFalse: [each]])
  equals: #(true true false).
c that: 'commits to items landed while every reader''s pager was open'
  isTrue: (results allSatisfy: [:each | each isArray and: [(each at: 3) > 0]]).
c that: 'every commit answered: inserted, removed, logged, or a conflict after its retries'
  isTrue: (ends allSatisfy: [:each | #(#inserted #removed #conflict #logged) includes: each]).
c that: 'a round decided all four commits of a round together, as one group'
  isTrue: (groups anySatisfy: [:g | g first >= 4]).
c that: 'a group published two or more commits at once (fewer publishes than commits)'
  isTrue: (groups anySatisfy: [:g | g last >= 2]).
c that: 'commits raced: some attempts conflicted and were retried'
  isTrue: attempts value > (answers count: [:each | each ~~ #conflict]).
c that: 'a pager of the final version holds every insertion and lacks every removal'
  is: ((PBQuery from: (db newTransaction getRootObject: 'items')) pagerSize: 50) rows
  equals: 400 + (ends count: [:each | each == #inserted]) - (ends count: [:each | each == #removed]).
space close.
report := c report.
report = 'failed'
  ifTrue: [report displayNl]
  ifFalse: [('commits ' , progress value printString , ' to items in ' , rounds printString , ' rounds, '
    , attempts value printString , ' attempts, ' , (answers count: [:each | each == #conflict]) printString
    , ' gave up; largest group ' , (groups inject: 0 into: [:m :g | m max: g first]) printString
    , ' entries; ' , report) displayNl. 'ok' displayNl].
