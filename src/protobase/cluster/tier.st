"-- cluster/tier.st: the shared tier, the cluster tier of a space every node shares --

proto_db cluster/persister.py at v2.0.0rc3 (PlainTier, _node_log, cluster_fields; persist: and
readPersisted at v2.0.0rc4, which keep the root's version outside its identity): what the
coordinator and the persister need from the storage of a space that every node of the cluster
shares, a PBFileStorage opened in cluster mode (PBFileStorage clusterPath:, CC20) on a shared
file system. Records live in the shared storage, so nothing is shipped or applied (DEPTH = 0);
the persisted root is the storage's own root (space.root).

  PBSharedTier  storage: aClusterStorage nodeId: anId opens the node's acceptor log
                (PBAcceptorLog, cluster/rootlog.st) at cluster/<logName>.roots inside the
                space directory; the log creates cluster/ and syncs the log file, cluster/ and
                the space directory (L10). A log already open (another tier of the node, in
                this process or another: a double start, Review Focus 3) is PBUserError naming
                cluster/<logName>.roots.lock; a log holding a kind-5 or kind-6 entry (written
                by a tiered node, which this port does not run) is PBNotSupportedError (CC15);
                a storage not in cluster mode is PBValidationError.
                logName: anId (CC21, proto_db _node_log): anId itself when it matches
                [A-Za-z0-9._-]{1,64}, else the lowercase hex of its UTF-8 bytes, so the file
                is the one proto_db names, always inside cluster/ ('..' is '...roots').
                The tier protocol of the coordinator shell (coordinator.st): storage,
                loadRoots, logAccepted: and logCommitted: (a PBLabeledRoot, unpacked for the
                log), logPromise: (a term), logRejoined, readPersisted, canRead:. Every write
                to the log comes from the one actor that owns it (the coordinator's acceptor):
                PBAcceptorLog is not serialized. For the persister and the commit round:
                flushLocal (the storage's segments synced), persist: (CC19), close.
                readPersisted answers the storage root as a PBLabeledRoot: the label and the
                cluster epoch from its SpaceRoot's cluster_term and cluster_epoch, or label 0
                and the storage epoch for a root written outside cluster mode (proto_db
                cluster_fields); nil for an empty space.
                persist: aLabeledRoot publishes its record as space.root and answers true, or
                false when the storage holds a newer root in the order of roots, or that root at
                a version at or above aLabeledRoot's (PBRootOrder, rc4's shape: the persisted
                root never goes backwards; the version is outside the order), or #busy when another
                holder has the root lock: tryLockRoot, readRoot, the order check, then
                replaceRoot: with the storage epoch plus one (the compare-and-swap), the lock
                released whatever happens. It never waits; the persister reschedules a busy
                attempt (cluster/persister.st). The persister never calls it itself: it runs on
                the space's round runner, the one actor that writes the node's storage (Task 21
                review I1, PBRoundRunner >> persist:).

Every value here is immutable; a PBSharedTier holds its storage and its open log."

Import from: 'protobase/errors'.
Import from: 'protobase/framing'.
Import from: 'protobase/registry'.
Import from: 'protobase/store'.
Import from: 'protobase/roots'.
Import from: 'protobase/cluster/rootlog'.

"=== PBSharedTier ============================================================"

Object subclass: #PBSharedTier instanceVariableNames: 'storage nodeId log'.

"The acceptor log class a tier opens. A seam: tests observe its directory syncs."
PBSharedTier class >> logClass
  ^ PBAcceptorLog.

"The characters of a node id that is its own log name (proto_db _node_log)."
PBSharedTier class >> _safeCharacters
  ^ 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-'.

"The name of the acceptor log of the node anId, without its '.roots' suffix (CC21): anId when it
 matches [A-Za-z0-9._-]{1,64}, else the lowercase hex of its UTF-8 bytes."
PBSharedTier class >> logName: anId
  | safe |
  (anId isString and: [anId isSymbol not]) ifFalse: [
    ^ PBValidationError signal: 'PBSharedTier: a node id is a String, not ' , anId printString].
  safe := self _safeCharacters.
  ((anId size between: 1 and: 64) and: [anId allSatisfy: [:ch | safe includes: ch]]) ifTrue: [^ anId copy].
  ^ anId utf8Encoded hex asLowercase.

"The tier of the node anId over aClusterStorage, a PBFileStorage in cluster mode (module comment)."
PBSharedTier class >> storage: aClusterStorage nodeId: anId
  | name opened ok roots |
  ((aClusterStorage isKindOf: PBFileStorage) and: [aClusterStorage isClusterMode]) ifFalse: [
    ^ PBValidationError signal: 'The storage of a cluster node is a PBFileStorage opened with clusterPath:, not '
      , aClusterStorage printString].
  name := self logName: anId.
  opened := self logClass path: aClusterStorage directory / PBFileStorage clusterDirectoryName / (name , '.roots').
  ok := false.
  [roots := opened load.
   roots dataEntryCount > 0 ifTrue: [
     ^ PBNotSupportedError signal: 'PBSharedTier: the acceptor log ' , opened path pathString , ' holds '
       , roots dataEntryCount printString , ' entries of kind 5 or 6, written by a node of a tiered storage, which protoBaseST does not run'].
   ok := true] ensure: [ok ifFalse: [opened close]].
  ^ self basicNew _setStorage: aClusterStorage nodeId: anId log: opened.

PBSharedTier >> _setStorage: aStorage nodeId: anId log: aLog
  "Runs once, on a fresh instance."
  storage isNil ifFalse: [^ PBUserError signal: 'PBSharedTier is initialised once'].
  storage := aStorage.
  nodeId := anId.
  log := aLog.
  ^ self.

"The shared storage (the coordinator compares tiers by it: proto_db _attach_locked)."
PBSharedTier >> storage
  ^ storage.

PBSharedTier >> nodeId
  ^ nodeId.

"The real path of the node's acceptor log, a FileReference."
PBSharedTier >> logPath
  ^ log path.

"--- the acceptor log ---"

"Logs aLabeledRoot as accepted (synced before this answers)."
PBSharedTier >> logAccepted: aLabeledRoot
  ^ log append: #accepted label: aLabeledRoot label root: aLabeledRoot record.

"Logs aLabeledRoot as known committed (durable with the next synced entry, R67)."
PBSharedTier >> logCommitted: aLabeledRoot
  ^ log append: #committed label: aLabeledRoot label root: aLabeledRoot record.

"Makes the promise of aTerm durable before it is sent."
PBSharedTier >> logPromise: aTerm
  ^ log promise: aTerm.

"Appends the rejoined marker (synced)."
PBSharedTier >> logRejoined
  ^ log markRejoined.

"What the node's acceptor log holds: a PBLoggedRoots."
PBSharedTier >> loadRoots
  ^ log load.

"--- the shared storage ---"

"Makes this node's records durable in the shared storage (proto_db flush_local)."
PBSharedTier >> flushLocal
  ^ storage flushSegment.

"The storage root as a PBLabeledRoot (module comment), nil for an empty space."
PBSharedTier >> readPersisted
  | record |
  record := storage readRoot.
  record isNil ifTrue: [^ nil].
  ^ self _labeled: record.

"The PBLabeledRoot of the storage root aRootRecord (proto_db cluster_fields and read_persisted):
 the cluster term and epoch of its SpaceRoot, or label 0 and the storage epoch outside cluster
 mode; the record keeps the version aRootRecord was read at (rc4 read_persisted, record.version)."
PBSharedTier >> _labeled: aRootRecord
  | space term epoch |
  space := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: aRootRecord pointer storage: storage.
  epoch := space clusterEpoch.
  epoch isNil ifTrue: [
    ^ PBLabeledRoot label: 0 record: (PBRootRecord _version: aRootRecord version segment: aRootRecord segment
      offset: aRootRecord offset epoch: aRootRecord epoch)].
  term := space clusterTerm.
  ^ PBLabeledRoot label: (term isNil ifTrue: [0] ifFalse: [term])
    record: (PBRootRecord _version: aRootRecord version segment: aRootRecord segment offset: aRootRecord offset epoch: epoch).

"Publishes the record of aLabeledRoot as the storage root (CC19, proto_db PlainTier.persist):
 true once published; false when the storage holds a newer root in the order of roots, or that
 root at a version at or above its own (_holds:over:, rc4's shape); #busy when another holder
 has the root lock. The lock is released whatever happens.
 A protoBaseST addition: the label and epoch of aLabeledRoot must be the cluster_term and
 cluster_epoch its SpaceRoot carries (PBValidationError, nothing written), so the root persisted
 is ordered as readPersisted later reports it."
PBSharedTier >> persist: aLabeledRoot
  | current |
  ((aLabeledRoot isKindOf: PBLabeledRoot) and: [aLabeledRoot record notNil]) ifFalse: [
    ^ PBValidationError signal: 'PBSharedTier persist: a PBLabeledRoot of a record was expected, not ' , aLabeledRoot printString].
  storage tryLockRoot ifFalse: [^ #busy].
  ^ [self _checkFieldsOf: aLabeledRoot.
     current := storage readRoot.
     (current notNil and: [self _holds: (self _labeled: current) over: aLabeledRoot])
       ifTrue: [false]
       ifFalse: [
         storage replaceRoot: (PBRootRecord segment: aLabeledRoot record segment offset: aLabeledRoot record offset
           epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1])).
         true]]
    ensure: [storage unlockRoot].

"Whether the persisted root aCurrent (a PBLabeledRoot read from space.root) makes the persist of
 aLabeledRoot a no-op (CC19 in rc4's shape, proto_db PlainTier.persist at v2.0.0rc4): it orders
 after aLabeledRoot, or it is the same root at a version at or above aLabeledRoot's. The version
 is outside the order of roots (rc4 RootRecord.version, compare=False): the same root held at a
 lower version is published again, at the version replaceRoot: writes (4, the only one this port
 writes; rc4 hands publish_root the committer's version, a no-op at format 4). At format 4 every
 root is version 4 on both sides, so the second case is the old '>= 0' (rc4 delta C4)."
PBSharedTier >> _holds: aCurrent over: aLabeledRoot
  | order |
  order := PBRootOrder compare: aCurrent with: aLabeledRoot.
  order > 0 ifTrue: [^ true].
  ^ order = 0 and: [aCurrent record version >= aLabeledRoot record version].

"Refuses (PBValidationError) aLabeledRoot when its SpaceRoot carries cluster fields other than
 its label and epoch. A SpaceRoot without cluster_epoch is left to replaceRoot:, which refuses it
 in cluster mode (no cluster_term)."
PBSharedTier >> _checkFieldsOf: aLabeledRoot
  | space term epoch |
  space := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: aLabeledRoot record pointer storage: storage.
  epoch := space clusterEpoch.
  epoch isNil ifTrue: [^ self].
  term := space clusterTerm.
  term isNil ifTrue: [term := 0].
  (term = aLabeledRoot label and: [epoch = aLabeledRoot epoch]) ifTrue: [^ self].
  ^ PBValidationError signal: 'PBSharedTier persist: the root is labelled ' , aLabeledRoot label printString
    , ' with epoch ' , aLabeledRoot epoch printString , ', but its SpaceRoot at ' , aLabeledRoot record pointer printString
    , ' carries cluster_term ' , term printString , ' and cluster_epoch ' , epoch printString.

"Whether the shared storage can read the SpaceRoot of aLabeledRoot (the rejoin's probe of its
 adopted root, PBProbeRoot): true for the empty space; false when its record is missing, damaged or not a
 SpaceRoot (a PBDBError) or the file system fails. A closed storage is PBClosedError: the
 probe has no tier to ask."
PBSharedTier >> canRead: aLabeledRoot
  aLabeledRoot record isNil ifTrue: [^ true].
  ^ [storage loadAt: aLabeledRoot record pointer expecting: PBFileStorage spaceRootTag. true]
    on: Error do: [:e |
      ((e isKindOf: PBClosedError) not and: [(e isKindOf: PBDBError) or: [e isKindOf: FileSystemError]])
        ifTrue: [e return: false]
        ifFalse: [e pass]].

"Closes the node's acceptor log and releases its lock (the space is closing). Idempotent. The
 storage is the space's: it is not closed here."
PBSharedTier >> close
  log close.

PBSharedTier >> printOn: aStream
  aStream nextPutAll: 'PBSharedTier('; print: nodeId; nextPutAll: ', '; print: storage; nextPut: $).
