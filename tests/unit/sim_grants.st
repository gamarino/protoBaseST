"EXPECT: ok 10"
"The acceptor's phase-1 rules (cluster/acceptor.st) in the simulator (_sim.st), over seeds 1-40,
 with duplicated, delayed and reordered messages: each node starts over a log holding the
 rejoined marker (a cluster formed before), and the test injects the requests, renewals and
 releases a proposer would send (proto_db test_cluster_lease, _terms, _renewal, _voters).
 (1) A grant, then busy for another holder, with the remaining promise in seconds. (2) A
 release ends busy at once. (3) The startup grace refuses (starting, efficiency only: the term
 is granted once the grace ends). (4) A restart restores the promise from the log, never below
 it (L17): the granted term and every lower one are refused after the restart, whatever the
 crash keeps of the unsynced tail. (5) A learner never grants nor promises. (6) A renewal keeps
 the term without a write to the acceptor log (the disk's appends are counted). (7) A refused
 higher request does not end the owner's renewals. (8) No grant is replied before its promise
 is synced: after a power loss of every node, each node's log holds every term it granted (and
 the simulator's checker runs after every step). (9) The plant PlantRenewStale (a renewal
 decided after the stale-term rule, proto_db's renew_stale) makes family 7 fail. (10) Started
 over empty logs (proto_db start then _attach_locked): a one-member cluster's node and the
 learner of four members each take one start step and log the rejoined marker, synced, and
 serve; the three voters of four log nothing, take one start step each and refuse requests as
 rejoining (their rejoin is Task 16's)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sim'.

"--- test rules: the product rules, recording the replies each node receives ---"

PBCoordinatorCore subclass: #GrantRules instanceVariableNames: 'seen'.

GrantRules class >> new
  ^ self basicNew setUp.

GrantRules >> setUp
  seen := OrderedCollection new.

"The grant, reject and answer messages anId received, in arrival order."
GrantRules >> repliesAt: anId
  ^ (seen select: [:e | e first = anId]) collect: [:e | e last].

GrantRules >> dispatchReceived: anEvent in: s now: t
  (#('grant' 'reject' 'answer') includes: anEvent message type) ifTrue: [seen add: { s config nodeId. anEvent message }].
  ^ super dispatchReceived: anEvent in: s now: t.

"Plant (proto_db renew_stale): a renewal of a term below the highest seen is decided as a
 plain request, after the stale-term rule."
GrantRules subclass: #PlantRenewStale.

PlantRenewStale >> acceptRenew: anEvent in: s now: t
  (anEvent message at: 'term') < s grants highestSeen ifTrue: [^ self acceptRequest: anEvent in: s now: t].
  ^ super acceptRenew: anEvent in: s now: t.

"--- the checks ---"

| c ids four marker logsOf faults simOf vs request renew release query replies reasons grantTerms
  run family failuresOf grace g one two |
c := Check new.
ids := #('n0' 'n1' 'n2').
four := #('n0' 'n1' 'n2' 'n3').
marker := { PBLogAppend kind: #rejoined label: 0 root: nil sync: true }.
logsOf := [:someIds | | d | d := Dictionary new. someIds do: [:id | d at: id put: marker]. d].
faults := PBSimFaults drop: 0 duplicate: 1/5 delay: 2000 reorder: true.
simOf := [:seed :rules :someIds |
  | s |
  s := PBSim seed: seed ids: someIds rules: rules options: Dictionary new logs: (logsOf value: someIds).
  s faults: faults.
  s].
vs := [:s | (s nodeAt: s ids first) config membership fingerprint].
request := [:s :from :term :inc | PBClusterMessage type: 'request' from: from fields: {
  'term' -> term. 'rid' -> 1. 'inc' -> inc. 'vs' -> (vs value: s) }].
renew := [:s :from :term :inc | PBClusterMessage type: 'renew' from: from fields: {
  'term' -> term. 'rid' -> 2. 'inc' -> inc. 'vs' -> (vs value: s) }].
release := [:from :term :inc | PBClusterMessage type: 'release' from: from fields: {
  'term' -> term. 'inc' -> inc. 'root' -> nil. 'committed' -> nil. 'certain' -> true. 'held' -> true.
  'next' -> nil. 'more' -> false }].
query := [:s :from | PBClusterMessage type: 'query' from: from fields: {
  'rid' -> 3. 'inc' -> 1. 'ballot' -> 0. 'vs' -> (vs value: s) }].
"Runs aSim until its queue is empty."
run := [:s | s runUntil: [false] steps: 5000. s].
"The reasons of the replies anId received from aGranter ('granted' for a grant), as a Set."
reasons := [:rules :anId :aGranter | (((rules repliesAt: anId) select: [:m | m from = aGranter]) collect: [:m |
  m type = 'grant' ifTrue: ['granted'] ifFalse: [m type = 'reject' ifTrue: [m at: 'reason'] ifFalse: [m at: 'state']]]) asSet].
grantTerms := [:rules :anId :aGranter | (((rules repliesAt: anId) select: [:m | m type = 'grant' and: [m from = aGranter]])
  collect: [:m | m at: 'term']) asSet].
"The default startup grace is D + margin = 3333334 us; g is after it."
grace := 3333334.
g := 4000000.
"Runs aFamily (a block of a seed and a rules object answering nil or a failure text) over
 seeds 1-40 with rules of aClass; answers the failure texts (an error is one)."
failuresOf := [:aFamily :aClass |
  ((1 to: 40) asArray collect: [:seed |
    [aFamily value: seed value: aClass new] on: Error do: [:e | 'seed ' , seed printString , ': ' , e messageText]])
    reject: [:x | x isNil]].
family := Dictionary new.

"(1) grant then busy for another holder"
family at: 1 put: [:seed :rules |
  | s busy |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  s inject: (request value: s value: 'n2' value: 8194 value: 9) to: 'n1' at: g + 100000.
  run value: s.
  busy := ((rules repliesAt: 'n2') select: [:m | m type = 'reject']) collect: [:m | m at: 'remaining'].
  ({ reasons value: rules value: 'n0' value: 'n1'. reasons value: rules value: 'n2' value: 'n1'.
     busy allSatisfy: [:r | r isFloat and: [r between: 1.89 and: 1.91]]. (s diskOf: 'n1') loggedRoots promise }
    = { #('granted') asSet. #('busy') asSet. true. 4096 })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (rules repliesAt: 'n2') printString]].

"(2) release ends busy at once"
family at: 2 put: [:seed :rules |
  | s |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  s inject: (release value: 'n0' value: 4096 value: 7) to: 'n1' at: g + 100000.
  s inject: (request value: s value: 'n2' value: 8194 value: 9) to: 'n1' at: g + 200000.
  run value: s.
  ({ reasons value: rules value: 'n0' value: 'n1'. reasons value: rules value: 'n2' value: 'n1' }
    = { #('granted') asSet. #('granted') asSet })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (rules repliesAt: 'n2') printString]].

"(3) startup grace refuses (efficiency only): starting with the grace left, granted after it"
family at: 3 put: [:seed :rules |
  | s first |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: 1000000.
  run value: s.
  first := (rules repliesAt: 'n0') collect: [:m | m type = 'reject' ifTrue: [{ m type. m at: 'reason'. m at: 'remaining' }] ifFalse: [{ m type }]].
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  run value: s.
  ((first notEmpty and: [first allSatisfy: [:r | r first = 'reject' and: [(r at: 2) = 'starting'
      and: [(r at: 3) between: 2.331 and: 2.334]]]])
    and: [(grantTerms value: rules value: 'n0' value: 'n1') = #(4096) asSet])
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (rules repliesAt: 'n0') printString]].

"(4) restart restores the promise from the log, never below it (L17)"
family at: 4 put: [:seed :rules |
  | s r later |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  s runUntil: [(grantTerms value: rules value: 'n0' value: 'n1') notEmpty] steps: 5000.
  s crash: 'n1' unsynced: #any.
  s restart: 'n1'.
  r := s trace last.
  r := ((r copyFrom: 3 to: r size) subStrings: ' ') first asNumber.
  s inject: (PBClusterMessage type: 'request' from: 'n0' fields: {
    'term' -> 4096. 'rid' -> 5. 'inc' -> 7. 'vs' -> (vs value: s) }) to: 'n1' at: r + g.
  s inject: (request value: s value: 'n2' value: 2 value: 9) to: 'n1' at: r + g + 100000.
  s inject: (request value: s value: 'n2' value: 8194 value: 9) to: 'n1' at: r + g + 200000.
  run value: s.
  "The replies to the request sent after the restart (rid 5): earlier copies of the first
   request may still reach the new incarnation, during its grace."
  later := (rules repliesAt: 'n0') select: [:m | (m at: 'rid') = 5].
  ((later notEmpty and: [later allSatisfy: [:m | m type = 'reject' and: [(m at: 'reason') = 'term_taken']]])
    and: [(((rules repliesAt: 'n2') collect: [:m | m type = 'grant' ifTrue: [m at: 'term'] ifFalse: [m at: 'reason']]) asSet
      = { 'stale_term'. 8194 } asSet)
    and: [(s diskOf: 'n1') loggedRoots promise >= 4096]])
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , later printString , ' '
      , (rules repliesAt: 'n2') printString]].

"(5) learner never grants: n3 of four members (the voters are n0, n1, n2)"
family at: 5 put: [:seed :rules |
  | s |
  s := simOf value: seed value: rules value: four.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n3' at: g.
  s inject: (request value: s value: 'n1' value: 8193 value: 8) to: 'n3' at: g + 100000.
  s inject: (request value: s value: 'n2' value: 12290 value: 9) to: 'n3' at: g + 200000.
  s inject: (query value: s value: 'n0') to: 'n3' at: g + 300000.
  run value: s.
  ({ reasons value: rules value: 'n0' value: 'n3'. reasons value: rules value: 'n1' value: 'n3'.
     reasons value: rules value: 'n2' value: 'n3'. (rules repliesAt: 'n0') size >= 2. (s diskOf: 'n3') loggedRoots promise }
    = { #('learner') asSet. #('learner') asSet. #('learner') asSet. true. 0 })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (rules repliesAt: 'n0') printString]].

"(6) renew keeps the term without a log write: four renewals, the disk's appends unchanged, the
 grant extended past its first expiry"
family at: 6 put: [:seed :rules |
  | s size |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  run value: s.
  size := (s diskOf: 'n1') size.
  1 to: 4 do: [:k | s inject: (renew value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g + (k * 500000)].
  s inject: (request value: s value: 'n2' value: 8194 value: 9) to: 'n1' at: g + 3000000.
  run value: s.
  ({ size. (s diskOf: 'n1') size. reasons value: rules value: 'n0' value: 'n1'.
     reasons value: rules value: 'n2' value: 'n1'. (rules repliesAt: 'n0') size >= 5 }
    = { 2. 2. #('granted') asSet. #('busy') asSet. true })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': disk ' , size printString , '->' , (s diskOf: 'n1') size printString
      , ' ' , (rules repliesAt: 'n0') printString]].

"(7) a refused higher request does not end the owner's renewals"
family at: 7 put: [:seed :rules |
  | s |
  s := simOf value: seed value: rules value: ids.
  s inject: (request value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  s inject: (request value: s value: 'n2' value: 8194 value: 9) to: 'n1' at: g + 100000.
  s inject: (renew value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g + 200000.
  s inject: (renew value: s value: 'n0' value: 4096 value: 7) to: 'n1' at: g + 1500000.
  run value: s.
  ({ reasons value: rules value: 'n0' value: 'n1'. reasons value: rules value: 'n2' value: 'n1' }
    = { #('granted') asSet. #('busy') asSet })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (rules repliesAt: 'n0') printString]].

"(8) no reply before the promise is synced: requests from every node to every other one at
 drawn times and terms; after a power loss of every node, each log holds every term it granted"
family at: 8 put: [:seed :rules |
  | s draw bad |
  s := simOf value: seed value: rules value: ids.
  draw := Random seed: seed * 7919 + 17.
  1 to: 30 do: [:k |
    | from to |
    from := ids at: (draw nextInt: 3).
    to := ids at: (draw nextInt: 3).
    from = to ifFalse: [
      s inject: (request value: s value: from value: ((draw nextInt: 6) * 4096) + (ids indexOf: from) - 1 value: 7)
        to: to at: g + (k * 300000) + (draw nextInt: 200000)]].
  run value: s.
  ids do: [:id | s crash: id unsynced: #drop].
  bad := ids reject: [:granter |
    | terms |
    terms := OrderedCollection new.
    ids do: [:id | terms addAll: (grantTerms value: rules value: id value: granter)].
    terms allSatisfy: [:term | (s diskOf: granter) loggedRoots promise >= term]].
  ((ids inject: 0 into: [:n :id | n + (rules repliesAt: id) size]) > 0 and: [bad isEmpty])
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': a grant of ' , bad printString , ' not durable']].

"(10) started over empty logs"
family at: 9 put: [:seed :rules |
  | s t solo starts entries |
  starts := [:aSim :id | (aSim trace select: [:l | l includesSubstring: id , ' accept PBStartNode']) size].
  entries := [:aSim :id | (aSim diskOf: id) loggedRoots entries collect: [:e | e kind]].
  solo := PBSim seed: seed ids: #('n0') rules: rules options: Dictionary new.
  solo faults: faults.
  run value: solo.
  t := PBSim seed: seed ids: four rules: rules options: Dictionary new.
  t faults: faults.
  run value: t.
  t inject: (request value: t value: 'n0' value: 4096 value: 7) to: 'n1' at: g.
  t inject: (request value: t value: 'n2' value: 4098 value: 9) to: 'n3' at: g + 100000.
  run value: t.
  ({ starts value: solo value: 'n0'. entries value: solo value: 'n0'. (solo diskOf: 'n0') syncedSize.
     (solo nodeAt: 'n0') acceptor isRejoined.
     four collect: [:id | starts value: t value: id]. four collect: [:id | entries value: t value: id].
     (t diskOf: 'n3') syncedSize. four collect: [:id | (t nodeAt: id) acceptor isRejoined].
     reasons value: rules value: 'n0' value: 'n1'. reasons value: rules value: 'n2' value: 'n3' }
    = { 1. #(4). 1. true. #(1 1 1 1). #(#() #() #() #(4)). 1. #(false false false true).
        #('rejoining') asSet. #('learner') asSet })
    ifTrue: [nil] ifFalse: ['seed ' , seed printString , ': ' , (entries value: t value: 'n3') printString , ' '
      , (four collect: [:id | starts value: t value: id]) printString]].

one := (1 to: 8) asArray collect: [:k | failuresOf value: (family at: k) value: GrantRules].
c that: 'grant then busy for another holder' is: (one at: 1) equals: #().
c that: 'release ends busy at once' is: (one at: 2) equals: #().
c that: 'startup grace refuses (efficiency only)' is: (one at: 3) equals: #().
c that: 'restart restores the promise from the log, never below it (L17)' is: (one at: 4) equals: #().
c that: 'learner never grants' is: (one at: 5) equals: #().
c that: 'renew keeps the term without a log write' is: (one at: 6) equals: #().
c that: 'a refused higher request does not end the owner''s renewals' is: (one at: 7) equals: #().
c that: 'no reply before the promise is synced' is: (one at: 8) equals: #().
c that: 'started over empty logs, a lone voter and a learner log the rejoined marker, the voters rejoin'
  is: (failuresOf value: (family at: 9) value: GrantRules) equals: #().

"(9) The plant fails family 7 on every seed."
two := failuresOf value: (family at: 7) value: PlantRenewStale.
c that: 'PlantRenewStale makes its family fail' is: two size equals: 40.

c report displayNl.
