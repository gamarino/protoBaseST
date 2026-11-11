"_st_write_space.st <mode> <directory> [<out.json>]: protoST's side of st_write_to_py.sh and
 crash_states_to_py.sh (a helper, never run as a test), writing through PBFileStorage's write
 side (plan Task 17): records saved into the storage's own segments, the root published under
 the root lock, each commit at the epoch of the root it was built on plus one.

  create <dir> <out.json>   creates database 'st' (version 0: a PBList of 300 integers, a
                            PBObject, a PBDictionary and an empty mutable dictionary;
                            published at epoch 1), then version 1 on top of it (one more root,
                            'previous' the version 0 root; epoch 2), with segments capped at
                            4096 bytes, so the records span several segments; writes
                            PBNotation dumpSpace:to: of the result
  extend <dir> <out.json>   reads the current root (ProtoBase's commit on top of it
                            included), adds version n + 1 of database 'st' with the root
                            'st2', publishes the epoch read plus one, and dumps the space
  trylock <dir>             prints the answer of tryLockRoot ('true' or 'false'), and
                            releases the lock when it took it
  hold-lock <dir>           takes the root lock, prints 'locked', holds it until stdin
                            closes, then releases it and prints 'released'
  crash-record <dir>        leaves a torn record at the end of a new segment
  crash-header <dir>        leaves a new segment whose header is torn (11 bytes)
  crash-roottmp <dir>       leaves a torn space.root.tmp (a publish failed while writing it)
  crash-tail <dir>          leaves two records appended after the root, never published

 The crash modes use the seams of tests/unit/_seams.st (on STPATH): a prefix is written and
 the write fails, which leaves what a crash there leaves; the root stays as it was.
Prints 'written' (create, extend, crash-*) or the answer (trylock)."
Import from: 'protobase'.
Import from: '_seams'.

| args mode dir st utc version publish root dbRoot spaceRoot objects stamp |
args := Smalltalk arguments.
(args size between: 2 and: 3) ifFalse: [
  'usage: _st_write_space.st create|extend|trylock <directory> [<out.json>]' displayNl.
  Smalltalk exit: 2].
mode := args at: 1.
dir := args at: 2.
utc := ZoneOffset utc.

"A new DatabaseRoot (persisted order) over objects and mutables."
version := [:anObjects :aMutables :n :aTime :anOrigin :aPrevious |
  PBDatabaseRoot _unsavedWithState: (PBFrozenDict withAssociations: {
    'objects' -> anObjects. 'mutables' -> aMutables. 'version' -> n. 'committed_at' -> aTime.
    'origin' -> anOrigin. 'previous' -> aPrevious })].
"Saves a SpaceRoot over aDatabases and publishes it, under the lock, at the epoch of the
 root the commit was built on (aStartEpoch, 0 for a space that had none) plus one: a root
 published meanwhile makes it PBConflictError, never a lost update."
publish := [:aStorage :aDatabases :aStartEpoch |
  | sr ptr |
  sr := PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> aDatabases }).
  ptr := aStorage save: sr.
  aStorage flushSegment.
  aStorage tryLockRoot ifFalse: [Error signal: 'the root lock is held by another process'].
  [aStorage replaceRoot: (PBRootRecord segment: ptr segmentBytes offset: ptr offset epoch: aStartEpoch + 1)]
    ensure: [aStorage unlockRoot]].
"Not before aTime: committed_at never goes back (ProtoBase _build_root)."
stamp := [:aTime | | now |
  now := DateTime nowUTC.
  (aTime isNil or: [now utcOrdinalMicroseconds >= aTime utcOrdinalMicroseconds]) ifTrue: [now] ifFalse: [aTime]].

mode = 'hold-lock' ifTrue: [
  st := PBFileStorage path: dir.
  st tryLockRoot ifFalse: [Error signal: 'the root lock is held by another process'].
  'locked' displayNl.
  Stdio stdin upToEnd.
  st unlockRoot.
  st close.
  'released' displayNl.
  Smalltalk exit: 0].

(mode beginsWith: 'crash-') ifTrue: [
  | sp |
  st := SeamStorage path: dir.
  root := st readRoot.
  mode = 'crash-record' ifTrue: [
    st save: (PBObject withAll: { 'kept' -> 'an orphan' }).
    st writer tearNextAppendAt: 9.
    [st save: (PBObject withAll: { 'lost' -> true })] on: PBUnexpectedError do: [:e | nil]].
  mode = 'crash-header' ifTrue: [
    st tearNextSegmentHeader.
    [st save: (PBObject withAll: { 'lost' -> true })] on: PBUnexpectedError do: [:e | nil]].
  mode = 'crash-roottmp' ifTrue: [
    spaceRoot := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName) at: root pointer storage: st.
    sp := st save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> spaceRoot databases })).
    st tearRootTempAt: 6.
    st tryLockRoot.
    [st replaceRoot: (PBRootRecord segment: sp segmentBytes offset: sp offset epoch: root epoch + 1)]
      on: PBUnexpectedError do: [:e | nil].
    st unlockRoot].
  mode = 'crash-tail' ifTrue: [
    st save: (PBObject withAll: { 'unpublished' -> 1 }).
    st save: (PBObject withAll: { 'unpublished' -> 2 })].
  st readRoot epoch = root epoch ifFalse: [Error signal: 'the crash moved the root'].
  st close.
  'written' displayNl.
  Smalltalk exit: 0].

st := mode = 'create'
  ifTrue: [PBFileStorage path: dir segmentMaxBytes: 4096]
  ifFalse: [PBFileStorage path: dir].
mode = 'trylock' ifTrue: [
  | took |
  took := st tryLockRoot.
  took ifTrue: [st unlockRoot].
  st close.
  took printString displayNl.
  Smalltalk exit: 0].

mode = 'create' ifTrue: [
  | v0 v1 |
  objects := ((PBDictionary new
      setAt: 'numbers' value: (PBList new extend: (1 to: 300) asArray))
      setAt: 'acme' value: (PBObject withAll: { 'name' -> 'ACME'. 'since' -> (CalendarDate year: 2026 month: 11 day: 11). 'score' -> 4.5 }))
      setAt: 'rates' value: ((PBDictionary new setAt: 'ARS' value: 1) setAt: 'USD' value: 1450).
  v0 := version value: objects value: PBDictionary new value: 0 value: (stamp value: nil)
    value: (UUID new bytes) value: nil.
  publish value: st value: (PBDictionary new setAt: 'st' value: v0) value: 0.
  v1 := version value: (objects setAt: 'later' value: #('a' 'b'))
    value: v0 mutables value: 1 value: (stamp value: v0 committedAt) value: v0 origin value: v0.
  publish value: st value: (PBDictionary new setAt: 'st' value: v1) value: 1].

mode = 'extend' ifTrue: [
  | next |
  root := st readRoot.
  spaceRoot := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName) at: root pointer storage: st.
  dbRoot := spaceRoot databases getAt: 'st'.
  next := version value: (dbRoot objects setAt: 'st2' value: (PBObject withAll: { 'from' -> 'protoST' }))
    value: dbRoot mutables value: dbRoot version + 1 value: (stamp value: dbRoot committedAt)
    value: dbRoot origin value: dbRoot.
  publish value: st value: (spaceRoot databases setAt: 'st' value: next) value: root epoch].

st close.
PBNotation dumpSpace: (PBObjectSpace storage: (PBFileStorage path: dir)) to: (args at: 3).
'written' displayNl.
