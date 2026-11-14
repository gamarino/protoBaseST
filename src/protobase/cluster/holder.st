"-- cluster/holder.st: the base choice, the holder's replication, the commit point and the commit round --

The holder side of a commit round of proto_db's ClusterCoordinator (cluster/coordinator.py at
v2.0.0rc3: replicate over a storage shared by every node, the ack branch of _on_answer, and the
dispatcher's half of _learn_label) as rule methods of PBCoordinatorCore over the values of
lease.st, core.st, proposer.st, owner.st and this module, at DEPTH 0 (CC7: no gate, no store,
no proposal). Nothing here reads a clock: t is the node's clock (CC3).

  dispatchReplicateWanted:in:now: (proto_db replicate, CP 1.7 steps 6-9). A permission that is no
    longer valid, has less than sendReserve left (R121), or whose term is below the rejoin
    ballot of this node's acceptor (L14), sends nothing: the waiter gets #none
    (H7: nothing acceptable left the node, a retryable conflict). Otherwise
    replicate(term, rid, inc, root, committed, records, chunks, base, base_ranges, seq, pred,
    vs, copies, ranges) goes to every other voter (proto_db _send_voters), and the holder's own
    acceptance, when it is a voter, is decided by its own acceptor (PBToAcceptor of the same
    message, CC1), whose ack comes back as the step's vote. The message carries the root
    labelled with the permission's term, the committed root the acceptor last reported, no
    records and no chunks (the records are in the shared storage before the round replicates,
    L11), no base, the permission's seq, the root it was built on (pred), the voter-set
    fingerprint, copies { this node } and no ranges, as proto_db's shared-storage path.
    Counted replications.
  The commit point (H7). Each voter's ack is recorded once (receivedAck:, proto_db _on_answer:
    an ack of another incarnation is dropped and counted stale_replies, one of another term or
    request ignored, a learner's never counted, D54; ok adds the voter to the acks, a refusal
    adds it to the refusals unless it acked; the holder's own refusal is neither). The replication is decided once its own
    acceptance answered (proto_db decides it after the own append) and either a majority of
    the voters acked (the holder included), or more voters refused than a majority allows, or
    the permission's validity ended (its timer). It is #committed exactly when a majority acked
    and the permission is still valid when that is observed; anything else is #unknown, since
    the root left the node: counted replication_failures, the node suspect for the term (its
    acceptor too, PBSuspect). An own acceptance whose append failed ends it #unknown at once
    (proto_db: the own log write raises after the sends). A commit teaches the node's own
    acceptor the root as committed (PBLearnCommitted, accepted knowledge, appended #committed
    without a sync) and clears a suspicion the root's label answers.
  The done that follows (owner.st dispatchDoneReport:) is broadcast; every member's acceptor
    learns its committed root (acceptor.st acceptDone:).
  dispatchAcceptorDecided: (proposer.st) hands this module the own ack (_ownAck:in:now:effects:)
    and applies the label a step learnt (_learnt:in:): proto_db _learn_label, a suspicion of the
    dispatcher that the label answers is cleared and the hint rises. The dispatcher's
    suspicion and its acceptor's are the two halves of proto_db's single _suspect_term, so
    every observation of a root, made in the acceptor's step, clears both.

  The base choice (CP 1.6, proto_db transactions.py _lease_base, _phase_1_floor,
    _base_needs_commit, refound, _guard_error, and coordinator.py recover_root with the answer
    branch of _on_answer): leaseBase:waiter:in:now: (the rule of PBBaseWanted) settles the waiter
    with a PBBaseDecision (#ok, #stale or #unreachable) or an error value. A certain permit, or a
    base already bound under the permission, is the base. Otherwise a recovery round (query,
    ballot 0, to the other voters, for requestTimeout at most; recoveryDone:in:) ends at a
    majority of witnesses, this node counted when it is one, or waits for every other voter when
    asked (PBRecoverWanted every:waiter:, which runs a round alone). Fewer witnesses than a
    majority: PBConflictError. Else the highest accepted root among the witnesses is the
    result, their committed roots are learnt (not accepted, not logged), the hint rises to their
    labels and the suspicion held at the send is cleared (both halves, PBRecovered).
    phase1Floor: (R127) raises the base to the permission's root when that orders higher. With
    no root known anywhere, the shared storage's persisted root is read (PBReadPersisted) and a
    term below its label + refoundStep refounds (#stale, the hint raised). A committed root of a
    later term, or of this term above the base, makes it #stale; a base below the committed root
    this node knows reads the persisted root for the hard guard (PBCorruptionError naming the
    operator's remedy, or a refound from it). A base labelled above the term is #stale. A base
    other than the empty space that is not the committed root this node knows needs a commit
    first (R50) and is probed (PBProbeRoot); an unreadable one is #unreachable (R133). An #ok
    base is bound to its permission, and so is each root committed under it (proto_db
    bind_root), so a later round under the permission builds on the last committed root.
  The pred (proto_db replicate: lease.sent, else the lease root, which bind_root sets to the
    base): the holder keeps, per permission held, the base bound and the root last sent
    (PBHolder permits), and dispatchReplicateWanted: refuses a pred other than predFor:in:
    (PBValidationError): acceptors trust the pred, so a wrong one is never sent. The record is
    forgotten when the permission's done report is made (owner.st dispatchDoneReport:).

  The commit round (spec 5.6, proto_db transactions.py _run_round, _permit_round, _keep,
    _take_kept, _await_retries, _drop_kept): round:in:now:, a pure state machine over a
    PBRoundState, whose effects the shell performs and whose answers come back as events. One
    round at a time takes the whole queue under one permission; its base first (PBAskBase),
    re-committed when it needs a commit (its unchanged root, one PBReplicate); each PBRoundEntry
    builds on the previous root (stamp { term. epoch + 1 }), a conflict fails alone; before each
    build after the first the group bound (CC11, groupBoundAllows:now:) asks for sendReserve +
    the round's longest build, the rest back to the head of the queue; before any send
    mayReplicate:now: refuses less than sendReserve left (R121, the CC18 text) and a term below
    the rejoin ballot (L14), nothing sent, a retryable conflict. Outcomes as H7. A stale base
    requeues the round at the head; termRetries stale permissions in a row fail the queue
    (proto_db _TERM_RETRIES). Held retries (D-LIVE-2): a conflicted entry that will retry gets
    PBConflictError held:, and the permission is kept, max(min(retryHold, the time left),
    retryWait), until every held caller (PBRoundEntry caller) has queued its retry. PBReportDone
    ends each permission with its outcome.

Not here: the rejoin ballot itself (set by rejoining, Task 16), bounded replication, copies and
the gate (Phase D).

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
Import from: 'protobase/cluster/owner'.

"=== PBReplication ============================================================"

"One replication of a holder that is not decided yet (proto_db's replicate waiter): the waiter,
 the permission, the request id, the root, the voters that acked and those that refused, whether
 its own acceptance has not answered yet, and the token of its timer (at the permission's end)."
PBProposerValue subclass: #PBReplication.

PBReplication class >> fieldNames
  ^ #(#waiter #permission #rid #root #acks #nacks #ownPending #token).

PBReplication class >> waiter: aWaiter permission: aPermission rid: aRid root: aRoot ownPending: aBoolean token: aToken
  ^ self _from: (Dictionary new
    at: #waiter put: aWaiter; at: #permission put: aPermission; at: #rid put: aRid; at: #root put: aRoot;
    at: #acks put: #(); at: #nacks put: #(); at: #ownPending put: aBoolean; at: #token put: aToken; yourself).

PBReplication >> waiter
  ^ self _at: #waiter.

PBReplication >> permission
  ^ self _at: #permission.

PBReplication >> rid
  ^ self _at: #rid.

PBReplication >> root
  ^ self _at: #root.

"The voters that acknowledged, a fresh Array."
PBReplication >> acks
  ^ (self _at: #acks) copy.

"The voters that refused and did not acknowledge, a fresh Array."
PBReplication >> nacks
  ^ (self _at: #nacks) copy.

"Whether the holder's own acceptance has not answered yet."
PBReplication >> isOwnPending
  ^ self _at: #ownPending.

PBReplication >> token
  ^ self _at: #token.

"This replication with aVoter's answer: ok adds it to the acks and drops it from the refusals;
 a refusal adds it to the refusals unless it acked (proto_db _on_answer)."
PBReplication >> answered: aVoter ok: isOk
  | acks nacks |
  acks := self acks.
  nacks := self nacks.
  isOk
    ifTrue: [
      (acks includes: aVoter) ifFalse: [acks := acks copyWith: aVoter].
      nacks := nacks reject: [:v | v = aVoter]]
    ifFalse: [(acks includes: aVoter) ifFalse: [(nacks includes: aVoter) ifFalse: [nacks := nacks copyWith: aVoter]]].
  ^ self with: { #acks -> acks. #nacks -> nacks }.

PBReplication >> printOn: aStream
  aStream nextPutAll: 'PBReplication('; print: self rid; nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: self root); nextPut: $).

"=== PBCoordinatorCore: replicating =========================================="

"The replications of s not decided yet."
PBCoordinatorCore >> _replicationsIn: s
  ^ (self _holderIn: s) replications.

"s with aReplication replaced by another (nil: removed), by request id."
PBCoordinatorCore >> _replaceReplication: aReplication with: another in: s
  | h list |
  h := self _holderIn: s.
  list := h replications reject: [:r | r rid = aReplication rid].
  another notNil ifTrue: [list := list copyWith: another].
  ^ s with: { #holder -> (h with: { #replications -> list }) }.

"Nothing acceptable left the node (H7): the waiter of anEvent gets #none."
PBCoordinatorCore >> _sendNothing: anEvent in: s effects: fx
  ^ self _settle: anEvent waiter with: #none in: s effects: fx.

"L14 at the send (proto_db replicate reads _rejoin_ballot under its lock): whether aPermission's
 term is below the rejoin ballot of this node's acceptor (its last report). The commit round
 refuses earlier, with the reason (mayReplicate:now:); this repeats the check where the root
 leaves the node, so a ballot raised in between still sends nothing (#none)."
PBCoordinatorCore >> _belowRejoinBallot: aPermission in: s
  s acceptorView isNil ifTrue: [^ false].
  ^ aPermission term < s acceptorView rejoinBallot.

"The replicate message of aRoot built on aPred under aPermission (proto_db replicate's
 replication(), shared storage: no records, no chunks, no base, copies this node, no ranges)."
PBCoordinatorCore >> _replicate: aRoot pred: aPred permission: aPermission rid: aRid in: s
  | view |
  view := s acceptorView.
  ^ PBClusterMessage type: 'replicate' from: s config nodeId fields: {
    'term' -> aPermission term. 'rid' -> aRid. 'inc' -> s inc. 'root' -> (PBClusterMessage rootValue: aRoot).
    'committed' -> (view isNil ifTrue: [nil] ifFalse: [PBClusterMessage rootValue: view committed]).
    'records' -> #(). 'chunks' -> 0. 'base' -> nil. 'base_ranges' -> nil. 'seq' -> aPermission seq.
    'pred' -> (PBClusterMessage rootValue: aPred). 'vs' -> s config membership fingerprint.
    'copies' -> { s config nodeId }. 'ranges' -> nil }.

"proto_db replicate (CP 1.7 steps 6-9): the root to the other voters and to the own acceptor,
 or nothing when the permission ended or its time left is below the send reserve (R121)."
PBCoordinatorCore >> dispatchReplicateWanted: anEvent in: s now: t
  ^ self _step: [:fx | | p c rid msg own pair state rep |
    p := anEvent permission.
    c := s config.
    anEvent root label = p term ifFalse: [
      ^ PBValidationError signal: 'PBReplicateWanted: a root of term ' , p term printString , ' is labelled with it, not '
        , anEvent root label printString].
    (self _predAllows: anEvent in: s) ifFalse: [
      ^ PBValidationError signal: 'PBReplicateWanted: a root of ' , (PBCoreValue textOf: p) , ' is built on '
        , (PBCoreValue textOf: (self predFor: p in: s)) , ' (the base, else the root last sent under it), not on '
        , (PBCoreValue textOf: anEvent pred)].
    ((p isValidAt: t) and: [(p remainingAt: t) >= c sendReserve and: [(self _belowRejoinBallot: p in: s) not]])
      ifFalse: [self _sendNothing: anEvent in: s effects: fx]
      ifTrue: [
        rid := s nextRid.
        msg := self _replicate: anEvent root pred: anEvent pred permission: p rid: rid in: s.
        fx add: (PBCount stat: 'replications').
        self _sendVoters: msg in: s effects: fx.
        own := c membership isVoter: c nodeId.
        own ifTrue: [fx add: (PBToAcceptor event: (PBReceived message: msg))].
        pair := self _token: #replicate in: (s with: { #nextRid -> (rid + 1) }).
        fx add: (PBTimer after: (p remainingAt: t) token: pair last event: #replicate).
        rep := PBReplication waiter: anEvent waiter permission: p rid: rid root: anEvent root ownPending: own token: pair last.
        "proto_db lease.sent: the next root under the permission extends this one."
        state := self _replaceReplication: rep with: rep in: (self _sent: anEvent root under: p in: pair first).
        self _decideReplication: rep in: state now: t effects: fx]].

"proto_db replicate's wait: once its own acceptance answered, aReplication is decided by a
 majority of acks, by more refusals than a majority allows, or by the end of its permission;
 committed exactly when a majority acked within the permission (H7)."
PBCoordinatorCore >> _decideReplication: aReplication in: s now: t effects: fx
  | voters majority valid |
  aReplication isOwnPending ifTrue: [^ s].
  voters := s config membership voters size.
  majority := s config membership majority.
  valid := aReplication permission isValidAt: t.
  ((aReplication acks size >= majority) or: [(aReplication nacks size > (voters - majority)) or: [valid not]]) ifFalse: [^ s].
  ^ self _endReplication: aReplication committed: (self _commitPoint: aReplication majority: majority valid: valid) in: s effects: fx.

"The commit point (CP 1.7 step 9): a majority of the voters acknowledged, observed while the
 permission is valid."
PBCoordinatorCore >> _commitPoint: aReplication majority: aMajority valid: isValid
  ^ aReplication acks size >= aMajority and: [isValid].

"aReplication ends: committed (its root learnt committed by the own acceptor, a suspicion its
 label answers cleared, and the root bound as its permission's base: proto_db _permit_round's
 bind_root after _commit_base and after each successful replicate, so a later round under the
 permission builds on it), else unknown (the root left this node: counted, the node suspect for
 its term, its acceptor too)."
PBCoordinatorCore >> _endReplication: aReplication committed: isCommitted in: s effects: fx
  | state label |
  state := self _replaceReplication: aReplication with: nil in: s.
  label := aReplication root label.
  isCommitted ifTrue: [
    fx add: (PBToAcceptor event: (PBLearnCommitted root: aReplication root accept: true logged: true)).
    state := state with: { #suspectTerm -> (self _learnLabel: label clears: state suspectTerm) }.
    state := self _bindCommitted: aReplication permission root: aReplication root in: state.
    ^ self _settle: aReplication waiter with: #committed in: state effects: fx].
  fx add: (PBCount stat: 'replication_failures'); add: (PBToAcceptor event: (PBSuspect term: label)).
  state := state with: { #suspectTerm -> (state suspectTerm max: label) }.
  ^ self _settle: aReplication waiter with: #unknown in: state effects: fx.

"The replication whose request id is aRid, nil when none (decided, or never sent)."
PBCoordinatorCore >> _replication: aRid in: s
  ^ (self _replicationsIn: s) detect: [:r | r rid = aRid] ifNone: [nil].

"The ack aMessage from aVoter: recorded in the replication it answers (its request id and term),
 when its sender is a voter; then the replication is decided if it can be."
PBCoordinatorCore >> _onAck: aMessage in: s now: t effects: fx
  | rep h root state |
  rep := self _replication: (aMessage at: 'rid') in: s.
  (rep isNil or: [rep permission term ~= (aMessage at: 'term')]) ifTrue: [^ s].
  "The hint rises from any ack that answers this replication, a learner's too (proto_db
   _on_answer)."
  h := self _hintsIn: s.
  root := PBClusterMessage rootFrom: (aMessage at: 'root').
  state := root isNil ifTrue: [s] ifFalse: [s with: { #hints -> (h with: { #hint -> (h hint max: root label) }) }].
  "Only a voter's answer decides the root (D54)."
  (self _countsAck: aMessage in: state) ifFalse: [^ state].
  rep := rep answered: aMessage from ok: (aMessage at: 'ok').
  ^ self _decideReplication: rep in: (self _replaceReplication: rep with: rep in: state) now: t effects: fx.

"Whether the ack aMessage is a voter's (proto_db _on_answer: only a voter's answer decides the
 root, D54)."
PBCoordinatorCore >> _countsAck: aMessage in: s
  ^ s config membership isVoter: aMessage from.

"proto_db _on_answer, an ack: one of another incarnation of this node is dropped (its request ids
 restarted)."
PBCoordinatorCore >> receivedAck: anEvent in: s now: t
  ^ self _step: [:fx |
    (self _isStale: anEvent message in: s)
      ifTrue: [fx add: (PBCount stat: 'stale_replies'). s]
      ifFalse: [self _onAck: anEvent message in: s now: t effects: fx]].

"The own acceptor answered the own replication (CC1): an ok is recorded as a voter's ack, a
 refusal is not recorded (proto_db replicate adds only an own acceptance to the acks), and the
 replication may be decided now."
PBCoordinatorCore >> _ownAck: anAck in: s now: t effects: fx
  | rep state |
  rep := self _replication: (anAck at: 'rid') in: s.
  rep isNil ifTrue: [^ s].
  rep := rep with: { #ownPending -> false }.
  state := self _replaceReplication: rep with: rep in: s.
  "proto_db replicate: an own refusal is neither an ack nor a refusal of the waiter."
  (anAck at: 'ok') ifFalse: [^ self _decideReplication: rep in: state now: t effects: fx].
  ^ self _onAck: anAck in: state now: t effects: fx.

"The own acceptance of a replication could not be made durable (the tier failed, R57): the root
 left this node already, so its outcome is unknown (proto_db: the own log write raises after the
 sends)."
PBCoordinatorCore >> _ownAckFailed: anAck in: s now: t effects: fx
  | rep |
  rep := self _replication: (anAck at: 'rid') in: s.
  rep isNil ifTrue: [^ s].
  ^ self _endReplication: rep committed: false in: s effects: fx.

"The timer of a replication: its permission ended (re-armed when it came early)."
PBCoordinatorCore >> _replicationTimer: anEvent in: s now: t effects: fx
  | rep |
  rep := (self _replicationsIn: s) detect: [:r | r token = anEvent token] ifNone: [nil].
  rep isNil ifTrue: [^ s].
  "Defensive, as _askTimer: re-arms: a timer that came before the permission's end (a shell
   whose timer source is not the node's clock) is set again for the time left, so the
   replication is never stranded undecided."
  (rep permission isValidAt: t) ifTrue: [
    fx add: (PBTimer after: (rep permission remainingAt: t) token: rep token event: #replicate).
    ^ s].
  ^ self _decideReplication: rep in: s now: t effects: fx.

"proto_db _learn_label on the dispatcher's half of the suspicion: a root labelled aLabel was
 observed by the acceptor's step; a suspicion it answers is cleared and the hint rises."
PBCoordinatorCore >> _learnt: aLabel in: s
  | h |
  aLabel = 0 ifTrue: [^ s].
  h := self _hintsIn: s.
  ^ s with: { #suspectTerm -> (self _learnLabel: aLabel clears: s suspectTerm). #hints -> (h with: { #hint -> (h hint max: aLabel) }) }.

"A replicate proves its term was won (proto_db _apply_replicate _note_owner): the owner hint,
 then the acceptor lane."
PBCoordinatorCore >> receivedReplicate: anEvent in: s now: t
  ^ self _step: [:fx |
    fx add: (PBToAcceptor event: anEvent).
    self _poke: (s with: { #hints -> (self _noteOwner: (anEvent message at: 'term') in: (self _hintsIn: s) of: s) })
      now: t effects: fx].

"=== The base choice: values, events and effects ==============================="

"--- PBBaseDecision ---"

Object subclass: #PBBaseDecision instanceVariableNames: 'base needsCommit outcome'.

"The base of a commit round under a permission (CP 1.6, proto_db _lease_base and the start of
 _permit_round): aRoot, the PBLabeledRoot the round builds on (for #stale or #unreachable the
 base that was found, or nil); aBoolean, whether it must be committed first (R50, proto_db
 _base_needs_commit and _commit_base: it is not the committed root this node knows, so the
 round replicates an unchanged root on it before building); anOutcome, #ok (build on it),
 #stale (the base orders at or above the permission's term, or a committed root of this term or
 a later one supersedes it: nothing is sent, the round requeues its commits and the permission
 ends unknown, D50) or #unreachable (it must be committed first and the shared storage cannot
 read its SpaceRoot: nothing is sent, the commits get a retryable conflict and the permission
 ends unknown, so its owner abandons the term, R133)."
PBBaseDecision class >> base: aRoot needsCommit: aBoolean outcome: anOutcome
  (#(#ok #stale #unreachable) includes: anOutcome) ifFalse: [
    ^ PBValidationError signal: 'PBBaseDecision: an outcome is #ok, #stale or #unreachable, not ' , anOutcome printString].
  (aRoot isNil or: [aRoot isClassObject not and: [aRoot class == PBLabeledRoot]]) ifFalse: [
    ^ PBValidationError signal: 'PBBaseDecision: a base is a PBLabeledRoot or nil, not ' , aRoot printString].
  (anOutcome = #ok and: [aRoot isNil]) ifTrue: [^ PBValidationError signal: 'PBBaseDecision: an #ok decision names its base'].
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBBaseDecision: needsCommit is a Boolean, not ' , aBoolean printString].
  ^ self basicNew _setBase: aRoot needsCommit: aBoolean outcome: anOutcome asSymbol.

PBBaseDecision >> _setBase: aRoot needsCommit: aBoolean outcome: anOutcome
  "Runs once, on a fresh instance."
  outcome isNil ifFalse: [^ PBUserError signal: 'PBBaseDecision is immutable'].
  base := aRoot.
  needsCommit := aBoolean.
  outcome := anOutcome.
  ^ self.

PBBaseDecision >> base
  ^ base.

PBBaseDecision >> needsCommit
  ^ needsCommit.

PBBaseDecision >> outcome
  ^ outcome.

PBBaseDecision >> isOk
  ^ outcome = #ok.

PBBaseDecision >> printOn: aStream
  aStream nextPutAll: 'PBBaseDecision('; nextPutAll: outcome; nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: base);
    nextPutAll: (needsCommit ifTrue: [', commit first'] ifFalse: ['']); nextPut: $).

"--- PBBaseChoice ---"

"A base choice or a recovery round in progress (proto_db _lease_base and recover_root, which
 wait on a thread; here a value of the holder): the waiter; the permission (nil for a recovery
 asked by PBRecoverWanted); every (wait for every other voter); the phase (#recovery: its query
 is out; #refound or #guard: the persisted root is being read for a refound or for the hard
 guard; #probe: the base's SpaceRoot is being probed); the request id of its query; the token
 of its timer or storage read; the suspicion the node held when the query was sent; the
 answers ({ sender. accepted root. committed root. state } each, the roots PBLabeledRoots or
 nil); the committed roots learnt so far (their highest, nil when none: proto_db's _committed
 includes them at once); the base found so far (a PBLabeledRoot or nil)."
PBProposerValue subclass: #PBBaseChoice.

PBBaseChoice class >> fieldNames
  ^ #(#waiter #permission #every #phase #rid #token #suspected #answers #learnt #current).

PBBaseChoice class >> waiter: aWaiter permission: aPermissionOrNil every: aBoolean
  ^ self _from: (Dictionary new
    at: #waiter put: aWaiter; at: #permission put: aPermissionOrNil; at: #every put: aBoolean; at: #phase put: #start;
    at: #rid put: 0; at: #token put: nil; at: #suspected put: 0; at: #answers put: #(); at: #learnt put: nil;
    at: #current put: nil; yourself).

PBBaseChoice >> waiter
  ^ self _at: #waiter.

"The permission whose base is chosen, nil for a recovery asked on its own."
PBBaseChoice >> permission
  ^ self _at: #permission.

PBBaseChoice >> every
  ^ self _at: #every.

PBBaseChoice >> phase
  ^ self _at: #phase.

PBBaseChoice >> rid
  ^ self _at: #rid.

PBBaseChoice >> token
  ^ self _at: #token.

PBBaseChoice >> suspected
  ^ self _at: #suspected.

"{ sender. accepted. committed. state } of every answer, a fresh Array."
PBBaseChoice >> answers
  ^ (self _at: #answers) collect: [:a | a copy].

PBBaseChoice >> learnt
  ^ self _at: #learnt.

PBBaseChoice >> current
  ^ self _at: #current.

"This choice with aSender's answer (it replaces an earlier one of that sender, proto_db's
 waiter.answers[sender])."
PBBaseChoice >> answered: aSender accepted: anAccepted committed: aCommitted state: aState
  ^ self with: { #answers -> (((self _at: #answers) reject: [:a | a first = aSender])
    copyWith: { aSender. anAccepted. aCommitted. aState }) }.

PBBaseChoice >> printOn: aStream
  aStream nextPutAll: 'PBBaseChoice('; nextPutAll: self phase; nextPutAll: ', '; nextPutAll: (PBCoreValue textOf: self permission); nextPut: $).

"--- PBRecoverWanted ---"

PBCoreEvent subclass: #PBRecoverWanted instanceVariableNames: 'every waiter'.

"A recovery round (proto_db recover_root(every)): aWaiter is settled with { known. root } (the
 highest root accepted among the witnesses' answers and this node's, nil and false when none),
 or with the PBConflictError of a round that no majority of witnesses answered within
 requestTimeout. With aBoolean the round waits for every other voter instead of ending at a
 majority of witnesses (proto_db open_database, re-review 2 M6)."
PBRecoverWanted class >> every: aBoolean waiter: aWaiter
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBRecoverWanted: every is a Boolean, not ' , aBoolean printString].
  ^ self basicNew _setEvery: aBoolean waiter: (self _present: aWaiter named: 'waiter').

PBRecoverWanted >> _setEvery: aBoolean waiter: aWaiter
  "Runs once, on a fresh instance."
  waiter isNil ifFalse: [^ PBUserError signal: 'PBRecoverWanted is immutable'].
  every := aBoolean.
  waiter := aWaiter.
  ^ self.

PBRecoverWanted >> every
  ^ every.

PBRecoverWanted >> waiter
  ^ waiter.

PBRecoverWanted >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchRecoverWanted: self in: aNodeState now: t.

PBRecoverWanted >> printOn: aStream
  aStream nextPutAll: 'PBRecoverWanted('; nextPutAll: (every ifTrue: ['every, '] ifFalse: ['']);
    nextPutAll: (PBCoreValue textOf: waiter); nextPut: $).

"--- PBStorageRead ---"

PBCoreEvent subclass: #PBStorageRead instanceVariableNames: 'token root failure'.

"The shell read the shared storage's persisted root for the PBReadPersisted aToken: aRoot (a
 PBLabeledRoot, nil when none is persisted), or the read failed with aFailure (an Exception,
 not signalled; aRoot is then ignored)."
PBStorageRead class >> token: aToken root: aRoot failure: aFailure
  (aRoot isNil or: [aRoot isClassObject not and: [aRoot class == PBLabeledRoot]]) ifFalse: [
    ^ PBValidationError signal: 'PBStorageRead: a root is a PBLabeledRoot or nil, not ' , aRoot printString].
  (aFailure isNil or: [aFailure isKindOf: Exception]) ifFalse: [
    ^ PBValidationError signal: 'PBStorageRead: a failure is an Exception or nil, not ' , aFailure printString].
  ^ self basicNew _setToken: (self _present: aToken named: 'token') root: aRoot failure: aFailure.

PBStorageRead >> _setToken: aToken root: aRoot failure: aFailure
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBStorageRead is immutable'].
  token := aToken.
  root := aRoot.
  failure := aFailure.
  ^ self.

PBStorageRead >> token
  ^ token.

PBStorageRead >> root
  ^ root.

PBStorageRead >> failure
  ^ failure.

PBStorageRead >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchStorageRead: self in: aNodeState now: t.

PBStorageRead >> printOn: aStream
  aStream nextPutAll: 'PBStorageRead('; nextPutAll: (PBCoreValue textOf: token); nextPutAll: ', ';
    nextPutAll: (failure isNil ifTrue: [PBCoreValue textOf: root] ifFalse: ['failed']); nextPut: $).

"--- PBRootProbed ---"

PBCoreEvent subclass: #PBRootProbed instanceVariableNames: 'token readable'.

"The shell probed the root of the PBProbeRoot aToken: aBoolean, whether the shared storage can
 read its SpaceRoot."
PBRootProbed class >> token: aToken readable: aBoolean
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBRootProbed: readable is a Boolean, not ' , aBoolean printString].
  ^ self basicNew _setToken: (self _present: aToken named: 'token') readable: aBoolean.

PBRootProbed >> _setToken: aToken readable: aBoolean
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBRootProbed is immutable'].
  token := aToken.
  readable := aBoolean.
  ^ self.

PBRootProbed >> token
  ^ token.

PBRootProbed >> isReadable
  ^ readable.

PBRootProbed >> dispatchWith: aCore in: aNodeState now: t
  ^ aCore dispatchRootProbed: self in: aNodeState now: t.

PBRootProbed >> printOn: aStream
  aStream nextPutAll: 'PBRootProbed('; nextPutAll: (PBCoreValue textOf: token); nextPutAll: ', ';
    nextPutAll: (readable ifTrue: ['readable'] ifFalse: ['unreadable']); nextPut: $).

"--- PBRecovered (an acceptor event) ---"

PBCoreEvent subclass: #PBRecovered instanceVariableNames: 'suspected'.

"A recovery round sent while this node's suspicion was aTerm (an Integer > 0) ended with a
 majority of witnesses: the acceptor's half of the suspicion is cleared when it is at most
 aTerm (proto_db recover_root: 'if self._suspect_term <= suspected: self._suspect_term = 0')."
PBRecovered class >> suspected: aTerm
  (aTerm isInteger and: [aTerm > 0]) ifFalse: [
    ^ PBValidationError signal: 'PBRecovered: a term is an Integer > 0, not ' , aTerm printString].
  ^ self basicNew _setSuspected: aTerm.

PBRecovered class >> isAcceptorEvent
  ^ true.

PBRecovered >> _setSuspected: aTerm
  "Runs once, on a fresh instance."
  suspected isNil ifFalse: [^ PBUserError signal: 'PBRecovered is immutable'].
  suspected := aTerm.
  ^ self.

PBRecovered >> suspected
  ^ suspected.

PBRecovered >> acceptWith: aCore in: anAcceptorState now: t
  ^ aCore acceptRecovered: self in: anAcceptorState now: t.

PBRecovered >> printOn: aStream
  aStream nextPutAll: 'PBRecovered('; print: suspected; nextPut: $).

"--- PBReadPersisted, PBProbeRoot (effects) ---"

PBEffect subclass: #PBReadPersisted instanceVariableNames: 'token'.

"Read the shared storage's persisted root (proto_db tier.read_persisted) and hand the dispatcher
 PBStorageRead token: aToken root: failure:."
PBReadPersisted class >> token: aToken
  ^ self basicNew _setToken: (self _present: aToken named: 'token').

PBReadPersisted >> _setToken: aToken
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBReadPersisted is immutable'].
  token := aToken.
  ^ self.

PBReadPersisted >> token
  ^ token.

PBReadPersisted >> applyTo: aShell
  ^ aShell applyReadPersisted: self.

PBReadPersisted >> printOn: aStream
  aStream nextPutAll: 'PBReadPersisted('; nextPutAll: (PBCoreValue textOf: token); nextPut: $).

PBEffect subclass: #PBProbeRoot instanceVariableNames: 'root token'.

"Probe whether the shared storage can read the SpaceRoot of aRoot (a PBLabeledRoot of a record)
 and hand the dispatcher PBRootProbed token: aToken readable:."
PBProbeRoot class >> root: aRoot token: aToken
  ((aRoot isClassObject not and: [aRoot class == PBLabeledRoot]) and: [aRoot record notNil]) ifFalse: [
    ^ PBValidationError signal: 'PBProbeRoot: a root is a PBLabeledRoot of a record, not ' , aRoot printString].
  ^ self basicNew _setRoot: aRoot token: (self _present: aToken named: 'token').

PBProbeRoot >> _setRoot: aRoot token: aToken
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBProbeRoot is immutable'].
  root := aRoot.
  token := aToken.
  ^ self.

PBProbeRoot >> root
  ^ root.

PBProbeRoot >> token
  ^ token.

PBProbeRoot >> applyTo: aShell
  ^ aShell applyProbeRoot: self.

PBProbeRoot >> printOn: aStream
  aStream nextPutAll: 'PBProbeRoot('; nextPutAll: (PBCoreValue textOf: root); nextPut: $).

"=== PBCoordinatorCore: what the holder bound and sent under a permission ======"

"The record { { term. seq }. bound. sent. committed } of aPermission in s, nil when none: the base
 bound under it, the root last sent under it and the root last committed under it (each a
 PBLabeledRoot or nil)."
PBCoordinatorCore >> _permitRecord: aPermission in: s
  | key |
  key := { aPermission term. aPermission seq }.
  ^ (self _holderIn: s) permits detect: [:e | e first = key] ifNone: [nil].

"Field n (2 bound, 3 sent, 4 committed) of aPermission's record in s, nil when none."
PBCoordinatorCore >> _permit: aPermission field: n in: s
  | e |
  e := self _permitRecord: aPermission in: s.
  ^ e isNil ifTrue: [nil] ifFalse: [e at: n].

"s with the record of aPermission replaced by { key. aBound. aSent. aCommitted }; at most
 permitsSeenLimit records are kept (the oldest go first)."
PBCoordinatorCore >> _permit: aPermission bound: aBound sent: aSent committed: aCommitted in: s
  | h key list |
  h := self _holderIn: s.
  key := { aPermission term. aPermission seq }.
  list := (h permits reject: [:e | e first = key]) copyWith: { key. aBound. aSent. aCommitted }.
  list size > PBHolder permitsSeenLimit ifTrue: [list := list copyFrom: list size - PBHolder permitsSeenLimit + 1 to: list size].
  ^ s with: { #holder -> (h with: { #permits -> list }) }.

"s with aRoot bound as the base of aPermission (proto_db _permit_round: permission.bind_root,
 which also makes the base certain for a later round under it); the rest is kept."
PBCoordinatorCore >> _bind: aPermission base: aRoot in: s
  ^ self _permit: aPermission bound: aRoot sent: (self _permit: aPermission field: 3 in: s)
    committed: (self _permit: aPermission field: 4 in: s) in: s.

"s with aRoot, committed under aPermission, bound as its base and recorded as committed under it
 (proto_db _permit_round: bind_root after _commit_base and after each successful replicate; the
 commit is this node's committed knowledge, which a later choice under the permission reads
 before the acceptor reports it)."
PBCoordinatorCore >> _bindCommitted: aPermission root: aRoot in: s
  ^ self _permit: aPermission bound: aRoot sent: (self _permit: aPermission field: 3 in: s) committed: aRoot in: s.

"s with aRoot recorded as the root last sent under aPermission (proto_db replicate, lease.sent =
 (label, root) at the send; nothing is recorded when nothing acceptable left the node)."
PBCoordinatorCore >> _sent: aRoot under: aPermission in: s
  ^ self _permit: aPermission bound: (self _permit: aPermission field: 2 in: s) sent: aRoot
    committed: (self _permit: aPermission field: 4 in: s) in: s.

"s without the record of aPermission (it ended: proto_db finish)."
PBCoordinatorCore >> _forgetPermit: aPermission in: s
  | h key |
  s holder isNil ifTrue: [^ s].
  h := s holder.
  key := { aPermission term. aPermission seq }.
  (h permits anySatisfy: [:e | e first = key]) ifFalse: [^ s].
  ^ s with: { #holder -> (h with: { #permits -> (h permits reject: [:e | e first = key]) }) }.

"The root aPermission's base is: the base bound under it, else the root its permit carried."
PBCoordinatorCore >> _rootOf: aPermission in: s
  | e |
  e := self _permitRecord: aPermission in: s.
  ^ (e notNil and: [(e at: 2) notNil]) ifTrue: [e at: 2] ifFalse: [aPermission root].

"Whether aPermission's base needs no recovery round: a base bound under it, or a certain permit
 (proto_db lease.root_certain, which bind_root sets)."
PBCoordinatorCore >> _isCertain: aPermission in: s
  | e |
  e := self _permitRecord: aPermission in: s.
  ^ (e notNil and: [(e at: 2) notNil]) or: [aPermission isCertain].

"The root the next root under aPermission must be built on (proto_db replicate: lease.sent, else
 (lease.root_term, lease.root)): the root last sent under it, else its base (the empty space
 labelled 0 when the permit carried none)."
PBCoordinatorCore >> predFor: aPermission in: s
  | e root |
  e := self _permitRecord: aPermission in: s.
  (e notNil and: [(e at: 3) notNil]) ifTrue: [^ e at: 3].
  root := self _rootOf: aPermission in: s.
  ^ root isNil ifTrue: [PBLabeledRoot label: 0 record: nil] ifFalse: [root].

"Whether the PBReplicateWanted anEvent names the pred its permission's commit path must use (the
 Task 13 safety obligation): acceptors trust the pred (V2' cannot detect a pred that lies about
 the build base), so a wrong one is refused here, not sent."
PBCoordinatorCore >> _predAllows: anEvent in: s
  ^ anEvent pred key = (self predFor: anEvent permission in: s) key.

"=== PBCoordinatorCore: the base choice ======================================="

"The base choices of s in progress."
PBCoordinatorCore >> _choicesIn: s
  ^ (self _holderIn: s) choices.

"s with aChoice recorded (replacing the one of its waiter)."
PBCoordinatorCore >> _replaceChoice: aChoice in: s
  | h |
  h := self _holderIn: s.
  ^ s with: { #holder -> (h with: { #choices -> ((h choices reject: [:c | c waiter = aChoice waiter]) copyWith: aChoice) }) }.

"s without aChoice (the one of its waiter)."
PBCoordinatorCore >> _removeChoice: aChoice in: s
  | h |
  h := self _holderIn: s.
  ^ s with: { #holder -> (h with: { #choices -> (h choices reject: [:c | c waiter = aChoice waiter]) }) }.

"The choice of s waiting in one of somePhases for aToken, nil when none."
PBCoordinatorCore >> _choiceWithToken: aToken phases: somePhases in: s
  ^ (self _choicesIn: s) detect: [:c | c token = aToken and: [somePhases includes: c phase]] ifNone: [nil].

"Whether this node's own answers are a witness's (proto_db _witness_state = 'ok'), from the
 acceptor's last report."
PBCoordinatorCore >> _ownWitness: s
  ^ s acceptorView notNil and: [(self _witnessStateIn: s acceptorView) = 'ok'].

"The newest root this node knows committed (proto_db committed_root) while aChoice runs: the
 acceptor's last report or a root aChoice learnt, the higher."
PBCoordinatorCore >> _committedFor: aChoice in: s
  ^ PBRootOrder max: (s acceptorView isNil ifTrue: [nil] ifFalse: [s acceptorView committed]) with: aChoice learnt.

"Whether two records (PBRootRecords, or nil: the empty space) are the same (proto_db compares
 RootRecord tuples)."
PBCoordinatorCore >> _sameRecord: aRecord as: another
  (aRecord isNil or: [another isNil]) ifTrue: [^ aRecord isNil and: [another isNil]].
  ^ aRecord version = another version and: [aRecord segment = another segment
    and: [aRecord offset = another offset and: [aRecord epoch = another epoch]]].

"proto_db _phase_1_floor (R127): whether aRoot, an uncertain lease's phase-1 value (the
 permission's root: the owner's phase-1 value or a root it knew committed later), bounds the
 base from below. The base of the first root of a term must extend every root chosen in a lower
 term, since the ballot rule alone lets every voter accept that first root over an older one;
 each granter promised the term before it reported its accepted root, so the phase-1 value
 orders at or above every chosen root of a lower term, while a recovery answer promises nothing
 (ballot 0) and may predate a root accepted afterwards (re-review 2 of 8.3n, C1). False when the
 lease knows no root (proto_db: lease.root None and root_term 0, which covers the empty space
 labelled 0): the recovery round or the persisted root decides (D46)."
PBCoordinatorCore >> phase1Floor: aRoot
  ^ aRoot notNil and: [aRoot record notNil or: [aRoot label > 0]].

"proto_db _lease_base: the base of a commit round under aPermission (CP 1.6), as a PBStep ending
 in PBSettle of aWaiter with a PBBaseDecision, or with an error: the PBConflictError of a
 recovery round that no majority of witnesses answered in time (retryable: the permission ends
 'none', as proto_db's recover_root raising), the PBCorruptionError of the hard guard, or the
 failure of a persisted-root read the refound needed. In order: (1) a certain permit or a base
 bound under the permission: its root; (2) else a recovery round (recoveryDone:in:); (3) the
 higher of the permission's root and the recovery result when phase1Floor: (R127); (4) nothing
 known anywhere: refound from the persisted root (PBReadPersisted), the terms raised by
 refoundStep; (5) a committed root of a later term, or of this term above the base, supersedes
 it: #stale; (6) the hard guard: never below the committed root this node knows (else refound
 from a persisted root at or above it, or PBCorruptionError naming forceRejoin); a base labelled
 above the term is #stale; (7) needsCommit when the base is not the committed root this node
 knows (R50); (8) such a base whose SpaceRoot the shared storage cannot read (PBProbeRoot) is
 #unreachable (R133). An #ok base is bound to the permission (predFor:in:)."
PBCoordinatorCore >> leaseBase: aPermission waiter: aWaiter in: s now: t
  ^ self _step: [:fx | | choice |
    "A root committed under the permission is committed knowledge already (proto_db's shared
     _committed), though the acceptor may not have reported it yet."
    choice := (PBBaseChoice waiter: aWaiter permission: aPermission every: false)
      with: { #learnt -> (self _permit: aPermission field: 4 in: s) }.
    (self _isCertain: aPermission in: s)
      ifTrue: [self _committedChecks: (choice with: { #current -> (self _rootOf: aPermission in: s) }) in: s now: t effects: fx]
      ifFalse: [self _recover: choice in: s now: t effects: fx]].

PBCoordinatorCore >> dispatchBaseWanted: anEvent in: s now: t
  ^ self leaseBase: anEvent permission waiter: anEvent waiter in: s now: t.

"proto_db recover_root(every), asked on its own."
PBCoordinatorCore >> dispatchRecoverWanted: anEvent in: s now: t
  ^ self _step: [:fx |
    self _recover: (PBBaseChoice waiter: anEvent waiter permission: nil every: anEvent every) in: s now: t effects: fx].

"proto_db recover_root: query(rid, inc, ballot 0, vs) to every other voter, answered by their
 acceptors (acceptQuery:in:now:), awaited for requestTimeout at most."
PBCoordinatorCore >> _recover: aChoice in: s now: t effects: fx
  | rid pair choice state |
  rid := s nextRid.
  pair := self _token: #recovery in: (s with: { #nextRid -> (rid + 1) }).
  self _sendVoters: (PBClusterMessage type: 'query' from: s config nodeId fields: {
    'rid' -> rid. 'inc' -> s inc. 'ballot' -> 0. 'vs' -> s config membership fingerprint }) in: s effects: fx.
  fx add: (PBTimer after: s config requestTimeout token: pair last event: #recovery).
  choice := aChoice with: { #phase -> #recovery. #rid -> rid. #token -> pair last. #suspected -> (self _suspectIn: s) }.
  state := self _replaceChoice: choice in: pair first.
  (self recoveryDone: choice in: state) ifTrue: [^ self _recovered: choice in: state now: t effects: fx].
  ^ state.

"Whether the recovery round aChoice ends now (proto_db recover_root's settled): every other voter
 answered; or, unless it waits for every voter, a majority of the voters are witnesses that
 answered, this node counted when it is one (D46, Task 8.3n fix round 3: waiting for every
 voter made each round last requestTimeout while one was down)."
PBCoordinatorCore >> recoveryDone: aChoice in: s
  | ok |
  aChoice answers size >= (s config membership voters reject: [:v | v = s config nodeId]) size ifTrue: [^ true].
  aChoice every ifTrue: [^ false].
  ok := (aChoice answers select: [:a | (a at: 4) = 'ok']) size.
  ^ ok + ((self _ownWitness: s) ifTrue: [1] ifFalse: [0]) >= s config membership majority.

"proto_db _on_answer, an answer: one of another incarnation is dropped (stale_replies); one to a
 recovery round in progress is recorded (an answer replaces its sender's earlier one), and the
 round may end."
PBCoordinatorCore >> receivedAnswer: anEvent in: s now: t
  ^ self _step: [:fx | | m choice state |
    m := anEvent message.
    (self _isStale: m in: s)
      ifTrue: [fx add: (PBCount stat: 'stale_replies'). s]
      ifFalse: [
        choice := (self _choicesIn: s) detect: [:c | c phase = #recovery and: [c rid = (m at: 'rid')]] ifNone: [nil].
        choice isNil
          ifTrue: [s]
          ifFalse: [
            choice := choice answered: m from accepted: (PBClusterMessage rootFrom: (m at: 'root'))
              committed: (PBClusterMessage rootFrom: (m at: 'committed')) state: (m at: 'state').
            state := self _replaceChoice: choice in: s.
            (self recoveryDone: choice in: state)
              ifTrue: [self _recovered: choice in: state now: t effects: fx]
              ifFalse: [state]]]].

"The timer of a recovery round: requestTimeout passed, it ends with the answers it has."
PBCoordinatorCore >> _recoveryTimer: anEvent in: s now: t effects: fx
  | choice |
  choice := self _choiceWithToken: anEvent token phases: #(#recovery) in: s.
  choice isNil ifTrue: [^ s].
  ^ self _recovered: choice in: s now: t effects: fx.

"The recovery round aChoice ended (proto_db recover_root after its wait). Counted recoveries.
 Fewer witnesses than a majority (this node counted when it is one): PBConflictError. Else the
 result is the highest accepted root among the witnesses' answers and this node's own; their
 committed roots are learnt (committed knowledge only, accept=False: a peer's may be the
 persisted root), the hint rises to every answer's accepted label, and the suspicion held when
 the query was sent is cleared (both halves). A plain recovery settles { known. root }; a base
 choice goes on (_afterRecovery:)."
PBCoordinatorCore >> _recovered: aChoice in: s now: t effects: fx
  | c answers own needed best h learnt state |
  c := s config.
  state := self _removeChoice: aChoice in: s.
  fx add: (PBCount stat: 'recoveries').
  answers := aChoice answers select: [:a | (a at: 4) = 'ok'].
  own := self _ownWitness: s.
  needed := own ifTrue: [c membership majority - 1] ifFalse: [c membership majority].
  answers size < needed ifTrue: [
    ^ self _settle: aChoice waiter with: (PBConflictError new messageText: 'Node ' , c nodeId , ': only '
      , (answers size + (own ifTrue: [1] ifFalse: [0])) printString , ' of the ' , c membership majority printString
      , ' witnesses needed answered the recovery query'; yourself) in: state effects: fx].
  best := own ifTrue: [s acceptorView accepted] ifFalse: [nil].
  h := self _hintsIn: state.
  learnt := aChoice learnt.
  answers do: [:a | | accepted committed |
    accepted := a at: 2.
    committed := a at: 3.
    committed notNil ifTrue: [
      fx add: (PBToAcceptor event: (PBLearnCommitted root: committed accept: false logged: false)).
      learnt := PBRootOrder max: learnt with: committed].
    h := h with: { #hint -> (h hint max: (accepted isNil ifTrue: [0] ifFalse: [accepted label])) }.
    (accepted notNil and: [(PBRootOrder compare: accepted with: best) > 0]) ifTrue: [best := accepted]].
  state := state with: { #hints -> h }.
  state suspectTerm <= aChoice suspected ifTrue: [state := state with: { #suspectTerm -> 0 }].
  aChoice suspected > 0 ifTrue: [fx add: (PBToAcceptor event: (PBRecovered suspected: aChoice suspected))].
  aChoice permission isNil ifTrue: [^ self _settle: aChoice waiter with: { best notNil. best } in: state effects: fx].
  ^ self _afterRecovery: (aChoice with: { #learnt -> learnt. #current -> best }) in: state now: t effects: fx.

"proto_db _lease_base after recover_root: the phase-1 floor (phase1Floor:, R127) raises the
 recovery result to the permission's root when that orders higher, or stands for it when the
 round knew no root; with no root known anywhere, the persisted root is read for a refound."
PBCoordinatorCore >> _afterRecovery: aChoice in: s now: t effects: fx
  | root current |
  root := self _rootOf: aChoice permission in: s.
  current := aChoice current.
  ((self phase1Floor: root) and: [current isNil or: [(PBRootOrder compare: root with: current) > 0]]) ifTrue: [
    current := root].
  current isNil ifTrue: [^ self _readPersisted: (aChoice with: { #phase -> #refound }) in: s effects: fx].
  ^ self _committedChecks: (aChoice with: { #current -> current }) in: s now: t effects: fx.

"aChoice waits for the persisted root (PBReadPersisted)."
PBCoordinatorCore >> _readPersisted: aChoice in: s effects: fx
  | pair |
  pair := self _token: #base in: s.
  fx add: (PBReadPersisted token: pair last).
  ^ self _replaceChoice: (aChoice with: { #token -> pair last }) in: pair first.

"The shell read the persisted root for a base choice."
PBCoordinatorCore >> dispatchStorageRead: anEvent in: s now: t
  ^ self _step: [:fx | | choice |
    choice := self _choiceWithToken: anEvent token phases: #(#refound #guard) in: s.
    choice isNil
      ifTrue: [s]
      ifFalse: [self _persistedRead: anEvent for: choice in: (self _removeChoice: choice in: s) now: t effects: fx]].

"proto_db _lease_base on the persisted root. For a refound (nothing known): a failed read ends
 the choice with its failure; no persisted root is the empty space labelled 0. For the hard
 guard: a failed read, no persisted root, or one below the committed root this node knows is
 the guard's PBCorruptionError. Else the persisted root is learnt committed (not accepted:
 a granting majority that knows nothing newer must refound), counted storage_root_reads, and is
 the base: a term not above its label by refoundStep refounds (#stale); a refound base then
 passes the committed checks, a guard's goes on to its last checks."
PBCoordinatorCore >> _persistedRead: anEvent for: aChoice in: s now: t effects: fx
  | persisted committed choice |
  aChoice phase = #guard
    ifTrue: [
      committed := self _committedFor: aChoice in: s.
      (anEvent failure notNil or: [anEvent root isNil or: [(PBRootOrder compare: anEvent root with: committed) < 0]]) ifTrue: [
        ^ self _settle: aChoice waiter with: (self _guardError: aChoice current committed: committed) in: s effects: fx]]
    ifFalse: [anEvent failure notNil ifTrue: [^ self _settle: aChoice waiter with: anEvent failure in: s effects: fx]].
  persisted := anEvent root isNil ifTrue: [PBLabeledRoot label: 0 record: nil] ifFalse: [anEvent root].
  fx add: (PBCount stat: 'storage_root_reads'); add: (PBToAcceptor event: (PBLearnCommitted root: persisted accept: false logged: false)).
  choice := aChoice with: { #current -> persisted. #learnt -> (PBRootOrder max: aChoice learnt with: persisted) }.
  aChoice permission term < (persisted label + PBMembership refoundStep) ifTrue: [
    ^ self _refound: persisted label for: choice in: s effects: fx].
  aChoice phase = #refound ifTrue: [^ self _committedChecks: choice in: s now: t effects: fx].
  ^ self _finishBase: choice in: s now: t effects: fx.

"proto_db refound (D46): the cluster restarts from the persisted root labelled aLabel; this
 node's terms are raised above aLabel + refoundStep, so the refounded lineage supersedes any
 root a lost majority accepted. This permission's term is too low: #stale."
PBCoordinatorCore >> _refound: aLabel for: aChoice in: s effects: fx
  | h |
  h := self _hintsIn: s.
  ^ self _stale: aChoice in: (s with: { #hints -> (h with: { #hint -> (h hint max: aLabel + PBMembership refoundStep) }) }) effects: fx.

"Whether aCommitted (the committed root this node knows, or nil) supersedes aBase under
 aPermission (proto_db _lease_base): it is of a later term (a later owner committed), or of this
 term and above the base (a commit of this term after the base the owner gave, D50)."
PBCoordinatorCore >> _superseded: aPermission by: aCommitted base: aBase
  aCommitted isNil ifTrue: [^ false].
  aCommitted label > aPermission term ifTrue: [^ true].
  ^ aCommitted label = aPermission term and: [(PBRootOrder compare: aCommitted with: aBase) > 0].

"The hard guard (proto_db _lease_base): whether aBase orders below aCommitted, the committed root
 this node knows. Every committed root was accepted by a majority, which every recovery and
 every granting majority of witnesses intersects; an older base means acceptor logs were lost
 beyond the failure model, and committing over it would drop an acknowledged commit."
PBCoordinatorCore >> _belowCommitted: aBase committed: aCommitted
  ^ aCommitted notNil and: [(PBRootOrder compare: aBase with: aCommitted) < 0].

"The error of the hard guard (proto_db _guard_error), naming the operator's remedy."
PBCoordinatorCore >> _guardError: aBase committed: aCommitted
  ^ PBCorruptionError new messageText: 'Protocol violation: the base root (label '
    , (aBase isNil ifTrue: [0] ifFalse: [aBase label]) printString , ', epoch '
    , (aBase isNil ifTrue: [0] ifFalse: [aBase epoch]) printString
    , ') orders below the committed root this node knows (label ' , aCommitted label printString , ', epoch '
    , aCommitted epoch printString , '); refusing to commit over it. This follows the loss of a majority of acceptor '
    , 'logs, which lost that commit. Once an operator has established that loss, call forceRejoin on this node: '
    , 'it forgets the commit it cannot recover and continues from the highest root the cluster accepted (D46)'; yourself.

"proto_db _lease_base's checks against the committed root this node knows: superseded (#stale),
 then the hard guard (below it: the persisted root is read, a refound from it or the guard's
 error)."
PBCoordinatorCore >> _committedChecks: aChoice in: s now: t effects: fx
  | committed |
  committed := self _committedFor: aChoice in: s.
  (self _superseded: aChoice permission by: committed base: aChoice current) ifTrue: [^ self _stale: aChoice in: s effects: fx].
  (self _belowCommitted: aChoice current committed: committed) ifTrue: [
    ^ self _readPersisted: (aChoice with: { #phase -> #guard }) in: s effects: fx].
  ^ self _finishBase: aChoice in: s now: t effects: fx.

"The last checks (proto_db _lease_base and _base_needs_commit): a base labelled above the term is
 #stale (the acquisition learnt the label; the next term is above it); a base other than the
 empty space that is not the committed root this node knows needs a commit first (R50), and its
 SpaceRoot is probed first (R133)."
PBCoordinatorCore >> _finishBase: aChoice in: s now: t effects: fx
  | base committed needs |
  base := aChoice current.
  base label > aChoice permission term ifTrue: [^ self _stale: aChoice in: s effects: fx].
  committed := self _committedFor: aChoice in: s.
  "proto_db _permit_round: 'if current is not None and _base_needs_commit(...)': the empty space
   is never re-committed."
  needs := base record notNil and: [self _needsCommit: base committed: committed].
  needs ifTrue: [^ self _probe: aChoice in: s effects: fx].
  ^ self _decide: (PBBaseDecision base: base needsCommit: needs outcome: #ok) for: aChoice in: s effects: fx.

"proto_db _base_needs_commit at DEPTH 0: aBase is not the committed root this node knows
 (known_root() != (True, current): the records compared, as proto_db's RootRecord tuples)."
PBCoordinatorCore >> _needsCommit: aBase committed: aCommitted
  ^ (aCommitted notNil and: [self _sameRecord: aCommitted record as: aBase record]) not.

"aChoice waits for the probe of its base's SpaceRoot (PBProbeRoot)."
PBCoordinatorCore >> _probe: aChoice in: s effects: fx
  | pair |
  pair := self _token: #base in: s.
  fx add: (PBProbeRoot root: aChoice current token: pair last).
  ^ self _replaceChoice: (aChoice with: { #phase -> #probe. #token -> pair last }) in: pair first.

"The shell probed a base that needs a commit first: readable, it is the base; else #unreachable."
PBCoordinatorCore >> dispatchRootProbed: anEvent in: s now: t
  ^ self _step: [:fx | | choice state |
    choice := self _choiceWithToken: anEvent token phases: #(#probe) in: s.
    choice isNil
      ifTrue: [s]
      ifFalse: [
        state := self _removeChoice: choice in: s.
        anEvent isReadable
          ifTrue: [self _decide: (PBBaseDecision base: choice current needsCommit: true outcome: #ok) for: choice in: state effects: fx]
          ifFalse: [self _unreachable: choice in: state effects: fx]]].

"R133 (proto_db _BaseUnreachable, re-review 3 of 8.3n, I1): a base that must be committed first and
 cannot be read is #unreachable: nothing is sent, the commits get a retryable conflict and the
 permission ends unknown, so the owner abandons the term (O6) instead of issuing the same base
 again (O5) and stalling every round of the term; a fresh phase 1 on the live members decides."
PBCoordinatorCore >> _unreachable: aChoice in: s effects: fx
  ^ self _decide: (PBBaseDecision base: aChoice current needsCommit: true outcome: #unreachable) for: aChoice in: s effects: fx.

"aChoice ends #stale (proto_db _lease_base answering None)."
PBCoordinatorCore >> _stale: aChoice in: s effects: fx
  ^ self _decide: (PBBaseDecision base: aChoice current needsCommit: false outcome: #stale) for: aChoice in: s effects: fx.

"aChoice's waiter is settled with aDecision; an #ok base is bound to its permission."
PBCoordinatorCore >> _decide: aDecision for: aChoice in: s effects: fx
  | state |
  state := self _removeChoice: aChoice in: s.
  aDecision isOk ifTrue: [state := self _bind: aChoice permission base: aDecision base in: state].
  ^ self _settle: aChoice waiter with: aDecision in: state effects: fx.

"proto_db recover_root's suspicion: the acceptor's half is cleared when it is at most the
 suspicion the node held when the round was sent."
PBCoordinatorCore >> acceptRecovered: anEvent in: s now: t
  (s suspectTerm > 0 and: [s suspectTerm <= anEvent suspected]) ifFalse: [^ self _unchangedAcceptor: s].
  ^ PBAcceptorStep
    state: (s withGrants: s grants suspectTerm: 0 rejoined: s isRejoined tierFailed: s tierFailed loggedPromise: s loggedPromise)
    appends: #() reply: #().

"=== The commit round: values ================================================"

"--- PBRoundEntry ---"

"One commit waiting for a round, or in one (proto_db _Entry): its token names it to the shell
 (the waiter its PBSettle settles); caller, the client that made it (proto_db entry.thread: a
 held retry is awaited by its caller, and the retry of a commit is a new entry of the same
 caller); willRetry, whether its caller retries a conflict at once
 (proto_db entry.retrying: Database.run has retries left); deadline, the shell's (CC10: the
 standalone runner's lockTimeout deadline, nil when none), carried and not read by the cluster
 round's rules."
PBProposerValue subclass: #PBRoundEntry.

PBRoundEntry class >> fieldNames
  ^ #(#token #caller #willRetry #deadline).

PBRoundEntry class >> token: aToken caller: aCaller willRetry: aBoolean deadline: aDeadline
  aToken isNil ifTrue: [^ PBValidationError signal: 'PBRoundEntry: a token is required'].
  aCaller isNil ifTrue: [^ PBValidationError signal: 'PBRoundEntry: a caller is required'].
  (aBoolean == true or: [aBoolean == false]) ifFalse: [
    ^ PBValidationError signal: 'PBRoundEntry: willRetry is a Boolean, not ' , aBoolean printString].
  (aDeadline isNil or: [aDeadline isInteger]) ifFalse: [
    ^ PBValidationError signal: 'PBRoundEntry: a deadline is an Integer of microseconds or nil, not ' , aDeadline printString].
  ^ self _from: (Dictionary new at: #token put: aToken; at: #caller put: aCaller; at: #willRetry put: aBoolean;
    at: #deadline put: aDeadline; yourself).

PBRoundEntry >> token
  ^ self _at: #token.

PBRoundEntry >> caller
  ^ self _at: #caller.

PBRoundEntry >> willRetry
  ^ self _at: #willRetry.

PBRoundEntry >> deadline
  ^ self _at: #deadline.

PBRoundEntry >> printOn: aStream
  aStream nextPutAll: 'PBRoundEntry('; nextPutAll: (PBCoreValue textOf: self token); nextPut: $).

"--- PBRoundState ---"

"The commit round of one node (proto_db _Group with the state of its runner, _run_round and
 _permit_round), one round at a time: the config; the queue (PBRoundEntry, waiting); the phase
 (#idle; #permit: a permission asked; #base: its base asked; #recommit: the unchanged root of a
 base that needs a commit first is being built; #recommitting: that root is replicating; #build:
 an entry is building; #replicate: the round's root is replicating; #held: the permission is kept
 for held retries, D-LIVE-2); the batch (the entries that asked for the permission, proto_db
 _run_round's batch); the permission and its outcome (#none, #committed, #unknown) with the root
 committed under it; the round's base (the pred of its replicate) and current root (the next
 entry builds on it); live (the entries of the round not built yet), building (the entry being
 built), built ({ entry. root }), conflicted ({ entry. error }), longest (the longest build of
 the round, microseconds), tried (builds started in the round); rounds (run under the
 permission); awaiting (while the permission is kept: the callers whose held retries the next
 round waits for, proto_db _await_retries' held) and awaitCount (with no held caller: how many
 commits it waits for, the round's conflicts); stale (the permissions in a row whose base was
 stale, proto_db _commit_in_group's count); the hold timer's token and the next token; rejoinBallot (this node's rejoin
 ballot, L14: the shell hands in the acceptor's, withRejoinBallot:)."
PBProposerValue subclass: #PBRoundState.

PBRoundState class >> fieldNames
  ^ #(#config #queue #phase #batch #permission #outcome #committed #base #current #live #building #built #conflicted
      #longest #tried #rounds #awaiting #awaitCount #stale #holdToken #nextToken #rejoinBallot).

"The round of the node of aConfig, idle, nothing queued."
PBRoundState class >> config: aConfig
  (aConfig isKindOf: PBClusterConfig) ifFalse: [
    ^ PBValidationError signal: 'PBRoundState: a config is a PBClusterConfig, not ' , aConfig printString].
  ^ self _from: (Dictionary new
    at: #config put: aConfig; at: #queue put: #(); at: #phase put: #idle; at: #batch put: #(); at: #permission put: nil;
    at: #outcome put: #none; at: #committed put: nil; at: #base put: nil; at: #current put: nil; at: #live put: #();
    at: #building put: nil; at: #built put: #(); at: #conflicted put: #(); at: #longest put: 0; at: #tried put: 0;
    at: #rounds put: 0; at: #awaiting put: #(); at: #awaitCount put: 0; at: #stale put: 0; at: #holdToken put: nil; at: #nextToken put: 1; at: #rejoinBallot put: 0; yourself).

PBRoundState >> config
  ^ self _at: #config.

"The entries waiting for a round, a fresh Array."
PBRoundState >> queue
  ^ (self _at: #queue) copy.

PBRoundState >> phase
  ^ self _at: #phase.

"The entries that asked for the permission being asked, a fresh Array."
PBRoundState >> batch
  ^ (self _at: #batch) copy.

"The permission held (a PBPermission), nil when none."
PBRoundState >> permission
  ^ self _at: #permission.

"The permission's outcome so far: #none, #committed or #unknown."
PBRoundState >> outcome
  ^ self _at: #outcome.

"The root committed under the permission (the last), nil when none."
PBRoundState >> committed
  ^ self _at: #committed.

"The base of the round: the root its replicate names as pred."
PBRoundState >> base
  ^ self _at: #base.

"The root the next entry of the round builds on."
PBRoundState >> current
  ^ self _at: #current.

"The entries of the round not built yet, a fresh Array."
PBRoundState >> live
  ^ (self _at: #live) copy.

PBRoundState >> building
  ^ self _at: #building.

"{ entry. root } of every entry built in the round, in order, a fresh Array."
PBRoundState >> built
  ^ (self _at: #built) collect: [:e | e copy].

"{ entry. error } of every entry of the round that conflicted, in order, a fresh Array."
PBRoundState >> conflicted
  ^ (self _at: #conflicted) collect: [:e | e copy].

"The longest build of the round, microseconds."
PBRoundState >> longest
  ^ self _at: #longest.

PBRoundState >> tried
  ^ self _at: #tried.

"The rounds run under the permission."
PBRoundState >> rounds
  ^ self _at: #rounds.

PBRoundState >> holdToken
  ^ self _at: #holdToken.

"While the permission is kept: the callers whose held retries the next round waits for (proto_db
 _await_retries' held), a fresh Array."
PBRoundState >> awaiting
  ^ (self _at: #awaiting) copy.

"While the permission is kept with no held caller: how many commits the next round waits for."
PBRoundState >> awaitCount
  ^ self _at: #awaitCount.

"The permissions in a row whose base was stale (proto_db _commit_in_group's stale)."
PBRoundState >> stale
  ^ self _at: #stale.

PBRoundState >> nextToken
  ^ self _at: #nextToken.

PBRoundState >> rejoinBallot
  ^ self _at: #rejoinBallot.

"Whether the permission is kept for held retries (D-LIVE-2)."
PBRoundState >> isHeld
  ^ self phase = #held.

"This state with aBallot as the rejoin ballot when it is higher (it never goes down: a ballot a
 quorum promised stays promised)."
PBRoundState >> withRejoinBallot: aBallot
  (aBallot isInteger and: [aBallot >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBRoundState: a rejoin ballot is an Integer >= 0, not ' , aBallot printString].
  aBallot <= self rejoinBallot ifTrue: [^ self].
  ^ self with: { #rejoinBallot -> aBallot }.

PBRoundState >> printOn: aStream
  aStream nextPutAll: 'PBRoundState('; nextPutAll: self phase; nextPutAll: ', '; print: self queue size; nextPutAll: ' queued, ';
    nextPutAll: (PBCoreValue textOf: self permission); nextPut: $).

"=== The commit round: events ================================================"

"An event of a node's commit round (PBCoordinatorCore round:in:now:), never the dispatcher's."
PBCoreValue subclass: #PBRoundEvent.

"Sends aCore the round rule of this event's class."
PBRoundEvent >> roundWith: aCore in: aRoundState now: t
  ^ self subclassResponsibility.

"--- PBRoundEnqueued ---"

PBRoundEvent subclass: #PBRoundEnqueued instanceVariableNames: 'entry'.

"A commit joins the node's group (proto_db _commit_in_group): anEntry, a PBRoundEntry."
PBRoundEnqueued class >> entry: anEntry
  (anEntry isKindOf: PBRoundEntry) ifFalse: [
    ^ PBValidationError signal: 'PBRoundEnqueued: an entry is a PBRoundEntry, not ' , anEntry printString].
  ^ self basicNew _setEntry: anEntry.

PBRoundEnqueued >> _setEntry: anEntry
  "Runs once, on a fresh instance."
  entry isNil ifFalse: [^ PBUserError signal: 'PBRoundEnqueued is immutable'].
  entry := anEntry.
  ^ self.

PBRoundEnqueued >> entry
  ^ entry.

PBRoundEnqueued >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundEnqueued: self in: aRoundState now: t.

PBRoundEnqueued >> printOn: aStream
  aStream nextPutAll: 'PBRoundEnqueued('; print: entry; nextPut: $).

"--- PBPermitted ---"

PBRoundEvent subclass: #PBPermitted instanceVariableNames: 'permission'.

"The answer to PBAskPermit: aPermission (a PBPermission), or the error that ended the wait (an
 Exception, not signalled: PBTimeoutError, a fence's error, ...)."
PBPermitted class >> permission: aPermissionOrError
  ((aPermissionOrError isKindOf: PBPermission) or: [aPermissionOrError isKindOf: Exception]) ifFalse: [
    ^ PBValidationError signal: 'PBPermitted: a permission is a PBPermission or an Exception, not ' , aPermissionOrError printString].
  ^ self basicNew _setPermission: aPermissionOrError.

PBPermitted >> _setPermission: aPermissionOrError
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBPermitted is immutable'].
  permission := aPermissionOrError.
  ^ self.

PBPermitted >> permission
  ^ permission.

PBPermitted >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundPermitted: self in: aRoundState now: t.

PBPermitted >> printOn: aStream
  aStream nextPutAll: 'PBPermitted('; nextPutAll: (PBCoreValue textOf: permission); nextPut: $).

"--- PBBaseDecided ---"

PBRoundEvent subclass: #PBBaseDecided instanceVariableNames: 'decision'.

"The answer to PBAskBase: aDecision (a PBBaseDecision, leaseBase:waiter:in:now:), or the error
 the base choice ended with (an Exception, not signalled)."
PBBaseDecided class >> decision: aDecisionOrError
  ((aDecisionOrError isKindOf: PBBaseDecision) or: [aDecisionOrError isKindOf: Exception]) ifFalse: [
    ^ PBValidationError signal: 'PBBaseDecided: a decision is a PBBaseDecision or an Exception, not ' , aDecisionOrError printString].
  ^ self basicNew _setDecision: aDecisionOrError.

PBBaseDecided >> _setDecision: aDecisionOrError
  "Runs once, on a fresh instance."
  decision isNil ifFalse: [^ PBUserError signal: 'PBBaseDecided is immutable'].
  decision := aDecisionOrError.
  ^ self.

PBBaseDecided >> decision
  ^ decision.

PBBaseDecided >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundBaseDecided: self in: aRoundState now: t.

PBBaseDecided >> printOn: aStream
  aStream nextPutAll: 'PBBaseDecided('; print: decision; nextPut: $).

"--- PBBuilt, PBBuildConflict, PBBuildFailed ---"

PBRoundEvent subclass: #PBBuilt instanceVariableNames: 'entry root micros'.

"The answer to PBBuild: the root built for anEntry (nil: the unchanged root of a base that needs
 a commit first, proto_db _commit_base), aRoot (a PBLabeledRoot carrying the build's stamp: label
 the term, epoch the base's + 1; nil for an entry with nothing to publish, proto_db ptr None),
 built in someMicros (an Integer >= 0: the build's measured time, which feeds the group bound)."
PBBuilt class >> entry: anEntryOrNil root: aRootOrNil micros: someMicros
  (anEntryOrNil isNil or: [anEntryOrNil isKindOf: PBRoundEntry]) ifFalse: [
    ^ PBValidationError signal: 'PBBuilt: an entry is a PBRoundEntry or nil, not ' , anEntryOrNil printString].
  (aRootOrNil isNil or: [aRootOrNil isClassObject not and: [aRootOrNil class == PBLabeledRoot]]) ifFalse: [
    ^ PBValidationError signal: 'PBBuilt: a root is a PBLabeledRoot or nil, not ' , aRootOrNil printString].
  (someMicros isInteger and: [someMicros >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBBuilt: micros is an Integer >= 0, not ' , someMicros printString].
  ^ self basicNew _setEntry: anEntryOrNil root: aRootOrNil micros: someMicros.

PBBuilt >> _setEntry: anEntryOrNil root: aRootOrNil micros: someMicros
  "Runs once, on a fresh instance."
  micros isNil ifFalse: [^ PBUserError signal: 'PBBuilt is immutable'].
  entry := anEntryOrNil.
  root := aRootOrNil.
  micros := someMicros.
  ^ self.

PBBuilt >> entry
  ^ entry.

PBBuilt >> root
  ^ root.

PBBuilt >> micros
  ^ micros.

PBBuilt >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundBuilt: self in: aRoundState now: t.

PBBuilt >> printOn: aStream
  aStream nextPutAll: 'PBBuilt('; nextPutAll: (PBCoreValue textOf: entry); nextPutAll: ', ';
    nextPutAll: (PBCoreValue textOf: root); nextPutAll: ', '; print: micros; nextPutAll: ' us)'.

PBRoundEvent subclass: #PBBuildConflict instanceVariableNames: 'entry error'.

"The build of anEntry conflicted (anError, a PBConflictError, not signalled): it fails alone
 (proto_db _permit_round: a conflicting transaction fails alone)."
PBBuildConflict class >> entry: anEntry error: anError
  (anEntry isKindOf: PBRoundEntry) ifFalse: [
    ^ PBValidationError signal: 'PBBuildConflict: an entry is a PBRoundEntry, not ' , anEntry printString].
  (anError isKindOf: PBConflictError) ifFalse: [
    ^ PBValidationError signal: 'PBBuildConflict: an error is a PBConflictError, not ' , anError printString].
  ^ self basicNew _setEntry: anEntry error: anError.

PBBuildConflict >> _setEntry: anEntry error: anError
  "Runs once, on a fresh instance."
  entry isNil ifFalse: [^ PBUserError signal: 'PBBuildConflict is immutable'].
  entry := anEntry.
  error := anError.
  ^ self.

PBBuildConflict >> entry
  ^ entry.

PBBuildConflict >> error
  ^ error.

PBBuildConflict >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundBuildConflict: self in: aRoundState now: t.

PBBuildConflict >> printOn: aStream
  aStream nextPutAll: 'PBBuildConflict('; nextPutAll: (PBCoreValue textOf: entry); nextPut: $).

PBRoundEvent subclass: #PBBuildFailed instanceVariableNames: 'entry error'.

"The build of anEntry (nil: of the unchanged root of a base that needs a commit first) failed
 with anError (an Exception, not signalled, other than a conflict of an entry)."
PBBuildFailed class >> entry: anEntryOrNil error: anError
  (anEntryOrNil isNil or: [anEntryOrNil isKindOf: PBRoundEntry]) ifFalse: [
    ^ PBValidationError signal: 'PBBuildFailed: an entry is a PBRoundEntry or nil, not ' , anEntryOrNil printString].
  (anError isKindOf: Exception) ifFalse: [
    ^ PBValidationError signal: 'PBBuildFailed: an error is an Exception, not ' , anError printString].
  ^ self basicNew _setEntry: anEntryOrNil error: anError.

PBBuildFailed >> _setEntry: anEntryOrNil error: anError
  "Runs once, on a fresh instance."
  error isNil ifFalse: [^ PBUserError signal: 'PBBuildFailed is immutable'].
  entry := anEntryOrNil.
  error := anError.
  ^ self.

PBBuildFailed >> entry
  ^ entry.

PBBuildFailed >> error
  ^ error.

PBBuildFailed >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundBuildFailed: self in: aRoundState now: t.

PBBuildFailed >> printOn: aStream
  aStream nextPutAll: 'PBBuildFailed('; nextPutAll: (PBCoreValue textOf: entry); nextPutAll: ', '; print: error class; nextPut: $).

"--- PBReplicated ---"

PBRoundEvent subclass: #PBReplicated instanceVariableNames: 'outcome'.

"The answer to PBReplicate: anOutcome, #committed, #unknown or #none (H7, the settle of
 dispatchReplicateWanted:in:now:)."
PBReplicated class >> outcome: anOutcome
  (#(#committed #unknown #none) includes: anOutcome) ifFalse: [
    ^ PBValidationError signal: 'PBReplicated: an outcome is #committed, #unknown or #none, not ' , anOutcome printString].
  ^ self basicNew _setOutcome: anOutcome asSymbol.

PBReplicated >> _setOutcome: anOutcome
  "Runs once, on a fresh instance."
  outcome isNil ifFalse: [^ PBUserError signal: 'PBReplicated is immutable'].
  outcome := anOutcome.
  ^ self.

PBReplicated >> outcome
  ^ outcome.

PBReplicated >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundReplicated: self in: aRoundState now: t.

PBReplicated >> printOn: aStream
  aStream nextPutAll: 'PBReplicated('; nextPutAll: outcome; nextPut: $).

"--- PBHoldExpired, PBDropKept ---"

PBRoundEvent subclass: #PBHoldExpired instanceVariableNames: 'token'.

"The hold timer aToken came due (the event of the round's PBTimer): a permission still kept
 under that token ends (proto_db _keep's expire)."
PBHoldExpired class >> token: aToken
  ^ self basicNew _setToken: (self _present: aToken named: 'token').

PBHoldExpired >> _setToken: aToken
  "Runs once, on a fresh instance."
  token isNil ifFalse: [^ PBUserError signal: 'PBHoldExpired is immutable'].
  token := aToken.
  ^ self.

PBHoldExpired >> token
  ^ token.

PBHoldExpired >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundHoldExpired: self in: aRoundState now: t.

PBHoldExpired >> printOn: aStream
  aStream nextPutAll: 'PBHoldExpired('; nextPutAll: (PBCoreValue textOf: token); nextPut: $).

PBRoundEvent subclass: #PBDropKept instanceVariableNames: 'caller'.

"aCaller, whose conflict was held, will not retry (proto_db _drop_kept: Database.run returned or
 raised instead): the kept permission no longer waits for it."
PBDropKept class >> caller: aCaller
  ^ self basicNew _setCaller: (self _present: aCaller named: 'caller').

PBDropKept >> _setCaller: aCaller
  "Runs once, on a fresh instance."
  caller isNil ifFalse: [^ PBUserError signal: 'PBDropKept is immutable'].
  caller := aCaller.
  ^ self.

PBDropKept >> caller
  ^ caller.

PBDropKept >> roundWith: aCore in: aRoundState now: t
  ^ aCore roundDropKept: self in: aRoundState now: t.

PBDropKept >> printOn: aStream
  aStream nextPutAll: 'PBDropKept('; nextPutAll: (PBCoreValue textOf: caller); nextPut: $).

"=== The commit round: effects ==============================================="

PBEffect subclass: #PBAskPermit.

"Ask the node for a write permission (PBPermitWanted) and hand the round PBPermitted with its
 answer."
PBAskPermit >> applyTo: aShell
  ^ aShell applyAskPermit: self.

PBEffect subclass: #PBAskBase instanceVariableNames: 'permission'.

"Ask the node for the base of a round under aPermission (PBBaseWanted) and hand the round
 PBBaseDecided with its answer."
PBAskBase class >> permission: aPermission
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBAskBase: a permission is a PBPermission, not ' , aPermission printString].
  ^ self basicNew _setPermission: aPermission.

PBAskBase >> _setPermission: aPermission
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBAskBase is immutable'].
  permission := aPermission.
  ^ self.

PBAskBase >> permission
  ^ permission.

PBAskBase >> applyTo: aShell
  ^ aShell applyAskBase: self.

PBAskBase >> printOn: aStream
  aStream nextPutAll: 'PBAskBase('; nextPutAll: (PBCoreValue textOf: permission); nextPut: $).

PBEffect subclass: #PBBuild instanceVariableNames: 'entry base stamp'.

"Build anEntry's transaction on aBase (a PBLabeledRoot) with aStamp ({ term. epoch }: the
 permission's term, the base's epoch + 1, proto_db _ClusterStamp) and hand the round PBBuilt,
 PBBuildConflict or PBBuildFailed. anEntry nil: save the unchanged root of aBase with aStamp (a
 base that needs a commit first, proto_db _commit_base)."
PBBuild class >> entry: anEntryOrNil base: aBase stamp: aStamp
  (anEntryOrNil isNil or: [anEntryOrNil isKindOf: PBRoundEntry]) ifFalse: [
    ^ PBValidationError signal: 'PBBuild: an entry is a PBRoundEntry or nil, not ' , anEntryOrNil printString].
  (aBase isKindOf: PBLabeledRoot) ifFalse: [
    ^ PBValidationError signal: 'PBBuild: a base is a PBLabeledRoot, not ' , aBase printString].
  (aStamp isArray and: [aStamp size = 2 and: [aStamp allSatisfy: [:i | i isInteger and: [i >= 0]]]]) ifFalse: [
    ^ PBValidationError signal: 'PBBuild: a stamp is { term. epoch }, not ' , aStamp printString].
  ^ self basicNew _setEntry: anEntryOrNil base: aBase stamp: aStamp copy.

PBBuild >> _setEntry: anEntryOrNil base: aBase stamp: aStamp
  "Runs once, on a fresh instance."
  stamp isNil ifFalse: [^ PBUserError signal: 'PBBuild is immutable'].
  entry := anEntryOrNil.
  base := aBase.
  stamp := aStamp.
  ^ self.

PBBuild >> entry
  ^ entry.

PBBuild >> base
  ^ base.

"{ term. epoch }, a fresh Array."
PBBuild >> stamp
  ^ stamp copy.

PBBuild >> applyTo: aShell
  ^ aShell applyBuild: self.

PBBuild >> printOn: aStream
  aStream nextPutAll: 'PBBuild('; nextPutAll: (PBCoreValue textOf: entry); nextPutAll: ' on ';
    nextPutAll: (PBCoreValue textOf: base); nextPutAll: ', '; print: stamp; nextPut: $).

PBEffect subclass: #PBReplicate instanceVariableNames: 'permission root pred'.

"Replicate aRoot, built under aPermission on aPred (the round's base), as PBReplicateWanted
 permission: root: pred: waiter:, and hand the round PBReplicated with its outcome."
PBReplicate class >> permission: aPermission root: aRoot pred: aPred
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBReplicate: a permission is a PBPermission, not ' , aPermission printString].
  ((aRoot isKindOf: PBLabeledRoot) and: [aPred isKindOf: PBLabeledRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBReplicate: a root and a pred are PBLabeledRoots, not ' , aRoot printString , ', ' , aPred printString].
  ^ self basicNew _setPermission: aPermission root: aRoot pred: aPred.

PBReplicate >> _setPermission: aPermission root: aRoot pred: aPred
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBReplicate is immutable'].
  permission := aPermission.
  root := aRoot.
  pred := aPred.
  ^ self.

PBReplicate >> permission
  ^ permission.

PBReplicate >> root
  ^ root.

PBReplicate >> pred
  ^ pred.

PBReplicate >> applyTo: aShell
  ^ aShell applyReplicate: self.

PBReplicate >> printOn: aStream
  aStream nextPutAll: 'PBReplicate('; nextPutAll: (PBCoreValue textOf: root); nextPutAll: ' on ';
    nextPutAll: (PBCoreValue textOf: pred); nextPut: $).

PBEffect subclass: #PBReportDone instanceVariableNames: 'permission outcome root'.

"End aPermission with anOutcome (#committed, #unknown or #none) and aRoot (the root committed
 under it, nil unless #committed): PBDoneReport permission: outcome: root: to the node (proto_db
 _end_permission, finish)."
PBReportDone class >> permission: aPermission outcome: anOutcome root: aRootOrNil
  (aPermission isKindOf: PBPermission) ifFalse: [
    ^ PBValidationError signal: 'PBReportDone: a permission is a PBPermission, not ' , aPermission printString].
  (PBDoneReport outcomes includes: anOutcome) ifFalse: [
    ^ PBValidationError signal: 'PBReportDone: an outcome is #committed, #unknown or #none, not ' , anOutcome printString].
  ((anOutcome = #committed) = aRootOrNil notNil) ifFalse: [
    ^ PBValidationError signal: 'PBReportDone: a root exactly with #committed'].
  ^ self basicNew _setPermission: aPermission outcome: anOutcome asSymbol root: aRootOrNil.

PBReportDone >> _setPermission: aPermission outcome: anOutcome root: aRootOrNil
  "Runs once, on a fresh instance."
  permission isNil ifFalse: [^ PBUserError signal: 'PBReportDone is immutable'].
  permission := aPermission.
  outcome := anOutcome.
  root := aRootOrNil.
  ^ self.

PBReportDone >> permission
  ^ permission.

PBReportDone >> outcome
  ^ outcome.

PBReportDone >> root
  ^ root.

PBReportDone >> applyTo: aShell
  ^ aShell applyReportDone: self.

PBReportDone >> printOn: aStream
  aStream nextPutAll: 'PBReportDone('; nextPutAll: (PBCoreValue textOf: permission); nextPutAll: ', '; nextPutAll: outcome; nextPut: $).

"=== PBCoordinatorCore: the commit round ====================================="

"The step of the commit round of aRoundState for anEvent at t (microseconds of the node's clock):
 a PBStep whose state is the new PBRoundState. A rule that answers anything else is
 PBUnexpectedError."
PBCoordinatorCore >> round: anEvent in: aRoundState now: t
  | step |
  (anEvent isKindOf: PBRoundEvent) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: a round event is a PBRoundEvent, not ' , anEvent printString].
  (aRoundState isKindOf: PBRoundState) ifFalse: [
    ^ PBValidationError signal: 'PBCoordinatorCore: a round state is a PBRoundState, not ' , aRoundState printString].
  t isInteger ifFalse: [^ PBValidationError signal: 'PBCoordinatorCore: now is an Integer of microseconds, not ' , t printString].
  step := anEvent roundWith: self in: aRoundState now: t.
  ((step isKindOf: PBStep) and: [step state isKindOf: PBRoundState]) ifFalse: [
    ^ PBUnexpectedError signal: 'The round rule for ' , anEvent printString , ' answered ' , step printString , ', not a PBStep of a PBRoundState'].
  ^ step.

"The shell handed anEvent to a round in another phase than aPhase: PBValidationError (the shell
 answers each effect once, with the event of its kind)."
PBCoordinatorCore >> _expect: aPhase in: s for: anEvent
  s phase = aPhase ifFalse: [
    ^ PBValidationError signal: 'The round takes ' , anEvent printString , ' only in phase ' , aPhase , ', not in ' , s phase].

"anEvent names the entry being built, else PBValidationError."
PBCoordinatorCore >> _expectBuilding: anEvent in: s
  (s building notNil and: [anEvent entry notNil and: [anEvent entry token = s building token]]) ifFalse: [
    ^ PBValidationError signal: 'The round is building ' , (PBCoreValue textOf: s building) , ', not '
      , (PBCoreValue textOf: anEvent entry)].

"The stamp of a root built on aRoot under s's permission: { term. epoch + 1 } (proto_db
 _ClusterStamp(permission.term, current.epoch + 1))."
PBCoordinatorCore >> _stampOn: aRoot in: s
  ^ { s permission term. aRoot epoch + 1 }.

"aRoot was built on aBase with its stamp (label the term, epoch the base's + 1), else
 PBValidationError: a root that does not extend the base by one epoch under the term is never
 sent."
PBCoordinatorCore >> _checkBuilt: aRoot on: aBase in: s for: anEvent
  | stamp |
  stamp := self _stampOn: aBase in: s.
  (aRoot notNil and: [aRoot label = stamp first and: [aRoot epoch = stamp last]]) ifFalse: [
    ^ PBValidationError signal: anEvent printString , ': a root built on ' , (PBCoreValue textOf: aBase) , ' under '
      , (PBCoreValue textOf: s permission) , ' carries the stamp ' , stamp printString , ', not ' , (PBCoreValue textOf: aRoot)].

"Each of someEntries settled with anOutcome (an error shared by them is one value: a shell that
 signals it to several callers signals a copy to each, proto_db error_shared)."
PBCoordinatorCore >> _finish: someEntries with: anOutcome effects: fx
  someEntries do: [:e | fx add: (PBSettle waiter: e token outcome: anOutcome)].

"Milliseconds of someMicros, rounded, as text."
PBCoordinatorCore >> _ms: someMicros
  ^ (someMicros / 1000) rounded printString.

"--- joining, the permission ---"

"proto_db _commit_in_group: a commit joins the node's group. With no round, the round takes the
 whole queue and asks for a permission; under a permission kept for held retries, the next round
 under it starts once the queue holds as many commits as it awaits (_retriesIn:, D-LIVE-2); else
 it waits for the round that runs."
PBCoordinatorCore >> roundEnqueued: anEvent in: s now: t
  ^ self _step: [:fx | | state |
    state := s with: { #queue -> (s queue copyWith: anEvent entry) }.
    s phase = #idle ifTrue: [state := self _askPermit: state effects: fx].
    (s phase = #held and: [self _retriesIn: state]) ifTrue: [state := self _takeKept: state now: t effects: fx].
    state].

"proto_db _await_retries: whether the retries a kept permission awaits are queued: every held
 caller has a commit in the queue (held <= queued, by caller); with no held caller, the queue
 holds as many commits as the round had conflicts."
PBCoordinatorCore >> _retriesIn: s
  s queue isEmpty ifTrue: [^ false].
  s awaiting isEmpty ifTrue: [^ s queue size >= s awaitCount].
  ^ s awaiting allSatisfy: [:who | s queue anySatisfy: [:q | q caller = who]].

"One round at a time (proto_db _run_round's batch): the whole queue asks for one permission."
PBCoordinatorCore >> _askPermit: s effects: fx
  s queue isEmpty ifTrue: [^ s].
  fx add: PBAskPermit new.
  ^ s with: { #phase -> #permit. #batch -> s queue. #queue -> #() }.

"proto_db _take_kept: a kept permission still valid runs the next round, with the whole queue;
 one that is not ends, and the queue asks for a new one."
PBCoordinatorCore >> _takeKept: s now: t effects: fx
  (s permission isValidAt: t) ifTrue: [
    ^ self _startRound: (s with: { #live -> s queue. #queue -> #(). #holdToken -> nil. #awaiting -> #(). #awaitCount -> 0 })
      now: t effects: fx].
  ^ self _endPermission: s now: t effects: fx.

"The answer to PBAskPermit (proto_db _run_round after coordinator.permit): with a permission, the
 batch and every commit queued meanwhile run its first round (_drain_queue); an error settles the
 batch with it, and a queue that formed meanwhile asks again."
PBCoordinatorCore >> roundPermitted: anEvent in: s now: t
  ^ self _step: [:fx | | p |
    self _expect: #permit in: s for: anEvent.
    p := anEvent permission.
    (p isKindOf: PBPermission)
      ifTrue: [
        self _startRound: (s with: { #permission -> p. #outcome -> #none. #committed -> nil. #rounds -> 0.
          #live -> (s batch , s queue). #batch -> #(). #queue -> #() }) now: t effects: fx]
      ifFalse: [
        self _finish: s batch with: p effects: fx.
        self _askPermit: (s with: { #phase -> #idle. #batch -> #(). #stale -> 0 }) effects: fx]].

"A round under the permission (proto_db _permit_round): its base first (_lease_base, every
 round)."
PBCoordinatorCore >> _startRound: s now: t effects: fx
  fx add: (PBAskBase permission: s permission).
  ^ s with: { #phase -> #base. #rounds -> (s rounds + 1). #built -> #(). #conflicted -> #(). #longest -> 0. #tried -> 0.
    #building -> nil. #base -> nil. #current -> nil }.

"--- the base ---"

"The base of the round (proto_db _permit_round after _lease_base): an error ends the round with
 it, nothing sent; #stale requeues; #unreachable is a retryable conflict that abandons the term;
 #ok builds on it, after re-committing it when it needs a commit first."
PBCoordinatorCore >> roundBaseDecided: anEvent in: s now: t
  ^ self _step: [:fx | | d |
    self _expect: #base in: s for: anEvent.
    d := anEvent decision.
    (d isKindOf: PBBaseDecision)
      ifFalse: [self _failRound: s with: d sent: false now: t effects: fx]
      ifTrue: [
        d outcome = #stale
          ifTrue: [self _staleBase: s now: t effects: fx]
          ifFalse: [
            d outcome = #unreachable
              ifTrue: [self _unreachableBase: s decision: d now: t effects: fx]
              ifFalse: [self _based: s on: d now: t effects: fx]]]].

"proto_db _permit_round, base None: nothing was sent; the commits go back to the head of the
 queue (not as attempts) and the permission ends with an outcome its owner cannot take for
 granted, 'unknown', so the owner abandons the term (D50) -- unless a round under it committed
 already (a held retry's round: its done reports that commit). proto_db _commit_in_group: after
 termRetries such permissions in a row, every queued commit fails with a retryable conflict."
PBCoordinatorCore >> _staleBase: s now: t effects: fx
  | state stale |
  state := s with: { #queue -> (s live , s queue). #live -> #() }.
  s outcome = #committed ifFalse: [state := state with: { #outcome -> #unknown }].
  stale := s stale + 1.
  stale >= self termRetries ifTrue: [
    self _finish: state queue with: (PBConflictError new messageText: 'Node ' , s config nodeId , ': no permission with a '
      , 'base at or above the committed root after ' , self termRetries printString , ' attempts; nothing was replicated'; yourself)
      effects: fx.
    ^ self _endPermission: (state with: { #queue -> #() }) now: t effects: fx].
  ^ (self _endPermission: state now: t effects: fx) with: { #stale -> stale }.

"proto_db _TERM_RETRIES: the permissions in a row with a stale base after which the queued
 commits fail."
PBCoordinatorCore >> termRetries
  ^ 5.

"proto_db _BaseUnreachable (R133): nothing was sent, the commits get a retryable conflict, and
 the permission ends 'unknown' so its owner abandons the term instead of issuing the base again."
PBCoordinatorCore >> _unreachableBase: s decision: aDecision now: t effects: fx
  ^ self _failRound: (s with: { #outcome -> #unknown })
    with: (PBConflictError new messageText: 'Node ' , s config nodeId , ': the base root (label ' , aDecision base label printString
      , ', epoch ' , aDecision base epoch printString , ') cannot be re-committed now: the shared storage cannot read its '
      , 'SpaceRoot; nothing was replicated'; yourself)
    sent: false now: t effects: fx.

"An #ok base: bound by the core already. One that needs a commit first is re-committed before any
 entry (proto_db _commit_base: an unchanged root on top, labelled with the term, epoch + 1)."
PBCoordinatorCore >> _based: s on: aDecision now: t effects: fx
  | state |
  state := s with: { #base -> aDecision base. #current -> aDecision base }.
  aDecision needsCommit ifTrue: [
    fx add: (PBBuild entry: nil base: aDecision base stamp: (self _stampOn: aDecision base in: s)).
    ^ state with: { #phase -> #recommit }].
  ^ self _buildNext: state now: t effects: fx.

"--- the builds ---"

"CC11, the group-size bound (a protoBaseST liveness addition, Q4): before building a commit after
 the first of the round, whether the permission has sendReserve + the longest build of the round
 left. It never decides safety: the reserve check decides what is sent."
PBCoordinatorCore >> groupBoundAllows: s now: t
  ^ (s permission remainingAt: t) >= (s config sendReserve + s longest).

"The next build of the round (proto_db _permit_round's loop): each entry on the root the previous
 one produced; the first always, a later one while the group bound allows it (the rest go back to
 the head of the queue, not as attempts); with every entry tried, the root is sent."
PBCoordinatorCore >> _buildNext: s now: t effects: fx
  | e |
  s live isEmpty ifTrue: [^ self _afterBuilds: s now: t effects: fx].
  (s tried > 0 and: [(self groupBoundAllows: s now: t) not]) ifTrue: [
    ^ self _afterBuilds: (s with: { #queue -> (s live , s queue). #live -> #() }) now: t effects: fx].
  e := s live first.
  fx add: (PBBuild entry: e base: s current stamp: (self _stampOn: s current in: s)).
  ^ s with: { #phase -> #build. #building -> e. #live -> (s live copyFrom: 2 to: s live size). #tried -> (s tried + 1) }.

"The answer to PBBuild: the unchanged root of a re-commit is sent (after the checks of
 mayReplicate:now:); an entry's root is the next build's base (nil: nothing to publish, settled
 false)."
PBCoordinatorCore >> roundBuilt: anEvent in: s now: t
  ^ self _step: [:fx |
    anEvent entry isNil
      ifTrue: [self _recommitBuilt: anEvent in: s now: t effects: fx]
      ifFalse: [self _entryBuilt: anEvent in: s now: t effects: fx]].

PBCoordinatorCore >> _recommitBuilt: anEvent in: s now: t effects: fx
  | refusal |
  self _expect: #recommit in: s for: anEvent.
  self _checkBuilt: anEvent root on: s base in: s for: anEvent.
  refusal := self mayReplicate: s now: t.
  refusal notNil ifTrue: [^ self _refuse: s with: refusal now: t effects: fx].
  fx add: (PBReplicate permission: s permission root: anEvent root pred: s base).
  ^ s with: { #phase -> #recommitting. #current -> anEvent root }.

PBCoordinatorCore >> _entryBuilt: anEvent in: s now: t effects: fx
  | state |
  self _expect: #build in: s for: anEvent.
  self _expectBuilding: anEvent in: s.
  state := s with: { #building -> nil. #longest -> (s longest max: anEvent micros) }.
  anEvent root isNil ifTrue: [
    fx add: (PBSettle waiter: anEvent entry token outcome: false).
    ^ self _buildNext: state now: t effects: fx].
  self _checkBuilt: anEvent root on: s current in: s for: anEvent.
  ^ self _buildNext: (state with: { #current -> anEvent root. #built -> ((s built) copyWith: { anEvent entry. anEvent root }) })
    now: t effects: fx.

"A conflicting entry fails alone (decided after the replication: proto_db conflicted)."
PBCoordinatorCore >> roundBuildConflict: anEvent in: s now: t
  ^ self _step: [:fx |
    self _expect: #build in: s for: anEvent.
    self _expectBuilding: anEvent in: s.
    self _buildNext: (s with: { #building -> nil. #conflicted -> ((s conflicted) copyWith: { anEvent entry. anEvent error }) })
      now: t effects: fx].

"A build that failed (proto_db _permit_round: ProtoDBError, entry.finish(error)): an entry's
 PBDBError fails it alone, any other error ends the round with it, nothing sent (proto_db's
 except branch); the re-commit's ends the round with its error, and the outcome is unknown unless nothing
 a voter may accept can have left (proto_db: 'sent' is set before _commit_base; nothing_sent
 only for a conflict, validation or user error)."
PBCoordinatorCore >> roundBuildFailed: anEvent in: s now: t
  ^ self _step: [:fx |
    anEvent entry isNil
      ifTrue: [
        self _expect: #recommit in: s for: anEvent.
        self _failRound: s with: anEvent error sent: (self _nothingSent: anEvent error) not now: t effects: fx]
      ifFalse: [
        self _expect: #build in: s for: anEvent.
        self _expectBuilding: anEvent in: s.
        (anEvent error isKindOf: PBDBError)
          ifTrue: [
            fx add: (PBSettle waiter: anEvent entry token outcome: anEvent error).
            self _buildNext: (s with: { #building -> nil }) now: t effects: fx]
          ifFalse: [self _failRound: s with: anEvent error sent: false now: t effects: fx]]].

"proto_db _permit_round's except: an error that says nothing acceptable left the node."
PBCoordinatorCore >> _nothingSent: anError
  ^ (anError isKindOf: PBConflictError) or: [(anError isKindOf: PBValidationError) or: [anError isKindOf: PBUserError]].

"--- sending ---"

"Every entry tried: a round that built nothing sends nothing; else its root goes out, after the
 checks of mayReplicate:now:."
PBCoordinatorCore >> _afterBuilds: s now: t effects: fx
  | refusal |
  s built isEmpty ifTrue: [^ self _roundDone: s now: t effects: fx].
  refusal := self mayReplicate: s now: t.
  refusal notNil ifTrue: [^ self _refuse: s with: refusal now: t effects: fx].
  fx add: (PBReplicate permission: s permission root: s current pred: s base).
  ^ s with: { #phase -> #replicate }.

"nil when the round may send its root now, else the PBConflictError of the refusal (nothing is
 sent: truthful, retryable, H7): R121, less than sendReserve left of the permission
 (_reserveRefusal:left:, CC18); L14, the permission's term below this node's rejoin ballot
 (_belowRejoinBallot:)."
PBCoordinatorCore >> mayReplicate: s now: t
  | left |
  left := s permission remainingAt: t.
  left < s config sendReserve ifTrue: [^ self _reserveRefusal: s left: left].
  ^ self _belowRejoinBallot: s.

"CC18 (Review Focus 2): the reserve refusal names the time left, sendReserve, the longest build
 of the round and leaseDuration, so a transaction whose build alone exceeds the permission window
 says why it never commits (proto_db _check_reserve's text, with the build)."
PBCoordinatorCore >> _reserveRefusal: s left: someMicros
  | c |
  c := s config.
  ^ PBConflictError new messageText: 'Node ' , c nodeId , ': the permission had ' , (self _ms: someMicros)
    , ' ms left, less than the ' , (self _ms: c sendReserve) , ' ms a replication needs (sendReserve); the longest build of '
    , 'this round took ' , (self _ms: s longest) , ' ms, and a permission lasts at most the belief of ' , (self _ms: c belief)
    , ' ms (leaseDuration ' , (self _ms: c leaseDuration) , ' ms less driftMargin ' , (self _ms: c driftMargin)
    , ' ms): a commit whose build leaves less than sendReserve of it never commits; shorten the transaction or raise '
    , 'leaseDuration. Nothing was replicated'; yourself.

"L14 (proto_db replicate: label < _rejoin_ballot): this node's rejoin ballot was promised by
 V - majority + 1 voters, so no term below it can gain a majority again; the refusal of a root of
 a term below it is a conflict, nothing sent, nil when the term is not below it."
PBCoordinatorCore >> _belowRejoinBallot: s
  s permission term < s rejoinBallot ifFalse: [^ nil].
  ^ PBConflictError new messageText: 'Node ' , s config nodeId , ': term ' , s permission term printString
    , ' is below this node''s rejoin ballot ' , s rejoinBallot printString , ', which a quorum promised; nothing was replicated';
    yourself.

"The round refused to send (counted sends_refused_reserve when the permission is valid with less
 than the reserve left: proto_db raises an expired lease without counting): nothing left the
 node, the round ends with the refusal."
PBCoordinatorCore >> _refuse: s with: aRefusal now: t effects: fx
  ((s permission isValidAt: t) and: [(s permission remainingAt: t) < s config sendReserve]) ifTrue: [
    fx add: (PBCount stat: 'sends_refused_reserve')].
  ^ self _failRound: s with: aRefusal sent: false now: t effects: fx.

"The answer to PBReplicate (H7): of the re-commit, #committed builds the entries on it; of the
 round's root, #committed settles the built entries true. Otherwise the round ends: #none, a
 retryable conflict (nothing acceptable left the node), #unknown, PBOutcomeUnknownError."
PBCoordinatorCore >> roundReplicated: anEvent in: s now: t
  ^ self _step: [:fx | | o |
    o := anEvent outcome.
    s phase = #recommitting
      ifTrue: [
        o = #committed
          ifTrue: [self _buildNext: (s with: { #outcome -> #committed. #committed -> s current. #base -> s current }) now: t effects: fx]
          ifFalse: [self _replicationFailed: s outcome: o now: t effects: fx]]
      ifFalse: [
        self _expect: #replicate in: s for: anEvent.
        o = #committed
          ifTrue: [
            self _finish: (s built collect: [:b | b first]) with: true effects: fx.
            self _roundDone: (s with: { #outcome -> #committed. #committed -> s current. #base -> s current. #built -> #() })
              now: t effects: fx]
          ifFalse: [self _replicationFailed: s outcome: o now: t effects: fx]]].

"A replication that did not commit: #unknown (the root left this node) or #none (nothing a voter
 may accept left it)."
PBCoordinatorCore >> _replicationFailed: s outcome: anOutcome now: t effects: fx
  anOutcome = #unknown ifTrue: [
    ^ self _failRound: s with: (PBOutcomeUnknownError new messageText: 'Node ' , s config nodeId , ': the root of this commit '
      , 'was sent under ' , (PBCoreValue textOf: s permission) , ' and no majority of the voters acknowledged it within the '
      , 'permission: it may or may not be committed (the next phase 1 decides)'; yourself)
      sent: true now: t effects: fx].
  ^ self _failRound: s with: (PBConflictError new messageText: 'Node ' , s config nodeId , ': nothing a voter may accept left '
    , 'this node under ' , (PBCoreValue textOf: s permission) , ' (it ended, or had too little time left, before the root '
    , 'was sent); nothing was replicated'; yourself)
    sent: false now: t effects: fx.

"proto_db _permit_round's except branch: the round ends with anError. A conflicted entry gets its
 own conflict (not part of what was sent, never held); every other entry of the round (built,
 being built, not built yet) gets anError. With isSent, something a voter may accept left the
 node: the permission's outcome is unknown. Then the permission ends."
PBCoordinatorCore >> _failRound: s with: anError sent: isSent now: t effects: fx
  | state |
  s conflicted do: [:c | fx add: (PBSettle waiter: c first token outcome: c last)].
  self _finish: (s built collect: [:b | b first]) , (s building isNil ifTrue: [#()] ifFalse: [{ s building }]) , s live
    with: anError effects: fx.
  state := s with: { #built -> #(). #conflicted -> #(). #building -> nil. #live -> #() }.
  isSent ifTrue: [state := state with: { #outcome -> #unknown }].
  ^ self _endPermission: state now: t effects: fx.

"--- after a round: held retries (D-LIVE-2) ---"

"proto_db _permit_round after the replication: whether the conflicted anEntry's retry is held
 (permitHeld): the permission is kept for another round (isHold: rounds <= permitRetries), its
 caller retries at once and the permission is still valid. (proto_db also asks that the outcome
 is not unknown; here an unknown outcome always ends the round in _failRound:with:sent:now:effects:
 first, so it never reaches _roundDone:now:effects:.)"
PBCoordinatorCore >> _holds: anEntry hold: isHold valid: isValid in: s
  ^ isHold and: [anEntry willRetry and: [isValid]].

"The round ended without an error (its root committed, or it built nothing): each conflicted
 entry gets its conflict, permitHeld when its retry is held (_holds:hold:valid:in:). Then
 proto_db _run_round's loop: no conflict, permitRetries rounds run or the permission no longer
 valid end the permission; otherwise it is kept for the retries."
PBCoordinatorCore >> _roundDone: s now: t effects: fx
  | hold valid callers state |
  hold := s rounds <= s config permitRetries.
  valid := s permission isValidAt: t.
  callers := OrderedCollection new.
  s conflicted do: [:c |
    (self _holds: c first hold: hold valid: valid in: s)
      ifTrue: [
        (callers includes: c first caller) ifFalse: [callers add: c first caller].
        fx add: (PBSettle waiter: c first token outcome: (PBConflictError held: (c last messageText ifNil: [c last class name])))]
      ifFalse: [fx add: (PBSettle waiter: c first token outcome: c last)]].
  state := s with: { #conflicted -> #(). #building -> nil }.
  (s conflicted isEmpty or: [s rounds > s config permitRetries or: [valid not]]) ifTrue: [
    ^ self _endPermission: state now: t effects: fx].
  ^ self _keep: (state with: { #awaiting -> callers asArray. #awaitCount -> s conflicted size })
    hold: (callers isEmpty
      ifTrue: [s config retryWait]
      ifFalse: [(s config retryHold min: (s permission remainingAt: t)) max: s config retryWait])
    now: t effects: fx.

"proto_db _keep and _await_retries: the permission s awaits (its awaiting) is kept for someMicros
 (a PBTimer whose PBHoldExpired ends the wait: max(min(retryHold, the time left), retryWait) for
 held retries, retryWait for conflicts nobody retries at once) for the retries of the round's conflicts; once
 they are queued (_retriesIn:), the next round under it takes the whole queue."
PBCoordinatorCore >> _keep: s hold: someMicros now: t effects: fx
  | token state |
  token := { #hold. s nextToken }.
  state := s with: { #phase -> #held. #holdToken -> token. #nextToken -> (s nextToken + 1) }.
  fx add: (PBTimer after: someMicros token: token event: (PBHoldExpired token: token)).
  (self _retriesIn: state) ifFalse: [^ state].
  ^ self _takeKept: state now: t effects: fx.

"The hold timer of a permission still kept under its token: the wait ends (proto_db
 _await_retries' deadline: what queued runs the next round; _keep's expire: nothing queued, the
 permission ends)."
PBCoordinatorCore >> roundHoldExpired: anEvent in: s now: t
  ^ self _step: [:fx |
    (s phase = #held and: [anEvent token = s holdToken])
      ifTrue: [self _endWait: s now: t effects: fx]
      ifFalse: [s]].

"proto_db _drop_kept: a held caller will not retry. The kept permission no longer waits for it;
 waiting for no one, the wait ends. A caller not awaited changes nothing."
PBCoordinatorCore >> roundDropKept: anEvent in: s now: t
  ^ self _step: [:fx | | state |
    (s phase = #held and: [s awaiting includes: anEvent caller])
      ifTrue: [
        state := s with: { #awaiting -> (s awaiting copyWithout: anEvent caller) }.
        (state awaiting isEmpty or: [self _retriesIn: state])
          ifTrue: [self _endWait: state now: t effects: fx]
          ifFalse: [state]]
      ifFalse: [s]].

"The wait of a kept permission ends: the commits queued run the next round under it; none, the
 permission ends."
PBCoordinatorCore >> _endWait: s now: t effects: fx
  s queue isEmpty ifTrue: [^ self _endPermission: s now: t effects: fx].
  ^ self _takeKept: s now: t effects: fx.

"proto_db _end_permission (finish): the permission ends with its outcome and the root committed
 under it (PBReportDone, the node's done); a queue that formed asks for the next permission. A
 permission that ends any other way than stale ends the stale run (proto_db: stale = 0). The
 shell performs the PBReportDone before the PBAskPermit that may follow it in the same step, and
 must not issue that permit before the done has freed the node's permission (R148)."
PBCoordinatorCore >> _endPermission: s now: t effects: fx
  fx add: (PBReportDone permission: s permission outcome: s outcome
    root: (s outcome = #committed ifTrue: [s committed] ifFalse: [nil])).
  ^ self _askPermit: (s with: { #phase -> #idle. #permission -> nil. #outcome -> #none. #committed -> nil. #base -> nil.
    #current -> nil. #rounds -> 0. #awaiting -> #(). #awaitCount -> 0. #stale -> 0. #holdToken -> nil. #built -> #(). #conflicted -> #(). #live -> #(). #building -> nil.
    #longest -> 0. #tried -> 0 }) effects: fx.
