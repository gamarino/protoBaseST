"EXPECT: ok 6"
"The rejoin of an empty acceptor log (cluster/rejoin.st, CP 'A node that lost its disk', R51,
 R78a, L13, L14) in the simulator (_sim.st), proto_db test_cluster_rejoin, _rejoin_fresh and
 _rejoin_records. The families, the hooked simulator and the planted wrong rules are in
 _rejoin.st; the product rules run every rejoin, base choice and commit. (1) The R78a schedule:
 a wiped acknowledger restarts with its timer 1.3, 2 and 3 times as fast as the holder's, the
 holder's timer running or standing still: no acknowledged commit is lost, R is never
 committed, each rejoin takes one ballot. (2) PlantRejoinByWaiting (it waits restartGrace on its
 own clock instead of the ballot) loses R on the stalled-timer schedule (S4). (3) A cluster's
 first start completes without a ballot and leaves termsSeen 0 (R51); a late first start after
 a term was asked completes by a ballot ('rootless'). (4) A rejoined node never replicates
 below its ballot (L14): a permission of the owner's older term sends nothing (#none). (5)
 PlantReplicateBelowBallot sends it, and the voters refuse it (#unknown). (6) Losing a majority
 of logs: the wiped nodes stay rejoining until forceRejoin; the survivor's base is then a
 PBCorruptionError naming forceRejoin, and forceRejoin on it forgets the lost commit."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_rejoin'.

| c runs out |
c := Check new.

"(1)"
runs := OrderedCollection new.
#(1 2) do: [:seed |
  { 13/10. 2. 3 } do: [:rate |
    #(false true) do: [:stall | runs add: (RejoinFamilies r78a: RejoinRules new seed: seed rate: rate stall: stall)]]].
c that: 'R78a: no commit lost at wiped rates 1.3, 2, 3, holder running or stalled ({ violation. a. b. ballots })'
  is: (runs collect: [:r | { r first. r at: 2. r at: 3. r at: 4 }]) asArray asSet asArray
  equals: { { nil. #unknown. #acknowledged. 1 } }.

"(2)"
out := RejoinFamilies r78a: PlantRejoinByWaiting new seed: 1 rate: 13/10 stall: true.
c that: 'PlantRejoinByWaiting is caught (S4: R acknowledged, then dropped; no ballot)'
  is: { (out first ifNil: ['']) includesSubstring: 'S4: the acknowledged commit ''a'''. out at: 2. out at: 4 }
  equals: { true. #acknowledged. 0 }.

"(3)"
c that: 'first start: new, no ballot, termsSeen 0, a commits; late first start: rootless, by ballot'
  is: { (RejoinFamilies firstStart: RejoinRules new seed: 1) asArray. (RejoinFamilies lateStart: RejoinRules new seed: 1) asArray }
  equals: { { nil. #(0 0 0). #(1 1 1). 0. #acknowledged }. { nil. true. #(1 1). #acknowledged. #(true true) } }.

"(4)"
c that: 'L14: a rejoined node sends nothing below its ballot ({ violation. x. sent below. ballot above the term })'
  is: (#(1 2) collect: [:seed | (RejoinFamilies belowBallot: RejoinRules new seed: seed) asArray])
  equals: #(#(nil #none 0 true) #(nil #none 0 true)).

"(5)"
out := RejoinFamilies belowBallot: PlantReplicateBelowBallot new seed: 1.
c that: 'PlantReplicateBelowBallot is caught (it sends below its ballot; the voters refuse: unknown)'
  is: { out first. out at: 2. (out at: 3) > 0 }
  equals: { nil. #unknown. true }.

"(6)"
c that: 'majority loss: stuck until forceRejoin, the guard names forceRejoin, forceRejoin on the survivor'
  is: (RejoinFamilies majorityLoss: RejoinRules new seed: 1) asArray
  equals: { #(false false). #(true true). true. #(true true). #acknowledged. #failed }.

c report displayNl.
