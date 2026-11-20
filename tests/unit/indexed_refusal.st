"EXPECT: ok 13"
"What an indexed collection refuses (design spec 3.3 and 7.4; indexed queries, plan Task 4a). Run on a copy of the database vector: its root 'people' is a Dictionary with the
 key-group indexes by_age and by_city, 'hnsw' a List with the vector index hnsw, 'tags' a List
 without indexes.

 Key-group indexes are maintained: setAt:value: and removeAt: on 'people' answer versions whose
 indexes agree with their elements. A vector index, or an index of a kind protoBaseST does not
 know (an opaque atom, written here with SpaceBuilder), keeps its collection read only: every
 change, addIndex: and removeIndex: included, is PBNotSupportedError naming it; extend: of
 nothing answers the receiver, as proto_db returns before it touches the indexes. Merges onto
 indexed currents are not refused (plan Task 4b, tests/unit/idx_merge.st), except onto one
 holding a vector index (idx_merge.st check 8) or an index of an unknown kind (here, on a
 Dictionary written with the same opaque index)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c dir space snap people hnsw tags changed removed b opaque setRef listRef st custom |
c := Check new.
dir := 'out/indexed_refusal' asFileReference / ('run-' , Smalltalk pid printString , '-'
  , Time microsecondClockValue printString).
(dir / 'database') ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: dir / 'database' / f basename].
space := PBObjectSpace storage: (PBFileStorage path: (dir / 'database') pathString).
snap := (space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first.
people := snap getRootObject: 'people'.
hnsw := snap getRootObject: 'hnsw'.
tags := snap getRootObject: 'tags'.
c that: 'people has key-group indexes' is: people indexNames equals: #('by_age' 'by_city').

"Key-group indexes are written."
changed := people setAt: 'zed' value: 1.
removed := changed removeAt: 'zed'.
c that: 'setAt:value: on the indexed root maintains its indexes'
  is: { (changed getIndex: 'by_age') count. (changed getIndex: 'by_city') count. changed validate == changed }
  equals: { people count + 1. people count + 1. true }.
c that: 'removeAt: too' is: { (removed getIndex: 'by_age') count. removed validate == removed } equals: { people count. true }.
c that: 'the receiver keeps its indexes' is: (people getIndex: 'by_age') count equals: people count.

"A vector index: read only."
c that: 'an indexed List: appendLast:' signals: PBNotSupportedError containing: 'hnsw' during: [hnsw appendLast: 1].
c that: 'an indexed List: sliceFrom:to:' signals: PBNotSupportedError containing: 'hnsw' during: [hnsw head: 1].
c that: 'addIndex: and removeIndex: on it' is: {
    [hnsw addIndex: (PBEqualityIndex name: 'by_x' path: 'x'). nil] on: PBNotSupportedError do: [:e | e return: #refused].
    [hnsw removeIndex: 'hnsw'. nil] on: PBNotSupportedError do: [:e | e return: #refused] }
  equals: #(#refused #refused).
c that: 'extend: nothing on an indexed list answers it, as proto_db' isTrue: (hnsw extend: #()) == hnsw.
c that: 'reads still work' is: people count equals: (people keys size).

"An index of a kind protoBaseST does not know: an opaque atom in the index set."
b := SpaceBuilder segment: (ByteArray fromHex: '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4b').
opaque := b add: 'acme.indexing.CustomIndex' oid: 1 state: { 'name' -> 'custom' }.
setRef := b add: 3 oid: 2 state: { 'root' -> (b add: 0 oid: 3 state: { 'key' -> 'custom'. 'value' -> opaque.
  'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }) }.
listRef := b add: 5 oid: 4 state: { 'root' -> nil. 'count' -> 0. 'indexes' -> setRef }.
b writeTo: dir / 'opaque' root: listRef.
st := PBFileStorage path: (dir / 'opaque') pathString.
custom := PBTypeRegistry unloadedAtomFor: listRef tag at: listRef pointer storage: st.
c that: 'an unknown index kind: appendLast:' signals: PBNotSupportedError containing: 'acme.indexing.CustomIndex'
  during: [custom appendLast: 1].
st close.
"The same opaque index on a Dictionary: a merge onto it is refused, naming it (plan Task 4b)."
b := SpaceBuilder segment: (ByteArray fromHex: '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4c').
opaque := b add: 'acme.indexing.CustomIndex' oid: 1 state: { 'name' -> 'custom' }.
setRef := b add: 3 oid: 2 state: { 'root' -> (b add: 0 oid: 3 state: { 'key' -> 'custom'. 'value' -> opaque.
  'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }) }.
listRef := b add: 6 oid: 4 state: { 'root' -> nil. 'count' -> 0. 'indexes' -> setRef }.
b writeTo: dir / 'opaque-dict' root: listRef.
st := PBFileStorage path: (dir / 'opaque-dict') pathString.
custom := PBTypeRegistry unloadedAtomFor: listRef tag at: listRef pointer storage: st.
c that: 'an unknown index kind: a merge onto it (rebaseOnto:)' signals: PBNotSupportedError containing: 'acme.indexing.CustomIndex'
  during: [(PBDictionary new setAt: 1 value: 2) rebaseOnto: custom].
st close.

c that: 'a List without indexes is written' is: (tags appendLast: 'new') count equals: tags count + 1.
c that: 'and keeps its index set' isTrue: ((tags appendLast: 'new') stateAt: 'indexes') == (tags stateAt: 'indexes').

space close.
c report displayNl.
