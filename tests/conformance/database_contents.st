"EXPECT: database contents ok (database contents 17/17)"
"The database section read as a database (README, 'Using the vectors', 7, second
 part), on a copy of vectors/database: following space.root -> SpaceRoot ->
 databases['db'] -> DatabaseRoot, PBNotation describeDatabase: of a snapshot of the
 current version must be the manifest's contents (roots, mutables, indexes, origin),
 with ConformanceInvoice (_model.st) registered. Each part is also checked on its own
 (the database list, the root names, each root, the mutables, the indexes, the
 origin), so an expected difference names exactly what differs, and the trained
 ivf_flat index must hold the listed centroids, trained size and list of every stored
 vector (computing the list assignment is a writer's check: the prototype never
 writes a vector index). The ids are 'database', 'databases', 'root names',
 'root <name>', 'mutables', 'indexes', 'origin' and 'ivf'."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest contents dir space db snap run mismatch ids expectedWhole names ivf |
manifest := Vectors manifest.
contents := (manifest at: 'database') at: 'contents'.
names := (contents at: 'roots') collect: [:pair | pair at: 1].
ids := { 'database'. 'databases'. 'root names' } , (names collect: [:n | 'root ' , n])
  , #('mutables' 'indexes' 'origin' 'ivf').
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
space close.
dir deleteAll.
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' item(s)') displayNl]
  ifFalse: [('database contents ok (' , (run summaryAs: 'database contents') , ')') displayNl]
