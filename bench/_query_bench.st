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
