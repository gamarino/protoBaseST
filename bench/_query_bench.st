"_query_bench.st: the data and the checksums the M1 and M3 query workloads share (spec 7.3; indexed
 queries, plan Tasks 4a and 4b), used by bench/query_workload.st (standalone) and
 bench/cluster_workload.st (M3 in a cluster). bench/py_query_workload.py is the proto_db side.
 A helper: nothing here runs on import.

  QueryBench people: n plan: aPlan      the PBDictionary of n records (record i: id i, name
                                        'p<i>', city one of six by i mod 6, age 18 + (7i mod 23),
                                        plus 0.5 when i mod 5 = 0), with the indexes of aPlan:
                                        idx0 none, idx1 an equality index on 'city', idx3 that one,
                                        a range index on 'age' and a range index on the extractor
                                        'bench.m1.name_length' (the name's size), registered here
  QueryBench change: j size: n          { key. record } of change j (0 <= j): the key (7919 j)
                                        mod n and the record id n + j, name 'q<j>', city by j mod 6,
                                        age 18 + (11 j mod 23)
  QueryBench indexReport: anIndex       { rows. groups. checksum } of an index (plan call IP10's
                                        ordered checksum over the stored occurrences in key order,
                                        the group's position in place of the row's, the side group
                                        last)
  QueryBench checksumOf: aDictionary    the dictionary's ordered checksum (sum of (key + 1) * id
                                        over the values in key order) with, in index-name order,
                                        each index's folded in: c := (c * 31 + index checksum) mod
                                        (2^61 - 1)"
Import from: 'protobase'.

Object subclass: #QueryBench instanceVariableNames: '' classVariableNames: 'NameLength'.

QueryBench class >> modulus
  ^ (2 raisedTo: 61) - 1.

QueryBench class >> person: anId name: aName city: i age: years
  ^ PBObject withAll: { 'id' -> anId. 'name' -> aName.
    'city' -> (#('Oslo' 'Rome' 'Paris' 'Lima' 'Kyiv' 'Quito') at: i \\ 6 + 1). 'age' -> years }.

"The extractor 'bench.m1.name_length', registered once per process: one block, so a second
 registration is the same one (a registry refuses another block under the name)."
QueryBench class >> registerExtractor
  NameLength isNil ifFalse: [^ self].
  NameLength := [:r | (r at: 'name') size].
  PBKeySpec registerExtractor: 'bench.m1.name_length' block: NameLength version: '1'.

QueryBench class >> indexesOf: aPlan
  self registerExtractor.
  aPlan = 'idx0' ifTrue: [^ #()].
  aPlan = 'idx1' ifTrue: [^ { PBEqualityIndex name: 'by_city' path: 'city' }].
  aPlan = 'idx3' ifTrue: [^ { PBEqualityIndex name: 'by_city' path: 'city'. PBRangeIndex name: 'by_age' path: 'age'.
    PBRangeIndex name: 'by_name_length' keySpec: (PBKeySpec extractor: 'bench.m1.name_length') }].
  ^ Error signal: 'QueryBench: unknown plan ' , aPlan printString.

QueryBench class >> people: n plan: aPlan
  | people |
  people := PBDictionary new.
  0 to: n - 1 do: [:i |
    people := people setAt: i value: (self person: i name: 'p' , i printString city: i
      age: 18 + (7 * i \\ 23) + (i \\ 5 = 0 ifTrue: [0.5] ifFalse: [0]))].
  (self indexesOf: aPlan) do: [:each | people := people addIndex: each].
  ^ people.

QueryBench class >> change: j size: n
  ^ { 7919 * j \\ n. self person: n + j name: 'q' , j printString city: j age: 18 + (11 * j \\ 23) }.

QueryBench class >> indexReport: anIndex
  | p g sum |
  p := self modulus.
  g := 0. sum := 0.
  PBAvl keysAndValuesDo: [:key :group |
    g := g + 1.
    PBKeyGroups group: group do: [:e :k | sum := (sum + (g * (e at: 'id') * k)) \\ p]] over: anIndex groups.
  g := g + 1.
  PBKeyGroups group: anIndex side do: [:e :k | sum := (sum + (g * (e at: 'id') * k)) \\ p].
  ^ { anIndex count. anIndex groupCount. sum }.

QueryBench class >> checksumOf: aDictionary
  | p check |
  p := self modulus.
  check := 0.
  aDictionary keysAndValuesDo: [:k :v | check := (check + ((k + 1) * (v at: 'id'))) \\ p].
  aDictionary indexNames do: [:name |
    check := (check * 31 + ((self indexReport: (aDictionary getIndex: name)) at: 3)) \\ p].
  ^ check.

"The planner workloads P1, P2 and P3 (spec 7.3; indexed queries, plan Task 7). Each answers
 { rows. queries. plan. checksum. us. model. modelLine }: model, a field of the WORK line, is
 compared with proto_db's like the rest of the work; modelLine, printed as a MODEL line, carries
 the model's costs (in thousandths) and is informative only."
Object subclass: #PlannerBench.

PlannerBench class >> p1Units
  ^ #(1 8 32) inject: #() into: [:all :c | all , (#('idx0' 'idx2' 'idx8') collect: [:k | { 'P1'. c. k }])].

PlannerBench class >> p2Units
  | plans |
  plans := OrderedCollection new.
  #('r0001' 'r0010' 'r0100' 'r0500' 'r0900' 'r0990' 'r1000' 'ne-few' 'ne-many') do: [:point |
    plans add: point , '-index'; add: point , '-scan'].
  ^ plans asArray collect: [:plan | { 'P2'. 2000. plan }].

PlannerBench class >> p3Units
  ^ { { 'P3'. 2000. 'intersect' }. { 'P3'. 2000. 'filter' } }.

PlannerBench class >> time: aBlock
  | t0 |
  t0 := Time microsecondClockValue.
  aBlock value.
  ^ Time microsecondClockValue - t0.

"The node names of an explain, depth first, joined by '/'."
PlannerBench class >> shapeOf: anExplain
  | out walk |
  out := OrderedCollection new.
  walk := nil.
  walk := [:info | out add: (info at: 'plan'). (info at: 'children') do: [:kid | walk value: kid]].
  walk value: anExplain.
  ^ out inject: '' into: [:s :each | s isEmpty ifTrue: [each] ifFalse: [s , '/' , each]].

"P1's fold of one explain: c * 31 + 64 * (its nodes) + the sum, over the nodes that read an index
 'i<k>', of k + 1."
PlannerBench class >> fold: aChecksum explain: anExplain
  | nodes indexes walk |
  nodes := 0. indexes := 0.
  walk := nil.
  walk := [:info |
    nodes := nodes + 1.
    (info includesKey: 'index') ifTrue: [indexes := indexes + ((((info at: 'index') at: 'index') allButFirst) asInteger + 1)].
    (info at: 'children') do: [:kid | walk value: kid]].
  walk value: anExplain.
  ^ (aChecksum * 31 + (64 * nodes) + indexes) \\ QueryBench modulus.

"P1, planner overhead: a PBList of 1000 records (id i and f0..f7, f<k> = (i (2k + 3) 7919) mod 50) with k
 indexes (plan idx<k>: index i<m> on f<m>, a range index for even m, an equality index for odd m);
 200 conditions of c conjuncts (conjunct j of condition q on f<j mod 8>: '<' ((7q + 13j) mod 50)
 for even j, '==' ((3q + j) mod 50) for odd j), compiled untimed; timed: PBPlanner's plan and its
 explain, no execution. rows 1000, queries 200, checksum the fold of the 200 explains."
PlannerBench class >> p1: c plan: aPlan
  | k coll conditions explains us check |
  k := (aPlan copyFrom: 4 to: aPlan size) asInteger.
  coll := PBList new.
  0 to: 999 do: [:i |
    coll := coll appendLast: (PBObject withAll: { 'id' -> i } , ((0 to: 7) asArray collect: [:f |
      ('f' , f printString) -> (i * (2 * f + 3) * 7919 \\ 50)]))].
  0 to: k - 1 do: [:m |
    coll := coll addIndex: (m even
      ifTrue: [PBRangeIndex name: 'i' , m printString path: 'f' , m printString]
      ifFalse: [PBEqualityIndex name: 'i' , m printString path: 'f' , m printString])].
  conditions := (0 to: 199) asArray collect: [:q | | tokens |
    tokens := OrderedCollection new.
    0 to: c - 1 do: [:j |
      tokens add: 'f' , (j \\ 8) printString.
      j even
        ifTrue: [tokens add: '<'; add: 7 * q + (13 * j) \\ 50]
        ifFalse: [tokens add: '=='; add: 3 * q + j \\ 50]].
    PBExpression compile: tokens asArray].
  us := self time: [
    explains := conditions collect: [:each |
      (PBPlanner plan: coll where: each orderBy: nil limit: nil offset: 0) explain]].
  check := explains inject: 0 into: [:sum :each | self fold: sum explain: each].
  ^ { 1000. 200. aPlan. check. us. self shapeOf: explains last. nil }.

"The PBList of n records of P2 and P3: id i, r i (unique), few i mod 4, many i (n key groups), x i mod 10,
 y i mod 7."
PlannerBench class >> records: n
  | coll |
  coll := PBList new.
  0 to: n - 1 do: [:i |
    coll := coll appendLast: (PBObject withAll: { 'id' -> i. 'r' -> i. 'few' -> (i \\ 4). 'many' -> i.
      'x' -> (i \\ 10). 'y' -> (i \\ 7) })].
  ^ coll.

"Runs aPlan 5 times, timed; answers { rows. checksum. us }, the checksum the sum of id + 1 over the
 last run's rows mod 2^61 - 1."
PlannerBench class >> run: aPlan
  | rows us |
  us := self time: [5 timesRepeat: [rows := aPlan execute]].
  ^ { rows size. (rows inject: 0 into: [:sum :e | sum + (e at: 'id') + 1]) \\ QueryBench modulus. us }.

"P2, the model against timings: n records with a range index by_r on r, equality indexes by_few
 on few and by_many on many. Plan r<permille>-index or -scan: the term r < n * permille / 1000;
 ne-few-... and ne-many-...: few != 0 and many != 0. The -index unit runs the index's own plan of
 the term (forced), the -scan unit a PBFilter over the collection scan (forced); model is the
 shape PBPlanner chooses for the term, the MODEL line both plans' model costs."
PlannerBench class >> p2: n plan: aPlan
  | coll point forced term index indexPlan scanPlan chosen r |
  coll := (((self records: n) addIndex: (PBRangeIndex name: 'by_r' path: 'r'))
    addIndex: (PBEqualityIndex name: 'by_few' path: 'few'))
    addIndex: (PBEqualityIndex name: 'by_many' path: 'many').
  forced := (aPlan endsWith: '-index') ifTrue: ['index'] ifFalse: ['scan'].
  point := aPlan copyFrom: 1 to: aPlan size - forced size - 1.
  (point beginsWith: 'r')
    ifTrue: [term := PBTerm path: 'r' op: '<' value: n * (point allButFirst) asInteger // 1000. index := 'by_r']
    ifFalse: [
      index := point = 'ne-few' ifTrue: ['by_few'] ifFalse: ['by_many'].
      term := PBTerm path: (index copyFrom: 4 to: index size) op: '!=' value: 0].
  indexPlan := (coll getIndex: index) plan: term.
  scanPlan := PBFilter source: coll asQueryPlan terms: term.
  chosen := PBPlanner plan: coll where: term orderBy: nil limit: nil offset: 0.
  r := self run: (forced = 'index' ifTrue: [indexPlan] ifFalse: [scanPlan]).
  ^ { r at: 1. 5. aPlan. r at: 2. r at: 3. self shapeOf: chosen explain.
    'index_cost=' , (indexPlan estimate cost * 1000) rounded printString
      , ' scan_cost=' , (scanPlan estimate cost * 1000) rounded printString }.

"P3, intersect: n records with an equality index by_x on x and a range index by_y on y; the
 condition x == 3 and y == 2. Plan intersect: the PBIntersect of both indexes' plans, built by
 hand; filter: PBPlanner's plan (one access path and a residual filter). model is the planner's
 shape, the MODEL line both plans' model costs."
PlannerBench class >> p3: n plan: aPlan
  | coll t1 t2 hand chosen r |
  coll := ((self records: n) addIndex: (PBEqualityIndex name: 'by_x' path: 'x'))
    addIndex: (PBRangeIndex name: 'by_y' path: 'y').
  t1 := PBTerm path: 'x' op: '==' value: 3.
  t2 := PBTerm path: 'y' op: '==' value: 2.
  hand := PBIntersect withAll: { (coll getIndex: 'by_x') plan: t1. (coll getIndex: 'by_y') plan: t2 }.
  chosen := PBPlanner plan: coll where: (PBExpression compile: #('x' '==' 3 'y' '==' 2)) orderBy: nil limit: nil offset: 0.
  (#('intersect' 'filter') includes: aPlan) ifFalse: [^ Error signal: 'P3: unknown plan ' , aPlan].
  r := self run: (aPlan = 'intersect' ifTrue: [hand] ifFalse: [chosen]).
  ^ { r at: 1. 5. aPlan. r at: 2. r at: 3. self shapeOf: chosen explain.
    'intersect_cost=' , (hand estimate cost * 1000) rounded printString
      , ' filter_cost=' , (chosen estimate cost * 1000) rounded printString }.
