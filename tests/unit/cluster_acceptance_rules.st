"EXPECT: ok 28"
"The acceptance rules (cluster/acceptor.st) and the holder's replication and commit point
 (cluster/holder.st) called directly, one guard per check (proto_db coordinator.py _may_accept,
 _apply_replicate, _refuse_queued, _on_done, _on_release, _observe_accepted, _observe_committed,
 _learn_label, _attach_locked, replicate, _on_answer, _on_reply, _permission_from_owner).
 (1-7) The chain rule, proto_db test_cluster_chain_rule's seven tests: a root extending the
 accepted root is accepted (and a duplicate); a sibling is refused, and a root built on it; a
 root not built on the accepted root is refused until its pred is learnt committed; a later
 root of a term never follows an accepted root of an older term; a node that accepted nothing
 takes only the first root of a term; a stale permission seq is refused; the first root of a
 newer term follows the ballot rule only. (8) The ballot rule: a root of a term below one
 granted here is refused. (9) A replicate whose root is unknown, the empty space, labelled
 with another term or sent in chunks is refused; a learner, a rejoining node, a failed tier
 refuse; a fenced node acks false. (10) An accepted replicate appends one synced #accepted,
 publishes the acceptor and the committed root it teaches, counts accepted, acks ok (stored
 false, the accepted root), notes the seq and the label learnt; a refusal acks false, counted
 refused. (11) The own replication is decided by the same rule, answered in the step's vote,
 uncounted, teaching no committed root. (12) A done 'committed' teaches a newer root: appended
 #committed without a sync, published, accepted knowledge; an older one, another outcome or a
 fenced node teaches nothing. (13) A held release teaches its committed root in proto_db's
 order: the grant it ended taints, the root clears that, an uncertain release taints again; the
 own release teaches nothing. (14) PBLearnCommitted: accepted knowledge or not, appended or not,
 nothing appended on a failed tier, nothing learnt when fenced. (15) A suspicion is cleared only by a label at or above it.
 (16) A log restored: the accepted root is the higher of the logged accepted and committed
 roots. (17) A holder sends nothing past its permission or under the send reserve (#none); else
 the replicate to the other voters, its own acceptance and a timer at the permission's end;
 a learner holder has no own acceptance; with a reserve of 0 still nothing past the
 permission; a root not labelled with the permission's term is refused. (18) The replication is decided only after its own
 acceptance answered; a majority of acks commits it, teaching the own acceptor the root
 (logged) and clearing a suspicion it answers. (19) A majority observed past the permission is
 unknown: counted, suspect, PBSuspect; so is its timer, and a failed own acceptance at once.
 (20) More refusals than a majority allows end it unknown at once; the holder's own refusal
 is neither an ack nor a refusal (proto_db). The timer decides only once the own acceptance
 answered. (21, two checks) Acks
 of another incarnation are dropped, of another term ignored, a duplicate counted once; a
 learner's never counts, though a matching one raises the hint. (22) A step's learnt label clears the dispatcher's suspicion at or below it and
 raises the hint. (23) A certain permit, remote or local, teaches its base committed (not
 logged); a grant's committed root is committed knowledge only. (24) A replicate notes the
 owner hint and goes to the acceptor lane; one of another voter set is dropped and counted; a
 store never reaches the acceptor (V1)."
Import from: 'protobase'.
Import from: '_check'.

| c core peers config three five marker logged acceptorOf T OLD rec accept node r1 r2 r3 base sibling k k1 old newer
  vs msg repl step ackOf counts s granted nodeOf perm view eff toAcc settled t0 rep holderOf learn s2 v own stats
  timers hintAck done unknown late few refused ownFailed |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :someIds | PBClusterConfig nodeId: id peers: (peers value: someIds) options: (Dictionary new at: #startupGrace put: 0; yourself)].
three := #('n0' 'n1' 'n2').
five := #('n0' 'n1' 'n2' 'n3' 'n4').
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:a | a payload]) path: 'test'].
acceptorOf := [:id :someIds :appends | PBAcceptorState config: (config value: id value: someIds) logged: (logged value: appends) now: 0].
T := 5 * 4096.
OLD := 4 * 4096.
"proto_db rec(epoch): a root of epoch e (its own offset), labelled aLabel."
rec := [:aLabel :e | PBLabeledRoot label: aLabel record: (PBRootRecord segment: (ByteArray new: 16) offset: 64 + e epoch: e)].
"proto_db test_cluster_chain_rule _accept: decided by _mayAccept:, adopted when ok."
node := nil.
accept := [:label :root :pred :seq | | ok |
  ok := core _mayAccept: root term: label pred: pred seq: seq in: node.
  ok ifTrue: [node := node with: { #accepted -> root. #seqSeen -> (core _seqSeen: node seqSeen after: label seq: seq) }].
  ok].
base := rec value: OLD value: 9.

"(1-7) The chain rule."
node := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10. r2 := rec value: T value: 11.
c that: 'a root extending the accepted root is accepted, and a duplicate'
  is: { accept value: T value: r1 value: base value: 1. accept value: T value: r2 value: r1 value: 1. accept value: T value: r2 value: r1 value: 1 }
  equals: #(true true true).
node := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10. r2 := rec value: T value: 11.
sibling := PBLabeledRoot label: T record: (PBRootRecord segment: (ByteArray new: 16) offset: 999 epoch: 11).
c that: 'a sibling in the same term is refused without a protocol violation, and a root built on it'
  is: { accept value: T value: r1 value: base value: 1. accept value: T value: r2 value: r1 value: 2.
    accept value: T value: sibling value: r1 value: 3. accept value: T value: (rec value: T value: 12) value: sibling value: 3 }
  equals: #(true true false false).
node := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10. r2 := rec value: T value: 11. r3 := rec value: T value: 12.
c that: 'a root not built on the accepted root is refused until its pred is learnt committed'
  is: { accept value: T value: r1 value: base value: 1. accept value: T value: r3 value: r2 value: 2.
    [node := (core _observeCommitted: r2 accept: true in: node) first. node accepted key = r2 key] value.
    accept value: T value: r3 value: r2 value: 2 }
  equals: #(true false true true).
node := acceptorOf value: 'n1' value: three value: { marker }.
old := rec value: OLD value: 10. k := rec value: T value: 11. k1 := rec value: T value: 12.
c that: 'a later root of a term never follows an accepted root of an older term'
  is: { accept value: OLD value: old value: (rec value: OLD - 4096 value: 8) value: 3. accept value: T value: k1 value: k value: 2.
    accept value: T value: k value: old value: 1. accept value: T value: k1 value: k value: 2 }
  equals: #(true false true true).
node := acceptorOf value: 'n1' value: three value: { marker }.
k := rec value: T value: 11. k1 := rec value: T value: 12.
c that: 'a node that accepted nothing takes only the first root of a term'
  is: { accept value: T value: k1 value: k value: 2. accept value: T value: k1 value: nil value: 2.
    accept value: T value: k value: (PBLabeledRoot label: 0 record: nil) value: 1 }
  equals: #(false false true).
node := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10. r2 := rec value: T value: 11. r3 := rec value: T value: 12.
c that: 'a stale permission sequence is refused'
  is: { accept value: T value: r1 value: base value: 1. accept value: T value: r2 value: r1 value: 3. accept value: T value: r3 value: r2 value: 2 }
  equals: #(true true false).
node := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10.
newer := T + 4096.
c that: 'the first root of a newer term follows the ballot rule only'
  is: { accept value: T value: r1 value: base value: 7. accept value: newer value: (rec value: newer value: 11) value: (rec value: T value: 10) value: 1.
    accept value: newer + 4096 value: (rec value: newer + 4096 value: 13) value: (rec value: newer + 4096 value: 12) value: 1.
    accept value: T value: (rec value: T value: 12) value: r1 value: 8 }
  equals: #(true true false false).

"(8) The ballot rule."
vs := (config value: 'n1' value: three) membership fingerprint.
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
granted := (core accept: (msg value: 'request' value: 'n2' value: { 'term' -> (T + 2). 'rid' -> 1. 'inc' -> 1. 'vs' -> vs })
  in: (acceptorOf value: 'n1' value: three value: { marker }) now: 1000) state.
c that: 'a root of a term below one granted here is refused (the ballot rule)'
  is: { core _mayAccept: (rec value: T value: 10) term: T pred: base seq: 1 in: granted.
    core _mayAccept: (rec value: T + 2 value: 10) term: T + 2 pred: base seq: 1 in: granted }
  equals: #(false true).

"(9) Validity and the refusals of the acceptor's state."
repl := [:from :term :root :pred :fields | | d |
  d := OrderedCollection new.
  d addAll: { 'term' -> term. 'rid' -> 7. 'inc' -> 3. 'root' -> (PBClusterMessage rootValue: root). 'committed' -> nil.
    'records' -> #(). 'chunks' -> 0. 'base' -> nil. 'base_ranges' -> nil. 'seq' -> 1. 'pred' -> (PBClusterMessage rootValue: pred).
    'vs' -> vs. 'copies' -> { from }. 'ranges' -> nil }.
  fields do: [:a | d := d reject: [:e | e key = a key]. d add: a].
  msg value: 'replicate' value: from value: d asArray].
ackOf := [:aStep | | sends | sends := (aStep reply select: [:e | (e isKindOf: PBSend) and: [e message type = 'ack']]) collect: [:e | e message].
  sends isEmpty ifTrue: [aStep vote] ifFalse: [sends first]].
counts := [:aStep | (aStep reply select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]].
s := acceptorOf value: 'n1' value: three value: { marker }.
r1 := rec value: T value: 10.
c that: 'a replicate of an unknown root, the empty space, another label or chunks is refused, counted, acked false'
  is: ({ repl value: 'n0' value: T value: nil value: base value: #().
      repl value: 'n0' value: T value: (PBLabeledRoot label: T record: nil) value: base value: #().
      repl value: 'n0' value: T value: (rec value: T + 1 value: 10) value: base value: #().
      repl value: 'n0' value: T value: r1 value: base value: { 'chunks' -> 1 } } collect: [:m | | st |
    st := core accept: m in: s now: 1000.
    { st appends size. (ackOf value: st) at: 'ok'. counts value: st } ])
  , ({ acceptorOf value: 'n3' value: five value: { marker }. acceptorOf value: 'n1' value: three value: #().
      s withGrants: s grants suspectTerm: 0 rejoined: true tierFailed: 'disk' loggedPromise: 0 } collect: [:st0 |
    (ackOf value: (core accept: (repl value: 'n0' value: T value: r1 value: base value: #()) in: st0 now: 1000)) at: 'ok'])
  , { [ | f | f := PBAcceptorState basicNew _setConfig: s config grants: s grants accepted: nil committed: nil seqSeen: #(0 0)
        suspectTerm: 0 rejoined: true rejoinBallot: 0 tierFailed: nil fenced: 'fenced' log: s log loggedPromise: { s log. 0 }.
      step := core accept: (repl value: 'n0' value: T value: r1 value: base value: #()) in: f now: 1000.
      { step appends size. (ackOf value: step) at: 'ok' } ] value }
  equals: { #(0 false #('refused')). #(0 false #('refused')). #(0 false #('refused')). #(0 false #('refused')). false. false. false. #(0 false) }.

"(10) An accepted replicate."
r2 := rec value: OLD value: 5.
step := core accept: (repl value: 'n0' value: T value: r1 value: base value: { 'committed' -> (PBClusterMessage rootValue: r2). 'seq' -> 4 })
  in: s now: 1000.
c that: 'an accepted replicate: one synced append, published, counted, acked ok with its root; seq and label noted'
  is: { step appends collect: [:a | { a kind. a label. a sync }]. step reply collect: [:e | e class name].
    ((ackOf value: step) at: 'ok'). ((ackOf value: step) at: 'stored'). (PBClusterMessage rootFrom: ((ackOf value: step) at: 'root')) key = r1 key.
    step state accepted key = r1 key. step state committed key = r2 key. step state seqSeen. step learnt.
    (step reply detect: [:e | e isKindOf: PBSend]) to }
  equals: { { { #accepted. T. true } }. #(#PBPublishAcceptor #PBPublishCommitted #PBCount #PBSend). true. false. true. true. true.
    { T. 4 }. T. 'n0' }.

"(11) The own replication."
step := core accept: (repl value: 'n1' value: T value: r1 value: base value: { 'committed' -> (PBClusterMessage rootValue: r2) }) in: s now: 1000.
c that: 'the own replication is decided by the same rule, synced, answered in the vote, uncounted, teaching no committed root'
  is: { step appends collect: [:a | { a kind. a sync }]. (step reply select: [:e | (e isKindOf: PBSend) or: [e isKindOf: PBCount]]) size. step vote type. step vote at: 'ok'.
    step state committed. (core accept: (repl value: 'n1' value: T value: (rec value: T + 1 value: 10) value: base value: #()) in: s now: 1000) vote at: 'ok' }
  equals: #(#(#(#accepted true)) 0 'ack' true nil false).

"(12) A done."
learn := [:aStep | { aStep appends collect: [:a | { a kind. a sync }]. (aStep reply collect: [:e | e class name]).
  aStep state committed isNil ifTrue: [nil] ifFalse: [aStep state committed key = r1 key]. aStep state accepted isNil ifTrue: [nil] ifFalse: [aStep state accepted key = r1 key]. aStep learnt }].
step := [:outcome :root :st | core accept: (msg value: 'done' value: 'n0' value: { 'term' -> T. 'seq' -> 1. 'inc' -> 3. 'outcome' -> outcome.
  'root' -> (PBClusterMessage rootValue: root). 'copies' -> #(). 'ranges' -> nil }) in: st now: 1000].
s2 := (core _observeCommitted: (rec value: T value: 11) accept: true in: s) first.
c that: 'a done committed teaches a newer root, unsynced; an older one, another outcome or a fenced node nothing'
  is: { learn value: (step value: 'committed' value: r1 value: s). (step value: 'committed' value: r1 value: s2) appends size.
    (step value: 'unknown' value: r1 value: s) appends size.
    (step value: 'committed' value: r1 value: (PBAcceptorState basicNew _setConfig: s config grants: s grants accepted: nil committed: nil
      seqSeen: #(0 0) suspectTerm: 0 rejoined: true rejoinBallot: 0 tierFailed: nil fenced: 'x' log: s log loggedPromise: { s log. 0 })) appends size }
  equals: { { { { #committed. false } }. #(#PBPublishCommitted). true. true. T }. 0. 0. 0 }.

"(13) A held release."
s2 := (core accept: (msg value: 'request' value: 'n2' value: { 'term' -> 4098. 'rid' -> 1. 'inc' -> 1. 'vs' -> vs }) in: s now: 1000) state.
step := [:term :certain :committed :from | core accept: (msg value: 'release' value: from value: { 'term' -> term. 'inc' -> 9. 'root' -> nil.
  'committed' -> (PBClusterMessage rootValue: committed). 'certain' -> certain. 'held' -> true. 'next' -> nil. 'more' -> false })
  in: s2 now: 1000 + 10000000].
c that: 'a held release teaches its committed root after the ended grant taints, an uncertain one taints again; the own teaches nothing'
  is: { (step value: 4096 value: true value: (rec value: 4098 value: 3) value: 'n0') state suspectTerm.
    (step value: 4096 value: true value: (rec value: 4097 value: 3) value: 'n0') state suspectTerm.
    (step value: 4100 value: false value: (rec value: 4098 value: 3) value: 'n0') state suspectTerm.
    [ | st | st := step value: 4096 value: true value: (rec value: 4098 value: 3) value: 'n0'.
      { st appends collect: [:a | { a kind. a sync }]. st state committed label. st state accepted label. st learnt } ] value.
    (step value: 4096 value: true value: (rec value: 4098 value: 3) value: 'n1') state committed }
  equals: { 0. 4098. 4100. { { { #committed. false } }. 4098. 4098. 4098 }. nil }.

"(14) PBLearnCommitted."
learn := [:root :acc :log :st | core accept: (PBLearnCommitted root: root accept: acc logged: log) in: st now: 1000].
c that: 'learning committed: accepted knowledge or not, appended or not, nothing appended on a failed tier, nothing learnt when fenced'
  is: { [ | st | st := learn value: r1 value: false value: false value: s. { st appends size. st state committed key = r1 key. st state accepted. st learnt } ] value.
    [ | st | st := learn value: r1 value: true value: true value: s. { st appends size. st state accepted key = r1 key } ] value.
    [ | st | st := learn value: r1 value: true value: true value: (s withGrants: s grants suspectTerm: 0 rejoined: true tierFailed: 'disk' loggedPromise: 0).
      { st appends size. st state committed key = r1 key. st reply size } ] value.
    [ | st | st := learn value: r1 value: true value: true value: (PBAcceptorState basicNew _setConfig: s config grants: s grants
        accepted: nil committed: nil seqSeen: #(0 0) suspectTerm: 0 rejoined: true rejoinBallot: 0 tierFailed: nil fenced: 'x'
        log: s log loggedPromise: { s log. 0 }).
      { st appends size. st state committed. st reply size } ] value }
  equals: { { 0. true. nil. T }. #(1 true). #(0 true 1). #(0 nil 0) }.

"(15) A suspicion."
s2 := core accept: (PBSuspect term: T) in: s now: 1000.
c that: 'a suspicion is cleared only by a label at or above it'
  is: { (learn value: (rec value: T - 1 value: 3) value: true value: false value: s2 state) state suspectTerm.
    (learn value: (rec value: T value: 3) value: false value: false value: s2 state) state suspectTerm.
    (learn value: (rec value: T + 1 value: 3) value: true value: false value: s2 state) state suspectTerm.
    core _learnLabel: 5 clears: 0 }
  equals: { T. 0. 0. 0 }.

"(16) A log restored."
c that: 'a restored acceptor accepts the higher of its logged accepted and committed roots'
  is: { (acceptorOf value: 'n1' value: three value: { marker. PBLogAppend kind: #accepted label: 4096 root: (rec value: 4096 value: 2) record sync: true.
      PBLogAppend kind: #committed label: 8192 root: (rec value: 8192 value: 3) record sync: false }) accepted label.
    (acceptorOf value: 'n1' value: three value: { marker. PBLogAppend kind: #accepted label: 8192 root: (rec value: 8192 value: 4) record sync: true.
      PBLogAppend kind: #committed label: 4096 root: (rec value: 4096 value: 3) record sync: false }) accepted epoch }
  equals: #(8192 4).

"(17) Sending."
t0 := 1000000.
view := acceptorOf value: 'n0' value: three value: { marker. PBLogAppend kind: #committed label: OLD root: base record sync: false }.
nodeOf := [:id :someIds | (PBNodeState config: (config value: id value: someIds) inc: 5) with: { #acceptorView -> view }].
perm := [:valid | PBPermission term: T seq: 3 rid: 9 owner: 'n0' root: base certain: true sentAt: t0 valid: valid].
eff := [:aStep | aStep effects collect: [:e | e class name]].
toAcc := [:aStep | (aStep effects select: [:e | e isKindOf: PBToAcceptor]) collect: [:e | e event]].
settled := [:aStep | (aStep effects select: [:e | e isKindOf: PBSettle]) collect: [:e | e outcome]].
"From here an unknown replication's settle is shown as its PBOutcomeUnknownError's exact text."
settled := [:aStep | (aStep effects select: [:e | e isKindOf: PBSettle]) collect: [:e |
  (e outcome isKindOf: PBOutcomeUnknownError) ifTrue: [e outcome messageText] ifFalse: [e outcome]]].
"proto_db's text of an unknown outcome at n0 for r1 (epoch 10), coordinator.py replicate."
unknown := [:why | 'Node n0: ' , why , '; the root (epoch 10) may or may not take effect'].
late := [:n | unknown value: 'the lease ended before this node observed the outcome (' , n printString
  , ' acknowledgements, 2 needed, were counted only after the lease had ended)'].
few := [:n | unknown value: 'only ' , n printString , ' of the 2 acknowledgements needed arrived before the lease ended'].
refused := [:n :m | unknown value: n printString , ' members refused the root, and only ' , m printString
  , ' of the 2 acknowledgements needed arrived'].
ownFailed := 'Node n0: the commit of root epoch 10 failed after the root was sent (its own acceptance could not be made '
  , 'durable); peers may have acknowledged it, so it may or may not take effect'.
step := [:p :id :someIds :t | core dispatch: (PBReplicateWanted permission: p root: r1 pred: base waiter: #w) in: (nodeOf value: id value: someIds) now: t].
c that: 'nothing is sent past the permission (a reserve of 0 too) or under the reserve; else the replicate, the own acceptance and a timer; a root of another term is refused'
  is: { settled value: (step value: (perm value: 500000) value: 'n0' value: three value: t0 + 500000).
    settled value: (step value: (perm value: 500000) value: 'n0' value: three value: t0 + 500000 - (config value: 'n0' value: three) sendReserve + 1).
    [ | st m | st := step value: (perm value: 500000) value: 'n0' value: three value: t0 + 1000.
      m := (st effects detect: [:e | e isKindOf: PBSend]) message.
      { eff value: st. (st effects select: [:e | e isKindOf: PBSend]) collect: [:e | e to].
        (st effects detect: [:e | e isKindOf: PBTimer]) after. m at: 'seq'. (PBClusterMessage rootFrom: (m at: 'pred')) key = base key.
        (PBClusterMessage rootFrom: (m at: 'committed')) key = base key. m at: 'copies'. m at: 'chunks'. (m at: 'vs') = vs.
        (toAcc value: st) first message type } ] value.
    (toAcc value: (step value: (perm value: 500000) value: 'n3' value: five value: t0 + 1000)) size.
    settled value: (core dispatch: (PBReplicateWanted permission: (perm value: 500000) root: r1 pred: base waiter: #w)
      in: ((PBNodeState config: (PBClusterConfig nodeId: 'n0' peers: (peers value: three)
          options: (Dictionary new at: #startupGrace put: 0; at: #sendReserve put: 0; yourself)) inc: 5) with: { #acceptorView -> view })
      now: t0 + 500000).
    [core dispatch: (PBReplicateWanted permission: (perm value: 500000) root: (rec value: T + 1 value: 10) pred: base waiter: #w)
      in: (nodeOf value: 'n0' value: three) now: t0 + 1000. #sent] on: PBValidationError do: [:e | #refused] }
  equals: { #(#none). #(#none). { #(#PBCount #PBSend #PBSend #PBToAcceptor #PBTimer). #('n1' 'n2'). 499000. 3. true. true. #('n0'). 0. true. 'replicate' }. 0.
    #(#none). #refused }.

"(18) The commit point."
s := (step value: (perm value: 500000) value: 'n0' value: three value: t0 + 1000) state.
rep := [:st | st holder replications first].
ackOf := [:from :ok :term :inc :rid | msg value: 'ack' value: from value: { 'term' -> term. 'rid' -> rid. 'inc' -> inc. 'ok' -> ok.
  'root' -> (PBClusterMessage rootValue: r1). 'stored' -> false }].
v := [:st :from :ok :t | core dispatch: (ackOf value: from value: ok value: T value: 5 value: (rep value: st) rid) in: st now: t].
own := [:st :ok :t | core dispatch: (PBAcceptorDecided step: (PBAcceptorStep state: view appends: #() reply: #()
  vote: (PBClusterMessage type: 'ack' from: 'n0' fields: { 'term' -> T. 'rid' -> (rep value: st) rid. 'inc' -> 5. 'ok' -> ok.
    'root' -> nil. 'stored' -> false }))) in: st now: t].
s2 := (v value: (v value: s value: 'n1' value: true value: t0 + 2000) state value: 'n2' value: true value: t0 + 3000).
step := own value: (s2 state with: { #suspectTerm -> T }) value: true value: t0 + 4000.
c that: 'decided only after its own acceptance; a majority commits, teaching the own acceptor and clearing the suspicion'
  is: { settled value: s2. s2 state holder replications size. settled value: step. step state holder replications size.
    (toAcc value: step) collect: [:e | { e class name. e isLogged. e isAccepted }]. step state suspectTerm }
  equals: { #(). 1. #(#committed). 0. { { #PBLearnCommitted. true. true } }. 0 }.

"(19) Unknown outcomes."
step := own value: (v value: (v value: s value: 'n1' value: true value: t0 + 2000) state value: 'n2' value: true value: t0 + 600000) state
  value: true value: t0 + 600000.
timers := [:aStep | { settled value: aStep. (aStep effects select: [:e | e isKindOf: PBTimer]) collect: [:e | e after] }].
c that: 'a majority observed past the permission, its timer (once the own acceptance answered; re-armed when early), a failed own acceptance: unknown, counted, suspect'
  is: { settled value: step. (step effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]. step state suspectTerm.
    (toAcc value: step) collect: [:e | e class name asSymbol].
    settled value: (core dispatch: (PBTimerFired token: (rep value: s) token event: #replicate) in: (own value: s value: true value: t0 + 2000) state now: t0 + 500000).
    timers value: (core dispatch: (PBTimerFired token: (rep value: s) token event: #replicate) in: (own value: s value: true value: t0 + 2000) state now: t0 + 400000).
    timers value: (core dispatch: (PBTimerFired token: (rep value: s) token event: #replicate) in: s now: t0 + 400000).
    settled value: (core dispatch: (PBTimerFired token: (rep value: s) token event: #replicate) in: s now: t0 + 500000).
    settled value: (core dispatch: (PBAcceptorDiscarded step: (PBAcceptorStep state: view appends: #() reply: #()
      vote: (PBClusterMessage type: 'ack' from: 'n0' fields: { 'term' -> T. 'rid' -> (rep value: s) rid. 'inc' -> 5. 'ok' -> true.
        'root' -> nil. 'stored' -> false }))) in: (v value: (v value: s value: 'n1' value: true value: t0 + 2000) state value: 'n2' value: true value: t0 + 3000) state now: t0 + 4000) }
  equals: { { late value: 3 }. #('replication_failures'). T. #(#PBSuspect). { few value: 1 }. { #(). #(100000) }. { #(). #(100000) }. #().
    { ownFailed } }.

"(20) Refusals."
c that: 'more refusals than a majority allows end it unknown at once; an own refusal is neither (proto_db), peers alone can commit'
  is: { settled value: (v value: (own value: s value: true value: t0 + 2000) state value: 'n1' value: false value: t0 + 3000).
    settled value: (v value: (v value: (own value: s value: true value: t0 + 2000) state value: 'n1' value: false value: t0 + 3000) state
      value: 'n2' value: false value: t0 + 4000).
    settled value: (v value: (own value: s value: false value: t0 + 2000) state value: 'n1' value: false value: t0 + 3000).
    settled value: (v value: (v value: (own value: s value: false value: t0 + 2000) state value: 'n1' value: false value: t0 + 3000) state
      value: 'n2' value: false value: t0 + 4000).
    settled value: (v value: (v value: (own value: s value: false value: t0 + 2000) state value: 'n1' value: true value: t0 + 3000) state
      value: 'n2' value: true value: t0 + 4000) }
  equals: { #(). { refused value: 2 value: 1 }. #(). { refused value: 2 value: 0 }. #(#committed) }.

"(20b, 20c) proto_db test_cluster_rejoin_records.py M2 (re-review 4): a majority counted only
 after the permission ended is reported as such, never as too few acknowledgements; too few
 acknowledgements are still reported as too few. The round's error is the replication's."
c that: 'a majority counted after the lease ended is reported as such'
  is: [ | st text | st := v value: (own value: s value: true value: t0 + 2000) state value: 'n1' value: true value: t0 + 600000.
    text := (settled value: st) first.
    { text. (text includesSubstring: 'lease ended before') and: [text includesSubstring: 'observed'].
      text includesSubstring: 'acknowledgements needed arrived'. st state holder replications size } ] value
  equals: { late value: 2. true. false. 0 }.
c that: 'too few acknowledgements are still reported as too few'
  is: [ | text | text := (settled value: (core dispatch: (PBTimerFired token: (rep value: s) token event: #replicate)
      in: (own value: s value: true value: t0 + 2000) state now: t0 + 500000)) first.
    { text. text includesSubstring: 'only 1 of the 2 acknowledgements needed' } ] value
  equals: { few value: 1. true }.

"(21) Ack filters."
s2 := (own value: s value: true value: t0 + 2000) state.
hintAck := [:rid :term | core dispatch: (msg value: 'ack' value: 'n1' value: { 'term' -> term. 'rid' -> rid. 'inc' -> 5. 'ok' -> false.
  'root' -> (PBClusterMessage rootValue: (rec value: T + 50 value: 40)). 'stored' -> false }) in: s2 now: t0 + 3000].
c that: 'acks of another incarnation are dropped, of another term ignored, a duplicate counted once; only an ack answering the replication raises the hint'
  is: { [ | st | st := core dispatch: (ackOf value: 'n1' value: true value: T value: 6 value: (rep value: s2) rid) in: s2 now: t0 + 3000.
      { settled value: st. (st effects select: [:e | e isKindOf: PBCount]) collect: [:e | e stat] } ] value.
    settled value: (core dispatch: (ackOf value: 'n1' value: true value: T + 1 value: 5 value: (rep value: s2) rid) in: s2 now: t0 + 3000).
    (rep value: (v value: (v value: s value: 'n1' value: true value: t0 + 2000) state value: 'n1' value: true value: t0 + 2500) state) acks.
    (core _hintsIn: (hintAck value: (rep value: s2) rid + 99 value: T) state) hint.
    (core _hintsIn: (hintAck value: (rep value: s2) rid value: T + 1) state) hint.
    (hintAck value: (rep value: s2) rid value: T) state hints hint }
  equals: { { #(). #('stale_replies') }. #(). #('n1'). (core _hintsIn: s2) hint. (core _hintsIn: s2) hint. T + 50 }.
holderOf := [:id :someIds | | st |
  st := core dispatch: (PBReplicateWanted permission: (perm value: 500000) root: r1 pred: base waiter: #w)
    in: ((PBNodeState config: (config value: id value: someIds) inc: 5) with: { #acceptorView -> (acceptorOf value: id value: someIds value: { marker }) })
    now: t0 + 1000.
  st state].
s2 := holderOf value: 'n3' value: five.
c that: 'a learner''s ack never counts toward the commit point (D54), but a matching one raises the hint (proto_db)'
  is: { settled value: (core dispatch: (ackOf value: 'n4' value: true value: T value: 5 value: (rep value: s2) rid)
      in: (core dispatch: (ackOf value: 'n0' value: true value: T value: 5 value: (rep value: s2) rid) in: s2 now: t0 + 2000) state now: t0 + 3000).
    settled value: (core dispatch: (ackOf value: 'n1' value: true value: T value: 5 value: (rep value: s2) rid)
      in: (core dispatch: (ackOf value: 'n0' value: true value: T value: 5 value: (rep value: s2) rid) in: s2 now: t0 + 2000) state now: t0 + 3000).
    (core _hintsIn: (core dispatch: (msg value: 'ack' value: 'n4' value: { 'term' -> T. 'rid' -> (rep value: s2) rid. 'inc' -> 5. 'ok' -> true.
      'root' -> (PBClusterMessage rootValue: (rec value: T + 50 value: 40)). 'stored' -> false }) in: s2 now: t0 + 2000) state) hint }
  equals: { #(). #(#committed). T + 50 }.

"Task 18 (proto_db test_a_learners_refusal_never_decides_a_replication): a learner's refusal
 never counts toward the refusals that end a replication either: with n4's refusal and n1's,
 only one voter refused, so the replication runs on and commits at n0 and n2."
c that: 'a learner''s refusal never decides a replication (D54)'
  is: { [ | st |
      st := core dispatch: (ackOf value: 'n4' value: false value: T value: 5 value: (rep value: s2) rid) in: s2 now: t0 + 2000.
      st := core dispatch: (ackOf value: 'n1' value: false value: T value: 5 value: (rep value: s2) rid) in: st state now: t0 + 2100.
      { settled value: st. (rep value: st state) acks.
        settled value: (core dispatch: (ackOf value: 'n2' value: true value: T value: 5 value: (rep value: st state) rid)
          in: (core dispatch: (ackOf value: 'n0' value: true value: T value: 5 value: (rep value: st state) rid) in: st state now: t0 + 2200) state
          now: t0 + 2300) } ] value }
  equals: { { #(). #(). #(#committed) } }.

"(22) The dispatcher's half of _learn_label."
s2 := (nodeOf value: 'n0' value: three) with: { #suspectTerm -> T }.
learn := [:label | core dispatch: (PBAcceptorDecided step: (PBAcceptorStep state: view appends: #() reply: #() vote: nil learnt: label)) in: s2 now: 1000].
c that: 'a learnt label clears the dispatcher''s suspicion at or below it and raises the hint'
  is: { (learn value: T - 1) state suspectTerm. (learn value: T) state suspectTerm. (learn value: T + 7) state hints hint. (learn value: 0) state suspectTerm }
  equals: { T. 0. T + 7. T }.

"(23) Permits and grants."
s2 := (PBNodeState config: (config value: 'n2' value: three) inc: 3) with: {
  #holder -> (PBHolder empty with: { #asks -> { PBPermitAsk waiter: #w rid: 11 sentAt: 0 term: 4097 target: 'n1' request: nil retryAt: 1 endAt: 2 } }) }.
learn := [:certain :root | toAcc value: (core dispatch: (msg value: 'permit' value: 'n1' value: { 'term' -> 4097. 'rid' -> 11. 'seq' -> 1. 'inc' -> 3.
  'root' -> (PBClusterMessage rootValue: root). 'certain' -> certain. 'valid' -> 0.5. 'after' -> nil }) in: s2 now: 1000)].
step := core _step: [:fx | core _observeGrant: (PBClusterMessage type: 'grant' from: 'n1' fields: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 5.
  'root' -> nil. 'committed' -> (PBClusterMessage rootValue: r1). 'certain' -> true }) effects: fx. s2].
c that: 'a certain permit teaches its base committed (not logged); a grant''s committed root is committed knowledge only'
  is: { (learn value: true value: base) collect: [:e | { e class name. e root key = base key. e isAccepted. e isLogged }].
    learn value: false value: base.
    (toAcc value: step) collect: [:e | { e isAccepted. e isLogged }] }
  equals: { { { #PBLearnCommitted. true. true. false } }. #(). #(#(false false)) }.

"(24) The dispatcher."
s2 := nodeOf value: 'n1' value: three.
step := core dispatch: (repl value: 'n0' value: T value: r1 value: base value: #()) in: s2 now: 1000.
done := [:outcome | ((core dispatch: (PBDoneReport permission: (perm value: 500000) outcome: outcome root: r1) in: (nodeOf value: 'n0' value: three) now: t0 + 2000)
  effects detect: [:e | (e isKindOf: PBSend) and: [e message type = 'done']]) message at: 'copies'].
c that: 'a replicate notes the owner and goes to the acceptor; another voter set is dropped and counted; a store never is accepted; a committed done names the holder in copies'
  is: { step state hints ownerTerm. step state hints ownerNode. eff value: step.
    eff value: (core dispatch: (repl value: 'n0' value: T value: r1 value: base value: { 'vs' -> (vs + 1) }) in: s2 now: 1000).
    (stats := (core dispatch: (repl value: 'n0' value: T value: r1 value: base value: { 'vs' -> (vs + 1) }) in: s2 now: 1000) effects first stat).
    eff value: (core dispatch: (msg value: 'store' value: 'n0' value: { 'term' -> T. 'rid' -> 7. 'inc' -> 3. 'root' -> (PBClusterMessage rootValue: r1).
      'records' -> #(). 'chunks' -> 0. 'ranges' -> nil. 'copies' -> #('n0'). 'vs' -> vs }) in: s2 now: 1000).
    (core accept: (msg value: 'store' value: 'n0' value: { 'term' -> T. 'rid' -> 7. 'inc' -> 3. 'root' -> (PBClusterMessage rootValue: r1).
      'records' -> #(). 'chunks' -> 0. 'ranges' -> nil. 'copies' -> #('n0'). 'vs' -> vs }) in: (acceptorOf value: 'n1' value: three value: { marker }) now: 1000) appends size.
    done value: #committed. done value: #unknown }
  equals: { T. 'n0'. #(#PBToAcceptor). #(#PBCount). 'config_mismatches'. #(). 0. #('n0'). #() }.

c report displayNl.
