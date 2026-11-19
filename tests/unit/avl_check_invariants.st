"EXPECT: ok 31"
"Plan Task 14: PBAvl check: verifies the invariants of format spec 'AVL nodes' (ProtoBase
 avl.check_invariants) and signals PBCorruptionError on the first violation: height,
 count, balance, strictly increasing key order, weight, and one node class per tree. The
 trees here are built node by node with wrong fields (as damaged records would read).
 Also the argument checks of the write functions (PBValidationError, as ProtoBase's
 ProtoValidationError): indexes are Integers in range, a root is a tree of the expected
 kind, keys are orderable. Every function answers a new root and leaves its input as it
 was."
Import from: 'protobase'.
Import from: '_check'.
| c mk pos key cnt leaf good root before cached |
c := Check new.
mk := [:cls :assocs | cls _unsavedWithState: (PBFrozenDict withAssociations: assocs)].
pos := [:v :l :r :h :n | mk value: PBPosNode value: { 'value' -> v. 'left' -> l. 'right' -> r. 'height' -> h. 'count' -> n }].
key := [:k :l :r :h :n | mk value: PBKeyNode value: { 'key' -> k. 'value' -> 0. 'left' -> l. 'right' -> r. 'height' -> h. 'count' -> n }].
cnt := [:k :p :l :r :h :n :w | mk value: PBCountedKeyNode value: {
  'key' -> k. 'value' -> p. 'left' -> l. 'right' -> r. 'height' -> h. 'count' -> n. 'weight' -> w }].
leaf := pos value: 1 value: nil value: nil value: 1 value: 1.
good := pos value: 2 value: leaf value: nil value: 2 value: 2.
c that: 'a valid tree passes and is answered' is: (PBAvl check: good) == good equals: true.
c that: 'the empty tree passes' is: (PBAvl check: nil) equals: nil.
c that: 'wrong height' signals: PBCorruptionError containing: 'height' during: [
  PBAvl check: (pos value: 2 value: leaf value: nil value: 3 value: 2)].
c that: 'wrong count' signals: PBCorruptionError containing: 'count' during: [
  PBAvl check: (pos value: 2 value: leaf value: nil value: 2 value: 5)].
c that: 'unbalanced' signals: PBCorruptionError containing: 'balance' during: [
  PBAvl check: (pos value: 3 value: good value: nil value: 3 value: 3)].
c that: 'a height that is not an Integer' signals: PBCorruptionError during: [
  PBAvl check: (pos value: 2 value: leaf value: nil value: 'two' value: 2)].
c that: 'an implausible root height' signals: PBCorruptionError containing: 'height' during: [
  PBAvl check: (pos value: 2 value: nil value: nil value: 200 value: 1)].
c that: 'a child that is not a node' signals: PBCorruptionError during: [
  PBAvl check: (pos value: 2 value: 7 value: nil value: 2 value: 2)].
c that: 'a value box as a child' signals: PBCorruptionError during: [
  PBAvl check: (pos value: 2 value: (mk value: PBValueBox value: { 'value' -> 'x' }) value: nil value: 2 value: 2)].
c that: 'a root that is not a node' signals: PBCorruptionError during: [
  PBAvl check: (mk value: PBValueBox value: { 'value' -> 'x' })].
c that: 'a keyed node under a positional root' signals: PBCorruptionError containing: 'kind' during: [
  PBAvl check: (pos value: 2 value: (key value: 1 value: nil value: nil value: 1 value: 1) value: nil value: 2 value: 2)].
c that: 'keys out of order' signals: PBCorruptionError containing: 'order' during: [
  PBAvl check: (key value: 1 value: (key value: 2 value: nil value: nil value: 1 value: 1) value: nil value: 2 value: 2)].
c that: 'two equal keys (1 and 1.0)' signals: PBCorruptionError containing: 'order' during: [
  PBAvl check: (key value: 1 value: nil value: (key value: 1.0 value: nil value: nil value: 1 value: 1) value: 2 value: 2)].
c that: 'an unorderable key' signals: PBCorruptionError during: [
  PBAvl check: (key value: (PBFrozenList withAll: #(1)) value: nil value: nil value: 1 value: 1)].
c that: 'keys in order pass' is: (PBAvl check: (key value: 2 value: (key value: 1 value: nil value: nil value: 1 value: 1) value: nil value: 2 value: 2)) notNil equals: true.
"Review R2-I1: check: recomputes each order key from the key, as check_invariants does: a
 root of key 5 whose cached order key is 2's, over keys 1 and 3, is in order only by the
 cache (keyAt: 5 would miss it)."
c that: 'a cached order key that is not the key''s' signals: PBCorruptionError containing: 'cached order key' during: [
  PBAvl check: ((key value: 5 value: (key value: 1 value: nil value: nil value: 1 value: 1)
    value: (key value: 3 value: nil value: nil value: 1 value: 1) value: 2 value: 3)
    _publishOrderKey: (PBKeys orderKey: 2); yourself)].
cached := (key value: 2 value: (key value: 1 value: nil value: nil value: 1 value: 1)
  value: (key value: 3 value: nil value: nil value: 1 value: 1) value: 2 value: 3) _publishOrderKey: (PBKeys orderKey: 2.0); yourself.
c that: 'a cached order key equal to the key''s passes' isTrue: (PBAvl check: cached) == cached.
c that: 'a CountedKeyNode under a KeyNode root' signals: PBCorruptionError containing: 'kind' during: [
  PBAvl check: (key value: 2 value: (cnt value: 1 value: (PBTuple withAll: #(0 1)) value: nil value: nil value: 1 value: 1 value: 1) value: nil value: 2 value: 2)].
c that: 'wrong weight' signals: PBCorruptionError containing: 'weight' during: [
  PBAvl check: (cnt value: 2 value: (PBTuple withAll: #(0 2))
    value: (cnt value: 1 value: (PBTuple withAll: #(0 1)) value: nil value: nil value: 1 value: 1 value: 1)
    value: nil value: 2 value: 2 value: 4)].
c that: 'a weighted value that is not a pair' signals: PBCorruptionError during: [
  PBAvl check: (cnt value: 1 value: 5 value: nil value: nil value: 1 value: 1 value: 1)].
c that: 'right weights pass' is: (PBAvl check: (cnt value: 2 value: (PBTuple withAll: #(0 2))
    value: (cnt value: 1 value: (PBTuple withAll: #(0 1)) value: nil value: nil value: 1 value: 1 value: 1)
    value: nil value: 2 value: 2 value: 3)) notNil equals: true.
"Argument checks."
root := PBAvl posAppend: (PBAvl posAppend: nil value: 'a') value: 'b'.
c that: 'an index past the end' signals: PBValidationError during: [PBAvl posInsert: root at: 3 value: 1].
c that: 'a negative index' signals: PBValidationError during: [PBAvl posAt: root index: -1].
c that: 'posAt: at count' signals: PBValidationError during: [PBAvl posAt: root index: 2].
c that: 'a Boolean index' signals: PBValidationError during: [PBAvl posSet: root at: true value: 1].
c that: 'a Float index' signals: PBValidationError during: [PBAvl posRemove: root at: 0.0].
c that: 'remove from the empty tree' signals: PBValidationError during: [PBAvl posRemove: nil at: 0].
c that: 'a keyed root for a positional function' signals: PBValidationError during: [
  PBAvl posAppend: (PBAvl keyPut: nil key: 1 value: 1 nodeClass: PBKeyNode) first value: 1].
c that: 'a positional root for a keyed function' signals: PBValidationError during: [PBAvl keyPut: root key: 1 value: 1 nodeClass: PBKeyNode].
c that: 'an unorderable key' signals: PBValidationError during: [PBAvl keyPut: nil key: (PBFrozenList withAll: #(1)) value: 1 nodeClass: PBKeyNode].
before := PBAvl posAt: root index: 0.
PBAvl posRemove: (PBAvl posSet: root at: 0 value: 'z') at: 1.
c that: 'the input tree is unchanged' is: { PBAvl posAt: root index: 0. PBAvl posAt: root index: 1. root count } equals: { before. 'b'. 2 }.
c report displayNl.
