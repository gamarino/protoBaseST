"EXPECT: ok 2"
"A read whose persisted root was read but not learnt never sees the empty space (final review M5;
 space.st PBObjectSpace >> _committedRecord). The directory holds a persisted root (a standalone
 space with database 'legacy'). Of three members only n0 runs, so its confirmation and its
 recovery from the peers fail (no majority answers), and the read falls back to the persisted
 root. A seam coordinator (FenceBeforeLearn) fences n0 after the space read the persisted root and
 before the acceptor learns it, the race the review names: a fenced acceptor learns nothing
 (acceptLearnCommitted:), so n0 still knows no committed root. (1) listDatabases answers the
 persisted root's databases, not #() (the empty space); (2) openDatabase: finds 'legacy' and a
 transaction reads its data: on the fenced node the recovery is refused at once, and the read
 falls back to the persisted root, as proto_db's fenced node (its recovery query goes unanswered,
 ProtoConflictError, then the persisted read). No wait depends on time: the confirmation's permit is bounded by the
 space's lockTimeout and the recovery by requestTimeout, and either failure only leads on to the
 persisted read. The space (QuietSpace) starts no persister, whose refresh would learn the
 persisted root first."
Import from: 'protobase'.
Import from: '_check'.

PBClusterCoordinator subclass: #FenceBeforeLearn.

FenceBeforeLearn >> _observePersisted: aLabeledRoot from: aTier
  (self instVarNamed: 'cells') acceptor value _fault: 'planted: fenced between the persisted read and the learn'.
  [self isFenced] whileFalse: [(Future after: 10) wait].
  ^ super _observePersisted: aLabeledRoot from: aTier.

PBObjectSpace subclass: #QuietSpace.

"No persister: its refresh would learn the persisted root first, and the race could not be set up."
QuietSpace >> _startPersister
  ^ self.

| c base dir space db peers node r |
c := Check new.
base := FileSystem temp / ('pbst-reads-persisted-unlearnt-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
dir := base / 'space'.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'legacy'.
db run: [:t | t setRootObject: 'counter' value: 41].
space close.

peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7800].
node := FenceBeforeLearn nodeId: 'n0' peers: peers options: (Dictionary new
  at: #leaseDuration put: 600; at: #driftMargin put: 400; at: #requestTimeout put: 100; at: #startupGrace put: 0;
  at: #acquireTimeout put: 300; at: #transport put: PBInProcessNetwork new endpoint; yourself).
node start.
space := QuietSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node lockTimeout: 300.
r := [space listDatabases] on: Error do: [:e | e return: { e class name. e messageText }].
c that: 'a persisted root read but not learnt (n0 fenced in between) is answered, never the empty space'
  is: { r. node isFenced. node committedRoot }
  equals: { #('legacy'). true. nil }.
r := [(space openDatabase: 'legacy') run: [:t | t getRootObject: 'counter'] retries: 0]
  on: Error do: [:e | e return: { e class name. e messageText }].
c that: 'and its database is found and read'
  is: r
  equals: 41.

[space close] on: Error do: [:e | e return: nil].
node stop waitWithin: 60000.
base deleteAll.
c report.
