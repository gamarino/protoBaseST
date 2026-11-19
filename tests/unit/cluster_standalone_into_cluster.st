"EXPECT: ok 6"
"A standalone space protoBaseST wrote is brought into a cluster (final review I3; tier.st
 _labeled:, round.st _recommitRootOn:stamp:, proto_db cluster_fields: a root written outside
 cluster mode reads as label 0 with the storage epoch, and the first lease re-commits it as the
 first cluster root, R50). (1) A plain space (PBFileStorage path:) is written and closed: database
 'legacy', a counter at 41 and a token. (2) Three in-process coordinators (one PBInProcessNetwork)
 open the same directory with clusterPath:; every node reads the old data. (3) A commit on n1
 increments the counter; every node reads 42. (4) After sync:, space.root holds a cluster root
 (cluster_term set), and the chain of cluster_previous ends at the plain root: the last link has no
 cluster field and is the atom the plain space published (its pointer). (5) The door is one way:
 the directory now holds cluster/, and PBFileStorage path: refuses it with PBNotSupportedError.
 (6) A cluster stopped and started again over the same directory still reads the data. The
 proto_db side (proto_db reads the converted space; a proto_db-written standalone space converted)
 is tests/interop/standalone_into_cluster.sh. Waits are conditions with a deadline (60 s); no
 duration is asserted."
Import from: 'protobase'.
Import from: '_check'.

| c base dir plain space db record ids peers network nodes spaces until open stop reads root chain last
  links |
c := Check new.
base := FileSystem temp / ('pbst-standalone-into-cluster-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
dir := base / 'space'.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].

"(1)"
plain := PBFileStorage path: dir pathString.
space := PBObjectSpace storage: plain.
db := space newDatabase: 'legacy'.
db run: [:t | t setRootObject: 'counter' value: 41. t setRootObject: 'tokens' value: (PBDictionary new setAt: 'old' value: 'standalone')].
record := plain readRoot.
space close.

"(2)"
ids := #('n0' 'n1' 'n2').
open := [
  peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7500].
  network := PBInProcessNetwork new.
  nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
    at: #leaseDuration put: 3000; at: #requestTimeout put: 100; at: #transport put: network endpoint; yourself)].
  nodes do: [:node | node start].
  spaces := nodes collect: [:node | PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
  until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]].
stop := [
  spaces do: [:s | s close].
  nodes do: [:node | node stop waitWithin: 60000]].
"Each node's { counter. token }, read through run:."
reads := [spaces collect: [:s |
  (s openDatabase: 'legacy') run: [:t | { t getRootObject: 'counter'. (t getRootObject: 'tokens') getAt: 'old' }] retries: 50]].
open value.
c that: 'every node of the cluster reads the data the standalone space holds'
  is: reads value
  equals: { { 41. 'standalone' }. { 41. 'standalone' }. { 41. 'standalone' } }.

"(3)"
((spaces at: 2) openDatabase: 'legacy') run: [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1] retries: 50.
c that: 'a commit on n1 is read by every node'
  is: (until value: [(reads value collect: [:x | x first]) = #(42 42 42)])
  equals: true.

"(4)"
(spaces at: 2) sync: 60000.
root := PBTypeRegistry unloadedAtomFor: (PBTypeRegistry aliasOf: PBSpaceRoot typeName) at: (spaces at: 2) storage readRoot pointer storage: (spaces at: 2) storage.
links := OrderedCollection new.
chain := root.
[chain notNil and: [chain clusterEpoch notNil]] whileTrue: [links add: chain clusterTerm. chain := chain clusterPrevious].
last := chain.
c that: 'space.root is a cluster root whose cluster_previous chain ends at the plain root the standalone space published'
  is: { root clusterTerm notNil. links notEmpty. links allSatisfy: [:t | t > 0]. last notNil.
    last notNil and: [last clusterTerm isNil and: [last clusterPrevious isNil]].
    last notNil and: [last pointer offset = record pointer offset and: [last pointer segmentBytes = record pointer segmentBytes]] }
  equals: { true. true. true. true. true. true }.
stop value.

"(5)"
c that: 'the conversion is one way: the directory holds cluster/'
  is: (dir / 'cluster') exists
  equals: true.
c that: 'and PBFileStorage path: refuses it'
  signals: PBNotSupportedError containing: 'holds cluster/'
  during: [PBFileStorage path: dir pathString].

"(6)"
open value.
c that: 'a cluster started again over the directory reads the converted data'
  is: (until value: [(reads value collect: [:x | x first]) = #(42 42 42)])
  equals: true.
stop value.

base deleteAll.
c report.
