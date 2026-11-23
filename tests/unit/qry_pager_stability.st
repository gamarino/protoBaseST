"EXPECT: ok"
"Indexed queries, plan Task 9: pagers under concurrent writers (proto_db
 tests/concurrency/test_pager_stability.py at v2.0.0rc4, D56, R77). Three writer actors commit
 insertions before, inside and after the pages being read, and removals, while three
 reader actors page through snapshots: an ordered scan (by rank), a range ordered by its key,
 descending (by rank), and an unindexed condition (materialised). Each reader takes four snapshots,
 the k-th after at least 8 k commits, builds its pager on it and reads every page. Every reader
 must see exactly the rows of its own snapshot: no row twice, none skipped, rows equal to the
 snapshot's asArray. The cached-query half of proto_db's test is not ported: the query result
 cache is deferred (spec 3.2, ruling IQ3); tests/unit/queries_checklist.tsv notes it. The writers'
 draws come from QData random: (fixed seeds); the interleaving varies from run to run, and the
 property holds for every one.

 The program thread drives the test in rounds. In each round it sends one step to every reader
 that is not done (open the next snapshot when enough commits have landed, or read the next page)
 and one commit to the next writer in turn, all at once, so the pages are read while the commit
 runs, and waits for all of them before the next round. So one commit lands in every round,
 concurrently with the pages being read: commits land while every pager is open, and one lands
 before each snapshot after the first (snapshot k opens once 8 k commits have landed). A round's commit may land before or after the page read in the same
 round, so a commit lands between page p and page p + 2 (the next round's commit lands after page
 p is read and before page p + 2 is), not necessarily between every two pages. The rounds are
 finite: a reader needs 24 commits and one round per page. The writers take turns so that the
 commits are those the readers need (one per round; three per round made the test twice as slow,
 the commits being its cost); racing commits, grouped and retried while pagers read, are tested
 by tests/unit/qry_pager_racing.st, and conflicts and their retries by run_retries.st,
 round_group_commit.st and tx_conflict_read.st; this test is about
 pagers under commits.

 Every actor message is finite and waits for nothing another actor's message must end first
 (D56, protoST LANGUAGE 10.4). A wait nested in a block (here, the commit's own wait for the
 round runner inside db run:) blocks its worker, which runs other actors' messages on top of it
 until they end; the waiting message resumes only then. The first version of this test had
 writer and reader actors that each looped, waiting a millisecond at a time, until the readers
 were done: a reader's wait could run a writer's endless loop on top of itself, and the run hung
 (always with PROTOST_WORKERS=1, rarely with the default pool; the test
 qry_pager_stability_one_worker.sh runs this file with one worker). Here a message run on top of
 a wait always ends, so the waiting message always resumes."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"A writer: each commitNext commits one change to the root 'items' of db, drawn from QData random:
 aSeed. The writers take turns (one commit per round), so their commits never conflict: a
 PBConflictError here is a failure like any other error."
Object subclass: #PageWriter instanceVariableNames: 'db seed random n progress'.

PageWriter class >> on: aDb seed: aSeed progress: aProgress
  ^ self new setDb: aDb seed: aSeed progress: aProgress.

PageWriter >> setDb: aDb seed: aSeed progress: aProgress
  db := aDb. seed := aSeed. progress := aProgress.
  random := QData random: aSeed.
  n := 0.

"Commits one change and adds one to progress: an insertion before, inside or after the keys of
 the initial rows, or a removal (the root never falls to 50 elements, so every removal drawn is
 made). Answers #inserted or #removed, or the class and text of an error other than a conflict."
PageWriter >> commitNext
  | choice slot gone |
  n := n + 1.
  choice := random next.
  slot := (random next * 400) truncated.
  gone := random next.
  ^ [db run: [:tx | | items |
       items := tx getRootObject: 'items'.
       choice < 0.3 ifTrue: [items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (0 - (seed * 1000) - n). 'v' -> (0 - n) })].
       (choice >= 0.3 and: [choice < 0.6]) ifTrue: [
         items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (10 * slot + 5). 'v' -> n })].
       (choice >= 0.6 and: [choice < 0.8]) ifTrue: [
         items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (seed * 100000 + n). 'k' -> (100000 + (seed * 1000) + n). 'v' -> n })].
       (choice >= 0.8 and: [items count > 50]) ifTrue: [items := items removeAt: (gone * items count) truncated].
       tx setRootObject: 'items' value: items].
     progress swap: [:x | x + 1].
     choice < 0.8 ifTrue: [#inserted] ifFalse: [#removed]]
    on: Error do: [:e | e class name , ': ' , e messageText].

"A reader: pages through four snapshots of db, one step per message."
Object subclass: #PageReader instanceVariableNames: 'db query size progress k tx expected pager page seen first problems ranks landed'.

PageReader class >> on: aDb query: aBlock size: aSize progress: aProgress
  ^ self new setDb: aDb query: aBlock size: aSize progress: aProgress.

PageReader >> setDb: aDb query: aBlock size: aSize progress: aProgress
  db := aDb. query := aBlock. size := aSize. progress := aProgress.
  k := 0.
  problems := OrderedCollection new.
  ranks := Set new.
  landed := 0.

"One step. With no pager open: when at least 8 k commits have landed, opens snapshot k (from 0):
 the query aBlock answers for the snapshot's root, its asArray, and a pager of aSize over it;
 otherwise nothing. Then, with a pager open, reads its next page; after the last one, checks the
 pages against the snapshot and closes it. Answers true while the reader is not done."
PageReader >> step
  | q ids |
  k > 3 ifTrue: [^ false].
  pager isNil ifTrue: [
    progress value < (8 * k) ifTrue: [^ true].
    tx := db newTransaction.
    q := query value: (PBQuery from: (tx getRootObject: 'items')).
    expected := q asArray.
    pager := q pagerSize: size.
    ranks add: pager byRank.
    seen := OrderedCollection new.
    page := 0.
    first := progress value].
  seen addAll: (pager page: page).
  page := page + 1.
  page > pager pages ifFalse: [^ true].
  landed := progress value - first.
  ids := seen asArray collect: [:each | each at: 'id'].
  (seen asArray = expected) ifFalse: [problems add: k -> 'the pages are not the snapshot''s rows'].
  ids asSet size = ids size ifFalse: [problems add: k -> 'a row shown twice'].
  (pager rows = expected size and: [pager rows = seen size]) ifFalse: [problems add: k -> 'rows'].
  tx abort.
  pager := nil.
  k := k + 1.
  ^ k <= 3.

"{ problems. byRank values. commits landed between the opening and the last page of the last
 pager }."
PageReader >> result
  ^ { problems asArray. ranks asArray. landed }.

"The value of aFuture, or the class and text of its rejection (the program thread's wait blocks
 it; it never runs an actor's message)."
Object subclass: #Outcome.
Outcome class >> of: aFuture
  ^ [aFuture waitWithin: 120000] on: Error do: [:e | e class name , ': ' , e messageText].

| c dir space db progress writers readers active ends rounds steps commits results report |
c := Check new.
dir := 'out/qry_pager_stability' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'db'.
db run: [:tx | tx setRootObject: 'items' value: ((tx newList addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: ((0 to: 399) asArray collect: [:i | PBFrozenDict withAssociations: { 'id' -> i. 'k' -> (10 * i). 'v' -> i }]))].
progress := Atom on: 0.
writers := (1 to: 3) asArray collect: [:s | (PageWriter on: db seed: s progress: progress) asActor].
readers := {
  (PageReader on: db query: [:q | q orderBy: 'k'] size: 23 progress: progress) asActor.
  (PageReader on: db query: [:q | (q where: ((PBField path: 'k') >= 1000)) orderBy: 'k' descending: true]
    size: 17 progress: progress) asActor.
  (PageReader on: db query: [:q | (q where: ((PBField path: 'v') < 300)) orderBy: 'k']
    size: 31 progress: progress) asActor }.
"active: the readers not done, as indices; a reader's step that fails ends it with its error."
active := (1 to: 3) asArray.
results := Array new: 3.
ends := OrderedCollection new.
rounds := 0.
[active isEmpty or: [rounds >= 1000]] whileFalse: [
  rounds := rounds + 1.
  steps := active collect: [:i | (readers at: i) step].
  commits := { (writers at: rounds - 1 \\ 3 + 1) commitNext }.
  steps := steps collect: [:f | Outcome of: f].
  ends addAll: (commits collect: [:f | Outcome of: f]).
  1 to: active size do: [:j |
    (steps at: j) == true ifFalse: [
      results at: (active at: j) put: ((steps at: j) == false
        ifTrue: [Outcome of: (readers at: (active at: j)) result]
        ifFalse: [steps at: j])]].
  active := (1 to: active size) asArray
    inject: #() into: [:acc :j | (steps at: j) == true ifTrue: [acc , { active at: j }] ifFalse: [acc]]].
c that: 'every reader finished within 1000 rounds'
  isTrue: active isEmpty.
c that: 'every reader saw exactly its snapshot''s rows on every pager: none twice, none skipped'
  is: (results collect: [:each | each isArray ifTrue: [each first] ifFalse: [each]])
  equals: #(#() #() #()).
c that: 'the first two readers page by rank, the third from a materialised result'
  is: (results collect: [:each | each isArray ifTrue: [each at: 2] ifFalse: [each]])
  equals: #(#(true) #(true) #(false)).
c that: 'commits landed between the opening and the last page of every reader''s last pager'
  isTrue: (results allSatisfy: [:each | each isArray and: [(each at: 3) > 0]]).
c that: 'the writers committed without an error, more than 20 times in all'
  isTrue: ((ends allSatisfy: [:each | each == #inserted or: [each == #removed]]) and: [progress value > 20]).
c that: 'a pager of the final version holds every insertion and lacks every removal'
  is: ((PBQuery from: (db newTransaction getRootObject: 'items')) pagerSize: 50) rows
  equals: 400 + (ends count: [:each | each == #inserted]) - (ends count: [:each | each == #removed]).
space close.
report := c report.
report = 'failed'
  ifTrue: [report displayNl]
  ifFalse: [('commits ' , progress value printString , ' in ' , rounds printString , ' rounds; ' , report) displayNl. 'ok' displayNl].
