"-- roots.st: the space and database roots of format 4, read side --

Format spec v2.0.0rc1, 'Space and database roots'; ProtoBase
proto_db/transactions.py (SpaceRoot, DatabaseRoot) at the tag.

  PBSpaceRoot      proto_db.transactions.SpaceRoot, the atom space.root points
                   to: databases (a PBDictionary from database name to its
                   current PBDatabaseRoot); clusterTerm, clusterEpoch and
                   clusterPrevious are optional (absent: nil), written only under
                   a cluster lease (databases:term:epoch:previous:)
  PBDatabaseRoot   proto_db.transactions.DatabaseRoot, one version of a database:
                   objects and mutables (PBDictionary), version, committedAt (an
                   aware UTC DateTime), previous (the previous version, nil for
                   version 0) and origin (16 bytes, the database's identity;
                   optional: absent means nil)

A DatabaseRoot without mutables was written before D35 and cannot be opened:
its load is PBCorruptionError (a required field), as in ProtoBase. A nil
databases, objects or mutables is PBCorruptionError naming the field.
previous answers a new unloaded stub on each call (D53): walking the history
never leaves older versions loaded behind a root."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/avl'.
Import from: 'protobase/collections'.
Import from: 'calendar'.

PBAtom subclass: #PBSpaceRoot.

PBSpaceRoot class >> typeName
  ^ 'proto_db.transactions.SpaceRoot'.

PBSpaceRoot class >> requiredFields
  ^ #('databases').

PBSpaceRoot class >> persistedFields
  ^ #('databases').

"The PBDictionary from database name to PBDatabaseRoot."
PBSpaceRoot >> databases
  ^ _PBTree required: (self stateAt: 'databases') kind: PBDictionary field: 'databases' in: self.

"A new, unsaved space root over aDictionary (database name -> PBDatabaseRoot),
 as ProtoBase's SpaceRoot(databases=...) outside a cluster: no cluster field."
PBSpaceRoot class >> databases: aDictionary
  (aDictionary isKindOf: PBDictionary) ifFalse: [
    ^ PBValidationError signal: 'PBSpaceRoot databases: a PBDictionary was expected, not ' , aDictionary printString].
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> aDictionary }).

"A new, unsaved space root committed under a cluster lease, as ProtoBase's
 SpaceRoot(databases=..., cluster=stamp, previous=...): the state keys in the
 order databases, cluster_term, cluster_epoch, cluster_previous (the order the
 cluster segment vector shows). anInteger term and epoch are Integers >= 0;
 aSpaceRootOrNil is the space root it was built on, or nil (written as nil, as
 ProtoBase writes a None history link)."
PBSpaceRoot class >> databases: aDictionary term: aTerm epoch: anEpoch previous: aSpaceRootOrNil
  (aDictionary isKindOf: PBDictionary) ifFalse: [
    ^ PBValidationError signal: 'PBSpaceRoot databases: a PBDictionary was expected, not ' , aDictionary printString].
  ((aTerm isInteger and: [aTerm >= 0]) and: [anEpoch isInteger and: [anEpoch >= 0]]) ifFalse: [
    ^ PBValidationError signal: 'PBSpaceRoot: the cluster term and epoch are Integers >= 0, not '
      , { aTerm. anEpoch } printString].
  (aSpaceRootOrNil isNil or: [aSpaceRootOrNil isKindOf: PBSpaceRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBSpaceRoot: previous is a PBSpaceRoot or nil, not ' , aSpaceRootOrNil printString].
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: {
    'databases' -> aDictionary. 'cluster_term' -> aTerm. 'cluster_epoch' -> anEpoch.
    'cluster_previous' -> aSpaceRootOrNil }).

"The term of the cluster lease the root was committed under, or nil."
PBSpaceRoot >> clusterTerm
  ^ self stateAt: 'cluster_term'.

PBSpaceRoot >> clusterEpoch
  ^ self stateAt: 'cluster_epoch'.

PBSpaceRoot >> clusterPrevious
  ^ self stateAt: 'cluster_previous'.

PBAtom subclass: #PBDatabaseRoot.

PBDatabaseRoot class >> typeName
  ^ 'proto_db.transactions.DatabaseRoot'.

PBDatabaseRoot class >> requiredFields
  ^ #('objects' 'mutables' 'version' 'committed_at' 'previous').

PBDatabaseRoot class >> persistedFields
  ^ #('objects' 'mutables' 'version' 'committed_at' 'origin' 'previous').

"A new, unsaved database version (ProtoBase DatabaseRoot(...)): the fields in
 the order ProtoBase writes them (persistedFields); origin nil (a database
 created before D56) is left out, as ProtoBase leaves it out; previous nil for
 version 0."
PBDatabaseRoot class >> objects: anObjects mutables: aMutables version: anInteger committedAt: aDateTime
    origin: anOrigin previous: aPrevious
  | fields |
  ((anObjects isKindOf: PBDictionary) and: [aMutables isKindOf: PBDictionary]) ifFalse: [
    ^ PBValidationError signal: 'PBDatabaseRoot: objects and mutables are PBDictionaries, not '
      , { anObjects. aMutables } printString].
  (aPrevious isNil or: [aPrevious isKindOf: PBDatabaseRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBDatabaseRoot: previous is a PBDatabaseRoot or nil, not ' , aPrevious printString].
  fields := OrderedCollection new.
  fields addLast: 'objects' -> anObjects; addLast: 'mutables' -> aMutables; addLast: 'version' -> anInteger;
    addLast: 'committed_at' -> aDateTime.
  anOrigin isNil ifFalse: [fields addLast: 'origin' -> anOrigin].
  fields addLast: 'previous' -> aPrevious.
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: fields asArray).

"The committed_at of a version that follows one committed at aDateTime: now,
 or aDateTime when the clock reads earlier, so history times never go back
 (ProtoBase max(_utc_now(), previous committed_at)); always in UTC (ZoneOffset
 utc). A previous committed_at that is not an aware DateTime is
 PBCorruptionError, where ProtoBase's max would fail on it."
PBDatabaseRoot class >> committedAfter: aDateTime
  | now |
  ((aDateTime isKindOf: DateTime) and: [aDateTime isNaive not]) ifFalse: [
    ^ PBCorruptionError signal: 'PBDatabaseRoot: committed_at is not an aware datetime: ' , aDateTime printString].
  now := DateTime nowUTC.
  aDateTime utcOrdinalMicroseconds <= now utcOrdinalMicroseconds ifTrue: [^ now].
  ^ DateTime utcOrdinalMicroseconds: aDateTime utcOrdinalMicroseconds zone: ZoneOffset utc.

"The PBDictionary from root name to the root's value."
PBDatabaseRoot >> objects
  ^ _PBTree required: (self stateAt: 'objects') kind: PBDictionary field: 'objects' in: self.

"The PBDictionary from mutable cell name to the cell's value (D35)."
PBDatabaseRoot >> mutables
  ^ _PBTree required: (self stateAt: 'mutables') kind: PBDictionary field: 'mutables' in: self.

PBDatabaseRoot >> version
  ^ _PBTree integer: (self stateAt: 'version') field: 'version' of: self.

PBDatabaseRoot >> committedAt
  ^ self stateAt: 'committed_at'.

"The previous version's PBDatabaseRoot, nil for version 0: a new unloaded
 stub on each call, so a root never keeps its predecessors loaded (ProtoBase
 D53 reloads previous on each read). The stub in this root's state is never
 loaded."
PBDatabaseRoot >> previous
  | stub |
  stub := _PBTree node: (self stateAt: 'previous') kind: PBDatabaseRoot in: self.
  ^ stub isNil ifTrue: [nil] ifFalse: [stub unloadedCopy].

"The database's 16-byte identity, or nil for a database created before D56."
PBDatabaseRoot >> origin
  ^ self stateAt: 'origin'.

{ PBSpaceRoot. PBDatabaseRoot } do: [:each | PBTypeRegistry register: each].
