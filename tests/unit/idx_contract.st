"EXPECT: ok 6"
"Indexed queries, plan Task 3: the structure half of proto_db's index contract
 (tests/contracts/index_contract.py at v2.0.0rc4; the plan half, plan == scan, joins in Task 7)
 for PBEqualityIndex and PBRangeIndex, on QData values: 300 (the element key spec, every value
 rank) and QData people: 300 (the path 'age', mixed numbers, absent and nil), for the seeds
 1..PBST_PROP_SEEDS (default 8, proto_db's contract count; plan call IP16; from PBST_PROP_SEED_FROM when set):
   (b) random add, remove and replace sequences keep validate: passing, and the stored multiset
       (membersDo:) equals the model's (QData bagOf:)
   withReplaced:with: equals withRemoved: then withAdded:, node for node
   build: holds what the fold of withAdded: from empty holds, node for node in key order (keys,
       member keys, elements, counts; the shapes differ: balanced against insertion order),
       whatever the receiver holds
   (c) save and lazy load: the loaded index has the definition and the explain of the saved one,
       validates, and keeps working (add, remove)
   (g) no hook changes its receiver (state, explain), and each answers a new index of the
       same class, name and key spec
   (d) readers are unaffected by concurrent writers: four actors derive versions from one index
       while it is read, and every version they answer validates against its own model
 (b) runs at proto_db's cadence (30 steps, validate: and the oracle after each). The other checks
 are smaller than first written, to bound the run time: 8 replacements on 80 elements, saved
 indexes of 120 elements, readers dumping 5 times.
 Saves go to out/idx_contract (git ignores out/), a new directory per run, so runs over disjoint
 seed ranges may run in parallel."
Import from: 'random'.
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"One writer of the concurrency check: derives 60 versions from an index, removing every third
 step and adding otherwise, and answers { version. model }."
Object subclass: #IdxWriter instanceVariableNames: 'index model seed'.

IdxWriter class >> index: anIndex model: anArray seed: anInteger
  ^ self basicNew setIndex: anIndex model: anArray seed: anInteger.

IdxWriter >> setIndex: anIndex model: anArray seed: anInteger
  index := anIndex.
  model := anArray.
  seed := anInteger.

IdxWriter >> run
  | version current |
  version := index.
  current := OrderedCollection withAll: model.
  0 to: 59 do: [:i |
    i \\ 3 = 2
      ifTrue: [
        | victim |
        victim := current removeAt: (seed * 31 + i) \\ current size + 1.
        version := version withRemoved: victim]
      ifFalse: [
        | e |
        e := PBObject withAll: { 'age' -> ((seed + i) \\ 9). 'n' -> i negated }.
        version := version withAdded: e.
        current addLast: e]].
  ^ { version. current asArray }.

"Reads an index 20 times and answers the dumps it saw."
Object subclass: #IdxReader instanceVariableNames: 'index'.

IdxReader class >> index: anIndex
  ^ self basicNew setIndex: anIndex.

IdxReader >> setIndex: anIndex
  index := anIndex.

IdxReader >> run
  | seen |
  seen := Set new.
  5 timesRepeat: [seen add: (QData dump: index); add: index explain printString].
  ^ seen size.

| c seeds kinds sets fails expect dump fold bag random draw base storage saved |
c := Check new.
seeds := QData seedRange: 8.
kinds := { PBEqualityIndex. PBRangeIndex }.
fails := OrderedCollection new.
expect := [:label :actual :expected |
  actual = expected ifFalse: [fails add: label , ': expected ' , expected printString , ', got ' , actual printString]].
dump := [:index | QData dump: index].
fold := [:index :all | | out | out := index empty. all do: [:e | out := out withAdded: e]. out].
"The stored multiset of an index, as QData bagOf: counts a collection."
bag := [:index | | out |
  out := Dictionary new.
  index membersDo: [:e :k | | id | id := PBMemberKeys identityOf: e. out at: id put: (out at: id ifAbsent: [0]) + k].
  out].
"{ label. key spec. elements } for a seed."
sets := [:seed | {
  { 'values'. PBKeySpec element. QData values: 300 seed: seed }.
  { 'people'. PBKeySpec path: 'age'. QData people: 300 seed: seed } }].

"(b) random add, remove and replace keep validate: passing, at proto_db's cadence
 (check_mutation_sequence, index_contract.py 244-278): from empty or, half the time, from the build
 of 0 to 14 elements, 30 steps, each followed by assert_consistent's structure half: validate:
 and the stored multiset against the model (the oracle)."
fails := OrderedCollection new.
seeds do: [:seed |
  random := QData random: seed.
  draw := [:k | (random next * k) truncated + 1].
  (sets value: seed) do: [:set |
    kinds do: [:k |
      | index model pool |
      pool := set last.
      model := OrderedCollection new.
      index := k name: 'idx' keySpec: (set at: 2).
      random next < 0.5 ifTrue: [
        ((random next * 15) truncated) timesRepeat: [model addLast: (pool at: (draw value: pool size))].
        index := index build: model].
      1 to: 30 do: [:step |
        | r label |
        r := random next.
        label := k name , ' ' , set first , ' seed ' , seed printString , ' step ' , step printString.
        (model isEmpty or: [r < 0.45])
          ifTrue: [
            | e |
            e := (model notEmpty and: [random next < 0.25]) ifTrue: [model at: (draw value: model size)] ifFalse: [pool at: (draw value: pool size)].
            index := index withAdded: e.
            model addLast: e]
          ifFalse: [
            r < 0.75
              ifTrue: [index := index withRemoved: (model removeAt: (draw value: model size))]
              ifFalse: [
                | i new |
                i := draw value: model size.
                new := pool at: (draw value: pool size).
                index := index withReplaced: (model at: i) with: new.
                model at: i put: new]].
        [index validate: model] on: PBCorruptionError do: [:e | fails add: label , ': ' , e messageText. e return: nil].
        expect value: label , ' bag' value: (bag value: index) value: (QData bagOf: model)].
      expect value: k name , ' ' , set first , ' count' value: index count value: model size]]].
c that: 'random add, remove and replace keep validate: passing' is: fails asArray equals: #().

"withReplaced:with: equals withRemoved: then withAdded: (check_hook_equivalences)."
fails := OrderedCollection new.
seeds do: [:seed |
  random := QData random: seed + 1000.
  (sets value: seed) do: [:set |
    kinds do: [:k |
      | elements index |
      elements := set last copyFrom: 1 to: 80.
      index := (k name: 'idx' keySpec: (set at: 2)) build: elements.
      8 timesRepeat: [
        | old new |
        old := elements at: (random next * elements size) truncated + 1.
        new := set last at: (random next * set last size) truncated + 1.
        expect value: k name , ' ' , set first , ' seed ' , seed printString
          value: (dump value: (index withReplaced: old with: new))
          value: (dump value: ((index withRemoved: old) withAdded: new))]]]].
c that: 'withReplaced:with: equals remove then add' is: fails asArray equals: #().

"build: holds the fold of withAdded: from empty, node for node in key order, whatever the receiver
 holds (check_hook_equivalences)."
fails := OrderedCollection new.
seeds do: [:seed |
  (sets value: seed) do: [:set |
    kinds do: [:k |
      | populated other |
      populated := (k name: 'idx' keySpec: (set at: 2)) build: (set last copyFrom: 1 to: 50).
      expect value: k name , ' ' , set first , ' seed ' , seed printString
        value: (QData contents: (populated build: set last)) value: (QData contents: (fold value: populated value: set last)).
      other := set last copyFrom: 151 to: 300.
      expect value: k name , ' ' , set first , ' seed ' , seed printString , ' rebuilt'
        value: (QData contents: (populated build: other)) value: (QData contents: (fold value: populated value: other)).
      [(populated build: other) validate: other] on: PBCorruptionError do: [:e | fails add: e messageText. e return: nil]]]].
c that: 'build: holds the fold of withAdded:' is: fails asArray equals: #().

"(c) save and lazy load (check_persistence, test_persistence_roundtrip_keeps_answers,
 test_key_spec_survives_persistence): the loaded index has the definition and the explain of the
 saved one, validates, and keeps working."
fails := OrderedCollection new.
PBKeySpec registerExtractor: 'tests.idx_contract.age' block: [:e | (PBKeySpec path: 'age') extract: e] version: '1'.
base := 'out/idx_contract' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
base ensureCreateDirectory.
storage := PBFileStorage path: base pathString.
saved := OrderedCollection new.
seeds do: [:seed |
  (sets value: seed) , { { 'extractor'. PBKeySpec extractor: 'tests.idx_contract.age'. QData people: 300 seed: seed } } do: [:set |
    kinds do: [:k |
      | index |
      index := (k name: 'saved_' , seed printString keySpec: (set at: 2)) build: (set last copyFrom: 1 to: 120).
      index _saveInto: storage.
      saved addLast: { k. set. index. seed }]]].
storage close.
"Read back through a fresh storage on the same directory: nothing is cached."
storage := PBFileStorage path: base pathString.
expect value: 'saved indexes' value: saved size value: seeds size * 6.
saved do: [:each |
  | k set index elements loaded extra victim rest label |
  k := each at: 1. set := each at: 2. index := each at: 3.
  random := QData random: (each at: 4) + 2000.
  label := k name , ' ' , set first , ' seed ' , (each at: 4) printString.
  elements := set last copyFrom: 1 to: 120.
  loaded := k unloadedAt: index pointer storage: storage.
  expect value: label , ' loads lazily' value: loaded isLoaded value: false.
  expect value: label , ' definition' value: { loaded class. loaded name. loaded keySpecObject. loaded keySpec }
    value: { k. index name. set at: 2. index keySpec }.
  expect value: label , ' explain' value: loaded explain value: index explain.
  [loaded validate: elements] on: PBCorruptionError do: [:e | fails add: label , ' loaded: ' , e messageText. e return: nil].
  extra := set last at: (random next * set last size) truncated + 1.
  [(loaded withAdded: extra) validate: elements , { extra }] on: PBCorruptionError do: [:e |
    fails add: label , ' loaded, then added: ' , e messageText. e return: nil].
  victim := (random next * elements size) truncated + 1.
  rest := (elements copyFrom: 1 to: victim - 1) , (elements copyFrom: victim + 1 to: elements size).
  [(loaded withRemoved: (elements at: victim)) validate: rest] on: PBCorruptionError do: [:e |
    fails add: label , ' loaded, then removed: ' , e messageText. e return: nil]].
storage close.
c that: 'save and lazy load give equal explain' is: fails asArray equals: #().

"(g) no hook changes its receiver (check_hooks_do_not_mutate, and check_empty: empty keeps the
 definition and holds nothing)."
fails := OrderedCollection new.
seeds do: [:seed |
  random := QData random: seed + 3000.
  (sets value: seed) do: [:set |
    kinds do: [:k |
      | elements index new victim before calls |
      elements := set last copyFrom: 1 to: (random next * 29) truncated + 1.
      index := (k name: 'idx' keySpec: (set at: 2)) build: elements.
      new := set last at: (random next * set last size) truncated + 1.
      victim := elements at: (random next * elements size) truncated + 1.
      calls := {
        'withAdded:' -> [index withAdded: new].
        'withRemoved:' -> [index withRemoved: victim].
        'withReplaced:with:' -> [index withReplaced: victim with: new].
        'build:' -> [index build: { new }].
        'empty' -> [index empty] }.
      calls do: [:call |
        | result label |
        label := k name , ' ' , set first , ' seed ' , seed printString , ' ' , call key.
        before := { dump value: index. index explain }.
        result := call value value.
        expect value: label , ' receiver' value: { dump value: index. index explain } value: before.
        expect value: label , ' answer' value: { result class. result name. result keySpec. result == index }
          value: { k. index name. index keySpec. false }].
      expect value: k name , ' empty holds nothing' value: { index empty count. index empty groupCount } value: #(0 0).
      before := { dump value: index. index explain }.
      index validate: elements; explain; groupCount; count.
      index membersDo: [:e :m | nil].
      expect value: k name , ' a read hook' value: { dump value: index. index explain } value: before]]].
c that: 'no hook changes its receiver' is: fails asArray equals: #().

"(d) test_readers_unaffected_by_concurrent_writers, at structure level: eight readers read one
 version (its dump and explain never change) while four writers derive versions from it; every
 version validates against its writer's model, and the shared one against its own."
fails := OrderedCollection new.
kinds do: [:k |
  | elements index readers writers seen derived |
  elements := (0 to: 199) asArray collect: [:i | PBObject withAll: { 'age' -> (i \\ 7). 'n' -> i }].
  index := (k name: 'by_age' path: 'age') build: elements.
  readers := (1 to: 8) asArray collect: [:i | (IdxReader index: index) asActor].
  writers := (0 to: 3) asArray collect: [:s | (IdxWriter index: index model: elements seed: s) asActor].
  seen := readers collect: [:r | r run].
  derived := writers collect: [:w | w run].
  seen := seen collect: [:f | f wait].
  derived := derived collect: [:f | f wait].
  expect value: k name , ' readers saw one version' value: seen asSet asArray value: #(2).
  derived do: [:pair |
    [pair first validate: pair last] on: PBCorruptionError do: [:e | fails add: k name , ' derived: ' , e messageText. e return: nil].
    expect value: k name , ' derived count' value: pair first count value: pair last size].
  [index validate: elements] on: PBCorruptionError do: [:e | fails add: k name , ' shared: ' , e messageText. e return: nil]].
c that: 'readers are unaffected by concurrent writers' is: fails asArray equals: #().

c report displayNl.
