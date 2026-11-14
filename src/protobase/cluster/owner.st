"-- cluster/owner.st: the owner's rules O1-O8 at DEPTH 0, abandoned terms, permit requests --

The owner side of proto_db's ClusterCoordinator (cluster/coordinator.py at v2.0.0rc3: _dispatch,
_on_permit_req, _permit_outcome, _abandon, _refuse_queue, _on_done_owner, finish and the owner
checks of _own_loop_body) and the holder side of a permit request (_permission_from_owner,
_on_permit_reply), as rule methods of PBCoordinatorCore over the values of lease.st, core.st,
proposer.st and this module, at DEPTH 0 (CC7: pipelined permissions, O2 and O4, are Phase D).
Nothing here reads a clock: t is the node's clock (CC3).

  The owner (coordinator-protocol.rst 'The owner's rules, O1 to O8'). Its ownership keeps a
    FIFO of permission requests, its own commits' among the members' (PBOwnership queue), and a
    pipeline of at most one issued permission (PBIssued).
    O1 (_issue:now:effects:, proto_db _dispatch): a permission is issued when the queue is not
       empty, the term serves (not abandoned, lease valid), the pipeline is empty (DEPTH 0),
       the ownerIdleRelease drain allows it, and at least a quarter of the belief is left (else
       the ownership renews first). It carries the base (the newest root known committed in the
       term, the lease's root at first), certain when that base is known committed, and the
       remaining lease as valid; its deadline is valid + requestTimeout on the owner's clock.
       Counted permits_issued. A local commit's permission settles its waiter; a member's is
       permit(term, rid, seq, inc, root, certain, valid, after nil).
    O3 (_permitOutcome:): a 'committed' done retires its entry and every older one; its root
       becomes the base if it orders above it, and the base is known committed.
    O5: a 'none' from the only entry removes it; the next permit reuses the base (D50).
    O6: anything else abandons the term: 'unknown'; a done of another incarnation than the
       permission's (counted as 'unknown', L12); no done by the deadline; the lease expiring
       with a permission out (proposer.st _ownLoop:).
    O7 (receivedPermitReq:): a retried request whose permit is out gets that same permit again,
       never a second; a request already queued is not queued twice.
    O8: the term ends idle (or by the R80 drain) only with an empty pipeline (_ownLoop:).
    A permit_req for a term this node does not serve is refused: permit_no(term = max(highest
    term seen, own term), reason 'not_owner' when it owns no term or another one, 'ending' when
    that term no longer serves).
  Abandoning a term (_abandon:why:now:effects:, D50): counted terms_abandoned; the node is
    suspect for the term (suspectTerm, and PBSuspect to its acceptor, which then reports certain
    = false); every queued member gets permit_no 'abandoned' and the local waiters wait again;
    the pipeline is cleared; the ownership loop ends the term and releases it as uncertain
    (proposer.st _releaseLease:, certain only when not suspect). The next owner's phase 1 decides
    what the term left. The dispatcher's suspicion is cleared by committed knowledge (Task 13,
    proto_db _learn_label); until then it stays, which only makes later leases uncertain.
  A done (receivedDone:, proto_db _on_done_owner): every member learns the owner of its term and
    counts it as a wake-up and progress (it ends a back-off); the owner of that term sequences
    the next permission now (O3, O5, O6); the message then goes to the acceptor lane, where
    Task 13 learns the committed root it teaches. dispatchDoneReport: (proto_db finish): the
    holder's done(term, seq, inc, outcome, root, copies: this node for a committed root, ranges)
    is broadcast; at its own ownership the outcome is applied at once, if the permission was
    issued to this incarnation.
  The holder side (PBHolder, proto_db _permit_waits). A waiter's deadline is acquireTimeout from
    its PBPermitWanted. With an owner hint naming another member (term not 0), a waiter asks it
    (_ask:, a PBPermitAsk): permit_req(term, rid, inc) under the hint's term, counted
    permit_requests_sent, sent again every requestTimeout while unanswered (counted
    permit_requests_retried: the owner answers a retry with the same permit, O7). It ends:
    with a permit (receivedPermit:): the hint learns its term; a permit of another incarnation
    is dropped unanswered (counted permits_foreign_dropped: only the incarnation it was issued
    to may say what was done with it, L12); a duplicate (term, seq) is dropped; a permit nobody
    waits for is handed back at once with done 'none'; else the waiter gets a PBPermission valid
    for valid from the request's send (the owner issued it later, so it never outlasts the
    owner's lease here), certain only when the base is known and no after names a proposal
    (H2), counted permits_held. With a refusal (receivedPermitNo:): one to another incarnation
    is dropped (stale_replies); else counted permits_refused, and the hint forgets its sender
    as owner only while it still names the term the request was sent under (_refusalForgets:,
    proto_db 8.3n fix round 2). With silence: at leaseDuration after the send, or at the
    waiter's deadline, the hint forgets the owner only if it still names the term asked under
    and that member (_silenceForgets:, re-review 1 N4). A refused or silent waiter then tries
    to own (proposer.st), and every new round asks a known owner first.
  acquireTimeout: a waiter queued at this node's own ownership whose deadline passed leaves the
    queue and ends in PBTimeoutError (_expireQueued:now:effects:, run before every issue and by
    the ownership loop, whose timer includes the earliest such deadline; proto_db: the thread
    leaves the queue at its deadline and permit raises, the ownership holding _local). A waiter
    of the acquisition (proposer.st) whose deadline passed ends in PBTimeoutError after a lost
    round, a deferral that yields to an owner, or while the acceptor rejoins; the turn's deferral
    ends at the earliest deadline, and the back-off never lasts past it.

Timing differences from proto_db (no safety rule reads them): proto_db's threads ask an owner
each on their own; here a waiter refused or silent rejoins the node's acquisition, whose next
round asks a known owner at once (proto_db backs off once first); a waiter that is not the head
of the acquisition times out at the end of the first round after its deadline (proto_db's
thread, blocked on the local lock, at its deadline); a waiter queued at the ownership while a
renewal runs times out when the renewal closes.

Every value here is immutable: built once by its class-side constructor; with: answers a new
value."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/protocol'.
Import from: 'protobase/cluster/config'.
Import from: 'protobase/cluster/lease'.
Import from: 'protobase/cluster/core'.
Import from: 'protobase/cluster/acceptor'.
Import from: 'protobase/cluster/proposer'.

"=== PBIssued ================================================================"

"One permission an owner issued and has not retired (proto_db _Issued at DEPTH 0): to node's
 incarnation inc for its request rid, number seq, deadline on the owner's clock (valid +
 requestTimeout from the issue), the permit message sent (nil for this node's own commits) and
 the base it carries (a PBLabeledRoot, nil when unknown)."
PBProposerValue subclass: #PBIssued.

PBIssued class >> fieldNames
  ^ #(#node #seq #inc #rid #deadline #permit #base).

PBIssued class >> node: aNode seq: aSeq inc: anInc rid: aRid deadline: aDeadline permit: aMessage base: aRoot
  ^ self _from: (Dictionary new
    at: #node put: aNode; at: #seq put: aSeq; at: #inc put: anInc; at: #rid put: aRid; at: #deadline put: aDeadline;
    at: #permit put: aMessage; at: #base put: aRoot; yourself).

PBIssued >> node
  ^ self _at: #node.

PBIssued >> seq
  ^ self _at: #seq.

PBIssued >> inc
  ^ self _at: #inc.

PBIssued >> rid
  ^ self _at: #rid.

PBIssued >> deadline
  ^ self _at: #deadline.

"The permit message sent, nil for a permission of this node's own commits."
PBIssued >> permit
  ^ self _at: #permit.

PBIssued >> base
  ^ self _at: #base.

PBIssued >> printOn: aStream
  aStream nextPutAll: 'PBIssued('; print: self seq; nextPutAll: ' to '; nextPutAll: self node; nextPut: $).

"=== PBPermitAsk ============================================================="

"A permit request of a local waiter to the owner a hint named (proto_db _PermitWait): the
 waiter, the request id, its send, the term asked under and the member asked, the request (sent
 again on a retry), when it is retried next, when it ends unanswered (the send + leaseDuration,
 or the waiter's deadline if earlier) and the token of its timer."
PBProposerValue subclass: #PBPermitAsk.

PBPermitAsk class >> fieldNames
  ^ #(#waiter #rid #sentAt #term #target #request #retryAt #endAt #token).

PBPermitAsk class >> waiter: aWaiter rid: aRid sentAt: aSent term: aTerm target: aNode request: aMessage retryAt: aRetry endAt: anEnd
  ^ self _from: (Dictionary new
    at: #waiter put: aWaiter; at: #rid put: aRid; at: #sentAt put: aSent; at: #term put: aTerm; at: #target put: aNode;
    at: #request put: aMessage; at: #retryAt put: aRetry; at: #endAt put: anEnd; at: #token put: nil; yourself).

PBPermitAsk >> waiter
  ^ self _at: #waiter.

PBPermitAsk >> rid
  ^ self _at: #rid.

PBPermitAsk >> sentAt
  ^ self _at: #sentAt.

PBPermitAsk >> term
  ^ self _at: #term.

PBPermitAsk >> target
  ^ self _at: #target.

PBPermitAsk >> request
  ^ self _at: #request.

PBPermitAsk >> retryAt
  ^ self _at: #retryAt.

PBPermitAsk >> endAt
  ^ self _at: #endAt.

PBPermitAsk >> token
  | token |
  token := self _at: #token.
  ^ token isNil ifTrue: [nil] ifFalse: [token copy].

PBPermitAsk >> printOn: aStream
  aStream nextPutAll: 'PBPermitAsk('; print: self rid; nextPutAll: ' to '; nextPutAll: self target; nextPut: $).

"=== PBHolder ================================================================"

"The holder side of a node's permissions: the permit requests out (PBPermitAsk), the deadline of
 every local waiter not yet settled ({ waiter. deadline }), the last permits seen ({ term.
 seq }, at most permitsSeenLimit: proto_db _permits_seen), the replications not decided yet
 (holder.st PBReplication), the base choices and recovery rounds in progress (holder.st
 PBBaseChoice) and what the holder bound and sent under each permission it holds ({ { term.
 seq }. base bound or nil. root last sent or nil }, at most permitsSeenLimit: proto_db
 lease.bind_root and lease.sent)."
PBProposerValue subclass: #PBHolder.

PBHolder class >> fieldNames
  ^ #(#asks #deadlines #seen #replications #choices #permits).

PBHolder class >> permitsSeenLimit
  ^ 64.

PBHolder class >> empty
  ^ self _from: (Dictionary new at: #asks put: #(); at: #deadlines put: #(); at: #seen put: #();
    at: #replications put: #(); at: #choices put: #(); at: #permits put: #(); yourself).

"A fresh Array."
PBHolder >> asks
  ^ (self _at: #asks) copy.

"{ waiter. deadline } of every local waiter not yet settled, a fresh Array."
PBHolder >> deadlines
  ^ (self _at: #deadlines) collect: [:e | e copy].

"{ term. seq } of the last permits seen, a fresh Array."
PBHolder >> seen
  ^ (self _at: #seen) collect: [:e | e copy].

"The deadline of aWaiter (microseconds of the node's clock), nil when none is recorded."
PBHolder >> deadlineOf: aWaiter
  | e |
  e := (self _at: #deadlines) detect: [:d | d first = aWaiter] ifNone: [nil].
  ^ e isNil ifTrue: [nil] ifFalse: [e last].

"The replications not decided yet (holder.st PBReplication), a fresh Array."
PBHolder >> replications
  ^ (self _at: #replications) copy.

"The base choices and recovery rounds in progress (holder.st PBBaseChoice), a fresh Array."
PBHolder >> choices
  ^ (self _at: #choices) copy.

"{ { term. seq }. bound. sent } of the permissions held (holder.st), a fresh Array."
PBHolder >> permits
  ^ (self _at: #permits) collect: [:e | e copy].

"The ask whose request id is aRid, or nil."
PBHolder >> askWithRid: aRid
  ^ (self _at: #asks) detect: [:a | a rid = aRid] ifNone: [nil].

"=== PBCoordinatorCore: the holder's helpers ================================="

PBCoordinatorCore >> _holderIn: s
  ^ s holder isNil ifTrue: [PBHolder empty] ifFalse: [s holder].

"s with aWaiter's deadline recorded: acquireTimeout from t (proto_db permit's deadline)."
PBCoordinatorCore >> _expect: aWaiter in: s now: t
  | h |
  h := self _holderIn: s.
  ^ s with: { #holder -> (h with: { #deadlines -> ((h deadlines reject: [:e | e first = aWaiter])
    copyWith: { aWaiter. t + s config acquireTimeout }) }) }.

"aWaiter settled with anOutcome (a PBSettle), its deadline forgotten."
PBCoordinatorCore >> _settle: aWaiter with: anOutcome in: s effects: fx
  | h |
  fx add: (PBSettle waiter: aWaiter outcome: anOutcome).
  h := self _holderIn: s.
  ^ s with: { #holder -> (h with: { #deadlines -> (h deadlines reject: [:e | e first = aWaiter]) }) }.

"The earliest deadline of the waiters of the acquisition, nil when none has one."
PBCoordinatorCore >> _deadlineIn: s
  | h deadline |
  h := self _holderIn: s.
  deadline := nil.
  s waiters do: [:w | | d |
    d := h deadlineOf: w.
    (d notNil and: [deadline isNil or: [d < deadline]]) ifTrue: [deadline := d]].
  ^ deadline.

"Every waiter of the acquisition whose deadline passed at t ends in PBTimeoutError (proto_db
 permit, _await_rejoin: ProtoTimeoutError), for aReason."
PBCoordinatorCore >> _expire: s because: aReason now: t effects: fx
  | late |
  late := self _late: s waiters in: s now: t.
  late isEmpty ifTrue: [^ s].
  ^ self _timeOut: late because: aReason in: (s with: { #waiters -> (s waiters reject: [:w | late includes: w]) }) effects: fx.

"The waiters of someWaiters whose deadline passed at t."
PBCoordinatorCore >> _late: someWaiters in: s now: t
  | h |
  h := self _holderIn: s.
  ^ someWaiters select: [:w | | d | d := h deadlineOf: w. d notNil and: [t >= d]].

"someWaiters settled with PBTimeoutError, for aReason."
PBCoordinatorCore >> _timeOut: someWaiters because: aReason in: s effects: fx
  | state |
  state := s.
  someWaiters do: [:w |
    state := self _settle: w with: (PBTimeoutError new messageText: 'Node ' , s config nodeId
      , ' could not obtain a write permission within ' , (s config acquireTimeout // 1000) printString , ' ms ('
      , aReason , ')'; yourself) in: state effects: fx].
  ^ state.

"Every local waiter queued at the ownership whose deadline passed at t leaves the queue and ends
 in PBTimeoutError (proto_db _permission_from_owner, own branch: the thread leaves the queue at
 its deadline, and permit raises, since the ownership holds _local)."
PBCoordinatorCore >> _expireQueued: s now: t effects: fx
  | own late |
  own := s ownership.
  own isNil ifTrue: [^ s].
  late := self _late: ((own queue collect: [:e | e at: 4]) reject: [:w | w isNil]) in: s now: t.
  late isEmpty ifTrue: [^ s].
  ^ self _timeOut: late because: 'its turn at this node''s ownership did not come'
    in: (s with: { #ownership -> (own with: { #queue -> (own queue reject: [:e | (e at: 4) notNil and: [late includes: (e at: 4)]]) }) })
    effects: fx.

"The earliest deadline of the local waiters queued at the ownership, nil when none has one."
PBCoordinatorCore >> _queuedDeadlineIn: s
  | h deadline |
  h := self _holderIn: s.
  deadline := nil.
  s ownership queue do: [:e | | d |
    d := (e at: 4) isNil ifTrue: [nil] ifFalse: [h deadlineOf: (e at: 4)].
    (d notNil and: [deadline isNil or: [d < deadline]]) ifTrue: [deadline := d]].
  ^ deadline.

"The member the owner hint names, when it is another member of a term above 0 (proto_db
 _permission_from_owner: target is None or target == self or term == 0 asks nobody), else nil."
PBCoordinatorCore >> _ownerToAsk: s
  | h |
  h := self _hintsIn: s.
  (h ownerNode isNil or: [h ownerNode = s config nodeId or: [h ownerTerm = 0]]) ifTrue: [^ nil].
  ^ h ownerNode.

"=== PBCoordinatorCore: asking an owner ======================================"

"Every waiter of the acquisition asks the owner the hint names (proto_db permit's loop, its first
 step): a waiter whose ask ends at once rejoins the waiters."
PBCoordinatorCore >> _askAll: s now: t effects: fx
  | state |
  state := s with: { #waiters -> #() }.
  s waiters do: [:w | state := self _ask: w in: state now: t effects: fx].
  ^ self _wantLease: state now: t effects: fx.

"proto_db _permission_from_owner, a known owner: aWaiter's permit_req under the hint's term to
 the member it names; with none named, aWaiter joins the waiters."
PBCoordinatorCore >> _ask: aWaiter in: s now: t effects: fx
  | target h holder rid request deadline endAt ask state |
  target := self _ownerToAsk: s.
  target isNil ifTrue: [^ self _wantLease: (s with: { #waiters -> (s waiters copyWith: aWaiter) }) now: t effects: fx].
  h := self _hintsIn: s.
  rid := s nextRid.
  request := PBClusterMessage type: 'permit_req' from: s config nodeId fields: {
    'term' -> h ownerTerm. 'rid' -> rid. 'inc' -> s inc }.
  fx add: (PBCount stat: 'permit_requests_sent'); add: (PBSend to: target message: request).
  holder := self _holderIn: s.
  deadline := holder deadlineOf: aWaiter.
  "A remote owner answers when the request reaches the head of its queue; one leaseDuration
   without an answer means it is gone or busy elsewhere."
  endAt := t + s config leaseDuration.
  deadline notNil ifTrue: [endAt := endAt min: deadline].
  ask := PBPermitAsk waiter: aWaiter rid: rid sentAt: t term: h ownerTerm target: target request: request
    retryAt: t + s config requestTimeout endAt: endAt.
  state := s with: { #nextRid -> (rid + 1). #holder -> (holder with: { #asks -> (holder asks copyWith: ask) }) }.
  t >= endAt ifTrue: [^ self _askSilent: ask in: state now: t effects: fx].
  ^ self _arm: ask in: state now: t effects: fx.

"The ask anAsk (in s) with a timer of its own until its next retry or its end."
PBCoordinatorCore >> _arm: anAsk in: s now: t effects: fx
  | pair state armed |
  pair := self _token: #ask in: s.
  state := pair first.
  fx add: (PBTimer after: (0 max: (anAsk retryAt min: anAsk endAt) - t) token: pair last event: #ask).
  armed := anAsk with: { #token -> pair last }.
  ^ self _replaceAsk: anAsk with: armed in: state.

"s with anAsk replaced by anotherAsk (nil: removed)."
PBCoordinatorCore >> _replaceAsk: anAsk with: anotherAsk in: s
  | h asks |
  h := self _holderIn: s.
  asks := h asks reject: [:a | a rid = anAsk rid].
  anotherAsk notNil ifTrue: [asks := asks copyWith: anotherAsk].
  ^ s with: { #holder -> (h with: { #asks -> asks }) }.

"The timer of an ask: at its end, silence; at its retry, the request again (proto_db review M6)."
PBCoordinatorCore >> _askTimer: anEvent in: s now: t effects: fx
  | ask |
  ask := (self _holderIn: s) asks detect: [:a | a token = anEvent token] ifNone: [nil].
  ask isNil ifTrue: [^ s].
  t >= ask endAt ifTrue: [^ self _askSilent: ask in: s now: t effects: fx].
  t >= ask retryAt ifFalse: [^ self _arm: ask in: s now: t effects: fx].
  fx add: (PBCount stat: 'permit_requests_retried'); add: (PBSend to: ask target message: ask request).
  ^ self _arm: (ask with: { #retryAt -> (t + s config requestTimeout) }) in: s now: t effects: fx.

"Whether silence about anAsk forgets the owner aHints names: only while the hint still names the
 term the request was sent under and that member (proto_db: the owner hint == (wait.term,
 target); a newer term of that member learnt since, from its renewals, says nothing about the
 silence)."
PBCoordinatorCore >> _silenceForgets: anAsk in: aHints
  ^ aHints ownerTerm = anAsk term and: [aHints ownerNode = anAsk target].

"Whether aSender's refusal of anAsk forgets aSender as the owner aHints names: only while the hint
 names aSender for the term the request was sent under, whatever term the refusal carries (the
 sender's highest)."
PBCoordinatorCore >> _refusalForgets: anAsk from: aSender in: aHints
  ^ aHints ownerNode = aSender and: [aHints ownerTerm = anAsk term].

"No answer to anAsk within its wait: the owner is forgotten (_silenceForgets:in:), the waiter
 tries to own; a permit arriving later is handed back."
PBCoordinatorCore >> _askSilent: anAsk in: s now: t effects: fx
  | h state |
  h := self _hintsIn: s.
  (self _silenceForgets: anAsk in: h) ifTrue: [h := h with: { #ownerNode -> nil }].
  state := (self _replaceAsk: anAsk with: nil in: s) with: { #hints -> h }.
  state := state with: { #waiters -> (state waiters copyWith: anAsk waiter) }.
  ^ self _wantLease: (self _poke: state now: t effects: fx) now: t effects: fx.

"proto_db _on_permit_reply, a permit: the hint learns its term (a permit proves it); one of
 another incarnation is dropped unanswered (L12), a duplicate dropped, one nobody waits for
 handed back with done 'none'; else the waiter gets its PBPermission."
PBCoordinatorCore >> receivedPermit: anEvent in: s now: t
  ^ self _step: [:fx | | m holder key ask root state permission seen |
    m := anEvent message.
    state := s with: { #hints -> (self _noteOwner: (m at: 'term') in: (self _hintsIn: s) of: s) }.
    holder := self _holderIn: state.
    key := { m at: 'term'. m at: 'seq' }.
    (m at: 'inc') ~= s inc
      ifTrue: [
        "Issued to another incarnation of this node: only the incarnation that received a
         permission may say what it did with it; its owner learns the outcome as unknown."
        fx add: (PBCount stat: 'permits_foreign_dropped')]
      ifFalse: [
        (holder seen includes: key) ifFalse: [
          seen := holder seen copyWith: key.
          seen size > PBHolder permitsSeenLimit ifTrue: [seen := seen copyFrom: seen size - PBHolder permitsSeenLimit + 1 to: seen size].
          holder := holder with: { #seen -> seen }.
          state := state with: { #holder -> holder }.
          ask := holder askWithRid: (m at: 'rid').
          ask isNil
            ifTrue: [
              "Nobody waits for it any more: handed back at once, so the owner moves on (O5)."
              fx add: (PBSend to: m from message: (PBClusterMessage type: 'done' from: s config nodeId fields: {
                'term' -> (m at: 'term'). 'seq' -> (m at: 'seq'). 'inc' -> s inc. 'outcome' -> 'none'. 'root' -> nil.
                'copies' -> #(). 'ranges' -> nil }))]
            ifFalse: [
              root := PBClusterMessage rootFrom: (m at: 'root').
              "Valid from the request's send (D45): the owner issued it later. H2: a proposal base
               (after) is never certain."
              permission := PBPermission term: (m at: 'term') seq: (m at: 'seq') rid: (m at: 'rid') owner: m from root: root
                certain: ((m at: 'certain') and: [root notNil and: [(m at: 'after') isNil]])
                sentAt: ask sentAt valid: (self class microsFromWire: (m at: 'valid')).
              fx add: (PBCount stat: 'permits_held').
              self _observePermit: permission effects: fx.
              state := self _settle: ask waiter with: permission in: (self _replaceAsk: ask with: nil in: state) effects: fx]]].
    self _poke: state now: t effects: fx].

"proto_db _permission_from_owner: a permission whose base is certain teaches its base as
 committed (_observe_committed, accepted knowledge, not logged), so that this node, owning a
 later term, knows its lease root committed (proposer.st _own:)."
PBCoordinatorCore >> _observePermit: aPermission effects: fx
  aPermission isCertain ifTrue: [
    fx add: (PBToAcceptor event: (PBLearnCommitted root: aPermission root accept: true logged: false))].

"proto_db _on_permit_reply, a permit_no: one to another incarnation is dropped (its request ids
 restarted); else the waiter's request was refused: the hint forgets the sender only while it
 names the term asked under (_refusalForgets:from:in:), and the waiter tries to own."
PBCoordinatorCore >> receivedPermitNo: anEvent in: s now: t
  ^ self _step: [:fx | | m ask h state |
    m := anEvent message.
    (m at: 'inc') ~= s inc
      ifTrue: [fx add: (PBCount stat: 'stale_replies'). s]
      ifFalse: [
        ask := (self _holderIn: s) askWithRid: (m at: 'rid').
        ask isNil
          ifTrue: [s]
          ifFalse: [
            fx add: (PBCount stat: 'permits_refused').
            h := self _hintsIn: s.
            (self _refusalForgets: ask from: m from in: h) ifTrue: [h := h with: { #ownerNode -> nil }].
            state := (self _replaceAsk: ask with: nil in: s) with: { #hints -> h }.
            state := state with: { #waiters -> (state waiters copyWith: ask waiter) }.
            self _wantLease: (self _poke: state now: t effects: fx) now: t effects: fx]]].

"=== PBCoordinatorCore: the owner ============================================"

"s with someWaiters (this node's own commits) queued at its ownership, each with a request id of
 its own, their demand now (proto_db _permission_from_owner, own branch)."
PBCoordinatorCore >> _queueLocal: someWaiters in: s now: t
  | own rid queue |
  someWaiters isEmpty ifTrue: [^ s].
  own := s ownership.
  rid := s nextRid.
  queue := own queue.
  someWaiters do: [:w |
    queue := queue copyWith: { s config nodeId. rid. s inc. w }.
    rid := rid + 1].
  ^ s with: { #nextRid -> rid. #ownership -> (own with: { #queue -> queue. #lastDemand -> t. #lastLocal -> t }) }.

"Whether the pipeline of anOwnership holds as many permissions as it may (O1: DEPTH + 1 at
 most, so one at DEPTH 0)."
PBCoordinatorCore >> _pipelineFull: anOwnership in: s
  ^ anOwnership pipeline size > s config depth.

"Rule O1 (proto_db _dispatch at DEPTH 0): the permission of the head of the queue, when the term
 serves, the pipeline is empty, the R80 drain allows it and a quarter of the belief is left."
PBCoordinatorCore >> _issue: aState now: t effects: fx
  | s own c entry seq valid base certain permit state issued |
  s := self _expireQueued: aState now: t effects: fx.
  own := s ownership.
  (own isNil or: [own queue isEmpty or: [(own isServingAt: t) not or: [self _pipelineFull: own in: s]]]) ifTrue: [^ s].
  c := s config.
  "Draining (R80): nothing new; the ownership loop ends the term once the pipeline is empty."
  (c ownerIdleRelease notNil and: [t - own lastLocal > c ownerIdleRelease]) ifTrue: [^ s].
  "Too little lease left for a replication to finish under it: the ownership renews first."
  4 * (own lease remainingAt: t) < c belief ifTrue: [^ s].
  entry := own queue first.
  seq := own seq + 1.
  "Valid for what remains of the owner's lease, never longer."
  valid := own lease remainingAt: t.
  base := own base.
  certain := base notNil and: [own isCommitted].
  fx add: (PBCount stat: 'permits_issued').
  (entry at: 4) notNil
    ifTrue: [
      | local |
      permit := nil.
      local := PBPermission term: own term seq: seq rid: (entry at: 2) owner: c nodeId root: base certain: certain
        sentAt: t valid: valid.
      self _observePermit: local effects: fx.
      state := self _settle: (entry at: 4) with: local in: s effects: fx]
    ifFalse: [
      permit := PBClusterMessage type: 'permit' from: c nodeId fields: {
        'term' -> own term. 'rid' -> (entry at: 2). 'seq' -> seq. 'inc' -> (entry at: 3).
        'root' -> (PBClusterMessage rootValue: base). 'certain' -> certain.
        'valid' -> (self class wireSeconds: valid). 'after' -> nil }.
      fx add: (PBSend to: entry first message: permit).
      state := s].
  issued := PBIssued node: entry first seq: seq inc: (entry at: 3) rid: (entry at: 2)
    deadline: t + valid + c requestTimeout permit: permit base: base.
  ^ state with: { #ownership -> (own with: { #queue -> (own queue copyFrom: 2 to: own queue size). #seq -> seq.
    #pipeline -> (own pipeline copyWith: issued) }) }.

"The members of someEntries (requests { node. rid. inc. waiter }) get permit_no aReason for
 aTerm; answers the local waiters among them, in order (proto_db _refuse_queue)."
PBCoordinatorCore >> _refuse: someEntries reason: aReason term: aTerm in: s effects: fx
  | locals |
  locals := OrderedCollection new.
  someEntries do: [:e |
    (e at: 4) notNil
      ifTrue: [locals add: (e at: 4)]
      ifFalse: [fx add: (PBSend to: e first message: (PBClusterMessage type: 'permit_no' from: s config nodeId fields: {
        'term' -> aTerm. 'rid' -> (e at: 2). 'inc' -> (e at: 3). 'reason' -> aReason }))]].
  ^ locals asArray.

"proto_db _abandon (D50): an outcome the owner cannot know. Suspect for the term (its acceptor
 too), the queue refused 'abandoned' (local waiters wait again), the pipeline cleared; the
 ownership loop releases the lease as uncertain. aText says why (proto_db logs it)."
PBCoordinatorCore >> _abandon: s why: aText now: t effects: fx
  | own locals |
  own := s ownership.
  (own isNil or: [own isAbandoned]) ifTrue: [^ s].
  fx add: (PBCount stat: 'terms_abandoned'); add: (PBToAcceptor event: (PBSuspect term: own term)).
  locals := self _refuse: own queue reason: 'abandoned' term: own term in: s effects: fx.
  ^ s with: { #ownership -> (own with: { #abandoned -> true. #pipeline -> #(). #queue -> #() }).
    #suspectTerm -> (s suspectTerm max: own term). #waiters -> (locals , s waiters) }.

"The issued permission anIssued of the ownership ended with anOutcome (a String: 'committed',
 'none', or anything else) and aRoot, told by the incarnation it was issued to (proto_db
 _permit_outcome at DEPTH 0): O3, O5, O6; then the next permission, and the ownership loop."
PBCoordinatorCore >> _permitOutcome: anIssued outcome: anOutcome root: aRoot in: s now: t effects: fx
  | own pipeline index base state |
  own := s ownership.
  pipeline := own pipeline.
  anOutcome = 'committed'
    ifTrue: [
      "O3: it and every older entry retire; its root becomes the committed base."
      index := (1 to: pipeline size) detect: [:i | (pipeline at: i) node = anIssued node and: [(pipeline at: i) seq = anIssued seq]].
      base := own base.
      (base isNil or: [(PBRootOrder compare: aRoot with: base) > 0]) ifTrue: [base := aRoot].
      state := s with: { #ownership -> (own with: { #pipeline -> (pipeline copyFrom: index + 1 to: pipeline size).
        #base -> base. #committed -> true }) }]
    ifFalse: [
      anOutcome = 'none'
        ifTrue: [
          "O5: the only entry ended without a root: the next permit reuses the committed base."
          (pipeline size = 1 and: [pipeline first node = anIssued node and: [pipeline first seq = anIssued seq]])
            ifTrue: [state := s with: { #ownership -> (own with: { #pipeline -> #() }) }]
            ifFalse: [
              state := self _abandon: s why: 'permission ' , anIssued seq printString , ' of ' , anIssued node
                , ' ended without a root with another permission outstanding' now: t effects: fx]]
        ifFalse: [
          "O6: an outcome the owner cannot sequence."
          state := self _abandon: s why: anOutcome now: t effects: fx]].
  ^ self _ownLoop: (self _issue: state now: t effects: fx) now: t effects: fx.

"proto_db _on_permit_req: a member asks this node, as owner of term, for a permission. O7: a
 retried request whose permit is out gets that permit again; a request already queued is not
 queued twice. A term this node does not serve is refused."
PBCoordinatorCore >> receivedPermitReq: anEvent in: s now: t
  ^ self _step: [:fx | | m own sender out state view reason |
    m := anEvent message.
    own := s ownership.
    sender := m from.
    (own notNil and: [own term = (m at: 'term') and: [(own isServingAt: t) and: [s fenced isNil]]])
      ifTrue: [
        out := own pipeline detect: [:e | e node = sender and: [e inc = (m at: 'inc') and: [e rid = (m at: 'rid')]]] ifNone: [nil].
        out notNil
          ifTrue: [
            out permit notNil ifTrue: [fx add: (PBSend to: sender message: out permit)].
            state := s]
          ifFalse: [
            state := (own queue anySatisfy: [:e | e first = sender and: [(e at: 2) = (m at: 'rid')]])
              ifTrue: [s]
              ifFalse: [s with: { #ownership -> (own with: { #queue -> (own queue copyWith: { sender. m at: 'rid'. m at: 'inc'. nil }) }) }].
            state := self _issue: state now: t effects: fx].
        state := state with: { #ownership -> (state ownership with: { #lastDemand -> t }) }.
        self _ownLoop: state now: t effects: fx]
      ifFalse: [
        reason := (own isNil or: [own term ~= (m at: 'term')]) ifTrue: ['not_owner'] ifFalse: ['ending'].
        view := s acceptorView.
        fx add: (PBSend to: sender message: (PBClusterMessage type: 'permit_no' from: s config nodeId fields: {
          'term' -> ((view isNil ifTrue: [0] ifFalse: [view grants highestSeen]) max: (own isNil ifTrue: [0] ifFalse: [own term])).
          'rid' -> (m at: 'rid'). 'inc' -> (m at: 'inc'). 'reason' -> reason })).
        s]].

"proto_db _on_done_owner: a permission ended. Every member learns the owner of its term and
 counts a wake-up and progress; the owner of that term sequences the next permission now (the
 outcome of a done of another incarnation than the permission's is 'unknown', L12). The message
 then goes to the acceptor lane (the committed root it teaches, Task 13)."
PBCoordinatorCore >> receivedDone: anEvent in: s now: t
  ^ self _step: [:fx | | m h own issued state outcome |
    m := anEvent message.
    h := self _noteOwner: (m at: 'term') in: (self _hintsIn: s) of: s.
    state := s with: { #hints -> (h with: { #wakeups -> (h wakeups + 1). #progress -> (h progress + 1) }) }.
    own := state ownership.
    issued := (own notNil and: [own term = (m at: 'term')]) ifTrue: [own entryOf: m from seq: (m at: 'seq')] ifFalse: [nil].
    issued notNil ifTrue: [
      outcome := (m at: 'inc') = issued inc ifTrue: [m at: 'outcome'] ifFalse: ['unknown'].
      state := self _permitOutcome: issued outcome: outcome root: (PBClusterMessage rootFrom: (m at: 'root'))
        in: state now: t effects: fx].
    fx add: (PBToAcceptor event: anEvent).
    self _poke: state now: t effects: fx].

"proto_db finish: the holder of a permission tells every member its outcome, done(term, seq, inc,
 outcome, root, copies, ranges); the root is the committed one, known only when committed. At
 this node's own ownership, a permission issued to this incarnation is sequenced at once."
PBCoordinatorCore >> dispatchDoneReport: anEvent in: s now: t
  ^ self _step: [:fx | | p outcome root own issued state later |
    p := anEvent permission.
    outcome := anEvent outcome asString.
    root := outcome = 'committed'
      ifTrue: [anEvent root isNil ifTrue: [PBLabeledRoot label: 0 record: nil] ifFalse: [anEvent root]]
      ifFalse: [nil].
    "The permission ended: what the holder bound and sent under it is forgotten (holder.st)."
    state := self _forgetPermit: p in: s.
    later := OrderedCollection new.
    p owner = s config nodeId ifTrue: [
      own := s ownership.
      issued := (own notNil and: [own term = p term]) ifTrue: [own entryOf: s config nodeId seq: p seq] ifFalse: [nil].
      (issued notNil and: [issued inc = s inc]) ifTrue: [
        state := self _permitOutcome: issued outcome: outcome root: root in: state now: t effects: later]].
    self _broadcast: (PBClusterMessage type: 'done' from: s config nodeId fields: {
      'term' -> p term. 'seq' -> p seq. 'inc' -> s inc. 'outcome' -> outcome.
      'root' -> (PBClusterMessage rootValue: root).
      "proto_db finish: the placement a committed replication learnt (_learn_locator with
       copies [self], shared storage) names the holder; none otherwise."
      'copies' -> ((outcome = 'committed' and: [root record notNil]) ifTrue: [{ s config nodeId }] ifFalse: [#()]).
      'ranges' -> nil }) in: s effects: fx.
    fx addAll: later.
    state].
