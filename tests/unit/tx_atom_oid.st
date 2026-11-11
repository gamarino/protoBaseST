"EXPECT: ok 18"
"An atom's oid (ProtoBase D21, core/atom.py _assign_oid; ruling R13): it is not a storage
 id. An atom that is not stored draws a version-4 UUID in memory on first need (oid, =,
 hash, an order key, a hash key), never by saving, and keeps it; a stored atom's oid is
 its record's. Atoms are = when they are one object or share an oid, and hash by it, as
 Atom.__eq__ and __hash__. So an unsaved atom is a map key and a lookup probe like any
 other, and keeps its identity once a record carries its oid (the writer is plan Task 15:
 here the record is written with the atom's oid, as that writer will). Two first readers
 that race agree on one oid: the race is forced through the _newOid seam, with the second
 reader on an actor, never by timing."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

PBObject subclass: #RacingObject.
RacingObject class >> typeName
  ^ 'tests.oid.RacingObject'.
"The first draw lets a second reader, on an actor, take the oid first; the first reader
 then finds the cell filled and answers the installed oid, not its own draw."
RacingObject >> _newOid
  | mine |
  mine := super _newOid.
  Draws swap: [:n | n + 1].
  Draws value = 1 ifTrue: [
    Mine value: mine ifCurrent: nil.
    Seen value: (OidReader new asActor oidOf: self) wait ifCurrent: nil].
  ^ mine.
Object subclass: #OidReader.
OidReader >> oidOf: anAtom
  ^ anAtom oid.

| c fresh other map key2 b ref space tx stub racer first base empty |
Smalltalk at: #Draws put: (Atom on: 0).
Smalltalk at: #Seen put: (Atom on: nil).
Smalltalk at: #Mine put: (Atom on: nil).
PBTypeRegistry register: RacingObject.
c := Check new.
empty := PBFrozenDict withAssociations: #().
fresh := PBObject _unsavedWithState: empty.
other := PBObject _unsavedWithState: empty.
c that: 'no oid before the first need' is: fresh knownOid equals: nil.
c that: 'a version-4 UUID' is: ((fresh oid at: 7) bitShift: -4) equals: 4.
c that: 'the oid is kept' is: fresh oid equals: fresh oid.
c that: 'two unsaved atoms differ' isTrue: fresh oid ~= other oid.
c that: '= by identity' is: fresh = fresh equals: true.
c that: 'not = another unsaved atom' is: fresh = other equals: false.
c that: 'hash is stable' is: fresh hash equals: fresh hash.
"In an in-memory collection (PBFrozenDict), as key and as probe."
map := PBFrozenDict withAssociations: { fresh -> 'one'. other -> 'two' }.
c that: 'found by itself' is: (map at: fresh) equals: 'one'.
c that: 'the other key' is: (map at: other) equals: 'two'.
c that: 'a third unsaved atom misses' is: (map at: (PBObject _unsavedWithState: empty) ifAbsent: ['absent']) equals: 'absent'.
key2 := PBTuple withAll: { fresh. 1 }.
c that: 'inside a tuple key' is: ((PBFrozenDict withAssociations: { key2 -> 'tuple' }) at: (PBTuple withAll: { fresh. 1 })) equals: 'tuple'.
"Once a record carries the oid, its stub is = to the unsaved atom and finds its key."
base := FileSystem temp / ('pbst-tx-atom-oid-' , Smalltalk pid printString).
base deleteAll.
b := SpaceBuilder segment: (ByteArray fromHex: '4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e').
ref := b add: 19 oidBytes: fresh oid state: #().
space := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'oid'
  root: (b spaceWithDatabase: 'db' roots: { 'saved' -> ref } mutables: #() oids: 10))).
tx := (space openDatabase: 'db') newTransaction.
stub := tx getRootObject: 'saved'.
c that: 'the stored atom has the same oid' is: stub oid equals: fresh oid.
c that: 'and is = to the unsaved one' is: stub = fresh equals: true.
c that: 'it finds the unsaved atom''s key' is: (map at: stub) equals: 'one'.
tx abort.
space close.
base deleteAll.
"Two first readers race: one oid wins, both answer it."
racer := RacingObject _unsavedWithState: empty.
first := racer oid.
c that: 'two draws were made' is: Draws value equals: 2.
c that: 'the reader on the actor answered the installed oid' is: Seen value equals: first.
c that: 'the first reader answered it too, not its own draw' isTrue: first ~= Mine value.
c that: 'the oid stays' is: racer oid equals: first.
c report displayNl.
