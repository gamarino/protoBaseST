"EXPECT: ok 3"
"Indexed roots written by many actors at once (indexed queries, plan Task 4b): proto_db's
 tests/concurrency/test_indexed_roots.py and test_index_weights_concurrency.py at v2.0.0rc4, on a
 file space, with fewer writers and writes than proto_db's 16 threads (protoBaseST's index writes
 are about thirty times slower, docs/deviations.md M1).

 (1) test_appends_to_an_indexed_list: 4 actors append 10 records each to an indexed PBList root
 (a read-modify-write: PBList is not ConcurrentOptimized, so a lost race conflicts and run:
 retries it). The list holds every record exactly once, each actor's in its own order, 40 commits
 were counted, and both indexes validate and answer like a scan (every key's countOfKey: equals
 the occurrences a scan finds). (2) test_blind_set_at_on_an_indexed_dictionary: 4 actors each
 blind-write 15 times into an indexed PBDictionary root (a new dictionary with one key of its own
 and one of 5 shared keys; the root never read: merged onto the current value). Every own key
 holds what its writer wrote, a shared key one of the values written to it, the seed is kept, no
 attempt conflicted, and the indexes validate and answer like a scan. (3) The half of
 test_weights_are_exact_after_concurrent_merges_and_retries that needs no plan: 4 actors, two
 blind writers and two read-modify-writers (inserts, updates of the indexed field, removals, and
 appends to an indexed PBList), on a PBDictionary and a PBList each indexed on 'k'; on snapshots
 taken during the run and at the end, every group's total equals its members' recount and its
 members tree's weight, the groups tree's weight plus the side group equals the index's total,
 and the index validates; keys only a blind writer writes are in the final dictionary (the merge
 path ran). Its rank windows (ordered plans, window:) are ported with Task 6. Spaces go to
 out/idx_indexed_roots (git ignores out/), a new directory per run."
Import from: 'random'.
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #RootWriter instanceVariableNames: 'attempts conflicts'.

"Answers { commits. attempts. conflicts }: n appends of { t. i } records to 'log'."
RootWriter >> append: n as: t in: aDb
  attempts := 0.
  conflicts := 0.
  0 to: n - 1 do: [:i | | rec |
    rec := PBObject withAll: { 't' -> t. 'i' -> i. 'seq' -> (t * 1000 + i) }.
    aDb run: [:tr |
      attempts := attempts + 1.
      tr setRootObject: 'log' value: ((tr getRootObject: 'log') appendLast: rec)] retries: 10000].
  ^ { n. attempts }.

"Answers { commits. attempts }: n blind writes into 'd', each a new dictionary with an own key and a
 shared key."
RootWriter >> blind: n as: t shared: s in: aDb
  attempts := 0.
  0 to: n - 1 do: [:i | | own shared |
    own := PBObject withAll: { 't' -> t. 'i' -> i }.
    shared := PBObject withAll: { 't' -> t. 'i' -> i }.
    aDb run: [:tr |
      attempts := attempts + 1.
      tr setRootObject: 'd' value: ((tr newDictionary setAt: 't' , t printString , '-' , i printString value: own)
        setAt: 'shared-' , (i \\ s) printString value: shared)] retries: 10000].
  ^ { n. attempts }.

"proto_db's worker of test_weights_are_exact_after_concurrent_merges_and_retries, n changes:
 an odd seed blind-writes, an even one reads and writes 'd' (and every fourth change 'l').
 Snapshots of ('d', 'l') every tenth change. Answers the snapshots."
RootWriter >> weights: n seed: aSeed in: aDb
  | rnd snaps |
  rnd := Random seed: aSeed.
  snaps := OrderedCollection new.
  0 to: n - 1 do: [:i | | key |
    key := rnd nextInt: 40.
    aDb run: [:tr | | roll d lst |
      roll := rnd next.
      aSeed odd
        ifTrue: [
          tr setRootObject: 'd' value: ((tr newDictionary
            setAt: key value: (PBObject withAll: { 'k' -> (rnd nextInt: 10). 'w' -> aSeed. 'i' -> i }))
            setAt: 2000 + (100 * aSeed) + i value: (PBObject withAll: { 'k' -> (rnd nextInt: 10) }))]
        ifFalse: [
          d := tr getRootObject: 'd'.
          roll < 0.5
            ifTrue: [d := d setAt: key value: (PBObject withAll: { 'k' -> (rnd nextInt: 10). 'w' -> aSeed. 'i' -> i })]
            ifFalse: [
              (roll < 0.7 and: [d has: key])
                ifTrue: [d := d removeAt: key]
                ifFalse: [d := d setAt: 1000 * aSeed + i
                  value: (PBObject withAll: { 'k' -> (roll > 0.95 ifTrue: [nil] ifFalse: [rnd nextInt: 10]) })]].
          tr setRootObject: 'd' value: d.
          i \\ 4 = 0 ifTrue: [
            lst := (tr getRootObject: 'l') appendLast: (PBObject withAll: { 'k' -> (rnd nextInt: 10). 'w' -> aSeed }).
            (lst count > 5 and: [roll < 0.3]) ifTrue: [lst := lst removeAt: (rnd nextInt: lst count) - 1].
            tr setRootObject: 'l' value: lst]]] retries: 1000.
    i \\ 10 = 0 ifTrue: [ | tr |
      tr := aDb newTransaction.
      snaps addLast: { tr getRootObject: 'd'. tr getRootObject: 'l' }.
      tr abort]].
  ^ snaps asArray.

| c dir space db t0 log records futures counts scanAgrees d content shared own exact snaps final |
c := Check new.
dir := 'out/idx_indexed_roots' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
dir ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString) lockTimeout: 600000.
db := space newDatabase: 'db'.

"nil when every index of aCollection validates and every key's countOfKey: equals the occurrences
 a scan of its elements finds (order keys compared); otherwise what differs."
scanAgrees := [:aCollection | | elements problem |
  problem := nil.
  elements := aCollection elements.
  [aCollection validate] on: PBDBError do: [:e | problem := e class name , ': ' , e messageText].
  aCollection indexNames do: [:name | | index spec |
    index := aCollection getIndex: name.
    spec := index keySpecObject.
    elements do: [:e | | k ok scanned |
      k := spec extract: e.
      ok := PBMemberKeys orderKeyOrNil: k.
      ok isNil ifFalse: [
        scanned := elements count: [:x | | xk | xk := PBMemberKeys orderKeyOrNil: (spec extract: x).
          xk notNil and: [(xk compareWith: ok) = 0]].
        (index countOfKey: k) = scanned ifFalse: [problem := name , ' countOfKey: ' , k printString]]]].
  problem].

"(1)"
db run: [:tr | tr setRootObject: 'log' value: ((tr newList
  addIndex: (PBEqualityIndex name: 'by_t' path: 't')) addIndex: (PBRangeIndex name: 'by_seq' path: 'seq'))].
futures := (0 to: 3) collect: [:t | RootWriter new asActor append: 10 as: t in: db].
counts := futures collect: [:f | f waitWithin: 600000].
log := db newTransaction getRootObject: 'log'.
records := log elements collect: [:e | { e at: 't'. e at: 'i' }].
c that: 'appends to an indexed List from 4 actors: each record once, in its writer''s order; the indexes answer like a scan'
  is: { log count. (records asSortedCollection: [:x :y | (x at: 1) < (y at: 1) or: [(x at: 1) = (y at: 1) and: [(x at: 2) <= (y at: 2)]]]) asArray
      = ((0 to: 3) inject: #() into: [:acc :t | acc , ((0 to: 9) collect: [:i | { t. i }]) asArray]).
    (0 to: 3) allSatisfy: [:t | ((records select: [:r | (r at: 1) = t]) collect: [:r | r at: 2]) asArray = (0 to: 9) asArray].
    (counts inject: 0 into: [:acc :x | acc + (x at: 1)]). scanAgrees value: log }
  equals: { 40. true. true. 40. nil }.

"(2)"
db run: [:tr | tr setRootObject: 'd' value: (((tr newDictionary
  addIndex: (PBEqualityIndex name: 'by_t' path: 't')) addIndex: (PBRangeIndex name: 'by_i' path: 'i'))
  setAt: 'seed' value: (PBObject withAll: { 't' -> -1. 'i' -> -1 }))].
futures := (0 to: 3) collect: [:t | RootWriter new asActor blind: 15 as: t shared: 5 in: db].
counts := futures collect: [:f | f waitWithin: 600000].
d := db newTransaction getRootObject: 'd'.
content := Dictionary new.
d keysAndValuesDo: [:k :v | content at: k put: { v at: 't'. v at: 'i' }].
own := (0 to: 3) allSatisfy: [:t | (0 to: 14) allSatisfy: [:i |
  (content at: 't' , t printString , '-' , i printString ifAbsent: [nil]) = { t. i }]].
shared := (0 to: 4) allSatisfy: [:s | | v | v := content at: 'shared-' , s printString ifAbsent: [nil].
  v notNil and: [(v at: 2) \\ 5 = s]].
c that: 'blind setAt: into an indexed Dictionary from 4 actors: every own key, a written value on each shared key, no conflict; the indexes answer like a scan'
  is: { own. shared. content at: 'seed'. d count. counts collect: [:x | (x at: 2) - (x at: 1)]. scanAgrees value: d }
  equals: { true. true. #(-1 -1). 1 + 60 + 5. #(0 0 0 0). nil }.

"(3)"
db run: [:tr |
  tr setRootObject: 'd' value: (tr newDictionary addIndex: (PBRangeIndex name: 'k' path: 'k')).
  tr setRootObject: 'l' value: (tr newList addIndex: (PBRangeIndex name: 'k' path: 'k'))].
futures := (0 to: 3) collect: [:s | RootWriter new asActor weights: 30 seed: s in: db].
snaps := OrderedCollection new.
futures do: [:f | snaps addAll: (f waitWithin: 600000)].
final := db newTransaction.
snaps addLast: { final getRootObject: 'd'. final getRootObject: 'l' }.
"nil when anIndex's weights are exact (tests/support/index_weights.py assert_exact_weights) and it
 validates against aCollection's elements; otherwise what differs."
exact := [:aCollection | | index recount problem side sideN |
  index := aCollection getIndex: 'k'.
  problem := nil.
  recount := 0.
  PBAvl keysAndValuesDo: [:key :group | | n |
    n := 0.
    PBKeyGroups group: group do: [:e :k | n := n + k].
    (n = (group at: 2) and: [n = (PBAvl keyWeight: (group at: 1))]) ifFalse: [problem := 'group ' , key printString].
    recount := recount + n] over: index groups.
  (PBAvl keyWeight: index groups) = recount ifFalse: [problem := 'groups weight'].
  side := index side.
  sideN := 0.
  PBKeyGroups group: side do: [:e :k | sideN := sideN + k].
  (sideN = (side at: 2) and: [sideN = (PBAvl keyWeight: (side at: 1))]) ifFalse: [problem := 'side group'].
  recount + sideN = index count ifFalse: [problem := 'total'].
  [index validate: aCollection elements] on: PBDBError do: [:e | problem := e class name , ': ' , e messageText].
  problem].
c that: 'index weights are exact and the indexes validate on every snapshot after concurrent merges and retries; the blind writes merged'
  is: { (snaps collect: [:pair | { exact value: (pair at: 1). exact value: (pair at: 2) }]) asSet asArray.
    (snaps last at: 1) count > 0. (snaps last at: 2) count > 0.
    #(1 3) allSatisfy: [:s | (0 to: 29) anySatisfy: [:i | (snaps last at: 1) has: 2000 + (100 * s) + i]] }
  equals: { { #(nil nil) }. true. true. true }.
final abort.
space close.
c report displayNl.
