"-- cluster/holder.st: the base choice, the holder's replication and the commit point --

The holder side of a commit round of proto_db's ClusterCoordinator (cluster/coordinator.py at
v2.0.0rc3: replicate over a storage shared by every node, the ack branch of _on_answer, and the
dispatcher's half of _learn_label) as rule methods of PBCoordinatorCore over the values of
lease.st, core.st, proposer.st, owner.st and this module, at DEPTH 0 (CC7: no gate, no store,
no proposal). Nothing here reads a clock: t is the node's clock (CC3).

  dispatchReplicateWanted:in:now: (proto_db replicate, CP 1.7 steps 6-9). A permission that is no
    longer valid, or has less than sendReserve left (R121), sends nothing: the waiter gets #none
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
    that is not the committed root this node knows needs a commit first (R50) and is probed
    (PBProbeRoot); an unreadable one is #unreachable (R133). An #ok base is bound to its
    permission.
  The pred (proto_db replicate: lease.sent, else the lease root, which bind_root sets to the
    base): the holder keeps, per permission held, the base bound and the root last sent
    (PBHolder permits), and dispatchReplicateWanted: refuses a pred other than predFor:in:
    (PBValidationError): acceptors trust the pred, so a wrong one is never sent. The record is
    forgotten when the permission's done report is made (owner.st dispatchDoneReport:).

Not here: the rejoin ballot's refusal to replicate below it (L14, Task 16), bounded
replication, copies and the gate (Phase D).

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
    ((p isValidAt: t) and: [(p remainingAt: t) >= c sendReserve])
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
 label answers cleared), else unknown (the root left this node: counted, the node suspect for
 its term, its acceptor too)."
PBCoordinatorCore >> _endReplication: aReplication committed: isCommitted in: s effects: fx
  | state label |
  state := self _replaceReplication: aReplication with: nil in: s.
  label := aReplication root label.
  isCommitted ifTrue: [
    fx add: (PBToAcceptor event: (PBLearnCommitted root: aReplication root accept: true logged: true)).
    state := state with: { #suspectTerm -> (self _learnLabel: label clears: state suspectTerm) }.
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

"The record { { term. seq }. bound. sent } of aPermission in s, nil when none."
PBCoordinatorCore >> _permitRecord: aPermission in: s
  | key |
  key := { aPermission term. aPermission seq }.
  ^ (self _holderIn: s) permits detect: [:e | e first = key] ifNone: [nil].

"s with the record of aPermission replaced by { key. aBound. aSent }; at most permitsSeenLimit
 records are kept (the oldest go first)."
PBCoordinatorCore >> _permit: aPermission bound: aBound sent: aSent in: s
  | h key list |
  h := self _holderIn: s.
  key := { aPermission term. aPermission seq }.
  list := (h permits reject: [:e | e first = key]) copyWith: { key. aBound. aSent }.
  list size > PBHolder permitsSeenLimit ifTrue: [list := list copyFrom: list size - PBHolder permitsSeenLimit + 1 to: list size].
  ^ s with: { #holder -> (h with: { #permits -> list }) }.

"s with aRoot bound as the base of aPermission (proto_db _permit_round: permission.bind_root,
 which also makes the base certain for a later round under it); what was sent is kept."
PBCoordinatorCore >> _bind: aPermission base: aRoot in: s
  | e |
  e := self _permitRecord: aPermission in: s.
  ^ self _permit: aPermission bound: aRoot sent: (e isNil ifTrue: [nil] ifFalse: [e last]) in: s.

"s with aRoot recorded as the root last sent under aPermission (proto_db replicate, lease.sent =
 (label, root) at the send; nothing is recorded when nothing acceptable left the node)."
PBCoordinatorCore >> _sent: aRoot under: aPermission in: s
  | e |
  e := self _permitRecord: aPermission in: s.
  ^ self _permit: aPermission bound: (e isNil ifTrue: [nil] ifFalse: [e at: 2]) sent: aRoot in: s.

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
  (e notNil and: [e last notNil]) ifTrue: [^ e last].
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
    choice := PBBaseChoice waiter: aWaiter permission: aPermission every: false.
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
 #stale (the acquisition learnt the label; the next term is above it); a base that is not the
 committed root this node knows needs a commit first (R50), and when it is not the empty space
 its SpaceRoot is probed first (R133)."
PBCoordinatorCore >> _finishBase: aChoice in: s now: t effects: fx
  | base committed needs |
  base := aChoice current.
  base label > aChoice permission term ifTrue: [^ self _stale: aChoice in: s effects: fx].
  committed := self _committedFor: aChoice in: s.
  needs := self _needsCommit: base committed: committed.
  (needs and: [base record notNil]) ifTrue: [^ self _probe: aChoice in: s effects: fx].
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
