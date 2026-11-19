"EXPECT: ok 16"
"What an indexed collection refuses (design spec 3.3 and 7.4; indexed queries, plan Task 4a and
 plan call IP17). Run on a copy of the database vector: its root 'people' is a Dictionary with the
 key-group indexes by_age and by_city, 'hnsw' a List with the vector index hnsw, 'tags' a List
 without indexes.

 Key-group indexes are maintained: setAt:value: and removeAt: on 'people' answer versions whose
 indexes agree with their elements. A vector index, or an index of a kind protoBaseST does not
 know (an opaque atom, written here with SpaceBuilder), keeps its collection read only: every
 change, addIndex: and removeIndex: included, is PBNotSupportedError naming it; extend: of
 nothing answers the receiver, as proto_db returns before it touches the indexes.

 The interim refusal (IP17, until Task 4b logs the index operations): a merge whose receiver or
 current has an index, rebaseOnto: and a PBCountedSet transform onto an indexed current, is
 PBNotSupportedError; addIndex: and removeIndex: answer versions that are not mergeable, and so
 is everything derived from them."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c dir space snap people hnsw tags changed removed b opaque setRef listRef st custom city plain bag
  indexedBag |
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

c that: 'a List without indexes is written' is: (tags appendLast: 'new') count equals: tags count + 1.
c that: 'and keeps its index set' isTrue: ((tags appendLast: 'new') stateAt: 'indexes') == (tags stateAt: 'indexes').

"The interim merge refusal (IP17)."
city := PBEqualityIndex name: 'by_city' path: 'city'.
plain := PBDictionary new setAt: 'zed' value: 1.
c that: 'rebaseOnto: an indexed current' signals: PBNotSupportedError containing: 'Task 4b'
  during: [plain rebaseOnto: people].
c that: 'rebaseOnto: of an indexed receiver onto a plain current, and of a receiver whose index was removed onto an indexed current' is: {
    [(PBDictionary new addIndex: city) rebaseOnto: PBDictionary new. nil] on: PBNotSupportedError do: [:e | e return: #refused].
    [((PBDictionary new addIndex: city) removeIndex: 'by_city') rebaseOnto: people. nil]
      on: PBNotSupportedError do: [:e | e return: #refused] }
  equals: #(#refused #refused).
bag := PBCountedSet new add: 'x'.
indexedBag := PBCountedSet new addIndex: (PBEqualityIndex name: 'e' keySpec: PBKeySpec element).
c that: 'a PBCountedSet transform onto an indexed current' is: {
    [bag rebaseOnto: indexedBag. nil] on: PBNotSupportedError do: [:e | e return: #refused].
    [indexedBag _transform: 'x' removes: 0 adds: 1. nil] on: PBNotSupportedError do: [:e | e return: #refused] }
  equals: #(#refused #refused).
c that: 'addIndex: and removeIndex: answer versions that are not mergeable' is: {
    PBDictionary new isMergeable. (PBDictionary new addIndex: city) isMergeable.
    ((PBDictionary new addIndex: city) removeIndex: 'by_city') isMergeable.
    (((PBDictionary new addIndex: city) removeIndex: 'by_city') setAt: 1 value: 2) isMergeable }
  equals: #(true false false false).
space close.
c report displayNl.
