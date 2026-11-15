"EXPECT: ok 10"
"The coordinator shell (cluster/coordinator.st) over PBInProcessNetwork and MemoryTier, the tier
 double (_cluster_shell.st): proto_db test_cluster_coordinator.py, test_cluster_durability.py,
 test_cluster_tier_failures.py and test_cluster_rejoin_records.py, the parts that need the
 shell. Every wait is a condition with a deadline of 60 s; no check reads a duration.
 (1) Three coordinators elect an owner and issue a permit (outcomes only). (2) A commit under
 it (base, replicate, done) is #committed and committedRoot follows the done. (3) The reply of
 an acceptance is sent after its append: the tier double and the endpoint record the order
 (CC2, R55). (4) stats holds grants_given, permits_issued and the health keys. (5) A test
 subclass of _PBAcceptor whose append raises fences its node: stats fenced, its _permit
 rejected with PBUnexpectedError naming the cause, it sends nothing after the fence but
 ack(ok = false), and the other two still commit. (6) A tier
 whose writes fail puts its node in tier-failed state (R57): it refuses grants (grants_given 0,
 tier_failed, healthy false) while the other two commit; the reason the dispatcher was handed
 (PBAcceptorDiscarded) is the acceptor's tierFailed (review m). (7) _attach: refuses a
 startupGrace below leaseDuration + driftMargin over a log that is not empty (L17, proto_db
 test_a_restart_on_a_log_needs_a_grace_of_one_lease_plus_the_drift_margin: 0, 0.2 D, D and
 the safe value less 1 ms refused; the safe value and the default accepted). (8) stop settles
 every pending Future: a permit that cannot be granted (no majority) is rejected with
 PBClosedError, as are _permit before start and after stop. (9) stop settles a replication in
 flight #unknown, never #none. (10) A failed acceptance write is refused and fails the tier
 (proto_db test_a_failed_acceptance_write_is_refused_and_fails_the_tier): the replication
 to a node whose accepted append fails gets no acknowledgement from it, and the node refuses
 tier_failed from then on."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_shell'.

PBCoordinatorCore subclass: #ReasonRules instanceVariableNames: 'seen'.

ReasonRules class >> new
  ^ self basicNew setSeen: (Atom on: #()).

ReasonRules >> setSeen: anAtom
  seen := anAtom.

ReasonRules >> seen
  ^ seen value.

ReasonRules >> dispatchAcceptorDiscarded: anEvent in: s now: t
  seen swap: [:old | old , { { #discarded. anEvent reason } }].
  ^ super dispatchAcceptorDiscarded: anEvent in: s now: t.

ReasonRules >> acceptAppendFailed: anEvent in: s now: t
  seen swap: [:old | old , { { #failed. anEvent reason } }].
  ^ super acceptAppendFailed: anEvent in: s now: t.

_PBAcceptor subclass: #FaultyAcceptor.

FaultyAcceptor >> _append: anAppend
  ^ Error signal: 'planted fault in the acceptor shell'.

| c kit three nodes tiers out p r trace first a b grace n f rules root q |
c := Check new.
three := #('n0' 'n1' 'n2').

"--- (1)-(4): a healthy cluster ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
tiers := three collect: [:id | MemoryTier served: id trace: kit trace].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
p := out at: 2.
c that: 'three coordinators elect an owner and issue a permit'
  is: { p class name. p term > 0. (nodes first nodeState ownership) notNil }
  equals: { #PBPermission. true. true }.
c that: 'a commit under the permit is committed and committedRoot follows the done'
  is: { out first. kit waitUntil: [nodes first committedRoot notNil and: [nodes first committedRoot key = (out at: 3) key]].
    nodes first committedEpoch = (out at: 3) epoch }
  equals: { #committed. true. true }.
trace := kit trace value.
"The first grant a peer sent, and the promise it appended before; the first ack, and its accepted append."
first := [:prefix | (1 to: trace size) detect: [:k | (trace at: k) beginsWith: prefix] ifNone: [0]].
a := (2 to: 3) collect: [:i | | id g pr ack acc |
  id := three at: i.
  g := (first value: id , ' send grant').
  pr := (first value: id , ' append promise').
  ack := (first value: id , ' send ack').
  acc := (first value: id , ' append accepted').
  (g = 0 or: [ack = 0]) ifTrue: [#missing] ifFalse: [{ pr > 0 and: [pr < g]. acc > 0 and: [acc < ack] }]].
c that: 'the reply of an acceptance is sent after its append (promise before grant, accepted before ack)'
  is: (a select: [:x | x ~= #missing]) asSet asArray
  equals: #(#(true true)).
a := nodes collect: [:x | x stats].
c that: 'stats hold grants_given, permits_issued and the health keys'
  is: { (a inject: 0 into: [:sum :d | sum + (d at: 'grants_given')]) > 0.
    (a inject: 0 into: [:sum :d | sum + (d at: 'permits_issued')]) > 0.
    a collect: [:d | #('healthy' 'fenced' 'tier_failed' 'persisting' 'rejoining' 'failure') collect: [:k | d at: k]] }
  equals: { true. true. (1 to: 3) asArray collect: [:i | { true. false. false. true. false. nil }] }.
kit stopAll: nodes.

"--- (5): an acceptor shell whose append raises fences its node ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | id = 'n2'
  ifTrue: [kit node: id options: Dictionary new rules: PBCoordinatorCore new acceptorClass: FaultyAcceptor]
  ifFalse: [kit node: id]].
tiers := three collect: [:id | MemoryTier served: id trace: kit trace].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
f := kit waitUntil: [(nodes at: 3) isFenced].
n := kit trace value size.
r := kit settle: (nodes at: 3) _permit.
"After the fence n2 sends nothing but refusals of replications and plain answers (proto_db
 _enqueue, _refuse_queued): a second commit asks it again."
a := kit commitOn: nodes first offset: 2.
b := ((kit trace value copyFrom: n + 1 to: kit trace value size) select: [:l | l beginsWith: 'n2 send'])
  reject: [:l | (l includesSubstring: 'send ack') and: [l endsWith: 'ok=false']].
"A fenced dispatcher drops its own events too: a confirmation never reaches the acceptor (the
 dispatcher has handled it before the attach is queued, so the refused attach is the acceptor's
 barrier)."
(nodes at: 3) _confirmed waitWithin: 60000.
q := kit settle: ((nodes at: 3) _attach: (MemoryTier served: 'n2' trace: kit trace)).
c that: 'an error escaping the acceptor fences its node; its permit is refused PBUnexpectedError naming the cause; the others commit'
  is: { out first. a first. b. (nodes at: 3) needsConfirmation. q first. f. (nodes at: 3) stats at: 'fenced'. (nodes at: 3) stats at: 'healthy'. r first. (r at: 2) class name.
    ((r at: 2) messageText includesSubstring: 'fenced after an internal failure').
    ((r at: 2) messageText includesSubstring: 'planted fault'). (nodes at: 3) acceptorState fenced notNil.
    (tiers at: 3) payloads size }
  equals: { #committed. #committed. #(). true. #error. true. true. false. #error. #PBUnexpectedError. true. true. true. 1 }.
kit stopAll: nodes.

"--- (6), (10): a tier whose writes fail ---"
kit := ShellKit ids: three.
rules := ReasonRules new.
nodes := three collect: [:id | id = 'n2'
  ifTrue: [kit node: id options: Dictionary new rules: rules acceptorClass: _PBAcceptor]
  ifFalse: [kit node: id]].
tiers := three collect: [:id | MemoryTier served: id trace: kit trace].
tiers := { tiers first. tiers at: 2. (MemoryTier served: 'n2' trace: kit trace) }.
nodes do: [:x | x start].
(1 to: 2) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
"n2's log fails from its first write on: the marker is read, every append fails."
b := MemoryTier name: 'n2' trace: kit trace failing: true.
b addPayload: (PBAcceptorLog encode: #rejoined label: 0 root: nil).
((nodes at: 3) _attach: b) waitWithin: 60000.
out := kit commitOn: nodes first offset: 1.
f := kit waitUntil: [((nodes at: 3) stats at: 'tier_failed')].
a := (nodes at: 3) stats.
c that: 'a tier whose writes fail refuses grants while the other two commit; the reason handed on is one value'
  is: { out first. f. a at: 'grants_given'. a at: 'healthy'. a at: 'fenced'.
    (rules seen collect: [:x | x first]) asSet size = 2.
    (rules seen collect: [:x | x last]) asSet asArray = { (nodes at: 3) acceptorState tierFailed }.
    ((nodes at: 3) acceptorState tierFailed includesSubstring: 'simulated disk failure').
    b payloads size }
  equals: { #committed. true. 0. false. false. true. true. true. 1 }.
kit stopAll: nodes.

"--- (10): a failed acceptance write is refused (ack ok = false) and fails the tier ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
b := MemoryTier name: 'n2' trace: kit trace failing: #(#accepted).
b addPayload: (PBAcceptorLog encode: #rejoined label: 0 root: nil).
tiers := { MemoryTier served: 'n0' trace: kit trace. MemoryTier served: 'n1' trace: kit trace. b }.
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
f := kit waitUntil: [((nodes at: 3) stats at: 'tier_failed') and: [kit trace value anySatisfy: [:l | l beginsWith: 'n2 send ack']]].
n := b payloads size.
a := kit commitOn: nodes first offset: 2.
kit waitUntil: [((kit trace value select: [:l | l beginsWith: 'n2 send ack']) size >= 2)].
trace := (kit trace value select: [:l | l beginsWith: 'n2 send ack']) collect: [:l | l copyFrom: (l indexOf: $=) + 1 to: l size].
c that: 'a failed acceptance write is refused (ack ok=false) and fails the tier; the next replication is refused without a write'
  is: { out first. a first. f. trace asSet asArray. ((nodes at: 3) stats at: 'accepted'). ((nodes at: 3) stats at: 'refused') >= 2.
    (b payloads size = n). ((nodes at: 3) acceptorState tierFailed includesSubstring: 'simulated disk failure') }
  equals: { #committed. #committed. true. #('false'). 0. true. true. true }.
kit stopAll: nodes.

"--- (7): the startup grace of a restart (L17) ---"
grace := [:ms | | k x |
  k := ShellKit ids: three.
  x := k node: 'n1' options: (ms isNil ifTrue: [Dictionary new] ifFalse: [Dictionary new at: #startupGrace put: ms; yourself])
    rules: PBCoordinatorCore new acceptorClass: _PBAcceptor.
  x start.
  r := k settle: (x _attach: (MemoryTier served: 'n1' trace: k trace)).
  x stop waitWithin: 60000.
  r first = #ok ifTrue: [#ok] ifFalse: [{ (r at: 2) class name. (r at: 2) messageText includesSubstring: 'startupGrace' }]].
c that: 'a restart on a log needs a grace of one lease plus the drift margin'
  is: ({ 0. 120. 600. 999. 1000. nil } collect: [:ms | grace value: ms])
  equals: { #(#PBValidationError true). #(#PBValidationError true). #(#PBValidationError true). #(#PBValidationError true). #ok. #ok }.

"--- (8), (9): stop settles every pending Future ---"
kit := ShellKit ids: three.
n := kit node: 'n0'.
a := kit settle: n _permit.
n start.
(n _attach: (MemoryTier served: 'n0' trace: kit trace)) waitWithin: 60000.
f := n _permit.
b := n stop.
b waitWithin: 60000.
c that: 'stop settles every pending Future with PBClosedError, as _permit before start and after stop'
  is: { a first. (a at: 2) class name. (kit settle: f) first. ((kit settle: f) at: 2) class name. ((kit settle: n _permit) at: 2) class name }
  equals: { #error. #PBClosedError. #error. #PBClosedError. #PBClosedError }.
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
tiers := three collect: [:id | MemoryTier served: id trace: kit trace].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
p := (kit settle: nodes first _permit) at: 2.
root := kit rootUnder: p on: ((kit settle: (nodes first _baseFor: p)) at: 2) base offset: 1.
"The peers stop first: the replication can never be acknowledged, then its node stops."
kit stopAll: (nodes allButFirst).
f := nodes first _replicate: root under: p.
a := kit waitUntil: [(nodes first stats at: 'replications') >= 1].
nodes first stop waitWithin: 60000.
c that: 'stop settles a replication in flight #unknown, never #none'
  is: { a. kit settle: f }
  equals: #(true #(#ok #unknown)).

c report displayNl.
