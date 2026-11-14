"EXPECT: ok 18"
"The acceptor's rules (cluster/acceptor.st) called directly, one rule per check, and the
 append failure in the simulator (proto_db coordinator.py _route, _refusal, _decide,
 _on_release, the plain query, _attach_locked's first-start marker, _tier_failed).
 (1) The dispatcher (core.st's checks, then the handlers of acceptor.st) drops a message from a non-member or from itself, drops and counts a voter-set
 mismatch on a fingerprinted type, hands request, renew, release and query to the acceptor
 lane and leaves the rest. (2) The acceptor drops a non-member; this node's own request is
 decided as a peer's and answered in the step's vote, never sent (CC1), a grant appending its
 promise, uncounted; its own refusal is the vote too; its own release raises no suspicion. (3-4) The acceptor's refusals in proto_db's order: learner, tier_failed, rejoining, with
 the highest term, the accepted root and certain; a fenced node sends nothing for a request, a
 renewal or a release (proto_db _enqueue) and still answers a plain query. (5) bad_ballot, stale_term,
 term_taken; a grant of a new term appends one synced promise and carries the accepted and
 committed roots; a duplicate appends nothing. (6) A grant that ends an expired one makes the
 node suspect: certain false. (7) A release frees the grant and closes the term; one held and
 not certain makes the node suspect. (8) The plain query: ok with promised max(termsSeen,
 accepted label), empty while rejoining, learner, unknown once the tier failed (no roots,
 promised 0); a ballot query is not answered here. (9) acceptStart: marks a learner's or a
 lone voter's empty log rejoined (synced), leaves a voter with other voters rejoining, and a
 start delivered again rebuilds nothing (the grace keeps its end). (10) PBSuspect raises the
 suspicion. (11) An append failure fails the tier (the first reason kept). (12) In the
 simulator, a grant whose promise cannot be written is never replied and the node then refuses
 tier_failed; the discarded step leaves no grant and no logged promise. (13) The wire remaining
 is seconds. (14) Constructors refuse bad arguments. (15) Every grant, renewals and duplicates
 included, counts grants_given; a refusal does not. (16) loggedPromise belongs to the log it was
 written to: over another log (a re-attach, Task 20) a renewal writes its promise again. (17) The
 product rules hand PBStartNode to the acceptor; handler selectors are named from the type."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.

PBCoordinatorCore subclass: #SeenRules instanceVariableNames: 'seen'.

SeenRules class >> new
  ^ self basicNew setUp.

SeenRules >> setUp
  seen := OrderedCollection new.

SeenRules >> seen
  ^ seen.

SeenRules >> dispatchReceived: anEvent in: s now: t
  (#('grant' 'reject') includes: anEvent message type) ifTrue: [seen add: anEvent message].
  ^ super dispatchReceived: anEvent in: s now: t.

| c core peers config three four one marker root accepted logged stateOf vs msg request renew release query counted reattached
  step reply send fenced s d sim g pair |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :someIds | PBClusterConfig nodeId: id peers: (peers value: someIds) options: Dictionary new].
three := #('n0' 'n1' 'n2').
four := #('n0' 'n1' 'n2' 'n3').
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
root := PBRootRecord segment: (ByteArray new: 16) offset: 100 epoch: 1.
accepted := PBLogAppend kind: #accepted label: 4097 root: root sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
"The acceptor state of anId among someIds over appends, started at 0 (grace end 3333334)."
stateOf := [:id :someIds :appends | PBAcceptorState config: (config value: id value: someIds) logged: (logged value: appends) now: 0].
vs := (config value: 'n1' value: three) membership fingerprint.
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
request := [:from :term :inc | msg value: 'request' value: from value: { 'term' -> term. 'rid' -> 1. 'inc' -> inc. 'vs' -> vs }].
renew := [:from :term :inc | msg value: 'renew' value: from value: { 'term' -> term. 'rid' -> 1. 'inc' -> inc. 'vs' -> vs }].
release := [:from :term :inc :certain | msg value: 'release' value: from value: { 'term' -> term. 'inc' -> inc. 'root' -> nil.
  'committed' -> nil. 'certain' -> certain. 'held' -> true. 'next' -> nil. 'more' -> false }].
query := [:from :ballot | msg value: 'query' value: from value: { 'rid' -> 3. 'inc' -> 1. 'ballot' -> ballot. 'vs' -> vs }].
"The one reply message of anAcceptorStep."
reply := [:aStep | | sends | sends := aStep reply select: [:e | e isKindOf: PBSend].
  sends size = 1 ifTrue: [sends first message] ifFalse: [sends]].
send := [:aStep | (aStep reply select: [:e | e isKindOf: PBSend]) collect: [:e | e to]].
"The stats a step counts."
counted := [:aStep | (aStep reply select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]].
"aState attached to another log (aLoggedRoots), its lease activity kept: the state a re-attach
 would build (Task 20); a test seam through the private setter."
reattached := [:aState :aLoggedRoots | PBAcceptorState basicNew _setConfig: aState config grants: aState grants
  accepted: aLoggedRoots accepted committed: aLoggedRoots committed seqSeen: aState seqSeen suspectTerm: aState suspectTerm
  rejoined: aLoggedRoots isRejoined rejoinBallot: aState rejoinBallot tierFailed: nil fenced: aState fenced log: aLoggedRoots
  loggedPromise: { aState log. aState loggedPromise }].
g := 4000000.

"(1) The dispatcher's routing."
s := PBNodeState config: (config value: 'n1' value: three) inc: 5.
d := [:anEvent | (core dispatch: anEvent in: s now: g) effects collect: [:e | e class name]].
c that: 'the dispatcher drops unknown senders and itself, counts a vs mismatch, routes the acceptor lane'
  is: { d value: (PBReceived message: (PBClusterMessage type: 'request' from: 'zz' fields: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs })).
    d value: (request value: 'n1' value: 4097 value: 1).
    (core dispatch: (msg value: 'renew' value: 'n0' value: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'vs' -> (vs + 1) }) in: s now: g) effects
      collect: [:e | e stat].
    d value: (msg value: 'query' value: 'n0' value: { 'rid' -> 3. 'inc' -> 1. 'ballot' -> 0. 'vs' -> (vs + 1) }).
    { request value: 'n0' value: 4096 value: 1. renew value: 'n0' value: 4096 value: 1.
      release value: 'n0' value: 4096 value: 1 value: true. query value: 'n0' value: 0 } collect: [:e | d value: e].
    d value: (msg value: 'want' value: 'n0' value: #()) }
  equals: { #(). #(). #('config_mismatches'). #(#PBCount). #(#(#PBToAcceptor) #(#PBToAcceptor) #(#PBToAcceptor) #(#PBToAcceptor)). #() }.

"(2) The acceptor drops a non-member and decides this node's own messages (CC1)."
s := stateOf value: 'n1' value: three value: { marker }.
step := core accept: (request value: 'n1' value: 4097 value: 1) in: s now: g.
pair := { (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'zz' fields: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs })) in: s now: g) state == s.
  step reply. step vote type. step vote from. step vote at: 'term'. step appends collect: [:a | { a kind. a label }].
  step state grants activeGrant holder.
  (core accept: (request value: 'n1' value: 4097 value: 1) in: s now: 0) vote at: 'reason'.
  (core accept: (request value: 'n0' value: 4096 value: 1) in: s now: g) vote.
  (core accept: (release value: 'n1' value: 4097 value: 1 value: false) in: step state now: g + 1000) state suspectTerm.
  (core accept: (release value: 'n1' value: 4097 value: 1 value: true) in: step state now: g + 3000000) state suspectTerm.
  (core accept: (release value: 'n1' value: 4097 value: 1 value: true) in: step state now: g + 1000) state grants activeGrant }.
c that: 'the acceptor drops a non-member; its own request is decided and answered in the vote, never sent'
  is: pair
  equals: { true. #(). 'grant'. 'n1'. 4097. #(#(#promise 4097)). 'n1'. 'starting'. nil. 0. 0. nil }.

"(3) Refusals of the acceptor's state, in proto_db _refusal's order; a fenced node sends nothing."
fenced := [:aState | PBAcceptorState basicNew _setConfig: aState config grants: aState grants accepted: aState accepted
  committed: aState committed seqSeen: aState seqSeen suspectTerm: aState suspectTerm rejoined: aState isRejoined
  rejoinBallot: aState rejoinBallot tierFailed: aState tierFailed fenced: 'a test fence' log: aState log
  loggedPromise: { aState log. aState loggedPromise }].
s := fenced value: (stateOf value: 'n1' value: three value: { marker }).
c that: 'a fenced node sends nothing for a request, a renewal or a release, and answers a plain query'
  is: ({ request value: 'n0' value: 4096 value: 1. renew value: 'n0' value: 4096 value: 1.
      release value: 'n0' value: 4096 value: 1 value: true } collect: [:e | | st | st := core accept: e in: s now: g.
        { st reply. st appends. st state == s }])
    , { (reply value: (core accept: (query value: 'n2' value: 0) in: s now: g)) at: 'state' }
  equals: { #(#() #() true). #(#() #() true). #(#() #() true). 'ok' }.
s := stateOf value: 'n3' value: four value: { marker }.
c that: 'refusals: learner before tier_failed, tier_failed before rejoining'
  is: { (reply value: (core accept: (request value: 'n0' value: 4096 value: 1)
      in: (core accept: (PBAppendFailed reason: 'disk') in: s now: g) state now: g)) at: 'reason'.
    (reply value: (core accept: (request value: 'n0' value: 4096 value: 1)
      in: (core accept: (PBAppendFailed reason: 'disk') in: (stateOf value: 'n1' value: three value: #()) now: g) state now: g)) at: 'reason'.
    (reply value: (core accept: (request value: 'n0' value: 4096 value: 1) in: (stateOf value: 'n1' value: three value: #()) now: g)) at: 'reason' }
  equals: #('learner' 'tier_failed' 'rejoining').

"(4) A refusal of the state reports the highest term, the accepted root and certain; nothing changes."
s := stateOf value: 'n1' value: three value: { accepted }.
step := core accept: (request value: 'n0' value: 8192 value: 1) in: s now: g.
c that: 'a state refusal carries highest, the accepted root, certain and appends nothing'
  is: { (reply value: step) at: 'reason'. (reply value: step) at: 'highest'. (PBClusterMessage rootFrom: ((reply value: step) at: 'root')) key.
    (reply value: step) at: 'certain'. step appends. step state == s. send value: step }
  equals: { 'rejoining'. 4097. (PBLabeledRoot label: 4097 record: root) key. true. #(). true. #('n0') }.

"(5) The grant rules: bad_ballot, a grant with its promise, a duplicate, stale_term, term_taken."
s := stateOf value: 'n1' value: three value: { marker. accepted }.
step := core accept: (request value: 'n0' value: 8193 value: 1) in: s now: g.
pair := { (reply value: step) at: 'reason'. step appends }.
step := core accept: (request value: 'n0' value: 8192 value: 1) in: s now: g.
pair := pair , { (reply value: step) type. step appends collect: [:a | { a kind. a label. a sync }].
  (PBClusterMessage rootFrom: ((reply value: step) at: 'root')) key. (reply value: step) at: 'committed'. (reply value: step) at: 'certain'.
  step state loggedPromise }.
s := step state.
step := core accept: (request value: 'n0' value: 8192 value: 1) in: s now: g + 1000.
pair := pair , { (reply value: step) type. step appends. step state loggedPromise }.
pair := pair , { (reply value: (core accept: (request value: 'n2' value: 4098 value: 1) in: s now: g + 1000)) at: 'reason' }.
step := core accept: (release value: 'n0' value: 8192 value: 1 value: true) in: s now: g + 1000.
pair := pair , { (reply value: (core accept: (request value: 'n0' value: 8192 value: 2) in: step state now: g + 2000)) at: 'reason' }.
c that: 'bad_ballot, a grant appends its synced promise and carries the roots, a duplicate appends nothing, stale_term, term_taken'
  is: pair
  equals: { 'bad_ballot'. #(). 'grant'. #(#(#promise 8192 true)). (PBLabeledRoot label: 4097 record: root) key. nil. true. 8192.
    'grant'. #(). 8192. 'stale_term'. 'term_taken' }.

"(6) A grant that ends an expired one: the node is suspect for it."
s := (core accept: (request value: 'n0' value: 8192 value: 1) in: (stateOf value: 'n1' value: three value: { marker }) now: g) state.
step := core accept: (request value: 'n2' value: 8194 value: 1) in: s now: g + 2000000.
c that: 'ending an expired grant makes the node suspect: certain false'
  is: { (reply value: step) type. (reply value: step) at: 'certain'. step state suspectTerm.
    (reply value: (core accept: (request value: 'n2' value: 8194 value: 1) in: s now: g + 1000)) at: 'certain' }
  equals: { 'grant'. false. 8192. true }.

"(7) Releases."
step := core accept: (release value: 'n0' value: 8192 value: 1 value: true) in: s now: g + 1000.
pair := { step state grants activeGrant. step state grants highestGranted. step state suspectTerm. step appends. step reply.
  (core accept: (release value: 'n0' value: 8192 value: 1 value: false) in: s now: g + 1000) state suspectTerm.
  (core accept: (release value: 'n0' value: 8192 value: 2 value: true) in: s now: g + 1000) state grants activeGrant term.
  (core accept: (release value: 'n0' value: 8192 value: 1 value: true) in: s now: g + 2000000) state suspectTerm }.
c that: 'a release frees its grant and closes the term; uncertain or after expiry the node is suspect'
  is: pair equals: { nil. 8192. 0. #(). #(). 8192. 8192. 8192 }.

"(8) The plain query."
s := (core accept: (request value: 'n0' value: 8192 value: 1) in: (stateOf value: 'n1' value: three value: { marker. accepted }) now: g) state.
pair := [:aState | | m | m := reply value: (core accept: (query value: 'n2' value: 0) in: aState now: g).
  { m at: 'state'. m at: 'promised'. m at: 'certain'. (m at: 'root') notNil. (m at: 'committed') notNil. m at: 'ballot' }].
c that: 'a plain query answers ok, empty, learner or unknown with promised max(termsSeen, accepted label); a ballot query is not answered'
  is: { pair value: s. pair value: (stateOf value: 'n1' value: three value: { marker. accepted }).
    pair value: (stateOf value: 'n1' value: three value: { accepted }). pair value: (stateOf value: 'n3' value: four value: { marker }).
    pair value: (core accept: (PBAppendFailed reason: 'disk') in: s now: g) state.
    (core accept: (query value: 'n2' value: 8194) in: s now: g) reply }
  equals: { #('ok' 8192 true true false 0). #('ok' 4097 true true false 0). #('empty' 4097 true true false 0).
    #('learner' 0 true false false 0). #('unknown' 0 false false false 0). #() }.

"(9) acceptStart."
one := PBAcceptorState config: (config value: 'n0' value: #('n0')) logged: (logged value: #()) now: 0.
step := core accept: PBStartNode new in: one now: 5000000.
pair := { step appends collect: [:a | { a kind. a sync }]. step state isRejoined.
  (core accept: PBStartNode new in: step state now: 6000000) appends.
  (core accept: PBStartNode new in: step state now: 6000000) state grants isStarting: 4000000.
  (core accept: PBStartNode new in: (stateOf value: 'n3' value: four value: #()) now: 0) appends size.
  (core accept: PBStartNode new in: (stateOf value: 'n1' value: three value: #()) now: 0) appends.
  (core accept: PBStartNode new in: (stateOf value: 'n1' value: three value: #()) now: 0) state isRejoined }.
c that: 'acceptStart marks a lone voter''s or learner''s empty log, leaves a rejoin, rebuilds nothing again'
  is: pair equals: { #(#(#rejoined true)). true. #(). false. 1. #(). false }.

"(10) PBSuspect."
s := stateOf value: 'n1' value: three value: { marker }.
step := core accept: (PBSuspect term: 4096) in: s now: g.
c that: 'PBSuspect raises the suspicion; grants are then uncertain'
  is: { step state suspectTerm. (core accept: (PBSuspect term: 10) in: step state now: g) state suspectTerm.
    (reply value: (core accept: (request value: 'n0' value: 8192 value: 1) in: step state now: g)) at: 'certain' }
  equals: { 4096. 4096. false }.

"(11) An append failure fails the tier for good; the first reason is kept."
step := core accept: (PBAppendFailed reason: 'first') in: s now: g.
c that: 'an append failure fails the tier, the first reason kept'
  is: { step state tierFailed. (core accept: (PBAppendFailed reason: 'second') in: step state now: g) state tierFailed. step reply }
  equals: { 'first'. 'first'. #() }.

"(12) In the simulator: the grant whose promise cannot be written is withdrawn."
d := Dictionary new.
three do: [:id | d at: id put: { marker }].
sim := PBSim seed: 3 ids: three rules: SeenRules new options: Dictionary new logs: d.
sim failAppends: 'n1'.
sim inject: (request value: 'n0' value: 4096 value: 1) message to: 'n1' at: g.
sim inject: (request value: 'n2' value: 4098 value: 1) message to: 'n1' at: g + 1000.
sim runUntil: [false] steps: 1000.
c that: 'a grant whose promise append fails is never replied nor kept; the node then refuses tier_failed'
  is: { (sim diskOf: 'n1') size. (sim nodeAt: 'n1') acceptor tierFailed notNil.
    sim trace anySatisfy: [:l | l includesSubstring: 'n0 <- n1 grant'].
    (sim trace select: [:l | l includesSubstring: 'n2 <- n1 reject']) size.
    (sim nodeAt: 'n1') acceptor loggedPromise. (sim nodeAt: 'n1') acceptor grants activeGrant }
  equals: { 1. true. false. 1. 0. nil }.

"(13) The wire remaining is seconds, a Float."
s := (core accept: (request value: 'n0' value: 8192 value: 1) in: (stateOf value: 'n1' value: three value: { marker }) now: g) state.
c that: 'busy remaining and starting remaining are seconds'
  is: { (reply value: (core accept: (request value: 'n2' value: 8194 value: 1) in: s now: g + 500000)) at: 'remaining'.
    (reply value: (core accept: (request value: 'n0' value: 8192 value: 1) in: (stateOf value: 'n1' value: three value: { marker }) now: 333334))
      at: 'remaining'. PBCoordinatorCore wireSeconds: 0 }
  equals: { 1.5. 3.0. 0.0 }.

"(14) Constructors."
c that: 'PBSuspect and PBAppendFailed refuse bad arguments; PBCount names a stat'
  is: ({ [PBSuspect term: 0]. [PBSuspect term: 'x']. [PBAppendFailed reason: '']. [PBCount stat: nil] } collect: [:b |
    [b value. 'none'] on: PBValidationError do: [:e | 'refused']]) , { (PBCount stat: 'config_mismatches') stat }
  equals: #('refused' 'refused' 'refused' 'refused' 'config_mismatches').

"(15) grants_given."
s := stateOf value: 'n1' value: three value: { marker }.
step := core accept: (request value: 'n0' value: 8192 value: 1) in: s now: g.
c that: 'every grant counts grants_given, renewals and duplicates included; a refusal does not'
  is: { counted value: step. counted value: (core accept: (renew value: 'n0' value: 8192 value: 1) in: step state now: g + 1000).
    counted value: (core accept: (request value: 'n0' value: 8192 value: 1) in: step state now: g + 1000).
    counted value: (core accept: (request value: 'n2' value: 8194 value: 1) in: step state now: g + 1000).
    counted value: (core accept: (request value: 'n0' value: 8192 value: 1) in: s now: 0) }
  equals: { #('grants_given'). #('grants_given'). #('grants_given'). #(). #() }.

"(16) loggedPromise belongs to its log."
s := step state.
one := logged value: { marker }.
pair := reattached value: s value: one.
c that: 'over another log the logged promise is 0 and a renewal writes its promise again; over its own log it writes nothing'
  is: { s loggedPromise. pair loggedPromise. pair grants activeGrant term.
    (core accept: (renew value: 'n0' value: 8192 value: 1) in: s now: g + 1000) appends size.
    (core accept: (renew value: 'n0' value: 8192 value: 1) in: pair now: g + 1000) appends collect: [:a | { a kind. a label. a sync }].
    (core accept: (renew value: 'n0' value: 8192 value: 1) in: pair now: g + 1000) state loggedPromise }
  equals: { 8192. 0. 8192. 0. #(#(#promise 8192 true)). 8192 }.

"(17) The start reaches the acceptor; handler names."
s := PBNodeState config: (config value: 'n1' value: three) inc: 5.
c that: 'PBStartNode goes to the acceptor; handlers are named from the type'
  is: { (core dispatch: PBStartNode new in: s now: 0) effects collect: [:e | { e class name. e event class name }].
    PBCoordinatorCore handlerFor: 'permit_req' prefix: 'received'. PBCoordinatorCore handlerFor: 'query' prefix: 'accept' }
  equals: { #(#(#PBToAcceptor #PBStartNode)). #receivedPermitReq:in:now:. #acceptQuery:in:now: }.

c report displayNl.
