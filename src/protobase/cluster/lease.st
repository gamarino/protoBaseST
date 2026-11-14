"-- cluster/lease.st: the grant rules of a peer, lease attempts, leases and permissions --

proto_db cluster/lease.py (PeerGrants, GrantDecision, LeaseAttempt, Lease, Permission) at
v2.0.0rc3, with the ballot check of coordinator.py _decide, as immutable values. Nothing here
reads a clock, sends, logs or waits: time is the argument now: (microseconds, the unit of
PBClusterConfig), and every transition answers a new value.

  PBGrantState     what one peer has promised (PeerGrants): a term is granted to at most one
                   holder, and once granted to no other holder until the grant expires on this
                   peer's clock (now >= expiry) or its holder releases it. Every request is
                   refused during the startup grace. A request of another incarnation of the
                   holder of the active grant ends that grant (its process is gone). The
                   caller makes promiseToLog durable before it sends a grant.
  PBActiveGrant    the grant that runs: holder, inc, term, expiry.
  PBGrantDecision  the outcome of a request or a renewal: verdict (#grant or #reject), reason
                   (the wire string: 'granted', 'bad_ballot', 'starting', 'stale_term',
                   'busy', 'term_taken'), highest, remaining (microseconds of the promise or
                   grace that blocks a grant; of the grant on a grant), promiseToLog (the term
                   of a grant, nil on a refusal), endedTerm (a grant this decision ended
                   without its holder's release, by expiry or by a new incarnation, 0 when
                   none: the caller is suspect for it) and newState.
  PBAttempt        the replies to one request of a requester (LeaseAttempt): won at a majority
                   of the voters (V // 2 + 1, the requester's own vote included), lost when that
                   is out of reach. A peer counts once, by its first reply.
  PBLease          a won lease: valid on the holder's clock until validUntil, which the caller
                   computes as the request's send + belief (L5: from the send, never the win).
  PBPermission     a write permission of the owner of a term (D50): a PBLease whose validUntil
                   is the send of the permit request + the owner's valid; after is nil at
                   DEPTH 0, and the base is certain only when it is known.

Every value here is immutable: built once by its class-side constructor."

Import from: 'protobase/errors'.
Import from: 'protobase/cluster/members'.
Import from: 'protobase/cluster/rootlog'.
Import from: 'protobase/cluster/config'.

"=== PBActiveGrant ==========================================================="

Object subclass: #PBActiveGrant instanceVariableNames: 'holder inc term expiry'.

PBActiveGrant class >> holder: aHolder inc: anInc term: aTerm expiry: anExpiry
  ^ self basicNew _setHolder: aHolder inc: anInc term: aTerm expiry: anExpiry.

PBActiveGrant >> _setHolder: aHolder inc: anInc term: aTerm expiry: anExpiry
  "Runs once, on a fresh instance."
  holder isNil ifFalse: [^ PBUserError signal: 'PBActiveGrant is immutable'].
  holder := aHolder.
  inc := anInc.
  term := aTerm.
  expiry := anExpiry.
  ^ self.

PBActiveGrant >> holder
  ^ holder.

PBActiveGrant >> inc
  ^ inc.

PBActiveGrant >> term
  ^ term.

"The time (microseconds, this peer's clock) the grant ends at."
PBActiveGrant >> expiry
  ^ expiry.

"=== PBGrantDecision ========================================================="

Object subclass: #PBGrantDecision instanceVariableNames: 'verdict reason highest remaining promiseToLog endedTerm newState'.

PBGrantDecision class >> verdict: aVerdict reason: aReason highest: aHighest remaining: aRemaining promiseToLog: aTerm endedTerm: anEnded newState: aState
  ^ self basicNew _setVerdict: aVerdict reason: aReason highest: aHighest remaining: aRemaining promiseToLog: aTerm endedTerm: anEnded newState: aState.

PBGrantDecision >> _setVerdict: aVerdict reason: aReason highest: aHighest remaining: aRemaining promiseToLog: aTerm endedTerm: anEnded newState: aState
  "Runs once, on a fresh instance."
  verdict isNil ifFalse: [^ PBUserError signal: 'PBGrantDecision is immutable'].
  verdict := aVerdict.
  reason := aReason.
  highest := aHighest.
  remaining := aRemaining.
  promiseToLog := aTerm.
  endedTerm := anEnded.
  newState := aState.
  ^ self.

"#grant or #reject."
PBGrantDecision >> verdict
  ^ verdict.

PBGrantDecision >> reason
  ^ reason.

"The highest term the reply reports (proto_db GrantDecision.highest)."
PBGrantDecision >> highest
  ^ highest.

PBGrantDecision >> remaining
  ^ remaining.

PBGrantDecision >> promiseToLog
  ^ promiseToLog.

PBGrantDecision >> endedTerm
  ^ endedTerm.

PBGrantDecision >> newState
  ^ newState.

"=== PBGrantState ============================================================"

"highest: the highest term seen in a request or a release; grantedMax: the highest term granted
 or closed here; grantedTop: the highest term actually granted here (the ballot a replicated
 root must not be below); grant: the PBActiveGrant, or nil; graceEnd: the end of the startup
 grace. A grant whose expiry has passed stays in grant until a rule settles it: every rule
 settles first, as proto_db's _settle."
Object subclass: #PBGrantState instanceVariableNames: 'highest grantedMax grantedTop grant graceEnd'.

"The state of a peer started at t: nothing granted, every request refused until t + startupGrace."
PBGrantState class >> initial: aConfig now: t
  ^ self basicNew _setHighest: 0 grantedMax: 0 grantedTop: 0 grant: nil graceEnd: t + aConfig startupGrace.

PBGrantState >> _setHighest: aHighest grantedMax: aMax grantedTop: aTop grant: aGrant graceEnd: anEnd
  "Runs once, on a fresh instance."
  graceEnd isNil ifFalse: [^ PBUserError signal: 'PBGrantState is immutable'].
  highest := aHighest.
  grantedMax := aMax.
  grantedTop := aTop.
  grant := aGrant.
  graceEnd := anEnd.
  ^ self.

PBGrantState >> _highest: aHighest grantedMax: aMax grantedTop: aTop grant: aGrant
  ^ self class basicNew _setHighest: aHighest grantedMax: aMax grantedTop: aTop grant: aGrant graceEnd: graceEnd.

PBGrantState >> highestSeen
  ^ highest.

PBGrantState >> highestGranted
  ^ grantedMax.

PBGrantState >> grantedTop
  ^ grantedTop.

"The PBActiveGrant last granted and not ended by a rule, or nil. Its expiry may have passed:
 the caller compares it with its now."
PBGrantState >> activeGrant
  ^ grant.

PBGrantState >> isStarting: t
  ^ t < graceEnd.

"Honours the promise logged before a restart (proto_db PeerGrants.restore, called by
 coordinator.py _attach_locked with max(promised, accepted label)): that term, and every lower
 one, counts as granted here. It reads no clock, as proto_db's."
PBGrantState >> restore: aLoggedRoots
  | term |
  term := aLoggedRoots promise max: (aLoggedRoots accepted isNil ifTrue: [0] ifFalse: [aLoggedRoots accepted label]).
  ^ self _highest: (highest max: term) grantedMax: (grantedMax max: term) grantedTop: (grantedTop max: term) grant: grant.

"Decides aHolder's (incarnation anInc) request for aTerm at t (proto_db _decide, then
 PeerGrants.on_request without renew)."
PBGrantState >> decideRequest: aHolder inc: anInc term: aTerm now: t config: c
  ^ self _decide: aHolder inc: anInc term: aTerm now: t config: c renew: false.

"Decides aHolder's renewal of aTerm at t (D50): the active, unreleased grant of that holder,
 incarnation and term is extended to t + leaseDuration, before the stale-term rule (a higher term
 only requested here, and refused, promised nothing); any other renewal is decided as a request.
 The term is already durable here, so the shell's promise write is a no-op (PBAcceptorLog
 promise: writes nothing at or below the durable promise)."
PBGrantState >> renew: aHolder inc: anInc term: aTerm now: t config: c
  ^ self _decide: aHolder inc: anInc term: aTerm now: t config: c renew: true.

PBGrantState >> _decide: aHolder inc: anInc term: aTerm now: t config: c renew: isRenew
  | g ended seen reject |
  aTerm \\ PBMembership maxMembers = (c membership rankOf: aHolder) ifFalse: [
    "Not this requester's ballot: granting it could give one term to two proposers. Decided
     before the grant rules, which it leaves untouched (coordinator.py _decide)."
    ^ PBGrantDecision verdict: #reject reason: 'bad_ballot' highest: highest remaining: 0 promiseToLog: nil
      endedTerm: 0 newState: self].
  g := grant.
  ended := 0.
  (g notNil and: [t >= g expiry]) ifTrue: [ended := g term. g := nil].
  (g notNil and: [g holder = aHolder and: [g inc ~= anInc]]) ifTrue: [ended := g term. g := nil].
  "Every outcome records the term as seen (the finally of on_request)."
  seen := highest max: aTerm.
  reject := [:aReason :aRemaining |
    PBGrantDecision verdict: #reject reason: aReason highest: highest remaining: aRemaining promiseToLog: nil
      endedTerm: ended newState: (self _highest: seen grantedMax: grantedMax grantedTop: grantedTop grant: g)].
  t < graceEnd ifTrue: [^ reject value: 'starting' value: graceEnd - t].
  (isRenew and: [g notNil and: [g holder = aHolder and: [g term = aTerm and: [g inc = anInc]]]]) ifTrue: [
    ^ PBGrantDecision verdict: #grant reason: 'granted' highest: highest remaining: c leaseDuration promiseToLog: aTerm
      endedTerm: 0 newState: (self _highest: seen grantedMax: grantedMax grantedTop: grantedTop
        grant: (PBActiveGrant holder: aHolder inc: anInc term: aTerm expiry: t + c leaseDuration))].
  aTerm < highest ifTrue: [^ reject value: 'stale_term' value: 0].
  g notNil ifTrue: [
    (g holder = aHolder and: [g term = aTerm]) ifTrue: [
      "A duplicate: granted again, the promise never extended."
      ^ PBGrantDecision verdict: #grant reason: 'granted' highest: highest remaining: g expiry - t promiseToLog: aTerm
        endedTerm: 0 newState: (self _highest: seen grantedMax: grantedMax grantedTop: grantedTop grant: g)].
    g holder = aHolder ifFalse: [^ reject value: 'busy' value: g expiry - t]].
  aTerm <= grantedMax ifTrue: [^ reject value: 'term_taken' value: 0].
  ^ PBGrantDecision verdict: #grant reason: 'granted' highest: aTerm remaining: c leaseDuration promiseToLog: aTerm
    endedTerm: ended newState: (self _highest: seen grantedMax: aTerm grantedTop: (grantedTop max: aTerm)
      grant: (PBActiveGrant holder: aHolder inc: anInc term: aTerm expiry: t + c leaseDuration)).

"Applies aHolder's release (or cancel) of aTerm from incarnation anInc at t (proto_db
 PeerGrants.on_release): frees the grant if it is that incarnation's grant of aTerm, and closes
 aTerm here, so a delayed duplicate of the request is refused. Answers { newState. endedTerm },
 endedTerm the term of a grant that had expired by t (the caller is suspect for it), else 0."
PBGrantState >> release: aHolder inc: anInc term: aTerm now: t
  | g ended |
  g := grant.
  ended := 0.
  (g notNil and: [t >= g expiry]) ifTrue: [ended := g term. g := nil].
  (g notNil and: [g holder = aHolder and: [g term = aTerm and: [g inc = anInc]]]) ifTrue: [g := nil].
  ^ { self _highest: (highest max: aTerm) grantedMax: (grantedMax max: aTerm) grantedTop: grantedTop grant: g. ended }.

PBGrantState >> printOn: aStream
  aStream nextPutAll: 'PBGrantState(highest '; print: highest; nextPutAll: ', granted '; print: grantedTop;
    nextPutAll: ', active '; print: (grant isNil ifTrue: [nil] ifFalse: [grant term]); nextPut: $).

"=== PBAttempt ==============================================================="

"grants: { peer. root. committed. certain } per granter, rejects: { peer. reason. highest.
 remaining } per refuser, in arrival order; highestSeen: the highest term of the request and of
 every refusal."
Object subclass: #PBAttempt instanceVariableNames: 'term rid sentAt voters grants rejects highestSeen'.

"An attempt for aTerm, request id r, sent at s (microseconds, the requester's clock), among v
 voters (learners excluded, D54)."
PBAttempt class >> term: aTerm rid: r sentAt: s voters: v
  (v isInteger and: [v > 0]) ifFalse: [
    ^ PBValidationError signal: 'PBAttempt: the voters are a positive Integer, not ' , v printString].
  ^ self basicNew _setTerm: aTerm rid: r sentAt: s voters: v grants: #() rejects: #() highestSeen: aTerm.

PBAttempt >> _setTerm: aTerm rid: r sentAt: s voters: v grants: aGrants rejects: aRejects highestSeen: aHighest
  "Runs once, on a fresh instance."
  grants isNil ifFalse: [^ PBUserError signal: 'PBAttempt is immutable'].
  term := aTerm.
  rid := r.
  sentAt := s.
  voters := v.
  grants := aGrants.
  rejects := aRejects.
  highestSeen := aHighest.
  ^ self.

PBAttempt >> _grants: aGrants rejects: aRejects highestSeen: aHighest
  ^ self class basicNew _setTerm: term rid: rid sentAt: sentAt voters: voters grants: aGrants rejects: aRejects highestSeen: aHighest.

PBAttempt >> _hasReplyFrom: aPeer
  ^ (grants anySatisfy: [:e | e first = aPeer]) or: [rejects anySatisfy: [:e | e first = aPeer]].

PBAttempt >> term
  ^ term.

PBAttempt >> rid
  ^ rid.

PBAttempt >> sentAt
  ^ sentAt.

"Grants needed to win: a majority of the voters, V // 2 + 1."
PBAttempt >> needed
  ^ voters // 2 + 1.

"The highest term of the request and of every refusal received (proto_db highest_seen)."
PBAttempt >> highestSeen
  ^ highestSeen.

"With aPeer's grant: aRoot (a PBLabeledRoot, or nil: it knows no root) is the root it accepted,
 aCommitted the root it knows committed, aBoolean false when it is suspect. A peer that already
 replied is not counted again (proto_db on_grant)."
PBAttempt >> withGrant: aPeer root: aRoot committed: aCommitted certain: aBoolean
  (self _hasReplyFrom: aPeer) ifTrue: [^ self].
  ^ self _grants: (grants copyWith: { aPeer. aRoot. aCommitted. aBoolean }) rejects: rejects highestSeen: highestSeen.

"With aPeer's refusal (reason the wire string, h its highest term, m the microseconds of the
 promise or grace that blocks it). The highest term counts even from a peer that already
 replied (proto_db on_reject)."
PBAttempt >> withReject: aPeer reason: aReason highest: h remaining: m
  (self _hasReplyFrom: aPeer) ifTrue: [^ self _grants: grants rejects: rejects highestSeen: (highestSeen max: h)].
  ^ self _grants: grants rejects: (rejects copyWith: { aPeer. aReason. h. m }) highestSeen: (highestSeen max: h).

"#won at needed grants, #lost when more than voters - needed refused, else #pending."
PBAttempt >> state
  grants size >= self needed ifTrue: [^ #won].
  rejects size > (voters - self needed) ifTrue: [^ #lost].
  ^ #pending.

"The longest remaining promise among the busy and starting refusals, 0 if none."
PBAttempt >> busyRemaining
  ^ rejects inject: 0 into: [:acc :e |
    ((e at: 2) = 'busy' or: [(e at: 2) = 'starting']) ifTrue: [acc max: (e at: 4)] ifFalse: [acc]].

"The committed roots the granters reported (the known ones, in arrival order), a fresh Array."
PBAttempt >> committedRoots
  ^ (grants collect: [:e | e at: 3]) reject: [:r | r isNil].

"{ root. certain } (CP 1.5 step 5, proto_db best_root and coordinator.py _close_attempt): root
 is the highest in root order of the granters' roots and anOwnRoot (the requester's accepted
 root, counted even when its own vote was refused; nil when it knows none or is a learner), nil
 when none is known; certain holds when a root is known, every granter knows a root and none is
 suspect, and the requester is not suspect (isSuspect). Two different roots with equal label
 and epoch are PBCorruptionError (PBRootOrder)."
PBAttempt >> bestRoot: anOwnRoot suspect: isSuspect
  | best |
  best := nil.
  grants do: [:e | best := PBRootOrder max: best with: (e at: 2)].
  best := PBRootOrder max: best with: anOwnRoot.
  ^ { best. (best notNil and: [isSuspect not and: [grants allSatisfy: [:e | (e at: 2) notNil and: [e at: 4]]]]) }.

PBAttempt >> printOn: aStream
  aStream nextPutAll: 'PBAttempt(term '; print: term; nextPutAll: ', '; print: self state; nextPut: $).

"=== PBLease ================================================================="

Object subclass: #PBLease instanceVariableNames: 'term validUntil root certain'.

"A won lease of aTerm, valid on the holder's clock before v (the request's send + belief, L5),
 with the phase-1 value aRoot (a PBLabeledRoot or nil) and aBoolean (it can be trusted without
 a recovery round)."
PBLease class >> term: aTerm validUntil: v root: aRoot certain: aBoolean
  ^ self basicNew _setTerm: aTerm validUntil: v root: aRoot certain: aBoolean.

PBLease >> _setTerm: aTerm validUntil: v root: aRoot certain: aBoolean
  "Runs once, on a fresh instance."
  term isNil ifFalse: [^ PBUserError signal: 'PBLease is immutable'].
  term := aTerm.
  validUntil := v.
  root := aRoot.
  certain := aBoolean.
  ^ self.

PBLease >> term
  ^ term.

PBLease >> validUntil
  ^ validUntil.

PBLease >> root
  ^ root.

PBLease >> isCertain
  ^ certain.

"Microseconds of validity left at now, 0 once expired."
PBLease >> remainingAt: now
  ^ 0 max: validUntil - now.

PBLease >> isValidAt: now
  ^ now < validUntil.

PBLease >> printOn: aStream
  aStream nextPutAll: self class name; nextPutAll: '(term '; print: term; nextPutAll: ', until '; print: validUntil; nextPut: $).

"=== PBPermission ============================================================"

PBLease subclass: #PBPermission instanceVariableNames: 'seq rid owner'.

"Permission number s of aTerm, issued by anOwner for the request rid r sent at aSent (this
 node's clock), valid for v microseconds from that send (the owner's valid: the owner issued it
 later, so it never outlasts the owner's lease here). aRoot is the base the owner sent; the base
 is certain only when known (H2 at DEPTH 0, where after is always nil)."
PBPermission class >> term: aTerm seq: s rid: r owner: anOwner root: aRoot certain: aBoolean sentAt: aSent valid: v
  ^ (self basicNew _setTerm: aTerm validUntil: aSent + v root: aRoot certain: (aBoolean and: [aRoot notNil]))
    _setSeq: s rid: r owner: anOwner.

PBPermission >> _setSeq: s rid: r owner: anOwner
  "Runs once, on a fresh instance."
  seq isNil ifFalse: [^ PBUserError signal: 'PBPermission is immutable'].
  seq := s.
  rid := r.
  owner := anOwner.
  ^ self.

PBPermission >> seq
  ^ seq.

PBPermission >> rid
  ^ rid.

PBPermission >> owner
  ^ owner.

"The pipelined predecessor: always nil at DEPTH 0 (Q3)."
PBPermission >> after
  ^ nil.
