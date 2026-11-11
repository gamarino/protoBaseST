"EXPECT: ok 2000"
"Plan Task 14: 2000 seeded random inserts, appends, sets and removes on a persistent
 positional tree (PBAvl over PBPosNode), against an OrderedCollection model. After each
 operation PBAvl check: holds and the tree holds the model's elements in order (posAt: and
 do:over: agree). Every 50th tree is kept with a copy of the model, and at the end each
 must still hold what it held (path copying never changes a node, so the later
 operations, which share its subtrees, left it as it was). Values around the boxing threshold come and go.
 The sequence is AvlOps (Random seed: 20261110); a failure prints the seed and the step.
 tests/interop/avl_ops_identical.sh replays the same sequence in ProtoBase."
Import from: 'protobase'.
Import from: '_avl_ops'.
| ops root model failure steps contents kept |
ops := AvlOps new.
root := nil.
model := OrderedCollection new.
failure := nil.
steps := 0.
kept := OrderedCollection new.
contents := [:aRoot |
  | out |
  out := OrderedCollection new.
  PBAvl do: [:node | out add: node value] over: aRoot.
  out].
[steps < 2000 and: [failure isNil]] whileTrue: [
  | op value next |
  op := ops nextPosOpFor: model size.
  steps := steps + 1.
  value := op size = 3 ifTrue: [AvlOps valueOf: (op at: 3)] ifFalse: [nil].
  (op at: 1) = #insert ifTrue: [
    next := PBAvl posInsert: root at: (op at: 2) value: value.
    model add: value beforeIndex: (op at: 2) + 1].
  (op at: 1) = #append ifTrue: [
    next := PBAvl posAppend: root value: value.
    model addLast: value].
  (op at: 1) = #set ifTrue: [
    next := PBAvl posSet: root at: (op at: 2) value: value.
    model at: (op at: 2) + 1 put: value].
  (op at: 1) = #remove ifTrue: [
    next := PBAvl posRemove: root at: (op at: 2).
    model removeAt: (op at: 2) + 1].
  failure := [
    PBAvl check: next.
    (contents value: next) asArray = model asArray
      ifFalse: ['the tree does not hold the model''s elements']
      ifTrue: [
        (model isEmpty or: [(PBAvl posAt: next index: ((op at: 2) min: model size - 1))
                = (model at: ((op at: 2) min: model size - 1) + 1)])
              ifTrue: [nil]
              ifFalse: ['posAt: disagrees with the model']]]
    on: Error do: [:e | e return: e class name , ': ' , e messageText].
  failure isNil ifFalse: [
    ('FAIL seed ' , AvlOps seed printString , ' step ' , steps printString , ' ('
      , (AvlOps textOf: op) , '): ' , failure) displayNl].
  root := next.
  steps \\ 50 = 0 ifTrue: [kept add: root -> model asArray]].
kept do: [:each |
  (failure isNil and: [(contents value: each key) asArray ~= each value]) ifTrue: [
    failure := 'a kept tree changed'.
    ('FAIL seed ' , AvlOps seed printString , ': a tree kept at a 50th step no longer holds its elements') displayNl]].
failure isNil ifTrue: [('ok ' , steps printString) displayNl] ifFalse: ['failed' displayNl].
