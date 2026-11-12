"EXPECT: ok 15"
"The polyglot_database section (README, 'Using the vectors', 9; design spec 10.1), the
 write half, on a copy of vectors/polyglot: the record that references the opaque records
 (the root 'holder', which holds a polyglot.st.Order and an older polyglot.st.SalesOrder
 record, neither of which protoBaseST has a class for) is changed and committed. The opaque
 records are kept byte for byte: the vendored segment file is unchanged (a commit only
 appends, to a segment of its own), the records at their original pointers hold the same
 payloads, the new holder references the same pointers, and the new segment holds no record
 of either opaque type (a record of the types the writer owns, such as the new holder
 DBObject, is written). The commit leaves the space valid for ProtoBase's verifier, which
 runs on the copy afterwards (SKIP without the interop venv)."
Import from: 'protobase'.
Import from: '_vectors'.

Object subclass: #Check instanceVariableNames: 'failures count'.
Check class >> new
  ^ self basicNew setUp.
Check >> setUp
  failures := OrderedCollection new.
  count := 0.
Check >> that: aLabel is: actual equals: expected
  count := count + 1.
  actual = expected ifFalse: [failures add: aLabel , ': expected ' , expected printString , ', got ' , actual printString].
Check >> that: aLabel isTrue: aBoolean
  ^ self that: aLabel is: aBoolean equals: true.
Check >> report
  failures do: [:each | ('FAIL ' , each) displayNl].
  ^ failures isEmpty ifTrue: ['ok ' , count printString] ifFalse: ['failed'].

| c dir section space db holder0 order0 older0 original originalBytes payloads typesOf types fresh holder1 verify |
c := Check new.
section := Vectors manifest at: 'polyglot_database'.
dir := Vectors copySpace: 'polyglot_database'.
original := dir / (section at: 'segment').
originalBytes := original binaryContents.
"typesOf value: aStorage value: aSegment: the type names of the atom records of segment aSegment (a UUID text), in file order."
typesOf := [:aStorage :aSegment |
  ((aStorage recordsOfSegment: aSegment) select: [:each | (each at: 2) isAtom]) collect: [:each |
    (PBTypeRegistry nameOfTag: ((MessagePack decodeOrdered: (each at: 3) strictKeys: true) at: 't' ifAbsent: [nil]))]].

space := PBObjectSpace storage: (PBFileStorage path: dir).
db := space openDatabase: 'db'.
holder0 := (db snapshotAt: db history first) getRootObject: 'holder'.
order0 := holder0 at: 'order'.
older0 := holder0 at: 'older_order'.
c that: 'the opaque records are read without a class' is: { order0 class. older0 class } equals: { PBOpaqueAtom. PBOpaqueAtom }.
payloads := { order0 pointer. older0 pointer } collect: [:ptr | (space storage recordAt: ptr) at: 2].

"Change the record that references them, and commit."
db newTransactionDo: [:t | | holder |
  holder := t getRootObject: 'holder'.
  t setRootObject: 'holder' value: (holder with: 'name' value: 'holder, rewritten')].
space close.

c that: 'the vendored segment file is byte for byte as it was' is: original binaryContents equals: originalBytes.
space := PBObjectSpace storage: (PBFileStorage path: dir).
db := space openDatabase: 'db'.
c that: 'a new version' is: (db history collect: [:e | e version]) asArray equals: #(3 2 1 0).
holder1 := (db snapshotAt: db history first) getRootObject: 'holder'.
c that: 'the holder is changed' is: (holder1 at: 'name') equals: 'holder, rewritten'.
c that: 'the new version references the same order pointer' is: (holder1 at: 'order') pointer equals: order0 pointer.
c that: 'and the same older record pointer' is: (holder1 at: 'older_order') pointer equals: older0 pointer.
c that: 'the opaque records still read' is: { ((holder1 at: 'order') at: 'number'). ((holder1 at: 'older_order') at: 'number') } equals: #(7 6).
c that: 'the payloads at the original pointers are unchanged'
  is: ({ (holder1 at: 'order') pointer. (holder1 at: 'older_order') pointer } collect: [:ptr | (space storage recordAt: ptr) at: 2])
  equals: payloads.
fresh := (dir children collect: [:f | f basename]) asArray select: [:name |
  (name endsWith: '.seg') and: [name ~= (section at: 'segment')]].
c that: 'the commit wrote one new segment' is: fresh size equals: 1.
types := typesOf value: space storage value: (fresh first copyFrom: 1 to: 32).
c that: 'the new segment holds records' isTrue: types notEmpty.
c that: 'it holds the new holder' isTrue: (types includes: 'proto_db.core.dbobject.DBObject').
c that: 'no new record of type polyglot.st.Order' is: (types select: [:t | t = 'polyglot.st.Order']) size equals: 0.
c that: 'nor of polyglot.st.SalesOrder' is: (types select: [:t | t = 'polyglot.st.SalesOrder']) size equals: 0.
c that: 'the old segment still holds both opaque records'
  is: ((typesOf value: space storage value: ((section at: 'segment') copyFrom: 1 to: 32)) select: [:t | t beginsWith: 'polyglot.st.']) asArray
  equals: #('polyglot.st.Order' 'polyglot.st.SalesOrder').
space close.

verify := OSProcess run: 'bash' arguments: { '../interop/_verify_space.sh'. dir pathString }.
c that: 'ProtoBase verifies the rewritten space (77: no venv)' isTrue: (#(0 77) includes: verify exitCode).
verify exitCode = 0 ifFalse: [verify exitCode = 77 ifFalse: [('FAIL ' , verify output , verify errorOutput) displayNl]].
dir deleteAll.
verify exitCode = 77
  ifTrue: [
    c report = 'failed' ifTrue: [Smalltalk exit: 1].
    'SKIP: the interop venv is missing (run tests/interop/setup_venv.sh): ProtoBase did not verify the rewritten space' displayNl]
  ifFalse: [c report displayNl].
