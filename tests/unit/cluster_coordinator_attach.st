"EXPECT: ok 10"
"The coordinator shell's attach, detach and routing contracts (cluster/coordinator.st; Task 20
 carry-overs (a), (b), (h), (k), N4, m10 and Task 19 (b)), over PBInProcessNetwork and
 MemoryTier (_cluster_shell.st). Every wait is a condition with a deadline of 60 s.
 (1) Before its tier is attached a node neither grants nor counts a grant: a peer's request is
 refused no_storage (counted grants_refused_no_storage) and a plain query answered unknown,
 while the two attached nodes commit (proto_db
 test_a_node_without_a_tier_neither_grants_nor_counts, test_x2_an_unattached_coordinator_is_never_a_rejoin_witness).
 (2, two checks) A message whose sender is not another member (an unknown id, or the node itself) is
 dropped and counted messages_ignored; a valid warm from another member (a type never sent at
 DEPTH 0, CC7) is counted ignored_messages, 0 until then, and changes nothing else (healthy,
 not fenced, messages_ignored unchanged). (3) A re-attach keeps the lease activity and takes the
 new log: the terms seen are kept, the log is the new one, and the next promise is written to
 the new log (carry-over (b)); while a tier is attached, attaching it again is a no-op answering
 true and attaching another is refused with PBValidationError (proto_db _attach_locked). (4) A done and a permit asked in that order are performed in
 order: the permit is issued once the done freed the permission (R148, carry-over (h)). (5) A
 forced rejoin does not outlive the log it was forced for (proto_db
 test_c2_audit_a_forced_rejoin_does_not_outlive_the_log_it_was_forced_for): forceRejoin,
 detach before it completes (the dispatcher marks the rejoin #detached, PBLogDetached),
 re-attach over a new empty log: the new rejoin is not forced.
 (6) A re-attach over an empty disk on a running coordinator rejoins by ballot (proto_db
 test_c2_a_reattach_over_an_empty_disk_rejoins_by_ballot, over the shell, with a committed root
 as the peers' history; its held-root variant is the simulator's, sim_rejoin.st R78a): the
 re-attach builds a fresh PBLoggedRoots (N4), the rejoin is a ballot (rejoin_ballots counted)
 and adopts the root the peers committed while the node was detached. The planted rules
 SkipBallot (the plain round's answers complete the rejoin, R53/R54) complete it with no ballot,
 so the ballot count tells the two apart. After a ballot, a permission under a term below it
 replicates nothing (#none: proto_db replicate's ProtoConflictError, L14) until a term above the
 ballot is live, so n0's next commit is retried until it commits.
 (7) A single-node cluster acquires and commits (proto_db
 test_single_node_cluster_acquires_and_releases). (8) A crashed holder: another member acquires
 after it, with a higher term (proto_db test_a_crashed_holder_blocks_others_until_its_lease_expires;
 that it waits for the lease to end is the rules' and the simulator's, never a duration here).
 (9) A late first-start member cut off by a partition stays rejoining through its gather
 rounds and rejoins once the partition heals, then acquires a higher term (proto_db
 test_a_late_first_start_member_cut_off_by_a_partition_rejoins_once_it_heals)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_shell'.

PBCoordinatorCore subclass: #SkipBallot.

"The plain round's answers complete the rejoin: no ballot (the planted rules of check 6)."
SkipBallot >> _ballotRound: aDecision answers: someAnswers in: s now: t effects: fx
  ^ self _completeRejoin: aDecision answers: someAnswers ballot: 0 in: s now: t effects: fx.

"Check 6 over rules aRules for n0: { rejoin_ballots before the re-attach. after. fresh log.
 rejoin completed. n0's accepted root is the one the peers committed. n0 then commits }."
Object subclass: #ReattachScenario.

ReattachScenario class >> run: aRules
  | three kit nodes t2 log1 before f committed out k |
  k := 1.
  three := #('n0' 'n1' 'n2').
  kit := ShellKit ids: three.
  nodes := three collect: [:id | id = 'n0'
    ifTrue: [kit node: id options: Dictionary new rules: aRules acceptorClass: _PBAcceptor]
    ifFalse: [kit node: id]].
  nodes first start.
  t2 := MemoryTier name: 'n0' trace: kit trace.
  (nodes first _attach: t2) waitWithin: 60000.
  log1 := nodes first acceptorState log.
  (nodes first _detach) waitWithin: 60000.
  (2 to: 3) do: [:i | (nodes at: i) start. ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
  committed := kit commitOn: (nodes at: 2) offset: 1.
  before := nodes first stats at: 'rejoin_ballots'.
  (nodes first _attach: t2) waitWithin: 60000.
  f := kit waitUntil: [(nodes first stats at: 'rejoining') not].
  out := { before. nodes first stats at: 'rejoin_ballots'. nodes first acceptorState log ~~ log1. f.
    committed first = #committed and: [nodes first acceptorState accepted notNil
      and: [nodes first acceptorState accepted key = (committed at: 3) key]].
    kit waitUntil: [(kit commitOn: nodes first offset: (k := k + 1)) first = #committed] }.
  kit stopAll: nodes.
  ^ out.

| same c kit three nodes tiers out p a b t1 t2 f s r q vs log1 log2 one late first0 |
c := Check new.
three := #('n0' 'n1' 'n2').

"--- (1)-(4): n0 starts unattached ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
tiers := three collect: [:id | MemoryTier served: id trace: kit trace].
nodes do: [:x | x start].
(2 to: 3) do: [:i | ((nodes at: i) _attach: (tiers at: i)) waitWithin: 60000].
out := kit commitOn: (nodes at: 2) offset: 1.
f := kit waitUntil: [(nodes first stats at: 'grants_refused_no_storage') >= 1].
vs := nodes first config membership fingerprint.
q := PBClusterMessage type: 'query' from: 'n1' fields: { 'rid' -> 99. 'inc' -> 1. 'ballot' -> 0. 'vs' -> vs }.
(nodes at: 2) config transport send: q to: 'n0'.
a := kit waitUntil: [kit trace value anySatisfy: [:l | l beginsWith: 'n0 send answer to n1 state=']].
c that: 'a node without a tier neither grants nor counts a grant; it refuses no_storage and answers unknown'
  is: { out first. f. nodes first stats at: 'grants_given'. a.
    ((kit trace value select: [:l | l beginsWith: 'n0 send answer']) collect: [:l | l copyFrom: (l indexOf: $=) + 1 to: l size]) asSet asArray.
    (kit trace value select: [:l | l beginsWith: 'n0 send reject']) allSatisfy: [:l | l endsWith: 'reason=no_storage'].
    (kit trace value anySatisfy: [:l | l beginsWith: 'n0 send grant']) }
  equals: { #committed. true. 0. true. #('unknown'). true. false }.

"(2) Unknown senders."
(nodes at: 2) config transport send: (PBClusterMessage type: 'query' from: 'zz' fields: { 'rid' -> 98. 'inc' -> 1. 'ballot' -> 0. 'vs' -> vs }) to: 'n0'.
nodes first config transport send: (PBClusterMessage type: 'query' from: 'n0' fields: { 'rid' -> 97. 'inc' -> 1. 'ballot' -> 0. 'vs' -> vs }) to: 'n0'.
c that: 'a message from a sender that is not another member is dropped and counted'
  is: { kit waitUntil: [(nodes first stats at: 'messages_ignored') = 2].
    kit trace value anySatisfy: [:l | (l beginsWith: 'n0 send answer to zz') or: [l beginsWith: 'n0 send answer to n0']] }
  equals: { true. false }.
a := nodes first stats at: 'ignored_messages' ifAbsent: [#absent].
(nodes at: 2) config transport send: (PBClusterMessage type: 'warm' from: 'n1' fields: { 'term' -> 4096. 'records' -> #() }) to: 'n0'.
c that: 'a valid warm from a member is counted ignored_messages, from 0, and changes nothing else'
  is: { a. kit waitUntil: [(nodes first stats at: 'ignored_messages' ifAbsent: [0]) = 1].
    nodes first stats at: 'healthy'. nodes first isFenced. nodes first stats at: 'messages_ignored' }
  equals: { 0. true. true. false. 2 }.

"(3) Attach n0, take part, then re-attach it over a new log."
t1 := MemoryTier served: 'n0' trace: kit trace.
(nodes first _attach: t1) waitWithin: 60000.
log1 := nodes first acceptorState log.
q := kit settle: (nodes first _attach: (MemoryTier served: 'n0' trace: kit trace)).
same := kit settle: (nodes first _attach: t1).
same := same , { nodes first acceptorState log == log1 }.
out := kit commitOn: (nodes at: 2) offset: 2.
f := kit waitUntil: [t1 payloads size > 1].
s := nodes first acceptorState grants termsSeen.
b := (nodes first _detach) waitWithin: 60000.
t2 := MemoryTier served: 'n0' trace: kit trace.
(nodes first _attach: t2) waitWithin: 60000.
log2 := nodes first acceptorState log.
a := nodes first acceptorState.
"A new term (n0's own acquisition) needs a promise on the new log."
r := kit commitOn: nodes first offset: 3.
c that: 'a re-attach keeps the lease activity and takes the new log; the next promise goes to the new log'
  is: { q first. (q at: 2) class name. (q at: 2) messageText. same. out first. f. b == t1. log2 == log1. a grants termsSeen >= s. a loggedPromise. a isRejoined.
    r first. kit waitUntil: [t2 payloads anySatisfy: [:x | (PBAcceptorLog decode: { x } path: 'p') promise > 0]] }
  equals: { #error. #PBValidationError. 'This coordinator already serves another storage'. #(#ok true true). #committed. true. true. false. true. 0. true. #committed. true }.

"(4) done, then permit, in order."
p := (kit settle: nodes first _permit) at: 2.
a := (kit settle: (nodes first _baseFor: p)) at: 2.
b := kit rootUnder: p on: a base offset: 4.
r := kit settle: (nodes first _replicate: b under: p).
nodes first _done: p outcome: #committed root: b.
f := kit settle: nodes first _permit.
c that: 'a done then a permit asked at once: the permit follows the done'
  is: { r. f first. (f at: 2) class name. (f at: 2) seq > p seq or: [(f at: 2) term > p term] }
  equals: { #(#ok #committed). #ok. #PBPermission. true }.
kit stopAll: nodes.

"--- (5), (6): a rejoin across detach and re-attach ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
nodes first start.
t1 := MemoryTier name: 'n0' trace: kit trace.
(nodes first _attach: t1) waitWithin: 60000.
a := kit waitUntil: [nodes first nodeState rejoin notNil and: [nodes first nodeState rejoin phase ~= #idle]].
nodes first forceRejoin.
f := kit waitUntil: [nodes first nodeState rejoin isForced].
(nodes first _detach) waitWithin: 60000.
q := kit waitUntil: [nodes first nodeState rejoin notNil and: [nodes first nodeState rejoin phase = #detached]].
t2 := MemoryTier name: 'n0' trace: kit trace.
(nodes first _attach: t2) waitWithin: 60000.
b := kit waitUntil: [| r1 | r1 := nodes first nodeState rejoin. r1 notNil and: [r1 log == nodes first acceptorState log]].
c that: 'a forced rejoin does not outlive the log it was forced for'
  is: { a. f. q. b. nodes first nodeState rejoin isForced. nodes first stats at: 'rejoining' }
  equals: { true. true. true. true. false. true }.
kit stopAll: nodes.
c that: 'a re-attach over an empty disk rejoins by ballot and adopts the root committed meanwhile; SkipBallot takes none'
  is: { ReattachScenario run: PBCoordinatorCore new. ReattachScenario run: SkipBallot new }
  equals: { { 0. 1. true. true. true. true }. { 0. 0. true. true. true. true } }.

"--- (7) a single-node cluster ---"
one := #('n0').
kit := ShellKit ids: one.
nodes := { kit node: 'n0' }.
nodes first start.
(nodes first _attach: (MemoryTier name: 'n0' trace: kit trace)) waitWithin: 60000.
out := kit commitOn: nodes first offset: 1.
f := kit waitUntil: [nodes first committedRoot notNil].
c that: 'a single-node cluster acquires and commits'
  is: { out first. f. (nodes first stats at: 'acquired') >= 1. nodes first acceptorState isRejoined }
  equals: { #committed. true. true. true }.
kit stopAll: nodes.

"--- (8) a crashed holder ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
out := kit commitOn: nodes first offset: 1.
nodes first stop waitWithin: 60000.
r := kit commitOn: (nodes at: 2) offset: 2.
c that: 'after a crashed holder another member acquires a higher term'
  is: { out first. r first. (r at: 2) term > (out at: 2) term }
  equals: { #committed. #committed. true }.
kit stopAll: nodes allButFirst.

"--- (9) a late first-start member cut off by a partition ---"
kit := ShellKit ids: three.
nodes := three collect: [:id | kit node: id options: (Dictionary new at: #startupGrace put: 0; yourself)
  rules: PBCoordinatorCore new acceptorClass: _PBAcceptor].
nodes do: [:x | x start].
(1 to: 3) do: [:i | ((nodes at: i) _attach: (MemoryTier name: (three at: i) trace: kit trace)) waitWithin: 60000].
a := kit waitUntil: [nodes allSatisfy: [:x | (x stats at: 'rejoining') not]].
out := kit commitOn: nodes first offset: 1.
kit network partition: #(#('n0' 'n1') #('n2')).
(nodes at: 3) stop waitWithin: 60000.
late := kit node: 'n2' options: (Dictionary new at: #startupGrace put: 0; yourself) rules: PBCoordinatorCore new acceptorClass: _PBAcceptor.
late start.
(late _attach: (MemoryTier name: 'n2' trace: kit trace)) waitWithin: 60000.
"Its gather rounds run out without a witness: it is still rejoining, and blocked."
b := kit waitUntil: [| rj | rj := late nodeState rejoin. rj notNil and: [rj phase = #retry]].
first0 := { late stats at: 'rejoining'. late acceptorState isRejoined }.
kit network heal.
f := kit waitUntil: [(late stats at: 'rejoining') not].
r := kit commitOn: late offset: 2.
c that: 'a late first-start member cut off by a partition rejoins once it heals'
  is: { a. out first. b. first0. f. late stats at: 'rejoin_blocked'. r first. (r at: 2) term > (out at: 2) term }
  equals: { true. #committed. true. #(true false). true. nil. #committed. true }.
kit stopAll: { nodes first. nodes at: 2. late }.

c report displayNl.
