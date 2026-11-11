"EXPECT: ok 28"
"Atom map keys read through a transaction and the storage's real resolver (plan Task 13,
 keeping Task 10 fix round 1): a map whose keys are references is decoded with the
 storage's resolver, and its stub keys are identified by their oids (PBKeys _keyId:mode:
 loads them), so a stub of another record of the same oid finds the key, and a state
 holding a map with references to two records of one oid is PBCorruptionError. The space
 holds two versions of one atom (two records, one oid).

 An atom that is not stored draws its oid on first need (ProtoBase D21, ruling R13), so a
 lookup by it, or by a tuple holding it, misses in a PBFrozenDict and in every collection;
 the tuple's other items must still be keys. A first load inside an application's
 `on: Exception do:` answers the data (review C1).

 Review note N3: a record whose map key refers back to the record itself, directly or
 through another record, can only come from damaged data or a writer that breaks the
 save-dependents-first invariant. ProtoBase recurses until Python's RecursionError;
 protoBaseST signals PBCorruptionError naming the pointer, and the transaction stays
 usable."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base b seg a1 a2 bee good twice other otherTx selfRef sizeA offA cycleB cycleA spaceRoot space tx m fresh stub2 db vectors people |
c := Check new.
base := FileSystem temp / ('pbst-tx-atom-map-keys-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.

seg := ByteArray fromHex: '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a'.
b := SpaceBuilder segment: seg.
"Two versions of one atom: two records of the oid 7."
a1 := b add: 19 oid: 7 state: { 'v' -> 1 }.
a2 := b add: 19 oid: 7 state: { 'v' -> 2 }.
bee := b add: 19 oid: 8 state: { 'v' -> 3 }.
good := b add: 19 oid: 9 state: { 'm' -> (PBFrozenDict withAssociations: { a1 -> 'seven'. bee -> 'eight' }) }.
twice := b add: 19 oid: 10 state: { 'm' -> (PBFrozenDict withAssociations: { a1 -> 1. a2 -> 2 }) }.
"A record whose map key is the record itself."
selfRef := b nextRef: 19.
selfRef := b add: 19 oid: 11 state: { 'm' -> (PBFrozenDict withAssociations: { selfRef -> 1 }) }.
"Two records whose map keys refer to each other: B is written first, keyed by A, the
 record right after it."
sizeA := b sizeOf: 19 oid: 12 state: { 'm' -> (PBFrozenDict withAssociations: { (b refAt: 300 tag: 19) -> 1 }) }.
offA := b nextOffset + sizeA.
cycleB := b add: 19 oid: 13 state: { 'm' -> (PBFrozenDict withAssociations: { (b refAt: offA tag: 19) -> 1 }) }.
c that: 'A is the next record' is: b nextOffset equals: offA.
cycleA := b add: 19 oid: 12 state: { 'm' -> (PBFrozenDict withAssociations: { cycleB -> 1 }) }.
c that: 'A sits where B refers' is: cycleA pointer offset equals: offA.
spaceRoot := b spaceWithDatabase: 'keys'
  roots: { 'good' -> good. 'twice' -> twice. 'self' -> selfRef. 'cycle' -> cycleA. 'a2' -> a2 }
  mutables: #() oids: 100.
space := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'keys' root: spaceRoot)).
tx := (space openDatabase: 'keys') newTransaction.

"Stub keys by oid, through the storage's resolver."
m := (tx getRootObject: 'good') at: 'm'.
c that: 'the map holds two keys' is: m size equals: 2.
c that: 'a key is a stub of the storage' is: m keys first class equals: PBObject.
c that: 'found by a stub of its own record' is: (m at: m keys first) equals: 'seven'.
stub2 := tx getRootObject: 'a2'.
c that: 'found by a stub of another record of the same oid' is: (m at: stub2 ifAbsent: ['absent']) equals: 'seven'.
c that: 'two records of one oid in one map' signals: PBCorruptionError during: [(tx getRootObject: 'twice') at: 'm'].

"An atom that is not stored draws its oid on first need (ProtoBase D21, ruling R13): a
 lookup by it misses, since no stored key has that fresh oid."
fresh := PBObject _unsavedWithState: (PBFrozenDict withAssociations: #()).
c that: 'at:ifAbsent: by an unsaved atom' is: (m at: fresh ifAbsent: ['absent']) equals: 'absent'.
c that: 'includesKey: by an unsaved atom' is: (m includesKey: fresh) equals: false.
c that: 'a tuple holding an unsaved atom' is: (m includesKey: (PBTuple withAll: { 1. fresh })) equals: false.
c that: 'the unsaved atom has drawn its oid' is: fresh knownOid size equals: 16.

"A first read inside an application's catch-all handler answers the data: loading
 signals nothing a handler could catch (review C1)."
other := PBObjectSpace storage: (PBFileStorage path: base / 'keys').
otherTx := (other openDatabase: 'keys') newTransaction.
c that: 'a first load inside on: Exception do:' is: ([((otherTx getRootObject: 'good') at: 'm') size]
  on: Exception do: [:e | 'caught ' , e class name]) equals: 2.
c that: 'whose stub keys are found' is: (((otherTx getRootObject: 'good') at: 'm') at: ((otherTx getRootObject: 'good') at: 'm') keys first) equals: 'seven'.
c that: 'N3 still refuses inside on: Exception do:' is: ([(otherTx getRootObject: 'self') at: 'm']
  on: Exception do: [:e | e class name]) equals: 'PBCorruptionError'.
otherTx abort.
other close.

"N3: a record that needs itself to be decoded."
c that: 'a map key that is its own record' signals: PBCorruptionError containing: 'save-dependents-first' during: [
  (tx getRootObject: 'self') at: 'm'].
c that: 'and again (nothing was cached)' signals: PBCorruptionError containing: 'refers back' during: [
  (tx getRootObject: 'self') at: 'm'].
c that: 'two records keyed by each other' signals: PBCorruptionError containing: 'refers back' during: [
  (tx getRootObject: 'cycle') at: 'm'].
c that: 'the transaction is still active' is: tx isActive equals: true.
c that: 'and still reads' is: (((tx getRootObject: 'good') at: 'm') at: stub2) equals: 'seven'.
tx abort.
space close.

"An unsaved atom as a lookup probe in every collection (ruling R13, which replaced
 review note N1), on a copy of the database vector: its oid is drawn, so it misses."
(base / 'database') ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: base / 'database' / f basename].
space := PBObjectSpace storage: (PBFileStorage path: base / 'database').
db := space openDatabase: 'db'.
tx := db newTransaction.
people := tx getRootObject: 'people'.
c that: 'PBDictionary getAt:' is: (people getAt: fresh) equals: nil.
c that: 'PBDictionary has:' is: (people has: fresh) equals: false.
c that: 'PBDictionary getAt: a tuple holding it' is: (people getAt: (PBTuple withAll: { fresh. 'ann' })) equals: nil.
c that: 'a tuple holding a list as well' signals: PBValidationError during: [
  people getAt: (PBTuple withAll: { fresh. #(1) })].
c that: 'PBHashDictionary getAt:' is: ((tx getRootObject: 'hash') getAt: fresh default: 'none') equals: 'none'.
c that: 'PBSet has:' is: ((tx getRootObject: 'set') has: fresh) equals: false.
c that: 'PBCountedSet countOf:' is: ((tx getRootObject: 'bag') countOf: fresh) equals: 0.
c that: 'PBRepeatedKeysDictionary has:' is: ((tx getRootObject: 'multi') has: fresh) equals: false.
c that: 'PBRepeatedKeysDictionary getAt:' is: ((tx getRootObject: 'multi') getAt: fresh) count equals: 0.
tx abort.
space close.
base deleteAll.
c report displayNl.
