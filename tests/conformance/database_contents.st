"EXPECT: database contents ok (database contents 20/20)"
"The database section read as a database (README, 'Using the vectors', 7, second
 part), on a copy of vectors/database: following space.root -> SpaceRoot ->
 databases['db'] -> DatabaseRoot, PBNotation describeDatabase: of a snapshot of the
 current version must be the manifest's contents (roots, mutables, indexes, origin),
 with ConformanceInvoice (_model.st) registered. Each part is also checked on its own
 (the database list, the root names, each root, the mutables, the indexes, the
 origin), so an expected difference names exactly what differs, and the trained
 ivf_flat index must hold the listed centroids, trained size and list of every stored
 vector (computing the list assignment is a writer's check: the prototype never
 writes a vector index). The exact index of the 'vectors' root and the hnsw index of
 the 'hnsw' root (proto_db tests/conformance/generate.py:633-643) pass validate:
 against their collections, and their explain is proto_db's (vectors phase V3,
 Addendum V 5.2): the manifest does not record explain, so the expected entries are
 proto_db v2.0.0rc4's VectorIndex.explain() of these two indexes, read from this
 vector's database with numpy and hnswlib blocked and written here. The explain of the
 ivf_flat index of the 'ivf' root is proto_db's too, read the same way (its lists and
 trained_size need no training; validating it needs its lists, the vectors phase's V4).
 The ids are 'database', 'databases', 'root names', 'root <name>', 'mutables',
 'indexes', 'origin', 'ivf', 'ivf explain', 'vector index vectors' and 'vector index
 hnsw'."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest contents dir space db snap run mismatch ids expectedWhole names ivf |
manifest := Vectors manifest.
contents := (manifest at: 'database') at: 'contents'.
names := (contents at: 'roots') collect: [:pair | pair at: 1].
ids := { 'database'. 'databases'. 'root names' } , (names collect: [:n | 'root ' , n])
  , #('mutables' 'indexes' 'origin' 'ivf' 'ivf explain' 'vector index vectors' 'vector index hnsw').
run := VectorRun section: 'database_contents' ids: ids.
mismatch := [:what :actual :expected |
  actual = expected ifTrue: [nil] ifFalse: [
    what , ' is ' , (Vectors json stringify: actual) , ', the manifest says ' , (Vectors json stringify: expected)]].
dir := Vectors copySpace: 'database'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
db := space openDatabase: 'db'.
snap := db snapshotAt: db history first.
expectedWhole := Dictionary new.
#('roots' 'mutables' 'indexes' 'origin') do: [:k | expectedWhole at: k put: (contents at: k)].
run begin.
run stage: 'describe' of: 'database' do: [
  mismatch value: 'describeDatabase:' value: (PBNotation describeDatabase: snap) value: expectedWhole].
run end: 'database'.
run begin.
run stage: 'describe' of: 'databases' do: [
  mismatch value: 'listDatabases' value: space listDatabases asArray value: #('db')].
run end: 'databases'.
run begin.
run stage: 'describe' of: 'root names' do: [
  mismatch value: 'rootNames' value: snap rootNames asArray value: names].
run end: 'root names'.
(contents at: 'roots') do: [:pair |
  | id |
  id := 'root ' , (pair at: 1).
  run begin.
  run stage: 'describe' of: id do: [
    mismatch value: id value: (PBNotation describeObject: (snap getRootObject: (pair at: 1))) value: (pair at: 2)].
  run end: id].
run begin.
run stage: 'describe' of: 'mutables' do: [
  mismatch value: 'the mutables' value: (PBNotation describeMutables: snap) value: (contents at: 'mutables')].
run end: 'mutables'.
run begin.
run stage: 'describe' of: 'indexes' do: [
  mismatch value: 'the indexes' value: (PBNotation describeIndexes: snap) value: (contents at: 'indexes')].
run end: 'indexes'.
run begin.
run stage: 'describe' of: 'origin' do: [
  mismatch value: 'the origin' value: (PBNotation describeOrigin: snap) value: (contents at: 'origin')].
run end: 'origin'.
run begin.
run stage: 'describe' of: 'ivf' do: [
  | index actual |
  index := (snap getRootObject: 'ivf') getIndex: 'ivf'.
  actual := Dictionary new.
  actual at: 'centroids' put: (index centroids asArray collect: [:v | v asArray collect: [:x | PBNotation describe: x]]).
  actual at: 'trained_size' put: index trainedSize.
  actual at: 'lists' put: (index storeEntries collect: [:entry |
    { entry key at: 1. (entry value at: 3) asArray collect: [:x | PBNotation describe: x] }]).
  mismatch value: 'the ivf index' value: actual value: (contents at: 'ivf')].
run end: 'ivf'.
run begin.
run stage: 'explain' of: 'ivf explain' do: [
  mismatch value: 'explain of ivf' value: ((snap getRootObject: 'ivf') getIndex: 'ivf') explain associations
    value: { 'index' -> 'ivf'. 'kind' -> 'VectorIndex'. 'key' -> 'emb'. 'dim' -> 2. 'metric' -> 'l2'. 'backend' -> 'ivf_flat'.
      'params' -> (PBFrozenDict withAssociations: { 'nlist' -> 2. 'nprobe' -> 1. 'retrain_growth' -> 4.0. 'seed' -> 1. 'train_iters' -> 3 }).
      'entries' -> 5. 'vectors' -> 4. 'members' -> 4. 'invalid' -> 1. 'lists' -> 2. 'trained_size' -> 2 }].
run end: 'ivf explain'.
{ { 'vectors'. 'near'. {
      'index' -> 'near'. 'kind' -> 'VectorIndex'. 'key' -> 'emb'. 'dim' -> 2. 'metric' -> 'l2'. 'backend' -> 'exact'.
      'params' -> (PBFrozenDict withAssociations: { 'numpy' -> true }).
      'entries' -> 2. 'vectors' -> 2. 'members' -> 2. 'invalid' -> 0 } }.
  { 'hnsw'. 'hnsw'. {
      'index' -> 'hnsw'. 'kind' -> 'VectorIndex'. 'key' -> 'emb'. 'dim' -> 2. 'metric' -> 'cosine'. 'backend' -> 'hnsw'.
      'params' -> (PBFrozenDict withAssociations: { 'M' -> 16. 'ef_construction' -> 200. 'ef_search' -> 64. 'seed' -> 0 }).
      'entries' -> 2. 'vectors' -> 2. 'members' -> 2. 'invalid' -> 0 } } } do: [:case |
  | id |
  id := 'vector index ' , (case at: 1).
  run begin.
  run stage: 'validate and explain' of: id do: [
    | collection index elements problem |
    collection := snap getRootObject: (case at: 1).
    index := collection getIndex: (case at: 2).
    elements := OrderedCollection new.
    collection do: [:e | elements addLast: e].
    problem := [index validate: elements asArray. nil] on: Error do: [:e | e return: e class name , ': ' , e messageText].
    problem isNil
      ifTrue: [mismatch value: 'explain of ' , (case at: 2) value: index explain associations value: (case at: 3)]
      ifFalse: ['validate: of ' , (case at: 2) , ' failed: ' , problem]].
  run end: id].
space close.
dir deleteAll.
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' item(s)') displayNl]
  ifFalse: [('database contents ok (' , (run summaryAs: 'database contents') , ')') displayNl]
