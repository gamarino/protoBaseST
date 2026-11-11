"EXPECT: ok 150"
"Plan Task 16b (ruling R15, fix round 1): every atom class has a record shape
 (_PBRecordShape), and each record carries a slots Array, the values of its fields in slot
 order, built once per record and published once by compare-and-swap. A class that declares
 slotFields reads them through accessors with literal slot numbers. This test takes the
 classes from the type registry (the built-in ones and the application subclasses below) and
 fails for a class that declares slotFields and has no accessor table here, and for an
 accessor whose literal disagrees with its class's slotFields: a reorder of the built-in
 persistedFields (which are their slotFields) is caught. The accessors answer the same values
 for a record built in memory, loaded, and loaded with its attributes reversed (the record's
 order is kept: the bytes do not change). A loaded record in persisted order shares its
 class's keys (no index of its own), for every registered class. The integer fields (height,
 count, weight) are checked once, when the record is loaded or built from a caller's state,
 whatever field is read first. A loser of the load race reads the slots of the installed
 envelope, forced through a seam, never by timing."
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

"An application keyed node whose records order their attributes differently: it keeps
 PBKeyNode's slot layout (inherited slotFields) and accessors."
PBKeyNode subclass: #ReorderedNode.
ReorderedNode class >> typeName
  ^ 'slotstest.ReorderedNode'.
ReorderedNode class >> persistedFields
  ^ #('left' 'right' 'key' 'value' 'height' 'count').

"An application keyed node with a later, optional integer field and its own accessor."
PBKeyNode subclass: #ExtendedNode.
ExtendedNode class >> typeName
  ^ 'slotstest.ExtendedNode'.
ExtendedNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' 'priority').
ExtendedNode class >> slotFields
  ^ ExtendedNode persistedFields.
ExtendedNode class >> integerFields
  ^ #('height' 'count' 'priority').
ExtendedNode >> priority
  ^ self _slotAt: 7.

| c accessors markers sink build saveLoad stub node reversed racing inner bad ptr seg classes keyTable |
c := Check new.
PBTypeRegistry register: ReorderedNode; register: ExtendedNode.
"The accessor of each slot field, per class that declares slotFields."
keyTable := { 'key' -> #key. 'value' -> #storedValue. 'left' -> #left. 'right' -> #right. 'height' -> #height. 'count' -> #count }.
accessors := Dictionary new.
accessors at: PBPosNode put: { 'value' -> #storedValue. 'left' -> #left. 'right' -> #right. 'height' -> #height. 'count' -> #count }.
accessors at: PBKeyNode put: keyTable.
accessors at: ReorderedNode put: keyTable.
accessors at: PBCountedKeyNode put: keyTable , { 'weight' -> #weight }.
accessors at: ExtendedNode put: keyTable , { 'priority' -> #priority }.
accessors at: PBValueBox put: { 'value' -> #value }.
"The registered classes, from the registry."
classes := (PBTypeRegistry _table values collect: [:entry | entry at: 1]) asSet asArray
  sort: [:a :b | a name <= b name].
"A distinct Integer per field name, whatever its position."
markers := Dictionary new.
classes do: [:cls | cls persistedFields do: [:f | markers at: f ifAbsent: [markers at: f put: 100 + markers size]]].
"An in-memory atom of aClass holding the marker of each field, in the order of aFieldArray."
build := [:aClass :aFieldArray |
  aClass _unsavedWithState: (PBFrozenDict withAssociations: (aFieldArray collect: [:f | f -> (markers at: f)]))].
sink := SegmentSink segment: (ByteArray fromHex: '16b016b016b016b016b016b016b016b0').
"A fresh stub of anAtom, saved first."
saveLoad := [:anAtom | anAtom _saveInto: sink. anAtom unloadedCopy].

c that: 'the registry lists the application node classes' isTrue: ((classes includes: ReorderedNode) and: [classes includes: ExtendedNode]).
(classes select: [:cls | cls slotFields notNil]) do: [:cls |
  | slotFields table cases |
  slotFields := cls slotFields.
  table := accessors at: cls ifAbsent: [#()].
  c that: cls name , ': one accessor per slot field' is: (table collect: [:a | a key]) asSet equals: slotFields asSet.
  cases := { 'built'. build value: cls value: cls persistedFields.
    'loaded'. saveLoad value: (build value: cls value: cls persistedFields).
    'loaded, attributes reversed'. saveLoad value: (build value: cls value: cls persistedFields reversed) }.
  1 to: cases size by: 2 do: [:k |
    | how atom |
    how := cases at: k.
    atom := cases at: k + 1.
    table do: [:a |
      c that: cls name , ' ' , how , ': ' , a value , ' reads slot ' , (slotFields indexOf: a key) printString
        is: (atom perform: a value) equals: (markers at: a key)]]].
"The built-in layouts are their record order: their writes share the keys and the slots."
{ PBPosNode. PBKeyNode. PBCountedKeyNode. PBValueBox } do: [:cls |
  c that: cls name , ': slotFields are persistedFields' is: cls slotFields equals: cls persistedFields].
"Every registered class: a loaded record in persisted order shares the class's keys."
(classes reject: [:cls | cls persistedFields isEmpty]) do: [:cls |
  stub := saveLoad value: (build value: cls value: cls persistedFields).
  c that: cls name , ': a loaded record shares the class keys' isTrue: (stub state _hasKeys: cls _recordShape persisted)].

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
