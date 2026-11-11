"EXPECT: ok 16"
"PBHashDictionary rebaseOnto: (plan Task 16; ProtoBase ConcurrentOptimized.rebase_onto and
 HashDictionary._replay_op), the cases of rebase_dictionary.st: the net effect of the log
 (the last intent per key by order key, in order of last occurrence) replayed onto another
 version through setAt:value: and removeAt:. The expected contents are ProtoBase
 v2.0.0rc1's answers for the same calls (items compared by key, since a hash dictionary's
 iteration order is its hash order)."
Import from: 'protobase'.
Import from: '_check'.

| c a current merged x y ynet yr sorted |
c := Check new.
sorted := [:aDict | (aDict items asSortedCollection: [:p :q | p key printString <= q key printString]) asArray].
a := PBHashDictionary new setAt: 'a' value: 1.
current := PBHashDictionary new setAt: 'b' value: 2.
merged := a rebaseOnto: current.
c that: 'the rebase holds both' is: (sorted value: merged) equals: { 'a' -> 1. 'b' -> 2 }.
c that: 'the current version is unchanged' is: current items equals: { 'b' -> 2 }.
c that: 'the receiver is unchanged' is: a items equals: { 'a' -> 1 }.
c that: 'the replay goes through the mutators'
  is: merged opLog equals: (PBFrozenList withAll: {
    PBTuple withAll: #('set' 'b' 2). PBTuple withAll: #('set' 'a' 1) }).

"Set then remove of one key nets to remove."
x := ((PBHashDictionary new setAt: 'k' value: 1) setAt: 'j' value: 7) removeAt: 'k'.
c that: 'the log holds every intent' is: x opLog size equals: 3.
c that: 'set then remove nets to remove'
  is: (sorted value: (x rebaseOnto: ((PBHashDictionary new setAt: 'k' value: 9) setAt: 'z' value: 0)))
  equals: { 'j' -> 7. 'z' -> 0 }.

"Keys by order key; replay in order of last occurrence."
y := ((((PBHashDictionary new removeAt: 'k') setAt: 1 value: 'a') setAt: 1.0 value: 'b')
  setAt: 'm' value: 1) setAt: (Decimal fromString: '1.00') value: 'c'.
ynet := y _netOps.
c that: 'the net effect: one op per key' is: ynet size equals: 3.
c that: 'in order of last occurrence' is: (ynet collect: [:op | op at: 1]) asArray equals: #('remove' 'set' 'set').
c that: 'the last intent of the key 1' is: ((ynet at: 3) at: 3) equals: 'c'.
yr := y rebaseOnto: (PBHashDictionary new setAt: 1.0 value: 'old').
c that: 'replayed onto a current holding 1.0: the stored key object is kept'
  is: (yr keys detect: [:k | k isNumber]) class equals: Float.
c that: 'and the last value wins' is: (yr getAt: 1) equals: 'c'.
c that: 'two keys' is: yr count equals: 2.

c that: 'an empty log' is: (PBHashDictionary new rebaseOnto: current) items equals: current items.
c that: 'a remove of a key absent from current is a no-op there'
  is: ((PBHashDictionary new removeAt: 'q') rebaseOnto: current) items equals: current items.
c that: 'a current of another class' signals: PBValidationError containing: 'PBDictionary'
  during: [a rebaseOnto: PBDictionary new].
c that: 'a current that is not a collection' signals: PBValidationError during: [a rebaseOnto: nil].
c report displayNl.
