"EXPECT: lessons ok 11"
"The lessons of the design (spec section 2.4, L1-L32) that have a protocol counterpart here, one
 schedule each: its planted wrong rule fails it, by the rule the lesson names (the
 violation's or the problem's text where the run reports one), and the product rules pass it. The plants and the
 schedules are those of the scenario families (_plants.st, _base.st, _rejoin.st, _round.st,
 _accept.st; L29's plant and schedule in _plants.st, LessonFamilies), one seed each.
   L5   the lease runs from the send, not the win (PlantWindowFromWin: 'L5: valid leases at
        once').
   L8   release-carried certainty is never a commit point (PlantReleaseTeachesAccepted: the
        D45 amendment 6 schedule 3 publishes a root committed 'without a majority of synced
        acceptances').
   L12  replies of another incarnation are dropped (PlantAnyIncarnation: n0 owns on them).
   L13  rejoin is a ballot, never a wait (PlantRejoinByWaiting: R78a, the wiped node's clock
        1.3x fast, holder stalled: S4).
   L14  no replication below the rejoin ballot (PlantReplicateBelowBallot sends below it).
   L15  the phase-1 floor (PlantC1NoFloor: the C1 schedule drops R', S4).
   L22  the send reserve (PlantNoReserve: the refused root is replicated).
   L24  proposer-qualified ballots (PlantSharedBallot: two members ask one term).
   L25  the voter-set fingerprint (PlantNoFingerprint: a member of another voter set helps a
        quorum, the lesson's own measure: 'b' acknowledged with its help; the run raises no
        checker violation to match).
   L28  one base issued twice, the strict form (PlantBaseTwice: S4 at convergence).
   L29  a dying holder's late done: O6 abandons the term at valid + requestTimeout
        (PlantLateDoneAsNone retires the permission as none: its base issued again, two roots
        of one label and epoch).
 The other lessons are named with where they are covered or why they do not apply here."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.
Import from: '_plants'.
Import from: '_base'.
Import from: '_rejoin'.
Import from: '_round'.
Import from: '_accept'.

| c lessons covered text has out |
c := Check new.
has := [:aText :aPart | (aText ifNil: ['']) includesSubstring: aPart].
"{ lesson. product passes (a Boolean). plant fails (a Boolean). what the plant's run showed }"
lessons := OrderedCollection new.

out := LeaseFamilies window: PlantWindowFromWin seed: 1.
lessons add: { 'L5'. (LeaseFamilies window: LeaseRules seeds: #(1)) = #(0 1).
  has value: out first value: 'L5: valid leases at once'.
  (out first ifNil: ['no violation']) lines first }.

out := AcceptFamilies certainty: [PlantReleaseTeachesAccepted new] schedule: 3 seed: 1.
lessons add: { 'L8'. (AcceptFamilies certainty: [AcceptRules new] schedules: #(1 2 3 4) seed: 1) = 0.
  out anySatisfy: [:t | t includesSubstring: 'without a majority of synced acceptances'].
  out isEmpty ifTrue: ['no problem'] ifFalse: [out first lines first] }.

out := LeaseFamilies incarnations: PlantAnyIncarnation seeds: #(1).
lessons add: { 'L12'. (LeaseFamilies incarnations: LeaseRules seeds: #(1)) = #(0 0). out first > 0.
  'incarnations { owned. uncounted } ' , out printString }.

out := RejoinFamilies r78a: PlantRejoinByWaiting new seed: 1 rate: 13/10 stall: true.
lessons add: { 'L13'. (RejoinFamilies r78a: RejoinRules new seed: 1 rate: 13/10 stall: true) first isNil.
  has value: out first value: 'S4: the acknowledged commit ''a'''.
  (out first ifNil: ['no violation']) lines first }.

out := RejoinFamilies belowBallot: PlantReplicateBelowBallot new seed: 1.
lessons add: { 'L14'. (RejoinFamilies belowBallot: RejoinRules new seed: 1) asArray = #(nil #none 0 true).
  (out at: 2) = #unknown and: [(out at: 3) > 0].
  'below ballot { violation. x. sent below. ballot above } ' , out asArray printString }.

out := BaseFamilies c1: PlantC1NoFloor new seed: 1.
lessons add: { 'L15'. (BaseFamilies c1: BaseRules new seed: 1) first isNil.
  has value: out first value: 'S4: the acknowledged commit ''rp'''.
  (out first ifNil: ['no violation']) lines first }.

out := RoundFamilies reserve: PlantNoReserve new seed: 1.
lessons add: { 'L22'. (RoundFamilies reserve: RoundRules new seed: 1) = { #acknowledged. true. 0. 1. 1 }.
  (out at: 2) not and: [(out at: 3) > 0 and: [(out at: 4) = 0]].
  'reserve { outcome. CC18 refusal. sends of the refused root. refusals. replications } ' , out printString }.

out := LeaseFamilies terms: PlantSharedBallot seeds: (1 to: 3).
lessons add: { 'L24'. [:r | r first = 0 and: [(r at: 2) = 0]] value: (LeaseFamilies terms: LeaseRules seeds: (1 to: 3)).
  (out at: 2) > 0.
  'terms { failed. shared. stalled } ' , out printString }.

out := AcceptFamilies voterSets: [PlantNoFingerprint new] seeds: #(1).
lessons add: { 'L25'. (AcceptFamilies voterSets: [AcceptRules new] seeds: #(1)) = #(0 0). (out at: 2) = 1.
  'voter sets { failed. helped } ' , out printString }.

out := BaseFamilies baseTwice: PlantBaseTwice new seed: 1.
lessons add: { 'L28'. (BaseFamilies baseTwice: BaseRules new seed: 1) = { nil. #acknowledged. #acknowledged }.
  has value: out first value: 'S4: the acknowledged commit ''c'''.
  (out first ifNil: ['no violation']) lines first }.

out := LessonFamilies lateDone: PlantLateDoneAsNone new seed: 1.
lessons add: { 'L29'. [:r | r first isNil and: [(r at: 2) >= 1 and: [(r at: 3) = #acknowledged]]]
    value: (LessonFamilies lateDone: PBCoordinatorCore new seed: 1).
  has value: out first value: 'two different roots carry label'.
  (out first ifNil: ['no violation']) lines first }.

covered := OrderedCollection new.
lessons do: [:l |
  Transcript show: (l at: 1) , ' plant: ' , (l at: 4); cr.
  c that: (l at: 1) , ': the product rules pass' is: (l at: 2) equals: true.
  c that: (l at: 1) , ': the plant fails' is: (l at: 3) equals: true.
  ((l at: 2) and: [l at: 3]) ifTrue: [covered add: (l at: 1)]].
text := WriteStream on: String new.
covered do: [:l | text nextPutAll: l] separatedBy: [text nextPutAll: ' '].
Transcript show: 'lessons covered here: ' , text contents; cr.
#(
  'L1 no UDP: TCP only, majority lease (the transport, Task 19)'
  'L2 no storage CAS among writers: the persister alone writes space.root (Task 20)'
  'L3 truthful outcomes after something acceptable left: H7 in every simulator check'
  'L4 the lease carries no safety: the timer audit (tests/audit, run_tests.sh --audit)'
  'L6 drift margin >= 2/3 D: the constructor (cluster_config.st), clock rates (sim_leases.st family 4)'
  'L7 one sender per peer (Task 19/20, the actors)'
  'L9 root order (label, epoch, segment, offset): cluster_root_order.st, the sibling-roots rule'
  'L10 acceptor log synced in every mode: cluster_acceptor_log.st, sync before reply (sim_acceptance.st)'
  'L11 records durable before the acceptance (Phase C, Task 20)'
  'L16 an unreachable floor base abandons the term: proto_db _BaseUnreachable arises only on a local-records tier (Phase D); over shared storage a base whose SpaceRoot cannot be read fails its re-commit build, nothing sent, rc4 R233 (sim_round_rules.st (25), (26))'
  'L17 promise restored from the log, grace for efficiency: sim_grants.st, cluster_acceptance_rules.st'
  'L18 confirmation commit after attach (Task 20/24, the space; needsConfirmation: cluster_rejoin_rules.st)'
  'L19 fair turns (D-LIVE-1): sim_leases.st family 5'
  'L20 held retries (D-LIVE-2): sim_round_rules.st (1), (8)'
  'L21 owner permissions and group commit: sim_permits.st, sim_round_rules.st'
  'L23 message lanes (Task 19/20: the dispatcher never does I/O; the simulator lane is serial)'
  'L26 failed tier refuses (Phase C, Task 20)'
  'L27 node directory copies: a documented prohibition; the node-id binding of the log is deferred (CC6, Phase D)'
  'L30 linear framed-log search (Task 2, cluster_framed_log.st)'
  'L31 mutation tools on a copy: not applicable, the plants are subclasses (CC13)'
  'L32 liveness measured with fsync: protoBaseST is fsync only; the fairness family charges syncCost: (sim_leases.st)') do: [:l |
    Transcript show: 'not here: ' , l; cr].
out := c report.
out displayNl.
(out beginsWith: 'ok') ifTrue: ['lessons ok ' , covered size printString] ifFalse: ['lessons failed'].
