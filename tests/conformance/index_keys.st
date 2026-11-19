"EXPECT: index keys ok"
"The key vectors of the indexed queries (plan Task 2, spec 6.1.1): vectors-index-keys/keys.msgpack,
 written by tests/interop/py_index_keys.py with proto_db at v2.0.0rc4 (seed 20261118) and checked
 against manifest.sha256 before it is read. For every case PBMemberKeys and PBKeys answer what
 proto_db's keyed.py and values.py answered: PBKeys isOrderable:, the depth and wire bytes of
 surrogate:, checkDepth:'s refusal (proto_db's sentence, whose subject is the index it names,
 'Index 'by_key' (EqualityIndex on <element>)', where PBMemberKeys, which knows no index, says
 'An index'), the
 depth and wire bytes of memberKeyOf:, and, for the cases whose member key nests at most
 'shallow' containers, where lowestOf: and highestOf: fall among all those cases' member keys
 (how many order below each bound). Every atom is written {'@ref': [oid, 0, tag]}: a case's atom
 is rebuilt from its oid, and written back the same way. Values cover every rank, the
 unorderables, PBMissing, nil, atoms, seeded random values and the depth limits of member keys
 (nested lists, maps and tuples at each limit and one container past it)."
Import from: 'protobase'.

"Resolves a case's references: an atom of the oid its segment holds (one per oid), and
 writes them back the same way."
Object subclass: #IndexKeysAtoms instanceVariableNames: 'atoms'.

IndexKeysAtoms class >> new
  ^ self basicNew setUp.

IndexKeysAtoms >> setUp
  atoms := Dictionary new.

IndexKeysAtoms >> refTo: aSegmentBytes offset: anInteger tag: aTag
  ^ atoms at: aSegmentBytes hex ifAbsentPut: [
    PBObject basicNew _setOid: aSegmentBytes copy pointer: nil storage: nil].

IndexKeysAtoms >> refBlock
  ^ [:anAtom | MessagePackMap withAll: { '@ref' -> { anAtom oid. 0. PBTypeRegistry writerTag: anAtom tag } }].

IndexKeysAtoms >> bytesOf: aValue
  ^ MessagePack encode: (PBCodec toWire: aValue atomRef: self refBlock).

| blob listed data limits shallow cases atoms values fails tail okeys bounded refused |
blob := 'vectors-index-keys/keys.msgpack' asFileReference binaryContents.
listed := 'vectors-index-keys/manifest.sha256' asFileReference contents.
(listed copyFrom: 1 to: 64) = blob sha256 hex asLowercase ifFalse: [
  Error signal: 'vectors-index-keys/keys.msgpack does not match manifest.sha256'].
data := MessagePack decode: blob.
fails := OrderedCollection new.
limits := data at: 'limits'.
PBMemberKeys depthLimits = (PBFrozenDict withAssociations: {
    'orderable' -> (limits at: 'orderable'). 'lists' -> (limits at: 'lists'). 'maps' -> (limits at: 'maps') })
  ifFalse: [fails add: 'depth limits ' , PBMemberKeys depthLimits printString].
(limits at: 'max_value_depth') = PBCodec maxValueDepth ifFalse: [fails add: 'MAX_VALUE_DEPTH'].
shallow := data at: 'shallow'.
cases := data at: 'cases'.
atoms := IndexKeysAtoms new.
values := cases collect: [:case |
  PBCodec fromWire: (MessagePack decodeOrdered: (case at: 'value') strictKeys: false) resolver: atoms].
okeys := OrderedCollection new.
cases doWithIndex: [:case :i |
  | id v sur refusal key bad |
  id := case at: 'id'.
  v := values at: i.
  bad := [:what :got :want | fails add: id , ': ' , what , ' is ' , got printString , ', proto_db says ' , want printString].
  (PBKeys isOrderable: v) = (case at: 'orderable') ifFalse: [bad value: 'isOrderable' value: (PBKeys isOrderable: v) value: (case at: 'orderable')].
  sur := PBMemberKeys surrogate: v.
  (PBCodec valueDepth: sur) = (case at: 'surrogate_depth') ifFalse: [
    bad value: 'the surrogate depth' value: (PBCodec valueDepth: sur) value: (case at: 'surrogate_depth')].
  (case at: 'surrogate') isNil ifFalse: [
    (atoms bytesOf: sur) = (case at: 'surrogate') ifFalse: [bad value: 'the surrogate' value: (atoms bytesOf: sur) hex value: (case at: 'surrogate') hex]].
  refusal := [PBMemberKeys checkDepth: v. nil] on: PBValidationError do: [:e | e return: e messageText].
  (case at: 'refusal') isNil
    ifTrue: [refusal isNil ifFalse: [bad value: 'the refusal' value: refusal value: nil]]
    ifFalse: [
      "proto_db names the generator's index first; PBMemberKeys says 'An index'."
      tail := ((case at: 'refusal') beginsWith: 'Index ''by_key'' (EqualityIndex on <element>) ')
        ifTrue: [(case at: 'refusal') copyFrom: 45 to: (case at: 'refusal') size]
        ifFalse: ['(an unexpected proto_db sentence) ' , (case at: 'refusal')].
      refusal = ('An index ' , tail) ifFalse: [bad value: 'the refusal' value: refusal value: tail]].
  key := PBMemberKeys memberKeyOf: v.
  (PBCodec valueDepth: key) = (case at: 'member_key_depth') ifFalse: [
    bad value: 'the member key depth' value: (PBCodec valueDepth: key) value: (case at: 'member_key_depth')].
  (case at: 'member_key') isNil ifFalse: [
    (atoms bytesOf: key) = (case at: 'member_key') ifFalse: [bad value: 'the member key' value: (atoms bytesOf: key) hex value: (case at: 'member_key') hex]].
  (case at: 'member_key_depth') <= shallow ifTrue: [okeys add: (PBKeys orderKey: key)]].
bounded := 0.
cases doWithIndex: [:case :i |
  | low high lowBelow highBelow |
  (case at: 'low_below') isNil ifFalse: [
    bounded := bounded + 1.
    low := PBMemberKeys lowestOf: (values at: i).
    high := PBMemberKeys highestOf: (values at: i).
    lowBelow := (okeys select: [:k | k < low]) size.
    highBelow := (okeys select: [:k | k < high]) size.
    { lowBelow. highBelow } = { case at: 'low_below'. case at: 'high_below' } ifFalse: [
      fails add: (case at: 'id') , ': the bounds have ' , { lowBelow. highBelow } printString
        , ' member keys below them, proto_db says ' , { case at: 'low_below'. case at: 'high_below' } printString]]].
refused := (cases select: [:case | (case at: 'refusal') notNil]) size.
(cases size >= 250 and: [refused >= 5 and: [bounded >= 250]]) ifFalse: [fails add: 'too few cases'].
('checked ' , cases size printString , ' cases: ' , refused printString , ' depth refusals, '
  , bounded printString , ' bound pairs') displayNl.
fails do: [:f | ('FAIL ' , f) displayNl].
fails isEmpty
  ifTrue: ['index keys ok' displayNl]
  ifFalse: [('FAILED: ' , fails size printString , ' mismatches over ' , cases size printString , ' cases') displayNl].
