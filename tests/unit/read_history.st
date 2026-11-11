"EXPECT: ok 33"
"The read-only space API (plan Task 12) on copies of the database and polyglot vectors
 (never the vendored files): PBObjectSpace, PBDatabase history (newest first, through
 previous), PBHistoryEntry, snapshotAt: and PBSnapshot, the identity check of a
 snapshot of another database (PBReferenceError), a DatabaseRoot without mutables
 (PBCorruptionError) and the lock timeout argument. The values are those ProtoBase
 v2.0.0rc1 answers on the same spaces."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base copy space db h newest oldest middle snap people other otherDb b dbRoot dict idx spaceRoot old names |
c := Check new.
base := FileSystem temp / ('pbst-read-history-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
copy := [:name |
  | dir |
  dir := base / name.
  dir ensureCreateDirectory.
  ('../conformance/vectors/' , name) asFileReference files do: [:f | f copyTo: dir / f basename].
  dir].

space := PBObjectSpace storage: (PBFileStorage path: (copy value: 'database')).
c that: 'the default lock timeout (ms)' is: space lockTimeout equals: 30000.
c that: 'listDatabases' is: space listDatabases asArray equals: #('db').
c that: 'openDatabase: an absent name' signals: PBValidationError containing: 'nope' during: [space openDatabase: 'nope'].
c that: 'openDatabase: an empty name' signals: PBValidationError during: [space openDatabase: ''].
db := space openDatabase: 'db'.
c that: 'the database name' is: db name equals: 'db'.
h := db history.
c that: 'three versions' is: h size equals: 3.
c that: 'newest first' is: (h collect: [:e | e version]) asArray equals: #(2 1 0).
c that: 'committedAt descends' isTrue: ((PBKeys compare: (h at: 1) committedAt with: (h at: 2) committedAt) > 0
  and: [(PBKeys compare: (h at: 2) committedAt with: (h at: 3) committedAt) > 0]).
c that: 'the commit time of version 0' is: (PBNotation describe: (h at: 3) committedAt) printString
  equals: (PBNotation describe: (DateTime year: 2026 month: 11 day: 10 hour: 12 minute: 0 second: 1
    microsecond: 0 fold: 0 zone: (ZoneOffset microseconds: 0 name: 'UTC'))) printString.
newest := h at: 1.
middle := h at: 2.
oldest := h at: 3.
names := #('bag' 'hash' 'hnsw' 'invoice' 'ivf' 'multi' 'people' 'set' 'tags' 'vectors').
c that: 'the newest entry root names' is: newest rootNames asArray equals: names.
c that: 'its mutable names' is: newest mutableNames asArray equals: #('counter').
c that: 'its mutable value' is: (newest getMutable: 'counter') equals: 5.
c that: 'an absent mutable' is: (newest getMutable: 'nope') equals: nil.
c that: 'a history entry has no getRootObject:' isTrue: (newest respondsTo: #getRootObject:) not.
c that: 'the middle entry' is: middle rootNames asArray equals: #('people').
c that: 'the middle entry has no mutables' is: middle mutableNames asArray equals: #().

snap := db snapshotAt: oldest.
c that: 'the snapshot of the oldest entry is version 0' is: snap version equals: 0.
c that: 'version 0 has no roots' is: snap rootNames asArray equals: #().
c that: 'version 0 has no mutables' is: snap mutableNames asArray equals: #().
c that: 'an absent root reads as nil' is: (snap getRootObject: 'people') equals: nil.
c that: 'its commit time' is: (PBKeys compare: snap committedAt with: oldest committedAt) equals: 0.
snap := db snapshotAt: middle.
people := snap getRootObject: 'people'.
c that: 'version 1 holds people' is: people class equals: PBDictionary.
c that: 'people of version 1' is: people keys asArray equals: #('ann' 'bob' 'cid').
c that: 'snapshotAt: a snapshot' is: (db snapshotAt: snap) version equals: 1.
c that: 'snapshotAt: the newest entry' is: ((db snapshotAt: newest) getRootObject: 'counter') equals: nil.
c that: 'getRootObject: an empty name' signals: PBValidationError during: [snap getRootObject: ''].
c that: 'snapshotAt: something else' signals: PBReferenceError during: [db snapshotAt: 42].

"The polyglot space also holds a database 'db', of another origin."
other := PBObjectSpace storage: (PBFileStorage path: (copy value: 'polyglot')) lockTimeout: 50.
c that: 'storage:lockTimeout:' is: other lockTimeout equals: 50.
otherDb := other openDatabase: 'db'.
c that: 'a version of another database of the same name' signals: PBReferenceError containing: 'another' during: [
  db snapshotAt: otherDb history first].
other close.
c that: 'a lock timeout must be a positive Integer' signals: PBValidationError during: [
  PBObjectSpace storage: (PBFileStorage path: (base / 'unused')) lockTimeout: 0].

"A DatabaseRoot written before D35: no mutables."
b := SpaceBuilder segment: (ByteArray fromHex: '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b').
idx := b add: 3 oid: 1 state: { 'root' -> nil }.
dict := b add: 6 oid: 2 state: { 'root' -> nil. 'count' -> 0. 'indexes' -> idx }.
dbRoot := b add: 18 oid: 3 state: { 'objects' -> dict. 'version' -> 0.
  'committed_at' -> (DateTime year: 2020 month: 1 day: 1 hour: 0 minute: 0 second: 0 microsecond: 0 fold: 0
    zone: (ZoneOffset microseconds: 0 name: 'UTC')). 'previous' -> nil }.
dict := b add: 6 oid: 4 state: { 'root' -> (b add: 0 oid: 5 state: { 'key' -> 'old'. 'value' -> dbRoot.
  'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }). 'count' -> 1. 'indexes' -> idx }.
spaceRoot := b add: 17 oid: 6 state: { 'databases' -> dict }.
old := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'old' root: spaceRoot)).
c that: 'the old database is listed' is: old listDatabases asArray equals: #('old').
c that: 'a DatabaseRoot without mutables' signals: PBCorruptionError containing: 'mutables' during: [
  (old openDatabase: 'old') history].
old close.

space close.
c that: 'a closed space' signals: PBClosedError during: [space listDatabases].
base deleteAll.
c report displayNl.
