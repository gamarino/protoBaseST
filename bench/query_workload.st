"query_workload.st: the query and index workloads of the indexed queries (spec 7.3, plan Task 3
 onwards); bench/py_query_workload.py runs the same work in proto_db, bench/run_query.sh runs
 both, verifies the work and prints the timings.

 Usage: protost query_workload.st [ids...]     (default: every workload; today M2)

 Each measured run prints two lines (plan call IP10, and its timing):
   WORK id=<id> impl=st size=<n> rows=<n> queries=<n> plan=<root> checksum=<n>
   TIME id=<id> impl=st size=<n> plan=<root> us=<microseconds>
 and the last line is 'query_workload ok'. Nothing is asserted about time.

 M2, the bulk build (pre-flight F6): an EqualityIndex on the path 'age' over n records (n = 10^2,
 10^3, 10^4, 10^5, or the sizes QUERY_M2_SIZES lists, separated by spaces), built by build: (plan=build, keyed.py build: group, sort, balanced trees) and
 by the fold of withAdded: from empty (plan=fold, what base.py's default build does). Record i
 (0 <= i < n) has id i and age (i * 7919) mod (n // 4 + 1), plus 0.5 when i mod 5 = 0; the age is
 absent when i mod 17 = 0 and nil when i mod 19 = 0 (and i mod 17 > 0). rows is the index's
 count, queries 1, and the checksum the ordered formula of IP10 over the stored occurrences in key
 order, with the position of the key group in place of the row's (rows inside a group are in
 member order, by oid, which differs between runs): (sum of (group position + 1) * id) mod
 (2^61 - 1), the side group last. Both builds must answer the same rows, groups and checksum, or
 the run fails."
Import from: 'protobase'.

| ids all time p records report sizes |
all := #('M2').
ids := Smalltalk arguments isEmpty ifTrue: [all] ifFalse: [Smalltalk arguments].
ids do: [:id | (all includes: id) ifFalse: [Error signal: 'query_workload: unknown workload ' , id]].
time := [:aBlock | | t0 | t0 := Time microsecondClockValue. aBlock value. Time microsecondClockValue - t0].
p := (2 raisedTo: 61) - 1.
records := [:n | (0 to: n - 1) asArray collect: [:i |
  | fields age |
  fields := OrderedCollection with: 'id' -> i.
  i \\ 17 = 0 ifFalse: [
    age := i \\ 19 = 0
      ifTrue: [nil]
      ifFalse: [(i * 7919) \\ (n // 4 + 1) + (i \\ 5 = 0 ifTrue: [0.5] ifFalse: [0])].
    fields addLast: 'age' -> age].
  PBObject withAll: fields asArray]].
"rows, groups and the checksum of an index (see the header)."
report := [:index | | g sum |
  g := 0. sum := 0.
  PBAvl keysAndValuesDo: [:key :group |
    g := g + 1.
    PBKeyGroups group: group do: [:e :k | sum := (sum + (g * (e at: 'id') * k)) \\ p]] over: index groups.
  g := g + 1.
  PBKeyGroups group: index side do: [:e :k | sum := (sum + (g * (e at: 'id') * k)) \\ p].
  { index count. index groupCount. sum }].
sizes := (Smalltalk getenv: 'QUERY_M2_SIZES') ifNil: ['100 1000 10000 100000'].
sizes := (sizes substrings: ' ') collect: [:each | each asInteger].

(ids includes: 'M2') ifTrue: [
  sizes do: [:n |
    | data empty built folded us1 us2 a b |
    data := records value: n.
    empty := PBEqualityIndex name: 'by_age' path: 'age'.
    us1 := time value: [built := empty build: data].
    us2 := time value: [folded := empty. data do: [:e | folded := folded withAdded: e]].
    a := report value: built.
    b := report value: folded.
    a = b ifFalse: [Error signal: 'M2 ' , n printString , ': build answers ' , a printString , ', the fold ' , b printString].
    (a at: 1) = n ifFalse: [Error signal: 'M2 ' , n printString , ': ' , (a at: 1) printString , ' rows'].
    { 'build' -> us1. 'fold' -> us2 } do: [:each |
      ('WORK id=M2 impl=st size=' , n printString , ' rows=' , (a at: 1) printString , ' queries=1 plan=' , each key
        , ' checksum=' , (a at: 3) printString) displayNl.
      ('TIME id=M2 impl=st size=' , n printString , ' plan=' , each key , ' us=' , each value printString) displayNl]]].
'query_workload ok' displayNl.
