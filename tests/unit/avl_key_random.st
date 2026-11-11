"EXPECT: ok 2000"
"Plan Task 14: 2000 seeded random puts and deletes on a persistent keyed tree (PBAvl over
 PBKeyNode), against a model of key -> value associations kept sorted with PBKeys
 compare:with:. Keys mix Integers, Floats (n and n.0 are one key: a put keeps the stored
 key object, as ProtoBase's key_put), and Strings; deletes may name an absent key (the
 tree is then answered unchanged, the same object). After each operation PBAvl check:
 holds, the tree holds the model in order, and keyAt: finds the operation's key (or nil), and the
 answer's replaced/removed flag and old value are the model's.
 Every 50th tree is kept with a copy of the model, and at the end each must still hold
 what it held (path copying never changes a node). The sequence is AvlOps (Random seed:
 20261110); a failure prints the seed and the step. tests/interop/avl_ops_identical.sh
 replays the same sequence in ProtoBase."
Import from: 'protobase'.
Import from: '_avl_ops'.
| ops root model failure steps slot kept holds |
ops := AvlOps new.
root := nil.
model := OrderedCollection new.
failure := nil.
steps := 0.
kept := OrderedCollection new.
"Whether the tree aRoot holds the associations of aSequence, in order: the same key
 objects (the model keeps the key a put stored), equal values."
holds := [:aRoot :aSequence |
  | i ok |
  i := 0.
  ok := (aRoot isNil ifTrue: [0] ifFalse: [aRoot count]) = aSequence size.
  ok ifTrue: [
    PBAvl nodesDo: [:node |
      i := i + 1.
      ok ifTrue: [
        (node key == (aSequence at: i) key) ifFalse: [ok := false].
        (node value = (aSequence at: i) value) ifFalse: [ok := false]]] over: aRoot].
  ok].
"The 1-based index of aKey in the model, or the negated index it would be inserted at
 (a binary search by PBKeys compare:with:)."
slot := [:aKey |
  | lo hi found |
  lo := 1.
  hi := model size.
  found := nil.
  [found isNil and: [lo <= hi]] whileTrue: [
    | mid c |
    mid := (lo + hi) // 2.
    c := PBKeys compare: (model at: mid) key with: aKey.
    c = 0 ifTrue: [found := mid].
    c < 0 ifTrue: [lo := mid + 1].
    c > 0 ifTrue: [hi := mid - 1]].
  found isNil ifTrue: [lo negated] ifFalse: [found]].
[steps < 2000 and: [failure isNil]] whileTrue: [
  | op key value stored previous old next at node result |
  op := ops nextKeyOp.
  steps := steps + 1.
  old := root.
  key := AvlOps valueOf: (op at: 2).
  at := slot value: key.
  stored := at > 0 ifTrue: [(model at: at) key] ifFalse: [nil].
  previous := at > 0 ifTrue: [(model at: at) value] ifFalse: [nil].
  (op at: 1) = #put ifTrue: [
    value := AvlOps valueOf: (op at: 3).
    result := PBAvl keyPut: root key: key value: value nodeClass: PBKeyNode.
    next := result first.
    at > 0
      ifTrue: [model at: at put: (model at: at) key -> value]
      ifFalse: [model add: key -> value beforeIndex: at negated]].
  (op at: 1) = #delete ifTrue: [
    result := PBAvl keyRemove: root key: key.
    next := result first.
    at > 0 ifTrue: [model removeAt: at]].
  failure := [
    PBAvl check: next.
    node := PBAvl keyAt: next key: key.
    (holds value: next value: model)
      ifFalse: ['the tree does not hold the model']
      ifTrue: [
        ((result at: 2) ~= (at > 0) or: [(result at: 3) ~= previous]) ifTrue: ['the replaced/removed flag or the old value is wrong'] ifFalse: [
          ((op at: 1) = #delete and: [at < 0 and: [next ~~ old]]) ifTrue: ['a delete of an absent key copied the tree'] ifFalse: [
            ((op at: 1) = #put and: [node isNil or: [node value ~= value]]) ifTrue: ['keyAt: misses the key put'] ifFalse: [
              ((op at: 1) = #put and: [at > 0 and: [node key ~~ stored]])
                ifTrue: ['a put replaced the stored key object'] ifFalse: [
                  ((op at: 1) = #delete and: [node notNil]) ifTrue: ['keyAt: finds a deleted key'] ifFalse: [nil]]]]]]]
    on: Error do: [:e | e return: e class name , ': ' , e messageText].
  failure isNil ifFalse: [
    ('FAIL seed ' , AvlOps seed printString , ' step ' , steps printString , ' ('
      , (AvlOps textOf: op) , '): ' , failure) displayNl].
  root := next.
  steps \\ 50 = 0 ifTrue: [kept add: root -> (model asArray collect: [:each | each key -> each value])]].
kept do: [:each |
  (failure isNil and: [(holds value: each key value: each value) not]) ifTrue: [
    failure := 'a kept tree changed'.
    ('FAIL seed ' , AvlOps seed printString , ': a tree kept at a 50th step no longer holds its entries') displayNl]].
failure isNil ifTrue: [('ok ' , steps printString) displayNl] ifFalse: ['failed' displayNl].
