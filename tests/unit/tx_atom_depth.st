"EXPECT: ok 13"
"The depth of a stored attribute value (format spec v2.0.0rc2, 'Value nesting depth'; plan
 Tasks 13 and 17b): an attribute value nests at most MAX_VALUE_DEPTH = 1022 msgpack
 containers, counted from the value, and the atom payload {t, oid, s: {name: value}} adds
 two, so a record holds at most 1024. An attribute of 1022 nested lists is written and read
 back through a transaction; one of 1023 is refused with PBValidationError naming the
 attribute before any byte is written, never with protoST's raw msgpack Error. A record
 holding a 1023-deep value (raw bytes: no writer produces them) is refused when read with
 PBCorruptionError. ProtoBase's side of both is tests/interop/st_deep_to_py.sh."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base around depthOf deep envelope b ref over overOffset offset space tx value payload |
c := Check new.
base := FileSystem temp / ('pbst-tx-atom-depth-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
around := [:n :seed | | v | v := seed. n timesRepeat: [v := Array with: v]. v].
depthOf := [:v | | x n | x := v. n := 0. [x isKindOf: PBFrozenList] whileTrue: [n := n + 1. x := x at: 1]. n].
deep := around value: 1022 value: 1.
envelope := PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: { 'v' -> deep }).
c that: '1022 lists: the envelope is made' is: (depthOf value: (envelope state at: 'v')) equals: 1022.
c that: 'and decodes back' is: (depthOf value: ((PBAtomEnvelope decode: envelope encode expecting: 19) state at: 'v')) equals: 1022.
c that: '1023 lists: refused when the envelope is made, naming the attribute' signals: PBValidationError
  containing: 'Attribute ''v'': The value nests deeper than MAX_VALUE_DEPTH = 1022 MessagePack containers, the most the storage format allows (format spec, "Value nesting depth")' during: [
    PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: { 'v' -> (around value: 1023 value: 1) })].
c that: 'a map 1023 deep too' signals: PBValidationError containing: 'MAX_VALUE_DEPTH = 1022' during: [
  PBAtomEnvelope tag: 19 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: {
    'v' -> (around value: 1020 value: (PBFrozenDict withAssociations: { 1 -> 2 })) })].
c that: 'a DBObject field names itself' signals: PBValidationError
  containing: 'Field ''v'' of proto_db.core.dbobject.DBObject: The value nests deeper than MAX_VALUE_DEPTH = 1022 MessagePack containers, the most the storage format allows (format spec, "Value nesting depth")' during: [
    PBObject withAll: { 'v' -> (around value: 1023 value: 1) }].
c that: 'a DBObject field of 1022 lists' is: (depthOf value: ((PBObject withAll: { 'v' -> deep }) at: 'v')) equals: 1022.

"Through a space: the 1022-deep record is read back by a transaction; the 1023-deep one is
 refused before a byte reaches the segment; a raw record holding 1023 is refused when read."
b := SpaceBuilder segment: (ByteArray fromHex: '3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c').
ref := b add: 19 oid: 1 state: { 'v' -> deep }.
offset := b nextOffset.
c that: '1023 lists: add: refuses' signals: PBValidationError during: [
  b add: 19 oid: 2 state: { 'v' -> (around value: 1023 value: 1) }].
c that: 'no byte was written' is: b nextOffset equals: offset.
"{t: 19, oid: 16 x 03, s: {v: 1023 lists around 1}}: a record 1025 containers deep."
payload := (ByteArray fromHex: '83a17413a36f6964c410' , ((1 to: 16) inject: '' into: [:s :i | s , '03']) , 'a17381a176')
  , (ByteArray withAll: ((1 to: 1023) asArray collect: [:i | 16r91])) , (ByteArray fromHex: '01').
over := b addPayload: payload tag: 19.
space := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'deep'
  root: (b spaceWithDatabase: 'db' roots: { 'deep' -> ref. 'over' -> over } mutables: #() oids: 10))).
tx := (space openDatabase: 'db') newTransaction.
value := (tx getRootObject: 'deep') at: 'v'.
c that: 'read back by a transaction' is: (depthOf value: value) equals: 1022.
c that: 'the innermost value' is: ((1 to: 1022) inject: value into: [:x :i | x at: 1]) equals: 1.
c that: 'its token is the record''s pointer' is: (tx readSet at: 'deep') equals: ref pointer.
c that: 'its bytes re-encode to the record''s' is: (PBCodec encode: value) equals: (PBCodec encode: deep).
c that: 'a record holding 1023 lists is refused when read' signals: PBCorruptionError containing: 'nesting deeper' during: [
  (tx getRootObject: 'over') at: 'v'].
tx abort.
space close.
base deleteAll.
c report displayNl.
