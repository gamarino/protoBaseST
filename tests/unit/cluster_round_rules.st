"EXPECT: ok 39"
"The commit round (cluster/holder.st, PBCoordinatorCore round:in:now:) called directly, one guard
 per check (proto_db transactions.py _run_round, _permit_round, _keep, _take_kept,
 _await_retries, _drop_kept; coordinator.py replicate's _check_reserve and rejoin-ballot
 refusal). go folds events into a PBRoundState of n0 and collects the effects. The permission:
 term T = 3 * 4096, sent at 0, valid 600 ms; sendReserve 166.666 ms. (1) One round at a time:
 the queue asks for one permission; a commit enqueued meanwhile waits and joins the round. (2)
 The stamp of a build is { term. base epoch + 1 }; each entry builds on the previous root. (3) A
 built root without that stamp is PBValidationError. (4) An event out of its phase is
 PBValidationError. (5) A build answer for another entry than the one building is
 PBValidationError. (6) CC11: the first entry is always built; a later one only while
 sendReserve + the longest build is left; the rest go back to the head of the queue; an entry
 with nothing to publish settles false. (7) R121:
 less than sendReserve left refuses the send (nothing replicated, sends_refused_reserve, the CC18
 text, a retryable conflict, the permission ends #none). (8) L14: a term below the rejoin ballot
 is refused (nothing replicated, its text); a term equal to it is not. (9) withRejoinBallot:
 never goes down. (10) #committed settles the built entries true. (11) A conflicted entry that
 will retry gets permitHeld; the permission is kept min(retryHold, left) and its retry runs the
 next round under it. (12) An entry that will not retry is not held, and the permission ends
 (one waiting for retryWait otherwise). (13) After permitRetries rounds nothing is held and the
 permission ends. (14) An invalid permission holds nothing. (15) A hold timer of another token
 is ignored; its own ends the permission. (16) With two held retries the next round waits for
 both (or a PBDropKept). (17) Enqueued under a kept permission that is no longer valid: the
 permission ends, the queue asks again. (18) #stale requeues, nothing settled, the permission
 ends #unknown; after a committed round, #committed. (19) Removed: #unreachable is no longer
 a base decision (rc4 R233: a re-commit whose read fails is (21)). (20) needsCommit: the base is re-committed first (its replicate's pred the base),
 then the entries build on the re-commit. (21) A failed re-commit sent nothing (R233): #none for
 a conflict and for any other error. (22) #unknown: the replication's PBOutcomeUnknownError (its text
 proto_db's, an unknown outcome without it refused) for every built entry, a
 conflicted one its own conflict. (23) A permit error settles the batch. (24) PBReportDone
 carries a root exactly with #committed. (26) termRetries stale permissions in a row fail the
 queued commits with a conflict (proto_db _TERM_RETRIES); a fresh permission, or a permit
 error, resets the run.
 (27) A held retry is awaited by its caller, not by a count: another caller's commit does not
 take its round (reviewer probe P3). (28) Commits left queued by the group bound do not stand
 for the held retry. (29) #none: a retryable conflict, never held; the permission ends #none, or
 #committed after a committed round. (30) A build error of any class fails its commit alone and
 the round builds the next entry (indexed queries ruling IQ1: an extractor's exception fails only
 its commit; proto_db rc4 ends the round on an error that is not a ProtoDBError, a documented
 deviation). (31) With no held caller, a kept permission waits for as many
 commits as the round had conflicts. (32) The stale limit fails every queued commit, those
 queued after the round's too. (33) PBBuildFailed carries whether the tier failed, a Boolean
 (R231). (34) A build that failed with exactly PBUnexpectedError after the permission expired
 joins the round's conflicts (proto_db conflicted.append), not settled at once (R212). Also: an expired permission's refusal is not counted (7); a held
 hold is at least retryWait (11); rounds 2 to permitRetries hold, the next does not (13); a
 stale round's commits go back to the head of the queue (18); a PBDropKept of a caller not
 awaited changes nothing (12, 16)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_round'.

| hround stale staleRun held lastErr firstErr textOf c core cfg peers T rec r1 perm e go fresh ok settles reps reportOf builds st out rule err x conflict permitted |
c := Check new.
core := RoundRules new.
peers := (1 to: 3) asArray collect: [:i | PBPeer nodeId: (#('n0' 'n1' 'n2') at: i) host: '127.0.0.1' port: 7000 + i].
cfg := PBClusterConfig nodeId: 'n0' peers: peers options: (Dictionary new at: #startupGrace put: 0; yourself).
T := 3 * 4096.
rec := [:aLabel :ep | PBLabeledRoot label: aLabel record: (PBRootRecord segment: (ByteArray new: 16) offset: 64 + ep epoch: ep)].
r1 := rec value: 4096 value: 1.
perm := PBPermission term: T seq: 1 rid: 9 owner: 'n1' root: nil certain: false sentAt: 0 valid: 600000.
e := [:k :r | PBRoundEntry token: k caller: k willRetry: r deadline: nil].
fresh := PBRoundState config: cfg.
ok := PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: false outcome: #ok).
conflict := [:k :r | PBBuildConflict entry: (e value: k value: r) error: (PBConflictError new messageText: 'hot'; yourself)].
"{ state. effects }: someEvents ({ event. t }) folded into aState."
go := [:aRules :aState :someEvents | | s fx |
  s := aState. fx := OrderedCollection new.
  someEvents do: [:p | | step | step := aRules round: p first in: s now: p last. s := step state. fx addAll: step effects].
  { s. fx asArray }].
settles := [:fx | (fx select: [:f | f isKindOf: PBSettle]) collect: [:f | { f waiter. f outcome }]].
reps := [:fx | fx select: [:f | f isKindOf: PBReplicate]].
reportOf := [:fx | (fx select: [:f | f isKindOf: PBReportDone]) collect: [:f | f outcome]].
builds := [:fx | fx select: [:f | f isKindOf: PBBuild]].
"The outcome of the first PBSettle of fx, nil when none; the text of an error, '' for nil."
lastErr := [:fx | (settles value: fx) isEmpty ifTrue: [nil] ifFalse: [(settles value: fx) last last]].
held := [:fx | | er | er := lastErr value: fx. (er isKindOf: PBConflictError) and: [er permitHeld]].
firstErr := [:fx | (settles value: fx) isEmpty ifTrue: [nil] ifFalse: [(settles value: fx) first last]].
textOf := [:anError | (anError respondsTo: #messageText) ifTrue: [anError messageText ifNil: ['']] ifFalse: ['']].
err := [:aBlock | [aBlock value. nil] on: Error do: [:ex | ex class]].
permitted := { PBRoundEnqueued entry: (e value: 'a' value: false). 0 }.
"Up to the first PBBuild of 'a' (and 'b' when withB) at t = 1000."
rule := [:aRules :withB | go value: aRules value: fresh value: ({ permitted } ,
  (withB ifTrue: [{ { PBRoundEnqueued entry: (e value: 'b' value: false). 0 } }] ifFalse: [#()]) ,
  { { PBPermitted permission: perm. 0 }. { ok. 1000 } })].

"(1)"
out := rule value: core value: true.
c that: 'one round at a time: one PBAskPermit, the later commit joins the round'
  is: { (go value: core value: fresh value: { permitted. { PBRoundEnqueued entry: (e value: 'b' value: false). 0 } }) last
      select: [:f | f isKindOf: PBAskPermit]. out first live collect: [:x1 | x1 token]. out first phase }
  printString equals: { { PBAskPermit new }. #('b'). #build } printString.

"(2)"
x := go value: core value: out first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 } }.
c that: 'stamps: { term. base epoch + 1 }, each on the previous root'
  is: { (builds value: out last) first stamp. (builds value: x last) first stamp. (builds value: x last) first base epoch }
  equals: { { T. 2 }. { T. 3 }. 2 }.

"(3)"
c that: 'a root without the stamp is refused'
  is: { err value: [go value: core value: out first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T - 1 value: 2) micros: 1. 2000 } }].
    err value: [go value: core value: out first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 5) micros: 1. 2000 } }] }
  equals: { PBValidationError. PBValidationError }.

"(4)"
c that: 'an event out of its phase is refused'
  is: { err value: [go value: core value: fresh value: { { ok. 0 } }]. err value: [go value: core value: fresh value: { { PBReplicated outcome: #committed. 0 } }] }
  equals: { PBValidationError. PBValidationError }.

"(5)"
c that: 'a build answer for another entry is refused'
  is: (err value: [go value: core value: out first value: { { PBBuilt entry: (e value: 'b' value: false) root: (rec value: T value: 2) micros: 1. 2000 } }])
  equals: PBValidationError.

"(6)"
x := go value: core value: out first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 300000. 301000 } }.
st := go value: core value: out first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 100000. 101000 } }.
c that: 'CC11: b waits when sendReserve + the longest build is not left (299 < 467 ms), is built when it is (499 >= 267); the first is built even under sendReserve left'
  is: { x first queue collect: [:q | q token]. (reps value: x last) size. (builds value: st last) size. st first phase.
    (builds value: (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 }. { ok. 500000 } }) last) size }
  equals: { #('b'). 1. 1. #build. 1 }.

c that: 'an entry with nothing to publish settles false and is not sent'
  is: (go value: core value: st first value: { { PBBuilt entry: (e value: 'b' value: false) root: nil micros: 1. 102000 } }) last first printString
  equals: (PBSettle waiter: 'b' outcome: false) printString.

"(7)"
x := go value: core value: (rule value: core value: false) first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 450000. 451000 } }.
c that: 'R121: under sendReserve left, nothing replicated, counted, CC18 text, retryable, #none'
  is: { (reps value: x last) size. (x last select: [:f | f isKindOf: PBCount]) collect: [:f | f stat].
    ((firstErr value: x last) isKindOf: PBConflictError).
    (#('149 ms left' 'sendReserve' '450 ms' 'leaseDuration') allSatisfy: [:w | (textOf value: (firstErr value: x last)) includesSubstring: w]).
    reportOf value: x last }
  equals: { 0. #('sends_refused_reserve'). true. true. #(#none) }.
st := go value: core value: (rule value: core value: false) first value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 650000 } }.
c that: 'an expired permission refuses the send without counting sends_refused_reserve'
  is: { (reps value: st last) size. (st last select: [:f | f isKindOf: PBCount]) size. reportOf value: st last }
  equals: { 0. 0. #(#none) }.

"(8)"
x := go value: core value: ((rule value: core value: false) first withRejoinBallot: T + 1)
  value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 } }.
st := go value: core value: ((rule value: core value: false) first withRejoinBallot: T)
  value: { { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 } }.
c that: 'L14: below the rejoin ballot nothing is replicated; equal to it, sent'
  is: { (reps value: x last) size. (textOf value: (firstErr value: x last)) includesSubstring: 'rejoin ballot'.
    (x last select: [:f | f isKindOf: PBCount]) size. (reps value: st last) size }
  equals: { 0. true. 0. 1 }.

"(9)"
c that: 'the rejoin ballot never goes down'
  is: ((fresh withRejoinBallot: 10) withRejoinBallot: 5) rejoinBallot
  equals: 10.

"(10)"
x := go value: core value: (rule value: core value: false) first value: {
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }. { PBReplicated outcome: #committed. 3000 } }.
c that: '#committed settles the built entries true, the permission ends #committed'
  is: { settles value: x last. reportOf value: x last }
  equals: { { { 'a'. true } }. #(#committed) }.

"A round of 'a' (committed) and 'h' (conflicting, willRetry aBool) up to its replication's answer at t."
hround := [:aRules :aBool :t | | s |
  s := go value: aRules value: fresh value: { permitted. { PBRoundEnqueued entry: (e value: 'h' value: aBool). 0 }. { PBPermitted permission: perm. 0 }. { ok. 1000 }.
    { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }. { conflict value: 'h' value: aBool. 3000 } }.
  go value: aRules value: s first value: { { PBReplicated outcome: #committed. t } }].
x := hround.

"(11)"
out := x value: core value: true value: 4000.
st := go value: core value: out first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 5000 } }.
c that: 'a held retry: permitHeld, kept min(retryHold, left), the retry runs under it'
  is: { (held value: out last). out first phase.
    ((out last select: [:f | f isKindOf: PBTimer]) collect: [:f | f after]). (st last first isKindOf: PBAskBase). st first rounds.
    ((x value: core value: true value: 550000) last select: [:f | f isKindOf: PBTimer]) collect: [:f | f after].
    ((x value: core value: true value: 598000) last select: [:f | f isKindOf: PBTimer]) collect: [:f | f after] }
  equals: { true. #held. { cfg retryHold }. true. 2. #(50000). { cfg retryWait } }.

"(12)"
st := x value: core value: false value: 4000.
c that: 'a retry not coming is not held: retryWait, then the permission ends'
  is: { (held value: st last). ((st last select: [:f | f isKindOf: PBTimer]) collect: [:f | f after]).
    reportOf value: (go value: core value: st first value: { { PBHoldExpired token: st first holdToken. 10000 } }) last.
    (go value: core value: st first value: { { PBDropKept caller: 'h'. 5000 } }) first phase }
  equals: { false. { cfg retryWait }. #(#committed). #held }.

"(13)"
st := out.
out := OrderedCollection new.
cfg permitRetries timesRepeat: [
  st := go value: core value: st first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 5000 }. { ok. 5000 }.
    { conflict value: 'h' value: true. 6000 } }.
  out add: (held value: st last)].
c that: 'rounds 2 to permitRetries still hold, round permitRetries + 1 does not and the permission ends'
  is: { out asArray. st first rounds. reportOf value: st last }
  equals: { ((2 to: cfg permitRetries + 1) collect: [:r | r <= cfg permitRetries]) asArray. 0. #(#committed) }.
out := x value: core value: true value: 4000.

"(14)"
st := x value: core value: true value: 600000.
c that: 'an invalid permission holds nothing'
  is: { (held value: st last). reportOf value: st last }
  equals: { false. #(#committed) }.

"(15)"
c that: 'a hold timer of another token is ignored, its own ends the permission'
  is: { (go value: core value: out first value: { { PBHoldExpired token: #(#hold 99). 9000 } }) last.
    reportOf value: (go value: core value: out first value: { { PBHoldExpired token: out first holdToken. 9000 } }) last }
  equals: { #(). #(#committed) }.

"(16)"
st := go value: core value: fresh value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 0 }. { PBRoundEnqueued entry: (e value: 'k' value: true). 0 }.
  { PBPermitted permission: perm. 0 }. { ok. 1000 }. { conflict value: 'h' value: true. 2000 }. { conflict value: 'k' value: true. 3000 } }.
x := go value: core value: st first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 4000 } }.
c that: 'two held retries: the next round waits for both, or for a PBDropKept'
  is: { st first awaiting. x first phase.
    (go value: core value: x first value: { { PBRoundEnqueued entry: (e value: 'k' value: true). 4000 } }) first phase.
    (go value: core value: x first value: { { PBDropKept caller: 'k'. 4000 } }) first phase.
    (go value: core value: x first value: { { PBDropKept caller: 'z'. 4000 } }) first phase }
  equals: { #('h' 'k'). #held. #base. #base. #held }.

"(17)"
st := go value: core value: out first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 700000 } }.
c that: 'enqueued under a kept permission no longer valid: it ends, the queue asks again'
  is: { reportOf value: st last. (st last last isKindOf: PBAskPermit). st first phase }
  equals: { #(#committed). true. #permit }.

"(18)"
st := go value: core value: (rule value: core value: false) first value: #().
x := go value: core value: (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 } }) first
  value: { { PBRoundEnqueued entry: (e value: 'z' value: false). 500 }.
    { PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: false outcome: #stale). 1000 } }.
st := go value: core value: out first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 5000 }.
  { PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: false outcome: #stale). 5000 } }.
c that: '#stale requeues at the head and ends #unknown; after a committed round, #committed'
  is: { settles value: x last. reportOf value: x last. x first phase. x first batch collect: [:q | q token]. reportOf value: st last }
  equals: { #(). #(#unknown). #permit. #('a' 'z'). #(#committed) }.

"(20)"
st := go value: core value: (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 } }) first
  value: { { PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: true outcome: #ok). 1000 } }.
c that: 'needsCommit: re-committed first (pred the base), then the entries build on it'
  is: (st first phase = #recommit
    ifTrue: [
      x := go value: core value: st first value: { { PBBuilt entry: nil root: (rec value: T value: 2) micros: 0. 1000 }. { PBReplicated outcome: #committed. 2000 } }.
      { (builds value: st last) first entry. (reps value: x last) first pred epoch. (builds value: x last) first entry token. (builds value: x last) first base epoch }]
    ifFalse: [{ st first phase }])
  equals: { nil. 1. 'a'. 2 }.

"(21)"
c that: 'a failed re-commit sent nothing: #none for a conflict and for any other error (R233)'
  is: { [reportOf value: (go value: core value: st first value: { { PBBuildFailed entry: nil error: (PBConflictError new messageText: 'c'; yourself) tierFailed: false. 1000 } }) last] on: Error do: [:ex | ex class].
    [reportOf value: (go value: core value: st first value: { { PBBuildFailed entry: nil error: (Error new messageText: 'io'; yourself) tierFailed: false. 1000 } }) last] on: Error do: [:ex | ex class] }
  equals: { #(#none). #(#none) }.

"(22)"
st := go value: core value: fresh value: { permitted. { PBRoundEnqueued entry: (e value: 'h' value: true). 0 }. { PBPermitted permission: perm. 0 }. { ok. 1000 }.
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }. { conflict value: 'h' value: true. 3000 }.
  { PBReplicated outcome: (PBOutcomeUnknownError new messageText: 'Node n0: only 1 of the 2 acknowledgements needed arrived '
    , 'before the lease ended; the root (epoch 2) may or may not take effect'; yourself). 4000 } }.
c that: '#unknown: PBOutcomeUnknownError for the built, the conflicted its own conflict, not held'
  is: { (settles value: st last) collect: [:p | { p first. p last class. (p last isKindOf: PBConflictError) and: [p last permitHeld] }].
    reportOf value: st last.
    ((settles value: st last) detect: [:p | p first = 'a']) last messageText.
    [PBReplicated outcome: #unknown. #accepted] on: PBValidationError do: [:ex | #refused] }
  equals: { { { 'h'. PBConflictError. false }. { 'a'. PBOutcomeUnknownError. false } }. #(#unknown).
    'Node n0: only 1 of the 2 acknowledgements needed arrived before the lease ended; the root (epoch 2) may or may not take effect'.
    #refused }.

"(23)"
st := go value: core value: fresh value: { permitted. { PBPermitted permission: (PBTimeoutError new messageText: 't'; yourself). 0 } }.
c that: 'a permit error settles the batch'
  is: { (settles value: st last) collect: [:p | { p first. p last class }]. st first phase }
  equals: { { { 'a'. PBTimeoutError } }. #idle }.

"(24)"
c that: 'PBReportDone: a root exactly with #committed'
  is: { err value: [PBReportDone permission: perm outcome: #committed root: nil]. err value: [PBReportDone permission: perm outcome: #none root: r1].
    err value: [PBReportDone permission: perm outcome: #committed root: r1] }
  equals: { PBValidationError. PBValidationError. nil }.

"(26) I1"
stale := PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: false outcome: #stale).
"{ state. effects } of n stale permissions in a row from aState (a permission asked)."
staleRun := [:aState :n | | acc |
  acc := { aState. #() }.
  1 to: n do: [:i | acc first phase = #permit ifTrue: [ | o |
    o := go value: core value: acc first value: { { PBPermitted permission: perm. i * 1000 }. { stale. i * 1000 + 1 } }.
    acc := { o first. acc last , o last }]].
  acc].
st := staleRun value: (go value: core value: fresh value: { permitted }) first value: core termRetries.
x := staleRun value: (go value: core value: fresh value: { permitted }) first value: core termRetries - 1.
x := go value: core value: x first value: { { PBPermitted permission: perm. 9000 }. { ok. 9001 }.
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1. 9002 }. { PBReplicated outcome: #committed. 9003 }.
  { PBRoundEnqueued entry: (e value: 'b' value: false). 9004 } }.
x := staleRun value: x first value: core termRetries - 1.
out := staleRun value: (go value: core value: fresh value: { permitted }) first value: core termRetries - 1.
out := go value: core value: out first value: { { PBPermitted permission: (PBTimeoutError new messageText: 't'; yourself). 9000 }.
  { PBRoundEnqueued entry: (e value: 'b' value: false). 9001 } }.
out := staleRun value: out first value: core termRetries - 1.
c that: 'termRetries stale permissions in a row fail the queue with a conflict; a fresh one resets the run'
  is: { (settles value: st last) collect: [:q | q first]. ((firstErr value: st last) isKindOf: PBConflictError).
    (textOf value: (firstErr value: st last)) includesSubstring: 'after 5 attempts'. (st last select: [:f | f isKindOf: PBAskPermit]) size.
    st first phase. (settles value: x last) collect: [:q | q first]. x first phase.
    (settles value: out last) collect: [:q | q first]. out first phase }
  equals: { #('a'). true. true. core termRetries - 1. #idle. #(). #permit. #(). #permit }.

"(27) I2: a held retry is awaited by caller (reviewer probe P3)"
st := go value: core value: fresh value: {
  permitted. { PBRoundEnqueued entry: (e value: 'h' value: true). 0 }. { PBPermitted permission: perm. 0 }. { ok. 1000 }.
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }.
  { conflict value: 'h' value: true. 3000 }. { PBRoundEnqueued entry: (e value: 'z' value: false). 3500 }.
  { PBReplicated outcome: #committed. 4000 } }.
x := go value: core value: st first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 4100 } }.
c that: 'a held retry gets its round although another caller''s commit is queued'
  is: { held value: st last. st first phase. st first awaiting. x first phase. x first live collect: [:q | q token] }
  equals: { true. #held. #('h'). #base. #('z' 'h') }.

"(28) I2: group-bound leftovers do not stand for a held retry"
st := go value: core value: fresh value: {
  { PBRoundEnqueued entry: (e value: 'h' value: true). 0 }. permitted. { PBRoundEnqueued entry: (e value: 'l' value: false). 0 }.
  { PBPermitted permission: perm. 0 }. { ok. 1000 }. { conflict value: 'h' value: true. 2000 }.
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 300000. 302000 }.
  { PBReplicated outcome: #committed. 303000 } }.
c that: 'a round that left commits queued by the group bound still waits for its held retry'
  is: { st first queue collect: [:q | q token]. st first phase. held value: st last.
    (go value: core value: st first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 303100 } }) first live
      collect: [:q | q token] }
  equals: { #('l'). #held. true. #('l' 'h') }.

"(29) I3: #none"
st := go value: core value: (rule value: core value: false) first value: {
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }. { PBReplicated outcome: #none. 3000 } }.
x := go value: core value: (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 } }) first value: {
  { PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: true outcome: #ok). 1000 }.
  { PBBuilt entry: nil root: (rec value: T value: 2) micros: 0. 1000 }. { PBReplicated outcome: #none. 2000 } }.
out := hround value: core value: true value: 4000.
out := go value: core value: out first value: { { PBRoundEnqueued entry: (e value: 'h' value: true). 5000 }. { PBBaseDecided decision:
  (PBBaseDecision base: (rec value: T value: 2) needsCommit: false outcome: #ok). 5000 }.
  { PBBuilt entry: (e value: 'h' value: true) root: (rec value: T value: 3) micros: 1000. 6000 }. { PBReplicated outcome: #none. 7000 } }.
c that: '#none: a retryable conflict, never held, reported #none; after a committed round, #committed'
  is: { ((firstErr value: st last) isKindOf: PBConflictError). held value: st last. reportOf value: st last.
    ((firstErr value: x last) isKindOf: PBConflictError). reportOf value: x last.
    ((firstErr value: out last) isKindOf: PBConflictError). held value: out last. reportOf value: out last }
  equals: { true. false. #(#none). true. #(#none). true. false. #(#committed) }.

"(30) an entry's build error, of any class, fails that entry alone (IQ1; was m5 before plan Task 4b)"
st := go value: core value: (rule value: core value: true) first value: {
  { PBBuildFailed entry: (e value: 'a' value: false) error: (Error new messageText: 'bug'; yourself) tierFailed: false. 2000 } }.
x := go value: core value: (rule value: core value: true) first value: {
  { PBBuildFailed entry: (e value: 'a' value: false) error: (PBValidationError new messageText: 'v'; yourself) tierFailed: false. 2000 } }.
c that: 'a build error of any class fails its commit alone; the round builds the next entry'
  is: { (settles value: st last) collect: [:q | { q first. q last messageText }]. reportOf value: st last. st first phase.
    (settles value: x last) collect: [:q | q first]. x first phase }
  equals: { #(#('a' 'bug')). #(). #build. #('a'). #build }.
out := go value: core value: st first value: {
  { PBBuilt entry: (e value: 'b' value: false) root: (rec value: T value: 2) micros: 1000. 3000 }. { PBReplicated outcome: #committed. 4000 } }.
c that: 'after the failed build the round builds b on the same base, stamped { T. 2 }, and commits it; a is not settled again'
  is: { (builds value: st last) collect: [:bd | { bd entry token. bd base == r1. bd stamp }].
    (settles value: out last) collect: [:q | { q first. q last }] }
  equals: { { { 'b'. true. { T. 2 } } }. #(#('b' true)) }.
x := go value: core value: (rule value: core value: true) first value: {
  { PBBuildFailed entry: (e value: 'a' value: false) error: (ZeroDivide new messageText: 'z'; yourself) tierFailed: false micros: 4500. 2000 } }.
c that: 'a failed build''s time counts in the round''s longest build (CC11, CC18), as a built one''s; refused when not an Integer >= 0'
  is: { x first longest. st first longest.
    err value: [PBBuildFailed entry: nil error: (Error new messageText: 'v'; yourself) tierFailed: false micros: -1] }
  equals: { 4500. 0. PBValidationError }.

"(31) n1: with no held caller, the kept permission waits for as many commits as conflicts"
st := go value: core value: fresh value: {
  permitted. { PBRoundEnqueued entry: (e value: 'h' value: false). 0 }. { PBRoundEnqueued entry: (e value: 'k' value: false). 0 }.
  { PBPermitted permission: perm. 0 }. { ok. 1000 }.
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 }.
  { conflict value: 'h' value: false. 3000 }. { conflict value: 'k' value: false. 3500 }. { PBReplicated outcome: #committed. 4000 } }.
x := go value: core value: st first value: { { PBRoundEnqueued entry: (e value: 'h' value: false). 4100 } }.
c that: 'two conflicts nobody holds: the next round waits for two commits'
  is: { st first awaitCount. x first phase.
    (go value: core value: x first value: { { PBRoundEnqueued entry: (e value: 'k' value: false). 4200 } }) first phase }
  equals: { 2. #held. #base }.

"(32) n2: the stale limit fails the whole queue, not only the round's commits (proto_db pending)"
st := staleRun value: (go value: core value: fresh value: { permitted }) first value: core termRetries - 1.
st := go value: core value: st first value: { { PBPermitted permission: perm. 9000 }.
  { PBRoundEnqueued entry: (e value: 'q' value: false). 9001 }. { stale. 9002 } }.
c that: 'after termRetries stale permissions, a commit queued meanwhile fails too'
  is: { (settles value: st last) collect: [:q | q first]. st first phase. st first queue }
  equals: { #('a' 'q'). #idle. #() }.

"(33) R231: the tier flag of PBBuildFailed"
c that: 'PBBuildFailed carries whether the tier failed, a Boolean, and has no constructor without it'
  is: { (PBBuildFailed entry: nil error: Error new tierFailed: true) isTierFailed.
    (PBBuildFailed entry: nil error: Error new tierFailed: false) isTierFailed.
    err value: [PBBuildFailed entry: nil error: Error new tierFailed: nil].
    PBBuildFailed class includesSelector: #entry:error: }
  equals: { true. false. PBValidationError. false }.

"(34) m2: a converted build joins the conflicts. HaltAfterBuild stops the round after the
 answer, so the state shows where the entry went."
x := PBUnexpectedError new messageText: 'store unreachable'; yourself.
st := go value: HaltAfterBuild new value: (rule value: core value: false) first value: {
  { PBBuildFailed entry: (e value: 'a' value: false) error: x tierFailed: false. 700000 } }.
c that: 'a build failing with exactly PBUnexpectedError after the permission expired joins the conflicts, its conflict caused by the error, not settled at once'
  is: { st first conflicted collect: [:q | q first token]. (st first conflicted collect: [:q | q last cause == x]) asArray.
    (st first conflicted collect: [:q | q last class]) asArray. (settles value: st last) size }
  equals: { #('a'). { true }. { PBConflictError }. 0 }.
x := ZeroDivide new messageText: 'ZeroDivide'; yourself.
st := go value: HaltAfterBuild new value: (rule value: core value: false) first value: {
  { PBBuildFailed entry: (e value: 'a' value: false) error: x tierFailed: false. 700000 } }.
c that: 'a build failing with an error that is not a PBDBError after the permission expired settles alone with it, never a conflict'
  is: { st first conflicted size. (settles value: st last) collect: [:q | { q first. q last == x }] }
  equals: { 0. #(#('a' true)) }.

"(35) Task 23: a replicate that failed with an error (PBReplicateFailed: the shell's flush, or a
 rejection of the coordinator's replicate). proto_db _permit_round's except branch: nothing was
 sent when the error is a conflict, a validation error (PBClosedError included) or a user error;
 any other error (a protocol violation, PBUnexpectedError) leaves the permission unknown. Every
 entry of the round gets the error itself, never a guess; the re-commit's replicate too."
st := go value: core value: (rule value: core value: false) first value: {
  { PBBuilt entry: (e value: 'a' value: false) root: (rec value: T value: 2) micros: 1000. 2000 } }.
x := [:anError | go value: core value: st first value: { { PBReplicateFailed error: anError. 3000 } }].
out := (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 } }) first.
out := go value: core value: out value: { { PBBaseDecided decision: (PBBaseDecision base: r1 needsCommit: true outcome: #ok). 1000 }.
  { PBBuilt entry: nil root: (rec value: T value: 2) micros: 0. 1000 }.
  { PBReplicateFailed error: (PBCorruptionError new messageText: 'v'; yourself). 2000 } }.
c that: 'a failed replicate ends the round with its error: nothing sent for a conflict, validation or user error, unknown otherwise'
  is: { #(#PBValidationError #PBClosedError #PBConflictError #PBUserError #PBCorruptionError #PBUnexpectedError) collect: [:k | | r |
      r := x value: ((Smalltalk at: k) new messageText: 'x'; yourself).
      { (firstErr value: r last) class name. reportOf value: r last. r first phase }].
    (settles value: out last) collect: [:q | q first]. reportOf value: out last.
    err value: [go value: core value: fresh value: { { PBReplicateFailed error: Error new. 0 } }].
    err value: [PBReplicateFailed error: 3] }
  equals: { { { #PBValidationError. #(#none). #idle }. { #PBClosedError. #(#none). #idle }. { #PBConflictError. #(#none). #idle }.
      { #PBUserError. #(#none). #idle }. { #PBCorruptionError. #(#unknown). #idle }. { #PBUnexpectedError. #(#unknown). #idle } }.
    #('a'). #(#unknown). PBValidationError. PBValidationError }.

"(36) Task 23, Review Focus 1: the space closed (PBRoundClosed left:). Every commit of the node
 is settled: one nothing of which left the node PBClosedError, one whose root left it (the
 shell's replicate left, in #replicate or #recommitting) PBOutcomeUnknownError; a conflicted
 entry its own conflict. A permission held ends with its outcome (#unknown once the root left),
 and no permit is asked."
x := [:aState :isLeft | go value: core value: aState value: { { PBRoundClosed left: isLeft. 5000 } }].
out := { (go value: core value: fresh value: { permitted. { PBRoundEnqueued entry: (e value: 'q' value: false). 0 } }) first.
  (go value: core value: fresh value: { permitted. { PBPermitted permission: perm. 0 } }) first.
  st first. st first.
  (hround value: core value: true value: 4000) first }.
out := (1 to: 5) collect: [:i | x value: (out at: i) value: (#(true true false true true) at: i)].
c that: 'closing settles every commit: PBClosedError when nothing left, PBOutcomeUnknownError once the root left; the permission ends, no permit'
  is: (out collect: [:r | { (settles value: r last) collect: [:q | { q first. q last class name }]. reportOf value: r last.
    (r last select: [:f | f isKindOf: PBAskPermit]) size. r first phase. r first queue size }])
  equals: { { { { 'a'. #PBClosedError }. { 'q'. #PBClosedError } }. #(). 0. #idle. 0 }.
    { { { 'a'. #PBClosedError } }. #(#none). 0. #idle. 0 }.
    { { { 'a'. #PBClosedError } }. #(#none). 0. #idle. 0 }.
    { { { 'a'. #PBOutcomeUnknownError } }. #(#unknown). 0. #idle. 0 }.
    { #(). #(#committed). 0. #idle. 0 } }.

c report.
