"query_workload.st: the query and index workloads of the indexed queries (spec 7.3, plan Task 3
 onwards); bench/py_query_workload.py runs the same work in proto_db, bench/run_query.sh runs
 both, verifies the work and prints the timings.

 Usage: protost query_workload.st [units...]     (default: every unit of every workload)

 A unit is <id>:<size>:<plan> (M1:600:idx3, M2:10000:build) or a bare id (M1, M2), every unit of
 that id. bench/run_query.sh runs each unit in a process of its own, so that one size's live set
 never weighs on another's and each process's peak memory is its own.

 Each measured unit prints two lines (plan call IP10, and its timing):
   WORK id=<id> impl=st size=<n> rows=<n> queries=<n> plan=<plan> checksum=<n>
   TIME id=<id> impl=st size=<n> plan=<plan> us=<microseconds>
 and the last line is 'query_workload ok'. Nothing is asserted about time.

 M1, maintenance on commit (spec 7.3): a PBDictionary of 600 records (record i: id i, name 'p<i>',
 city one of six by i mod 6, age 18 + (7i mod 23), plus 0.5 when i mod 5 = 0) with no index
 (plan idx0), an equality index on 'city' (idx1), or that one, a range index on 'age' and a range
 index on the extractor 'bench.m1.name_length' (the name's size) (idx3), committed once, untimed;
 then QUERY_M1_COMMITS (default 200) transactions, timed together, each reading the dictionary
 and committing it with one record replaced: transaction j (0 <= j < commits) maps the key
 (7919 j) mod 600 to a new record (id 600 + j, name 'q<j>', city by j mod 6, age 18 + (11 j mod
 23)), one replace event per index. The space goes to QUERY_DATA (a new directory the runner names;
 never removed), in a subdirectory named after the plan. rows is the dictionary's count read back in a new transaction, queries the
 commits, and the checksum folds, in index-name order, each index's IP10 checksum (as M2's) into
 the dictionary's ordered one (sum of (position + 1) * id over the values in key order): c := (c *
 31 + index checksum) mod (2^61 - 1). The read-back version must validate (every index against
 the elements).

 M2, the bulk build (pre-flight F6): an EqualityIndex on the path 'age' over n records (n = 10^2,
 10^3, 10^4, 10^5, or the sizes QUERY_M2_SIZES lists, separated by spaces), built by build: (plan=build, keyed.py build: group, sort, balanced trees) or
 by the fold of withAdded: from empty (plan=fold, what base.py's default build does). Record i
 (0 <= i < n) has id i and age (i * 7919) mod (n // 4 + 1), plus 0.5 when i mod 5 = 0; the age is
 absent when i mod 17 = 0 and nil when i mod 19 = 0 (and i mod 17 > 0). rows is the index's
 count, queries 1, and the checksum the ordered formula of IP10 over the stored occurrences in key
 order, with the position of the key group in place of the row's (rows inside a group are in
 member order, by oid, which differs between runs): (sum of (group position + 1) * id) mod
 (2^61 - 1), the side group last. When one process runs both plans of a size they must answer
 the same rows, groups and checksum, or the run fails; the runner also requires the build and
 fold units of a size to report the same work.

 P1, P2 and P3, the planner (plan Task 7; bench/_query_bench.st PlannerBench states the data):
 P1 the planner's overhead (plan and explain only, 1, 8 and 32 conjuncts over 0, 2 and 8 indexes;
 units P1:<conjuncts>:idx<k>), P2 the cost model against timings (a range term swept from 0.1
 permille to every element, and != on an index of 4 and of n key groups; units P2:2000:<point>-index
 and -scan, each plan forced), P3 the hand-built two-index intersection against the planner's
 filter plan (P3:2000:intersect and :filter). Their WORK lines carry model=, the node names of
 the plan PBPlanner chooses, compared with proto_db's like the rest; a MODEL line gives the model
 costs of the plans compared (thousandths), informative only.

 M3, a blind write merged onto an indexed current (plan Task 4b): M1's dictionary and plans (idx0,
 idx1, idx3; bench/_query_bench.st), then QUERY_M3_COMMITS (default 120) transactions, timed
 together, each committing a new dictionary that holds M1's change j alone, without reading the
 root: the commit rebases it onto the current version (rebaseOnto:), whose mutators maintain its
 indexes, so every commit is a merge. The 120 keys (7919 j) mod 600 are distinct, so the final
 content is M1's after 120 commits whatever the order of the commits; rows, queries and checksum
 are M1's. bench/cluster_workload.st runs the same 120 commits in a three-member cluster (profiles
 m3-idx0, m3-idx1, m3-idx3), verified against this unit's proto_db checksum."
Import from: 'protobase'.
Import from: '_query_bench'.

| all units time p records report sizes m1 m2 emit commits blindCommits |
all := #('M1' 'M2' 'M3' 'P1' 'P2' 'P3').
time := [:aBlock | | t0 | t0 := Time microsecondClockValue. aBlock value. Time microsecondClockValue - t0].
p := (2 raisedTo: 61) - 1.
sizes := (Smalltalk getenv: 'QUERY_M2_SIZES') ifNil: ['100 1000 10000 100000'].
sizes := (sizes substrings: ' ') collect: [:each | each asInteger].
commits := ((Smalltalk getenv: 'QUERY_M1_COMMITS') ifNil: ['200']) asInteger.
blindCommits := ((Smalltalk getenv: 'QUERY_M3_COMMITS') ifNil: ['120']) asInteger.
"The units to run: each argument, a bare id expanded."
units := OrderedCollection new.
(Smalltalk arguments isEmpty ifTrue: [all] ifFalse: [Smalltalk arguments]) do: [:arg |
  | parts |
  parts := arg substrings: ':'.
  (all includes: parts first) ifFalse: [Error signal: 'query_workload: unknown workload ' , arg].
  parts size = 1
    ifTrue: [
      (#('M1' 'M3') includes: parts first) ifTrue: [#('idx0' 'idx1' 'idx3') do: [:plan | units addLast: { parts first. 600. plan }]].
      parts first = 'M2' ifTrue: [sizes do: [:n | units addLast: { 'M2'. n. nil }]].
      parts first = 'P1' ifTrue: [units addAll: PlannerBench p1Units].
      parts first = 'P2' ifTrue: [units addAll: PlannerBench p2Units].
      parts first = 'P3' ifTrue: [units addAll: PlannerBench p3Units]]
    ifFalse: [
      parts size = 3 ifFalse: [Error signal: 'query_workload: a unit is <id>:<size>:<plan>, not ' , arg].
      units addLast: { parts first. (parts at: 2) asInteger. parts at: 3 }]].
emit := [:id :n :rows :queries :plan :checksum :us |
  ('WORK id=' , id , ' impl=st size=' , n printString , ' rows=' , rows printString , ' queries=' , queries printString
    , ' plan=' , plan , ' checksum=' , checksum printString) displayNl.
  ('TIME id=' , id , ' impl=st size=' , n printString , ' plan=' , plan , ' us=' , us printString) displayNl].
"rows, groups and the checksum of an index (see the header)."
report := [:index | QueryBench indexReport: index].

"M1 and M3: the dictionary of n records with the indexes of plan committed once, untimed; then
 the transactions, timed together; then the read-back. aBlind false: each transaction reads the
 dictionary and commits it with change j (M1); true: each commits a new dictionary holding change j
 alone, never reading the root, so the commit merges it onto the current version (M3)."
m1 := [:id :n :plan :count :aBlind |
  | data space db tx people us check |
  data := Smalltalk getenv: 'QUERY_DATA'.
  (data isNil or: [data isEmpty]) ifTrue: [Error signal: id , ' needs QUERY_DATA, a new directory for its space'].
  data := data asFileReference / plan.
  data ensureCreateDirectory.
  data := data pathString.
  people := QueryBench people: n plan: plan.
  space := PBObjectSpace storage: (PBFileStorage path: data).
  db := space newDatabase: 'bench'.
  tx := db newTransaction.
  tx setRootObject: 'people' value: people.
  tx commit.
  us := time value: [
    0 to: count - 1 do: [:j |
      | t change |
      change := QueryBench change: j size: n.
      t := db newTransaction.
      t setRootObject: 'people' value: ((aBlind ifTrue: [t newDictionary] ifFalse: [t getRootObject: 'people'])
        setAt: (change at: 1) value: (change at: 2)).
      t commit]].
  tx := db newTransaction.
  people := tx getRootObject: 'people'.
  people validate.
  check := QueryBench checksumOf: people.
  tx abort.
  space close.
  emit valueWithArguments: { id. n. people count. count. plan. check. us }].

m2 := [:n :plans |
  | data empty results |
  data := (0 to: n - 1) asArray collect: [:i |
    | fields age |
    fields := OrderedCollection with: 'id' -> i.
    i \\ 17 = 0 ifFalse: [
      age := i \\ 19 = 0
        ifTrue: [nil]
        ifFalse: [(i * 7919) \\ (n // 4 + 1) + (i \\ 5 = 0 ifTrue: [0.5] ifFalse: [0])].
      fields addLast: 'age' -> age].
    PBObject withAll: fields asArray].
  empty := PBEqualityIndex name: 'by_age' path: 'age'.
  results := plans collect: [:plan |
    | index us |
    (#('build' 'fold') includes: plan) ifFalse: [Error signal: 'M2: unknown plan ' , plan].
    us := time value: [
      plan = 'build'
        ifTrue: [index := empty build: data]
        ifFalse: [index := empty. data do: [:e | index := index withAdded: e]]].
    { plan. report value: index. us }].
  results do: [:r |
    (r at: 2) = (results first at: 2) ifFalse: [
      Error signal: 'M2 ' , n printString , ': ' , (r at: 1) , ' answers ' , (r at: 2) printString , ', '
        , (results first at: 1) , ' ' , (results first at: 2) printString].
    ((r at: 2) at: 1) = n ifFalse: [Error signal: 'M2 ' , n printString , ': ' , ((r at: 2) at: 1) printString , ' rows']].
  results do: [:r |
    emit valueWithArguments: { 'M2'. n. (r at: 2) at: 1. 1. r at: 1. (r at: 2) at: 3. r at: 3 }]].

units do: [:unit |
  (unit at: 1) = 'M1' ifTrue: [m1 valueWithArguments: { 'M1'. unit at: 2. unit at: 3. commits. false }].
  (unit at: 1) = 'M3' ifTrue: [m1 valueWithArguments: { 'M3'. unit at: 2. unit at: 3. blindCommits. true }].
  (unit at: 1) = 'M2' ifTrue: [
    m2 value: (unit at: 2) value: ((unit at: 3) isNil ifTrue: [#('build' 'fold')] ifFalse: [{ unit at: 3 }])].
  ((unit at: 1) first = $P) ifTrue: [ | r |
    r := PlannerBench perform: ((unit at: 1) asLowercase , ':plan:') asSymbol with: (unit at: 2) with: (unit at: 3).
    ('WORK id=' , (unit at: 1) , ' impl=st size=' , (unit at: 2) printString , ' rows=' , (r at: 1) printString
      , ' queries=' , (r at: 2) printString , ' plan=' , (r at: 3) , ' checksum=' , (r at: 4) printString
      , ' model=' , (r at: 6)) displayNl.
    ('TIME id=' , (unit at: 1) , ' impl=st size=' , (unit at: 2) printString , ' plan=' , (r at: 3) , ' us=' , (r at: 5) printString) displayNl.
    (r at: 7) isNil ifFalse: [('MODEL id=' , (unit at: 1) , ' impl=st size=' , (unit at: 2) printString , ' plan=' , (r at: 3) , ' ' , (r at: 7)) displayNl]]].
'query_workload ok' displayNl.
