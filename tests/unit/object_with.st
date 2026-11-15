"EXPECT: ok 34"
"New records (plan Task 15; ProtoBase DBObject(**attrs) and with_): PBObject withAll:,
 Invoice withAll: for an application class, with:value: and withAll: on a record. Each
 answers a new record, a new atom whose oid differs from the old one's; the old record is
 unchanged. Attributes keep the order they were given in; a change keeps an existing
 attribute's place and appends a new one, as ProtoBase's dict update. Values are made
 canonical at once. Attribute names are checked as the format spec's 'Atom records'
 requires (PBValidationError): not empty, no leading _, not oid, atom_pointer or context,
 not a behaviour name of DBObject or of the class; a name given twice is refused. A record
 of a class that is not registered can be built; a record read from storage answers new
 versions too; an opaque atom refuses with:value: naming its type.
 parents and with_parents are reserved for new fields (proto_db 2.0.0rc4, format spec 'Reserved
 names', R157): a change naming either is PBValidationError, while a stored field of either
 name still loads, reads, and is carried unchanged by a new version."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

PBObject subclass: #Invoice.
Invoice class >> typeName
  ^ 'tests.with.Invoice'.
Invoice class >> reservedAttributeNames
  ^ #('isPaid').
Invoice >> number
  ^ self at: 'number'.

| c a b oldOid inv inv2 base sb ref st stub newer opaque legacyRef legacy carried |
c := Check new.
a := PBObject withAll: { 'name' -> 'Ada'. 'born' -> 1815 }.
c that: 'withAll: holds the attributes' is: (a at: 'name') equals: 'Ada'.
c that: 'in the order given' is: a state keys equals: #('name' 'born').
c that: 'an absent attribute reads nil' is: (a at: 'died') equals: nil.
oldOid := a oid.
b := a with: 'born' value: 1816.
c that: 'with:value: answers a new record' is: (b at: 'born') equals: 1816.
c that: 'a new oid differs from the old' isTrue: b oid ~= oldOid.
c that: 'the old record is unchanged' is: (a at: 'born') equals: 1815.
c that: 'the old record keeps its oid' is: a oid equals: oldOid.
c that: 'they are different atoms' is: a = b equals: false.
c that: 'a change keeps the attribute''s place' is: b state keys equals: #('name' 'born').
c that: 'a new attribute is appended' is: (a with: 'died' value: 1852) state keys equals: #('name' 'born' 'died').
c that: 'nil defines the attribute' isTrue: ((a with: 'died' value: nil) hasDefinedAttr: 'died').
c that: 'withAll: on a record' is: ((a withAll: { 'born' -> 1. 'x' -> 2 }) state keys) equals: #('name' 'born' 'x').
c that: 'a value is made canonical' is: ((a with: 'tags' value: #('a' 'b')) at: 'tags') class equals: PBFrozenList.
c that: 'a refused value' signals: PBValidationError during: [a with: 'f' value: 1/3].
c that: 'with: ''_x''' signals: PBValidationError containing: '_x' during: [a with: '_x' value: 1].
c that: 'with: ''oid''' signals: PBValidationError containing: 'oid' during: [a with: 'oid' value: 1].
c that: 'with: ''context''' signals: PBValidationError during: [a with: 'context' value: 1].
c that: 'with: an empty name' signals: PBValidationError during: [a with: '' value: 1].
c that: 'with: a non-String name' signals: PBValidationError during: [a with: 3 value: 1].
c that: 'with: ''with_''' signals: PBValidationError containing: 'with_' during: [a with: 'with_' value: 1].
c that: 'withAll: a name given twice' signals: PBValidationError containing: 'twice'
  during: [PBObject withAll: { 'a' -> 1. 'a' -> 2 }].
c that: 'a new field named parents or with_parents is refused'
  is: ({ [PBObject withAll: { 'parents' -> 1 }]. [a with: 'with_parents' value: 1]. [Invoice withAll: { 'parents' -> #() }] }
    collect: [:block | [block value. 'created'] on: PBValidationError do: [:e |
      ((e messageText includesSubstring: 'parents') and: [e messageText includesSubstring: 'reserved'])
        ifTrue: ['refused'] ifFalse: [e messageText]]])
  equals: #('refused' 'refused' 'refused').
c that: 'withAll: not Associations' signals: PBValidationError during: [PBObject withAll: #(1 2)].
c that: 'PBObject new is an empty record' is: PBObject new state size equals: 0.
"An application class, not registered yet: records can be built."
inv := Invoice withAll: { 'number' -> 1043. 'total' -> (Decimal fromString: '12.50') }.
c that: 'Invoice withAll: answers an Invoice' is: inv class equals: Invoice.
c that: 'its accessor' is: inv number equals: 1043.
c that: 'a name the class reserves' signals: PBValidationError containing: 'isPaid' during: [inv with: 'isPaid' value: true].
inv2 := inv with: 'total' value: 13.
c that: 'with:value: keeps the class' is: inv2 class equals: Invoice.
"A record read from storage answers new versions too."
base := FileSystem temp / ('pbst-object-with-' , Smalltalk pid printString).
base deleteAll.
sb := SpaceBuilder segment: (ByteArray fromHex: '0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d').
ref := sb add: 19 oid: 7 state: { 'name' -> 'Grace'. 'born' -> 1906 }.
opaque := sb add: 'tests.with.Unknown' oid: 8 state: { 'x' -> 1 }.
legacyRef := sb add: 19 oid: 9 state: { 'parents' -> 'p'. 'with_parents' -> 3. 'n' -> 1 }.
sb writeTo: base root: ref.
st := PBFileStorage path: base.
stub := PBTypeRegistry unloadedAtomFor: 19 at: ref pointer storage: st.
newer := stub with: 'born' value: 1907.
c that: 'a stored record''s new version' is: { newer at: 'name'. newer at: 'born'. newer pointer } equals: { 'Grace'. 1907. nil }.
c that: 'a stored record is unchanged' is: (stub at: 'born') equals: 1906.
c that: 'an opaque atom refuses with:value:' signals: PBNotSupportedError containing: 'tests.with.Unknown'
  during: [(PBTypeRegistry unloadedAtomFor: 'tests.with.Unknown' at: opaque pointer storage: st) with: 'x' value: 2].
legacy := PBTypeRegistry unloadedAtomFor: 19 at: legacyRef pointer storage: st.
c that: 'a stored field parents or with_parents loads and reads'
  is: { legacy at: 'parents'. legacy at: 'with_parents'. legacy hasDefinedAttr: 'parents' } equals: #('p' 3 true).
carried := legacy with: 'n' value: 2.
c that: 'a new version carries a stored parents and with_parents unchanged'
  is: { carried state keys. carried at: 'parents'. carried at: 'with_parents'. carried at: 'n' }
  equals: { #('parents' 'with_parents' 'n'). 'p'. 3. 2 }.
c that: 'a stored parents field cannot be changed' signals: PBValidationError containing: 'parents'
  during: [legacy with: 'parents' value: 'q'].
st close.
base deleteAll.
c report displayNl.
