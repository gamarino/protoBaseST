"EXPECT: ok 12"
"The renewal back-off and the fenced term (proto_db 88ca21d, post-rc3: rulings R149 and R149a,
 gamarino/ProtoDB#1, the D50 amendment; tests/unit/test_cluster_renew_backoff.py ported to the
 pure core, virtual time only): cluster/lease.st (PBAttempt isTermFenced), cluster/config.st
 (renewBackoffFloor), cluster/proposer.st (_ownLoop:now:effects:, _closeRenewal:now:effects:)
 and cluster/owner.st (receivedPermitReq:in:now:) called directly. n1 (inc 5) owns term 5 from
 t0 (its lease to t0 + belief) over the voters n0, n1, n2; n2 (inc 3) and n0 (inc 4) ask it.
 (1) A term is fenced when its permanent refusals (stale_term, term_taken, or any reason with a
 highest term above the term) exceed voters - needed; the highest term seen alone never fences.
 (2) renewBackoffFloor is requestTimeout / 4, at least 1 ms.
 (3) test_a_fenced_term_steps_down_after_one_renewal: a majority refuses for good; one renewal,
 the queue refused 'ending' (a local waiter waits again and acquires after), terms_fenced,
 never abandoned, released certain at once.
 (4) test_a_fenced_term_lets_its_outstanding_permission_end_by_its_done: fenced with a
 permission out: the queue refused 'ending', nothing released, never abandoned, no renewal, a
 timer for the lease's remainder; a new request refused 'ending'; a local waiter waits; the done
 releases the term in its own step and the waiter starts an acquisition.
 (5) The lease expiring first with the permission out still abandons it (review I3).
 (6) test_a_transient_refusal_backs_off_until_the_refusals_remaining: no renewal before the
 refusals' remaining, a timer for it, the renewal after it wins and clears the back-off.
 (7) The back-off never lasts past the lease (min(remaining, ...)).
 (8) test_a_minority_busy_with_a_lower_term_never_fences_the_owner.
 (9) test_a_round_left_pending_after_a_majority_answered_backs_off (R149a): requestTimeout / 4.
 (10) test_a_fenced_term_resends_an_outstanding_permit_to_a_retry, and its done releases.
 (11) test_a_fenced_term_resends_its_permit_only_to_a_true_retry: every other request is
 refused with its reason, and so is the true retry once the lease has expired."
Import from: 'protobase'.
Import from: '_check'.

| c core peers config three marker logged stateIn msg granted reject req sendsOf sends stats counted timers settled run loop
  rejects grants t0 term belief rt owner s p pr pf pc pw pd pl pa pm permission start r tr cases fenced att permitOf first
  floor renewing tok |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :opts | PBClusterConfig nodeId: id peers: (peers value: three) options: opts].
three := #('n0' 'n1' 'n2').
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
stateIn := [:id | (PBNodeState config: (config value: id value: Dictionary new) inc: 5) with: {
  #acceptorView -> (PBAcceptorState config: (config value: id value: (Dictionary new at: #startupGrace put: 0; yourself))
    logged: (logged value: { marker }) now: 0) }].
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
req := [:from :aTerm :rid :inc | msg value: 'permit_req' value: from value: { 'term' -> aTerm. 'rid' -> rid. 'inc' -> inc }].
sendsOf := [:aStep :type | ((aStep effects select: [:e | (e isKindOf: PBSend) and: [e message type = type]]) collect: [:e | { e to. e message }]) asArray].
sends := [:aStep :type | (sendsOf value: aStep value: type) size].
stats := [:aStep | ((aStep effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]) asArray].
"The stats of aStep that this file is about, in order."
counted := [:aStep | (stats value: aStep) select: [:k | #('renewals' 'renewal_failures' 'terms_fenced' 'terms_abandoned' 'permits_issued') includes: k]].
timers := [:aStep | ((aStep effects select: [:e | e isKindOf: PBTimer]) collect: [:e | e after]) asArray].
settled := [:aStep | ((aStep effects select: [:e | e isKindOf: PBSettle]) collect: [:e | e outcome]) asArray].
permitOf := [:aStep | ((sendsOf value: aStep value: 'permit') collect: [:e | { e first. e last at: 'seq'. e last at: 'rid'. e last at: 'valid' }])].
"Dispatches someEvents in turn in aState at t: one step holding every effect. A bare message is
 n1's own vote, which its acceptor hands back in the step's vote (dispatchAcceptorDecided:)."
run := [:aState :t :someEvents | | st all |
  st := aState.
  all := OrderedCollection new.
  someEvents do: [:e | | step |
    step := (e isKindOf: PBClusterMessage)
      ifTrue: [core _step: [:fx | core _onReply: e in: st now: t effects: fx]]
      ifFalse: [core dispatch: e in: st now: t].
    all addAll: step effects. st := step state].
  PBStep state: st effects: all asArray].
loop := [:aState :t | core _step: [:fx | core _ownLoop: aState now: t effects: fx]].
"The refusals { from. reason. highest. remaining (microseconds) } of the renewal running in aState."
rejects := [:aState :specs | specs collect: [:sp | msg value: 'reject' value: sp first value: {
  'term' -> term. 'rid' -> aState ownership renewal rid. 'inc' -> 5. 'root' -> nil. 'certain' -> true.
  'reason' -> (sp at: 2). 'highest' -> (sp at: 3). 'remaining' -> (PBCoordinatorCore wireSeconds: (sp at: 4)) }]].
"The grants of someIds to the renewal running in aState (n1's: its own vote)."
grants := [:aState :someIds | someIds collect: [:id | | m |
  m := msg value: 'grant' value: id value: {
    'term' -> term. 'rid' -> aState ownership renewal rid. 'inc' -> 5. 'root' -> nil. 'committed' -> nil. 'certain' -> true }.
  id = 'n1' ifTrue: [m message] ifFalse: [m]]].
t0 := 1000000.
term := 5.
belief := (config value: 'n1' value: Dictionary new) belief.
rt := (config value: 'n1' value: Dictionary new) requestTimeout.
owner := [(stateIn value: 'n1') with: {
  #ownership -> (PBOwnership lease: (PBLease term: term validUntil: t0 + belief root: nil certain: true) base: nil committed: false now: t0).
  #hints -> ((PBHints seed: 1) with: { #ownerTerm -> term. #ownerNode -> 'n1' }) }].
"The ownership loop of aState at t after a local demand at t (proto_db's tests set last_demand
 before each poke): due when less than half the belief is left."
renewing := [:aState :t | loop value: (aState with: { #ownership -> (aState ownership with: { #lastDemand -> t }) }) value: t].

"(1) PBAttempt isTermFenced (proto_db LeaseAttempt.term_fenced)."
att := [:v :specs | specs inject: (PBAttempt term: term rid: 1 sentAt: 0 voters: v) into: [:a :sp |
  a withReject: sp first reason: (sp at: 2) highest: (sp at: 3) remaining: 0]].
fenced := [:v :specs | | a | a := att value: v value: specs. { a state. a isTermFenced }].
c that: 'a term is fenced only when its permanent refusals exceed voters - needed'
  is: {
    fenced value: 3 value: #(#('n0' 'stale_term' 5) #('n2' 'stale_term' 5)).
    fenced value: 3 value: #(#('n0' 'term_taken' 5) #('n2' 'term_taken' 5)).
    fenced value: 3 value: #(#('n0' 'busy' 6) #('n2' 'starting' 6)).
    fenced value: 3 value: #(#('n0' 'tier_failed' 6) #('n2' 'rejoining' 6)).
    fenced value: 3 value: #(#('n0' 'busy' 5) #('n2' 'starting' 5)).
    fenced value: 3 value: #(#('n0' 'busy' 4) #('n2' 'stale_term' 6)).
    fenced value: 3 value: #(#('n0' 'tier_failed' 5) #('n2' 'stale_term' 5)).
    fenced value: 3 value: #(#('n0' 'stale_term' 5) #('n0' 'busy' 9)).
    fenced value: 5 value: #(#('n0' 'stale_term' 5) #('n2' 'stale_term' 5)).
    fenced value: 5 value: #(#('n0' 'stale_term' 5) #('n2' 'busy' 4) #('n3' 'stale_term' 5)).
    fenced value: 5 value: #(#('n0' 'stale_term' 5) #('n2' 'term_taken' 5) #('n3' 'busy' 7)).
    (att value: 3 value: #(#('n0' 'busy' 4) #('n2' 'stale_term' 6))) highestSeen > term }
  equals: { #(#lost true). #(#lost true). #(#lost true). #(#lost true). #(#lost false). #(#lost false). #(#lost false).
    #(#pending false). #(#pending false). #(#lost false). #(#lost true). true }.

"(2) The back-off floor."
floor := [:ms | (config value: 'n1' value: (Dictionary new at: #requestTimeout put: ms; yourself)) renewBackoffFloor].
c that: 'renewBackoffFloor is requestTimeout / 4, at least 1 ms'
  is: { (config value: 'n1' value: Dictionary new) renewBackoffFloor. floor value: 8. floor value: 3. floor value: 1 }
  equals: #(62500 2000 1000 1000).

"(3) Fenced, nothing outstanding: n1's own commit w0 and n2's request wait in the queue (too
 little lease to issue, D50's quarter of the belief), the renewal is due; n0 and n2 promised a
 higher ballot. n2 is refused 'ending'; w0 waits again, and acquires once the term is released."
tr := t0 + belief - (belief // 8).
p := core dispatch: (PBPermitWanted waiter: #w0) in: owner value now: tr.
pr := core dispatch: (req value: 'n2' value: term value: 50001 value: 3) in: p state now: tr.
pf := run value: pr state value: tr + 2000 value: (rejects value: pr state value: #(#('n0' 'stale_term' 6 0) #('n2' 'stale_term' 6 0))).
c that: 'a fenced term steps down after one renewal: queue refused ending, released certain, never abandoned'
  is: { sends value: p value: 'renew'. sends value: pr value: 'renew'. pr state ownership queue size. sends value: pf value: 'renew'.
    pf state ownership. counted value: pf.
    (sendsOf value: pf value: 'permit_no') collect: [:e | { e first. e last at: 'rid'. e last at: 'reason' }].
    (sendsOf value: pf value: 'release') collect: [:e | { e first. e last at: 'term'. e last at: 'held'. e last at: 'certain'. e last at: 'more' }].
    (pf effects select: [:e | (e isKindOf: PBToAcceptor) and: [e event isKindOf: PBSuspect]]) size. pf state suspectTerm.
    settled value: pf. pf state waiters. pf state proposer notNil }
  equals: { 2. 0. 2. 0. nil. #('renewal_failures' 'terms_fenced'). { { 'n2'. 50001. 'ending' } }.
    { { 'n0'. term. true. true. true }. { 'n2'. term. true. true. true } }. 0. 0. #(). #(#w0). true }.

"(4) Fenced with n1's own permission out and n2's request queued behind it."
p := core dispatch: (PBPermitWanted waiter: #w1) in: owner value now: t0 + 1000.
permission := (settled value: p) first.
p := core dispatch: (req value: 'n2' value: term value: 50002 value: 3) in: p state now: t0 + 2000.
tr := t0 + belief - (belief // 4) + 1.
pr := renewing value: p state value: tr.
pf := run value: pr state value: tr + 1000 value: (rejects value: pr state value: #(#('n0' 'stale_term' 6 0) #('n2' 'busy' 6 50000))).
pc := core dispatch: (req value: 'n0' value: term value: 50003 value: 4) in: pf state now: tr + 2000.
pw := core dispatch: (PBPermitWanted waiter: #w2) in: pc state now: tr + 3000.
pl := run value: pw state value: tr + 100000 value: { PBTimerFired token: pw state ownership token event: #owner }.
pd := core dispatch: (PBDoneReport permission: permission outcome: #none) in: pl state now: tr + 101000.
c that: 'a fenced term with a permission out refuses its queue, releases nothing and never renews'
  is: { { permission class name. p state ownership queue size. sends value: pr value: 'renew' }.
    { pf state ownership isTermFenced. pf state ownership isAbandoned. pf state ownership pipeline size. pf state ownership queue. counted value: pf }.
    (sendsOf value: pf value: 'permit_no') collect: [:e | { e first. e last at: 'rid'. e last at: 'reason' }].
    { sends value: pf value: 'release'. sends value: pf value: 'renew'. (timers value: pf) last }.
    (sendsOf value: pc value: 'permit_no') collect: [:e | { e first. e last at: 'rid'. e last at: 'reason' }].
    { pc state ownership queue. pc state ownership pipeline size. counted value: pc }.
    { settled value: pw. pw state waiters. pw state ownership queue }.
    { sends value: pl value: 'renew'. sends value: pl value: 'release'. pl state ownership notNil. (timers value: pl) first } }
  equals: { #(#PBPermission 1 2).
    { true. false. 1. #(). #('renewal_failures' 'terms_fenced') }.
    { { 'n2'. 50002. 'ending' } }.
    { 0. 0. t0 + belief - (tr + 1000) }.
    { { 'n0'. 50003. 'ending' } }.
    { #(). 1. #() }.
    { #(). #(#w2). #() }.
    { 0. 0. true. t0 + belief - (tr + 100000) } }.
c that: 'the done of a fenced term''s permission releases it at once, certain, and its waiters acquire'
  is: { pd state ownership. counted value: pd.
    (sendsOf value: pd value: 'release') collect: [:e | { e first. e last at: 'held'. e last at: 'certain'. e last at: 'more' }].
    pd state proposer notNil. pd state waiters }
  equals: { nil. #(). { { 'n0'. true. true. true }. { 'n2'. true. true. true } }. true. #(#w2) }.

"(5) The lease expiring before the done still abandons (review I3)."
pa := loop value: pl state value: t0 + belief.
c that: 'a fenced term whose lease expires with a permission out is abandoned, released uncertain'
  is: { pa state ownership. counted value: pa.
    (sendsOf value: pa value: 'release') collect: [:e | { e first. e last at: 'held'. e last at: 'certain' }] }
  equals: { nil. #('terms_abandoned'). #(#('n0' true false) #('n2' true false)) }.

"(6) Transient: n0 and n2 answer starting (their grace) with remaining r."
start := t0 + belief - (belief // 3).
r := belief // 8.
pr := renewing value: owner value value: start.
pf := run value: pr state value: start + 1000 value: (rejects value: pr state value: { { 'n0'. 'starting'. term. r }. { 'n2'. 'starting'. term. r } }).
pm := renewing value: pf state value: start + 1000 + (r // 2).
pa := renewing value: pm state value: start + 1000 + r.
pw := run value: pa state value: start + 2000 + r value: (grants value: pa state value: #('n0' 'n2')).
c that: 'a transient refusal backs off until the refusals'' remaining, then the renewal wins and clears it'
  is: { { sends value: pr value: 'renew'. sends value: pf value: 'renew'. counted value: pf. pf state ownership renewAfter. (timers value: pf) last.
      pf state ownership isTermFenced }.
    { sends value: pm value: 'renew'. timers value: pm }.
    { sends value: pa value: 'renew'. counted value: pw. pw state ownership renewAfter. pw state ownership lease validUntil } }
  equals: { { 2. 0. #('renewal_failures'). start + 1000 + r. r. false }.
    { 0. { r - (r // 2) } }.
    { 2. #('renewals'). nil. start + 1000 + r + belief } }.

"(7) A refusal's remaining beyond the lease: the back-off ends with the lease."
pf := run value: pr state value: start + 1000 value: (rejects value: pr state value: #(#('n0' 'busy' 5 10000000) #('n2' 'busy' 5 10000000))).
c that: 'the back-off never lasts past the lease'
  is: { pf state ownership renewAfter. pf state ownership isTermFenced }
  equals: { t0 + belief. false }.

"(8) n0 is busy with a grant to another holder for a LOWER term (an attempt that lost), until
 tb. First n1 and n2 grant: won. Then n2 refuses for good (it promised a higher ballot): lost
 with one permanent refusal of the one allowed, and the highest term seen above the term; it
 backs off and is never fenced; once n0's other grant ended, n0 grants and the renewal wins."
pr := renewing value: owner value value: start.
pw := run value: pr state value: start + 1000 value: (rejects value: pr state value: { { 'n0'. 'busy'. term - 1. 400000 } }) ,
  (grants value: pr state value: #('n1' 'n2')).
s := pw state.
tr := s ownership lease validUntil - (belief // 3).
pl := renewing value: s value: tr.
pf := run value: pl state value: tr + 1000 value: (rejects value: pl state value: { { 'n0'. 'busy'. term - 1. 100000 } }) ,
  (grants value: pl state value: #('n1')) , (rejects value: pl state value: { { 'n2'. 'stale_term'. term + 1. 0 } }).
pa := renewing value: pf state value: pf state ownership renewAfter.
pd := run value: pa state value: pf state ownership renewAfter + 1000 value: (grants value: pa state value: #('n0' 'n1')).
c that: 'a minority busy with a lower term never fences the owner'
  is: { counted value: pw. pw state ownership renewAfter.
    { counted value: pf. pf state ownership isTermFenced. pf state ownership renewAfter. sends value: pf value: 'permit_no' }.
    { sends value: pa value: 'renew'. counted value: pd. pd state ownership isTermFenced. pd state ownership renewAfter } }
  equals: { #('renewals'). nil.
    { #('renewal_failures'). false. tr + 1000 + 100000. 0 }.
    { 2. #('renewals'). false. nil } }.

"(9) R149a: n0 refuses for good, n1 grants, n2 is silent: a majority answered, the round waits
 the stragglers and ends pending; it backs off requestTimeout / 4 (no refusal names a remaining)."
pr := renewing value: owner value value: start.
pf := run value: pr state value: start + 1000 value: (rejects value: pr state value: #(#('n0' 'stale_term' 6 0))) ,
  (grants value: pr state value: #('n1')).
tok := pf state ownership token.
pa := run value: pf state value: start + 1000 + (timers value: pf) last value: { PBTimerFired token: tok event: #owner }.
pm := renewing value: pa state value: pa state ownership renewAfter - 1.
pl := renewing value: pa state value: pa state ownership renewAfter.
c that: 'a round left pending after a majority answered backs off requestTimeout / 4'
  is: { pf state ownership renewal state. counted value: pa. pa state ownership isTermFenced.
    pa state ownership renewAfter - (start + 1000 + (timers value: pf) last). sends value: pa value: 'renew'.
    sends value: pm value: 'renew'. timers value: pm. sends value: pl value: 'renew' }
  equals: { #pending. #('renewal_failures'). false. rt // 4. 0. 0. #(1000). 2 }.

"(10) Fenced with n2's permit out: its O7 retry gets the same permit again, its done releases."
p := core dispatch: (req value: 'n2' value: term value: 50010 value: 3) in: owner value now: t0 + 1000.
first := permitOf value: p.
tr := t0 + belief - (belief // 4) + 1.
pr := renewing value: p state value: tr.
pf := run value: pr state value: tr + 1000 value: (rejects value: pr state value: #(#('n0' 'stale_term' 6 0) #('n2' 'stale_term' 6 0))).
pc := core dispatch: (req value: 'n2' value: term value: 50010 value: 3) in: pf state now: tr + 2000.
pd := core dispatch: (msg value: 'done' value: 'n2' value: { 'term' -> term. 'seq' -> 1. 'inc' -> 3. 'outcome' -> 'none'.
  'root' -> nil. 'copies' -> #(). 'ranges' -> nil }) in: pc state now: tr + 3000.
c that: 'a fenced term resends an outstanding permit to a retry, and its done releases it'
  is: { first size. pf state ownership isTermFenced. permitOf value: pc. sendsOf value: pc value: 'permit_no'. counted value: pc.
    pd state ownership. counted value: pd. (sendsOf value: pd value: 'release') collect: [:e | e last at: 'certain'] }
  equals: { 1. true. first. #(). #(). nil. #(). #(true true) }.

"(11) Only a true retry (sender, incarnation, request id and term), the lease valid."
cases := { { 'n2'. 50011. 3. term. 'ending' }. { 'n0'. 50010. 4. term. 'ending' }. { 'n2'. 50010. 4. term. 'ending' }.
  { 'n2'. 50012. 3. term + 1. 'not_owner' } }.
c that: 'a fenced term resends its permit only to a true retry, and not once the lease expired'
  is: { cases collect: [:e | | step |
      step := core dispatch: (req value: (e at: 1) value: (e at: 4) value: (e at: 2) value: (e at: 3)) in: pf state now: tr + 2000.
      { permitOf value: step. (sendsOf value: step value: 'permit_no') collect: [:m | { m first. m last at: 'rid'. m last at: 'inc'. m last at: 'reason' }].
        step state ownership queue. counted value: step }].
    { permitOf value: (pa := core dispatch: (req value: 'n2' value: term value: 50010 value: 3) in: pf state now: t0 + belief).
      (sendsOf value: pa value: 'permit_no') collect: [:m | m last at: 'reason']. counted value: pa } }
  equals: { cases collect: [:e | { #(). { { e at: 1. e at: 2. e at: 3. e at: 5 } }. #(). #() }]. { #(). #('ending'). #() } }.

c report displayNl.
