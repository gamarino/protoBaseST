"EXPECT: ok 20"
"The owner's rules and the holder side of a permit request (cluster/owner.st, with the deadline
 caps of cluster/proposer.st) called directly, one guard per check (proto_db coordinator.py
 _dispatch, _on_permit_req, _permit_outcome, _abandon, _refuse_queue, _own_loop_body, release,
 _permission_from_owner, _on_permit_reply, _back_off, _await_turn). n1 owns term 1 (inc 5) over
 the voters n0, n1, n2; n2 (inc 3) asks it.
 (1) A permit carries its base as certain only when the base is known committed (O1). (2) A won
 ownership's base is known committed only when the lease is certain and the root is the one its
 acceptor knows committed. (3) A committed done makes its root the certain base (O3). (4) An
 abandon makes the acceptor suspect the term (PBSuspect). (5) A retried request whose permit is
 out gets the same permit again, never a second (O7). (6) With less than a quarter of the
 belief left the owner renews instead of issuing (O1). (7) A request for a term the node no
 longer serves is refused 'ending', for another term 'not_owner', under the highest term. (8)
 The end of a term refuses its queued members 'ending' and hands its local waiters back. (9) The
 term never ends idle with a permission out (O8). (10) A release says more while a permit
 request of the node is out. (11) A permit request unanswered is sent again every
 requestTimeout, with the same rid. (12) A held permission is valid from the request's send, not
 from the permit's arrival (D45). (13) It is certain only with a base and no after (H2). (14) A
 duplicate permit, and a refusal of another incarnation, are dropped. (15) The back-off and the
 turn's deferral never last past the earliest waiter's deadline. (16) A local waiter queued at
 the ownership leaves it with PBTimeoutError at its deadline, and the ownership's timer wakes
 for it."
Import from: 'protobase'.
Import from: '_check'.

| c core peers config three marker logged view stateIn eff sends msg stats t0 r r2 owner req s pair fx
  permitOf sendsOf att w committedView holderState ask permit tok belief settled timers |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :someIds :opts | PBClusterConfig nodeId: id peers: (peers value: someIds) options: opts].
three := #('n0' 'n1' 'n2').
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
view := [:id :appends | PBAcceptorState config: (config value: id value: three value: (Dictionary new at: #startupGrace put: 0; yourself))
  logged: (logged value: appends) now: 0].
stateIn := [:id :appends | (PBNodeState config: (config value: id value: three value: Dictionary new) inc: 5)
  with: { #acceptorView -> (view value: id value: appends) }].
eff := [:aStep | aStep effects collect: [:e | e class name]].
sends := [:aStep | (aStep effects select: [:e | e isKindOf: PBSend]) collect: [:e | { e to. e message type }]].
sendsOf := [:aStep :type | ((aStep effects select: [:e | (e isKindOf: PBSend) and: [e message type = type]]) collect: [:e | e message])].
stats := [:aStep | (aStep effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]].
settled := [:aStep | (aStep effects select: [:e | e isKindOf: PBSettle]) collect: [:e | { e waiter. e outcome }]].
timers := [:aStep | (aStep effects select: [:e | e isKindOf: PBTimer]) collect: [:e | e after]].
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
t0 := 1000000.
belief := (config value: 'n1' value: three value: Dictionary new) belief.
r := PBLabeledRoot label: 1 record: (PBRootRecord segment: (ByteArray new: 16) offset: 7 epoch: 1).
r2 := PBLabeledRoot label: 1 record: (PBRootRecord segment: (ByteArray new: 16) offset: 8 epoch: 2).
committedView := { marker. PBLogAppend kind: #committed label: 1 root: r record sync: true }.
"n1 owning term 1 from t0 (lease to t0 + belief) on aBase, known committed or not."
owner := [:aBase :isCommitted | (stateIn value: 'n1' value: { marker }) with: {
  #ownership -> (PBOwnership lease: (PBLease term: 1 validUntil: t0 + belief root: aBase certain: true) base: aBase committed: isCommitted now: t0).
  #hints -> ((PBHints seed: 1) with: { #ownerTerm -> 1. #ownerNode -> 'n1' }) }].
req := [:from :term :rid :inc | msg value: 'permit_req' value: from value: { 'term' -> term. 'rid' -> rid. 'inc' -> inc }].
permitOf := [:aStep | (sendsOf value: aStep value: 'permit') first].

"(1) O1's certainty."
c that: 'a permit is certain only on a base known committed'
  is: { #(false true) collect: [:k | (permitOf value: (core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: k) now: t0 + 1000)) at: 'certain'].
    (permitOf value: (core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: nil value: true) now: t0 + 1000)) at: 'certain' }
  equals: { #(false true). false }.

"(2) The base of a won ownership."
att := PBAttempt term: 1 rid: 1 sentAt: t0 voters: 3.
w := [:aView :isCertain | | st |
  st := (stateIn value: 'n1' value: aView) with: { #waiters -> #(#w1) }.
  st := core _step: [:effects | core _own: att root: r certain: isCertain in: st now: t0 + 1000 effects: effects].
  ((settled value: st) detect: [:e | e first = #w1]) last isCertain].
c that: 'a won ownership''s base is known committed only when certain and the acceptor knows that root committed'
  is: { w value: { marker } value: true. w value: committedView value: true. w value: committedView value: false }
  equals: #(false true false).

"(3) O3: a committed done teaches the base."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: false) now: t0 + 1000.
s := (core dispatch: (msg value: 'done' value: 'n2' value: { 'term' -> 1. 'seq' -> 1. 'inc' -> 3. 'outcome' -> 'committed'.
  'root' -> (PBClusterMessage rootValue: r2). 'copies' -> #(). 'ranges' -> nil }) in: pair state now: t0 + 2000) state.
pair := core dispatch: (req value: 'n0' value: 1 value: 9 value: 4) in: s now: t0 + 3000.
c that: 'a committed done retires the permission and makes its root the certain base'
  is: { s ownership pipeline size. s ownership isCommitted. (permitOf value: pair) at: 'certain'.
    (PBClusterMessage rootFrom: ((permitOf value: pair) at: 'root')) key = r2 key. (permitOf value: pair) at: 'seq' }
  equals: { 0. true. true. true. 2 }.

"(4) An abandon: the acceptor suspects the term."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + 1000.
pair := core dispatch: (msg value: 'done' value: 'n2' value: { 'term' -> 1. 'seq' -> 1. 'inc' -> 3. 'outcome' -> 'unknown'.
  'root' -> nil. 'copies' -> #(). 'ranges' -> nil }) in: pair state now: t0 + 2000.
c that: 'an abandoned term makes the acceptor suspect it and the node uncertain'
  is: { ((pair effects select: [:e | (e isKindOf: PBToAcceptor) and: [e event isKindOf: PBSuspect]]) collect: [:e | e event term]) asArray.
    pair state suspectTerm. (stats value: pair) includes: 'terms_abandoned' }
  equals: { #(1). 1. true }.

"(5) O7."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + 1000.
s := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: pair state now: t0 + 2000.
c that: 'a retried request gets the same permit again, never a second'
  is: { ((sendsOf value: s value: 'permit') collect: [:m | { m at: 'seq'. m at: 'valid' }]) asArray.
    (stats value: s) includes: 'permits_issued'. s state ownership seq. s state ownership queue size }
  equals: { { { (permitOf value: pair) at: 'seq'. (permitOf value: pair) at: 'valid' } }. false. 1. 0 }.

"(6) O1's quarter of the belief."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + belief - (belief // 4) + 1000.
c that: 'with less than a quarter of the belief left the owner renews first'
  is: { (sends value: pair) collect: [:e | e last]. pair state ownership queue size. pair state ownership renewal notNil }
  equals: { #('renew' 'renew'). 1. true }.

"(7) Refusals."
s := (owner value: r value: true) with: { #ownership -> ((owner value: r value: true) ownership with: { #abandoned -> true }) }.
c that: 'a request for a term no longer served is refused ending, another term not_owner, under the highest term'
  is: { #(1 2) collect: [:term | | m |
      m := (sendsOf value: (core dispatch: (req value: 'n2' value: term value: 7 value: 3) in: s now: t0 + 1000) value: 'permit_no') first.
      { m at: 'reason'. m at: 'term'. m at: 'rid'. m at: 'inc' }].
    ((sendsOf value: (core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + belief) value: 'permit_no')
      collect: [:m | m at: 'reason']) asArray }
  equals: { #(#('ending' 1 7 3) #('not_owner' 1 7 3)). #('ending') }.

"(8) The end of a term."
s := (owner value: r value: true).
s := s with: { #ownership -> (s ownership with: { #queue -> { { 'n2'. 7. 3. nil }. { 'n1'. 8. 5. #w1 } } }) }.
fx := OrderedCollection new.
s := core _endOwnership: s now: t0 + 1000 effects: fx.
c that: 'the end of a term refuses its queued members ending and hands its local waiters back'
  is: { ((fx select: [:e | (e isKindOf: PBSend) and: [e message type = 'permit_no']]) collect: [:e | { e to. e message at: 'reason'. e message at: 'rid' }]) asArray.
    s ownership. (s waiters includes: #w1) }
  equals: { #(#('n2' 'ending' 7)). nil. true }.

"(9) O8."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + 1000.
s := pair state with: { #ownership -> (pair state ownership with: { #lastDemand -> (t0 - 10000000) }) }.
c that: 'the term never ends idle with a permission out'
  is: { (core _step: [:effects | core _ownLoop: s now: t0 + 2000 effects: effects]) state ownership notNil.
    (core _step: [:effects | core _ownLoop: (s with: { #ownership -> (s ownership with: { #pipeline -> #() }) }) now: t0 + 2000 effects: effects]) state ownership }
  equals: { true. nil }.

"(10) A release says more while a permit request is out."
ask := PBPermitAsk waiter: #w9 rid: 3 sentAt: t0 term: 4 target: 'n0' request: nil retryAt: t0 endAt: t0.
c that: 'a release says more while a permit request of the node is out'
  is: { #(false true) collect: [:withAsk | | st f |
    st := owner value: r value: true.
    withAsk ifTrue: [st := st with: { #holder -> (PBHolder empty with: { #asks -> { ask } }) }].
    f := OrderedCollection new.
    core _releaseLease: st ownership lease in: st now: t0 + 1000 effects: f.
    ((f select: [:e | e isKindOf: PBSend]) first message) at: 'more'] }
  equals: { #(false true) }.

"(11) The holder: n0 asks n1, the owner its hint names."
holderState := (stateIn value: 'n0' value: { marker }) with: { #hints -> ((PBHints seed: 1) with: { #ownerTerm -> 1. #ownerNode -> 'n1' }) }.
pair := core dispatch: (PBPermitWanted waiter: #w1) in: holderState now: t0.
s := pair state.
tok := s holder asks first token.
fx := core dispatch: (PBTimerFired token: tok event: #ask) in: s now: t0 + s config requestTimeout.
c that: 'an unanswered permit request is sent again every requestTimeout, with the same rid'
  is: { sends value: pair. (sendsOf value: fx value: 'permit_req') collect: [:m | { m at: 'rid'. m at: 'term' }].
    ((sendsOf value: pair value: 'permit_req') first at: 'rid'). (stats value: fx). timers value: fx }
  equals: { #(#('n1' 'permit_req')). { { s holder asks first rid. 1 } }. s holder asks first rid. #('permit_requests_retried').
    { s config requestTimeout } }.

"(12-13) The permission held."
permit := [:certain :root :after | msg value: 'permit' value: 'n1' value: { 'term' -> 1. 'rid' -> s holder asks first rid. 'seq' -> 1.
  'inc' -> 5. 'root' -> (PBClusterMessage rootValue: root). 'certain' -> certain. 'valid' -> 0.3. 'after' -> after }].
pair := core dispatch: (permit value: true value: r value: nil) in: s now: t0 + 50000.
c that: 'a held permission is valid from the request''s send'
  is: { (settled value: pair) collect: [:e | { e first. e last validUntil. e last seq }]. stats value: pair }
  equals: { { { #w1. t0 + 300000. 1 } }. #('permits_held') }.
c that: 'a held permission is certain only with a base and no after (H2)'
  is: ({ { true. r. nil }. { true. r. #(1 'n2') }. { true. nil. nil }. { false. r. nil } } collect: [:a |
    ((settled value: (core dispatch: (permit value: a first value: (a at: 2) value: a last) in: s now: t0 + 50000)) first) last isCertain])
  equals: #(true false false false).

"(14) Drops."
c that: 'a duplicate permit and a refusal of another incarnation are dropped'
  is: { eff value: (core dispatch: (permit value: true value: r value: nil) in: pair state now: t0 + 60000).
    stats value: (fx := core dispatch: (msg value: 'permit_no' value: 'n1' value: { 'term' -> 1. 'rid' -> s holder asks first rid. 'inc' -> 4.
      'reason' -> 'not_owner' }) in: s now: t0 + 1000).
    fx state holder asks size. fx state hints ownerNode }
  equals: { #(). #('stale_replies'). 1. 'n1' }.

"(15) Deadline caps: n0 waits with w1's deadline 300 ms away."
s := (stateIn value: 'n0' value: { marker }) with: { #waiters -> #(#w1). #proposer -> PBProposer start.
  #holder -> (PBHolder empty with: { #deadlines -> { { #w1. t0 + 300000 } } }) }.
pair := core _step: [:effects | core _backOff: s busy: 5000000 now: t0 effects: effects].
fx := core _step: [:effects | core _awaitTurn: (s with: { #hints -> ((PBHints seed: 1) with: { #turn -> { 'n2'. t0. t0 } }) })
  now: t0 + 1000 effects: effects].
c that: 'the back-off and the turn''s deferral never last past the earliest deadline'
  is: { pair state proposer backoffEnd <= (t0 + 300000). pair state proposer busyEnd. fx state proposer phase. timers value: fx }
  equals: { true. t0 + 300000. #turn. #(299000) }.

"(16) A local waiter queued at the ownership."
s := owner value: r value: true.
s := s with: { #ownership -> (s ownership with: { #queue -> { { 'n1'. 8. 5. #w1 } }. #pipeline -> { PBIssued node: 'n2' seq: 1 inc: 3 rid: 7
    deadline: t0 + belief permit: nil base: r } }).
  #holder -> (PBHolder empty with: { #deadlines -> { { #w1. t0 + 300000 } } }) }.
pair := core _step: [:effects | core _ownLoop: s now: t0 + 1000 effects: effects].
fx := core _step: [:effects | core _ownLoop: s now: t0 + 300000 effects: effects].
c that: 'a local waiter queued at the ownership leaves it with PBTimeoutError at its deadline'
  is: { (timers value: pair) first <= 299000. settled value: pair.
    (settled value: fx) collect: [:e | { e first. e last class name }]. fx state ownership queue. fx state holder deadlines }
  equals: { true. #(). #(#(#w1 #PBTimeoutError)). #(). #() }.

"(17) O5, O6 (Task 18: proto_db test_cluster_pipeline_owner.py o5 and o6 at DEPTH 0): a 'none'
 from the only entry removes it and the next permit reuses the committed base; a done told by
 another incarnation than the one the permit was issued to abandons the term."
pair := core dispatch: (req value: 'n2' value: 1 value: 7 value: 3) in: (owner value: r value: true) now: t0 + 1000.
fx := core dispatch: (msg value: 'done' value: 'n2' value: { 'term' -> 1. 'seq' -> 1. 'inc' -> 3. 'outcome' -> 'none'.
  'root' -> nil. 'copies' -> #(). 'ranges' -> nil }) in: pair state now: t0 + 2000.
s := core dispatch: (req value: 'n0' value: 1 value: 9 value: 4) in: fx state now: t0 + 3000.
r2 := core dispatch: (msg value: 'done' value: 'n2' value: { 'term' -> 1. 'seq' -> 1. 'inc' -> 4. 'outcome' -> 'committed'.
  'root' -> (PBClusterMessage rootValue: r). 'copies' -> #(). 'ranges' -> nil }) in: pair state now: t0 + 2000.
c that: 'a lone none restores the committed base; a done of another incarnation abandons'
  is: { fx state ownership pipeline size. (stats value: fx) includes: 'terms_abandoned'. sends value: fx.
    (permitOf value: s) at: 'seq'. (permitOf value: s) at: 'certain'.
    (PBClusterMessage rootFrom: ((permitOf value: s) at: 'root')) key = r key.
    (stats value: r2) includes: 'terms_abandoned'. r2 state suspectTerm }
  equals: { 0. false. #(). 2. true. true. true. 1 }.
r2 := PBLabeledRoot label: 1 record: (PBRootRecord segment: (ByteArray new: 16) offset: 8 epoch: 2).

"(18) proto_db test_a_permit_arriving_after_its_request_gave_up_is_handed_back_at_once: a permit
 no ask of this incarnation waits for is answered done 'none' at once, and settles nothing."
holderState := (stateIn value: 'n2' value: { marker }) with: { #hints -> ((PBHints seed: 1) with: { #ownerTerm -> 1. #ownerNode -> 'n1' }) }.
fx := core dispatch: (msg value: 'permit' value: 'n1' value: { 'term' -> 1. 'rid' -> 9. 'seq' -> 4. 'inc' -> 5.
  'root' -> (PBClusterMessage rootValue: r). 'certain' -> true. 'valid' -> 0.3. 'after' -> nil }) in: holderState now: t0.
c that: 'a permit nobody waits for is handed back at once with done none'
  is: { (sendsOf value: fx value: 'done') collect: [:m | { m at: 'term'. m at: 'seq'. m at: 'inc'. m at: 'outcome'. m at: 'root' }].
    ((fx effects select: [:e | e isKindOf: PBSend]) collect: [:e | e to]) asArray. settled value: fx }
  equals: { { { 1. 4. 5. 'none'. nil } }. #('n1'). #() }.

"(19) Task 24 fix round 2, n3: a local commit's own bound (PBPermitWanted waiter:timeout:, the
 space's lockTimeout) on a waiter queued at this node's ownership: its deadline is that bound
 from its dispatch, and its PBTimeoutError names it, not acquireTimeout."
s := owner value: r value: true.
s := s with: { #ownership -> (s ownership with: { #pipeline -> { PBIssued node: 'n2' seq: 1 inc: 3 rid: 7
    deadline: t0 + belief permit: nil base: r } }) }.
pair := core dispatch: (PBPermitWanted waiter: #w1 timeout: 300000) in: s now: t0.
fx := core _step: [:effects | core _ownLoop: pair state now: t0 + 300000 effects: effects].
c that: 'a local waiter queued at the ownership with its own bound times out at that bound, and the text names it'
  is: { pair state holder deadlines. (pair state ownership queue collect: [:e | e at: 4]) asArray. settled value: pair.
    (settled value: fx) collect: [:e | { e first. e last class name. e last messageText includesSubstring: 'within 300 ms' }].
    fx state ownership queue }
  equals: { { { #w1. t0 + 300000. 300000 } }. #(#w1). #(). #(#(#w1 #PBTimeoutError true)). #() }.

"(20) n3, the ask path: a waiter with its own bound that asks the owner its hint names stops
 waiting for the answer at that bound when it comes before leaseDuration (_ask:'s endAt)."
holderState := (stateIn value: 'n0' value: { marker }) with: { #hints -> ((PBHints seed: 1) with: { #ownerTerm -> 1. #ownerNode -> 'n1' }) }.
pair := core dispatch: (PBPermitWanted waiter: #w2 timeout: 300000) in: holderState now: t0.
fx := core dispatch: (PBPermitWanted waiter: #w3) in: holderState now: t0.
c that: 'a waiter with its own bound that asks the owner stops waiting for it at that bound'
  is: { pair state holder asks collect: [:a | { a waiter. a endAt }]. pair state holder deadlines.
    fx state holder asks collect: [:a | { a waiter. a endAt }] }
  equals: { { { #w2. t0 + 300000 } }. { { #w2. t0 + 300000. 300000 } }.
    { { #w3. t0 + holderState config leaseDuration } } }.

c report displayNl.
