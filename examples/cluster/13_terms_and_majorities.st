"EXPECT: 13 terms and majorities ok (12 checks)"
"Cluster lesson 13: the values every member computes alike, before any message is sent.
 Tutorial chapter: docs/tutorial/13-cluster-concepts.md

 What it teaches:
 - the voters: by default the first three ids in code point order; the others are learners;
   a majority is V // 2 + 1 voters;
 - terms are ballots: the smallest number above everything known whose low 12 bits are the
   proposer's rank, so two members never ask for the same term;
 - the lease: a holder believes it for leaseDuration - driftMargin, at most a third of what the
   granters promise; a smaller margin is refused (R78b);
 - the send reserve and the request timeout must fit inside that belief;
 - options of tiered storage are refused, not ignored.

 Pure values: nothing runs, nothing waits.

 Run it: STPATH=<repository>/src protost 13_terms_and_majorities.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson peers three five config |
lesson := Lesson named: '13 terms and majorities'.

peers := [:ids | ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400]].

"Three members: all three vote; two of them are a majority."
three := PBMembership peers: (peers value: #('n2' 'n0' 'n1')) voters: nil.
lesson check: 'ranks follow the sorted ids' is: three ids equals: #('n0' 'n1' 'n2').
lesson check: 'three voters' is: three voters equals: #('n0' 'n1' 'n2').
lesson check: 'a majority of three is two' is: three majority equals: 2.

"Five members: still three voters by default; n3 and n4 are learners."
five := PBMembership peers: (peers value: #('n0' 'n1' 'n2' 'n3' 'n4')) voters: nil.
lesson check: 'five members, three voters' is: { five voters. five isVoter: 'n4' } equals: { #('n0' 'n1' 'n2'). false }.
lesson check: 'an even voter set is refused' signals: PBValidationError containing: 'odd'
  during: [PBMembership peers: (peers value: #('n0' 'n1' 'n2' 'n3')) voters: #('n0' 'n1' 'n2' 'n3')].

"Terms are ballots qualified by the proposer's rank (low 12 bits)."
lesson check: 'the first ballot of rank 0 and of rank 1'
  is: { PBMembership ballotAfter: 0 rank: 0. PBMembership ballotAfter: 0 rank: 1 } equals: #(4096 1).
lesson check: 'above a term seen, the next ballot of rank 0'
  is: (PBMembership ballotAfter: 4097 rank: 0) equals: 8192.
lesson check: 'the rank is the term modulo 4096' is: (PBMembership ballotAfter: 70000 rank: 2) \\ 4096 equals: 2.

"The lease: the configuration answers microseconds; options are milliseconds."
config := PBClusterConfig nodeId: 'n0' peers: (peers value: #('n0' 'n1' 'n2')) options: (Dictionary new
  at: #leaseDuration put: 2000; yourself).
lesson check: 'driftMargin defaults to 2/3 of the lease, the belief to a third'
  is: { config driftMargin. config belief } equals: #(1333334 666666).
lesson check: 'a margin below 2/3 of the lease is refused (R78b)' signals: PBValidationError containing: 'R78b'
  during: [PBClusterConfig nodeId: 'n0' peers: (peers value: #('n0' 'n1' 'n2')) options: (Dictionary new
    at: #leaseDuration put: 2000; at: #driftMargin put: 200; yourself)].
lesson check: 'a request timeout longer than the belief is refused' signals: PBValidationError containing: 'belief'
  during: [PBClusterConfig nodeId: 'n0' peers: (peers value: #('n0' 'n1' 'n2')) options: (Dictionary new
    at: #leaseDuration put: 2000; at: #requestTimeout put: 700; yourself)].
lesson check: 'an option of tiered storage is refused, not ignored' signals: PBNotSupportedError containing: 'Phase D'
  during: [PBClusterConfig nodeId: 'n0' peers: (peers value: #('n0' 'n1' 'n2')) options: (Dictionary new
    at: #fetchTimeout put: 100; yourself)].
lesson finish.
