"EXPECT: ok 13"
"PBClusterConfig (cluster/config.st): the options of a cluster member and the timer table.
 Options are milliseconds; the accessors answer microseconds (CC3). With the proto_db defaults
 (lease 2000 ms) the margin is ceiling(2D/3) = 1333334 us, the belief 666666 us, the send
 reserve min(250 ms, belief // 4) = 166666 us, the startup grace D + margin = 3333334 us and
 the idle end D / 4 = 500000 us. The margin 1333 ms is below the minimum, 1334 ms is not
 (R78b); a send reserve of 200 ms exceeds belief // 4 (plant reserve_uncapped); a request
 timeout of 700 ms is not below the belief. #fetchTimeout belongs to Phase D (CC8). Nothing in
 this file runs a timer."
Import from: 'protobase'.
Import from: '_check'.
| c peers cfg opts build expected names |
c := Check new.
peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7000].
build := [:pairs |
  | d |
  d := Dictionary new.
  pairs do: [:p | d at: p key put: p value].
  PBClusterConfig nodeId: 'n1' peers: peers options: d].
cfg := build value: #().
c that: 'defaults in microseconds' is:
  { cfg leaseDuration. cfg driftMargin. cfg belief. cfg requestTimeout. cfg sendReserve. cfg acquireTimeout.
    cfg backoffLow. cfg backoffHigh. cfg startupGrace. cfg idleEnd. cfg persistInterval. cfg persistLag.
    cfg ownerIdleRelease }
  equals: { 2000000. 1333334. 666666. 250000. 166666. 30000000. 1000. 50000. 3333334. 500000. 50000. 1000000. nil }.
c that: 'constants and identity' is:
  { cfg wakeSpread. cfg minStraggle. cfg straggleFactor. cfg turnSilence. cfg gatherAttempts. cfg retryHold.
    cfg retryWait. cfg permitRetries. cfg depth. cfg nodeId. cfg rank. cfg membership ids. cfg authKey. cfg seed }
  equals: { 3000. 5000. 4. 50000. 3. 100000. 5000. 3. 0. 'n1'. 1. #('n0' 'n1' 'n2'). nil. nil }.
c that: 'driftMargin 1333 ms is refused' signals: PBValidationError containing: 'driftMargin'
  during: [build value: { #driftMargin -> 1333 }].
c that: 'driftMargin 1334 ms is accepted' is: (build value: { #driftMargin -> 1334 }) driftMargin equals: 1334000.
c that: 'sendReserve 200 ms is refused' signals: PBValidationError containing: 'sendReserve'
  during: [build value: { #sendReserve -> 200 }].
c that: 'requestTimeout 700 ms is refused' signals: PBValidationError containing: 'requestTimeout'
  during: [build value: { #requestTimeout -> 700 }].
c that: 'an unknown option is refused naming it' signals: PBValidationError containing: 'lease'
  during: [build value: { #lease -> 1000 }].
c that: 'fetchTimeout is Phase D' signals: PBNotSupportedError containing: 'Phase D'
  during: [build value: { #fetchTimeout -> 100 }].
c that: 'a node id that is no member is refused' signals: PBValidationError containing: 'n9'
  during: [PBClusterConfig nodeId: 'n9' peers: peers options: Dictionary new].
c that: 'a 31-byte authKey is refused' signals: PBValidationError containing: 'authKey'
  during: [build value: { #authKey -> (ByteArray new: 31) }].
c that: 'a 32-byte authKey is kept' is: (build value: { #authKey -> (ByteArray new: 32) }) authKey size equals: 32.
cfg := build value: { #leaseDuration -> 3000. #requestTimeout -> 100. #backoff -> #(2 9). #voters -> #('n0' 'n1' 'n2') }.
c that: 'other options derive their defaults from the lease' is:
  { cfg driftMargin. cfg sendReserve. cfg startupGrace. cfg backoffLow. cfg backoffHigh. cfg membership voters }
  equals: { 2000000. 100000. 5000000. 2000. 9000. #('n0' 'n1' 'n2') }.
expected := #('leaseDuration' 'driftMargin' 'renewal' 'permitFloor' 'idleEnd' 'ownerIdleRelease' 'requestTimeout'
  'sendReserve' 'permissionDeadline' 'startupGrace' 'backoff' 'wakeSpread' 'straggle' 'turnSilence'
  'acquireTimeout' 'gatherAttempts' 'persist' 'retryHold').
names := PBClusterConfig timerTable collect: [:row | row first].
c that: 'the timer table has one row per timer at depth 0' is:
  { names. (PBClusterConfig timerTable allSatisfy: [:row | row size = 3 and: [row allSatisfy: [:s | s isString and: [s notEmpty]]]]) }
  equals: { expected. true }.
c report displayNl.
