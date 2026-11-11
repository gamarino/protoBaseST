"EXPECT: ok 81"
"Plan Task 16b (ruling R15): a record of a class with a fixed shape (PBPosNode, PBKeyNode,
 PBCountedKeyNode, PBValueBox) reads its fields from a slots Array: the values of
 persistedFields, in that order, built once per record and published once by
 compare-and-swap. Each accessor reads a literal slot number; this test fails if a literal
 disagrees with the class's persistedFields, so a reorder of persistedFields (or of an
 accessor) is caught. The accessors answer the same values for a node built in memory, a
 loaded record, and a loaded record whose attributes are in another order (the record's
 order is kept: the bytes do not change). The integer fields (height, count, weight) are
 checked once, when the record is loaded or built, whatever field is read first. A loser
 of the load race reads the slots of the installed envelope, forced through a seam, never
 by timing."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sink'.

"A sink whose first load of a record first loads the same record through the atom in its
 cell, so that inner load installs its envelope first and the outer load loses the
 compare-and-swap."
SegmentSink subclass: #RacingLoadSink instanceVariableNames: 'racer loads'.
RacingLoadSink >> racer: anAtom
  racer := anAtom.
  loads := 0.
RacingLoadSink >> loads
  ^ loads.
RacingLoadSink >> loadAt: aPointer expecting: aTag within: aChain
  | r envelope |
  loads := loads + 1.
  envelope := super loadAt: aPointer expecting: aTag within: aChain.
  r := racer.
  racer := nil.
  r isNil ifFalse: [r left].
  ^ envelope.

| c accessors markers sink build saveLoad stub node reversed racing inner bad ptr seg |
c := Check new.
"The accessor of each persisted field (the stored value of a node; a box's value)."
accessors := Dictionary new.
accessors at: PBPosNode put: { 'value' -> #storedValue. 'left' -> #left. 'right' -> #right. 'height' -> #height. 'count' -> #count }.
accessors at: PBKeyNode put: { 'key' -> #key. 'value' -> #storedValue. 'left' -> #left. 'right' -> #right. 'height' -> #height. 'count' -> #count }.
accessors at: PBCountedKeyNode put: { 'key' -> #key. 'value' -> #storedValue. 'left' -> #left. 'right' -> #right. 'height' -> #height. 'count' -> #count. 'weight' -> #weight }.
accessors at: PBValueBox put: { 'value' -> #value }.
"A distinct Integer per field name, whatever its position."
markers := Dictionary new.
#('key' 'value' 'left' 'right' 'height' 'count' 'weight') doWithIndex: [:f :i | markers at: f put: 100 + i].
"An in-memory atom of aClass holding the marker of each field, in the order of aFieldArray."
build := [:aClass :aFieldArray |
  aClass _unsavedWithState: (PBFrozenDict withAssociations: (aFieldArray collect: [:f | f -> (markers at: f)]))].
sink := SegmentSink segment: (ByteArray fromHex: '16b016b016b016b016b016b016b016b0').
"A fresh stub of anAtom, saved first."
saveLoad := [:anAtom | anAtom _saveInto: sink. anAtom unloadedCopy].

{ PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:cls |
  | fields table cases |
  fields := cls persistedFields.
  table := accessors at: cls.
  c that: cls name , ': one accessor per persisted field' is: (table collect: [:a | a key]) asSet equals: fields asSet.
  cases := { 'built'. build value: cls value: fields.
    'loaded'. saveLoad value: (build value: cls value: fields).
    'loaded, attributes reversed'. saveLoad value: (build value: cls value: fields reversed) }.
  1 to: cases size by: 2 do: [:k |
    | how atom |
    how := cases at: k.
    atom := cases at: k + 1.
    table do: [:a |
      c that: cls name , ' ' , how , ': ' , a value , ' reads slot ' , (fields indexOf: a key) printString
        is: (atom perform: a value) equals: (markers at: a key)]]].

"The record's order is kept: a reversed record re-encodes to its own bytes."
reversed := build value: PBKeyNode value: PBKeyNode persistedFields reversed.
stub := saveLoad value: reversed.
c that: 'a reversed record keeps its order' is: (stub left; state) keys equals: PBKeyNode persistedFields reversed.
c that: 'and its bytes' is: (PBAtomEnvelope tag: stub tag oid: stub oid state: stub state) encode
  equals: (PBAtomEnvelope tag: reversed tag oid: reversed oid state: reversed state) encode.
c that: 'a loaded record equals the atom saved' isTrue: stub = reversed.

"Built once: the same Array on every read, the installed envelope's."
node := (PBAvl keyPut: nil key: 1 value: 'one' nodeClass: PBKeyNode) first.
c that: 'a built node: one slots Array' isTrue: node _slots == node _slots.
c that: 'a built node: the envelope''s' isTrue: node _slots == node _envelope slots.
stub := saveLoad value: node.
c that: 'a stub has no slots before it is loaded' isTrue: stub isLoaded not.
c that: 'a stub reads its key' is: stub key equals: 1.
c that: 'a loaded stub: the envelope''s' isTrue: stub _slots == stub _envelope slots.
c that: 'the slots take no part in =' isTrue: stub = node.
c that: 'nor in hash' is: stub hash equals: node hash.

"An absent field reads as nil (a state built in memory without it)."
c that: 'an absent field reads nil' is: (PBValueBox _unsavedWithState: (PBFrozenDict withAssociations: #())) value equals: nil.
c that: 'an absent node field reads nil' is: (PBPosNode _unsavedWithState: (PBFrozenDict withAssociations: { 'height' -> 1. 'count' -> 1 })) left equals: nil.

"The integer fields are checked when the record is built or loaded."
c that: 'a built node: height not an integer' signals: PBCorruptionError containing: 'the height of PBPosNode(nil) is not an integer' during: [
  PBPosNode _unsavedWithState: (PBFrozenDict withAssociations: { 'value' -> 1. 'left' -> nil. 'right' -> nil. 'height' -> 'two'. 'count' -> 1 })].
c that: 'a built node: a Boolean count' signals: PBCorruptionError containing: 'the count of' during: [
  PBKeyNode _unsavedWithState: (PBFrozenDict withAssociations: { 'key' -> 1. 'value' -> 1. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> true })].
c that: 'a built node: weight not an integer' signals: PBCorruptionError containing: 'the weight of' during: [
  PBCountedKeyNode _unsavedWithState: (PBFrozenDict withAssociations: {
    'key' -> 1. 'value' -> 1. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1. 'weight' -> 1.5 })].
"A damaged record, written by hand (no class would build it)."
seg := ByteArray fromHex: '16b116b116b116b116b116b116b116b1'.
bad := SegmentSink segment: seg.
ptr := bad pushAtom: (PBAtomEnvelope tag: (PBTypeRegistry tagFor: PBPosNode) oid: (ByteArray fromHex: '07070707070707070707070707070707')
  state: (PBFrozenDict withAssociations: { 'value' -> 1. 'left' -> nil. 'right' -> nil. 'height' -> 'two'. 'count' -> 1 })).
stub := PBPosNode unloadedAt: ptr storage: bad.
c that: 'a loaded node: the first field read checks height' signals: PBCorruptionError
  containing: 'the height of PBPosNode(' during: [stub left].
c that: 'and the record is not installed' isTrue: stub isLoaded not.

"The load race: the inner load installs its envelope, the outer load reads its slots."
racing := RacingLoadSink segment: (ByteArray fromHex: '16b216b216b216b216b216b216b216b2').
node := PBPosNode value: 'x' left: nil right: nil.
node _saveInto: racing.
stub := node unloadedCopy.
racing racer: stub.
c that: 'the loser reads the field' is: stub storedValue equals: 'x'.
c that: 'the record was decoded twice' is: racing loads equals: 2.
c that: 'the loser holds the installed envelope''s slots' isTrue: stub _slots == stub _envelope slots.
c report displayNl.
