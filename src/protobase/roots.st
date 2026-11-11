"-- roots.st: the space and database roots of format 4, read side --

Format spec v2.0.0rc1, 'Space and database roots'; ProtoBase
proto_db/transactions.py (SpaceRoot, DatabaseRoot) at the tag.

  PBSpaceRoot      proto_db.transactions.SpaceRoot, the atom space.root points
                   to: databases (a PBDictionary from database name to its
                   current PBDatabaseRoot); clusterTerm, clusterEpoch and
                   clusterPrevious are optional (absent: nil), written only under
                   a cluster lease
  PBDatabaseRoot   proto_db.transactions.DatabaseRoot, one version of a database:
                   objects and mutables (PBDictionary), version, committedAt (an
                   aware UTC DateTime), previous (the previous version, nil for
                   version 0) and origin (16 bytes, the database's identity;
                   optional: absent means nil)

A DatabaseRoot without mutables was written before D35 and cannot be opened:
its load is PBCorruptionError (a required field), as in ProtoBase."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/avl'.
Import from: 'protobase/collections'.

PBAtom subclass: #PBSpaceRoot.

PBSpaceRoot class >> typeName
  ^ 'proto_db.transactions.SpaceRoot'.

PBSpaceRoot class >> requiredFields
  ^ #('databases').

PBSpaceRoot class >> persistedFields
  ^ #('databases').

"The PBDictionary from database name to PBDatabaseRoot."
PBSpaceRoot >> databases
  ^ _PBTree node: (self stateAt: 'databases') kind: PBDictionary in: self.

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

"The PBDictionary from root name to the root's value."
PBDatabaseRoot >> objects
  ^ _PBTree node: (self stateAt: 'objects') kind: PBDictionary in: self.

"The PBDictionary from mutable cell name to the cell's value (D35)."
PBDatabaseRoot >> mutables
  ^ _PBTree node: (self stateAt: 'mutables') kind: PBDictionary in: self.

PBDatabaseRoot >> version
  ^ _PBTree integer: (self stateAt: 'version') field: 'version' of: self.

PBDatabaseRoot >> committedAt
  ^ self stateAt: 'committed_at'.

"The previous version's PBDatabaseRoot, nil for version 0."
PBDatabaseRoot >> previous
  ^ _PBTree node: (self stateAt: 'previous') kind: PBDatabaseRoot in: self.

"The database's 16-byte identity, or nil for a database created before D56."
PBDatabaseRoot >> origin
  ^ self stateAt: 'origin'.

{ PBSpaceRoot. PBDatabaseRoot } do: [:each | PBTypeRegistry register: each].
