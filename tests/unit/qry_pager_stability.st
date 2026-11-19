"EXPECT: ok"
"Indexed queries, plan Task 9: pagers under concurrent writers (proto_db
 tests/concurrency/test_pager_stability.py at v2.0.0rc4, D56, R77). Three writer actors keep
 committing insertions before, inside and after the pages being read, and removals, while three
 reader actors page through snapshots: an ordered scan (by rank), a range ordered by its key,
 descending (by rank), and an unindexed condition (materialised). Each reader takes four snapshots,
 the k-th after at least 8 k commits, builds its pager on it and reads every page, waiting before
 each page after the first for at least one more commit, so commits land between the pages of
 every pager by construction, not by how the actors are scheduled. Every reader must see exactly the
 rows of its own snapshot: no row twice, none skipped, rows equal to the snapshot's asArray. The
 cached-query half of proto_db's test is not ported: the query result cache is deferred (spec 3.2,
 ruling IQ3); tests/unit/queries_checklist.tsv notes it. The writers' draws come from QData random:
 (fixed seeds); the interleaving varies from run to run, and the property holds for every one.
 Mutable state shared by the actors is two Atoms: the commit count and the number of writers done."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"A writer: commits until the readers are done (aStop), aCount being only a safety cap, as
 proto_db's MAX_COMMITS: the writers outlive every reader, so commits land between the pages of
 every pager by construction, not by the relative speed of the actors."
Object subclass: #PageWriter.

"Commits aCount changes to the root 'items' of db, drawing them from QData random: aSeed; adds one
 to aProgress after each commit and to aDone at the end. Answers { commits. insertions. removals }
 (the root never falls to 50 elements, so every removal drawn is made), or the class and text of
 the first error."
PageWriter >> write: db seed: aSeed commits: aCount progress: aProgress done: aDone stop: aStop
  | rnd n inserted removed |
  rnd := QData random: aSeed.
  n := 0. inserted := 0. removed := 0.
  ^ [[n < aCount and: [aStop value not]] whileTrue: [ | choice slot gone |
       n := n + 1.
       choice := rnd next.
       slot := (rnd next * 400) truncated.
       gone := rnd next.
       db run: [:tx | | items |
           items := tx getRootObject: 'items'.
           choice < 0.3 ifTrue: [items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (aSeed * 100000 + n). 'k' -> (0 - (aSeed * 1000) - n). 'v' -> (0 - n) })].
           (choice >= 0.3 and: [choice < 0.6]) ifTrue: [
             items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (aSeed * 100000 + n). 'k' -> (10 * slot + 5). 'v' -> n })].
           (choice >= 0.6 and: [choice < 0.8]) ifTrue: [
             items := items appendLast: (PBFrozenDict withAssociations: { 'id' -> (aSeed * 100000 + n). 'k' -> (100000 + (aSeed * 1000) + n). 'v' -> n })].
           (choice >= 0.8 and: [items count > 50]) ifTrue: [items := items removeAt: (gone * items count) truncated].
           tx setRootObject: 'items' value: items]
         retries: 500 backoff: #(0 5).
       choice < 0.8 ifTrue: [inserted := inserted + 1] ifFalse: [removed := removed + 1].
       aProgress swap: [:x | x + 1]].
     aDone swap: [:x | x + 1].
     { n. inserted. removed }]
    on: Error do: [:e | aDone swap: [:x | x + 1]. e class name , ': ' , e messageText].

"A reader: pages through four snapshots of db."
Object subclass: #PageReader.

"Waits until aProgress holds at least aTarget, or every writer is done."
PageReader >> wait: aProgress for: aTarget done: aDone
  [aProgress value < aTarget and: [aDone value < 3]] whileTrue: [(Future after: 1) wait].

"Four snapshots, the k-th (k from 0) after at least 8 k commits; on each, the query aBlock answers
 for the snapshot's root, its asArray, and a pager of aSize over it, every page read with a commit
 waited for before each page after the first. Answers { problems. byRank values. commits seen
 between the first and the last page of the last pager }, or the class and text of an error."
PageReader >> read: db query: aBlock size: aSize progress: aProgress done: aDone
  | problems ranks landed |
  problems := OrderedCollection new.
  ranks := Set new.
  landed := 0.
  ^ [0 to: 3 do: [:k | | tx query expected pager seen first ids |
       self wait: aProgress for: 8 * k done: aDone.
       tx := db newTransaction.
       query := aBlock value: (PBQuery from: (tx getRootObject: 'items')).
       expected := query asArray.
       pager := query pagerSize: aSize.
       ranks add: pager byRank.
       seen := OrderedCollection new.
       first := aProgress value.
       0 to: pager pages do: [:p |
         p > 0 ifTrue: [self wait: aProgress for: aProgress value + 1 done: aDone].
         seen addAll: (pager page: p)].
       landed := aProgress value - first.
       ids := seen asArray collect: [:each | each at: 'id'].
       (seen asArray = expected) ifFalse: [problems add: k -> 'the pages are not the snapshot''s rows'].
       ids asSet size = ids size ifFalse: [problems add: k -> 'a row shown twice'].
       (pager rows = expected size and: [pager rows = seen size]) ifFalse: [problems add: k -> 'rows'].
       tx abort].
     { problems asArray. ranks asArray. landed }]
    on: Error do: [:e | e class name , ': ' , e messageText].

| c dir space db progress done stop writers readers results ends report |
c := Check new.
dir := 'out/qry_pager_stability' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'db'.
db run: [:tx | tx setRootObject: 'items' value: ((tx newList addIndex: (PBRangeIndex name: 'k' path: 'k'))
  extend: ((0 to: 399) asArray collect: [:i | PBFrozenDict withAssociations: { 'id' -> i. 'k' -> (10 * i). 'v' -> i }]))].
progress := Atom on: 0.
done := Atom on: 0.
stop := Atom on: false.
writers := (1 to: 3) asArray collect: [:s |
  PageWriter new asActor write: db seed: s commits: 1500 progress: progress done: done stop: stop].
readers := {
  PageReader new asActor read: db query: [:q | q orderBy: 'k'] size: 23 progress: progress done: done.
  PageReader new asActor read: db query: [:q | (q where: ((PBField path: 'k') >= 1000)) orderBy: 'k' descending: true]
    size: 17 progress: progress done: done.
  PageReader new asActor read: db query: [:q | (q where: ((PBField path: 'v') < 300)) orderBy: 'k']
    size: 31 progress: progress done: done }.
results := readers collect: [:f | f waitWithin: 600000].
stop swap: [:x | true].
ends := writers collect: [:f | f waitWithin: 600000].
c that: 'every reader saw exactly its snapshot''s rows on every pager: none twice, none skipped'
  is: (results collect: [:each | each isString ifTrue: [each] ifFalse: [each first]])
  equals: #(#() #() #()).
c that: 'the first two readers page by rank, the third from a materialised result'
  is: (results collect: [:each | each isString ifTrue: [each] ifFalse: [each at: 2]])
  equals: #(#(true) #(true) #(false)).
c that: 'commits landed between the pages of every reader''s last pager'
  isTrue: (results allSatisfy: [:each | each isString not and: [(each at: 3) > 0]]).
c that: 'the writers committed without an error, more than 20 times in all'
  isTrue: ((ends allSatisfy: [:each | each isArray]) and: [progress value > 20]).
c that: 'a pager of the final version holds every insertion and lacks every removal'
  is: ((PBQuery from: (db newTransaction getRootObject: 'items')) pagerSize: 50) rows
  equals: (ends inject: 400 into: [:acc :each | each isArray ifTrue: [acc + (each at: 2) - (each at: 3)] ifFalse: [acc]]).
space close.
report := c report.
report = 'failed'
  ifTrue: [report displayNl]
  ifFalse: [('commits ' , progress value printString , '; ' , report) displayNl. 'ok' displayNl].
