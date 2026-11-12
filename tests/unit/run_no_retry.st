"EXPECT: ok 6"
"Database run: (plan Task 19; ProtoBase Database.run): any error but PBConflictError aborts the attempt and
 propagates after exactly one attempt; PBOutcomeUnknownError is never retried. A block that ends its
 transaction itself is not committed again."
Import from: 'protobase'.
Import from: '_check'.

| c base space db attempts tx r |
c := Check new.
base := FileSystem temp / ('pbst-run-no-retry-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
attempts := Atom on: 0.

c that: 'an Error propagates' signals: Error containing: 'fault' during: [
  db run: [:t | attempts swap: [:v | v + 1]. tx := t. t setRootObject: 'a' value: 1. Error signal: 'fault'] retries: 5 backoff: #(0 0)].
c that: 'after exactly one attempt' is: attempts value equals: 1.
c that: 'aborted, nothing committed' is: { tx isActive. (db newTransaction getRootObject: 'a') } equals: { false. nil }.

attempts swap: [:v | 0].
c that: 'PBOutcomeUnknownError propagates' signals: PBOutcomeUnknownError during: [
  db run: [:t | attempts swap: [:v | v + 1]. PBOutcomeUnknownError signal: 'unknown'] retries: 5 backoff: #(0 0)].
c that: 'and is never retried' is: attempts value equals: 1.

r := db run: [:t | t setRootObject: 'b' value: 2. t commit. 'committed by the block'].
c that: 'a block that commits itself is answered without a second commit' is: r equals: 'committed by the block'.
space close.
base deleteAll.
'ok 6' displayNl.
