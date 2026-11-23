"EXPECT: ok 4"
"An IVF retrain in a cluster commit (final review M7; ruling 69: the retrain stays under the write
 permission, as proto_db's transactions.py runs it). A blind write of one member onto a
 vector-indexed dictionary (t newDictionary setAt:value:, as tests/unit/vec_collections.st (8)) is
 merged onto the current dictionary in the round's build, under the permission; the member it adds
 crosses the ivf_flat index's retrain threshold (nlist 2, retrain_growth 1.5: trained at 3 members,
 retrained at 5), so k-means runs inside that build.

 (1) One node, leaseDuration 3000 and driftMargin 2000 (a permission of at most 1000 ms, less
 sendReserve): the build is made to outlast the permission, and the commit is refused, with its
 retries, as a retryable PBConflictError with the CC18 text, naming leaseDuration and saying that
 nothing was replicated. (2) The committed root is unchanged: the dictionary still holds its four
 members and its index the training of 3. (3) The same commit, its build as long, on a node whose
 lease is long enough (leaseDuration 30000, driftMargin 20000: a permission of up to 10 s; a startupGrace of 500 ms, as
 the node starts a new cluster, so its first permission does not wait out a lease of 30 s), commits: the dictionary holds the
 five members and its index was retrained at 5, in the build. (4) On the first node with no delay
 the same commit commits too.

 How the build outlasts the permission: the RoundSeam's buildDelay (tests/unit/_cluster_commit.st)
 makes the build sleep 1300 ms before it merges, as tests/unit/cluster_commit_path.st (8) does. A
 real retrain takes that long only for an index of several hundred members (bench VB3/VB5), which
 would make this test slow and its outcome depend on the machine's speed; the refusal does not
 depend on what made the build long (mayReplicate:now: compares the permission left with
 sendReserve), and (3) and (4) show the retrain does run in that build. The delay is longer than
 the first node's whole permission and far shorter than the second's, so neither outcome depends on
 timing; every wait is a condition with a deadline (CommitKit)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.

| c base defs rec setup blind kitShort kitLong spaceShort spaceLong dbShort dbLong r rootOf seam out |
c := Check new.
base := FileSystem temp / ('pbst-cluster-vretrain-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.

rec := [:i | PBObject withAll: { 'n' -> i. 'vec' -> (PBTuple withAll: { i asFloat. (i * i \\ 7) asFloat }) }].
defs := [PBVectorIndex name: 'ivf' keySpec: (PBKeySpec path: 'vec') dim: 2 metric: 'l2' backend: 'ivf_flat'
  params: (Dictionary new at: 'nlist' put: 2; at: 'retrain_growth' put: 1.5; at: 'train_iters' put: 2;
    at: 'seed' put: 7; yourself)].
"A dictionary of members 1 to 4 under the ivf index: trained at 1, 2 and 3 (each reaches 1.5 times
 the size trained before), not at 4 (4 < 4.5)."
setup := [:t | | d |
  d := PBDictionary new addIndex: defs value.
  1 to: 4 do: [:i | d := d setAt: i value: (rec value: i)].
  t setRootObject: 'd' value: d].
"The blind write of member 5 (5 >= 4.5: the merge retrains the index)."
blind := [:t | t setRootObject: 'd' value: (t newDictionary setAt: 5 value: (rec value: 5))].
"{ the keys of the committed dictionary. its index's trained size } on aKit's node anId."
rootOf := [:aKit :anId | | d |
  d := aKit root: 'd' of: 'db' in: (aKit committedSpaceRoot: anId).
  { d keys asArray. (d getIndex: 'ivf') trainedSize }].

kitShort := CommitKit ids: #('s0') dir: base / 'short'
  options: (Dictionary new at: #leaseDuration put: 3000; at: #driftMargin put: 2000; at: #requestTimeout put: 300; yourself).
spaceShort := kitShort open: 's0'.
kitShort waitUntil: [((kitShort node: 's0') stats at: 'rejoining') not].
dbShort := spaceShort newDatabase: 'db'.
dbShort run: setup.

"(1) and (2)"
seam := SeamRound resetSeamOf: 's0'.
seam buildDelay swap: [:x | 1300].
r := kitShort settle: (Worker new asActor once: dbShort block: blind retries: 1).
seam buildDelay swap: [:x | nil].
c that: '(1) a retrain in a build longer than the permission: a PBConflictError with the CC18 text naming leaseDuration'
  is: { r first. r at: 2. ((r at: 3) includesSubstring: 'leaseDuration'). ((r at: 3) includesSubstring: 'Nothing was replicated') }
  equals: { #error. #PBConflictError. true. true }.
c that: '(2) the refused commits wrote nothing: four members, the index trained at 3'
  is: (rootOf value: kitShort value: 's0') equals: { #(1 2 3 4). 3 }.

"(3) the same commit, as long a build, under a long enough lease."
kitLong := CommitKit ids: #('s1') dir: base / 'long'
  options: (Dictionary new at: #leaseDuration put: 30000; at: #driftMargin put: 20000; at: #requestTimeout put: 300;
    at: #startupGrace put: 500; yourself).
spaceLong := kitLong open: 's1'.
kitLong waitUntil: [((kitLong node: 's1') stats at: 'rejoining') not].
dbLong := spaceLong newDatabase: 'db'.
dbLong run: setup.
seam := SeamRound resetSeamOf: 's1'.
seam buildDelay swap: [:x | 1300].
out := kitLong settle: (Worker new asActor once: dbLong block: blind retries: 0).
seam buildDelay swap: [:x | nil].
c that: '(3) under a lease whose permission outlasts the build, the same commit commits, the index retrained at 5 in the build'
  is: { out first. rootOf value: kitLong value: 's1' } equals: { #ok. { #(1 2 3 4 5). 5 } }.

"(4)"
out := kitShort settle: (Worker new asActor once: dbShort block: blind retries: 0).
c that: '(4) on the short lease with no delay, the same commit commits and retrains'
  is: { out first. rootOf value: kitShort value: 's0' } equals: { #ok. { #(1 2 3 4 5). 5 } }.

kitShort shutdown.
kitLong shutdown.
base deleteAll.
c report displayNl.
