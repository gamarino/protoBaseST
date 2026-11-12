"EXPECT: ok 39"
"A transaction after its end (plan Task 18, Review Focus 3; ProtoBase
 Transaction._check_active and commit): commit twice, getRootObject: after abort, commit
 after a failed commit (which leaves the transaction aborted), and every write message and
 factory after the end each signal PBUserError naming the state. An empty commit (no
 writes, reads or not) is a no-op: history size unchanged (plan call C16)."
Import from: 'protobase'.
Import from: '_check'.

| c base space db tx a b size messages |
c := Check new.
base := FileSystem temp / ('pbst-tx-after-end-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.

"An empty commit."
size := db history size.
tx := db newTransaction.
tx getRootObject: 'x'.
tx commit.
c that: 'an empty commit ends the transaction' is: tx isActive equals: false.
c that: 'and publishes nothing' is: db history size equals: size.
c that: 'commit twice' signals: PBUserError containing: 'committed' during: [tx commit].

tx := db newTransaction.
tx setRootObject: 'x' value: 1.
tx commit.
c that: 'one version more' is: db history size equals: size + 1.
c that: 'commit twice after a real commit' signals: PBUserError containing: 'committed' during: [tx commit].
c that: 'getRootObject: after commit' signals: PBUserError during: [tx getRootObject: 'x'].

tx := db newTransaction.
tx abort.
c that: 'getRootObject: after abort' signals: PBUserError containing: 'aborted' during: [tx getRootObject: 'x'].
c that: 'commit after abort' signals: PBUserError containing: 'aborted' during: [tx commit].

"A failed commit leaves the transaction aborted."
a := db newTransaction.
b := db newTransaction.
a getRootObject: 'x'.
b setRootObject: 'x' value: 2.
b commit.
a setRootObject: 'x' value: 3.
c that: 'the commit fails' signals: PBConflictError during: [a commit].
c that: 'a failed commit aborts' is: a isActive equals: false.
c that: 'commit after a failed commit' signals: PBUserError containing: 'aborted' during: [a commit].
c that: 'abort after a failed commit' signals: PBUserError containing: 'aborted' during: [a abort].

"Every write message and factory after the end."
messages := {
  'setRootObject:value:' -> [:t | t setRootObject: 'x' value: 1].
  'setRootObject:value:replace:' -> [:t | t setRootObject: 'x' value: 1 replace: true].
  'removeRootObject:' -> [:t | t removeRootObject: 'x'].
  'newMutable:value:' -> [:t | t newMutable: 'm' value: 1].
  'setMutable:value:' -> [:t | t setMutable: 'm' value: 1].
  'removeMutable:' -> [:t | t removeMutable: 'm'].
  'PBMutableObject set:value:' -> [:t | (PBMutableObject name: 'm') set: t value: 1].
  'newList' -> [:t | t newList].
  'newDictionary' -> [:t | t newDictionary].
  'newHashDictionary' -> [:t | t newHashDictionary].
  'newSet' -> [:t | t newSet].
  'newCountedSet' -> [:t | t newCountedSet].
  'newObject:' -> [:t | t newObject: { 'a' -> 1 }] }.
messages do: [:each |
  c that: each key , ' after commit' signals: PBUserError during: [each value value: b].
  c that: each key , ' after abort' signals: PBUserError during: [each value value: a]].
c that: 'nothing more was published' is: db history size equals: size + 2.

space close.
base deleteAll.
c report displayNl.
