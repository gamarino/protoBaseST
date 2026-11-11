"EXPECT: ok 61"
"The checks of framing.st beyond the vectors: the atom envelope rules of the
 format spec ('Atom records', 'How a reader resolves a reference'), the field
 types of a root record, record and segment refusals, and PBAtom's lazy load
 through a storage (a test double answering one payload)."
Import from: 'protobase'.
Import from: '_check'.

PBAtom subclass: #Invoice.
Invoice class >> typeName
  ^ 'acme.sales.Invoice'.
Invoice class >> typeAliases
  ^ #('acme.sales.LegacyInvoice').

PBAtom subclass: #Ledger.
Ledger class >> typeName
  ^ 'acme.sales.Ledger'.
Ledger class >> requiredFields
  ^ #('count').

"A storage double: it answers its payload's envelope, checked against the expected tag."
Object subclass: #OnePayloadStorage instanceVariableNames: 'payload loads'.
OnePayloadStorage class >> payload: aByteArray
  ^ self new setPayload: aByteArray.
OnePayloadStorage >> setPayload: aByteArray
  payload := aByteArray.
  loads := 0.
OnePayloadStorage >> loads
  ^ loads.
OnePayloadStorage >> loadAt: aPointer expecting: aTag
  loads := loads + 1.
  ^ PBAtomEnvelope decode: payload expecting: aTag.

| c oid map payload env seg ptr wire root rootBytes record storage stub ref opaque refBytes |
c := Check new.
PBTypeRegistry register: Invoice; register: Ledger.
oid := ByteArray withAll: (1 to: 16) asArray.
seg := ByteArray withAll: (101 to: 116) asArray.
ptr := PBAtomPointer segment: seg offset: 26.
map := [:assocs | MessagePackMap withAll: assocs].
payload := [:t :o :s | MessagePack encode: (map value: { 't' -> t. 'oid' -> o. 's' -> s })].

"A valid envelope, by alias and by name; any key order is read."
env := PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'b' -> 2. 'a' -> 1 })) expecting: 19.
c that: 'tag' is: env tag equals: 19.
c that: 'oid' is: env oid equals: oid.
c that: 'state in wire order' is: (env state associations collect: [:a | a key]) equals: #('b' 'a').
c that: 'state values' is: (env state at: 'a') equals: 1.
env := PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: #())) expecting: 'proto_db.core.dbobject.DBObject'.
c that: 'a built-in reference by name' is: env tag equals: 19.
env := PBAtomEnvelope decode: (MessagePack encode: (map value: { 's' -> (map value: #()). 'oid' -> oid. 't' -> 19 })) expecting: 19.
c that: 'keys in another order' is: env oid equals: oid.

"The envelope's keys and fields."
c that: 'an extra key' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (MessagePack encode: (map value: { 't' -> 19. 'oid' -> oid. 's' -> (map value: #()). 'x' -> 1 })) expecting: 19].
c that: 'a missing key' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (MessagePack encode: (map value: { 't' -> 19. 'oid' -> oid })) expecting: 19].
c that: 'not a map' signals: PBCorruptionError during: [PBAtomEnvelope decode: (MessagePack encode: #(1 2 3)) expecting: 19].
c that: 'malformed msgpack' signals: PBCorruptionError during: [PBAtomEnvelope decode: #[193] expecting: 19].
c that: 'a float tag' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 1.5 value: oid value: (map value: #())) expecting: 19].
c that: 'an alias outside the table' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 22 value: oid value: (map value: #())) expecting: 19].
c that: 'a record of another type' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 5 value: oid value: (map value: #())) expecting: 19].
c that: 'an oid of 15 bytes' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: (oid copyFrom: 1 to: 15) value: (map value: #())) expecting: 19].
c that: 'a state that is not a map' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: #()) expecting: 19].
c that: 'a bytes attribute name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { #[97] -> 1 })) expecting: 19].
c that: 'an attribute starting with _' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { '_a' -> 1 })) expecting: 19].
c that: 'an attribute named oid' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'oid' -> 1 })) expecting: 19].
c that: 'an attribute named atom_pointer' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'atom_pointer' -> 1 })) expecting: 19].
c that: 'an attribute named context' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'context' -> 1 })) expecting: 19].
c that: 'an empty attribute name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { '' -> 1 })) expecting: 19].
c that: 'an attribute twice' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'a' -> 1. 'a' -> 2 })) expecting: 19].
c that: 'a value that is not canonical' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'a' -> (map value: { '@nope' -> 1 }) })) expecting: 19].

"Type names: aliases, and opaque atoms (D59)."
env := PBAtomEnvelope decode: (payload value: 'acme.sales.LegacyInvoice' value: oid value: (map value: #())) expecting: 'acme.sales.Invoice'.
c that: 'a record written under an alias' is: env tag equals: 'acme.sales.LegacyInvoice'.
env := PBAtomEnvelope decode: (payload value: 'acme.sales.Invoice' value: oid value: (map value: #())) expecting: 'acme.sales.LegacyInvoice'.
c that: 'a reference spelled by an alias' is: env tag equals: 'acme.sales.Invoice'.
env := PBAtomEnvelope decode: (payload value: 'poly.st.SalesOrder' value: oid value: (map value: #())) expecting: 'poly.st.Order'.
c that: 'an opaque record under a name only its owner knows' is: env tag equals: 'poly.st.SalesOrder'.
c that: 'an opaque reference to a proto_db. record name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 'proto_db.x.Y' value: oid value: (map value: #())) expecting: 'poly.st.Order'].
c that: 'an opaque record behind a proto_db. reference name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 'poly.st.Order' value: oid value: (map value: #())) expecting: 'proto_db.x.Y'].
c that: 'a known record behind an unknown reference name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: #())) expecting: 'poly.st.Order'].
c that: 'an unknown record behind a known reference name' signals: PBCorruptionError during: [
  PBAtomEnvelope decode: (payload value: 'poly.st.Order' value: oid value: (map value: #())) expecting: 'acme.sales.Invoice'].

"References in the state read with the writer's tag: a built-in name is its alias."
refBytes := { seg. 30. 'proto_db.collections.Dictionary' }.
env := PBAtomEnvelope decode: (payload value: 19 value: oid value: (map value: { 'r' -> (map value: { '@ref' -> refBytes }) })) expecting: 19.
c that: 'a reference by built-in name' is: (env state at: 'r') tag equals: 6.

"Encoding: t canonical, keys t, oid, s, every value through the codec."
env := PBAtomEnvelope tag: 'proto_db.core.dbobject.DBObject' oid: oid state: (PBFrozenDict withAssociations: { 'a' -> 1. 'l' -> #(1 2) }).
wire := MessagePack decodeOrdered: env encode strictKeys: false.
c that: 'encoded keys' is: (wire associations collect: [:a | a key]) equals: #('t' 'oid' 's').
c that: 'encoded tag' is: (wire at: 't' ifAbsent: [nil]) equals: 19.
c that: 'round trip' is: (PBAtomEnvelope decode: env encode expecting: 19) state equals: env state.
c that: 'tag:oid:state: refuses a reserved name' signals: PBValidationError during: [
  PBAtomEnvelope tag: 19 oid: oid state: (PBFrozenDict withAssociations: { 'context' -> 1 })].
c that: 'tag:oid:state: refuses a short oid' signals: PBValidationError during: [
  PBAtomEnvelope tag: 19 oid: #[1 2] state: (PBFrozenDict withAssociations: #())].
c that: 'tag:oid:state: refuses a bad tag' signals: PBValidationError during: [
  PBAtomEnvelope tag: 99 oid: oid state: (PBFrozenDict withAssociations: #())].

"Root records: keys in order, field types checked."
root := PBRootRecord segment: seg offset: 26 epoch: 7.
rootBytes := root encode.
wire := MessagePack decodeOrdered: (rootBytes copyFrom: 5 to: rootBytes size) strictKeys: false.
c that: 'root keys' is: (wire associations collect: [:a | a key]) equals: #('version' 'segment' 'offset' 'epoch').
c that: 'root round trip' is: (PBRootRecord decode: rootBytes) pointer equals: ptr.
rootBytes := [:fields | | body w |
  body := MessagePack encode: (map value: fields).
  w := WriteStream on: ByteArray new.
  w nextPutUnsigned: body crc32 width: 4 bigEndian: false; nextPutAll: body.
  w contents].
c that: 'a Boolean version' signals: PBCorruptionError during: [
  PBRootRecord decode: (rootBytes value: { 'version' -> true. 'segment' -> seg. 'offset' -> 26. 'epoch' -> 7 })].
c that: 'a negative offset' signals: PBCorruptionError during: [
  PBRootRecord decode: (rootBytes value: { 'version' -> 4. 'segment' -> seg. 'offset' -> -1. 'epoch' -> 7 })].
c that: 'a missing epoch' signals: PBCorruptionError during: [
  PBRootRecord decode: (rootBytes value: { 'version' -> 4. 'segment' -> seg. 'offset' -> 26 })].
c that: 'a short segment' signals: PBCorruptionError during: [
  PBRootRecord decode: (rootBytes value: { 'version' -> 4. 'segment' -> #[1 2]. 'offset' -> 26. 'epoch' -> 7 })].
c that: 'a malformed version-5 root is corruption first' signals: PBCorruptionError during: [
  PBRootRecord decode: (rootBytes value: { 'version' -> 5. 'segment' -> #[1]. 'offset' -> 26. 'epoch' -> 7 })].
c that: 'extra keys are ignored' is: (PBRootRecord decode: (rootBytes value: { 'version' -> 3. 'segment' -> seg. 'offset' -> 26. 'epoch' -> 7. 'x' -> 'y' })) epoch equals: 7.

"Records and segment headers."
record := PBRecordHeader encodeKind: 1 payload: #[1 2 3].
c that: 'a truncated payload' signals: PBCorruptionError during: [
  (PBRecordHeader decode: record) payloadOfRecord: (record copyFrom: 1 to: record size - 1)].
c that: 'a truncated header' signals: PBCorruptionError during: [PBRecordHeader decode: (record copyFrom: 1 to: 14)].
c that: 'encodeKind: 3' signals: PBValidationError during: [PBRecordHeader encodeKind: 3 payload: #[]].
c that: 'a truncated segment header' signals: PBCorruptionError during: [PBSegmentHeader decode: ((PBSegmentHeader encodeSegment: seg) copyFrom: 1 to: 25)].
c that: 'encodeSegment: 15 bytes' signals: PBValidationError during: [PBSegmentHeader encodeSegment: (seg copyFrom: 1 to: 15)].

"PBAtom: a stub loads once, through its storage, and memoises the envelope."
storage := OnePayloadStorage payload: (payload value: 'acme.sales.Invoice' value: oid value: (map value: { 'total' -> 5 })).
stub := Invoice unloadedAt: ptr storage: storage.
c that: 'a stub is not loaded' isTrue: stub isLoaded not.
c that: 'stateAt:' is: (stub stateAt: 'total') equals: 5.
c that: 'loaded once' is: storage loads equals: 1.
c that: 'oid after the load' is: stub oid equals: oid.
c that: 'an absent field of an application type reads nil' is: (stub stateAt: 'note') equals: nil.
c that: 'still loaded once' is: storage loads equals: 1.
c that: 'a stub is a reference' is: (PBCodec encode: stub) equals: (PBCodec encode: (PBUnresolvedRef pointer: ptr tag: 'acme.sales.Invoice')).
storage := OnePayloadStorage payload: (payload value: 'acme.sales.Ledger' value: oid value: (map value: { 'total' -> 5 })).
c that: 'a missing required field' signals: PBCorruptionError containing: 'count' during: [
  (Ledger unloadedAt: ptr storage: storage) state].
storage := OnePayloadStorage payload: (payload value: 'poly.st.Order' value: oid value: (map value: { 'qty' -> 2 })).
opaque := PBTypeRegistry unloadedAtomFor: 'poly.st.Order' at: ptr storage: storage.
c that: 'an opaque stub keeps its name' is: opaque tag equals: 'poly.st.Order'.
c that: 'an opaque field' is: (opaque stateAt: 'qty') equals: 2.
c that: 'an opaque absent field' signals: PBNotSupportedError containing: 'poly.st.Order' during: [opaque stateAt: 'total'].
c report displayNl.
