"EXPECT: ok 13"
"PBGrantState, PBAttempt, PBLease and PBPermission (cluster/lease.st): the lease rules of
 proto_db cluster/lease.py (PeerGrants, LeaseAttempt, Lease, Permission) and the ballot check of
 coordinator.py _decide, as immutable values. Time is a parameter (microseconds): nothing here
 reads a clock. The configuration is proto_db's default (lease 2000 ms, belief 666666 us,
 startup grace 3333334 us) over the members n0, n1, n2 (ranks 0, 1, 2); a ballot carries its
 proposer's rank in its low 12 bits (4096 is rank 0's, 4097 rank 1's, 4098 rank 2's). One row per
 rule of PeerGrants.on_request and on_release; restore honours a logged promise and the label of
 the accepted root; an attempt is won at a majority of the voters and lost when one is out of
 reach; its best root is the highest in root order, and certain only when every granter knows
 a root and is not suspect, and the requester is not suspect. A lease is measured from the send
 of its request (L5): the planted case has the grants arrive 600 ms late, so a window measured
 from the win would still be valid where this one has ended."
Import from: 'protobase'.
Import from: '_check'.
| c peers cfg grace s0 g s1 busy dup ren rel ended logged restored seg root a won lost best lease late perm grantOf |
c := Check new.
peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7000].
cfg := PBClusterConfig nodeId: 'n0' peers: peers options: Dictionary new.
grace := cfg startupGrace.
s0 := PBGrantState initial: cfg now: 0.
grantOf := [:state | state activeGrant isNil
  ifTrue: [nil]
  ifFalse: [{ state activeGrant holder. state activeGrant inc. state activeGrant term. state activeGrant expiry }]].

"starting: every request is refused during the startup grace, with the grace left."
g := s0 decideRequest: 'n1' inc: 7 term: 4097 now: 1000 config: cfg.
c that: 'starting during the grace' is:
  { g verdict. g reason. g remaining. g promiseToLog. g newState highestSeen. s0 isStarting: grace - 1. s0 isStarting: grace }
  equals: { #reject. 'starting'. grace - 1000. nil. 4097. true. false }.

"a grant above grantedTop: the promise to log is the term."
g := s0 decideRequest: 'n1' inc: 7 term: 4097 now: grace config: cfg.
s1 := g newState.
c that: 'a grant above grantedTop asks for its promise to be logged' is:
  { g verdict. g reason. g remaining. g promiseToLog. g highest. s1 grantedTop. s1 highestGranted. grantOf value: s1 }
  equals: { #grant. 'granted'. 2000000. 4097. 4097. 4097. 4097. { 'n1'. 7. 4097. grace + 2000000 } }.

"busy: another holder, while the grant runs; the remaining promise is reported."
busy := s1 decideRequest: 'n2' inc: 9 term: 4098 now: grace + 500000 config: cfg.
c that: 'busy for another holder, with the remaining promise' is:
  { busy verdict. busy reason. busy remaining. busy promiseToLog. busy newState highestSeen. grantOf value: busy newState }
  equals: { #reject. 'busy'. 1500000. nil. 4098. { 'n1'. 7. 4097. grace + 2000000 } }.

"stale_term: below the highest term seen."
g := busy newState decideRequest: 'n0' inc: 3 term: 4096 now: grace + 600000 config: cfg.
c that: 'stale_term below the highest seen' is: { g verdict. g reason. g remaining. g highest }
  equals: { #reject. 'stale_term'. 0. 4098 }.

"term_taken: the same term again once its grant expired (the expiry ends it: endedTerm); and
 bad_ballot: a term that is not of the requester's rank, which changes nothing."
g := s1 decideRequest: 'n1' inc: 7 term: 4097 now: grace + 2000000 config: cfg.
ended := s1 decideRequest: 'n2' inc: 9 term: 4097 now: grace + 10 config: cfg.
c that: 'term_taken after the expiry, and bad_ballot' is:
  { g verdict. g reason. g endedTerm. grantOf value: g newState. ended reason. ended newState highestSeen. ended endedTerm }
  equals: { #reject. 'term_taken'. 4097. nil. 'bad_ballot'. 4097. 0 }.

"renew: the active grant is extended to now + D, even after a refused higher request; a plain
 duplicate grants again without extending the promise."
ren := busy newState renew: 'n1' inc: 7 term: 4097 now: grace + 600000 config: cfg.
dup := s1 decideRequest: 'n1' inc: 7 term: 4097 now: grace + 600000 config: cfg.
c that: 'a renew extends the active grant; a duplicate does not' is:
  { ren verdict. ren remaining. (grantOf value: ren newState) last. dup verdict. dup remaining. (grantOf value: dup newState) last }
  equals: { #grant. 2000000. grace + 2600000. #grant. 1400000. grace + 2000000 }.

"release: frees the grant and closes the term here."
rel := s1 release: 'n1' inc: 7 term: 4097 now: grace + 100.
c that: 'a release frees the grant and closes the term' is:
  { grantOf value: rel first. rel last.
    (rel first decideRequest: 'n1' inc: 7 term: 4097 now: grace + 200 config: cfg) reason.
    (rel first decideRequest: 'n2' inc: 9 term: 4098 now: grace + 200 config: cfg) reason }
  equals: { nil. 0. 'term_taken'. 'granted' }.

"restore: the logged promise and the accepted root's label count as granted."
logged := PBLoggedRoots accepted: (PBLabeledRoot label: 8193 record: nil) committed: nil promise: 4098 top: 8193
  rejoined: true dataEntryCount: 0 entries: #().
restored := s0 restore: logged.
c that: 'restore refuses at and below the logged promise' is:
  { restored grantedTop. restored highestGranted. restored highestSeen.
    (restored decideRequest: 'n1' inc: 7 term: 8193 now: grace config: cfg) reason.
    (restored decideRequest: 'n1' inc: 7 term: 4097 now: grace config: cfg) reason.
    (restored decideRequest: 'n1' inc: 7 term: 12289 now: grace config: cfg) reason }
  equals: { 8193. 8193. 8193. 'term_taken'. 'stale_term'. 'granted' }.

"attempts: won at needed grants, lost when a majority is out of reach."
a := PBAttempt term: 4097 rid: 1 sentAt: 100 voters: 3.
won := (a withGrant: 'n1' root: nil committed: nil certain: true) withGrant: 'n0' root: nil committed: nil certain: true.
lost := ((a withReject: 'n0' reason: 'busy' highest: 4096 remaining: 700) withReject: 'n2' reason: 'starting' highest: 8194 remaining: 900)
  withGrant: 'n2' root: nil committed: nil certain: true.
c that: 'an attempt is won at needed grants, lost past reach' is:
  { a needed. a state. (a withGrant: 'n1' root: nil committed: nil certain: true) state. won state.
    lost state. lost busyRemaining. lost highestSeen }
  equals: { 2. #pending. #pending. #won. #lost. 900. 8194 }.

"best root: the highest in root order, the requester's own root included."
seg := [:last | ByteArray withAll: ((1 to: 16) collect: [:i | i = 16 ifTrue: [last] ifFalse: [0]])].
root := [:label :epoch | PBLabeledRoot label: label record: (PBRootRecord segment: (seg value: epoch) offset: 26 epoch: epoch)].
a := PBAttempt term: 8193 rid: 2 sentAt: 100 voters: 3.
best := (a withGrant: 'n0' root: (root value: 4096 value: 9) committed: (root value: 4096 value: 8) certain: true)
  withGrant: 'n2' root: (root value: 4098 value: 3) committed: nil certain: true.
c that: 'the best root is the highest in root order' is:
  { (best bestRoot: nil suspect: false) first key. (best bestRoot: nil suspect: false) last.
    (best bestRoot: (root value: 4098 value: 4) suspect: false) first key.
    (best committedRoots collect: [:r | r key]) }
  equals: { (root value: 4098 value: 3) key. true. (root value: 4098 value: 4) key. { (root value: 4096 value: 8) key } }.

"uncertain: a granter knows no root, or one is suspect, or the requester is."
c that: 'uncertain when a granter reports no root or a suspicion' is:
  ({ ((a withGrant: 'n0' root: (root value: 4096 value: 9) committed: nil certain: true)
       withGrant: 'n2' root: nil committed: nil certain: true) bestRoot: nil suspect: false.
     ((a withGrant: 'n0' root: (root value: 4096 value: 9) committed: nil certain: true)
       withGrant: 'n2' root: (root value: 4096 value: 9) committed: nil certain: false) bestRoot: nil suspect: false.
     best bestRoot: nil suspect: true.
     (a withGrant: 'n0' root: nil committed: nil certain: true) bestRoot: nil suspect: false }
   collect: [:x | { x first isNil ifTrue: [nil] ifFalse: [x first key]. x last }])
  equals: { { (root value: 4096 value: 9) key. false }. { (root value: 4096 value: 9) key. false }.
    { (root value: 4098 value: 3) key. false }. { nil. false } }.

"L5: the window runs from the send. The grants arrive 600 ms after the send; from the win the
 lease would still be valid at sentAt + belief."
a := PBAttempt term: 4097 rid: 3 sentAt: 1000 voters: 3.
late := 1000 + 600000.
lease := PBLease term: a term validUntil: a sentAt + cfg belief root: nil certain: false.
c that: 'a lease is measured from the send, not the win' is:
  { lease isValidAt: 1000 + cfg belief - 1. lease isValidAt: 1000 + cfg belief. lease remainingAt: 1000 + cfg belief - 1.
    lease remainingAt: late + cfg belief. late + cfg belief - 1 > lease validUntil }
  equals: { true. false. 1. 0. true }.

"a permission: valid from the request's send for the owner's valid; after is nil at depth 0."
perm := PBPermission term: 4097 seq: 2 rid: 5 owner: 'n1' root: (root value: 4096 value: 9) certain: true sentAt: 1000 valid: 300000.
c that: 'a permission is valid from the send of its request' is:
  { perm validUntil. perm isValidAt: 300999. perm isValidAt: 301000. perm after. perm seq. perm rid. perm owner. perm isCertain.
    (PBPermission term: 4097 seq: 3 rid: 6 owner: 'n1' root: nil certain: true sentAt: 0 valid: 1) isCertain }
  equals: { 301000. true. false. nil. 2. 5. 'n1'. true. false }.
c report displayNl.
