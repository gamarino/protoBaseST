"_st_into_cluster.st <mode> <dir>: protoBaseST's side of standalone_into_cluster.sh (a helper,
 never run as a test).

  write-standalone <dir>
      a standalone space (PBFileStorage path:): database 'legacy' with the root objects
      'counter' (41) and 'tokens' (a PBDictionary, 'old' -> 'standalone'); prints 'written'.
  convert <dir>
      three in-process nodes (n0, n1, n2, one PBInProcessNetwork) open the standalone space <dir>
      with clusterPath:; every node reads counter 41 and tokens at 'old' (the token must be the
      same on every node); n1 commits counter + 1; once every node reads 42, n1 sync:s, so
      space.root holds a cluster root; every space is closed and every node stopped. Prints
      'converted <token>'.

 Every wait is a condition with a deadline of 60 s; no duration is asserted."
Import from: 'protobase'.

| args mode dir until |
args := Smalltalk arguments.
args size = 2 ifFalse: [
  'usage: _st_into_cluster.st write-standalone|convert <dir>' displayNl.
  Smalltalk exit: 2].
mode := args at: 1.
dir := args at: 2.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].

mode = 'write-standalone' ifTrue: [
  | space db |
  space := PBObjectSpace storage: (PBFileStorage path: dir).
  db := space newDatabase: 'legacy'.
  db run: [:t | t setRootObject: 'counter' value: 41. t setRootObject: 'tokens' value: (PBDictionary new setAt: 'old' value: 'standalone')].
  space close.
  'written' displayNl.
  Smalltalk exit: 0].

mode = 'convert' ifTrue: [
  | ids peers network nodes spaces reads first |
  ids := #('n0' 'n1' 'n2').
  peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7600].
  network := PBInProcessNetwork new.
  nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
    at: #leaseDuration put: 3000; at: #requestTimeout put: 100; at: #transport put: network endpoint; yourself)].
  nodes do: [:node | node start].
  spaces := nodes collect: [:node | PBObjectSpace storage: (PBFileStorage clusterPath: dir) coordinator: node].
  (until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]]) ifFalse: [
    Error signal: 'the nodes did not finish rejoining within 60 s'].
  reads := [spaces collect: [:s |
    (s openDatabase: 'legacy') run: [:t | { t getRootObject: 'counter'. (t getRootObject: 'tokens') getAt: 'old' }] retries: 50]].
  first := reads value.
  (first allSatisfy: [:x | x = { 41. first first last }]) ifFalse: [
    Error signal: 'the nodes read ' , first printString , ', not counter 41 and one token'].
  ((spaces at: 2) openDatabase: 'legacy') run: [:t | t setRootObject: 'counter' value: (t getRootObject: 'counter') + 1] retries: 50.
  (until value: [(reads value collect: [:x | x first]) = #(42 42 42)]) ifFalse: [
    Error signal: 'the nodes did not all read the commit within 60 s'].
  (spaces at: 2) sync: 60000.
  spaces do: [:s | s close].
  nodes do: [:node | node stop waitWithin: 60000].
  ('converted ' , first first last) displayNl.
  Smalltalk exit: 0].

('unknown mode ' , mode) displayNl.
Smalltalk exit: 2.
