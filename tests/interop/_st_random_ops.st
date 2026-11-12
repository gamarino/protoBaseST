"_st_random_ops.st <directory> <out.json>: protoST's side of st_random_ops.sh (design spec
 10.6, plan Task 20; a helper, never run as a test). Seeded random operation sequences on
 every collection protoBaseST can write, over 20 commits to one database:

  list   PBList          seed 20261110   AvlOps nextListOpFor: (insertAt:, appendFirst:, appendLast:,
                                         setAt:, removeAt:, extend:, sliceFrom:to:, head:, tail:)
  dict   PBDictionary    seed 20261111   setAt:value: and removeAt: (nextKeyOp)
  hash   PBHashDictionary seed 20261112  setAt:value: and removeAt: (nextKeyOp)
  set    PBSet           seed 20261113   add: and remove: (the keys of nextKeyOp)

 Each commit applies 12 operations to each collection in one transaction (the first commit
 starts from new collections). After each commit a new transaction reads every collection
 from storage and checks it: PBAvl check: of its tree (every node loaded, as ProtoBase's
 check_invariants), and its contents against a model kept beside it (an OrderedCollection, or
 a Dictionary by order key). A mismatch is an Error naming the seed, the commit and the
 operation. Then the space is dumped with PBNotation dumpSpace:to:, for ProtoBase's verifier
 (the last step of the shell script). Prints 'written <counts>'."
Import from: 'protobase'.
Import from: 'random'.
Import from: '_avl_ops'.

Object subclass: #Sequence instanceVariableNames: 'name seed ops model log'.
Sequence class >> name: aName seed: aSeed
  ^ self basicNew setName: aName seed: aSeed.
Sequence >> setName: aName seed: aSeed
  name := aName.
  seed := aSeed.
  ops := AvlOps basicNew setRandom: (Random seed: aSeed).
  model := name = 'list' ifTrue: [OrderedCollection new] ifFalse: [Dictionary new].
  log := nil.
Sequence >> name
  ^ name.
Sequence >> seed
  ^ seed.
Sequence >> model
  ^ model.
"The operation applied last, as text, for a failure message."
Sequence >> lastOperation
  ^ log ifNil: ['none'].

"aCollection after one random operation, which the model has followed."
Sequence >> step: aCollection
  | op |
  name = 'list' ifTrue: [
    op := ops nextListOpFor: aCollection count.
    log := AvlOps textOf: op.
    self followList: op.
    ^ AvlOps applyListOp: op to: aCollection].
  op := ops nextKeyOp.
  log := AvlOps textOf: op.
  ^ self applyKeyed: op to: aCollection.

Sequence >> applyKeyed: anOp to: aCollection
  | key value orderKey |
  key := AvlOps valueOf: (anOp at: 2).
  orderKey := PBKeys orderKey: key.
  (anOp at: 1) = #delete ifTrue: [
    model removeKey: orderKey ifAbsent: [nil].
    ^ name = 'set' ifTrue: [aCollection remove: key] ifFalse: [aCollection removeAt: key]].
  value := AvlOps valueOf: (anOp at: 3).
  name = 'set' ifTrue: [
    model at: orderKey put: key.
    ^ aCollection add: key].
  model at: orderKey put: key -> value.
  ^ aCollection setAt: key value: value.

"The model's list after anOp, as list_ops.st (a negative position counts from the end, a
 slice bound is clamped, 'nil' is no bound)."
Sequence >> followList: op
  | o n pos lo hi b |
  o := op at: 1.
  n := model size.
  pos := [:i | i < 0 ifTrue: [i + n] ifFalse: [i]].
  b := [:x :d | x = 'nil' ifTrue: [d] ifFalse: [((x < 0 ifTrue: [x + n] ifFalse: [x]) max: 0) min: n]].
  o = #insertAt ifTrue: [model add: (AvlOps valueOf: (op at: 3)) beforeIndex: (pos value: (op at: 2)) + 1].
  o = #appendFirst ifTrue: [model addFirst: (AvlOps valueOf: (op at: 2))].
  o = #appendLast ifTrue: [model addLast: (AvlOps valueOf: (op at: 2))].
  o = #setAt ifTrue: [model at: (pos value: (op at: 2)) + 1 put: (AvlOps valueOf: (op at: 3))].
  o = #removeAt ifTrue: [model removeAt: (pos value: (op at: 2)) + 1].
  o = #extend ifTrue: [(op copyFrom: 3 to: op size) do: [:t | model addLast: (AvlOps valueOf: t)]].
  (#(#sliceFrom #head #tail) includes: o) ifTrue: [
    o = #sliceFrom ifTrue: [lo := b value: (op at: 2) value: 0. hi := b value: (op at: 3) value: n].
    o = #head ifTrue: [lo := 0. hi := b value: (op at: 2) value: n].
    o = #tail ifTrue: [lo := b value: (op at: 2) value: 0. hi := n].
    hi := hi max: lo.
    model := OrderedCollection withAll: (model asArray copyFrom: lo + 1 to: hi)].

"nil when aCollection (read from storage) holds what the model holds and its tree is
 valid; otherwise what differs. PBAvl check: signals PBCorruptionError on a broken tree."
Sequence >> compare: aCollection
  PBAvl check: (aCollection stateAt: 'root').
  aCollection count = model size ifFalse: [
    ^ 'count ' , aCollection count printString , ' against ' , model size printString].
  name = 'list' ifTrue: [
    ^ aCollection elements = model asArray ifTrue: [nil] ifFalse: ['elements differ']].
  name = 'set' ifTrue: [
    model keysAndValuesDo: [:orderKey :key |
      (aCollection has: key) ifFalse: [^ 'missing element ' , key printString]].
    ^ nil].
  model keysAndValuesDo: [:orderKey :pair |
    (aCollection getAt: pair key) = pair value ifFalse: [^ 'wrong value at ' , pair key printString]].
  ^ nil.

| args space db sequences created |
args := Smalltalk arguments.
args size = 2 ifFalse: [
  'usage: _st_random_ops.st <directory> <out.json>' displayNl.
  Smalltalk exit: 2].
sequences := OrderedCollection new.
sequences
  add: (Sequence name: 'list' seed: 20261110);
  add: (Sequence name: 'dict' seed: 20261111);
  add: (Sequence name: 'hash' seed: 20261112);
  add: (Sequence name: 'set' seed: 20261113).
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
db := space newDatabase: 'structures'.
1 to: 20 do: [:commit |
  db newTransactionDo: [:t |
    sequences do: [:each | | collection |
      collection := t getRootObject: each name.
      collection isNil ifTrue: [
        collection := each name = 'list' ifTrue: [t newList] ifFalse: [
          each name = 'dict' ifTrue: [t newDictionary] ifFalse: [
            each name = 'hash' ifTrue: [t newHashDictionary] ifFalse: [t newSet]]]].
      12 timesRepeat: [collection := each step: collection].
      t setRootObject: each name value: collection]].
  db newTransactionDo: [:t |
    sequences do: [:each | | difference |
      difference := each compare: (t getRootObject: each name).
      difference isNil ifFalse: [
        Error signal: each name , ' (seed ' , each seed printString , ') after commit '
          , commit printString , ', last operation [' , each lastOperation , ']: ' , difference]]]].
created := WriteStream on: String new.
db newTransactionDo: [:t |
  sequences do: [:each |
    created nextPutAll: each name; nextPut: $=; print: (t getRootObject: each name) count; space]].
space close.
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
PBNotation dumpSpace: space to: (args at: 2).
space close.
('written ' , created contents trimSeparators) displayNl.
