"EXPECT: ok 30"
"Operation logs and log completeness (plan Task 16; ProtoBase ConcurrentOptimized, D33).
 Every PBDictionary, PBHashDictionary and PBSet version carries opLog, a PBFrozenList of
 PBTuples ('set' k v), ('remove' k) and ('add' e), the op names of ProtoBase's
 collections/*.py; every mutator call logs its intent, a blind write (one that changes
 nothing) included, and answers a new version. logComplete (isMergeable) is true for a
 version built by new and derived only by logged mutators, false for a loaded version and
 everything derived from it. A rebase answers what the replay through the public mutators
 gives: onto a loaded current (what a commit meets) an incomplete log; onto a version built
 in memory a complete one, as ProtoBase's rebase_onto (whose result keeps current's
 _log_complete). A PBList has no log (it is not ConcurrentOptimized in ProtoBase). A
 PBDictionary logs a large value in its stored form, the PBValueBox, and a rebase reuses
 that box (ProtoBase D51: the value is not written twice)."
Import from: 'protobase'.
Import from: '_check'.

| c d d1 d2 blind sink twin stub big withBig box rebased node s h tup base |
c := Check new.
tup := [:anArray | PBTuple withAll: anArray].
d := PBDictionary new.
c that: 'a new dictionary has a complete log' isTrue: d logComplete.
c that: 'an empty one' is: d opLog equals: (PBFrozenList withAll: #()).
c that: 'isMergeable answers logComplete' isTrue: d isMergeable.
d1 := d setAt: 'a' value: 1.
d2 := d1 removeAt: 'a'.
c that: 'setAt:value: logs (''set'' k v)' is: d1 opLog equals: (PBFrozenList withAll: { tup value: #('set' 'a' 1) }).
c that: 'removeAt: logs (''remove'' k)' is: d2 opLog equals: (PBFrozenList withAll: { tup value: #('set' 'a' 1). tup value: #('remove' 'a') }).
c that: 'the parent''s log is unchanged' is: d1 opLog size equals: 1.
c that: 'derived by logged mutators: complete' isTrue: (d1 logComplete and: [d2 logComplete]).
blind := d2 removeAt: 'a'.
c that: 'a blind write is logged' is: blind opLog size equals: 3.
c that: 'and answers a new version' isTrue: blind ~~ d2.
c that: 'with the same tree' isTrue: (blind stateAt: 'root') == (d2 stateAt: 'root').
c that: 'and stays complete' isTrue: blind logComplete.
c that: 'a refused key logs nothing' signals: PBValidationError during: [d1 setAt: Float nan value: 1].
c that: 'the log of a set'
  is: ((PBSet new add: 1) remove: 2) opLog equals: (PBFrozenList withAll: { tup value: #('add' 1). tup value: #('remove' 2) }).
h := (PBHashDictionary new setAt: 'k' value: #(1 2)) removeAt: 'z'.
c that: 'the log of a hash dictionary, values canonical'
  is: h opLog equals: (PBFrozenList withAll: { PBTuple withAll: { 'set'. 'k'. PBFrozenList withAll: #(1 2) }. tup value: #('remove' 'z') }).
c that: 'a hash dictionary built by new is complete' isTrue: h logComplete.

"Loaded versions."
base := FileSystem temp / ('pbst-oplog-complete-' , Smalltalk pid printString).
base deleteAll.
sink := PBFileStorage path: base pathString.
d1 _saveInto: sink.
twin := d1 _decodedTwin.
c that: 'a loaded version has an incomplete log' is: twin logComplete equals: false.
c that: 'and an empty one' is: twin opLog size equals: 0.
c that: 'it carries a consumed cell too' is: twin consumed value equals: false.
c that: 'a version derived from it is incomplete' is: (twin setAt: 'b' value: 2) logComplete equals: false.
c that: 'and logs from there' is: (twin setAt: 'b' value: 2) opLog size equals: 1.
stub := d1 unloadedCopy.
c that: 'a stub is incomplete' is: stub isMergeable equals: false.
c that: 'saving keeps the in-memory version complete' isTrue: d1 logComplete.
rebased := (PBDictionary new setAt: 'x' value: 1) rebaseOnto: twin.
c that: 'rebased onto a loaded current: incomplete' is: rebased logComplete equals: false.
c that: 'holding both' is: rebased items equals: { 'a' -> 1. 'x' -> 1 }.
c that: 'rebased onto a current built in memory: complete, as ProtoBase'
  isTrue: ((PBDictionary new setAt: 'x' value: 1) rebaseOnto: d1) logComplete.

"A PBList has no log."
c that: 'a PBList is never mergeable' is: (PBList new appendLast: 1) isMergeable equals: false.

"The stored form of a large value."
big := String new: PBAvl valueBoxMin withAll: $v.
withBig := PBDictionary new setAt: 'big' value: big.
box := (withBig opLog at: 1) at: 3.
c that: 'a large value is logged boxed' is: box class equals: PBValueBox.
c that: 'the box the node holds' isTrue: ((withBig stateAt: 'root') storedValue) == box.
rebased := withBig rebaseOnto: (PBDictionary new setAt: 'other' value: 1).
node := PBAvl keyAt: (rebased stateAt: 'root') key: 'big'.
c that: 'the rebase reuses the box' isTrue: node storedValue == box.
c that: 'and reads the value' is: (rebased getAt: 'big') equals: big.
sink close.
base deleteAll.
c report displayNl.
