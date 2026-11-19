"_st_cluster_space.st <mode> ...: protoBaseST's side of cluster_space_to_py.sh and
 rootlog_both_ways.sh (a helper, never run as a test).

  write <dir> <out.json> <fields.txt>
      three in-process nodes (n0, n1, n2) share the cluster space <dir> (PBFileStorage
      clusterPath:, PBInProcessNetwork); they commit the ERP-shaped workload of
      _st_write_space.st through the coordinator, each commit on another node: n0 creates
      database 'st' (newDatabase:), n0 commits the root 'numbers' (a PBList of 300 integers),
      n1 'acme' (a PBObject with a date and a float), n2 'rates' (a PBDictionary), n0 'later'
      (#('a' 'b')). The last commit is n0's, a barrier, so n0 knows the newest root; n0 then
      sync:s, so space.root holds it (checked: the cluster epoch of the storage root's
      SpaceRoot is n0's committedEpoch, and persistedEpoch >= committedEpoch). Writes
      PBNotation dumpSpace:to: <out.json> and the cluster fields of space.root to <fields.txt>,
      then closes every space and stops every node.
  load-log <file>
      prints what PBAcceptorLog decodes from the acceptor log <file> (read by path, as
      PBAcceptorLog >> load, no lock taken), in the text py_rootlog.py load prints.
  write-log <file>
      appends to the new acceptor log <file> the entry sequence py_rootlog.py write appends,
      through PBAcceptorLog's API (promise:, append:label:root:, markRejoined), and closes it.
  name <id>...
      prints PBSharedTier logName: of each id, one per line; an id given as hex: (hex of its
      UTF-8) is decoded first, so any id passes through the command line.

 The text of a log (both sides): 'accepted' and 'committed' as '<kind> none', '<kind> <label>
 empty' (the empty space) or '<kind> <label> <version> <segment hex> <offset> <epoch>'; then
 'promise <n>', 'top <n>', 'rejoined true|false'. The fields text: one line per SpaceRoot of
 the chain from space.root's through cluster_previous, '<cluster_term> <cluster_epoch>', the
 last line 'end'.

 Every wait is a condition with a deadline of 60 s; no duration is asserted."
Import from: 'protobase'.

| args mode until rootText logText sequence |
args := Smalltalk arguments.
args isEmpty ifTrue: [
  'usage: _st_cluster_space.st write|load-log|write-log|name ...' displayNl.
  Smalltalk exit: 2].
mode := args at: 1.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
rootText := [:aKind :aLabeledRoot |
  aLabeledRoot isNil
    ifTrue: [aKind , ' none']
    ifFalse: [aLabeledRoot record isNil
      ifTrue: [aKind , ' ' , aLabeledRoot label printString , ' empty']
      ifFalse: [aKind , ' ' , aLabeledRoot label printString , ' ' , aLabeledRoot record version printString
        , ' ' , aLabeledRoot record segmentHex , ' ' , aLabeledRoot record offset printString
        , ' ' , aLabeledRoot record epoch printString]]].
logText := [:aLoggedRoots |
  { rootText value: 'accepted' value: aLoggedRoots accepted.
    rootText value: 'committed' value: aLoggedRoots committed.
    'promise ' , aLoggedRoots promise printString.
    'top ' , aLoggedRoots top printString.
    'rejoined ' , aLoggedRoots isRejoined printString }].
"The entry sequence of py_rootlog.py write (keep both in step): a promise below the durable one
 writes nothing; an older committed root does not replace a newer one; the last promise needs
 the full u64 range."
sequence := [:aLog | | seg1 seg2 seg3 |
  seg1 := ByteArray withAll: (0 to: 15) asArray.
  seg2 := ByteArray withAll: (240 to: 255) asArray.
  seg3 := ByteArray withAll: (16 to: 31) asArray.
  aLog promise: 3.
  aLog append: #accepted label: 3 root: nil.
  aLog append: #committed label: 3 root: nil.
  aLog promise: 2.
  aLog promise: 7.
  aLog append: #accepted label: 7 root: (PBRootRecord segment: seg1 offset: 1234 epoch: 5).
  aLog append: #committed label: 7 root: (PBRootRecord segment: seg1 offset: 1234 epoch: 5).
  aLog append: #accepted label: 7 root: (PBRootRecord segment: seg2 offset: 99 epoch: 6).
  aLog append: #committed label: 3 root: (PBRootRecord segment: seg3 offset: 8 epoch: 9).
  aLog promise: (2 raisedTo: 63) + 1.
  aLog markRejoined].

mode = 'name' ifTrue: [
  (args copyFrom: 2 to: args size) do: [:arg | | id |
    id := (arg beginsWith: 'hex:')
      ifTrue: [(ByteArray fromHex: (arg copyFrom: 5 to: arg size)) utf8Decoded]
      ifFalse: [arg].
    (PBSharedTier logName: id) displayNl].
  Smalltalk exit: 0].

mode = 'load-log' ifTrue: [
  | file |
  file := (args at: 2) asFileReference.
  (logText value: (PBAcceptorLog decode: (PBAcceptorLog framedLogClass read: file kind: PBAcceptorLog logKind) payloads
    path: file pathString)) do: [:line | line displayNl].
  Smalltalk exit: 0].

mode = 'write-log' ifTrue: [
  | log |
  log := PBAcceptorLog path: (args at: 2).
  [sequence value: log] ensure: [log close].
  'written' displayNl.
  Smalltalk exit: 0].

mode = 'write' ifTrue: [
  | dir ids peers network nodes spaces dbs st record spaceRoot lines chain |
  args size = 4 ifFalse: [
    'usage: _st_cluster_space.st write <dir> <out.json> <fields.txt>' displayNl.
    Smalltalk exit: 2].
  dir := args at: 2.
  ids := #('n0' 'n1' 'n2').
  peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
  network := PBInProcessNetwork new.
  nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
    at: #leaseDuration put: 3000;
    at: #requestTimeout put: 100;
    at: #transport put: network endpoint;
    yourself)].
  nodes do: [:node | node start].
  spaces := nodes collect: [:node |
    PBObjectSpace storage: (PBFileStorage clusterPath: dir) coordinator: node].
  (until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]) ifFalse: [
    Error signal: 'the nodes did not finish rejoining within 60 s'].
  (spaces at: 1) newDatabase: 'st'.
  dbs := spaces collect: [:space | space openDatabase: 'st'].
  (dbs at: 1) run: [:t | t setRootObject: 'numbers' value: (PBList new extend: (1 to: 300) asArray)] retries: 100.
  (dbs at: 2) run: [:t |
    t setRootObject: 'acme' value: (PBObject withAll: {
      'name' -> 'ACME'. 'since' -> (CalendarDate year: 2026 month: 11 day: 11). 'score' -> 4.5 })] retries: 100.
  (dbs at: 3) run: [:t |
    t setRootObject: 'rates' value: ((PBDictionary new setAt: 'ARS' value: 1) setAt: 'USD' value: 1450)] retries: 100.
  (dbs at: 1) run: [:t | t setRootObject: 'later' value: #('a' 'b')] retries: 100.
  (spaces at: 1) sync: 60000.
  (spaces at: 1) persistedEpoch >= (spaces at: 1) committedEpoch ifFalse: [
    Error signal: 'after sync: the persisted epoch is below the committed one'].
  st := (spaces at: 1) storage.
  record := st readRoot.
  spaceRoot := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName)
    at: record pointer storage: st.
  spaceRoot clusterEpoch = (spaces at: 1) committedEpoch ifFalse: [
    Error signal: 'space.root holds cluster epoch ' , spaceRoot clusterEpoch printString
      , ', not n0''s committedEpoch ' , (spaces at: 1) committedEpoch printString].
  PBNotation dumpSpace: (spaces at: 1) to: (args at: 3).
  lines := OrderedCollection new.
  chain := spaceRoot.
  [chain isNil] whileFalse: [
    lines add: chain clusterTerm printString , ' ' , chain clusterEpoch printString.
    chain := chain clusterPrevious].
  lines add: 'end'.
  (args at: 4) asFileReference contents: (lines inject: '' into: [:acc :l | acc , l , (String with: Character lf)]).
  spaces do: [:space | space close].
  nodes do: [:node | node stop waitWithin: 60000].
  'written' displayNl.
  Smalltalk exit: 0].

('unknown mode ' , mode) displayNl.
Smalltalk exit: 2.
