"EXPECT: ok 83"
"Atom weight, stage 2 (plan Task 12). An atom whose class has a record shape (its persistedFields,
 when its slots are its state: _PBRecordShape keepsState:) and whose state holds exactly those
 fields, in that order, keeps its slots, its oid and the shared shape, never an envelope or a
 state dictionary: built by a write, built from a state, loaded with the atom cache off and on.
 Its state is derived on demand and is = to the state it was built from or decoded from; = and
 hash are the oid's, as before. Every other atom keeps its envelope, as before: a record of no
 shape (PBObject), a record whose names differ from its class's shape (attributes reversed),
 an opaque atom. The atom cache keeps what the atom keeps: for a shaped record, its slots and
 its oid. A record whose names equal the shape takes the decoder's fast path; one whose names
 do not, or whose class declares a name no record may carry, takes the checked path, with its
 errors. The oid pool marks a batch as UUID new marks each oid, and hands out distinct oids
 under two drawing actors whatever the interleaving."
Import from: 'protobase'.
Import from: '_check'.

"A keyed node class whose persistedFields hold a name every reader refuses: its shape cannot
 take the decoder's fast path."
PBKeyNode subclass: #BadNameNode.
BadNameNode class >> typeName
  ^ 'stagetwo.BadNameNode'.
BadNameNode class >> persistedFields
  ^ #('key' 'value' 'left' 'right' 'height' 'count' '_hidden').
BadNameNode class >> slotFields
  ^ BadNameNode persistedFields.

"A shaped node and a record that count the reads of their whole state (StateReads, a test-local OrderedCollection):
 a key path step reads one field through the memo and builds no state (plan Task 12, fix round 1)."
PBCountedKeyNode subclass: #StateCountingNode classVariableNames: 'StateReads'.
StateCountingNode class >> reads
  ^ StateReads size.
StateCountingNode class >> resetReads
  StateReads := OrderedCollection new.
StateCountingNode >> state
  StateReads isNil ifFalse: [StateReads add: 1].
  ^ super state.
PBObject subclass: #StateCountingRecord classVariableNames: 'StateReads'.
StateCountingRecord class >> reads
  ^ StateReads size.
StateCountingRecord class >> resetReads
  StateReads := OrderedCollection new.
StateCountingRecord >> state
  StateReads isNil ifFalse: [StateReads add: 1].
  ^ super state.

"A registered shaped node that counts, during a save, the reads of its whole state (one per
 saved atom: the walk builds it once and the push and the atom cache reuse it) and the stubs
 made of it (one per reference the atom cache keeps: a stub is never stubbed again) (plan
 Task 10, Step 0)."
PBCountedKeyNode subclass: #SaveCountingNode classVariableNames: 'StateReads Stubs'.
SaveCountingNode class >> typeName
  ^ 'stagetwo.SaveCountingNode'.
SaveCountingNode class >> reads
  ^ StateReads size.
SaveCountingNode class >> stubs
  ^ Stubs size.
SaveCountingNode class >> resetCounts
  StateReads := OrderedCollection new.
  Stubs := OrderedCollection new.
SaveCountingNode >> state
  StateReads isNil ifFalse: [StateReads add: 1].
  ^ super state.
SaveCountingNode >> _pbStubIn: aStorage
  Stubs isNil ifFalse: [Stubs add: 1].
  ^ super _pbStubIn: aStorage.

"Draws n oids, on an actor."
Object subclass: #Drawer.
Drawer >> draw: n
  ^ (1 to: n) asArray collect: [:i | _PBOidPool next].

| c holds keeps ok v node expected base st cached plain stub box list rec reversed ptr opaque bytes
  entry decoded twin raw marked drawn f1 f2 all shape elements fresh |
c := Check new.
"Whether an instance variable of anObject holds an instance of aClass."
holds := [:anObject :aClass |
  anObject class allInstVarNames anySatisfy: [:name | (anObject instVarNamed: name) isKindOf: aClass]].
"Whether anAtom keeps only its slots: no envelope, no state dictionary, the shared shape."
keeps := [:anAtom |
  ((holds value: anAtom value: PBAtomEnvelope) or: [holds value: anAtom value: PBFrozenDict]) not
    and: [(anAtom instVarNamed: 'memo') == anAtom class _recordShape]].
PBTypeRegistry register: BadNameNode.
PBTypeRegistry register: SaveCountingNode.

"--- built in memory ---"
ok := PBKeys orderKey: 5.
v := PBTuple withAll: { 'payload'. 1 }.
node := PBCountedKeyNode key: 5 orderKey: ok value: v left: nil right: nil.
expected := PBFrozenDict withAssociations: {
  'key' -> 5. 'value' -> v. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1. 'weight' -> 1 }.
c that: 'a node a write builds keeps only its slots' isTrue: (keeps value: node).
c that: 'its state is derived, a PBFrozenDict' isTrue: node state class == PBFrozenDict.
c that: 'equal to the state it was built from' is: node state equals: expected.
c that: 'on the class''s shared keys' isTrue: (node state _hasKeys: PBCountedKeyNode _recordShape persisted).
c that: 'over its slots' isTrue: (node state _valuesIfKeys: PBCountedKeyNode persistedFields) == node _slots.
c that: 'stateAt: reads a field' is: (node stateAt: 'weight') equals: 1.
c that: 'stateAt: of a field it does not hold reads nil' is: (node stateAt: 'nope') equals: nil.
c that: 'it is loaded' isTrue: node isLoaded.
box := PBValueBox _unsavedWithState: (PBFrozenDict withAssociations: { 'value' -> 'big' }).
c that: 'an atom built from a state in its shape keeps only its slots' isTrue: (keeps value: box).
c that: 'and answers that state' is: box state equals: (PBFrozenDict withAssociations: { 'value' -> 'big' }).
list := (PBList new appendLast: 'a') appendLast: 'b'.
c that: 'a collection version keeps only its slots' isTrue: (keeps value: list).
elements := OrderedCollection new.
list do: [:e | elements add: e].
c that: 'and reads its elements' is: elements asArray equals: #('a' 'b').
c that: 'a copy a write makes keeps only its slots' isTrue: (keeps value: (node withValue: (PBTuple withAll: { 'other'. 1 }))).
rec := PBObject withAll: { 'a' -> 1 }.
c that: 'a record of no shape keeps its envelope' isTrue: (holds value: rec value: PBAtomEnvelope).
c that: 'an atom whose state lacks a field of its shape keeps its envelope' isTrue:
  (holds value: (PBValueBox _unsavedWithState: (PBFrozenDict withAssociations: #())) value: PBAtomEnvelope).

base := FileSystem temp / ('pbst-atom-weight-stage2-' , Smalltalk pid printString).
base deleteAll.
[
  "--- loaded, cache off and on ---"
  plain := PBFileStorage path: (base / 'plain') pathString atomCacheEntries: 0.
  node _saveInto: plain.
  stub := PBCountedKeyNode unloadedAt: node pointer storage: plain.
  c that: 'a stub keeps nothing before its load' isTrue: stub isLoaded not.
  stub key.
  c that: 'a loaded stub keeps only its slots (no cache)' isTrue: (keeps value: stub).
  c that: 'its state equals the saved node''s' is: stub state equals: node state.
  c that: 'its oid is the record''s' is: stub knownOid equals: node oid.
  c that: 'it is = to the node saved' isTrue: (stub = node and: [node = stub]).
  c that: 'and hashes as it' is: stub hash equals: node hash.
  stub := PBCountedKeyNode unloadedAt: node pointer storage: plain.
  c that: 'a stub''s first need may be its oid' is: stub oid equals: node oid.
  c that: 'which loads it' isTrue: (keeps value: stub).
  twin := node _decodedTwin.
  c that: 'a decoded twin keeps only its slots' isTrue: (keeps value: twin).
  c that: 'and its state equals the node''s' is: twin state equals: node state.

  st := PBFileStorage path: (base / 'cached') pathString.
  fresh := PBCountedKeyNode key: 6 orderKey: (PBKeys orderKey: 6) value: v left: nil right: nil.
  ptr := st save: fresh.
  entry := (st instVarNamed: 'atomCache') entryAt: ptr class: PBCountedKeyNode.
  c that: 'a save caches the record' isTrue: entry notNil.
  c that: 'the cache keeps what the atom keeps: its oid' is: (entry at: 3) equals: fresh oid.
  c that: 'and its slots, no envelope' isTrue: ((entry at: 4) class == Array and: [(entry at: 4) = fresh _slots]).
  cached := PBCountedKeyNode unloadedAt: ptr storage: st.
  c that: 'a stub of a cached record reads its key' is: cached key equals: 6.
  c that: 'a stub loaded from the cache keeps only its slots' isTrue: (keeps value: cached).
  c that: 'and its state equals the fresh''s' is: cached state equals: fresh state.
  c that: 'and its oid' is: cached oid equals: fresh oid.
  ptr := st save: rec.
  entry := (st instVarNamed: 'atomCache') entryAt: ptr class: PBObject.
  c that: 'a record of no shape is cached as its envelope' isTrue: ((entry at: 4) isKindOf: PBAtomEnvelope).
  stub := PBObject unloadedAt: ptr storage: st.
  c that: 'and loads from the cache with its envelope' isTrue: ((stub stateAt: 'a') = 1 and: [holds value: stub value: PBAtomEnvelope]).

  "--- the generic path ---"
  reversed := PBKeyNode _unsavedWithState: (PBFrozenDict withAssociations:
    (PBKeyNode persistedFields reversed collect: [:f | f -> (f = 'height' | (f = 'count') ifTrue: [1] ifFalse: [f])])).
  c that: 'a record in another order keeps its envelope' isTrue: (holds value: reversed value: PBAtomEnvelope).
  reversed _saveInto: plain.
  stub := reversed unloadedCopy.
  c that: 'loaded, it reads its fields' is: stub key equals: 'key'.
  c that: 'through the checked path: it keeps its envelope' isTrue: (holds value: stub value: PBAtomEnvelope).
  c that: 'and its record''s order' is: stub state keys equals: PBKeyNode persistedFields reversed.
  c that: 'and is = to the atom saved' isTrue: stub = reversed.
  opaque := plain pushAtom: (PBAtomEnvelope tag: 'stagetwo.Elsewhere' oid: (ByteArray new: 16) state:
    (PBFrozenDict withAssociations: { 'x' -> 1 })).
  opaque := PBOpaqueAtom named: 'stagetwo.Elsewhere' unloadedAt: opaque storage: plain.
  c that: 'an opaque atom reads its fields' is: (opaque at: 'x') equals: 1.
  c that: 'and keeps its envelope' isTrue: (holds value: opaque value: PBAtomEnvelope).

  "--- the decoder: fast path and checked path ---"
  bytes := (PBAtomEnvelope tag: (PBTypeRegistry tagFor: PBKeyNode) oid: (ByteArray new: 16)
    state: (PBFrozenDict withAssociations: { 'key' -> 1. 'value' -> 'v'. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 })) encode.
  decoded := PBAtomEnvelope decode: bytes expecting: (PBTypeRegistry tagFor: PBKeyNode).
  c that: 'a record in its shape decodes on the shared keys' isTrue: (decoded state _hasKeys: PBKeyNode _recordShape persisted).
  c that: 'with its values' is: decoded state equals: (PBFrozenDict withAssociations: {
    'key' -> 1. 'value' -> 'v'. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }).
  shape := BadNameNode _recordShape.
  c that: 'a shape that names a field no record may carry takes no fast path' is: shape persistedNamesValid equals: false.
  c that: 'the built-in shapes do' is: PBKeyNode _recordShape persistedNamesValid equals: true.
  "msgpack {t: 'stagetwo.BadNameNode', oid: 16 zero bytes, s: {key: 1, value: 1, left: nil,
   right: nil, height: 1, count: 1, _hidden: 1}}, written by hand: no writer writes it."
  bytes := (MessagePack encode: (MessagePackMap withAll: {
    't' -> 'stagetwo.BadNameNode'. 'oid' -> (ByteArray new: 16).
    's' -> (MessagePackMap withAll: { 'key' -> 1. 'value' -> 1. 'left' -> nil. 'right' -> nil.
      'height' -> 1. 'count' -> 1. '_hidden' -> 1 }) })).
  c that: 'a record whose names are such a shape''s is refused as before' signals: PBCorruptionError
    containing: 'PBAtomEnvelope: the attribute name ''_hidden'' starts with _'
    during: [PBAtomEnvelope decode: bytes expecting: 'stagetwo.BadNameNode'].

  "The codec's fast path: a list or a @tup of values that are their own answers what the walk
   answers; anything else takes the walk."
  { #(1 'two' nil true 2.5). MessagePackMap withAll: { '@tup' -> #(1 'x') }.
    MessagePackMap withAll: { '@tup' -> { 1. #(2 3) } }. { 1. MessagePackMap withAll: { '@tup' -> #(2) } } } do: [:tree |
    | fast walk |
    fast := PBCodec fromWireValue: tree resolver: nil.
    walk := PBCodec fromWire: tree resolver: nil.
    c that: 'fromWireValue: of ' , tree printString , ' is the walk''s' isTrue: (fast class == walk class and: [fast = walk])].
  c that: 'a @tup with a second key is refused as before' signals: PBCorruptionError
    containing: 'a tagged value is a map with exactly one key' during: [
      PBCodec fromWireValue: (MessagePackMap withAll: { '@tup' -> #(1). 'x' -> 1 }) resolver: nil].
  bytes := MessagePack encode: (MessagePackMap withAll: { 't' -> 0. 't' -> 0. 'oid' -> (ByteArray new: 16) }).
  c that: 'a payload with a key twice is refused as before' signals: PBCorruptionError
    containing: 'the payload has the keys #(''t'' ''t'' ''oid''), not exactly t, oid and s'
    during: [PBAtomEnvelope decode: bytes expecting: 0].

  "A key path reads a shaped atom's field as its state does, and misses what it does not hold."
  c that: 'a key path reads a shaped atom''s field' is: ((PBKeySpec path: 'key') extract: node) equals: (node state at: 'key').
  c that: 'and misses an absent one' isTrue: ((PBKeySpec path: 'nothing') extract: node) == PBMissing default.
  "... without building the state, for a shaped node and for a record (whose step reads the name
   rule once)."
  rec := StateCountingNode key: 7 orderKey: (PBKeys orderKey: 7) value: v left: nil right: nil.
  StateCountingNode resetReads.
  c that: 'a key path step on a shaped node reads its field' is: ((PBKeySpec path: 'key') extract: rec) equals: 7.
  c that: 'and builds no state' is: StateCountingNode reads equals: 0.
  rec := StateCountingRecord withAll: { 'a' -> 1. 'n' -> nil }.
  StateCountingRecord resetReads.
  c that: 'a key path step on a record reads its field' is: ((PBKeySpec path: 'a') extract: rec) equals: 1.
  c that: 'a field holding nil reads nil' isTrue: ((PBKeySpec path: 'n') extract: rec) isNil.
  c that: 'an absent field is missing' isTrue: ((PBKeySpec path: 'b') extract: rec) == PBMissing default.
  c that: 'a name starting with _ is missing' isTrue: ((PBKeySpec path: '_a') extract: rec) == PBMissing default.
  c that: 'a reserved name is missing' isTrue: ((PBKeySpec path: 'oid') extract: rec) == PBMissing default.
  c that: 'and the record builds no state' is: StateCountingRecord reads equals: 0.

  "--- a save builds each state once and stubs each reference once ---"
  rec := SaveCountingNode key: 1 orderKey: (PBKeys orderKey: 1) value: v left: nil right: nil.
  rec := SaveCountingNode key: 2 orderKey: (PBKeys orderKey: 2) value: v left: rec right: nil.
  SaveCountingNode resetCounts.
  ptr := st save: rec.
  c that: 'a save into a cached storage builds each saved atom''s state once' is: SaveCountingNode reads equals: 2.
  c that: 'and makes one stub per reference it caches' is: SaveCountingNode stubs equals: 1.
  stub := SaveCountingNode unloadedAt: ptr storage: st.
  c that: 'the cached parent loads its child as a stub of the child''s record' is: stub left pointer equals: rec left pointer.
  c that: 'which reads the child''s key' is: stub left key equals: 1.
  c that: 'the cached state equals the saved one' is: stub state equals: rec state.
  rec := SaveCountingNode key: 3 orderKey: (PBKeys orderKey: 3) value: v left: nil right: nil.
  SaveCountingNode resetCounts.
  rec _saveInto: plain.
  c that: 'a save into a storage with no cache builds the state once' is: SaveCountingNode reads equals: 1.

  "--- the attribute name rule answers the same reasons (PBAtomEnvelope _nameProblem:) ---"
  c that: 'a valid name has no problem' isTrue: (PBAtomEnvelope _nameProblem: 'amount') isNil.
  c that: 'nor one that only starts as a reserved one' isTrue: ((#('oids' 'context_' 'atom') collect: [:n |
    PBAtomEnvelope _nameProblem: n]) allSatisfy: [:why | why isNil]).
  c that: 'oid is reserved' is: (PBAtomEnvelope _nameProblem: 'oid') equals: 'the attribute name ''oid'' is reserved'.
  c that: 'atom_pointer is reserved' is: (PBAtomEnvelope _nameProblem: 'atom_pointer')
    equals: 'the attribute name ''atom_pointer'' is reserved'.
  c that: 'context is reserved' is: (PBAtomEnvelope _nameProblem: 'context') equals: 'the attribute name ''context'' is reserved'.
  c that: 'a leading _ is refused' is: (PBAtomEnvelope _nameProblem: '_x') equals: 'the attribute name ''_x'' starts with _'.
  c that: 'the empty string is refused' is: (PBAtomEnvelope _nameProblem: '')
    equals: 'an attribute name is a non-empty string, not '''''.
  c that: 'nil is refused' is: (PBAtomEnvelope _nameProblem: nil) equals: 'an attribute name is a non-empty string, not nil'.
  c that: 'a number is refused' is: (PBAtomEnvelope _nameProblem: 3) equals: 'an attribute name is a non-empty string, not 3'.

  "--- the oid pool ---"
  raw := ByteArray withAll: ((1 to: 32) asArray collect: [:i | 255]).
  marked := ByteArray withAll: #(255 255 255 255 255 255 79 255 191 255 255 255 255 255 255 255
    255 255 255 255 255 255 79 255 191 255 255 255 255 255 255 255).
  c that: 'a batch is marked as UUID new marks an oid (all ones)' is: (_PBOidPool _mark: raw) equals: marked.
  raw := ByteArray new: 32.
  marked := ByteArray withAll: #(0 0 0 0 0 0 64 0 128 0 0 0 0 0 0 0 0 0 0 0 0 0 64 0 128 0 0 0 0 0 0 0).
  c that: 'a batch is marked as UUID new marks an oid (all zeros)' is: (_PBOidPool _mark: raw) equals: marked.
  drawn := (1 to: _PBOidPool batchSize * 3) asArray collect: [:i | _PBOidPool next].
  c that: 'every oid drawn is 16 bytes' isTrue: (drawn allSatisfy: [:o | (o isKindOf: ByteArray) and: [o size = 16]]).
  c that: 'of version 4 and variant 2r10' isTrue: (drawn allSatisfy: [:o |
    ((o at: 7) bitAnd: 16rF0) = 16r40 and: [((o at: 9) bitAnd: 16rC0) = 16r80]]).
  c that: 'all distinct, across three batches' is: (drawn collect: [:o | o hex]) asSet size equals: drawn size.
  f1 := Drawer new asActor draw: 300.
  f2 := Drawer new asActor draw: 300.
  all := f1 wait , f2 wait.
  c that: 'two drawing actors draw distinct oids' is: (all collect: [:o | o hex]) asSet size equals: 600.
] ensure: [
  plain isNil ifFalse: [plain close].
  st isNil ifFalse: [st close].
  base deleteAll].
c report displayNl.
