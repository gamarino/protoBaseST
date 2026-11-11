"EXPECT: ok 9"
"The depth of a stored attribute value (plan Task 13, from the Task 7 re-review): ProtoBase
 packs an attribute value inside the atom payload {t, oid, s: {name: value}} at depth 2,
 and msgpack-python packs at most 511 containers, so the limit for an attribute value is
 509. The atom writer (PBAtomEnvelope tag:oid:state: and encode) passes the enclosing depth
 2 to the codec: an attribute of 509 nested lists is written and read back through a
 transaction; one of 510 is refused with PBValidationError before any byte is written,
 never with protoST's raw msgpack Error. ProtoBase's read of the 509-deep record is
 tests/interop/st_deep_to_py.sh."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base around depthOf deep envelope b ref offset space tx value |
c := Check new.
base := FileSystem temp / ('pbst-tx-atom-depth-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
around := [:n :seed | | v | v := seed. n timesRepeat: [v := Array with: v]. v].
depthOf := [:v | | x n | x := v. n := 0. [x isKindOf: PBFrozenList] whileTrue: [n := n + 1. x := x at: 1]. n].
deep := around value: 509 value: 1.
envelope := PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: { 'v' -> deep }).
c that: '509 lists: the envelope is made' is: (depthOf value: (envelope state at: 'v')) equals: 509.
c that: 'and decodes back' is: (depthOf value: ((PBAtomEnvelope decode: envelope encode expecting: 19) state at: 'v')) equals: 509.
c that: '510 lists: refused when the envelope is made' signals: PBValidationError containing: '511' during: [
  PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: { 'v' -> (around value: 510 value: 1) })].
c that: 'a 510-deep map value too' signals: PBValidationError containing: '511' during: [
  PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: {
    'v' -> (around value: 508 value: (PBFrozenDict withAssociations: { 1 -> 2 })) })].

"Through a space: the 509-deep record is read back by a transaction; the 510-deep one is
 refused before a byte reaches the segment."
b := SpaceBuilder segment: (ByteArray fromHex: '3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c').
ref := b add: 19 oid: 1 state: { 'v' -> deep }.
offset := b nextOffset.
c that: '510 lists: add: refuses' signals: PBValidationError during: [
  b add: 19 oid: 2 state: { 'v' -> (around value: 510 value: 1) }].
c that: 'no byte was written' is: b nextOffset equals: offset.
space := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'deep'
  root: (b spaceWithDatabase: 'db' roots: { 'deep' -> ref } mutables: #() oids: 10))).
tx := (space openDatabase: 'db') newTransaction.
value := (tx getRootObject: 'deep') at: 'v'.
c that: 'read back by a transaction' is: (depthOf value: value) equals: 509.
c that: 'the innermost value' is: ((1 to: 509) inject: value into: [:x :i | x at: 1]) equals: 1.
c that: 'its token is the record''s pointer' is: (tx readSet at: 'deep') equals: ref pointer.
tx abort.
space close.
base deleteAll.
c report displayNl.
