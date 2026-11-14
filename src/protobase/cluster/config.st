"-- cluster/config.st: the configuration of a cluster member and the table of its timers --

proto_db's ClusterCoordinator.__init__ (cluster/coordinator.py) and the 'Timers' table of
coordinator-protocol.rst, with its defaults and refusal rules (maintainer decision Q6: proto_db's
defaults, configurable). Pure data: no timer runs here.

  PBClusterConfig  the validated configuration of one member: its node id and rank, the
                   membership, every duration, the constants of the protocol, the optional frame
                   key and the test seams. Options are given in milliseconds, as Integers; the
                   accessors answer microseconds (CC3). Class side: nodeId:peers:options:, and
                   timerTable, one row per timer of the protocol that applies at DEPTH 0 over
                   shared storage (the rows fetch_timeout, data replica hedge and gate fallback
                   are Phase D and absent): { name. default. what it drives }.

Rules (R78b, R121): driftMargin is at least ceiling(2D/3) (default that) and below D, so the
belief D - margin is at most a third of the promise; requestTimeout is below the belief;
sendReserve is at most belief // 4 (default min(requestTimeout, belief // 4)); startupGrace
defaults to D + margin; idleEnd is D // 4. Options that name tiered storage (CC8) are
PBNotSupportedError; any other unknown option is PBValidationError.

Every value here is immutable: built once by its class-side constructor."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/protocol'.

Object subclass: #PBClusterConfig instanceVariableNames: 'membership nodeId rank durations authKey seed transport clock'.

"The options of DEPTH 0, with the options that belong to Phase D (tiered storage, CC8)."
PBClusterConfig class >> _options
  ^ #(#leaseDuration #driftMargin #requestTimeout #sendReserve #acquireTimeout #backoff #startupGrace
      #persistInterval #persistLag #ownerIdleRelease #voters #authKey #seed #transport #clock).

PBClusterConfig class >> _phaseDOptions
  ^ #(#fetchTimeout #tier #tierOptions #dataReplicas #replicaHedge).

"A non-negative (positive when mustBePositive) Integer number of milliseconds, as microseconds;
 PBValidationError naming aName otherwise (proto_db _number: never a Boolean)."
PBClusterConfig class >> _micros: aValue named: aName positive: mustBePositive
  (aValue isInteger and: [aValue >= 0 and: [mustBePositive not or: [aValue > 0]]]) ifFalse: [
    ^ PBValidationError signal: aName , ' must be a ' , (mustBePositive ifTrue: ['positive'] ifFalse: ['non-negative'])
      , ' Integer number of milliseconds, not ' , aValue printString].
  ^ aValue * 1000.

"The configuration of the member aNodeId of the cluster anArrayOfPBPeer with the options of
 aDictionary (keys as the list above, durations in milliseconds)."
PBClusterConfig class >> nodeId: aNodeId peers: anArrayOfPBPeer options: aDictionary
  | membership opt micros duration margin minMargin belief request reserve grace backoff low high key |
  (aDictionary isKindOf: Dictionary) ifFalse: [
    ^ PBValidationError signal: 'PBClusterConfig: the options are a Dictionary, not ' , aDictionary printString].
  aDictionary keys do: [:k |
    (self _phaseDOptions includes: k) ifTrue: [
      ^ PBNotSupportedError signal: 'Option ' , k printString , ' belongs to tiered storage, which is Phase D, not supported'].
    (self _options includes: k) ifFalse: [
      ^ PBValidationError signal: 'Unknown cluster option ' , k printString]].
  membership := PBMembership peers: anArrayOfPBPeer voters: (aDictionary at: #voters ifAbsent: [nil]).
  opt := [:name :default | aDictionary at: name ifAbsent: [default]].
  micros := [:name :default :positive |
    (aDictionary includesKey: name)
      ifTrue: [self _micros: (aDictionary at: name) named: name printString positive: positive]
      ifFalse: [default]].
  duration := micros value: #leaseDuration value: 2000000 value: true.
  minMargin := (duration * 2 + 2) // 3.
  margin := micros value: #driftMargin value: minMargin value: false.
  margin >= duration ifTrue: [
    ^ PBValidationError signal: 'driftMargin must be smaller than leaseDuration'].
  margin < minMargin ifTrue: [
    ^ PBValidationError signal: 'driftMargin must be at least ' , minMargin printString
      , ' us (2/3 of leaseDuration): a holder believes its lease for at most a third of the granters'' promise (R78b)'].
  belief := duration - margin.
  request := micros value: #requestTimeout value: 250000 value: true.
  request >= belief ifTrue: [
    ^ PBValidationError signal: 'requestTimeout must be shorter than the belief, leaseDuration - driftMargin'].
  reserve := micros value: #sendReserve value: (request min: belief // 4) value: false.
  reserve > (belief // 4) ifTrue: [
    ^ PBValidationError signal: 'sendReserve must be at most (leaseDuration - driftMargin) / 4 ('
      , (belief // 4) printString , ' us): a larger reserve would refuse by rule the permissions an owner issues'].
  grace := micros value: #startupGrace value: duration + margin value: false.
  backoff := opt value: #backoff value: #(1 50).
  ((backoff isKindOf: Array) and: [backoff size = 2]) ifFalse: [
    ^ PBValidationError signal: 'backoff must be a (min, max) pair of milliseconds'].
  low := self _micros: backoff first named: 'backoff minimum' positive: false.
  high := self _micros: backoff last named: 'backoff maximum' positive: false.
  high < low ifTrue: [^ PBValidationError signal: 'backoff must satisfy min <= max'].
  key := opt value: #authKey value: nil.
  (key isNil or: [(key isKindOf: ByteArray) and: [key size >= PBClusterFrame tagSize]]) ifFalse: [
    ^ PBValidationError signal: 'authKey is nil or a ByteArray of at least ' , PBClusterFrame tagSize printString , ' bytes'].
  ^ self basicNew
    _setMembership: membership nodeId: aNodeId
    durations: (Dictionary new
      at: #leaseDuration put: duration;
      at: #driftMargin put: margin;
      at: #requestTimeout put: request;
      at: #sendReserve put: reserve;
      at: #acquireTimeout put: (micros value: #acquireTimeout value: 30000000 value: false);
      at: #backoffLow put: low;
      at: #backoffHigh put: high;
      at: #startupGrace put: grace;
      at: #persistInterval put: (micros value: #persistInterval value: 50000 value: true);
      at: #persistLag put: (micros value: #persistLag value: 1000000 value: false);
      at: #ownerIdleRelease put: (micros value: #ownerIdleRelease value: nil value: false);
      yourself)
    authKey: key seed: (opt value: #seed value: nil)
    transport: (opt value: #transport value: nil) clock: (opt value: #clock value: nil).

PBClusterConfig >> _setMembership: aMembership nodeId: anId durations: aDictionary authKey: aKey seed: aSeed transport: aTransport clock: aClock
  "Runs once, on a fresh instance; the member must be in the membership (PBValidationError)."
  membership isNil ifFalse: [^ PBUserError signal: 'PBClusterConfig is immutable'].
  rank := aMembership rankOf: anId.
  membership := aMembership.
  nodeId := anId.
  durations := aDictionary.
  authKey := aKey copy.
  seed := aSeed.
  transport := aTransport.
  clock := aClock.
  ^ self.

PBClusterConfig >> membership
  ^ membership.

PBClusterConfig >> nodeId
  ^ nodeId.

"The index of this member's id in the sorted ids."
PBClusterConfig >> rank
  ^ rank.

PBClusterConfig >> authKey
  ^ authKey isNil ifTrue: [nil] ifFalse: [authKey copy].

PBClusterConfig >> seed
  ^ seed.

"The test seams: nil unless given."
PBClusterConfig >> transport
  ^ transport.

PBClusterConfig >> clock
  ^ clock.

"--- durations, in microseconds ---"

"The time a grant blocks other holders on the granter's timer (D)."
PBClusterConfig >> leaseDuration
  ^ durations at: #leaseDuration.

PBClusterConfig >> driftMargin
  ^ durations at: #driftMargin.

"The holder's view of its lease: D - margin."
PBClusterConfig >> belief
  ^ self leaseDuration - self driftMargin.

PBClusterConfig >> requestTimeout
  ^ durations at: #requestTimeout.

PBClusterConfig >> sendReserve
  ^ durations at: #sendReserve.

PBClusterConfig >> acquireTimeout
  ^ durations at: #acquireTimeout.

PBClusterConfig >> backoffLow
  ^ durations at: #backoffLow.

PBClusterConfig >> backoffHigh
  ^ durations at: #backoffHigh.

PBClusterConfig >> startupGrace
  ^ durations at: #startupGrace.

"How long an owner is without demand before it releases its term: D / 4."
PBClusterConfig >> idleEnd
  ^ self leaseDuration // 4.

PBClusterConfig >> persistInterval
  ^ durations at: #persistInterval.

PBClusterConfig >> persistLag
  ^ durations at: #persistLag.

"nil: off."
PBClusterConfig >> ownerIdleRelease
  ^ durations at: #ownerIdleRelease.

"--- constants of the protocol (proto_db _WAKE_SPREAD, _MIN_STRAGGLE, ...), microseconds ---"

PBClusterConfig >> wakeSpread
  ^ 3000.

PBClusterConfig >> minStraggle
  ^ 5000.

PBClusterConfig >> straggleFactor
  ^ 4.

"How long a member defers to the member a release named: 50 ms, capped by requestTimeout."
PBClusterConfig >> turnSilence
  ^ 50000 min: self requestTimeout.

PBClusterConfig >> gatherAttempts
  ^ 3.

PBClusterConfig >> retryHold
  ^ 100000.

PBClusterConfig >> retryWait
  ^ 5000.

PBClusterConfig >> permitRetries
  ^ 3.

"proto_db's DEPTH: 0, shared storage."
PBClusterConfig >> depth
  ^ 0.

"One row per timer of coordinator-protocol.rst 'Timers' that applies at DEPTH 0: { name. default.
 what it drives }, the names those of the options where there is one. A fresh Array."
PBClusterConfig class >> timerTable
  ^ #(
    #('leaseDuration' '2000 ms' 'How long a grant blocks other holders on the granter''s timer.')
    #('driftMargin' 'ceiling(2/3 x leaseDuration), the minimum' 'The holder''s belief is leaseDuration - driftMargin: a third of the promise (R78b).')
    #('renewal' 'at half the belief left' 'When the owner renews while it has demand; a failed renewal does not end the term.')
    #('permitFloor' 'a quarter of the belief left' 'No permission is issued with less left; the owner renews first.')
    #('idleEnd' 'leaseDuration / 4 without demand' 'When an owner releases its term.')
    #('ownerIdleRelease' 'nil (off)' 'Ends a term whose own threads stopped asking (R80).')
    #('requestTimeout' '250 ms' 'How long an attempt, a renewal, a recovery round or a query waits; shorter than the belief.')
    #('sendReserve' 'min(requestTimeout, belief // 4)' 'Least validity left before anything acceptable is sent; less gives a truthful retryable conflict (R121).')
    #('permissionDeadline' 'valid + requestTimeout' 'An owner without a done by then abandons the term (O6).')
    #('startupGrace' 'leaseDuration + driftMargin' 'Grants refused after a start (efficiency).')
    #('backoff' '#(1 50) ms' 'Jittered delay between lost attempts.')
    #('wakeSpread' '3 ms' 'Random spread after a release wakes a requester.')
    #('straggle' '5 ms, factor 4' 'Once a majority answered an undecided attempt, how long the rest are awaited (R39).')
    #('turnSilence' '50 ms, capped by requestTimeout' 'How long a member defers to the member a release named.')
    #('acquireTimeout' '30000 ms' 'When a permit request gives up with a timeout.')
    #('gatherAttempts' '3' 'How many times a rejoin round asks a silent member again.')
    #('persist' 'persistInterval 50 ms, persistLag 1000 ms' 'Persister passes; when any node persists another''s commits.')
    #('retryHold' 'hold 100 ms, wait 5 ms, 3 retries' 'Held retries under a permission.')) collect: [:row | row copy].
