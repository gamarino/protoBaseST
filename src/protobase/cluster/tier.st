"-- cluster/tier.st: the shared tier, the cluster tier of a space every node shares --

proto_db cluster/persister.py at v2.0.0rc3 (PlainTier, _node_log, cluster_fields): what the
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
                false when the storage holds that root or a newer one in the order of roots
                (PBRootOrder: the persisted root never goes backwards), or #busy when another
                holder has the root lock: tryLockRoot, readRoot, the order check, then
                replaceRoot: with the storage epoch plus one (the compare-and-swap), the lock
                released whatever happens. It never waits; the persister reschedules a busy
                attempt (Task 25).

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
    ^ PBValidationError signal: 'PBSharedTier: the storage of a cluster node is a PBFileStorage opened with clusterPath:, not '
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
 mode."
PBSharedTier >> _labeled: aRootRecord
  | space term epoch |
  space := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: aRootRecord pointer storage: storage.
  epoch := space clusterEpoch.
  epoch isNil ifTrue: [
    ^ PBLabeledRoot label: 0 record: (PBRootRecord segment: aRootRecord segment offset: aRootRecord offset epoch: aRootRecord epoch)].
  term := space clusterTerm.
  ^ PBLabeledRoot label: (term isNil ifTrue: [0] ifFalse: [term])
    record: (PBRootRecord segment: aRootRecord segment offset: aRootRecord offset epoch: epoch).

"Publishes the record of aLabeledRoot as the storage root (CC19, proto_db PlainTier.persist):
 true once published; false when the storage holds that root or a newer one in the order of
 roots; #busy when another holder has the root lock. The lock is released whatever happens."
PBSharedTier >> persist: aLabeledRoot
  | current |
  ((aLabeledRoot isKindOf: PBLabeledRoot) and: [aLabeledRoot record notNil]) ifFalse: [
    ^ PBValidationError signal: 'PBSharedTier persist: a PBLabeledRoot of a record was expected, not ' , aLabeledRoot printString].
  storage tryLockRoot ifFalse: [^ #busy].
  ^ [current := storage readRoot.
     (current notNil and: [(PBRootOrder compare: (self _labeled: current) with: aLabeledRoot) >= 0])
       ifTrue: [false]
       ifFalse: [
         storage replaceRoot: (PBRootRecord segment: aLabeledRoot record segment offset: aLabeledRoot record offset
           epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1])).
         true]]
    ensure: [storage unlockRoot].

"Whether the shared storage can read the SpaceRoot of aLabeledRoot (the probe of a base,
 PBProbeRoot): true for the empty space; false when its record is missing, damaged or not a
 SpaceRoot (a PBDBError) or the file system fails."
PBSharedTier >> canRead: aLabeledRoot
  aLabeledRoot record isNil ifTrue: [^ true].
  ^ [storage loadAt: aLabeledRoot record pointer expecting: PBFileStorage spaceRootTag. true]
    on: Error do: [:e |
      ((e isKindOf: PBDBError) or: [e isKindOf: FileSystemError])
        ifTrue: [e return: false]
        ifFalse: [e pass]].

"Closes the node's acceptor log and releases its lock (the space is closing). Idempotent. The
 storage is the space's: it is not closed here."
PBSharedTier >> close
  log close.

PBSharedTier >> printOn: aStream
  aStream nextPutAll: 'PBSharedTier('; print: nodeId; nextPutAll: ', '; print: storage; nextPut: $).
