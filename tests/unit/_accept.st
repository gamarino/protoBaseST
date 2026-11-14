"_accept.st: the test rules, the checking simulator and the planted wrong rules of the acceptance
 scenario families (sim_acceptance.st; a helper: the runner never runs files whose name starts
 with _). Test support, not product (CC13): each plant is a subclass overriding one rule method.

  AcceptRules        the product rules, with a stand-in for the base choice (Task 14): the base of
                     a commit is its permission's root, the empty space when unknown. The
                     replication, the acceptance and the commit point are the product's.
  AcceptSim          a PBSim that also checks, after the product's rules ran: every ok ack
                     (sent, or a holder's own vote) is performed only once the #accepted entry of
                     its root is synced on the acker's disk; every root published committed
                     (PBPublishCommitted) and every commit acknowledged is in the synced
                     #accepted entries of a majority of the voters' logs (the commit point,
                     CP 1.7 step 9, never a release, L8); with watchCertain, every lease that
                     appears certain carries a root at or above every acknowledged commit's root.
  PlantAckBeforeSync         the acceptance is appended without a sync (R55, ack only after the
                             synced append).
  PlantCommittedUnlogged     committed knowledge is never appended (R67: it is appended, unsynced).
  PlantNoBallotRule          a root of a term below a granted one is accepted (the ballot rule).
  PlantNoLogMatching         a later root of the accepted root's term is accepted whatever its pred
                             (V2').
  PlantLearnerCounts         a learner's ack counts toward the commit point (D54).
  PlantNoFingerprint         a replicate of another voter set is taken (D54, vs).
  PlantReleaseTeachesAccepted a release carries the holder's accepted root as its committed root:
                             release-carried certainty, the D45 commit point (L8)."

Import from: 'protobase'.
Import from: '_sim'.

"=== The rules ==============================================================="

PBCoordinatorCore subclass: #AcceptRules.

"The stand-in for the base choice (Task 14): the permission's root, the empty space when unknown."
AcceptRules >> dispatchBaseWanted: anEvent in: s now: t
  | root |
  root := anEvent permission root.
  root isNil ifTrue: [root := PBLabeledRoot label: 0 record: nil].
  ^ PBStep state: s effects: { PBSettle waiter: anEvent waiter outcome: root }.

AcceptRules subclass: #PlantAckBeforeSync.

PlantAckBeforeSync >> acceptReplicate: anEvent in: s now: t
  | step |
  step := super acceptReplicate: anEvent in: s now: t.
  ^ PBAcceptorStep state: step state
    appends: (step appends collect: [:a | PBLogAppend kind: a kind label: a label root: a root sync: false])
    reply: step reply vote: step vote learnt: step learnt.

AcceptRules subclass: #PlantCommittedUnlogged.

PlantCommittedUnlogged >> _learnCommitted: aRoot accept: isAccept logged: isLogged in: s
  ^ super _learnCommitted: aRoot accept: isAccept logged: false in: s.

AcceptRules subclass: #PlantNoBallotRule.

PlantNoBallotRule >> _ballotAllows: aTerm in: s
  ^ true.

AcceptRules subclass: #PlantNoLogMatching.

PlantNoLogMatching >> _extends: anAccepted with: aPred
  ^ true.

AcceptRules subclass: #PlantLearnerCounts.

PlantLearnerCounts >> _countsAck: aMessage in: s
  ^ true.

AcceptRules subclass: #PlantNoFingerprint.

PlantNoFingerprint >> dispatchReceived: anEvent in: s now: t
  anEvent message type = 'replicate' ifFalse: [^ super dispatchReceived: anEvent in: s now: t].
  ^ self receivedReplicate: anEvent in: s now: t.

AcceptRules subclass: #PlantReleaseTeachesAccepted.

PlantReleaseTeachesAccepted >> _release: aTerm in: s held: isHeld certain: isCertain next: aNext more: isMore
  | m view |
  m := super _release: aTerm in: s held: isHeld certain: isCertain next: aNext more: isMore.
  view := s acceptorView.
  (isHeld and: [view notNil and: [view accepted notNil]]) ifFalse: [^ m].
  ^ PBClusterMessage type: 'release' from: m from fields: {
    'term' -> (m at: 'term'). 'inc' -> (m at: 'inc'). 'root' -> (m at: 'root').
    'committed' -> (PBClusterMessage rootValue: view accepted). 'certain' -> (m at: 'certain'). 'held' -> true.
    'next' -> (m at: 'next'). 'more' -> (m at: 'more') }.

"=== AcceptSim ==============================================================="

PBSim subclass: #AcceptSim instanceVariableNames: 'problems certain'.

AcceptSim >> problems
  problems isNil ifTrue: [problems := OrderedCollection new].
  ^ problems.

"From now on every lease that appears is checked for certainty (L8)."
AcceptSim >> watchCertain
  certain := Dictionary new.

AcceptSim >> _problem: aText
  self _trace: 'PROBLEM ' , aText.
  self problems add: aText.

"The synced #accepted entries of anId's disk, as PBLabeledRoot keys."
AcceptSim >> syncedAcceptedOf: anId
  | disk entries |
  disk := self diskOf: anId.
  entries := disk payloads copyFrom: 1 to: disk syncedSize.
  ^ ((PBAcceptorLog decode: entries path: 'check') entries select: [:e | e kind = 1])
    collect: [:e | (PBLabeledRoot label: e label record: e root) key].

"The kinds (1 accepted, 2 committed, 3 promise, 4 rejoined) of the unsynced entries of anId."
AcceptSim >> unsyncedKindsOf: anId
  | disk entries |
  disk := self diskOf: anId.
  entries := disk payloads.
  ^ (entries copyFrom: disk syncedSize + 1 to: entries size) collect: [:p | p at: 1].

"The cluster's membership: the first member's (never reconfigured by a family), so a member
 configured with another voter set is checked against the cluster's voters."
AcceptSim >> membership
  ^ (self nodeAt: self ids first) config membership.

"The cluster's voters whose synced log holds the acceptance of aRoot."
AcceptSim >> votersAccepting: aRoot by: anId
  ^ self membership voters select: [:v | (self syncedAcceptedOf: v) includes: aRoot key].

AcceptSim >> _checkMajority: aRoot by: anId why: aText
  | membership |
  (aRoot isNil or: [aRoot record isNil]) ifTrue: [^ self].
  membership := self membership.
  (self votersAccepting: aRoot by: anId) size >= membership majority ifFalse: [
    self _problem: aText , ' ' , (self keyText: aRoot) , ' at ' , anId , ' without a majority of synced acceptances ('
      , (self votersAccepting: aRoot by: anId) printString , ')'].

AcceptSim >> _checkAck: anAck by: aNode
  | root |
  (anAck at: 'ok') ifFalse: [^ self].
  root := PBClusterMessage rootFrom: (anAck at: 'root').
  (root notNil and: [(self syncedAcceptedOf: aNode id) includes: root key]) ifFalse: [
    self _problem: aNode id , ' acknowledged ' , (root isNil ifTrue: ['nil'] ifFalse: [self keyText: root])
      , ' before its acceptance was synced'].

AcceptSim >> applySend: aSend
  aSend message type = 'ack' ifTrue: [self _checkAck: aSend message by: current].
  ^ super applySend: aSend.

AcceptSim >> _reply: aStep at: aNode syncedThrough: anIndex
  (aStep vote notNil and: [aStep vote type = 'ack']) ifTrue: [self _checkAck: aStep vote by: aNode].
  ^ super _reply: aStep at: aNode syncedThrough: anIndex.

AcceptSim >> applyPublishCommitted: aPublish
  self _checkMajority: aPublish root by: current id why: 'published committed'.
  ^ super applyPublishCommitted: aPublish.

AcceptSim >> _end: aToken as: aStatus
  aStatus = #acknowledged ifTrue: [self _checkMajority: (self rootOf: aToken) by: self ids first why: 'acknowledged'].
  ^ super _end: aToken as: aStatus.

AcceptSim >> step
  | stepped |
  stepped := super step.
  certain isNil ifFalse: [self _checkCertain].
  ^ stepped.

"Every lease that appears certain carries a root at or above every acknowledged commit's root."
AcceptSim >> _checkCertain
  self ids do: [:id |
    | node own key |
    node := self nodeAt: id.
    own := node isUp ifTrue: [node state ownership] ifFalse: [nil].
    own notNil ifTrue: [
      key := id , ' ' , own term printString.
      (certain includesKey: key) ifFalse: [
        certain at: key put: own lease isCertain.
        own lease isCertain ifTrue: [
          self commitOrder do: [:token |
            ((self outcomeOf: token) = #acknowledged
                and: [(PBRootOrder compare: own lease root with: (self rootOf: token)) < 0]) ifTrue: [
              self _problem: 'the certain lease ' , key , ' carries ' , (PBCoreValue textOf: own lease root)
                , ', below the acknowledged ' , token printString]]]]]].

"The leases seen with watchCertain: { 'node term' -> certain }."
AcceptSim >> leases
  ^ certain.

"=== The scenario families ==================================================="

Object subclass: #AcceptFamilies.

"An AcceptSim of the members someIds formed before (each log the rejoined marker), startup grace
 0, the rules aRules, options aDictionary on top."
AcceptFamilies class >> sim: aRules seed: n ids: someIds options: aDictionary
  | logs opts |
  logs := Dictionary new.
  someIds do: [:id | logs at: id put: { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }].
  opts := Dictionary new.
  opts at: #startupGrace put: 0.
  aDictionary keysAndValuesDo: [:k :v | opts at: k put: v].
  ^ AcceptSim seed: n ids: someIds rules: aRules options: opts logs: logs.

AcceptFamilies class >> three
  ^ #('n0' 'n1' 'n2').

AcceptFamilies class >> five
  ^ #('n0' 'n1' 'n2' 'n3' 'n4').

"aSim commits aToken at anId and runs until it is resolved (or n steps)."
AcceptFamilies class >> commit: aToken at: anId in: aSim
  aSim commit: aToken at: anId.
  aSim runUntil: [(aSim outcomeOf: aToken) ~= #pending] steps: 200000.
  ^ aSim outcomeOf: aToken.

"Runs aSim until virtual time anEnd or until nothing is due."
AcceptFamilies class >> run: aSim until: anEnd
  aSim runUntil: [aSim now >= anEnd] steps: 1000000.

"Runs aSim until no member owns a term (each ownership ends idle) and every outcome is known:
 the crashes of a schedule then fall between terms. (A crash during a term leaves its owner
 renewing against restarted members that reject at once: correct, but a long run in virtual time
 at the simulator's latency.)"
AcceptFamilies class >> idle: aSim
  aSim runUntil: [aSim ids allSatisfy: [:id | | node |
    node := aSim nodeAt: id. node isUp not or: [node state ownership isNil]]] steps: 1000000.

"Whether aRoot and another are the same known root."
AcceptFamilies class >> same: aRoot as: another
  ^ aRoot notNil and: [another notNil and: [aRoot key = another key]].

"A run's checks failed: the PBSim violation (an Error whose text names the seed) or a problem
 of AcceptSim. Answers the number of problems, 1 for a violation."
AcceptFamilies class >> problemsOf: aBlock
  ^ [aBlock value] on: Error do: [:e |
    ((e messageText ifNil: ['']) includesSubstring: 'PBSim seed') ifFalse: [e signal].
    1].

"--- 1. ack only after the synced append ---"

"{ problems over the seeds of the run under faults. checks failed of the crash schedule }. Under
 drops, duplicates, delays and reordering, commits at every member: every ok ack is performed
 only once its acceptance is synced. Then the crash between sync and reply: n1's acceptance of
 'a' is synced and n1 crashes before its reply: the root is on its disk, n1 never acked it
 (counted nothing), restarted it holds it accepted, and 'a' commits by n0 and n2."
AcceptFamilies class >> ackAfterSync: aRulesBlock seeds: someSeeds
  | faulty crashed |
  faulty := 0.
  crashed := 0.
  someSeeds do: [:n |
    faulty := faulty + (self problemsOf: [ | sim |
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      sim faults: (PBSimFaults drop: 1/10 duplicate: 1/20 delay: 2000 reorder: true).
      #('a' 'b' 'c' 'd') doWithIndex: [:token :i | self commit: token at: (self three at: i \\ 3 + 1) in: sim].
      sim converge: 200000.
      sim problems size]).
    crashed := crashed + (self problemsOf: [ | sim root failed |
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      sim commit: 'a' at: 'n0'.
      sim runUntil: [(sim trace last includesSubstring: 'n1 synced through')
        and: [(sim rootOf: 'a') notNil and: [(sim syncedAcceptedOf: 'n1') includes: (sim rootOf: 'a') key]]] steps: 200000.
      root := sim rootOf: 'a'.
      failed := 0.
      ((sim syncedAcceptedOf: 'n1') includes: root key) ifFalse: [failed := failed + 1].
      sim crash: 'n1' unsynced: #drop.
      sim runUntil: [(sim outcomeOf: 'a') ~= #pending] steps: 200000.
      (sim countOf: 'accepted' at: 'n1') = 0 ifFalse: [failed := failed + 1].
      (self same: (sim diskOf: 'n1') loggedRoots accepted as: root) ifFalse: [failed := failed + 1].
      sim restart: 'n1'.
      (self same: (sim nodeAt: 'n1') acceptor accepted as: root) ifFalse: [failed := failed + 1].
      (sim outcomeOf: 'a') = #acknowledged ifFalse: [failed := failed + 1].
      sim converge: 200000.
      failed + sim problems size])].
  ^ { faulty. crashed }.

"--- 2. power loss drops only unsynced committed knowledge ---"

"{ seeds failed. seeds where a power loss dropped a committed entry }. Commits at every member;
 n2 loses power: what it loses is only #committed entries (an acceptance, a promise and the
 marker are synced before their reply); n1 crashes with its page cache written back: it
 restarts with the committed root it had published; the chains converge (S4)."
AcceptFamilies class >> powerLoss: aRulesBlock seeds: someSeeds
  | failed dropped |
  failed := 0.
  dropped := 0.
  someSeeds do: [:n |
    failed := failed + ((self problemsOf: [ | sim lost before bad |
      bad := 0.
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      #('a' 'b' 'c') doWithIndex: [:token :i | self commit: token at: (self three at: i) in: sim].
      self idle: sim.
      lost := sim unsyncedKindsOf: 'n2'.
      (lost allSatisfy: [:k | k = 2]) ifFalse: [bad := bad + 1].
      lost notEmpty ifTrue: [dropped := dropped + 1].
      sim crash: 'n2' unsynced: #drop.
      before := (sim nodeAt: 'n1') committed.
      sim crash: 'n1' unsynced: #keep.
      sim restart: 'n1'.
      sim restart: 'n2'.
      (self same: (sim nodeAt: 'n1') acceptor committed as: before) ifFalse: [bad := bad + 1].
      sim converge: 300000.
      bad + sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ { failed. dropped }.

"--- 3. the old term's roots are refused after a promise ---"

"{ seeds failed. seeds where the paused holder's root was acknowledged }. n0 owns a term and
 committed 'a'; it holds its permission for 'b' and its process pauses before it replicates
 (pause: its clock stands, it runs nothing) for 10 belief periods. Meanwhile n1 wins a newer
 term (n2 promises it) and pauses before it builds anything, so every voter still holds 'a'
 accepted and only the ballot rule can refuse n0's root. n0 resumes, its permission still valid
 on its own clock, and replicates 'b': nobody else accepts a root of the old term (n2 and, once
 it resumes, n1 refuse it), 'b' is not acknowledged, and the chains converge."
AcceptFamilies class >> pausedHolder: aRulesBlock seeds: someSeeds
  | failed acked |
  failed := 0.
  acked := 0.
  someSeeds do: [:n |
    failed := failed + ((self problemsOf: [ | sim old bad belief resumed others |
      bad := 0.
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      belief := (sim nodeAt: 'n0') config belief.
      self commit: 'a' at: 'n0' in: sim.
      old := (sim nodeAt: 'n0') state ownership term.
      sim commit: 'b' at: 'n0'.
      sim runUntil: [(sim rootOf: 'b') notNil] steps: 200000.
      sim pause: 'n0'.
      sim commit: 'c' at: 'n1'.
      sim runUntil: [| own | own := (sim nodeAt: 'n1') state ownership. own notNil and: [own term > old]] steps: 500000.
      sim pause: 'n1'.
      self run: sim until: sim now + (10 * belief).
      resumed := sim now.
      others := #('n1' 'n2') collect: [:id | (sim syncedAcceptedOf: id) size].
      sim resume: 'n0'.
      sim runUntil: [(sim outcomeOf: 'b') ~= #pending] steps: 500000.
      "Nothing of the old term accepted by n1 or n2 after the pause."
      #('n1' 'n2') doWithIndex: [:id :i |
        ((sim syncedAcceptedOf: id) allButFirst: (others at: i)) do: [:k | (k at: 1) = old ifTrue: [bad := bad + 1]]].
      (sim outcomeOf: 'b') = #acknowledged ifTrue: [acked := acked + 1. bad := bad + 1].
      "A wrong rule is caught here: past it, the resumed owner of the old term renews against
       members that reject at once, a long run in virtual time."
      bad = 0 ifTrue: [
        sim resume: 'n1'.
        sim runUntil: [(sim outcomeOf: 'c') ~= #pending] steps: 500000.
        sim converge: 300000.
        (sim outcomeOf: 'c') = #acknowledged ifFalse: [bad := bad + 1]].
      bad + sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ { failed. acked }.

"--- 4. log matching refuses a root not built on the accepted chain ---"

"{ seeds failed }. n0 committed 'a' in its term; a replicate of n0's term reaches n1 with root x
 built on y, which n1 never held: refused (ack false, nothing appended); y (built on 'a') is
 accepted, then x, which extends it now."
AcceptFamilies class >> logMatching: aRulesBlock seeds: someSeeds
  | failed |
  failed := 0.
  someSeeds do: [:n |
    failed := failed + ((self problemsOf: [ | sim a term inc seg y x replicate acks bad |
      bad := 0.
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      self commit: 'a' at: 'n0' in: sim.
      self run: sim until: sim now + 1000.
      a := sim rootOf: 'a'.
      term := a label.
      inc := (sim nodeAt: 'n0') state inc.
      seg := (sim nodeAt: 'n0') segment.
      y := PBLabeledRoot label: term record: (PBRootRecord segment: seg offset: 900001 epoch: a epoch + 10).
      x := PBLabeledRoot label: term record: (PBRootRecord segment: seg offset: 900002 epoch: a epoch + 11).
      replicate := [:root :pred :rid | PBClusterMessage type: 'replicate' from: 'n0' fields: {
        'term' -> term. 'rid' -> rid. 'inc' -> inc. 'root' -> (PBClusterMessage rootValue: root). 'committed' -> nil.
        'records' -> #(). 'chunks' -> 0. 'base' -> nil. 'base_ranges' -> nil. 'seq' -> 100. 'pred' -> (PBClusterMessage rootValue: pred).
        'vs' -> (sim nodeAt: 'n0') config membership fingerprint. 'copies' -> #('n0'). 'ranges' -> nil }].
      acks := [(sim trace select: [:l | l includesSubstring: 'n1   -> PBSend(n0, ack from n1)']) size].
      sim inject: (replicate value: x value: y value: 900001) to: 'n1' at: sim now.
      self run: sim until: sim now + 1000.
      ((sim syncedAcceptedOf: 'n1') includes: x key) ifTrue: [bad := bad + 1].
      (sim countOf: 'refused' at: 'n1') = 1 ifFalse: [bad := bad + 1].
      sim inject: (replicate value: y value: a value: 900002) to: 'n1' at: sim now.
      self run: sim until: sim now + 1000.
      sim inject: (replicate value: x value: y value: 900003) to: 'n1' at: sim now.
      self run: sim until: sim now + 1000.
      ((sim syncedAcceptedOf: 'n1') includes: x key) ifFalse: [bad := bad + 1].
      (sim countOf: 'accepted' at: 'n1') >= 3 ifFalse: [bad := bad + 1].
      bad + sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ failed.

"--- 5. learners never count ---"

"{ seeds failed. seeds where a learner's ack counted }. Five members, voters n0, n1, n2: the
 learner n3 owns a term and commits 'a' (a learner may own and commit); n1 and n2 are then cut
 off and n3 commits 'b' with only n0 reachable among the voters; a learner's ok ack for 'b'
 (n4's, injected) never counts: 'b' is not acknowledged; no learner ever accepts a root."
AcceptFamilies class >> learners: aRulesBlock seeds: someSeeds
  | failed counted |
  failed := 0.
  counted := 0.
  someSeeds do: [:n |
    failed := failed + ((self problemsOf: [ | sim bad rep |
      bad := 0.
      sim := self sim: aRulesBlock value seed: n ids: self five options: Dictionary new.
      (self commit: 'a' at: 'n3' in: sim) = #acknowledged ifFalse: [bad := bad + 1].
      sim partition: #(#('n0' 'n3' 'n4') #('n1' 'n2')).
      sim commit: 'b' at: 'n3'.
      sim runUntil: [(sim outcomeOf: 'b') ~= #pending
        or: [((sim nodeAt: 'n3') state holder notNil and: [(sim nodeAt: 'n3') state holder replications notEmpty])]] steps: 200000.
      rep := (sim nodeAt: 'n3') state holder isNil ifTrue: [nil] ifFalse: [(sim nodeAt: 'n3') state holder replications detect: [:r | true] ifNone: [nil]].
      rep notNil ifTrue: [
        sim inject: (PBClusterMessage type: 'ack' from: 'n4' fields: { 'term' -> rep permission term. 'rid' -> rep rid.
          'inc' -> (sim nodeAt: 'n3') state inc. 'ok' -> true. 'root' -> (PBClusterMessage rootValue: rep root). 'stored' -> false })
          to: 'n3' at: sim now].
      sim runUntil: [(sim outcomeOf: 'b') ~= #pending] steps: 200000.
      (sim outcomeOf: 'b') = #acknowledged ifTrue: [counted := counted + 1. bad := bad + 1].
      sim converge: 300000.
      #('n3' 'n4') do: [:id | (sim syncedAcceptedOf: id) isEmpty ifFalse: [bad := bad + 1]].
      bad + sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ { failed. counted }.

"--- 6. vs mismatch ---"

"{ seeds failed. seeds where the misconfigured member helped a quorum }. Five members, voters
 n0, n1, n2; n0 owns a term and committed 'a'. While n0 still owns it, n2 restarts configured
 with the voters n2, n3, n4 and n1 is cut off; n0 commits 'b' under its lease: n2 drops the
 replicate (counted config_mismatches), so 'b' is not acknowledged and n2 never accepts it;
 then n2's own commit 'r' gets no grant from n3 or n4 (they drop its requests)."
AcceptFamilies class >> voterSets: aRulesBlock seeds: someSeeds
  | failed helped |
  failed := 0.
  helped := 0.
  someSeeds do: [:n |
    failed := failed + ((self problemsOf: [ | sim bad rogue |
      bad := 0.
      sim := self sim: aRulesBlock value seed: n ids: self five options: Dictionary new.
      (self commit: 'a' at: 'n0' in: sim) = #acknowledged ifFalse: [bad := bad + 1].
      sim crash: 'n2' unsynced: #keep.
      rogue := Dictionary new.
      rogue at: #startupGrace put: 0; at: #voters put: #('n2' 'n3' 'n4').
      sim reconfigure: 'n2' options: rogue.
      sim restart: 'n2'.
      sim partition: #(#('n0' 'n2' 'n3' 'n4') #('n1')).
      sim commit: 'b' at: 'n0'.
      sim runUntil: [(sim outcomeOf: 'b') ~= #pending] steps: 300000.
      "After 'b': n2's own request would promise a newer term, and the ballot rule alone would
       refuse n0's replicate."
      sim commit: 'r' at: 'n2'.
      self run: sim until: sim now + (2 * (sim nodeAt: 'n0') config leaseDuration).
      (sim outcomeOf: 'b') = #acknowledged ifTrue: [helped := helped + 1. bad := bad + 1].
      (sim outcomeOf: 'r') = #acknowledged ifTrue: [bad := bad + 1].
      (sim countOf: 'config_mismatches' at: 'n2') > 0 ifFalse: [bad := bad + 1].
      #('n3' 'n4') do: [:id | (sim countOf: 'grants_given' at: id) = 0 ifFalse: [bad := bad + 1]].
      ((sim rootOf: 'b') notNil and: [(sim syncedAcceptedOf: 'n2') includes: (sim rootOf: 'b') key]) ifTrue: [bad := bad + 1].
      bad + sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ { failed. helped }.

"--- 7. release-carried certainty is never a commit point (L8) ---"

"{ schedules failed }: the four schedules of D45 amendment 6 (proto_db
 test_cluster_root_certainty at 9213356, where release-carried propagation made a stale root
 certain), as fixed schedules over the real replication. Each checks, with watchCertain, that a
 certain lease never carries a root below an acknowledged commit, and that every root a member
 publishes committed holds a majority of synced acceptances (the commit point, never a
 release). anArray names the schedules to run (1 to 4)."
AcceptFamilies class >> certainty: aRulesBlock schedules: anArray seed: n
  | failed |
  failed := 0.
  anArray do: [:k |
    failed := failed + ((self problemsOf: [ | sim |
      sim := self sim: aRulesBlock value seed: n ids: self three options: Dictionary new.
      sim watchCertain.
      self perform: ('schedule' , k printString , ':') asSymbol with: sim.
      sim converge: 300000.
      sim problems size]) > 0 ifTrue: [1] ifFalse: [0])].
  ^ failed.

"a stale certain release clears a peer's suspicion: n2 holds a term granted by n1 and pauses; n1
 wins a newer term (uncertain: its grant to n2 expired) and commits 'r2' with n0; n1's release
 is lost; n2 resumes and releases its old term, certain; n0, whose grant to n1 expired, takes
 n2's stale release, then wins a term with n2 alone."
AcceptFamilies class >> schedule1: sim
  | d |
  d := (sim nodeAt: 'n0') config leaseDuration.
  self commit: 'r1' at: 'n2' in: sim.
  sim pause: 'n2'.
  self commit: 'r2' at: 'n1' in: sim.
  sim partition: #(#('n1') #('n0' 'n2')).
  self run: sim until: sim now + (2 * d).
  sim resume: 'n2'.
  self run: sim until: sim now + (2 * d).
  self commit: 'r3' at: 'n0' in: sim.

"a same-holder request frees a grant without marking a missed root: n1 commits 'r2' with n0, its
 release is lost, it restarts within its startup grace and asks again (n0 ends the old
 incarnation's grant), loses (its own vote is starting); then n2 wins with n0."
AcceptFamilies class >> schedule2: sim
  | d graced |
  d := (sim nodeAt: 'n0') config leaseDuration.
  self commit: 'r1' at: 'n0' in: sim.
  self commit: 'r2' at: 'n1' in: sim.
  sim partition: #(#('n1') #('n0' 'n2')).
  sim crash: 'n1' unsynced: #keep.
  graced := Dictionary new.
  graced at: #startupGrace put: d.
  sim reconfigure: 'n1' options: graced.
  sim restart: 'n1'.
  sim partition: #(#('n0' 'n1') #('n2')).
  sim commit: 'x' at: 'n1'.
  self run: sim until: sim now + (d // 2).
  sim partition: #(#('n0' 'n2') #('n1')).
  self commit: 'r3' at: 'n2' in: sim.

"an uncertain release taints its receiver: n1 owns a term and, cut off, replicates 'r2' under
 its lease: it reaches nobody (an unknown outcome, n1 suspect, 'r2' accepted at n1 only); its
 release, not certain, reaches n0; n2 then wins with n0."
AcceptFamilies class >> schedule3: sim
  self commit: 'r1' at: 'n1' in: sim.
  sim partition: #(#('n1') #('n0' 'n2')).
  self commit: 'r2' at: 'n1' in: sim.
  sim partition: #(#('n0' 'n1') #('n2')).
  self run: sim until: sim now + (2 * (sim nodeAt: 'n0') config leaseDuration).
  sim partition: #(#('n0' 'n2') #('n1')).
  self commit: 'r3' at: 'n2' in: sim.

"the requester's own newer root counts when its own vote is refused: n0 commits 'r2' with n2
 only; n1's attempt reaches n0, which grants, and the replies and the cancel are lost (n0's
 grant to n1 stays); n0 then asks: its own vote is busy, n1 and n2 grant, and the lease's root
 is n0's own accepted root."
AcceptFamilies class >> schedule4: sim
  self commit: 'r1' at: 'n0' in: sim.
  sim partition: #(#('n0' 'n2') #('n1')).
  self commit: 'r2' at: 'n0' in: sim.
  self run: sim until: sim now + (2 * (sim nodeAt: 'n0') config leaseDuration).
  sim heal.
  sim delay: 'n0' to: 'n1' by: 10000000.
  sim commit: 'x' at: 'n1'.
  self run: sim until: sim now + ((sim nodeAt: 'n0') config requestTimeout).
  sim delay: 'n0' to: 'n1' by: 0.
  self commit: 'r3' at: 'n0' in: sim.
