"EXPECT: ok 32"
"The base choice (cluster/holder.st, CP 1.6) called directly, one guard per check (proto_db
 transactions.py _lease_base, _phase_1_floor, _base_needs_commit, _commit_base, refound,
 _guard_error; coordinator.py recover_root, _on_answer, replicate's pred). drive runs one
 PBBaseWanted through its effects: every query is answered as the check says (or not), a
 PBReadPersisted with the persisted root (or a failure), a PBProbeRoot with readable or not,
 and, when nothing else is due, the recovery timer fires. Three voters n0..n2, n0 deciding,
 startup grace 0, term T = 3 * 4096. (1) A certain permit: its root, no query. (2) An #ok base
 is bound: the next choice under that permission sends no query, and it is the pred. (3) A
 recovery ends at a majority of witnesses, this node counted, before its timer. (4) Answers of
 non-witnesses never count: the timer ends the round with a PBConflictError. (5) This node is
 counted only as a witness. (6) every waits for every other voter (the timer), and ends at once
 when all answered. (7) A sender's second answer replaces its first. (8) An answer of another
 incarnation is dropped (stale_replies). (9) A non-witness's accepted root is never the result.
 (10) Answers' committed roots are learnt (accept false) and count as committed knowledge. (11)
 The hint rises to every answer's accepted label; a result above the floor root wins. (12) The suspicion held at the send is cleared
 (both halves); a higher one raised meanwhile is kept, on both sides. (13) The phase-1 floor
 (R127) raises the base above the recovery result; PlantC1NoFloor does not. (14) phase1Floor:
 true for a known root, false for none and the empty space labelled 0. (15) Nothing known
 anywhere: refound from the persisted root (none: the empty space), #stale, hint raised by
 refoundStep, storage_root_reads, the persisted root learnt committed. (16) A term far enough
 above the persisted root builds on it. (17) A failed read ends the choice with its failure.
 (18-19) A committed root of a later term, or of this term above the base, supersedes it
 (#stale); of this term and equal, not. (20-22) The hard guard: a base below the committed root
 reads the persisted root; none, one below or a failed read: PBCorruptionError naming
 forceRejoin; one at or above: refound from it. (23) A base labelled above the term is #stale.
 (24) needsCommit (R50): not for the committed root, yes otherwise; the empty space is never
 re-committed (proto_db: 'current is not None') nor probed. (25) An unreadable base is #unreachable and is not bound. (26) The pred obligation: a
 PBReplicateWanted not built on the base, else on the root last sent, is refused
 (PBValidationError); the record is forgotten when the permission ends. (27) PBRecoverWanted
 settles { known. root }. (28) A root committed under a permission is bound (proto_db bind_root):
 a second round under it builds on that root, no commit needed, not #stale, whether or not the
 acceptor reported the commit, and the pred is that root. (29) A round that sent nothing
 (#none, under sendReserve) does not move the pred. (30) This node's own accepted root is in the
 recovery result. (31) An answer to another recovery round (its rid) is ignored. (32) L14 at the
 send: a term below the acceptor's rejoin ballot sends nothing."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_base'.

| c core peers cfg three marker logged viewOf stateOf rec r1 rp rq rT T perm answer drive out decision sends
  learnt s st choice p empty tr err count acc k av |
c := Check new.
core := BaseRules new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
three := #('n0' 'n1' 'n2').
cfg := PBClusterConfig nodeId: 'n0' peers: (peers value: three) options: (Dictionary new at: #startupGrace put: 0; yourself).
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
viewOf := [:appends | PBAcceptorState config: cfg logged: (logged value: appends) now: 0].
stateOf := [:appends | (PBNodeState config: cfg inc: 5) with: { #acceptorView -> (viewOf value: appends) }].
rec := [:aLabel :e | PBLabeledRoot label: aLabel record: (PBRootRecord segment: (ByteArray new: 16) offset: 64 + e epoch: e)].
T := 3 * 4096.
r1 := rec value: 4096 value: 1.
rp := rec value: 8192 value: 2.
rq := rec value: 8192 value: 3.
rT := rec value: T value: 5.
empty := PBLabeledRoot label: 0 record: nil.
"Logs: k knows r1 accepted and committed; a only accepted."
acc := [:r | PBLogAppend kind: #accepted label: r label root: r record sync: true].
count := [:r | PBLogAppend kind: #committed label: r label root: r record sync: true].
perm := [:root :certain | PBPermission term: T seq: 1 rid: 9 owner: 'n1' root: root certain: certain sentAt: 0 valid: 100000000].
"An answer from aSender to query aRid: anArray { accepted. committed. state } (the incarnation 5 unless a 4th)."
answer := [:aSender :aRid :anArray | PBReceived message: (PBClusterMessage type: 'answer' from: aSender fields: {
  'rid' -> aRid. 'inc' -> (anArray size > 3 ifTrue: [anArray at: 4] ifFalse: [5]).
  'root' -> (PBClusterMessage rootValue: (anArray at: 1)). 'committed' -> (PBClusterMessage rootValue: (anArray at: 2)).
  'certain' -> false. 'promised' -> 0. 'state' -> (anArray at: 3). 'ballot' -> 0 })].
"{ outcome or nil. effects. state. timer fired }: aRules decide the base of aPermission (or run anEvent) in aState."
drive := [:aRules :aState :anEvent :answers :persisted :readable | | queue state all outcome fired |
  queue := OrderedCollection with: anEvent.
  state := aState. all := OrderedCollection new. outcome := nil. fired := false.
  [outcome isNil and: [queue notEmpty or: [fired not and: [(all anySatisfy: [:e | (e isKindOf: PBTimer) and: [e event = #recovery]])]]]] whileTrue: [
    | ev step |
    queue isEmpty
      ifTrue: [
        fired := true.
        ev := PBTimerFired token: (all detect: [:e | (e isKindOf: PBTimer) and: [e event = #recovery]]) token event: #recovery]
      ifFalse: [ev := queue removeFirst].
    step := aRules dispatch: ev in: state now: 1000.
    state := step state.
    all addAll: step effects.
    step effects do: [:e |
      (e isKindOf: PBSettle) ifTrue: [outcome := e outcome].
      ((e isKindOf: PBSend) and: [e message type = 'query']) ifTrue: [
        (answers detect: [:a | a first = e to] ifNone: [nil]) ifNotNil: [:a |
          queue add: (answer value: e to value: (e message at: 'rid') value: a last)]].
      (e isKindOf: PBReadPersisted) ifTrue: [
        queue add: ((persisted isKindOf: Exception)
          ifTrue: [PBStorageRead token: e token root: nil failure: persisted]
          ifFalse: [
            persisted isArray
              ifTrue: [PBStorageRead token: e token root: persisted first failure: persisted last]
              ifFalse: [PBStorageRead token: e token root: persisted failure: nil]])].
      (e isKindOf: PBProbeRoot) ifTrue: [queue add: (PBRootProbed token: e token readable: readable)]]].
  { outcome. all. state. fired }].
decision := [:aRules :aState :aPermission :answers :persisted :readable |
  drive value: aRules value: aState value: (PBBaseWanted permission: aPermission waiter: #w) value: answers value: persisted value: readable].
"{ outcome. needsCommit. base label. base epoch } of a decision, the error class otherwise."
out := [:result | | o |
  o := result first.
  (o isKindOf: PBBaseDecision)
    ifTrue: [{ o outcome. o needsCommit. o base isNil ifTrue: [nil] ifFalse: [o base label]. o base isNil ifTrue: [nil] ifFalse: [o base epoch] }]
    ifFalse: [o class name]].
sends := [:result | ((result at: 2) select: [:e | (e isKindOf: PBSend) and: [e message type = 'query']]) size].
learnt := [:result | (((result at: 2) select: [:e | (e isKindOf: PBToAcceptor) and: [e event isKindOf: PBLearnCommitted]])
  collect: [:e | { e event root label. e event isAccepted }]) asArray].
k := { marker. acc value: r1. count value: r1 }.

"(1)"
s := decision value: core value: (stateOf value: k) value: (perm value: r1 value: true) value: #() value: nil value: true.
c that: 'a certain permit: its root, no query' is: { out value: s. sends value: s } equals: { #(#ok false 4096 1). 0 }.

"(2)"
p := perm value: r1 value: false.
s := decision value: core value: (stateOf value: k) value: p value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true.
st := decision value: core value: (s at: 3) value: p value: #() value: nil value: true.
c that: 'an #ok base is bound: the next choice sends no query; it is the pred'
  is: { out value: s. sends value: s. out value: st. sends value: st. (core predFor: p in: (s at: 3)) key = r1 key }
  equals: { #(#ok false 4096 1). 2. #(#ok false 4096 1). 0. true }.

"(3)"
s := decision value: core value: (stateOf value: k) value: p value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true.
c that: 'a recovery ends at a majority of witnesses, this node counted, before its timer'
  is: { out value: s. s at: 4 } equals: { #(#ok false 4096 1). false }.

"(4)"
s := decision value: core value: (stateOf value: k) value: p
  value: { { 'n1'. { r1. r1. 'learner' } } } value: nil value: true.
st := decision value: core value: (stateOf value: k) value: p
  value: { { 'n1'. { r1. r1. 'learner' } }. { 'n2'. { r1. r1. 'empty' } } } value: nil value: true.
c that: 'non-witnesses never count: the timer ends the round, PBConflictError naming the witnesses (all answered: at once)'
  is: { out value: s. s at: 4. (s first isKindOf: Exception) and: [(s first messageText ifNil: ['']) includesSubstring: 'witnesses needed answered the recovery query'].
    out value: st. st at: 4 }
  equals: { #PBConflictError. true. true. #PBConflictError. false }.

"(5)"
s := decision value: core value: (stateOf value: { acc value: r1. count value: r1 }) value: p value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true.
c that: 'this node is counted only as a witness (no rejoined marker: one answer is not a majority)'
  is: { out value: s. s at: 4 } equals: { #PBConflictError. true }.

"(6)"
s := drive value: core value: (stateOf value: k) value: (PBRecoverWanted every: true waiter: #r)
  value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true.
st := drive value: core value: (stateOf value: k) value: (PBRecoverWanted every: true waiter: #r)
  value: { { 'n1'. { r1. r1. 'ok' } }. { 'n2'. { r1. r1. 'ok' } } } value: nil value: true.
c that: 'every waits for every other voter, and ends at once when all answered ({ timer fired }, { timer fired })'
  is: { s at: 4. st at: 4 } equals: { true. false }.

"(7)"
choice := (PBBaseChoice waiter: #w permission: nil every: false)
  answered: 'n1' accepted: r1 committed: nil state: 'ok'.
choice := choice answered: 'n1' accepted: rp committed: nil state: 'ok'.
c that: 'a sender''s second answer replaces its first' is: { choice answers size. (choice answers first at: 2) key = rp key } equals: { 1. true }.

"(8)"
st := core dispatch: (PBBaseWanted permission: p waiter: #w) in: (stateOf value: { acc value: r1. count value: r1 }) now: 1000.
tr := (st effects detect: [:e | (e isKindOf: PBSend) and: [e message type = 'query']]) message at: 'rid'.
s := core dispatch: (answer value: 'n1' value: tr value: { r1. r1. 'ok'. 99 }) in: st state now: 1000.
c that: 'an answer of another incarnation is dropped, counted stale_replies'
  is: { (s effects collect: [:e | (e isKindOf: PBCount) ifTrue: [e stat] ifFalse: [e class name]]) asArray.
    (core _choicesIn: s state) first answers size }
  equals: { #('stale_replies'). 0 }.

"(9)"
s := decision value: core value: (stateOf value: k) value: (perm value: nil value: false)
  value: { { 'n1'. { rp. nil. 'learner' } }. { 'n2'. { r1. r1. 'ok' } } } value: nil value: true.
c that: 'a non-witness''s accepted root is never the result' is: (out value: s) equals: #(#ok false 4096 1).

"(10)"
s := decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false)
  value: { { 'n1'. { rp. rp. 'ok' } } } value: nil value: true.
c that: 'answers'' committed roots are learnt (accept false) and are committed knowledge (no commit first)'
  is: { learnt value: s. out value: s } equals: { { { 8192. false } }. #(#ok false 8192 2) }.

"(11)"
s := decision value: core value: (stateOf value: k) value: p value: { { 'n1'. { rp. r1. 'ok' } } } value: nil value: true.
c that: 'the hint rises to an answer''s accepted label; a recovery result above the floor root is the base'
  is: { (core _hintsIn: (s at: 3)) hint >= 8192. out value: s } equals: { true. #(#ok true 8192 2) }.

"(12)"
st := core dispatch: (PBBaseWanted permission: p waiter: #w) in: ((stateOf value: k) with: { #suspectTerm -> T }) now: 1000.
tr := (st effects detect: [:e | (e isKindOf: PBSend) and: [e message type = 'query']]) message at: 'rid'.
s := core dispatch: (answer value: 'n1' value: tr value: { r1. r1. 'ok' }) in: st state now: 1000.
err := core dispatch: (answer value: 'n1' value: tr value: { r1. r1. 'ok' }) in: (st state with: { #suspectTerm -> (2 * T) }) now: 1000.
av := viewOf value: k.
c that: 'the suspicion held at the send is cleared on both sides; a higher one is kept'
  is: { s state suspectTerm. ((s effects select: [:e | (e isKindOf: PBToAcceptor) and: [e event isKindOf: PBRecovered]]) collect: [:e | e event suspected]) asArray.
    err state suspectTerm.
    (core accept: (PBRecovered suspected: T) in: (av withGrants: av grants suspectTerm: T rejoined: true tierFailed: nil loggedPromise: av loggedPromise) now: 1000) state suspectTerm.
    (core accept: (PBRecovered suspected: T) in: (av withGrants: av grants suspectTerm: 2 * T rejoined: true tierFailed: nil loggedPromise: av loggedPromise) now: 1000) state suspectTerm }
  equals: { 0. { T }. 2 * T. 0. 2 * T }.

"(13)"
p := perm value: rp value: false.
c that: 'the phase-1 floor raises the base above the recovery result ({ product }, { PlantC1NoFloor })'
  is: { out value: (decision value: core value: (stateOf value: k) value: p value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true).
    out value: (decision value: PlantC1NoFloor new value: (stateOf value: k) value: p value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true) }
  equals: { #(#ok true 8192 2). #(#ok false 4096 1) }.

"(14)"
c that: 'phase1Floor: a known root, not none nor the empty space labelled 0'
  is: { core phase1Floor: r1. core phase1Floor: nil. core phase1Floor: empty. core phase1Floor: (PBLabeledRoot label: 4096 record: nil) }
  equals: #(true false false true).

"(15)"
s := decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false)
  value: { { 'n1'. { nil. nil. 'ok' } } } value: nil value: true.
c that: 'nothing known: refound from the persisted root (none), #stale, the hint raised by refoundStep, counted, learnt'
  is: { out value: s. (core _hintsIn: (s at: 3)) hint >= PBMembership refoundStep.
    ((s at: 2) select: [:e | (e isKindOf: PBCount) and: [e stat = 'storage_root_reads']]) size. learnt value: s }
  equals: { #(#stale false 0 0). true. 1. { { 0. false } } }.

"(16)"
p := PBPermission term: PBMembership refoundStep + 4096 seq: 1 rid: 9 owner: 'n1' root: nil certain: false sentAt: 0 valid: 100000000.
c that: 'a term far enough above the persisted root builds on it ({ term too low }, { far enough })'
  is: { out value: (decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false) value: { { 'n1'. { nil. nil. 'ok' } } } value: r1 value: true).
    out value: (decision value: core value: (stateOf value: { marker }) value: p value: { { 'n1'. { nil. nil. 'ok' } } } value: r1 value: true) }
  equals: { #(#stale false 4096 1). #(#ok false 4096 1) }.

"(17)"
c that: 'a failed read ends the choice with its failure (whatever root came with it)'
  is: { out value: (decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false)
    value: { { 'n1'. { nil. nil. 'ok' } } } value: (PBUnexpectedError new messageText: 'no read'; yourself) value: true).
    out value: (decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false)
    value: { { 'n1'. { nil. nil. 'ok' } } } value: { r1. PBUnexpectedError new messageText: 'no read'; yourself } value: true) }
  equals: #(#PBUnexpectedError #PBUnexpectedError).

"(18-19)"
c that: 'a committed root of a later term supersedes the base'
  is: (out value: (decision value: core value: (stateOf value: { marker. count value: (rec value: 4 * T value: 7) })
    value: (perm value: r1 value: true) value: #() value: nil value: true)) first
  equals: #stale.
c that: 'a committed root of this term above the base supersedes it; one equal to it does not'
  is: { (out value: (decision value: core value: (stateOf value: { marker. count value: (rec value: T value: 7) })
      value: (perm value: (rec value: T value: 6) value: true) value: #() value: nil value: true)) first.
    (out value: (decision value: core value: (stateOf value: { marker. count value: rT })
      value: (perm value: rT value: true) value: #() value: nil value: true)) first }
  equals: #(#stale #ok).

"(20-22) The hard guard: a certain base r1 below the committed rq."
st := stateOf value: { marker. count value: rq }.
c that: 'the hard guard: no persisted root, or one below the committed root: PBCorruptionError naming forceRejoin'
  is: { (decision value: core value: st value: (perm value: r1 value: true) value: #() value: nil value: true) first class name.
    [:o | (o isKindOf: Exception) and: [(o messageText ifNil: ['']) includesSubstring: 'call forceRejoin on this node']]
      value: (decision value: core value: st value: (perm value: r1 value: true) value: #() value: r1 value: true) first }
  equals: { #PBCorruptionError. true }.
p := PBPermission term: PBMembership refoundStep + 8192 seq: 1 rid: 9 owner: 'n1' root: r1 certain: true sentAt: 0 valid: 100000000.
c that: 'the hard guard: a failed read is the guard''s error (whatever root came with it)'
  is: { (decision value: core value: st value: (perm value: r1 value: true) value: #() value: (PBUnexpectedError new messageText: 'no read'; yourself) value: true) first class name.
    (decision value: core value: st value: p value: #() value: { rq. PBUnexpectedError new messageText: 'no read'; yourself } value: true) first class name }
  equals: #(#PBCorruptionError #PBCorruptionError).
p := PBPermission term: PBMembership refoundStep + 8192 seq: 1 rid: 9 owner: 'n1' root: r1 certain: true sentAt: 0 valid: 100000000.
c that: 'the hard guard: a persisted root at or above the committed one is a refound from it ({ term too low }, { far enough })'
  is: { out value: (decision value: core value: st value: (perm value: r1 value: true) value: #() value: rq value: true).
    out value: (decision value: core value: st value: p value: #() value: rq value: true) }
  equals: { #(#stale false 8192 3). #(#ok false 8192 3) }.

"(23)"
c that: 'a base labelled above the term is #stale'
  is: (out value: (decision value: core value: (stateOf value: { marker }) value: (perm value: nil value: false)
    value: { { 'n1'. { rec value: 4 * T value: 8. nil. 'ok' } } } value: nil value: true)) first
  equals: #stale.

"(24)"
c that: 'needsCommit: not for the committed root; a base only accepted is probed and committed first; the empty space never re-committed nor probed'
  is: { out value: (decision value: core value: (stateOf value: k) value: (perm value: r1 value: true) value: #() value: nil value: false).
    out value: (decision value: core value: (stateOf value: { marker. acc value: r1 }) value: (perm value: r1 value: true) value: #() value: nil value: true).
    [out value: (decision value: core value: (stateOf value: { marker }) value: (perm value: empty value: true) value: #() value: nil value: false)]
      on: Error do: [:e | e class name] }
  equals: { #(#ok false 4096 1). #(#ok true 4096 1). #(#ok false 0 0) }.

"(25)"
p := perm value: r1 value: true.
s := decision value: core value: (stateOf value: { marker. acc value: r1 }) value: p value: #() value: nil value: false.
c that: 'an unreadable base that needs a commit is #unreachable and is not bound'
  is: { out value: s. core _permitRecord: p in: (s at: 3) } equals: { #(#unreachable true 4096 1). nil }.

"(26) The pred obligation, under a permission whose base is r1."
p := perm value: r1 value: true.
s := (decision value: core value: (stateOf value: k) value: p value: #() value: nil value: true) at: 3.
st := core dispatch: (PBReplicateWanted permission: p root: rT pred: r1 waiter: #x) in: s now: 1000.
c that: 'the pred obligation: built on the base, then on the root last sent; forgotten at the permission''s end'
  is: { [core dispatch: (PBReplicateWanted permission: p root: rT pred: rp waiter: #x) in: s now: 1000. nil]
      on: PBValidationError do: [:e | #refused].
    (st effects select: [:e | (e isKindOf: PBSend) and: [e message type = 'replicate']]) size.
    [core dispatch: (PBReplicateWanted permission: p root: (rec value: T value: 6) pred: r1 waiter: #y) in: st state now: 1000. nil]
      on: PBValidationError do: [:e | #refused].
    [(core dispatch: (PBReplicateWanted permission: p root: (rec value: T value: 6) pred: rT waiter: #y) in: st state now: 1000) state notNil]
      on: PBValidationError do: [:e | #refused].
    core _permitRecord: p in: (core dispatch: (PBDoneReport permission: p outcome: 'unknown') in: st state now: 1000) state }
  equals: { #refused. 2. #refused. true. nil }.

"(27)"
s := drive value: core value: (stateOf value: k) value: (PBRecoverWanted every: false waiter: #r)
  value: { { 'n1'. { rp. r1. 'ok' } } } value: nil value: true.
c that: 'PBRecoverWanted settles { known. root }' is: { s first first. s first last key = rp key } equals: #(true true).

"(28)"
p := perm value: r1 value: true.
s := (decision value: core value: (stateOf value: k) value: p value: #() value: nil value: true) at: 3.
st := core dispatch: (PBReplicateWanted permission: p root: rT pred: r1 waiter: #x) in: s now: 1000.
st := core _step: [:fx | core _endReplication: (core _replicationsIn: st state) first committed: true in: st state effects: fx].
c that: 'a root committed under a permission is the next round''s base ({ acceptor lagging }, { acceptor reports it }, pred)'
  is: { out value: (decision value: core value: st state value: p value: #() value: nil value: true).
    out value: (decision value: core value: (st state with: { #acceptorView -> (viewOf value: { marker. acc value: r1. count value: r1. acc value: rT. count value: rT }) })
      value: p value: #() value: nil value: true).
    (core predFor: p in: ((decision value: core value: st state value: p value: #() value: nil value: true) at: 3)) key = rT key }
  equals: { #(#ok false 12288 5). #(#ok false 12288 5). true }.

"(29)"
p := perm value: r1 value: true.
s := (decision value: core value: (stateOf value: k) value: p value: #() value: nil value: true) at: 3.
st := core dispatch: (PBReplicateWanted permission: p root: rT pred: r1 waiter: #x) in: s now: p validUntil - 1.
c that: 'a round that sent nothing (#none) does not move the pred ({ outcome }, { the refused root as pred }, { the base as pred })'
  is: { ((st effects select: [:e | e isKindOf: PBSettle]) collect: [:e | e outcome]) asArray.
    [core dispatch: (PBReplicateWanted permission: p root: (rec value: T value: 6) pred: rT waiter: #y) in: st state now: 1000. #sent]
      on: PBValidationError do: [:e | #refused].
    [((core dispatch: (PBReplicateWanted permission: p root: (rec value: T value: 6) pred: r1 waiter: #y) in: st state now: 1000) effects
      select: [:e | (e isKindOf: PBSend) and: [e message type = 'replicate']]) size]
      on: PBValidationError do: [:e | #refused] }
  equals: { #(#none). #refused. 2 }.

"(30)"
s := decision value: core value: (stateOf value: { marker. acc value: r1. count value: r1. acc value: rp }) value: (perm value: nil value: false)
  value: { { 'n1'. { r1. r1. 'ok' } } } value: nil value: true.
c that: 'this node''s own accepted root is in the recovery result' is: (out value: s) equals: #(#ok true 8192 2).

"(31)"
st := core dispatch: (PBBaseWanted permission: (perm value: r1 value: false) waiter: #w) in: (stateOf value: k) now: 1000.
tr := (st effects detect: [:e | (e isKindOf: PBSend) and: [e message type = 'query']]) message at: 'rid'.
s := core dispatch: (answer value: 'n1' value: tr + 100 value: { r1. r1. 'ok' }) in: st state now: 1000.
c that: 'an answer to another recovery round is ignored ({ settled }, answers recorded)'
  is: { (s effects select: [:e | e isKindOf: PBSettle]) size. ((core _choicesIn: s state) collect: [:x | x answers size]) asArray }
  equals: { 0. #(0) }.

"(32) L14 at the send"
p := perm value: r1 value: true.
s := (decision value: core value: (stateOf value: k) value: p value: #() value: nil value: true) at: 3.
"s with its acceptor's rejoin ballot set to n (set by rejoining, Task 16: written here directly)."
st := [:n | | v | v := s acceptorView with: #(). v instVarNamed: 'rejoinBallot' put: n. s with: { #acceptorView -> v }].
c that: 'L14 at the send: a term below the acceptor''s rejoin ballot sends nothing (#none); equal to it, sent'
  is: { (core dispatch: (PBReplicateWanted permission: p root: rT pred: r1 waiter: #x) in: (st value: T + 1) now: 1000) effects
      collect: [:f | f class name].
    ((core dispatch: (PBReplicateWanted permission: p root: rT pred: r1 waiter: #x) in: (st value: T) now: 1000) effects
      select: [:f | (f isKindOf: PBSend) and: [f message type = 'replicate']]) size }
  equals: { #(#PBSettle). 2 }.

c report.
