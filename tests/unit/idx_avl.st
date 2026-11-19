"EXPECT: ok 12"
"Indexed queries, plan Task 1: the AVL functions the indexes and the rank access use (ProtoBase
 proto_db/collections/avl.py at v2.0.0rc4): order-key ranges (key_iter_okey_range), the
 reversed walk (key_iter_reversed), counts and weights below an order key (key_count_below,
 key_weight_below), the balanced keyed build (key_from_sorted, key_from_sorted_okeys over
 _build_balanced, plan call IP13), the weight walk from a rank (key_iter_from_weight) and the
 walks from a position (pos_iter_from, key_iter_from). The trees are built by keyPut: from
 Random seed: 20261118: 500 keys (one in ten a String, the others even Integers), each a
 CountedKeyNode whose value is a (payload, weight) pair, weights 1 to 5. Every walk is
 compared with what the full walk (keysAndValuesDo:over:) gives, filtered, reversed, sliced
 or expanded into its occurrences. The bulk shapes of sizes 0 to 16 are written inline (the
 middle of lo..hi is (lo + hi) // 2 over 0-based bounds, so an even count puts its upper
 middle at the root); node identity with proto_db is checked by
 tests/interop/avl_ops_identical.sh (its bulk sequence), not here. The last check pins the
 laziness the plans rely on (plan call IP9): a non-local return from the walk's block stops
 the walk."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #IdxAvlProbe.

"The first { key. value. skip } of the weight walk of aRoot from aRank, or nil: the walk is
 left by a non-local return at its first triple."
IdxAvlProbe class >> first: aRoot rank: aRank descending: aBoolean
  PBAvl keyDo: [:k :v :s | ^ { k. v. s }] over: aRoot fromWeight: aRank descending: aBoolean.
  ^ nil.

"Walks aRoot from rank 0, counting each triple in anAtom, and returns from this method at the
 third: answers that triple's key."
IdxAvlProbe class >> stopAtThird: aRoot counter: anAtom
  PBAvl keyDo: [:k :v :s |
    anAtom swap: [:n | n + 1].
    anAtom value = 3 ifTrue: [^ k]] over: aRoot fromWeight: 0 descending: false.
  ^ nil.

| c r between root plain pairs okeys keyOf refuses bad probes probeOkeys total occAsc occDesc
  nodesAsc nodesDesc shape shapes expectedShapes middles bulk triples pos posValues counter
  third starts |
c := Check new.
r := Random seed: 20261118.
"An Integer in lo..hi from the high bits of the generator (as AvlOps between:and:)."
between := [:lo :hi | lo + (r next * (hi - lo + 1)) truncated].
refuses := [:aBlock | [aBlock value. false] on: PBValidationError do: [:e | e return: true]].
keyOf := [:n | (between value: 1 value: 10) = 1 ifTrue: ['s' , n printString] ifFalse: [2 * n]].
root := nil.
plain := nil.
[root isNil or: [root count < 500]] whileTrue: [
  | key weight |
  key := keyOf value: (between value: 0 value: 4999).
  weight := between value: 1 value: 5.
  root := (PBAvl keyPut: root key: key value: (PBTuple withAll: { 'p' , key printString. weight })
    nodeClass: PBCountedKeyNode) first.
  plain := (PBAvl keyPut: plain key: key value: weight nodeClass: PBKeyNode) first].
pairs := OrderedCollection new.
PBAvl keysAndValuesDo: [:k :v | pairs add: { k. v }] over: root.
pairs := pairs asArray.
okeys := pairs collect: [:p | PBKeys orderKey: (p at: 1)].
total := 0.
pairs do: [:p | total := total + ((p at: 2) at: 2)].

"1. okey range: 20 random bound pairs (a bound is open, a key of the tree, or a value that may
 be absent), each with the four inclusivity combinations, against the filtered full walk."
bad := nil.
20 timesRepeat: [
  | bound lo hi |
  bound := [
    | k |
    k := between value: 1 value: 8.
    k = 1
      ifTrue: [nil]
      ifFalse: [k <= 4
        ifTrue: [okeys at: (between value: 1 value: okeys size)]
        ifFalse: [PBKeys orderKey: (k = 5
          ifTrue: [2 * (between value: 0 value: 4999) + 1]
          ifFalse: [k = 6 ifTrue: ['s' , (between value: 0 value: 4999) printString] ifFalse: [keyOf value: (between value: 0 value: 4999)]])]]].
  lo := bound value.
  hi := bound value.
  #(true false) do: [:loInc | #(true false) do: [:hiInc |
    | got expected |
    got := OrderedCollection new.
    PBAvl keyDo: [:k :v | got add: { k. v }] over: root fromOrderKey: lo inclusive: loInc toOrderKey: hi inclusive: hiInc.
    expected := OrderedCollection new.
    pairs doWithIndex: [:p :i |
      | ok |
      ok := (lo isNil or: [| cmp | cmp := (okeys at: i) compareWith: lo. cmp > 0 or: [cmp = 0 and: [loInc]]])
        and: [hi isNil or: [| cmp | cmp := (okeys at: i) compareWith: hi. cmp < 0 or: [cmp = 0 and: [hiInc]]]].
      ok ifTrue: [expected add: p]].
    (bad isNil and: [got asArray ~= expected asArray]) ifTrue: [
      bad := 'from ' , lo printString , ' ' , loInc printString , ' to ' , hi printString , ' ' , hiInc printString
        , ': ' , got size printString , ' pairs, expected ' , expected size printString]]]].
c that: 'okey range' is: bad equals: nil.

"2. reverse: the reversed full walk."
c that: 'reverse' is: ([:out | PBAvl keyReverseDo: [:k :v | out add: { k. v }] over: root. out asArray]
  value: OrderedCollection new) equals: pairs reverse.

"Probes: 25 keys of the tree and 25 values that are not in it (odd Integers, Strings, halves)."
probes := OrderedCollection new.
25 timesRepeat: [probes add: ((pairs at: (between value: 1 value: pairs size)) at: 1)].
25 timesRepeat: [
  | k |
  k := between value: 1 value: 3.
  probes add: (k = 1
    ifTrue: [2 * (between value: -10 value: 5010) + 1]
    ifFalse: [k = 2 ifTrue: ['s' , (between value: 0 value: 9999) printString , 'x'] ifFalse: [(between value: 0 value: 9999) + 0.5]])].
probeOkeys := probes asArray collect: [:p | PBKeys orderKey: p].

"3. count below: < and <= for each probe."
bad := nil.
probeOkeys do: [:pk | #(false true) do: [:inc |
  | expected got |
  expected := (okeys select: [:k | | cmp | cmp := k compareWith: pk. cmp < 0 or: [inc and: [cmp = 0]]]) size.
  got := PBAvl keyCountBelow: root orderKey: pk inclusive: inc.
  (bad isNil and: [got ~= expected]) ifTrue: [
    bad := pk printString , ' ' , inc printString , ': ' , got printString , ', expected ' , expected printString]]].
c that: 'count below' is: bad equals: nil.

"4. bulk: the balanced build of the sorted pairs is a valid tree of the same pairs and weight,
 the build from order keys gives the same nodes, and a key out of order (or repeated) is
 refused, as an unknown node class is."
shape := nil.
shape := [:node :out |
  node isNil ifFalse: [
    out add: (node key printString , ':' , node height printString).
    shape value: node left value: out.
    shape value: node right value: out].
  out].
bulk := PBAvl keyFromSorted: pairs nodeClass: PBCountedKeyNode.
triples := pairs collect: [:p | { PBKeys orderKey: (p at: 1). p at: 1. p at: 2 }].
c that: 'bulk' is: {
  (PBAvl check: bulk) == bulk.
  ([:out | PBAvl keysAndValuesDo: [:k :v | out add: { k. v }] over: bulk. out asArray] value: OrderedCollection new) = pairs.
  (PBAvl keyWeight: bulk) = total.
  (shape value: (PBAvl keyFromSortedOrderKeys: triples nodeClass: PBCountedKeyNode) value: OrderedCollection new)
    = (shape value: bulk value: OrderedCollection new).
  (PBAvl keyFromSorted: #() nodeClass: PBKeyNode) isNil.
  refuses value: [PBAvl keyFromSorted: pairs reverse nodeClass: PBCountedKeyNode].
  refuses value: [PBAvl keyFromSorted: { #(1 'a'). #(1.0 'b') } nodeClass: PBKeyNode].
  refuses value: [PBAvl keyFromSortedOrderKeys: triples reverse nodeClass: PBCountedKeyNode].
  refuses value: [PBAvl keyFromSorted: { #(1 'a') } nodeClass: PBPosNode] }
  equals: #(true true true true true true true true true).

"5. bulk shape: keys 1..n, key:height in pre-order, for n = 0..16; the root of an even count n
 is its upper middle, key n // 2 + 1 (plan call IP13)."
expectedShapes := #(''
  '1:1'
  '2:2 1:1'
  '2:2 1:1 3:1'
  '3:3 2:2 1:1 4:1'
  '3:3 2:2 1:1 5:2 4:1'
  '4:3 2:2 1:1 3:1 6:2 5:1'
  '4:3 2:2 1:1 3:1 6:2 5:1 7:1'
  '5:4 3:3 2:2 1:1 4:1 7:2 6:1 8:1'
  '5:4 3:3 2:2 1:1 4:1 8:3 7:2 6:1 9:1'
  '6:4 3:3 2:2 1:1 5:2 4:1 9:3 8:2 7:1 10:1'
  '6:4 3:3 2:2 1:1 5:2 4:1 9:3 8:2 7:1 11:2 10:1'
  '7:4 4:3 2:2 1:1 3:1 6:2 5:1 10:3 9:2 8:1 12:2 11:1'
  '7:4 4:3 2:2 1:1 3:1 6:2 5:1 11:3 9:2 8:1 10:1 13:2 12:1'
  '8:4 4:3 2:2 1:1 3:1 6:2 5:1 7:1 12:3 10:2 9:1 11:1 14:2 13:1'
  '8:4 4:3 2:2 1:1 3:1 6:2 5:1 7:1 12:3 10:2 9:1 11:1 14:2 13:1 15:1'
  '9:5 5:4 3:3 2:2 1:1 4:1 7:2 6:1 8:1 13:3 11:2 10:1 12:1 15:2 14:1 16:1').
shapes := OrderedCollection new.
middles := true.
0 to: 16 do: [:n |
  | t words |
  t := PBAvl keyFromSorted: ((1 to: n) asArray collect: [:i | { i. i * 10 }]) nodeClass: PBKeyNode.
  PBAvl check: t.
  words := shape value: t value: OrderedCollection new.
  shapes add: (words inject: '' into: [:acc :w | acc isEmpty ifTrue: [w] ifFalse: [acc , ' ' , w]]).
  (n > 0 and: [n even]) ifTrue: [middles := middles and: [t key = (n // 2 + 1)]]].
c that: 'bulk shape' is: { shapes asArray. middles } equals: { expectedShapes. true }.

"6. weight: the total, the weights below each probe, the empty tree, and a tree that is not
 weighted, refused by each weight function."
bad := nil.
probeOkeys do: [:pk | #(false true) do: [:inc |
  | expected got |
  expected := 0.
  okeys doWithIndex: [:k :i |
    | cmp |
    cmp := k compareWith: pk.
    (cmp < 0 or: [inc and: [cmp = 0]]) ifTrue: [expected := expected + (((pairs at: i) at: 2) at: 2)]].
  got := PBAvl keyWeightBelow: root orderKey: pk inclusive: inc.
  (bad isNil and: [got ~= expected]) ifTrue: [
    bad := pk printString , ' ' , inc printString , ': ' , got printString , ', expected ' , expected printString]]].
c that: 'weight' is: {
  PBAvl keyWeight: root. bad. PBAvl keyWeight: nil.
  PBAvl keyWeightBelow: nil orderKey: (okeys at: 1) inclusive: true.
  refuses value: [PBAvl keyWeight: plain].
  refuses value: [PBAvl keyWeightBelow: plain orderKey: (okeys at: 1) inclusive: false].
  refuses value: [PBAvl keyDo: [:k :v :s | nil] over: plain fromWeight: 0 descending: false] }
  equals: { total. nil. 0. 0. true. true. true }.

"The occurrences, in each direction: entry i is { node number. skip } of rank i - 1; a node
 stands for its count consecutive occurrences, in their own order in both directions."
nodesAsc := pairs.
nodesDesc := pairs reverse.
occAsc := OrderedCollection new.
nodesAsc doWithIndex: [:p :i | 0 to: ((p at: 2) at: 2) - 1 do: [:s | occAsc add: { i. s }]].
occDesc := OrderedCollection new.
nodesDesc doWithIndex: [:p :i | 0 to: ((p at: 2) at: 2) - 1 do: [:s | occDesc add: { i. s }]].

"7. from weight: the first triple of every rank 0..W - 1, both directions; and the whole walk
 of every 50th rank."
bad := nil.
{ false -> nodesAsc -> occAsc. true -> nodesDesc -> occDesc } do: [:spec |
  | desc nodes occ |
  desc := spec key key.
  nodes := spec key value.
  occ := spec value.
  occ size = total ifFalse: [bad := 'the occurrence list has ' , occ size printString , ' entries'].
  0 to: total - 1 do: [:rank |
    | o got expected |
    o := occ at: rank + 1.
    expected := { ((nodes at: (o at: 1)) at: 1). ((nodes at: (o at: 1)) at: 2). o at: 2 }.
    got := IdxAvlProbe first: root rank: rank descending: desc.
    (bad isNil and: [got ~= expected]) ifTrue: [
      bad := 'rank ' , rank printString , ' descending ' , desc printString , ': ' , got printString
        , ', expected ' , expected printString].
    rank \\ 50 = 0 ifTrue: [
      | walk full |
      walk := OrderedCollection new.
      PBAvl keyDo: [:k :v :s | walk add: { k. v. s }] over: root fromWeight: rank descending: desc.
      full := OrderedCollection with: expected.
      (o at: 1) + 1 to: nodes size do: [:i | full add: { (nodes at: i) at: 1. (nodes at: i) at: 2. 0 }].
      (bad isNil and: [walk asArray ~= full asArray]) ifTrue: [
        bad := 'the walk from rank ' , rank printString , ' descending ' , desc printString , ' differs']]]].
c that: 'from weight' is: bad equals: nil.

"8. rank W yields nothing, in both directions and on the empty tree."
c that: 'from weight W' is: ({ { root. total. false }. { root. total. true }. { nil. 0. false } } collect: [:t |
  | n |
  n := 0.
  PBAvl keyDo: [:k :v :s | n := n + 1] over: (t at: 1) fromWeight: (t at: 2) descending: (t at: 3).
  n]) equals: #(0 0 0).

"9, 10. the ranks just outside 0..W."
c that: 'from weight W + 1' signals: PBValidationError containing: 'out of range'
  during: [PBAvl keyDo: [:k :v :s | nil] over: root fromWeight: total + 1 descending: false].
c that: 'from weight -1' signals: PBValidationError containing: 'out of range'
  during: [PBAvl keyDo: [:k :v :s | nil] over: root fromWeight: -1 descending: true].

"11. from position: posDo:over:from: on a positional tree of 61 values built by inserts, for
 every start 0..61, and keyDo:over:from: on the keyed tree for 40 starts, against the full
 walk sliced; a start outside 0..count, or not an Integer, is refused."
pos := nil.
1 to: 61 do: [:i | pos := PBAvl posInsert: pos at: (between value: 0 value: i - 1) value: i * 3].
posValues := OrderedCollection new.
PBAvl posDo: [:v | posValues add: v] over: pos.
posValues := posValues asArray.
starts := (0 to: 10) asOrderedCollection.
starts addAll: #(249 250 498 499 500).
25 timesRepeat: [starts add: (between value: 0 value: 500)].
c that: 'from position' is: {
  (0 to: 61) allSatisfy: [:s |
    | got |
    got := OrderedCollection new.
    PBAvl posDo: [:v | got add: v] over: pos from: s.
    got asArray = (posValues copyFrom: s + 1 to: posValues size)].
  starts allSatisfy: [:s |
    | got |
    got := OrderedCollection new.
    PBAvl keyDo: [:k :v | got add: { k. v }] over: root from: s.
    got asArray = (pairs copyFrom: s + 1 to: pairs size)].
  refuses value: [PBAvl posDo: [:v | nil] over: pos from: 62].
  refuses value: [PBAvl posDo: [:v | nil] over: pos from: -1].
  refuses value: [PBAvl keyDo: [:k :v | nil] over: root from: 501].
  refuses value: [PBAvl keyDo: [:k :v | nil] over: root from: true].
  refuses value: [PBAvl posDo: [:v | nil] over: root from: 0].
  refuses value: [PBAvl keyDo: [:k :v | nil] over: pos from: 0] }
  equals: #(true true true true true true true true).

"12. early exit: a non-local return from the walk's block, in a method, stops the walk at once."
counter := Atom on: 0.
third := IdxAvlProbe stopAtThird: root counter: counter.
c that: 'early exit' is: { third. counter value } equals: { (pairs at: 3) at: 1. 3 }.

c report displayNl.
