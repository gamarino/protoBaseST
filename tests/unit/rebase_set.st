"EXPECT: ok 12"
"PBSet rebaseOnto: (plan Task 16; ProtoBase ConcurrentOptimized.rebase_onto and
 Set._replay_op): the last intent per element (presence or absence), elements compared by
 order key, in order of last occurrence, replayed through add: and remove:. The expected
 answers are ProtoBase v2.0.0rc1's for the same calls."
Import from: 'protobase'.
Import from: '_check'.

| c s net r e sorted empty |
c := Check new.
sorted := [:aSet | (aSet elements asSortedCollection: [:p :q | p printString <= q printString]) asArray].
"add then remove of one element nets to remove"
s := (PBSet new add: 1) remove: 1.
c that: 'the log holds both intents' is: s opLog equals: (PBFrozenList withAll: {
  PBTuple withAll: #('add' 1). PBTuple withAll: #('remove' 1) }).
net := s _netOps.
c that: 'add then remove nets to remove' is: net size equals: 1.
c that: 'the remove' is: (net first at: 1) equals: 'remove'.
empty := PBSet new.
r := s rebaseOnto: empty.
c that: 'replays as a no-op on a current without it' is: r count equals: 0.
c that: 'a new version all the same (the remove is logged as intent)' isTrue: (r ~~ empty and: [r opLog size = 1]).
c that: 'and removes it from a current holding it' is: (s rebaseOnto: (PBSet new add: 1.0)) count equals: 0.

"A longer log: ProtoBase's net effect is (add 2) (remove 1) (remove 'x')."
s := ((((PBSet new add: 1) add: 2) remove: 1) add: 'x') remove: 'x'.
net := s _netOps.
c that: 'the net effect, in order of last occurrence'
  is: (net collect: [:op | (op at: 1) , ' ' , (op at: 2) printString]) asArray
  equals: #('add 2' 'remove 1' 'remove ''x''').
r := s rebaseOnto: ((PBSet new add: 'x') add: 5).
c that: 'replayed: ProtoBase''s [2, 5]' is: (sorted value: r) equals: #(2 5).
c that: 'the current element objects stay' is: (r has: 5) equals: true.
e := (PBSet new add: (Decimal fromString: '2.0')) rebaseOnto: (PBSet new add: 2).
c that: 'an add of a present element changes nothing' is: e elements equals: #(2).
c that: 'a current of another class' signals: PBValidationError containing: 'PBCountedSet'
  during: [s rebaseOnto: PBCountedSet new].
c that: 'a PBList has no operation log to rebase' signals: PBNotSupportedError
  during: [PBList new rebaseOnto: PBList new].
c report displayNl.
