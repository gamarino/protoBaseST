"EXPECT: ok 17"
"Atoms as map keys and order keys (FS 'Order keys', rank 14; ProtoBase
 map_key_ids and Atom.__eq__/__hash__): an atom is identified by its oid,
 whether it is a stub (its record is loaded to read the oid), a saved atom or
 an unsaved one that knows its oid, so its identity never changes when it is
 saved. Two keys of one oid conflict: a writer refuses the map
 (PBValidationError) and a reader refuses a map holding references to two
 records of one oid (PBCorruptionError). A fresh atom whose oid is not
 assigned yet (oid assignment comes with plan Task 15) has no key:
 PBNotSupportedError, from orderKey:, hashKey: and isOrderable: alike. A
 reference decoded without a resolver (PBUnresolvedRef) has no known oid: as
 a map key it is identified by its pointer."
Import from: 'protobase'.
Import from: '_check'.
PBAtom subclass: #KeyAtom.
KeyAtom class >> typeName
  ^ 'acme.keys.KeyAtom'.
"A storage double: the record at a pointer has the oid listed for its offset."
Object subclass: #OidStorage instanceVariableNames: 'oids'.
OidStorage class >> oids: aDictionary
  ^ self new setOids: aDictionary.
OidStorage >> setOids: aDictionary
  oids := aDictionary.
OidStorage >> loadAt: aPointer expecting: aTag
  ^ PBAtomEnvelope tag: aTag oid: (oids at: aPointer offset) state: (PBFrozenDict withAssociations: #()).
OidStorage >> refTo: aByteArray offset: anInteger tag: aTag
  ^ PBTypeRegistry unloadedAtomFor: aTag at: (PBAtomPointer segment: aByteArray offset: anInteger) storage: self.
| c seg x y storage withOid stub fresh mapBytes bytes |
c := Check new.
PBTypeRegistry register: KeyAtom.
x := ByteArray withAll: (1 to: 16) asArray.
y := ByteArray withAll: (17 to: 32) asArray.
seg := ByteArray withAll: (101 to: 116) asArray.
storage := OidStorage oids: (Dictionary new at: 26 put: x; at: 90 put: x; at: 150 put: y; yourself).
withOid := [:oid | KeyAtom basicNew _setOid: oid pointer: nil storage: nil].
stub := [:offset | KeyAtom unloadedAt: (PBAtomPointer segment: seg offset: offset) storage: storage].
fresh := KeyAtom basicNew _setOid: nil pointer: nil storage: nil.
"Order and hash keys come from the oid, for a stub as for an unsaved atom."
c that: 'a stub and an unsaved atom of one oid are one order key' is: (PBKeys orderKey: (stub value: 26)) equals: (PBKeys orderKey: (withOid value: x)).
c that: 'and one hash key' is: (PBKeys hashKey: (stub value: 26)) equals: (PBKeys hashKey: (withOid value: x)).
c that: 'atoms order by oid' is: (PBKeys compare: (withOid value: x) with: (stub value: 150)) equals: -1.
"The writer's rule."
c that: 'two atoms of one oid conflict (writer)' signals: PBValidationError containing: 'conflict' during: [
  PBKeys checkMapKeys: { withOid value: x. withOid value: x } reading: false].
c that: 'two atoms of two oids do not conflict (writer)' is: (PBKeys checkMapKeys: { withOid value: x. withOid value: y } reading: false) equals: PBKeys.
"The reader's rule (PBFrozenDict)."
c that: 'two atoms of one oid conflict (reader)' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { (withOid value: x) -> 1. (withOid value: x) -> 2 }].
c that: 'a stub and an unsaved atom of its oid conflict' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { (stub value: 26) -> 1. (withOid value: x) -> 2 }].
c that: 'two stubs of two records of one oid conflict' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { (stub value: 26) -> 1. (stub value: 90) -> 2 }].
c that: 'a lookup by another instance of the oid' is: ((PBFrozenDict withAssociations: { (stub value: 26) -> 'a'. (stub value: 150) -> 'b' })
  at: (withOid value: x)) equals: 'a'.
c that: 'a lookup by the saved form of an unsaved key' is: ((PBFrozenDict withAssociations: { (withOid value: y) -> 'b' })
  at: (stub value: 150)) equals: 'b'.
"Decoding: references to two records of one oid are a corrupt map."
mapBytes := [:offsets | PBCodec encode: (PBFrozenDict withAssociations: (offsets collect: [:o |
  (PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: o) tag: 'acme.keys.KeyAtom') -> o]))].
bytes := mapBytes value: #(26 90).
c that: 'unresolved references are keys by pointer' is: (PBCodec decode: bytes) size equals: 2.
c that: 'a decoded map of two records of one oid is corrupt' signals: PBCorruptionError during: [
  PBCodec fromWire: (MessagePack decodeOrdered: bytes strictKeys: false) resolver: storage].
c that: 'a decoded map of two oids' is: (PBCodec fromWire: (MessagePack decodeOrdered: (mapBytes value: #(26 150)) strictKeys: false) resolver: storage) size equals: 2.
"A fresh atom, whose oid is not assigned yet."
c that: 'orderKey: of a fresh atom' signals: PBNotSupportedError containing: 'oid' during: [PBKeys orderKey: fresh].
c that: 'hashKey: of a fresh atom' signals: PBNotSupportedError containing: 'oid' during: [PBKeys hashKey: fresh].
c that: 'isOrderable: of a fresh atom' signals: PBNotSupportedError containing: 'oid' during: [PBKeys isOrderable: fresh].
c that: 'a fresh atom as a map key' signals: PBNotSupportedError containing: 'oid' during: [
  PBFrozenDict withAssociations: { fresh -> 1 }].
c report displayNl.
