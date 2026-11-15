"EXPECT: ok 7"
"The detached acceptor (core.st PBAcceptorState config:detachedAt:, attached:, detached,
 withFenced:; acceptor.st): the acceptor of a node with no acceptor log attached, before its
 first attach and after a detach (proto_db coordinator.py _refusal, _decide, _witness_state,
 _attach_locked, detach; Task 20 carry-overs (a) and (b)).
 (1) A peer's request is refused no_storage and counted grants_refused_no_storage; this node's
 own request is refused in its vote, uncounted; a learner is refused learner first. (2) A plain
 query is answered unknown (no root, certain false, promised 0); a ballot query too, with no
 promise. (3) The start appends and publishes nothing (a lone voter's no marker either); a replication is refused (ack ok false,
 counted refused); a committed root learnt is appended to no log. (4) attached: keeps the lease
 activity (the grant running, the terms seen, suspectTerm, seqSeen) and takes the new
 log's roots, marker and promise, the tier failure cleared; over the new log a renewal writes
 its promise again; a second attach is refused. (5) detached drops the log, its promise, its
 marker and its failure and keeps the grants. (6) withFenced: keeps the first reason. (7)
 config:logged:now: is the detached acceptor attached, its grace counted from the start."
Import from: 'protobase'.
Import from: '_check'.

| c core peers config three marker root rec logged vs msg request renew query counted reply
  d s step a b g f |
c := Check new.
core := PBCoordinatorCore new.
peers := [:someIds | (1 to: someIds size) asArray collect: [:i | PBPeer nodeId: (someIds at: i) host: '127.0.0.1' port: 7000 + i]].
config := [:id :someIds | PBClusterConfig nodeId: id peers: (peers value: someIds) options: Dictionary new].
three := #('n0' 'n1' 'n2').
marker := PBLogAppend kind: #rejoined label: 0 root: nil sync: true.
rec := PBRootRecord segment: (ByteArray new: 16) offset: 100 epoch: 1.
root := PBLabeledRoot label: 4097 record: rec.
logged := [:appends | PBAcceptorLog decode: (appends collect: [:x | x payload]) path: 'test'].
vs := (config value: 'n1' value: three) membership fingerprint.
msg := [:type :from :fields | PBReceived message: (PBClusterMessage type: type from: from fields: fields)].
request := [:from :term :inc | msg value: 'request' value: from value: { 'term' -> term. 'rid' -> 1. 'inc' -> inc. 'vs' -> vs }].
renew := [:from :term :inc | msg value: 'renew' value: from value: { 'term' -> term. 'rid' -> 1. 'inc' -> inc. 'vs' -> vs }].
query := [:from :ballot | msg value: 'query' value: from value: { 'rid' -> 3. 'inc' -> 1. 'ballot' -> ballot. 'vs' -> vs }].
reply := [:aStep | | sends | sends := aStep reply select: [:e | e isKindOf: PBSend].
  sends size = 1 ifTrue: [sends first message] ifFalse: [sends]].
counted := [:aStep | (aStep reply select: [:e | e isKindOf: PBCount]) collect: [:e | e stat]].
g := 4000000.
d := PBAcceptorState config: (config value: 'n1' value: three) detachedAt: 0.

"(1) Requests."
step := core accept: (request value: 'n0' value: 4096 value: 1) in: d now: g.
a := core accept: (request value: 'n1' value: 4097 value: 1) in: d now: g.
b := core accept: (request value: 'n0' value: 4096 value: 1)
  in: (PBAcceptorState config: (PBClusterConfig nodeId: 'n1' peers: (peers value: #('n0' 'n1' 'n2' 'n3'))
    options: (Dictionary new at: #voters put: #('n0' 'n2' 'n3'); yourself)) detachedAt: 0) now: g.
c that: 'with no acceptor log a request is refused no_storage, counted for a peer only; a learner is refused learner first'
  is: { d isAttached. (reply value: step) type. (reply value: step) at: 'reason'. counted value: step. step appends.
    a vote at: 'reason'. counted value: a. (reply value: b) at: 'reason'. counted value: b }
  equals: { false. 'reject'. 'no_storage'. #('grants_refused_no_storage'). #(). 'no_storage'. #(). 'learner'. #() }.

"(2) Queries."
step := core accept: (query value: 'n0' value: 0) in: d now: g.
a := core accept: (query value: 'n0' value: 8193) in: d now: g.
c that: 'with no acceptor log a plain or ballot query is answered unknown, nothing promised'
  is: { #('state' 'root' 'committed' 'certain' 'promised' 'ballot') collect: [:k | (reply value: step) at: k].
    ((reply value: a) at: 'state'). a appends. a state grants highestSeen }
  equals: { { 'unknown'. nil. nil. false. 0. 0 }. 'unknown'. #(). 0 }.

"(3) Start, replication, committed knowledge."
step := core accept: PBStartNode new in: d now: 0.
a := core accept: (msg value: 'replicate' value: 'n0' value: { 'term' -> 4097. 'rid' -> 2. 'inc' -> 1. 'seq' -> 1.
  'root' -> (PBClusterMessage rootValue: root). 'pred' -> (PBClusterMessage rootValue: (PBLabeledRoot label: 0 record: nil)).
  'committed' -> nil. 'records' -> #(). 'chunks' -> 0. 'base' -> nil. 'base_ranges' -> nil. 'vs' -> vs. 'copies' -> #('n0').
  'ranges' -> nil }) in: d now: g.
b := core accept: (PBLearnCommitted root: root accept: true logged: true) in: d now: g.
f := core accept: PBStartNode new in: (PBAcceptorState config: (PBClusterConfig nodeId: 'n0' peers: (peers value: #('n0'))
  options: Dictionary new) detachedAt: 0) now: 0.
c that: 'with no acceptor log the start writes nothing, a replication is refused, a committed root is appended to no log'
  is: { step appends. step reply. f appends. (reply value: a) at: 'ok'. counted value: a. a appends. b appends. b state committed key = root key }
  equals: { #(). #(). #(). false. #('refused'). #(). #(). true }.

"(4) attached: over a first log, a grant, then a re-attach over another log."
s := d attached: (logged value: { marker }).
step := core accept: (request value: 'n0' value: 4096 value: 1) in: s now: g.
s := step state with: { #suspectTerm -> 7. #seqSeen -> #(4096 3) }.
a := (s detached) attached: (logged value: { marker. PBLogAppend kind: #accepted label: 4097 root: rec sync: true }).
b := core accept: (renew value: 'n0' value: 4096 value: 1) in: a now: g + 1000.
c that: 'a re-attach keeps the lease activity and takes the new log''s roots and promise; a renewal over it writes its promise again'
  is: { step appends collect: [:x | { x kind. x label }]. s loggedPromise.
    a grants activeGrant holder. a grants termsSeen >= 4096. a suspectTerm. a seqSeen. a accepted key = root key. a isRejoined.
    a loggedPromise. a needsConfirmation.
    b appends collect: [:x | { x kind. x label }]. (reply value: b) type.
    [s attached: (logged value: { marker }). false] on: PBUserError do: [:e | true] }
  equals: { #(#(#promise 4096)). 4096. 'n0'. true. 7. #(4096 3). true. true. 0. true. #(#(#promise 4096)). 'grant'. true }.

"(5) detached."
f := (core accept: (PBAppendFailed reason: 'disk') in: s now: g) state.
a := f detached.
c that: 'detached drops the log, its promise, marker and failure, and keeps the grants'
  is: { f tierFailed. a isAttached. a log. a loggedPromise. a isRejoined. a tierFailed. a grants == f grants }
  equals: { 'disk'. false. nil. 0. false. nil. true }.

"(6) withFenced:."
c that: 'withFenced: keeps the first reason'
  is: { (d withFenced: 'one') fenced. ((d withFenced: 'one') withFenced: 'two') fenced. d fenced }
  equals: { 'one'. 'one'. nil }.

"(7) config:logged:now:."
a := PBAcceptorState config: (config value: 'n1' value: three) logged: (logged value: { marker }) now: 0.
b := d attached: a log.
c that: 'config:logged:now: is the detached acceptor of that start attached to the log'
  is: { a isAttached. a isRejoined. a loggedPromise. a accepted. a needsConfirmation.
    { a. b } collect: [:x | (reply value: (core accept: (request value: 'n0' value: 4096 value: 1) in: x now: 1000)) at: 'reason'] }
  equals: { true. true. 0. nil. true. #('starting' 'starting') }.

c report displayNl.
