"EXPECT: ok 23"
"The rejoin's rules (cluster/rejoin.st) called directly, one guard per check (proto_db
 coordinator.py _rejoin_answers, _rejoin_decision, _rejoin_round, _gather, _complete_rejoin,
 _publish_rejoin, _on_ballot_query, force_rejoin, needs_confirmation, confirmed). drive runs a
 rejoining n0 (one of three voters, startup grace 0) through its effects: every query reaches
 the real acceptor of its target (or none: a silent member), whose answer, passed through a
 tamper block, comes back; the acceptor steps run on n0's acceptor; a probe is answered readable
 or not; when nothing else is due, the timer of a gather fires. It stops when nothing is due
 (a retry waits for its timer). (1) The answers a rejoin needs: min(V - 1, V - majority + 1),
 majority - 1 when forced. (2) The decision: 'new' only when every other voter answered loaded,
 none with an accepted root, none with a term; 'rootless' with a term; 'witnesses' at the
 threshold; 'unknown', 'learner', this node and a non-member never count; 'forced' at
 majority - 1 loaded. (3) The ballot is above every promise and label reported, the acceptor's
 highest term and the hint, at this node's rank. (4) A ballot answer that does not echo the
 ballot counts as unknown. (5) The witness: an 'ok' acceptor promises the ballot, appended
 synced, once, and answers echoing it; a lower term is refused afterwards; a lower grant it
 ends makes it suspect; a rejoining one answers 'empty' with ballot 0 and promises nothing; a
 fenced one answers nothing. (6) The adoption: the promise of learnt, the accepted root, the
 rejoined marker, in that order, synced; the floor learnt, termsSeen the promises only; the
 ballot; committed knowledge; nothing on a rejoined acceptor; a first start appends the marker
 only and keeps termsSeen 0. (7) forceRejoin on a survivor forgets a committed root above its
 accepted root and asks for a confirmation; else nothing. (8) needsConfirmation: true at the
 attach, false after PBConfirmed, which the dispatcher hands to its acceptor. (9) A full rejoin
 on two witnesses: a plain round, a ballot round, the probe, the adoption; counted
 rejoin_ballots and rejoins, the hint raised. (10) Witnesses that do not echo the ballot block
 the rejoin, which retries. (11) An unreadable adopted root blocks it. (12) A silent member is
 asked gatherAttempts times. (13) An answer to another rid is ignored; one of another
 incarnation is a stale reply. (14) Forced: completes on one loaded answer after the plain
 round, without a ballot, and drops a committed root above the adopted root. (15) No rejoin
 starts on a failed tier or a fenced node. (16) An adoption whose append failed fails the
 rejoin. (17) rejoinBlockedIn: names the reason only while the node rejoins. (18) A ballot query
 raises the dispatcher's hint only toward an 'ok', unfenced view. (19) PBLogDetached and a
 report over another log drop the rejoin and its forced flag; one forced before any report
 runs for the first log. (20) A failed rejoin restarts over a new log; an adoption the failed
 tier refused fails it, with the reason. (21) A forceRejoin during a ballot round blocks it.
 (22) An adoption for a detached log changes nothing on the log attached next; a late report of
 the detached log starts no rejoin; a forceRejoin while detached carries to the next log. (23)
 A forceRejoin is bound to the log reported then."
Import from: 'protobase'.
Import from: '_check'.

| c core peers cfg three five marker logged viewOf rec r1 r2 acc count rejoining witness queryOf ans retag drive run
  out s v step B ids fenced msgs ballotOf phaseOf blockedOf v2 forcedOf |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
three := #('n0' 'n1' 'n2').
five := #('n0' 'n1' 'n2' 'n3' 'n4').
cfg := [:id :someIds | PBClusterConfig nodeId: id peers: (peers value: someIds)
  options: (Dictionary new at: #startupGrace put: 0; at: #voters put: someIds; yourself)].
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
viewOf := [:id :appends | PBAcceptorState config: (cfg value: id value: three) logged: (logged value: appends) now: 0].
rec := [:aLabel :e | PBLabeledRoot label: aLabel record: (PBRootRecord segment: (ByteArray new: 16) offset: 64 + e epoch: e)].
r1 := rec value: 4096 value: 1.
r2 := rec value: 8192 value: 2.
acc := [:r | PBLogAppend kind: #accepted label: r label root: r record sync: true].
count := [:r | PBLogAppend kind: #committed label: r label root: r record sync: true].
"An empty log (rejoining) and a witness that holds r1 accepted and committed."
rejoining := [:id | viewOf value: id value: #()].
witness := [:id | viewOf value: id value: { marker. acc value: r1. count value: r1 }].
queryOf := [:from :ballot | PBReceived message: (PBClusterMessage type: 'query' from: from fields: {
  'rid' -> 3. 'inc' -> 1. 'ballot' -> ballot. 'vs' -> (cfg value: 'n0' value: three) membership fingerprint })].
"A PBRejoinAnswer: { from. accepted. committed. promised. state. ballot }."
ans := [:a | PBRejoinAnswer from: (PBClusterMessage type: 'answer' from: (a at: 1) fields: {
  'rid' -> 1. 'inc' -> 1. 'root' -> (PBClusterMessage rootValue: (a at: 2)). 'committed' -> (PBClusterMessage rootValue: (a at: 3)).
  'certain' -> true. 'promised' -> (a at: 4). 'state' -> (a at: 5). 'ballot' -> (a at: 6) })].
"anAnswer with the fields of aDictionary replaced."
retag := [:m :d | PBClusterMessage type: 'answer' from: m from fields:
  (#('rid' 'inc' 'root' 'committed' 'certain' 'promised' 'state' 'ballot') collect: [:f | f -> (d at: f ifAbsent: [m at: f])])].
"{ node state. its acceptor state. every effect. the peers' acceptor states }: n0's dispatcher run from
 aFirst (an event; nil: its start) over aView; somePeers a Dictionary id -> acceptor state (a
 missing id is silent); aTamper answers the answer to deliver, or nil to lose it; isReadable
 answers every probe; isDiscarded discards the adoption's step (its append failed)."
drive := [:aState :aView :somePeers :aTamper :isReadable :isDiscarded :aFirst | | queue state view all timers n |
  view := aView.
  state := aState.
  all := OrderedCollection new.
  timers := OrderedCollection new.
  queue := OrderedCollection with: (aFirst ifNil: [PBAcceptorDecided step: (core accept: PBStartNode new in: view now: 0)]).
  n := 0.
  [n := n + 1. n < 400 and: [queue notEmpty or: [state rejoin notNil and: [state rejoin phase = #gather and: [timers notEmpty]]]]] whileTrue: [
    | ev st |
    ev := queue isEmpty
      ifTrue: [PBTimerFired token: timers last token event: #rejoin]
      ifFalse: [queue removeFirst].
    st := core dispatch: ev in: state now: 1000.
    state := st state.
    st effects do: [:e |
      all add: e.
      ((e isKindOf: PBSend) and: [e message type = 'query']) ifTrue: [
        (somePeers includesKey: e to) ifTrue: [ | pstep |
          pstep := core accept: (PBReceived message: e message) in: (somePeers at: e to) now: 1000.
          somePeers at: e to put: pstep state.
          (pstep reply select: [:r | r isKindOf: PBSend]) do: [:r | | m |
            m := aTamper value: r message.
            m notNil ifTrue: [queue add: (PBReceived message: m)]]]].
      (e isKindOf: PBToAcceptor) ifTrue: [ | astep |
        astep := core accept: e event in: view now: 1000.
        (isDiscarded and: [e event isKindOf: PBRejoinLearnt])
          ifTrue: [queue add: (PBAcceptorDiscarded step: astep)]
          ifFalse: [
            view := astep state.
            queue add: (PBAcceptorDecided step: astep)]].
      (e isKindOf: PBProbeRoot) ifTrue: [queue add: (PBRootProbed token: e token readable: isReadable)].
      ((e isKindOf: PBTimer) and: [e event = #rejoin]) ifTrue: [timers add: e]]].
  { state. view. all asArray. somePeers }].
"drive from n0's start over a rejoining log, the peers of someAssociations, aTamper, readable."
run := [:somePairs :aTamper | drive value: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) value: (rejoining value: 'n0')
  value: (Dictionary new addAll: somePairs; yourself) value: aTamper value: true value: false value: nil].
"The phase of aState's rejoin and why it is blocked ('' when none), nil-safe."
phaseOf := [:aState | aState rejoin isNil ifTrue: [nil] ifFalse: [aState rejoin phase]].
blockedOf := [:aState | (aState rejoin isNil or: [aState rejoin blocked isNil]) ifTrue: [''] ifFalse: [aState rejoin blocked]].
forcedOf := [:aState | aState rejoin notNil and: [aState rejoin isForced]].
msgs := [:effects | (effects select: [:e | (e isKindOf: PBSend) and: [e message type = 'query']]) collect: [:e | { e to. e message at: 'ballot' }]].
ballotOf := [:effects | ((effects select: [:e | (e isKindOf: PBSend) and: [e message type = 'query' and: [(e message at: 'ballot') > 0]]])
  collect: [:e | e message at: 'ballot']) asSet asArray].

"(1) The answers needed."
c that: 'answers needed: three voters 2 (forced 1), five voters 3 (forced 2)'
  is: { core rejoinAnswersNeeded: (PBNodeState config: (cfg value: 'n0' value: three) inc: 1) forced: false.
    core rejoinAnswersNeeded: (PBNodeState config: (cfg value: 'n0' value: three) inc: 1) forced: true.
    core rejoinAnswersNeeded: (PBNodeState config: (cfg value: 'n0' value: five) inc: 1) forced: false.
    core rejoinAnswersNeeded: (PBNodeState config: (cfg value: 'n0' value: five) inc: 1) forced: true }
  equals: #(2 1 3 2).

"(2) The decision."
s := PBNodeState config: (cfg value: 'n0' value: three) inc: 1.
out := [:someSpecs :isForced | | d | d := core rejoinDecision: (someSpecs collect: [:a | ans value: a]) forced: isForced in: s.
  d isNil ifTrue: [nil] ifFalse: [{ d first asSortedCollection asArray. d last }]].
c that: 'the decision: new, rootless, witnesses, forced, or none'
  is: {
    out value: { { 'n1'. nil. nil. 0. 'empty'. 0 }. { 'n2'. nil. nil. 0. 'empty'. 0 } } value: false.
    out value: { { 'n1'. nil. nil. 4096. 'empty'. 0 }. { 'n2'. nil. nil. 0. 'empty'. 0 } } value: false.
    out value: { { 'n1'. nil. nil. 0. 'empty'. 0 } } value: false.
    out value: { { 'n1'. r1. r1. 4096. 'ok'. 0 }. { 'n2'. nil. nil. 0. 'empty'. 0 } } value: false.
    out value: { { 'n1'. r1. r1. 4096. 'ok'. 0 }. { 'n2'. r1. nil. 4096. 'ok'. 0 } } value: false.
    out value: { { 'n1'. r1. r1. 4096. 'ok'. 0 }. { 'n2'. nil. nil. 0. 'unknown'. 0 } } value: false.
    out value: { { 'n1'. r1. r1. 4096. 'ok'. 0 }. { 'n2'. nil. nil. 0. 'learner'. 0 } } value: false.
    out value: { { 'n1'. r1. r1. 4096. 'ok'. 0 }. { 'n0'. r1. nil. 4096. 'ok'. 0 }. { 'n9'. r1. nil. 4096. 'ok'. 0 } } value: false.
    out value: { { 'n1'. nil. nil. 0. 'empty'. 0 } } value: true.
    out value: { { 'n1'. nil. nil. 0. 'unknown'. 0 } } value: true }
  equals: { { #('n1' 'n2'). #new }. { #('n1' 'n2'). #rootless }. nil. nil. { #('n1' 'n2'). #witnesses }. nil. nil. nil.
    { #('n1'). #forced }. nil }.

"(3) The ballot."
s := PBNodeState config: (cfg value: 'n0' value: three) inc: 1.
B := core rejoinBallotFor: { ans value: { 'n1'. r1. r2. 4096. 'ok'. 0 }. ans value: { 'n2'. r1. nil. 12000. 'ok'. 0 } } in: s.
c that: 'the ballot: above every promise and label, the highest term seen and the hint, at this rank'
  is: { B. core rejoinBallotFor: { ans value: { 'n1'. r1. r2. 4096. 'ok'. 0 } } in: s.
    core rejoinBallotFor: #() in: (s with: { #acceptorView -> ((rejoining value: 'n0') withGrants: ((rejoining value: 'n0') grants restore: 30000 seen: 0)
      suspectTerm: 0 rejoined: false tierFailed: nil loggedPromise: 0) }).
    core rejoinBallotFor: #() in: (s with: { #hints -> ((PBHints seed: 1) with: { #hint -> 40000 }) }) }
  equals: { PBMembership ballotAfter: 12000 rank: s config rank. PBMembership ballotAfter: 8192 rank: s config rank.
    PBMembership ballotAfter: 30000 rank: s config rank. PBMembership ballotAfter: 40000 rank: s config rank }.

"(4) Echoed ballots."
c that: 'an ok answer that does not echo the ballot (0 or another ballot) counts as unknown'
  is: ((core _confirming: 777 answers: { ans value: { 'n1'. r1. nil. 0. 'ok'. 777 }. ans value: { 'n2'. r1. nil. 0. 'ok'. 0 }.
    ans value: { 'n2'. nil. nil. 0. 'empty'. 0 }. ans value: { 'n2'. r1. nil. 0. 'ok'. 778 } }) collect: [:a | a state])
  equals: #('ok' 'unknown' 'empty' 'unknown').

"(5) The witness."
v := witness value: 'n1'.
step := core accept: (queryOf value: 'n0' value: 20481) in: v now: 1000.
fenced := PBAcceptorState basicNew _setConfig: v config grants: v grants accepted: v accepted committed: v committed seqSeen: v seqSeen
  suspectTerm: 0 rejoined: true rejoinBallot: 0 tierFailed: nil fenced: 'a test fence' log: v log loggedPromise: { v log. 0 }.
out := { step appends collect: [:a | { a kind. a label. a sync }].
  (step reply detect: [:e | e isKindOf: PBSend]) message at: 'state'.
  (step reply detect: [:e | e isKindOf: PBSend]) message at: 'ballot'.
  ((step reply detect: [:e | e isKindOf: PBSend]) message at: 'root') notNil.
  ((step reply detect: [:e | e isKindOf: PBSend]) message at: 'promised') >= 20481.
  (core accept: (queryOf value: 'n2' value: 20481) in: step state now: 1000) appends.
  (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'n2' fields: { 'term' -> 16386. 'rid' -> 1. 'inc' -> 1.
    'vs' -> v config membership fingerprint })) in: step state now: 1000) reply first message type.
  [:granted | | st | st := core accept: (queryOf value: 'n0' value: 20481) in: granted now: 1000.
    { st state suspectTerm. (st reply detect: [:e | e isKindOf: PBSend]) message at: 'certain' }]
    value: (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'n2' fields: { 'term' -> 8194. 'rid' -> 1. 'inc' -> 1.
      'vs' -> v config membership fingerprint })) in: v now: 1000) state.
  [:st | { st appends. (st reply detect: [:e | e isKindOf: PBSend]) message at: 'state'. (st reply detect: [:e | e isKindOf: PBSend]) message at: 'ballot' }]
    value: (core accept: (queryOf value: 'n0' value: 20481) in: (rejoining value: 'n1') now: 1000).
  (core accept: (queryOf value: 'n0' value: 20481) in: fenced now: 1000) reply }.
c that: 'the witness promises, logs once, echoes, answers after the promise; refuses lower; suspect (certain false) for an ended grant; empty and fenced'
  is: out
  equals: { #(#(#promise 20481 true)). 'ok'. 20481. true. true. #(). 'reject'. #(8194 false). { #(). 'empty'. 0 }. #() }.

"(6) The adoption."
v := rejoining value: 'n0'.
step := core accept: (PBRejoinLearnt learnt: 20481 seen: 8192 accepted: r1 committed: r2 ballot: 20481 log: v log) in: v now: 1000.
out := { step appends collect: [:a | { a kind. a label. a sync }]. step state isRejoined. step state rejoinBallot.
  step state accepted key = r1 key. step state committed key = r2 key. step state grants termsSeen. step state grants highestSeen.
  (core accept: (PBReceived message: (PBClusterMessage type: 'request' from: 'n2' fields: { 'term' -> 20481. 'rid' -> 1. 'inc' -> 1.
    'vs' -> v config membership fingerprint })) in: step state now: 1000) reply first message type.
  [:w | (core accept: (PBRejoinLearnt learnt: 0 seen: 0 accepted: nil committed: nil ballot: 0 log: w log) in: w now: 1000) state == w]
    value: (witness value: 'n0').
  [:st | { st appends collect: [:a | a kind]. st state grants termsSeen. st state isRejoined }]
    value: (core accept: (PBRejoinLearnt learnt: 0 seen: 0 accepted: nil committed: nil ballot: 0 log: v log) in: v now: 1000) }.
c that: 'the adoption: promise, accepted, marker in order, synced; floor, seen, ballot, committed; first start'
  is: { out first. out at: 2. out at: 3. out at: 4. out at: 5. out at: 6. out at: 7. out at: 8. out at: 9. out at: 10 }
  equals: { #(#(#promise 20481 true) #(#accepted 4096 true) #(#rejoined 0 true)). true. 20481. true. true. 8192. 20481. 'reject'.
    true. { #(#rejoined). 0. true } }.

"(7) forceRejoin on a survivor."
v := viewOf value: 'n1' value: { marker. acc value: r1 }.
v := (core accept: (PBLearnCommitted root: r2 accept: false logged: false) in: v now: 1000) state.
v := (core accept: PBConfirmed new in: v now: 1000) state.
step := core accept: PBForceRejoin new in: v now: 1000.
c that: 'forceRejoin on a survivor forgets a committed root above its accepted root and asks to confirm; else nothing'
  is: { v committed key = r2 key. v needsConfirmation. step state committed. step state accepted key = r1 key. step state needsConfirmation.
    [:w | (core accept: PBForceRejoin new in: w now: 1000) state == w] value: (witness value: 'n1').
    [:w | (core accept: PBForceRejoin new in: w now: 1000) state == w] value: (rejoining value: 'n1') }
  equals: { true. false. nil. true. true. true. true }.

"(8) The confirmation flag."
v := witness value: 'n1'.
c that: 'needsConfirmation: true at the attach, false after PBConfirmed, routed to the acceptor'
  is: { v needsConfirmation. (core accept: PBConfirmed new in: v now: 1000) state needsConfirmation.
    ((core dispatch: PBConfirmed new in: (PBNodeState config: v config inc: 1) now: 1000) effects collect: [:e | e event class name]) }
  equals: { true. false. #(#PBConfirmed) }.

"(9) A full rejoin on two witnesses."
out := run value: { 'n1' -> (witness value: 'n1'). 'n2' -> (witness value: 'n2') } value: [:m | m].
B := [:b | b isEmpty ifTrue: [0] ifFalse: [b first]] value: (ballotOf value: (out at: 3)).
c that: 'a full rejoin: plain round, ballot round, probe, adoption; counted; hint raised'
  is: { msgs value: (out at: 3). B > 4096. ((out at: 3) select: [:e | e isKindOf: PBProbeRoot]) size.
    ((out at: 3) select: [:e | (e isKindOf: PBToAcceptor) and: [e event isKindOf: PBRejoinLearnt]]) collect: [:e | e event ballot].
    ((out at: 3) select: [:e | e isKindOf: PBCount]) collect: [:e | e stat].
    (out at: 2) isRejoined. (out at: 2) rejoinBallot = B. (out at: 2) accepted key = r1 key. (out first) rejoin. (out first) hints hint >= B.
    ((out at: 4) at: 'n1') loggedPromise = B }
  equals: { { #('n1' 0). #('n2' 0). { 'n1'. B }. { 'n2'. B } }. true. 1. { B }. #('rejoin_ballots' 'rejoins'). true. true. true. nil. true. true }.

"(10) Witnesses that do not echo the ballot."
out := run value: { 'n1' -> (witness value: 'n1'). 'n2' -> (witness value: 'n2') }
  value: [:m | retag value: m value: (Dictionary new at: 'ballot' put: 0; yourself)].
c that: 'answers that do not echo the ballot block the rejoin, which retries'
  is: { (blockedOf value: out first) includesSubstring: 'too few members confirmed the rejoin ballot'.
    (phaseOf value: out first). (out at: 2) isRejoined. ((out at: 3) select: [:e | e isKindOf: PBToAcceptor]) size }
  equals: { true. #retry. false. 0 }.

"(11) An unreadable adopted root."
out := drive value: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) value: (rejoining value: 'n0')
  value: (Dictionary new at: 'n1' put: (witness value: 'n1'); at: 'n2' put: (witness value: 'n2'); yourself)
  value: [:m | m] value: false value: false value: nil.
c that: 'an unreadable adopted root blocks the rejoin, which retries'
  is: { (blockedOf value: out first) includesSubstring: 'cannot read the SpaceRoot'. (phaseOf value: out first). (out at: 2) isRejoined }
  equals: { true. #retry. false }.

"(12) A silent member."
out := run value: { 'n1' -> (witness value: 'n1') } value: [:m | m].
c that: 'a silent member is asked gatherAttempts times, then the round decides (here nothing: a retry)'
  is: { msgs value: (out at: 3). (phaseOf value: out first). out first config gatherAttempts }
  equals: { #(#('n1' 0) #('n2' 0) #('n2' 0) #('n2' 0)). #retry. 3 }.

"(13) Answers to another rid or incarnation."
out := run value: { 'n1' -> (witness value: 'n1'). 'n2' -> (witness value: 'n2') }
  value: [:m | m from = 'n2' ifTrue: [retag value: m value: (Dictionary new at: 'rid' put: (m at: 'rid') + 100; yourself)] ifFalse: [m]].
c that: 'an answer to another rid is ignored; one of another incarnation is a stale reply'
  is: { (msgs value: (out at: 3)) size. (phaseOf value: out first).
    (((run value: { 'n1' -> (witness value: 'n1'). 'n2' -> (witness value: 'n2') }
      value: [:m | m from = 'n2' ifTrue: [retag value: m value: (Dictionary new at: 'inc' put: 99; yourself)] ifFalse: [m]]) at: 3)
      select: [:e | (e isKindOf: PBCount) and: [e stat = 'stale_replies']]) size }
  equals: { 4. #retry. 3 }.

"(14) Forced."
v := viewOf value: 'n1' value: { marker. acc value: r1 }.
v := (core accept: (PBLearnCommitted root: r2 accept: false logged: false) in: v now: 1000) state.
s := (core dispatch: PBRejoinWanted new in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 1000) state.
out := drive value: s value: (rejoining value: 'n0') value: (Dictionary new at: 'n1' put: v; yourself)
  value: [:m | m] value: true value: false value: nil.
c that: 'forced: one loaded answer after a plain round, no ballot, a committed root above the adopted one dropped'
  is: { s rejoin isForced. ballotOf value: (out at: 3). (out at: 2) isRejoined. ((out at: 2) accepted notNil and: [(out at: 2) accepted key = r1 key]). (out at: 2) committed.
    (out at: 2) rejoinBallot }
  equals: { true. #(). true. true. nil. 0 }.

"(15) No rejoin on a failed tier or a fenced node."
v := (core accept: (PBAppendFailed reason: 'disk') in: (rejoining value: 'n0') now: 0) state.
c that: 'no rejoin starts on a failed tier or a fenced node'
  is: { (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v now: 0)) in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 0)
      state rejoin.
    (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: (rejoining value: 'n0') now: 0))
      in: ((PBNodeState config: (cfg value: 'n0' value: three) inc: 5) with: { #fenced -> 'a test fence' }) now: 0) state rejoin }
  equals: #(nil nil).

"(16) An adoption whose append failed."
out := drive value: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) value: (rejoining value: 'n0')
  value: (Dictionary new at: 'n1' put: (witness value: 'n1'); at: 'n2' put: (witness value: 'n2'); yourself)
  value: [:m | m] value: true value: true value: nil.
c that: 'an adoption whose append failed fails the rejoin'
  is: { (phaseOf value: out first). (blockedOf value: out first) includesSubstring: 'writing its acceptor log failed'. (out at: 2) isRejoined }
  equals: { #failed. true. false }.

"(17) rejoin_blocked."
out := run value: { 'n1' -> (witness value: 'n1'). 'n2' -> (witness value: 'n2') }
  value: [:m | retag value: m value: (Dictionary new at: 'ballot' put: 0; yourself)].
c that: 'rejoinBlockedIn: names the reason while rejoining, nil once rejoined'
  is: { ((core rejoinBlockedIn: out first) ifNil: ['']) includesSubstring: 'too few'.
    core rejoinBlockedIn: (out first with: { #acceptorView -> (witness value: 'n0') }) }
  equals: { true. nil }.

"(18) The witness's hint."
s := PBNodeState config: (cfg value: 'n1' value: three) inc: 5.
out := [:aView | (core _hintsIn: (core dispatch: (queryOf value: 'n0' value: 20481) in: (s with: { #acceptorView -> aView }) now: 1000) state) hint].
c that: 'a ballot query raises the hint when the view is an ok, unfenced witness only'
  is: { out value: (witness value: 'n1'). out value: (rejoining value: 'n1'). out value: fenced. (core _hintsIn: s) hint }
  equals: { 20481. 0. 0. 0 }.

"(19) Detach and re-attach drop the rejoin and its forced flag (proto_db detach,
 test_c2_audit_a_forced_rejoin_does_not_outlive_the_log_it_was_forced_for)."
v := rejoining value: 'n0'.
s := (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v now: 0)) in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 0) state.
s := (core dispatch: PBRejoinWanted new in: s now: 0) state.
out := { s rejoin isForced. s rejoin log == v log.
  [:st | { phaseOf value: st. forcedOf value: st }] value: (core dispatch: PBLogDetached new in: s now: 0) state.
  [:st | { st rejoin isForced. st rejoin phase. st rejoin log == v log }]
    value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: (rejoining value: 'n0') now: 0)) in: s now: 0) state.
  [:st | | v2 st2 | v2 := rejoining value: 'n0'.
    st2 := (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v2 now: 0)) in: st now: 0) state.
    { st2 rejoin isForced. st2 rejoin log == v2 log }]
    value: (core dispatch: PBRejoinWanted new in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 0) state }.
c that: 'a forced rejoin is dropped at detach and by a report over another log; forced before any report, it runs for the first'
  is: out
  equals: { true. true. { #detached. false }. { false. #gather. false }. #(true true) }.

"(20) A failed rejoin restarts over a replaced tier; an adoption the failed tier refused fails it."
out := drive value: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) value: (rejoining value: 'n0')
  value: (Dictionary new at: 'n1' put: (witness value: 'n1'); at: 'n2' put: (witness value: 'n2'); yourself)
  value: [:m | m] value: true value: true value: nil.
v := rejoining value: 'n0'.
s := (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) with: { #acceptorView -> v.
  #rejoin -> (PBRejoin idle with: { #phase -> #adopt. #log -> v log.
    #pending -> (PBRejoinLearnt learnt: 0 seen: 0 accepted: nil committed: nil ballot: 0 log: v log) }) }.
step := core dispatch: (PBAcceptorDecided step: (core accept: (PBAppendFailed reason: 'disk') in: v now: 0)) in: s now: 0.
c that: 'a failed rejoin restarts on a new log; an adoption refused by a failed tier fails with the reason'
  is: { phaseOf value: out first.
    phaseOf value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: (rejoining value: 'n0') now: 0)) in: out first now: 0) state.
    phaseOf value: step state. (blockedOf value: step state) includesSubstring: 'writing its acceptor log failed'.
    core rejoinBlockedIn: step state.
    phaseOf value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: (rejoining value: 'n0') now: 0)) in: step state now: 0) state }
  equals: { #failed. #gather. #failed. true. 'writing its acceptor log failed; close and reopen the space on a healthy disk'. #gather }.

"(21) A forceRejoin during the ballot round (proto_db reads the flag live): the round decides
 'forced', is blocked and retried, never completed on its witnesses."
v := rejoining value: 'n0'.
s := (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) with: { #acceptorView -> v.
  #rejoin -> (PBRejoin idle with: { #phase -> #gather. #ballot -> 20481. #attempt -> 1. #rid -> 7. #targets -> #('n1' 'n2').
    #forced -> true. #log -> v log }) }.
#('n1' 'n2') do: [:from |
  s := (core dispatch: (PBReceived message: (PBClusterMessage type: 'answer' from: from fields: {
    'rid' -> 7. 'inc' -> 5. 'root' -> (PBClusterMessage rootValue: r1). 'committed' -> nil. 'certain' -> true.
    'promised' -> 20481. 'state' -> 'ok'. 'ballot' -> 20481 })) in: s now: 1000) state].
c that: 'a forceRejoin during the ballot round blocks it (forced is not witnesses), then retries'
  is: { phaseOf value: s. (blockedOf value: s) includesSubstring: 'too few members confirmed' }
  equals: { #retry. true }.

"(22) An adoption in flight across a detach and a re-attach writes nothing to the new log
 (proto_db _complete_rejoin's 'self._tier is not tier'); a late report of the detached log
 starts no rejoin; a forceRejoin while detached is for the next log only."
v := rejoining value: 'n0'.
s := (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v now: 0)) in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 0) state.
s := (core dispatch: PBRejoinWanted new in: s now: 0) state.
s := (core dispatch: PBLogDetached new in: s now: 0) state.
v2 := rejoining value: 'n0'.
out := { [:st | { st appends. st state isRejoined. st state == v2 }]
    value: (core accept: (PBRejoinLearnt learnt: 4096 seen: 0 accepted: r1 committed: nil ballot: 0 log: v log) in: v2 now: 1000).
  [:st | { phaseOf value: st state. st effects size }]
    value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v now: 0)) in: s now: 0).
  [:st | { phaseOf value: st. forcedOf value: st. st rejoin notNil and: [st rejoin log == v2 log] }]
    value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v2 now: 0)) in: s now: 0) state.
  [:st | { st effects size. [:st2 | { phaseOf value: st2. forcedOf value: st2. st2 rejoin notNil and: [st2 rejoin log == v2 log] }]
      value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v2 now: 0)) in: st state now: 0) state }]
    value: (core dispatch: PBRejoinWanted new in: s now: 0) }.
c that: 'an adoption for the detached log changes nothing on the new log; a late old-log report starts nothing; forced while detached carries to the next log'
  is: out
  equals: { { #(). false. true }. { #detached. 0 }. { #gather. false. true }. { 0. { #gather. true. true } } }.

"(23) A forceRejoin binds the rejoin to the log reported then: on a tier-failed view (no rejoin
 runs), a later report over another log leaves the new rejoin unforced."
v := (core accept: (PBAppendFailed reason: 'disk') in: (rejoining value: 'n0') now: 0) state.
s := (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: v now: 0)) in: (PBNodeState config: (cfg value: 'n0' value: three) inc: 5) now: 0) state.
s := (core dispatch: PBRejoinWanted new in: s now: 0) state.
c that: 'forceRejoin on a tier-failed view is bound to that log: a report over another log starts an unforced rejoin'
  is: { s rejoin isForced. s rejoin log == v log.
    [:st | { phaseOf value: st. forcedOf value: st }]
      value: (core dispatch: (PBAcceptorDecided step: (core accept: PBStartNode new in: (rejoining value: 'n0') now: 0)) in: s now: 0) state }
  equals: { true. true. { #gather. false } }.

c report displayNl.
