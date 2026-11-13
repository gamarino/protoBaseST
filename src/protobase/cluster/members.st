"-- cluster/members.st: the static membership of a cluster, its ranks, voters and ballots --

The values every member computes like the others (ProtoBase format spec, 'Values a member must
compute'; proto_db cluster/coordinator.py Peer, _voter_set, ballot_after, the voter-set
fingerprint), so that two members configured alike agree on them byte for byte.

  PBPeer        a member: its node id (a non-empty String), the host and the port its transport
                listens on (proto_db Peer)
  PBMembership  the members of a cluster (static: D54, no dynamic membership). The rank of a
                member is the index of its id in the ids sorted in code point order; ballots
                (lease terms) carry the proposer's rank in their low 12 bits (rankBits), so a
                cluster has at most 4096 members. The voters (default: the first three ids,
                every member of a smaller cluster; an explicit set: distinct members, odd and at
                least three when the cluster has three or more) order roots; a majority is
                V // 2 + 1 of them. The fingerprint (vs) is the CRC-32 of the UTF-8 bytes of the
                sorted voter ids joined with ','.

Every value here is immutable: built once by its class-side constructor."

Import from: 'protobase/errors'.

"=== PBPeer ================================================================="

Object subclass: #PBPeer instanceVariableNames: 'nodeId host port'.

"A member of a cluster, as proto_db's Peer(node_id, host, port): the id a non-empty String (a
 Symbol is kept as its String), the host a String, the port an Integer from 0 to 65535;
 PBValidationError otherwise."
PBPeer class >> nodeId: anId host: aHost port: aPort
  ((anId isString and: [anId notEmpty]) and: [aHost isString
      and: [aPort isInteger and: [aPort between: 0 and: 65535]]]) ifFalse: [
    ^ PBValidationError signal: 'Invalid peer ' , { anId. aHost. aPort } printString
      , ': a peer is a non-empty String id, a String host and a port from 0 to 65535'].
  ^ self basicNew _setNodeId: anId asString host: aHost asString port: aPort.

PBPeer >> _setNodeId: anId host: aHost port: aPort
  "Runs once, on a fresh instance."
  nodeId isNil ifFalse: [^ PBUserError signal: 'PBPeer is immutable'].
  nodeId := anId.
  host := aHost.
  port := aPort.
  ^ self.

PBPeer >> nodeId
  ^ nodeId.

PBPeer >> host
  ^ host.

PBPeer >> port
  ^ port.

PBPeer >> = anObject
  ^ (anObject isClassObject not and: [anObject class == PBPeer])
    and: [nodeId = anObject nodeId and: [host = anObject host and: [port = anObject port]]].

PBPeer >> hash
  ^ nodeId hash.

PBPeer >> printOn: aStream
  aStream nextPutAll: 'PBPeer('; print: nodeId; nextPutAll: ', '; print: host; nextPutAll: ', '; print: port; nextPut: $).

"=== PBMembership ==========================================================="

Object subclass: #PBMembership instanceVariableNames: 'peers ids voters fingerprint'.

"The low bits of a ballot that hold the proposer's rank (proto_db RANK_BITS)."
PBMembership class >> rankBits
  ^ 12.

"The most members a cluster has (proto_db MAX_MEMBERS, 1 << rankBits)."
PBMembership class >> maxMembers
  ^ 1 bitShift: self rankBits.

"The term increment of a refound (proto_db REFOUND_TERM_STEP, 2^44): room for 2^32 ballots of
 every rank, and a multiple of maxMembers."
PBMembership class >> refoundStep
  ^ 1 bitShift: 44.

"The smallest ballot of proposer rank r above aFloor (proto_db ballot_after): the term whose
 low rankBits bits are r. Floor division, as Python's //."
PBMembership class >> ballotAfter: aFloor rank: r
  ^ ((aFloor - r) // self maxMembers + 1) * self maxMembers + r.

"The membership of the peers anArray (PBPeers, in any order) with the voters anArrayOrNil (nil:
 the default). PBValidationError for an empty list, an element that is not a PBPeer, duplicate
 ids, more than maxMembers members, or a voter set _voter_set refuses."
PBMembership class >> peers: anArray voters: anArrayOrNil
  | list sorted |
  (anArray isCollection and: [anArray isString not]) ifFalse: [
    ^ PBValidationError signal: 'PBMembership: the peers are a collection of PBPeers, not ' , anArray printString].
  list := anArray asArray.
  list isEmpty ifTrue: [^ PBValidationError signal: 'PBMembership: a cluster has at least one member'].
  (list allSatisfy: [:p | p isClassObject not and: [p class == PBPeer]]) ifFalse: [
    ^ PBValidationError signal: 'PBMembership: the peers are PBPeers, not ' , list printString].
  "Code point order, as Python's sorted: protoST compares Strings by code point."
  sorted := ((list collect: [:p | p nodeId]) asSortedCollection: [:a :b | a <= b]) asArray.
  2 to: sorted size do: [:i |
    (sorted at: i - 1) = (sorted at: i) ifTrue: [^ PBValidationError signal: 'Peer ids must be unique']].
  sorted size > self maxMembers ifTrue: [
    ^ PBValidationError signal: 'A cluster has at most ' , self maxMembers printString , ' members'].
  ^ self basicNew _setPeers: list copy ids: sorted voters: (self _voterSet: sorted voters: anArrayOrNil).

"The sorted voter ids (proto_db _voter_set): anArrayOrNil validated against the sorted member
 ids aRing, or the default (the first three, every member of a smaller cluster)."
PBMembership class >> _voterSet: aRing voters: anArrayOrNil
  | chosen |
  anArrayOrNil isNil ifTrue: [^ aRing copyFrom: 1 to: (aRing size min: 3)].
  (anArrayOrNil isCollection and: [anArrayOrNil isString not]) ifFalse: [
    ^ PBValidationError signal: 'voters must be a collection of member ids'].
  chosen := anArrayOrNil asArray.
  ((chosen asSet size = chosen size) and: [chosen allSatisfy: [:v | aRing includes: v]]) ifFalse: [
    ^ PBValidationError signal: 'voters must be distinct member ids, got ' , chosen printString].
  aRing size < 3
    ifTrue: [chosen size = aRing size ifFalse: [
      ^ PBValidationError signal: 'A cluster of fewer than three members has every member as a voter']]
    ifFalse: [(chosen size < 3 or: [chosen size even]) ifTrue: [
      ^ PBValidationError signal: 'The voter set must have an odd number of at least three members, got '
        , chosen size printString]].
  ^ ((chosen collect: [:v | v asString]) asSortedCollection: [:a :b | a <= b]) asArray.

PBMembership >> _setPeers: aPeerArray ids: anIdArray voters: aVoterArray
  "Runs once, on a fresh instance."
  peers isNil ifFalse: [^ PBUserError signal: 'PBMembership is immutable'].
  peers := aPeerArray.
  ids := anIdArray.
  voters := aVoterArray.
  fingerprint := (',' join: aVoterArray) utf8Encoded crc32.
  ^ self.

"The member ids in code point order (a fresh Array)."
PBMembership >> ids
  ^ ids copy.

"The rank of the member anId: its index (from 0) in ids. PBValidationError for an id that is
 not a member."
PBMembership >> rankOf: anId
  | index |
  index := ids indexOf: anId.
  index = 0 ifTrue: [^ PBValidationError signal: 'Node ' , anId printString , ' is not in the peer list'].
  ^ index - 1.

"The voter ids in code point order (a fresh Array)."
PBMembership >> voters
  ^ voters copy.

PBMembership >> isVoter: anId
  ^ voters includes: anId.

"The number of voters that is a majority of them (proto_db majority: V // 2 + 1)."
PBMembership >> majority
  ^ voters size // 2 + 1.

"The voter-set fingerprint (vs): the CRC-32 of the UTF-8 of the voter ids joined with ','."
PBMembership >> fingerprint
  ^ fingerprint.

"The PBPeer of the member anId; PBValidationError for an id that is not a member."
PBMembership >> peerNamed: anId
  ^ peers detect: [:p | p nodeId = anId]
    ifNone: [PBValidationError signal: 'Node ' , anId printString , ' is not in the peer list'].
