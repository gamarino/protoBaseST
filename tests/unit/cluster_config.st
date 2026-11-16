"EXPECT: ok 27"
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
| c peers cfg build expected names n a b |
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
expected := #('leaseDuration' 'driftMargin' 'renewal' 'permitFloor' 'renewBackoff' 'idleEnd' 'ownerIdleRelease' 'requestTimeout'
  'sendReserve' 'permissionDeadline' 'startupGrace' 'backoff' 'wakeSpread' 'straggle' 'turnSilence'
  'acquireTimeout' 'gatherAttempts' 'persist' 'retryHold').
names := PBClusterConfig timerTable collect: [:row | row first].
c that: 'the timer table has one row per timer at depth 0' is:
  { names. (PBClusterConfig timerTable allSatisfy: [:row | row size = 3 and: [row allSatisfy: [:s | s isString and: [s notEmpty]]]]) }
  equals: { expected. true }.
c that: 'a String key is honoured, as its Symbol' is: (build value: { 'leaseDuration' -> 9000 }) leaseDuration equals: 9000000.
c that: 'a key that is no String is refused naming it' signals: PBValidationError containing: '5'
  during: [build value: { 5 -> 9000 }].
c that: 'ownerIdleRelease 0 is refused' signals: PBValidationError containing: 'ownerIdleRelease'
  during: [build value: { #ownerIdleRelease -> 0 }].
c that: 'ownerIdleRelease 500 is kept' is: (build value: { #ownerIdleRelease -> 500 }) ownerIdleRelease equals: 500000.
n := build value: { #driftMargin -> nil. #sendReserve -> nil. #startupGrace -> nil. #ownerIdleRelease -> nil. #voters -> nil. #authKey -> nil }.
c that: 'an explicit nil is the default of a nullable option' is:
  { n driftMargin. n sendReserve. n startupGrace. n ownerIdleRelease. n authKey }
  equals: { 1333334. 166666. 3333334. nil. nil }.
c that: 'a duration above the SmallInteger bound is refused' signals: PBValidationError containing: 'acquireTimeout'
  during: [build value: { #acquireTimeout -> (SmallInteger maxVal // 4000 + 1) }].
c that: 'the bound itself is accepted' is: (build value: { #acquireTimeout -> (SmallInteger maxVal // 4000) }) acquireTimeout
  equals: SmallInteger maxVal // 4000 * 1000.
a := build value: { #backoff -> (OrderedCollection with: 3 with: 4) }.
b := build value: { #backoff -> (2 to: 3) }.
c that: 'backoff takes any pair of integers' is:
  { a backoffLow. a backoffHigh. b backoffLow. b backoffHigh }
  equals: { 3000. 4000. 2000. 3000 }.
c that: 'the member check comes before the duration checks' signals: PBValidationError containing: 'n9'
  during: [PBClusterConfig nodeId: 'n9' peers: peers options: (Dictionary new at: #leaseDuration put: 0; yourself)].
c that: 'tier options are ordinary unknown options' signals: PBValidationError containing: 'tier'
  during: [build value: { #tier -> 1 }].
"Review M1: durations in messages are milliseconds, an Integer or a decimal, never a Fraction or us."
c that: 'the driftMargin bound is stated in ms, as a decimal' signals: PBValidationError containing: 'at least 1333.334 ms'
  during: [build value: { #driftMargin -> 1333 }].
c that: 'the sendReserve bound is stated in ms, as a decimal' signals: PBValidationError containing: '(166.666 ms)'
  during: [build value: { #sendReserve -> 200 }].
c that: 'msText: prints microseconds as milliseconds: an Integer, else a decimal without trailing zeros'
  is: ({ 0. 1000. 3333334. 166666. 1500. 1. 120000 } collect: [:us | PBClusterConfig msText: us])
  equals: #('0' '1' '3333.334' '166.666' '1.5' '0.001' '120').
c that: 'no us in the refusals'
  is: ({ { #driftMargin -> 1333 }. { #sendReserve -> 200 } } collect: [:pairs |
    [build value: pairs. 'accepted'] on: PBValidationError do: [:e | e return: (e messageText includesSubstring: ' us')]])
  equals: #(false false).
c report displayNl.
