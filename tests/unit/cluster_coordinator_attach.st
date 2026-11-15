"EXPECT: ok 9"
"The coordinator shell's attach, detach and routing contracts (cluster/coordinator.st; Task 20
 carry-overs (a), (b), (h), (k), N4, m10 and Task 19 (b)), over PBInProcessNetwork and
 MemoryTier (_cluster_shell.st). Every wait is a condition with a deadline of 60 s.
 (1) Before its tier is attached a node neither grants nor counts a grant: a peer's request is
 refused no_storage (counted grants_refused_no_storage) and a plain query answered unknown,
 while the two attached nodes commit (proto_db
 test_a_node_without_a_tier_neither_grants_nor_counts, test_x2_an_unattached_coordinator_is_never_a_rejoin_witness).
 (2) A message whose sender is not another member (an unknown id, or the node itself) is
 dropped and counted messages_ignored. (3) A re-attach keeps the lease activity and takes the
 new log: the terms seen are kept, the log is the new one, and the next promise is written to
 the new log (carry-over (b)); a second attach while attached is refused (PBUserError). (4) A done and a permit asked in that order are performed in
 order: the permit is issued once the done freed the permission (R148, carry-over (h)). (5) A
 forced rejoin does not outlive the log it was forced for (proto_db
 test_c2_audit_a_forced_rejoin_does_not_outlive_the_log_it_was_forced_for): forceRejoin,
 detach before it completes (the dispatcher marks the rejoin #detached, PBLogDetached),
 re-attach over a new empty log: the new rejoin is not forced.
 (6) A re-attach over the same disk builds a fresh PBLoggedRoots (N4): the rejoin runs over it
 (never left #detached) and completes once the peers run (proto_db
 test_c2_a_reattach_over_an_empty_disk_rejoins_by_ballot, over the shell; whether the round is
 plain or a ballot is the rules', cluster_rejoin_rules.st: here the peers report no history).
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

| c kit three nodes tiers out p a b t1 t2 f s r q vs log1 log2 one late first0 |
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

"(3) Attach n0, take part, then re-attach it over a new log."
t1 := MemoryTier served: 'n0' trace: kit trace.
(nodes first _attach: t1) waitWithin: 60000.
log1 := nodes first acceptorState log.
q := kit settle: (nodes first _attach: (MemoryTier served: 'n0' trace: kit trace)).
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
  is: { q first. (q at: 2) class name. out first. f. b == t1. log2 == log1. a grants termsSeen >= s. a loggedPromise. a isRejoined.
    r first. kit waitUntil: [t2 payloads anySatisfy: [:x | (PBAcceptorLog decode: { x } path: 'p') promise > 0]] }
  equals: { #error. #PBUserError. #committed. true. true. false. true. 0. true. #committed. true }.

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
(nodes first _detach) waitWithin: 60000.
log1 := nodes first nodeState rejoin log.
(nodes first _attach: t2) waitWithin: 60000.
b := kit waitUntil: [| r1 | r1 := nodes first nodeState rejoin. r1 notNil and: [r1 log == nodes first acceptorState log]].
log2 := nodes first acceptorState log.
(2 to: 3) do: [:i | (nodes at: i) start. ((nodes at: i) _attach: (MemoryTier served: (three at: i) trace: kit trace)) waitWithin: 60000].
f := kit waitUntil: [(nodes first stats at: 'rejoining') not].
c that: 'a re-attach over the same disk builds a fresh log and its rejoin completes once the peers run'
  is: { b. log2 == log1. f. nodes first acceptorState isRejoined. (kit commitOn: nodes first offset: 1) first }
  equals: { true. false. true. true. #committed }.
kit stopAll: nodes.

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
