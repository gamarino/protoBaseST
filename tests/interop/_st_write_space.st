"_st_write_space.st <mode> <directory> [<out.json>]: protoST's side of st_write_to_py.sh (a
 helper, never run as a test), writing through PBFileStorage's write side (plan Task 17):
 records saved into the storage's own segment, the root published under the root lock.

  create <dir> <out.json>   creates database 'st' (version 0: a PBList of 300 integers, a
                            PBObject, a PBDictionary and an empty mutable dictionary;
                            published at epoch 1), then version 1 on top of it (one more root,
                            'previous' the version 0 root; epoch 2), and writes
                            PBNotation dumpSpace:to: of the result
  extend <dir> <out.json>   reads the current root (ProtoBase's commit on top of it
                            included), adds version n + 1 of database 'st' with the root
                            'st2', publishes epoch + 1, and dumps the space
  trylock <dir>             prints the answer of tryLockRoot ('true' or 'false'), and
                            releases the lock when it took it

Prints 'written' (create, extend) or the answer (trylock)."
Import from: 'protobase'.

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
"Saves a SpaceRoot over aDatabases and publishes it at the next epoch, under the lock."
publish := [:aStorage :aDatabases |
  | sr ptr current |
  sr := PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> aDatabases }).
  ptr := aStorage save: sr.
  aStorage flushSegment.
  aStorage tryLockRoot ifFalse: [Error signal: 'the root lock is held by another process'].
  [current := aStorage readRoot.
   aStorage replaceRoot: (PBRootRecord segment: ptr segmentBytes offset: ptr offset
     epoch: (current isNil ifTrue: [1] ifFalse: [current epoch + 1]))]
    ensure: [aStorage unlockRoot]].
"Not before aTime: committed_at never goes back (ProtoBase _build_root)."
stamp := [:aTime | | now |
  now := DateTime nowUTC.
  (aTime isNil or: [now utcOrdinalMicroseconds >= aTime utcOrdinalMicroseconds]) ifTrue: [now] ifFalse: [aTime]].

st := PBFileStorage path: dir.
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
  publish value: st value: (PBDictionary new setAt: 'st' value: v0).
  v1 := version value: (objects setAt: 'later' value: #('a' 'b'))
    value: v0 mutables value: 1 value: (stamp value: v0 committedAt) value: v0 origin value: v0.
  publish value: st value: (PBDictionary new setAt: 'st' value: v1)].

mode = 'extend' ifTrue: [
  | next |
  root := st readRoot.
  spaceRoot := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName) at: root pointer storage: st.
  dbRoot := spaceRoot databases getAt: 'st'.
  next := version value: (dbRoot objects setAt: 'st2' value: (PBObject withAll: { 'from' -> 'protoST' }))
    value: dbRoot mutables value: dbRoot version + 1 value: (stamp value: dbRoot committedAt)
    value: dbRoot origin value: dbRoot.
  publish value: st value: (spaceRoot databases setAt: 'st' value: next)].

st close.
PBNotation dumpSpace: (PBObjectSpace storage: (PBFileStorage path: dir)) to: (args at: 3).
'written' displayNl.
