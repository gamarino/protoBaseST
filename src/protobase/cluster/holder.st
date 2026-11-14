"-- cluster/holder.st: the holder's replication and the commit point --

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

The root of a later round under the same permission is built on the root sent before
(proto_db lease.sent): the round passes it as the event's pred (Task 15), as it passes the base
for the first one. Not here: the rejoin ballot's refusal to replicate below it (L14, Task 16),
bounded replication, copies and the gate (Phase D).

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
        state := self _replaceReplication: rep with: rep in: pair first.
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
  "Only a voter's answer decides the root (D54)."
  (self _countsAck: aMessage in: s) ifFalse: [^ s].
  "The hint rises only from an ack that answers this replication (proto_db _on_answer)."
  h := self _hintsIn: s.
  root := PBClusterMessage rootFrom: (aMessage at: 'root').
  state := root isNil ifTrue: [s] ifFalse: [s with: { #hints -> (h with: { #hint -> (h hint max: root label) }) }].
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
