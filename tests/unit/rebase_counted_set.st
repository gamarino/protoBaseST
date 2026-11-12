"EXPECT: ok 23"
"PBCountedSet rebaseOnto: (plan Task 22; design spec 7.2, D26; ProtoBase v2.0.0rc2
 proto_db/collections/sets.py, counter_net_effect, CountedSet._net_ops, _replay_op and
 _transform). The log's ops compose, per element, into one counter transform
 (removes, adds): add is (0, 1), remove is (1, 0), and (r1, a1) then (r2, a2) is
 (r1, a1 - r2 + a2) when a1 >= r2, otherwise (r1 + r2 - a1, a2). The net ops are
 ('net' e removes adds), in order of last occurrence, elements compared by order key (the
 first element object of each is kept), an identity transform omitted. Each is applied to
 current as one adjustment, c -> max(c - removes, 0) + adds, logged as
 ('transform' e removes adds), so a rebased version can itself be rebased. The expected
 answers are ProtoBase's for the same calls."
Import from: 'protobase'.
Import from: '_check'.

| c times s net r cur z textOf items r2 |
c := Check new.
times := [:n :e | | v | v := PBCountedSet new. n timesRepeat: [v := v add: e]. v].
textOf := [:anArray | (anArray collect: [:op |
  (op asArray collect: [:each | each isString ifTrue: [each] ifFalse: [each printString]])
    inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' ' , each]]]) asArray].
items := [:aSet | ((aSet items collect: [:each | each key printString , '=' , each value printString])
  asSortedCollection: [:p :q | p <= q]) asArray].

"Plan Step 1: add, add, remove onto a current count of 5 gives 6."
s := ((PBCountedSet new add: 'x') add: 'x') remove: 'x'.
c that: 'the log holds the three intents' is: (textOf value: s opLog asArray) equals: #('add x' 'add x' 'remove x').
net := s _netOps.
c that: 'they compose into one transform (0, 1)' is: (textOf value: net) equals: #('net x 0 1').
r := s rebaseOnto: (times value: 5 value: 'x').
c that: 'onto 5: 6' is: (r countOf: 'x') equals: 6.
c that: 'the total count follows' is: r totalCount equals: 6.
c that: 'the replay is logged as one transform' is: (textOf value: r opLog asArray) last equals: 'transform x 0 1'.
c that: 'onto a version built in memory, the answer keeps its completeness' is: r isMergeable equals: true.

"Removes below zero clamp at 0 before the adds."
s := (((PBCountedSet new remove: 'y') remove: 'y') remove: 'y') add: 'y'.
c that: 'three removes then an add: (3, 1)' is: (textOf value: s _netOps) equals: #('net y 3 1').
c that: 'onto 1: max(1 - 3, 0) + 1 = 1' is: ((s rebaseOnto: (times value: 1 value: 'y')) countOf: 'y') equals: 1.
c that: 'onto 4: 2' is: ((s rebaseOnto: (times value: 4 value: 'y')) countOf: 'y') equals: 2.
c that: 'onto a current without it: 1' is: ((s rebaseOnto: PBCountedSet new) countOf: 'y') equals: 1.

"A longer log over several elements."
s := (((((((PBCountedSet new add: 1) add: 'a') remove: 1) add: 2) add: 1.0) remove: 'a') remove: 'a') add: 'a'.
c that: 'the net ops, in order of last occurrence, the first element object kept'
  is: (textOf value: s _netOps) equals: #('net 2 0 1' 'net 1 0 1' 'net a 1 1').
cur := ((((((PBCountedSet new add: (Decimal fromString: '1.00')) add: (Decimal fromString: '1.00'))
  add: 'a') add: 'a') add: 'a') add: 3).
r := s rebaseOnto: cur.
c that: 'ProtoBase''s merged counts' is: (items value: r) equals: #('''a''=3' '1.00=3' '2=1' '3=1').
c that: 'current''s element object is kept' is: (r items detect: [:each | each value = 3 and: [each key isString not]]) key class equals: Decimal.
c that: 'four distinct elements' is: r count equals: 4.
c that: 'eight occurrences' is: r totalCount equals: 8.
c that: 'the transforms logged after current''s log'
  is: ((textOf value: r opLog asArray) copyFrom: 7 to: 9) equals: #('transform 2 0 1' 'transform 1 0 1' 'transform a 1 1').

"An identity transform is omitted: the rebase answers current itself."
s := (PBCountedSet new add: 'z') remove: 'z'.
c that: 'add then remove nets to nothing' is: s _netOps size equals: 0.
z := times value: 3 value: 'z'.
c that: 'the rebase answers current' isTrue: (s rebaseOnto: z) == z.

"A rebased version rebases in turn: its transform ops compose like the others."
r2 := (PBCountedSet new add: 1) rebaseOnto: (PBCountedSet new add: 2).
c that: 'its log' is: (textOf value: r2 opLog asArray) equals: #('add 2' 'transform 1 0 1').
c that: 'its net ops' is: (textOf value: r2 _netOps) equals: #('net 2 0 1' 'net 1 0 1').
r := r2 rebaseOnto: (PBCountedSet new add: 1).
c that: 'ProtoBase''s counts' is: (items value: r) equals: #('1=2' '2=1').

c that: 'a current of another class' signals: PBValidationError during: [s rebaseOnto: PBSet new].
c that: 'an unknown net op' signals: PBValidationError containing: 'Unknown PBCountedSet net op'
  during: [s _replay: (PBTuple withAll: #('add' 1)) onto: PBCountedSet new].
c report displayNl.
