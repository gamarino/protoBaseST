"EXPECT: ok 1015"
"Plan Task 14: the weight of a CountedKeyNode tree (format spec 'AVL nodes', ProtoBase D56):
 a node's value is a (payload, count) pair and its weight is the sum of the counts of its
 subtree. Checked on a built tree, after a value is replaced, after removes, and after each
 of 1000 seeded puts and deletes (AvlOps, Random seed: 20261110) against a model, with
 PBAvl check: (which verifies weight at every node) after each. A put into a non-empty tree
 takes the root's node class whatever nodeClass: names; a value that is not a pair of a
 payload and an Integer count >= 0 is PBValidationError."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_avl_ops'.
| c pair root sum ops model steps failure plain ok total |
c := Check new.
pair := [:p :n | PBTuple withAll: { p. n }].
root := nil.
1 to: 50 do: [:i | root := (PBAvl keyPut: root key: i value: (pair value: 'p' , i printString value: i \\ 4) nodeClass: PBCountedKeyNode) first].
sum := 0.
1 to: 50 do: [:i | sum := sum + (i \\ 4)].
c that: 'the root weight is the sum of the counts' is: root weight equals: sum.
c that: 'every node is a CountedKeyNode' is: (PBAvl check: root) == root equals: true.
ok := true.
PBAvl nodesDo: [:node |
  ok := ok and: [node weight = ((node value at: 2) + (node left isNil ifTrue: [0] ifFalse: [node left weight])
    + (node right isNil ifTrue: [0] ifFalse: [node right weight]))]] over: root.
c that: 'a node''s weight is its own count plus its children''s' isTrue: ok.
root := (PBAvl keyPut: root key: 7 value: (pair value: 'seven' value: 100) nodeClass: PBCountedKeyNode) first.
c that: 'replacing a value changes the weight by the count difference' is: root weight equals: sum - 3 + 100.
root := (PBAvl keyRemove: root key: 7) first.
root := (PBAvl keyRemove: root key: 10) first.
c that: 'removes subtract their counts' is: root weight equals: sum - 3 - 2.
root := (PBAvl keyPut: root key: 1000 value: (pair value: 'x' value: 5) nodeClass: PBKeyNode) first.
c that: 'a node added to a weighted tree is a CountedKeyNode' is: (PBAvl keyAt: root key: 1000) class equals: PBCountedKeyNode.
c that: 'and adds its count' is: root weight equals: sum - 5 + 5.
plain := (PBAvl keyPut: nil key: 1 value: 'one' nodeClass: PBKeyNode) first.
plain := (PBAvl keyPut: plain key: 2 value: (pair value: 'x' value: 5) nodeClass: PBCountedKeyNode) first.
c that: 'a node added to a plain tree is a KeyNode' is: (PBAvl keyAt: plain key: 2) class equals: PBKeyNode.
c that: 'a count below 0' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: (pair value: 'x' value: -1) nodeClass: PBCountedKeyNode].
c that: 'a Boolean count' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: (pair value: 'x' value: true) nodeClass: PBCountedKeyNode].
c that: 'a Float count' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: (pair value: 'x' value: 1.0) nodeClass: PBCountedKeyNode].
c that: 'a value that is not a pair' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: 3 nodeClass: PBCountedKeyNode].
c that: 'a triple' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: (PBTuple withAll: #(1 2 3)) nodeClass: PBCountedKeyNode].
c that: 'a replacement value is checked too' signals: PBValidationError during: [PBAvl keyPut: root key: 1 value: 'x' nodeClass: PBCountedKeyNode].
c that: 'nodeClass: must be a keyed node class' signals: PBValidationError during: [PBAvl keyPut: nil key: 1 value: 1 nodeClass: PBPosNode].
"1000 seeded operations against a model of key -> count."
ops := AvlOps new.
root := nil.
model := Dictionary new.
steps := 0.
failure := nil.
[steps < 1000 and: [failure isNil]] whileTrue: [
  | op key |
  op := ops nextCountedOp.
  steps := steps + 1.
  key := AvlOps valueOf: (op at: 2).
  (op at: 1) = #put
    ifTrue: [
      | value |
      value := AvlOps valueOf: (op at: 3).
      root := (PBAvl keyPut: root key: key value: value nodeClass: PBCountedKeyNode) first.
      model at: key put: (value at: 2)]
    ifFalse: [
      root := (PBAvl keyRemove: root key: key) first.
      model removeKey: key ifAbsent: [nil]].
  failure := [
    PBAvl check: root.
    total := 0.
    model do: [:n | total := total + n].
    (root isNil ifTrue: [0] ifFalse: [root weight]) = total
      ifTrue: [(root isNil ifTrue: [0] ifFalse: [root count]) = model size ifTrue: [nil] ifFalse: ['wrong count']]
      ifFalse: ['the root weight is not the model''s total']]
    on: Error do: [:e | e return: e class name , ': ' , e messageText].
  c that: 'seed ' , AvlOps seed printString , ' step ' , steps printString , ' (' , (AvlOps textOf: op) , ')' is: failure equals: nil].
c report displayNl.
