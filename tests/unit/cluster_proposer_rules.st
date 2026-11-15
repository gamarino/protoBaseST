"EXPECT: ok 33"
"The proposer's rules (cluster/proposer.st) called directly, one rule per check (proto_db
 coordinator.py permit, _become_owner, _open_attempt, _on_reply, _close_attempt, _back_off,
 release, _own_loop_body, _renew, the fairness hints).
 (1) ballotFor: is the ballot of the node's rank above the highest term its acceptor saw, the
 hint and the labels of its accepted and committed roots. (2) microsFromWire: is the exact
 inverse of wireSeconds:. (3) A permit wanted waits while the acceptor has not reported or
 rejoins (a timer at the waiter's deadline, acquireTimeout), then opens an attempt: its own request to its own acceptor, the request with vs to the
 other voters, a timer of requestTimeout. (4) The own vote travels in the acceptor step's vote;
 a majority with it wins: an ownership whose lease ends at the send + the belief, its waiter
 issued the first permission at once (owner.st, O1), counted acquired and ownerships. (5) A reply of another incarnation is counted
 stale_replies and never recorded; a learner's reply is never recorded; every reply raises the
 hint. (6) A discarded own grant is the refusal promise_failed. (7) A majority of replies to an
 undecided attempt waits max(minStraggle, straggleFactor x elapsed) for the rest (R39). (8) A
 lost attempt cancels (held false, certain false, more true) to every other member and its own
 acceptor, then backs off for [low / 2, low) at the first failure, extended to the refusals'
 busy remaining in microseconds; a cancel ends only the busy extension, a held release ends it
 all. (9) An owner with demand renews at half the belief left; a won renewal extends the lease.
 (10) Without demand for idleEnd the owner releases (held, certain, next nil, more false). (11) A
 release names the member seen waiting longest (want, request, cancel), more when local waiters
 remain, and the releaser defers to it until turnSilence when its request is not seen; a member
 nobody queues says want before it defers. (12) The named member takes its turn at once (no spread) and
 counts turns_taken. (13) ownerIdleRelease ends a term without local demand
 (terms_released_idle_local). (14) The owner hint is learnt from a renewal, not from a request.
 (15) A reject whose remaining is +Infinity (a valid float64 the wire accepts) is a lost round
 busy for leaseDuration, as proto_db's min(busy_remaining, D), not an error. (16) A majority of
 grants dispatched at the send + the belief or later (a late timer, a slow dispatcher) is not a
 win: a lost round, a cancel, no ownership (L5). (17) Likewise a renewal: counted
 renewal_failures, the lease not extended. (18) The plant PlantLateWin (the win check t <
 validUntil dropped) fails checks 16 and 17. (19) A waiter that arrives while the lease has
 lapsed during a renewal joins the queue of the renewed lease and is issued its permission
 (proto_db permit loops back to the owner). The seams that end the demand clear the queue and the
 pipeline of issued permissions (owner.st). (25-26) The acceptor's decision of this node's own
 request signalling a PBDBError (PBOwnStepFailed) rejects only the oldest waiter, proto_db's
 permit() caller driving the acquisition; the attempt is closed with its cancel but is no lost
 round: nothing counted, no back-off, the next waiter opens a new acquisition at once (failures 0)
 above the failed term; a lone waiter's rejection ends the acquisition, the cancel sent; a failure
 of that attempt's cancel rejects nobody; a late request failure changes nothing. (27-28) A
 failure of the own cancel of the last lost attempt rejects the oldest waiter once (proto_db
 _close_attempt raises it to the driving caller); a held release, a cancel of another term and
 a repeat change nothing; a lone waiter's rejection ends the acquisition; a failure arriving while
 the next attempt is open keeps that attempt for the other waiters, and when it rejects the last
 waiter it closes that attempt with its cancel (no lost round) before the acquisition ends. (29) A failure of the
 own renew of the current renewal ends the ownership without a release, abandoned and fenced
 (proto_db _own_loop); a late one changes nothing."
Import from: 'protobase'.
Import from: '_check'.

"The plant of checks 16-17: a majority wins whenever it comes, the win check t < validUntil
 dropped (CC13)."
PBCoordinatorCore subclass: #PlantLateWin.

PlantLateWin >> _inTime: anAttempt in: s now: t
  ^ true.

| c core peers config three four vs marker logged view stateIn ready step eff sends msg granted reject
  request s own att t0 pair sim owned renewing late lateRenewal plant stats lapsed rel want hintsAfter grantAfter
  renewMsg toAcceptor failed settled stat phase two req cancel lost lone other held opened releases |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :someIds :opts | PBClusterConfig nodeId: id peers: (peers value: someIds) options: opts].
three := #('n0' 'n1' 'n2').
four := #('n0' 'n1' 'n2' 'n3').
vs := (config value: 'n1' value: three value: Dictionary new) membership fingerprint.
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
"The acceptor state of anId over appends, started at 0 with no startup grace."
view := [:id :someIds :appends | PBAcceptorState config: (config value: id value: someIds value: (Dictionary new at: #startupGrace put: 0; yourself))
  logged: (logged value: appends) now: 0].
"A dispatcher state of anId (inc 5) whose acceptor reported the view of appends."
stateIn := [:id :someIds :appends :opts | (PBNodeState config: (config value: id value: someIds value: opts) inc: 5)
  with: { #acceptorView -> (view value: id value: someIds value: appends) }].
ready := [:id | stateIn value: id value: three value: { marker } value: Dictionary new].
eff := [:aStep | aStep effects collect: [:e | e class name]].
"The message of aStep's first PBToAcceptor effect, nil when there is none."
toAcceptor := [:aStep | | e | e := aStep effects detect: [:x | x isKindOf: PBToAcceptor] ifNone: [nil].
  e isNil ifTrue: [nil] ifFalse: [e event message]].
sends := [:aStep | (aStep effects select: [:e | e isKindOf: PBSend]) collect: [:e | { e to. e message type }]].
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
granted := [:from :term :rid :inc | msg value: 'grant' value: from value: { 'term' -> term. 'rid' -> rid. 'inc' -> inc.
  'root' -> nil. 'committed' -> nil. 'certain' -> true }].
reject := [:from :term :rid :inc :reason :highest :remaining | msg value: 'reject' value: from value: { 'term' -> term.
  'rid' -> rid. 'inc' -> inc. 'root' -> nil. 'certain' -> true. 'reason' -> reason. 'highest' -> highest. 'remaining' -> remaining }].
"Dispatches anEvent in s at t; answers the step."
step := [:anEvent :aState :t | core dispatch: anEvent in: aState now: t].
t0 := 1000000.

"(1) The ballot."
s := (ready value: 'n1') with: { #hints -> ((PBHints seed: 1) with: { #hint -> 9000 }) }.
c that: 'ballotFor: the ballot of the rank above the acceptor''s highest, the hint and the root labels'
  is: { core ballotFor: (ready value: 'n1').
    core ballotFor: s.
    core ballotFor: (stateIn value: 'n2' value: three value: { marker. PBLogAppend kind: #accepted label: 20000
      root: (PBRootRecord segment: (ByteArray new: 16) offset: 1 epoch: 1) sync: true } value: Dictionary new).
    core ballotFor: (((ready value: 'n1') with: { #acceptorView -> (core accept: (request := msg value: 'request' value: 'n0'
      value: { 'term' -> 12288. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }) in: (view value: 'n1' value: three value: { marker }) now: 0) state })) }
  equals: { 1. 12289. 20482. 12289 }.

"(2) The inbound remaining."
c that: 'microsFromWire: inverts wireSeconds: (to 2^51; near 2^52 one off, a documented limit)'
  is: { (#(0 1 7 999999 1000000 1333334 3333334 123456789 2251799813685247) collect: [:m |
      (PBCoordinatorCore microsFromWire: (PBCoordinatorCore wireSeconds: m)) = m]) asSet.
    (PBCoordinatorCore microsFromWire: (PBCoordinatorCore wireSeconds: 4375678581963491)) - 4375678581963491 }
  equals: { #(true) asSet. 1 }.

"(3) A permit wanted."
pair := step value: (PBPermitWanted waiter: #w1) value: (PBNodeState config: (config value: 'n1' value: three value: Dictionary new) inc: 5) value: t0.
att := step value: (PBPermitWanted waiter: #w1) value: (ready value: 'n1') value: t0.
c that: 'a permit wanted waits for the acceptor''s report, then opens an attempt'
  is: { eff value: pair. (pair effects collect: [:e | e after]). pair state proposer phase. pair state waiters.
    eff value: att. sends value: att. ((att effects at: 2) event message at: 'term').
    ((att effects at: 3) message at: 'vs') = vs. (att effects last) after. att state proposer phase. att state proposer attempt term }
  equals: { #(#PBTimer). #(30000000). #rejoin. #(#w1). #(#PBCount #PBToAcceptor #PBSend #PBSend #PBTimer). #(#('n0' 'request') #('n2' 'request')).
    1. true. 250000. #attempt. 1 }.

"(4) The own vote in the step, then a peer's grant: the win."
s := att state.
own := core accept: (att effects at: 2) event in: (view value: 'n1' value: three value: { marker }) now: t0.
pair := step value: (PBAcceptorDecided step: own) value: s value: t0 + 3000.
s := (step value: (granted value: 'n2' value: 1 value: 1 value: 5) value: pair state value: t0 + 4000) state.
c that: 'the own vote travels in the step; a majority wins an ownership valid from the send'
  is: { own reply. own vote type. pair state proposer attempt replies. s proposer. s ownership term.
    s ownership lease validUntil. s ownership queue. s ownership pipeline collect: [:e | { e node. e seq }]. s waiters. s hints ownerNode }
  equals: { #(). 'grant'. 1. nil. 1. t0 + 666666. #(). #(#('n1' 1)). #(). 'n1' }.

"(5) Stale and learner replies."
s := (step value: (PBPermitWanted waiter: #w1) value: (stateIn value: 'n0' value: four value: { marker } value: Dictionary new) value: t0) state.
pair := step value: (granted value: 'n1' value: 4096 value: 1 value: 6) value: s value: t0.
c that: 'a reply of another incarnation is counted and dropped; a learner''s reply is not a vote; replies raise the hint'
  is: { (pair effects collect: [:e | e stat]). pair state proposer attempt replies. pair state hints hint.
    (step value: (reject value: 'n3' value: 4096 value: 1 value: 5 value: 'learner' value: 9999 value: 0) value: s value: t0) state proposer attempt replies.
    (step value: (reject value: 'n3' value: 4096 value: 1 value: 5 value: 'learner' value: 9999 value: 0) value: s value: t0) state hints hint }
  equals: { #('stale_replies'). 0. 4096. 0. 9999 }.

"(6) A discarded own grant."
s := att state.
pair := step value: (PBAcceptorDiscarded step: own reason: 'disk full') value: s value: t0 + 3000.
c that: 'a discarded own grant is the refusal promise_failed'
  is: { pair state proposer attempt replies. pair state proposer attempt state.
    ((step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: pair state value: t0 + 4000) effects
      select: [:e | e isKindOf: PBCount]) collect: [:e | e stat] }
  equals: { 1. #pending. #('lost_attempts') }.

"(7) Stragglers."
pair := step value: (PBAcceptorDecided step: own) value: att state value: t0 + 2000.
pair := step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: pair state value: t0 + 2000.
s := (step value: (PBAcceptorDecided step: own) value: att state value: t0 + 1000) state.
c that: 'a majority of replies to an undecided attempt waits for the stragglers'
  is: { pair state proposer attempt state. pair state proposer straggling. (pair effects select: [:e | e isKindOf: PBTimer]) collect: [:e | e after].
    ((step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: s value: t0 + 1000) effects
      select: [:e | e isKindOf: PBTimer]) collect: [:e | e after] }
  equals: { #pending. true. #(8000). #(5000) }.

"(8) A lost attempt: the cancel, the back-off, what ends it."
s := (step value: (PBTimerFired token: pair state proposer token event: #proposer) value: pair state value: t0 + 10000) state.
pair := step value: (PBTimerFired token: pair state proposer token event: #proposer) value: pair state value: t0 + 10000.
c that: 'a lost attempt cancels to every member and its own acceptor, then backs off to the busy remaining'
  is: { (pair effects select: [:e | e isKindOf: PBSend]) collect: [:e | { e to. e message at: 'held'. e message at: 'certain'. e message at: 'more' }].
    ([:m | m isNil ifTrue: [nil] ifFalse: [m type]] value: (toAcceptor value: pair)). s proposer phase.
    s proposer backoffEnd - (t0 + 10000) between: 500 and: 999. s proposer busyEnd - (t0 + 10000) }
  equals: { #(#('n0' false false true) #('n2' false false true)). 'release'. #backoff. true. 500000 }.
pair := step value: (PBTimerFired token: s proposer token event: #proposer) value: s value: s proposer backoffEnd.
c that: 'a cancel ends only the busy extension; a held release ends the back-off'
  is: { pair state proposer phase.
    (step value: (msg value: 'release' value: 'n0' value: { 'term' -> 1. 'inc' -> 1. 'root' -> nil. 'committed' -> nil.
      'certain' -> false. 'held' -> false. 'next' -> nil. 'more' -> true }) value: s value: s proposer backoffEnd - 100) state proposer phase.
    (step value: (msg value: 'release' value: 'n0' value: { 'term' -> 1. 'inc' -> 1. 'root' -> nil. 'committed' -> nil.
      'certain' -> false. 'held' -> false. 'next' -> nil. 'more' -> true }) value: pair state value: s proposer backoffEnd + 100) state proposer phase.
    (step value: (msg value: 'release' value: 'n0' value: { 'term' -> 1. 'inc' -> 1. 'root' -> nil. 'committed' -> nil.
      'certain' -> true. 'held' -> true. 'next' -> nil. 'more' -> false }) value: s value: s proposer backoffEnd - 100) state proposer phase }
  equals: { #busy. #backoff. #spread. #spread }.

"(9-10) Owning: renewal at half the belief, idle end."
s := (step value: (PBAcceptorDecided step: own) value: att state value: t0 + 3000) state.
s := (step value: (granted value: 'n2' value: 1 value: 1 value: 5) value: s value: t0 + 4000) state.
s := s with: { #ownership -> (s ownership with: { #queue -> #(). #pipeline -> #() }) }.
owned := s.
pair := step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 333334.
renewing := pair state.
renewMsg := (pair effects at: 1) event message.
sim := step value: (granted value: 'n0' value: 1 value: pair state ownership renewal rid value: 5) value: pair state value: t0 + 340000.
sim := step value: (granted value: 'n2' value: 1 value: pair state ownership renewal rid value: 5) value: sim state value: t0 + 341000.
c that: 'an owner with demand renews at half the belief left; a won renewal extends the lease'
  is: { (step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 333332) state ownership renewal.
    sends value: pair. eff value: pair. sim effects collect: [:e | e class name]. sim state ownership lease validUntil. sim state ownership renewal }
  equals: { nil. #(#('n0' 'renew') #('n2' 'renew')). #(#PBToAcceptor #PBSend #PBSend #PBTimer). #(#PBCount #PBTimer). t0 + 333334 + 666666. nil }.
pair := step value: (PBTimerFired token: sim state ownership token event: #owner) value: sim state value: t0 + 504001.
c that: 'without demand for idleEnd the owner releases'
  is: { pair state ownership. (pair effects select: [:e | e isKindOf: PBSend]) collect: [:e | | m | m := e message.
      { e to. m at: 'term'. m at: 'held'. m at: 'certain'. m at: 'next'. m at: 'more' }].
    ([:m | m isNil ifTrue: [nil] ifFalse: [m at: 'held']] value: (toAcceptor value: pair)) }
  equals: { nil. #(#('n0' 1 true true nil false) #('n2' 1 true true nil false)). true }.

"(11) The turn named, the deferral, want."
s := (step value: (msg value: 'want' value: 'n2' value: #()) value: sim state value: t0 + 400000) state.
s := (step value: (msg value: 'request' value: 'n0' value: { 'term' -> 8192. 'rid' -> 3. 'inc' -> 1. 'vs' -> vs }) value: s value: t0 + 410000) state.
s := (step value: (PBPermitWanted waiter: #w2) value: s value: t0 + 420000) state.
"The waiter waits for the next term (a test seam: out of the queue, among the waiters)."
s := s with: { #ownership -> (s ownership with: { #queue -> #(). #pipeline -> #() }). #waiters -> #(#w2) }.
pair := step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 920001.
c that: 'a release names the member waiting longest, says more, and its releaser defers, saying want'
  is: { (pair effects select: [:e | e isKindOf: PBSend]) collect: [:e | { e to. e message type. (e message type = 'release') ifTrue: [e message at: 'next'] ifFalse: [nil].
      (e message type = 'release') ifTrue: [e message at: 'more'] ifFalse: [nil] }].
    pair state proposer phase. pair state hints turn. (pair effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
    (pair effects select: [:e | e isKindOf: PBTimer]) collect: [:e | e after].
    (step value: (PBTimerFired token: pair state proposer token event: #proposer) value: pair state value: t0 + 970001) state proposer phase.
    sends value: (step value: (PBPermitWanted waiter: #w9) value: (pair state with: { #proposer -> nil. #waiters -> #().
      #hints -> (pair state hints with: { #registered -> false }) }) value: t0 + 930000) }
  equals: { #(#('n0' 'release' 'n2' true) #('n2' 'release' 'n2' true)).
    #turn. { 'n2'. t0 + 920001. nil }. #('turns_named' 'deferrals'). #(50000). #attempt. #(#('n0' 'want') #('n2' 'want')) }.

"(12) The named member takes its turn."
s := (step value: (PBPermitWanted waiter: #w3) value: (ready value: 'n2') value: t0) state.
s := (step value: (reject value: 'n0' value: 2 value: 1 value: 5 value: 'busy' value: 1 value: 1.0) value: s value: t0) state.
s := (step value: (reject value: 'n1' value: 2 value: 1 value: 5 value: 'busy' value: 1 value: 1.0) value: s value: t0) state.
pair := step value: (msg value: 'release' value: 'n1' value: { 'term' -> 1. 'inc' -> 1. 'root' -> nil. 'committed' -> nil.
  'certain' -> true. 'held' -> true. 'next' -> 'n2'. 'more' -> true }) value: s value: t0 + 1000.
c that: 'the named member asks at once and counts turns_taken'
  is: { s proposer phase. pair state proposer phase. (pair effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
    pair state hints myTurn. pair state hints waiting collect: [:e | e first] }
  equals: { #backoff. #attempt. #('attempts' 'turns_taken'). false. #('n1') }.

"(13) ownerIdleRelease."
s := (step value: (PBPermitWanted waiter: #w1) value: (stateIn value: 'n1' value: three value: { marker }
  value: (Dictionary new at: #ownerIdleRelease put: 100; yourself)) value: t0) state.
s := (step value: (PBAcceptorDecided step: (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'n1' fields: {
  'term' -> 1. 'rid' -> 1. 'inc' -> 5. 'vs' -> vs })) in: (view value: 'n1' value: three value: { marker }) now: t0)) value: s value: t0) state.
s := (step value: (granted value: 'n0' value: 1 value: 1 value: 5) value: s value: t0) state.
s := s with: { #ownership -> (s ownership with: { #queue -> #(). #pipeline -> #() }) }.
pair := step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 100001.
c that: 'ownerIdleRelease ends a term without local demand'
  is: { (s ownership token) notNil. pair state ownership. (pair effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat] }
  equals: { true. nil. #('terms_released_idle_local') }.

"(13b) Without ownerIdleRelease (the default nil) the same term is kept at the same instant
 (proto_db test_without_owner_idle_release_a_requested_term_is_kept)."
s := (step value: (PBPermitWanted waiter: #w1) value: (stateIn value: 'n1' value: three value: { marker } value: Dictionary new) value: t0) state.
s := (step value: (PBAcceptorDecided step: (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'n1' fields: {
  'term' -> 1. 'rid' -> 1. 'inc' -> 5. 'vs' -> vs })) in: (view value: 'n1' value: three value: { marker }) now: t0)) value: s value: t0) state.
s := (step value: (granted value: 'n0' value: 1 value: 1 value: 5) value: s value: t0) state.
s := s with: { #ownership -> (s ownership with: { #queue -> #(). #pipeline -> #() }) }.
pair := step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 100001.
c that: 'without ownerIdleRelease a term serving no local demand is kept'
  is: { s config ownerIdleRelease. pair state ownership notNil. ((pair effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]) includes: 'terms_released_idle_local' }
  equals: { nil. true. false }.

"(14) The owner hint."
s := ready value: 'n1'.
c that: 'the owner hint is learnt from a renewal, not from a request'
  is: { ((step value: (msg value: 'request' value: 'n2' value: { 'term' -> 8194. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }) value: s value: t0) state hints) ownerTerm.
    ((step value: (msg value: 'renew' value: 'n2' value: { 'term' -> 8194. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }) value: s value: t0) state hints) ownerNode }
  equals: { 0. 'n2' }.

"(15) Two rejects whose remaining is +Infinity."
pair := step value: (reject value: 'n0' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: Float infinity) value: att state value: t0 + 4000.
pair := step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: Float infinity) value: pair state value: t0 + 4000.
c that: 'a reject with remaining +Infinity is a lost round busy for leaseDuration'
  is: { PBCoordinatorCore microsFromWire: Float infinity. (pair effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
    pair state proposer phase. pair state proposer busyEnd - (t0 + 4000) }
  equals: { PBCoordinatorCore wireMicrosCap. #('lost_attempts'). #backoff. 2000000 }.

"(16-18) A majority after the belief: of an attempt, of a renewal, and the plant."
late := [:rules :t | | p |
  p := rules dispatch: (PBAcceptorDecided step: own) in: att state now: t0 + 3000.
  p := rules dispatch: (granted value: 'n2' value: 1 value: 1 value: 5) in: p state now: t.
  { p state ownership isNil. (p effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
    (p effects select: [:e | e isKindOf: PBSend]) collect: [:e | { e to. e message type.
      e message type = 'release' ifTrue: [e message at: 'held'] ifFalse: [nil] }] }].
c that: 'a majority of grants at the send + the belief or later is not a win'
  is: { late value: core value: t0 + 666666. (late value: core value: t0 + 900000) first }
  equals: { { true. #('lost_attempts'). #(#('n0' 'release' false) #('n2' 'release' false)) }. true }.
lateRenewal := [:rules :t | | p |
  p := rules dispatch: (granted value: 'n0' value: 1 value: renewing ownership renewal rid value: 5) in: renewing now: t.
  p := rules dispatch: (granted value: 'n2' value: 1 value: renewing ownership renewal rid value: 5) in: p state now: t.
  stats := (p effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
  { stats includes: 'renewals'. stats includes: 'renewal_failures'.
    p state ownership isNil or: [p state ownership lease validUntil = (t0 + 666666)] }].
c that: 'a renewal won after its belief is a renewal failure and extends nothing'
  is: (lateRenewal value: core value: t0 + 333334 + 666666) equals: #(false true true).
plant := PlantLateWin new.
c that: 'the plant PlantLateWin fails checks 16 and 17'
  is: { ((late value: plant value: t0 + 666666) at: 2) includes: 'acquired'. (lateRenewal value: plant value: t0 + 333334 + 666666) first }
  equals: #(true true).

"(19) A waiter during a lapsed lease joins the renewed lease's queue."
s := stateIn value: 'n1' value: three value: { marker } value: (Dictionary new at: #requestTimeout put: 600; yourself).
pair := step value: (PBPermitWanted waiter: #w1) value: s value: t0.
s := (step value: (PBAcceptorDecided step: (core accept: (pair effects at: 2) event
  in: (view value: 'n1' value: three value: { marker }) now: t0)) value: pair state value: t0 + 1000) state.
s := (step value: (granted value: 'n2' value: 1 value: 1 value: 5) value: s value: t0 + 2000) state.
s := s with: { #ownership -> (s ownership with: { #queue -> #(). #pipeline -> #() }) }.
s := (step value: (PBTimerFired token: s ownership token event: #owner) value: s value: t0 + 333334) state.
lapsed := (step value: (PBPermitWanted waiter: #w2) value: s value: t0 + 700000) state.
pair := step value: (granted value: 'n0' value: 1 value: lapsed ownership renewal rid value: 5) value: lapsed value: t0 + 800000.
pair := step value: (granted value: 'n2' value: 1 value: lapsed ownership renewal rid value: 5) value: pair state value: t0 + 800000.
c that: 'a waiter that arrived while the lease lapsed joins the renewed lease''s queue'
  is: { s ownership renewal notNil. lapsed waiters. lapsed ownership queue. pair state ownership lease validUntil.
    pair state ownership queue. pair state ownership pipeline collect: [:e | e seq]. pair state waiters. pair state ownership lastDemand }
  equals: { true. #(#w2). #(). t0 + 1000000. #(). #(2). #(). t0 + 800000 }.

"(20-24) Fairness (Task 18: the rows of proto_db test_cluster_fairness.py the families above do
 not cover), at n1, from the hints: a release, held or a cancel, of a member."
rel := [:from :term :next :more | msg value: 'release' value: from value: { 'term' -> term. 'inc' -> 1. 'root' -> nil.
  'committed' -> nil. 'certain' -> true. 'held' -> true. 'next' -> next. 'more' -> more }].
want := [:from | msg value: 'want' value: from value: #()].
hintsAfter := [:aState :events | | st | st := aState.
  events do: [:pairOf | st := (step value: pairOf first value: st value: pairOf last) state].
  st].
s := hintsAfter value: (ready value: 'n1') value: { { want value: 'n2'. t0 }. { want value: 'n0'. t0 + 1 }.
  { rel value: 'n0' value: 4096 value: 'n2' value: false. t0 + 2 } }.
c that: 'a silent named member is not named again until it asks, and keeps its place'
  is: { s hints waiting. s hints turn.
    (core _nextTurn: (hintsAfter value: s value: { { want value: 'n0'. t0 + 3 } }) hints) first.
    (core _nextTurn: (hintsAfter value: s value: { { want value: 'n0'. t0 + 3 }. { want value: 'n2'. t0 + 4 } }) hints) first }
  equals: { #(). { 'n2'. t0 + 2. nil }. 'n0'. 'n2' }.
s := hintsAfter value: (stateIn value: 'n1' value: four value: { marker } value: Dictionary new)
  value: { { want value: 'n0'. t0 }. { want value: 'n2'. t0 + 1 }. { want value: 'n3'. t0 + 2 }.
    { rel value: 'n0' value: 4096 value: 'n2' value: true. t0 + 5 } }.
c that: 'a releaser that still wants the lease says more and is queued at the tail'
  is: { s hints waiting. (core _nextTurn: s hints) first }
  equals: { { { 'n3'. t0 + 2 }. { 'n0'. t0 + 5 } }. 'n3' }.
s := hintsAfter value: (ready value: 'n1') value: { { want value: 'n2'. t0 }. { rel value: 'n0' value: 4096 value: 'n2' value: false. t0 + 2 } }.
pair := { (hintsAfter value: s value: { { rel value: 'n0' value: 4096 value: 'n2' value: false. t0 + 3 } }) hints turn.
  (hintsAfter value: s value: { { rel value: 'n0' value: 4096 value: 'n2' value: false. t0 + 3 }.
    { msg value: 'request' value: 'n2' value: { 'term' -> 4098. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }. t0 + 4 } }) hints turn }.
s := hintsAfter value: s value: { { msg value: 'request' value: 'n2' value: { 'term' -> 4098. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }. t0 + 4 }.
  { rel value: 'n2' value: 4098 value: nil value: false. t0 + 10 }. { rel value: 'n0' value: 4096 value: 'n2' value: false. t0 + 11 } }.
own := core _step: [:fx | core _awaitTurn: (s with: { #waiters -> #(#w). #proposer -> PBProposer start.
    #holder -> (PBHolder empty with: { #deadlines -> { { #w. t0 + 10000000 } } }) })
  now: t0 + 11 + s config turnSilence effects: fx].
c that: 'a duplicated, stale or reordered release costs at most one bound'
  is: { pair first. pair last. s hints turn. ((own effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]) first.
    own state hints turn }
  equals: { { 'n2'. t0 + 3. nil }. { 'n2'. t0 + 3. t0 + 4 }. { 'n2'. t0 + 11. nil }. 'deferral_timeouts'. nil }.
c that: 'a wrong next: a non-member is ignored, the receiver asks at once, the sender costs one bound'
  is: { (hintsAfter value: (ready value: 'n1') value: { { rel value: 'n0' value: 4096 value: 'zz' value: false. t0 } }) hints turn.
    [ | h | h := (hintsAfter value: (ready value: 'n1') value: { { rel value: 'n0' value: 4096 value: 'n1' value: false. t0 } }) hints.
      { h myTurn. h turn } ] value.
    (hintsAfter value: (ready value: 'n1') value: { { rel value: 'n0' value: 4096 value: 'n0' value: false. t0 } }) hints turn }
  equals: { nil. { true. nil }. { 'n0'. t0. nil } }.
grantAfter := [:next :more | | v st |
  v := core accept: (msg value: 'request' value: 'n0' value: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs })
    in: (view value: 'n1' value: three value: { marker }) now: t0.
  st := core accept: (rel value: 'n0' value: 4096 value: next value: more) in: v state now: t0 + 10.
  st := core accept: (msg value: 'request' value: 'n2' value: { 'term' -> 4098. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs })
    in: st state now: t0 + 20.
  { st state grants printString. st state grants highestGranted. ((st reply select: [:e | e isKindOf: PBSend]) collect: [:e | e message type]) asArray }].
c that: 'the fairness hints never change a grant'
  is: { grantAfter value: 'n2' value: true. grantAfter value: 'zz' value: false. (grantAfter value: nil value: false) last }
  equals: { grantAfter value: nil value: false. grantAfter value: nil value: false. #('grant') }.

"(25-29) Own step failures (PBOwnStepFailed), at the rules, with no timing."
"Dispatches the failure of this node's own message m with a planted PBValidationError."
failed := [:m :aState :t | m isNil
  ifTrue: [PBStep state: aState effects: #()]
  ifFalse: [step value: (PBOwnStepFailed message: m error: (PBValidationError new messageText: 'planted'; yourself))
    value: aState value: t]].
settled := [:aStep | (aStep effects select: [:e | e isKindOf: PBSettle]) collect: [:e | { e waiter. e outcome messageText }]].
phase := [:aState | aState proposer isNil ifTrue: [nil] ifFalse: [aState proposer phase]].
stat := [:aStep | (aStep effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]].
"Two waiters of the attempt att opened: #w1 started it, #w2 joined it."
two := (step value: (PBPermitWanted waiter: #w2) value: att state value: t0 + 1) state.
req := (att effects at: 2) event message.
releases := [:aStep | (aStep effects select: [:e | (e isKindOf: PBSend) and: [e message type = 'release']]) collect: [:e |
  { e to. e message at: 'term'. e message at: 'held' }]].
pair := failed value: req value: two value: t0 + 2000.
lone := failed value: req value: att state value: t0 + 2000.
c that: 'an own request failure rejects only the oldest waiter; its cancel is sent, no lost round, the next waiter asks at once'
  is: { two waiters. settled value: pair. pair state waiters. releases value: pair.
    ([:m | m isNil ifTrue: [nil] ifFalse: [m type]] value: (toAcceptor value: pair)). stat value: pair. (phase value: pair state).
    pair state proposer notNil and: [pair state proposer failures = 0 and: [pair state proposer attempt notNil and: [pair state proposer attempt term > 1]]].
    (pair effects select: [:e | e isKindOf: PBSend]) collect: [:e | e message type] }
  equals: { #(#w1 #w2). #(#(#w1 'planted')). #(#w2). #(#('n0' 1 false) #('n2' 1 false)). 'release'. #('attempts'). #attempt. true.
    #('release' 'release' 'request' 'request') }.
c that: 'an own request failure of a lone waiter ends the acquisition with the attempt''s cancel, no lost round'
  is: { settled value: lone. lone state waiters. lone state proposer. releases value: lone. stat value: lone }
  equals: { #(#(#w1 'planted')). #(). nil. #(#('n0' 1 false) #('n2' 1 false)). #() }.
cancel := toAcceptor value: pair.
other := failed value: (PBClusterMessage type: 'request' from: 'n1' fields: { 'term' -> 1. 'rid' -> 99. 'inc' -> 5. 'vs' -> vs })
  value: two value: t0 + 2000.
c that: 'the cancel of that attempt rejects nobody when it fails; a late request failure changes nothing'
  is: { (failed value: cancel value: pair state value: t0 + 2001) effects. (failed value: cancel value: pair state value: t0 + 2001) state waiters.
    other effects. other state waiters. (phase value: other state) }
  equals: { #(). #(#w2). #(). #(#w1 #w2). #attempt }.
"A lost attempt of the two waiters: rejects from a majority (n0, n2)."
lost := step value: (reject value: 'n0' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: two value: t0 + 4000.
lost := step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: lost state value: t0 + 4000.
cancel := toAcceptor value: lost.
pair := failed value: cancel value: lost state value: t0 + 5000.
c that: 'an own cancel failure of the last lost attempt rejects the oldest waiter once; the others keep backing off'
  is: { stat value: lost. (phase value: lost state). (cancel isNil ifTrue: [nil] ifFalse: [{ cancel at: 'term'. cancel at: 'held' }]).
    settled value: pair. eff value: pair. pair state waiters. (phase value: pair state). (pair state proposer notNil and: [pair state proposer backoffEnd = lost state proposer backoffEnd]).
    (failed value: cancel value: pair state value: t0 + 5001) effects }
  equals: { #('lost_attempts'). #backoff. #(1 false). #(#(#w1 'planted')). #(#PBSettle). #(#w2). #backoff. true. #() }.
held := PBClusterMessage type: 'release' from: 'n1' fields: { 'term' -> 1. 'inc' -> 5. 'root' -> nil. 'committed' -> nil.
  'certain' -> true. 'held' -> true. 'next' -> nil. 'more' -> false }.
other := PBClusterMessage type: 'release' from: 'n1' fields: { 'term' -> 99. 'inc' -> 5. 'root' -> nil. 'committed' -> nil.
  'certain' -> false. 'held' -> false. 'next' -> nil. 'more' -> true }.
lone := step value: (reject value: 'n0' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: att state value: t0 + 4000.
lone := step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: lone state value: t0 + 4000.
lone := failed value: cancel value: lone state value: t0 + 5000.
c that: 'a held release or a cancel of another term changes nothing; a lone waiter''s rejection ends the acquisition'
  is: { (failed value: held value: lost state value: t0 + 5000) effects. (failed value: held value: lost state value: t0 + 5000) state waiters.
    (failed value: other value: lost state value: t0 + 5000) effects. (failed value: other value: lost state value: t0 + 5000) state waiters.
    settled value: lone. lone state waiters. lone state proposer }
  equals: { #(). #(#w1 #w2). #(). #(#w1 #w2). #(#(#w1 'planted')). #(). nil }.
"The cancel's failure arrives once the next attempt is open (its request out): the proposer's
 timers fired until the phase is #attempt."
opened := [:aStep | | st |
  st := aStep state.
  1 to: 6 do: [:i | (st proposer notNil and: [st proposer phase ~= #attempt]) ifTrue: [
    st := (step value: (PBTimerFired token: st proposer token event: #proposer) value: st value: st proposer wakeAt last) state]].
  st].
lone := step value: (reject value: 'n0' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: att state value: t0 + 4000.
lone := opened value: (step value: (reject value: 'n2' value: 1 value: 1 value: 5 value: 'busy' value: 1 value: 0.5) value: lone state value: t0 + 4000).
pair := failed value: cancel value: lone value: lone proposer startedAt + 1.
other := failed value: cancel value: (opened value: lost) value: (opened value: lost) proposer startedAt + 1.
c that: 'a cancel failure during the next attempt: kept for the other waiters; rejecting the last one, that attempt is cancelled first'
  is: { (phase value: lone). lone proposer attempt term > 1. lone proposer lostTerm.
    settled value: pair. pair state proposer. pair state waiters. eff value: pair. releases value: pair. stat value: pair.
    settled value: other. other state waiters. (phase value: other state). other effects size }
  equals: { #attempt. true. 1.
    #(#(#w1 'planted')). nil. #(). #(#PBSettle #PBToAcceptor #PBSend #PBSend). { { 'n0'. lone proposer attempt term. false }. { 'n2'. lone proposer attempt term. false } }. #().
    #(#(#w1 'planted')). #(#w2). #attempt. 1 }.
pair := failed value: renewMsg value: renewing value: t0 + 335000.
other := failed value: (PBClusterMessage type: 'renew' from: 'n1' fields: { 'term' -> 1. 'rid' -> ((renewMsg at: 'rid') + 99). 'inc' -> 5.
  'vs' -> vs }) value: renewing value: t0 + 335000.
c that: 'an own renew failure ends the ownership abandoned, with no release, and fences; a late one changes nothing'
  is: { renewMsg type. renewing ownership renewal notNil. pair state ownership. (eff value: pair) includes: #PBFence. (eff value: pair) last.
    (stat value: pair) includes: 'terms_abandoned'. (pair effects select: [:e | e isKindOf: PBSend]) collect: [:e | e message type].
    other effects. other state ownership notNil and: [other state ownership renewal notNil] }
  equals: { 'renew'. true. nil. true. #PBFence. true. #(). #(). true }.

c report displayNl.
