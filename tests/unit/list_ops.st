"EXPECT: ok 39"
"PBList writes (plan Task 15; ProtoBase proto_db/collections/lists.py): PBList new and
 setAt:value:, insertAt:value:, removeAt:, appendFirst:, appendLast:, extend:,
 sliceFrom:to:, head: and tail: each answer a new list, a new atom with its own oid, and
 leave the receiver as it was. Values are made canonical at once (an Array is stored as a
 PBFrozenList; a Symbol is refused), large ones are boxed and read unboxed. The fields of
 a new list are written in ProtoBase's order (indexes, count, root when empty; root,
 count, indexes later). A seeded sequence of 600 operations (AvlOps nextListOpFor:, the
 sequence tests/interop/avl_ops_identical.sh compares with ProtoBase's List) is checked
 after each step against an OrderedCollection model with PBAvl check:, and every 50th
 version is kept and re-verified at the end. The class comments of PBList, PBDictionary,
 PBSet and PBCountedSet state the rule in their first sentence."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_avl_ops'.

| c empty one two three model list ops kept failure big ext first |
c := Check new.
empty := PBList new.
c that: 'a new list is empty' is: empty count equals: 0.
c that: 'size is count' is: empty size equals: 0.
c that: 'no elements' is: empty elements equals: #().
c that: 'an empty index set' is: empty indexNames equals: #().
c that: 'the fields of an empty list, in ProtoBase''s order' is: empty state keys equals: #('indexes' 'count' 'root').
c that: 'no oid before its first need' is: empty knownOid equals: nil.
c that: 'not saved' is: empty pointer equals: nil.
one := empty appendLast: 3.
c that: 'appendLast: answers the new list' is: one elements equals: #(3).
c that: 'the receiver is unchanged' is: empty count equals: 0.
c that: 'a new atom' isTrue: one ~~ empty.
c that: 'with its own oid' isTrue: one oid ~= empty oid.
c that: 'the fields of a later version' is: one state keys equals: #('root' 'count' 'indexes').
c that: 'the index set is carried over' isTrue: (one stateAt: 'indexes') == (empty stateAt: 'indexes').
two := (one appendFirst: 1) insertAt: 1 value: 2.
c that: 'appendFirst: and insertAt:' is: two elements equals: #(1 2 3).
c that: 'one is unchanged' is: one elements equals: #(3).
three := two setAt: -1 value: 30.
c that: 'setAt: -1' is: three elements equals: #(1 2 30).
c that: 'two is unchanged' is: two elements equals: #(1 2 3).
c that: 'removeAt: 0' is: (three removeAt: 0) elements equals: #(2 30).
c that: 'three is unchanged' is: three elements equals: #(1 2 30).
c that: 'getAt:' is: (three getAt: 2) equals: 30.

"Canonical values."
c that: 'an Array is stored as a PBFrozenList' is: ((empty appendLast: #(1 2)) getAt: 0) class equals: PBFrozenList.
c that: 'a Symbol is refused' signals: PBValidationError during: [empty appendLast: #foo:bar:].
c that: 'a Character is refused' signals: PBValidationError during: [empty insertAt: 0 value: $a].
c that: 'a Dictionary is refused' signals: PBValidationError during: [one setAt: 0 value: Dictionary new].
big := String new: 300 withAll: $x.
c that: 'a large value is boxed' is: ((empty appendLast: big) stateAt: 'root') storedValue class equals: PBValueBox.
c that: 'and read unboxed' is: ((empty appendLast: big) getAt: 0) equals: big.

"extend:"
ext := two extend: three.
c that: 'extend: a PBList' is: ext elements equals: #(1 2 3 1 2 30).
c that: 'extend: an OrderedCollection' is: (empty extend: (OrderedCollection withAll: #(7 8))) elements equals: #(7 8).
c that: 'extend: nothing answers the receiver, as ProtoBase' isTrue: (two extend: #()) == two.
c that: 'extend: a non-collection' signals: PBValidationError during: [two extend: 5].
c that: 'extend: a String is one value' signals: PBValidationError containing: 'appendLast:' during: [two extend: 'abc'].
c that: 'extend: refuses a bad value before building' signals: PBValidationError during: [two extend: { 1. #sym:bol: }].

"The seeded sequence against a model."
ops := AvlOps new.
model := OrderedCollection new.
list := PBList new.
kept := OrderedCollection new.
failure := nil.
1 to: 600 do: [:step |
  | op o n pos lo hi b |
  failure isNil ifTrue: [
    op := ops nextListOpFor: list count.
    list := AvlOps applyListOp: op to: list.
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
    PBAvl check: (list stateAt: 'root').
    (list count = model size and: [list elements = model asArray]) ifFalse: [
      failure := 'seed ' , AvlOps seed printString , ' step ' , step printString , ' ' , (AvlOps textOf: op)].
    step \\ 50 = 0 ifTrue: [kept add: list -> model asArray]]].
c that: 'the seeded sequence matches the model' is: failure equals: nil.
c that: 'the kept versions are unchanged' isTrue: (kept allSatisfy: [:each | each key elements = each value]).

"The class comments."
first := 'Every message answers a new version; the receiver never changes.'.
{ PBList. PBDictionary. PBSet. PBCountedSet } do: [:cls |
  c that: cls name , ' comment' isTrue: (cls comment beginsWith: first)].
c that: 'PBList comment: zero-based' isTrue: (PBList comment includesSubstring: 'Positions are zero-based, as in ProtoBase.').
c report displayNl.
