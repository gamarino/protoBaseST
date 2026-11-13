"EXPECT: ok 20"
"PBPeer and PBMembership (cluster/members.st): the values every member of a cluster computes
 like the others (format spec, 'Values a member must compute'; proto_db cluster/coordinator.py
 _voter_set, ballot_after, the fingerprint). Ranks are indices in the ids sorted in code point
 order; the default voters are the first three ids (every member of a smaller cluster); an
 explicit voter set of a cluster of three or more is odd and has at least three members; the
 fingerprint is the CRC-32 of the UTF-8 of the sorted voter ids joined with ','. The 200 floors
 of the ballot check come from a seeded generator, so the run is the same every time. The
 fingerprints 3456220713 ('B,a,z') and 3464710033 (voters z, U+00E9, U+1F600 of the members a,
 z, U+00E9, U+FFFF, U+1F600) are those proto_db's _voter_set and zlib.crc32 give. protoST has no
 Symbol distinct from String ('n0' asSymbol is the String 'n0'), so a Symbol voter id is the
 String id: given twice under both spellings it is a duplicate."
Import from: 'protobase'.
Import from: '_check'.
| c peers members five rng distinct |
c := Check new.
peers := [:ids | ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7000]].
members := PBMembership peers: (peers value: #('n2' 'n0' 'n1')) voters: nil.
c that: 'the ranks follow the sorted ids' is: (#('n0' 'n1' 'n2') collect: [:id | members rankOf: id]) equals: #(0 1 2).
c that: 'code point order puts Z before a' is: (PBMembership peers: (peers value: #('a' 'Z')) voters: nil) ids equals: #('Z' 'a').
five := PBMembership peers: (peers value: #('n4' 'n3' 'n2' 'n1' 'n0')) voters: nil.
c that: 'the default voters of 5 members are the first three' is: { five voters. five isVoter: 'n2'. five isVoter: 'n3'. (five peerNamed: 'n3') nodeId }
  equals: { #('n0' 'n1' 'n2'). true. false. 'n3' }.
c that: 'every member of a 2-member cluster votes' is: (PBMembership peers: (peers value: #('b' 'a')) voters: nil) voters equals: #('a' 'b').
c that: 'an explicit voter set of 4 is refused' signals: PBValidationError
  during: [PBMembership peers: (peers value: #('n4' 'n3' 'n2' 'n1' 'n0')) voters: #('n0' 'n1' 'n2' 'n3')].
c that: 'duplicate ids are refused' signals: PBValidationError
  during: [PBMembership peers: (peers value: #('n0' 'n1' 'n0')) voters: nil].
c that: '4097 members are refused' signals: PBValidationError
  during: [PBMembership peers: (peers value: ((1 to: 4097) collect: [:i | 'n' , i printString])) voters: nil].
c that: 'the majority of 3 voters is 2' is: members majority equals: 2.
c that: 'the fingerprint is the CRC-32 of the joined voter ids' is: members fingerprint equals: 'n0,n1,n2' utf8Encoded crc32.
c that: 'ballotAfter: 0 rank: 5' is: (PBMembership ballotAfter: 0 rank: 5) equals: 5.
c that: 'ballotAfter: 4101 rank: 5' is: (PBMembership ballotAfter: 4101 rank: 5) equals: 8197.
c that: 'ballotAfter: 4100 rank: 5' is: (PBMembership ballotAfter: 4100 rank: 5) equals: 4101.
rng := Random seed: 7.
distinct := (1 to: 200) allSatisfy: [:i |
  | floor ranks ballots |
  floor := rng between: 0 and: 1000000.
  ranks := { rng between: 0 and: 4095. rng between: 0 and: 4095 }.
  ballots := ranks collect: [:r | PBMembership ballotAfter: floor rank: r].
  (ranks first = ranks last) or: [ballots first ~= ballots last
    and: [(ballots allSatisfy: [:b | b > floor]) and: [(ballots collect: [:b | b \\ 4096]) = ranks]]]].
c that: 'two ranks never produce the same ballot' isTrue: distinct.
c that: 'rankOf: an unknown id is refused' signals: PBValidationError during: [members rankOf: 'q'].
c that: 'peerNamed: an unknown id is refused' signals: PBValidationError during: [members peerNamed: 'q'].
c that: 'an empty peer list is refused' signals: PBValidationError during: [PBMembership peers: #() voters: nil].
c that: 'refoundStep is 2^44' is: PBMembership refoundStep equals: (2 raisedTo: 44).
c that: 'the fingerprint of B,a,z' is: (PBMembership peers: (peers value: #('z' 'a' 'B')) voters: nil) fingerprint equals: 3456220713.
c that: 'code point order and fingerprint beyond ASCII' is: [| e ffff emoji m |
  e := String with: (Character value: 16rE9).
  ffff := String with: (Character value: 16rFFFF).
  emoji := String with: (Character value: 16r1F600).
  m := PBMembership peers: (peers value: { emoji. 'z'. ffff. e. 'a' }) voters: { 'z'. e. emoji }.
  { m ids = { 'a'. 'z'. e. ffff. emoji }. m voters = { 'z'. e. emoji }. m fingerprint }] value
  equals: #(true true 3464710033).
c that: 'a voter given as Symbol and String is a duplicate' signals: PBValidationError containing: 'distinct'
  during: [PBMembership peers: (peers value: #('n0' 'n1' 'n2')) voters: { 'n0' asSymbol. 'n0'. 'n1' }].
c report displayNl.
