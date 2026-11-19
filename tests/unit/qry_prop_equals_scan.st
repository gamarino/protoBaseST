"EXPECT: ok"
"Indexed queries, plan Task 7 (spec 7.2): a planned query answers what a scan answers (proto_db's
 tests/property/test_index_equals_scan.py at v2.0.0rc4, and test_planner.py's property), for the
 seeds 1..PBST_PROP_SEEDS (default 20, plan call IP16), each seed's draws from QData random: (the
 first draw discarded). For every seed and every collection kind protoBaseST writes (PBList, PBSet,
 PBCountedSet, PBDictionary, PBHashDictionary; PBRepeatedKeysDictionary has no mutators here, so
 the query vectors cover it, written by proto_db): a random collection (0 to 90 elements: records
 with a, b and a nested c.d, as a record or a map, sometimes absent or nil, and one plain value in
 ten, drawn from proto_db's FIELD_VALUES: 1, 1.0, Decimal 1, Decimal 1.0, true, nil, NaN, a list,
 tuples, dates, ByteArrays, 10^16 and 10^16 + 1; a set keeps the orderable ones; some elements
 twice), 0 to 3 equality and range indexes (none in one draw in seven) on a, b, c.d, the element or an extractor, and 10
 queries: random expressions of depth <= 3 with every operator on indexed, unindexed and absent
 paths (and on the extractor), or proto_db's targeted shapes (an indexable term, an Or, an And, a
 Not), with 0 to 2 order keys, a limit (nil or 0..6) and an offset (0..5). The oracle is
 independent of the planner: evaluate: over the elements, then a stable multi-pass sort over the
 key slots (orderable keys by order key, the unorderable ones last). Every query's rows equal the
 oracle's as a multiset (QData scan:) when there is no window; with an order, the key sequence
 equals the oracle's; a window is a window of that order (test_index_equals_scan.py
 assert_window: the key sequence, each tie group wholly inside it exact, a cut one a
 sub-multiset); a second execution answers the same; explain answers. Each collection is then
 saved and read back through a fresh storage (lazy), and every query plans by the same access
 path and answers the same. Concurrent readers (spec 7.2): four actors run one plan per seed over
 the same version at once and every answer equals the first. Census: the scan, an index, a Union
 and an ordered index scan are each chosen at least once over the run
 (test_every_access_path_was_exercised). A failure prints its seed. The saves go to
 out/qry_prop_equals_scan (git ignores out/), a new directory per run."
Import from: 'protobase'.
Import from: '_queries'.
Import from: '_check'.

"The draws of one seed (QData random:) and the values of test_index_equals_scan.py."
Object subclass: #PropGen instanceVariableNames: 'random'.

PropGen class >> seed: aSeed
  ^ self basicNew setRandom: (QData random: aSeed).

PropGen >> setRandom: aRandom
  random := aRandom.

PropGen >> between: lo and: hi
  ^ lo + (random next * (hi - lo + 1)) truncated.

PropGen >> chance: aFloat
  ^ random next < aFloat.

PropGen >> pick: anArray
  ^ anArray at: (self between: 1 and: anArray size).

"FIELD_VALUES, PBMissing last."
PropGen class >> fieldValues
  ^ { true. false. 0. 1. 1.0. Decimal fromString: '1'. Decimal fromString: '1.0'. 2. 3. -1. 0.5. 2.5. 10 raisedTo: 16.
    (10 raisedTo: 16) + 1. nil. 'a'. 'b'. ''. 'ab'. ByteArray withAll: #(120). ByteArray new.
    CalendarDate year: 2026 month: 1 day: 1. CalendarDate year: 2026 month: 1 day: 3.
    PBTuple withAll: #(1 't'). PBTuple withAll: #(0 'a'). PBFrozenList withAll: #(1). Float nan. PBMissing default }.

"The orderable field values (OPERANDS)."
PropGen class >> operands
  ^ self fieldValues select: [:v | v ~~ PBMissing default and: [PBKeys isOrderable: v]].

"BETWEEN_PAIRS."
PropGen class >> betweenPairs
  ^ { #(0 2). { 1. 10 raisedTo: 17 }. #(-1 1.0). #('a' 'b'). #('' 'ab'). #(false true). { ByteArray new. ByteArray withAll: #(120) }.
    { CalendarDate year: 2026 month: 1 day: 1. CalendarDate year: 2026 month: 1 day: 3 }. #(0.5 2.5).
    { PBTuple withAll: #(0 'a'). PBTuple withAll: #(1 't') }. { Decimal fromString: '1'. 3 } }.

PropGen class >> extractor
  ^ 'qry_prop.b'.

"PATHS (the extractor added: it reads b)."
PropGen class >> paths
  ^ { 'a'. 'b'. 'c.d'. 'a'. 'b'. nil. 'zz'. '@' , self extractor }.

"A record (test_index_equals_scan.py records), or one plain value in ten."
PropGen >> element
  | attrs a b d nest |
  (self between: 0 and: 9) = 0 ifTrue: [^ self pick: (PropGen fieldValues copyFrom: 1 to: PropGen fieldValues size - 1)].
  attrs := OrderedCollection new.
  a := self pick: PropGen fieldValues. b := self pick: PropGen fieldValues. d := self pick: PropGen fieldValues.
  a == PBMissing default ifFalse: [attrs add: 'a' -> a].
  b == PBMissing default ifFalse: [attrs add: 'b' -> b].
  nest := self between: 0 and: 3.
  (d ~~ PBMissing default and: [nest = 0]) ifTrue: [attrs add: 'c' -> (PBObject withAll: { 'd' -> d })].
  (d ~~ PBMissing default and: [nest = 1]) ifTrue: [attrs add: 'c' -> (PBFrozenDict withAssociations: { 'd' -> d })].
  nest = 2 ifTrue: [attrs add: 'c' -> nil].
  ^ PBObject withAll: attrs asArray.

"A term over every operator (test_index_equals_scan.py terms)."
PropGen >> term
  | path op |
  path := self pick: PropGen paths.
  op := self pick: #('==' '==' '!=' '<' '<=' '>' '>=' 'in' 'in' '?N' '?!N' '?T' '?!T' 'contains' 'between[]' 'between()' 'between(]' 'between[)').
  ^ self termOn: path op: op.

PropGen >> termOn: aPath op: anOp
  (#('?N' '?!N' '?T' '?!T') includes: anOp) ifTrue: [^ PBTerm path: aPath op: anOp].
  anOp = 'in' ifTrue: [^ PBTerm path: aPath op: anOp value: ((1 to: (self between: 0 and: 4)) asArray collect: [:i | self pick: PropGen operands])].
  (anOp beginsWith: 'between') ifTrue: [^ PBTerm path: aPath op: anOp value: (self pick: PropGen betweenPairs)].
  anOp = 'contains' ifTrue: [^ PBTerm path: aPath op: anOp value: (self pick: { 'a'. 'b'. 1. ByteArray withAll: #(120). 0 })].
  ^ PBTerm path: aPath op: anOp value: (self pick: PropGen operands).

"An expression of depth <= aDepth: a term, or an And or Or of 2-3, or a Not."
PropGen >> expression: aDepth
  | r |
  (aDepth <= 1 or: [self chance: 0.4]) ifTrue: [^ self term].
  r := self between: 0 and: 2.
  r = 2 ifTrue: [^ (self expression: aDepth - 1) not].
  ^ (r = 0 ifTrue: [PBAnd] ifFalse: [PBOr]) withAll: ((1 to: (self between: 2 and: 3)) asArray collect: [:i | self expression: aDepth - 1]).

"A selective term an index can answer (indexable_terms)."
PropGen >> indexable
  | op |
  op := self pick: #('==' 'in' '<' '>=' '?N' '?!N' 'between[]' 'between()' 'between(]' 'between[)').
  op = 'in' ifTrue: [^ PBTerm path: (self pick: { 'a'. 'b'. 'c.d'. nil }) op: op
    value: ((1 to: (self between: 1 and: 3)) asArray collect: [:i | self pick: PropGen operands])].
  ^ self termOn: (self pick: { 'a'. 'b'. 'c.d'. nil. '@' , PropGen extractor }) op: op.

"proto_db's targeted shapes: a term, an Or, an And, an And of terms and Ors, a Not."
PropGen >> targeted
  | r |
  r := self between: 0 and: 4.
  r = 0 ifTrue: [^ self indexable].
  r = 1 ifTrue: [^ PBOr withAll: ((1 to: (self between: 2 and: 3)) asArray collect: [:i | self indexable])].
  r = 2 ifTrue: [^ PBAnd withAll: ((1 to: (self between: 2 and: 3)) asArray collect: [:i | self indexable])].
  r = 3 ifTrue: [^ PBAnd withAll: ((1 to: (self between: 2 and: 3)) asArray collect: [:i |
    (self chance: 0.5) ifTrue: [self indexable] ifFalse: [self indexable | self indexable]])].
  ^ self indexable not.

"nil, an expression or a targeted shape."
PropGen >> condition
  | r |
  r := self between: 0 and: 3.
  r = 0 ifTrue: [^ nil].
  r = 1 ifTrue: [^ self expression: 3].
  ^ self targeted.

"0 to 3 distinct index definitions (kind, key spec): none in about one draw in seven, so most
 collections have an index to choose."
PropGen >> indexes
  | out specs |
  specs := { 'a'. 'b'. 'c.d'. nil. '@' , PropGen extractor }.
  out := OrderedCollection new.
  ((self chance: 0.15) ifTrue: [0] ifFalse: [self between: 1 and: 3]) timesRepeat: [ | kind path name |
    kind := self pick: { PBEqualityIndex. PBRangeIndex }.
    path := self pick: specs.
    name := kind name , '_' , (path isNil ifTrue: ['element'] ifFalse: [path]).
    (out anySatisfy: [:each | each name = name]) ifFalse: [
      out add: (kind name: name keySpec: (PBKeySpec forTermPath: path))]].
  ^ out asArray.

"0 to 2 order keys on distinct paths."
PropGen >> order
  | out |
  out := OrderedCollection new.
  (self between: 0 and: 2) timesRepeat: [ | path |
    path := self pick: PropGen paths.
    (out anySatisfy: [:k | k key = path]) ifFalse: [out add: (PBSortKey key: path descending: (self chance: 0.5))]].
  ^ out asArray.

"The collection of kind aName over anArray (test_index_equals_scan.py BUILDERS, less
 RepeatedKeysDictionary)."
PropGen class >> build: aName of: anArray
  aName = 'List' ifTrue: [^ PBList new extend: anArray].
  aName = 'Set' ifTrue: [^ anArray inject: PBSet new into: [:acc :e | acc add: e]].
  aName = 'CountedSet' ifTrue: [^ anArray inject: PBCountedSet new into: [:acc :e | acc add: e]].
  aName = 'Dictionary' ifTrue: [^ (1 to: anArray size) inject: PBDictionary new into: [:acc :i | acc setAt: i - 1 value: (anArray at: i)]].
  ^ (1 to: anArray size) inject: PBHashDictionary new into: [:acc :i | acc setAt: i - 1 value: (anArray at: i)].

"=== the oracle (independent of the planner) ==="
Object subclass: #Oracle.

"The ascending sort slot of a key: { 0. order key } or { 1 } (test_index_equals_scan.py slot)."
Oracle class >> slot: aKey
  ^ (PBKeys isOrderable: aKey) ifTrue: [{ 0. PBMemberKeys orderKeyOrNil: aKey }] ifFalse: [#(1)].

Oracle class >> compare: a with: b
  (a at: 1) = (b at: 1) ifFalse: [^ (a at: 1) < (b at: 1) ifTrue: [-1] ifFalse: [1]].
  (a at: 1) = 1 ifTrue: [^ 0].
  ^ (a at: 2) compareWith: (b at: 2).

"The key slots of anElement for the keys anArray."
Oracle class >> slotsOf: anElement keys: anArray
  ^ anArray collect: [:k | self slot: ((PBKeySpec forTermPath: k key) extract: anElement)].

Oracle class >> sameSlots: a as: b
  a size = b size ifFalse: [^ false].
  1 to: a size do: [:i | (self compare: (a at: i) with: (b at: i)) = 0 ifFalse: [^ false]].
  ^ true.

"The elements of aCollection for which anExpression holds, sorted by the keys anArray with a
 stable pass per key, last key first, each descending one reversed as Python's
 sort(reverse=True) does (equal keys keep their order)."
Oracle class >> scan: aCollection where: anExpression keys: anArray
  | rows |
  rows := OrderedCollection new.
  aCollection do: [:e | (anExpression isNil or: [anExpression evaluate: e]) ifTrue: [rows add: e]].
  rows := rows asArray.
  anArray size to: 1 by: -1 do: [:i | | spec desc tagged |
    spec := PBKeySpec forTermPath: (anArray at: i) key.
    desc := (anArray at: i) descending.
    tagged := (1 to: rows size) asArray collect: [:n | { rows at: n. self slot: (spec extract: (rows at: n)). n }].
    tagged := tagged sort: [:x :y | | c |
      c := self compare: (x at: 2) with: (y at: 2).
      desc ifTrue: [c := c negated].
      c = 0 ifTrue: [(x at: 3) <= (y at: 3)] ifFalse: [c < 0]].
    rows := tagged collect: [:each | each at: 1]].
  ^ rows.

"The access path of an explain (test_index_equals_scan.py classify)."
Oracle class >> classify: anInfo
  | found |
  found := OrderedCollection new.
  self names: anInfo into: found.
  (found anySatisfy: [:n | n includesSubstring: 'Ordered']) ifTrue: [^ 'ordered'].
  (found includes: 'Union') ifTrue: [^ 'union'].
  (found anySatisfy: [:n | n beginsWith: 'Index']) ifTrue: [^ 'index'].
  ^ 'scan'.

Oracle class >> names: anInfo into: anOrderedCollection
  anOrderedCollection add: (anInfo at: 'plan').
  (anInfo at: 'children') do: [:kid | self names: kid into: anOrderedCollection].

"Problems of got as the window of oracle (test_index_equals_scan.py check_query and assert_window):
 an empty Array when it is one."
Oracle class >> problemsOf: got oracle: oracle keys: keys limit: limit offset: offset
  | out stop window slots total inside byKeyOracle byKeyGot group gotBag oracleBag |
  out := OrderedCollection new.
  stop := limit isNil ifTrue: [oracle size] ifFalse: [offset + limit min: oracle size].
  window := offset >= oracle size ifTrue: [#()] ifFalse: [oracle copyFrom: offset + 1 to: stop].
  gotBag := QData bagOf: got.
  oracleBag := QData bagOf: oracle.
  (limit isNil and: [offset = 0]) ifTrue: [
    gotBag = oracleBag ifFalse: [out add: 'rows differ from the scan']].
  got size = window size ifFalse: [^ out add: 'window size ' , got size printString , ' not ' , window size printString; yourself].
  keys isEmpty ifTrue: [
    (gotBag keys allSatisfy: [:k | (gotBag at: k) <= (oracleBag at: k ifAbsent: [0])])
      ifFalse: [out add: 'an unordered window is not a sub-multiset of the scan'].
    ^ out].
  slots := oracle collect: [:e | self slotsOf: e keys: keys].
  ((1 to: got size) allSatisfy: [:i | self sameSlots: (self slotsOf: (got at: i) keys: keys) as: (slots at: offset + i)])
    ifFalse: [^ out add: 'the key sequence differs from the sorted scan'; yourself].
  "Tie groups: the runs of equal key slots in the oracle (it is sorted); got's row i lies in the
   group of the oracle's row offset + i, since the key sequences are equal."
  group := Array new: oracle size.
  1 to: oracle size do: [:i |
    group at: i put: ((i > 1 and: [self sameSlots: (slots at: i - 1) as: (slots at: i)])
      ifTrue: [group at: i - 1] ifFalse: [i])].
  total := Dictionary new. inside := Dictionary new. byKeyOracle := Dictionary new. byKeyGot := Dictionary new.
  oracle doWithIndex: [:e :i | total at: (group at: i) put: (total at: (group at: i) ifAbsent: [0]) + 1.
    (byKeyOracle at: (group at: i) ifAbsentPut: [OrderedCollection new]) add: e].
  got doWithIndex: [:e :i | | g |
    g := group at: offset + i.
    inside at: g put: (inside at: g ifAbsent: [0]) + 1.
    (byKeyGot at: g ifAbsentPut: [OrderedCollection new]) add: e].
  byKeyGot keysAndValuesDo: [:k :members | | mine theirs |
    mine := QData bagOf: members. theirs := QData bagOf: (byKeyOracle at: k).
    (inside at: k) = (total at: k)
      ifTrue: [mine = theirs ifFalse: [out add: 'a tie group inside the window differs']]
      ifFalse: [(mine keys allSatisfy: [:id | (mine at: id) <= (theirs at: id ifAbsent: [0])]) ifFalse: [
        out add: 'a cut tie group holds rows the scan does not']]].
  ^ out.

"Runs a plan on its own actor (spec 7.2, concurrent readers)."
Object subclass: #PlanReader.

PlanReader >> identitiesOf: aPlan
  ^ aPlan execute collect: [:e | PBMemberKeys identityOf: e].

| seeds failures census kinds extractor dir storage saved readers plain c |
seeds := QData seeds: 20.
failures := OrderedCollection new.
census := Dictionary new.
kinds := #('List' 'Set' 'CountedSet' 'Dictionary' 'HashDictionary').
PBKeySpec registerExtractor: PropGen extractor block: [:e | (PBKeySpec path: 'b') extract: e] version: '1'.
dir := 'out/qry_prop_equals_scan' asFileReference / ('run-' , Smalltalk pid printString , '-' , Time microsecondClockValue printString).
dir ensureCreateDirectory.
storage := PBFileStorage path: dir pathString.
saved := OrderedCollection new.
readers := OrderedCollection new.
"Plans, runs and checks one query; answers its access path, or nil after recording a failure."
plain := [:label :coll :expr :keys :limit :offset | | plan got again oracle problems info |
  [plan := PBPlanner plan: coll where: expr orderBy: (keys isEmpty ifTrue: [nil] ifFalse: [keys]) limit: limit offset: offset.
   got := plan execute.
   again := plan execute.
   oracle := Oracle scan: coll where: expr keys: keys.
   problems := Oracle problemsOf: got oracle: oracle keys: keys limit: limit offset: offset.
   (QData bagOf: again) = (QData bagOf: got) ifFalse: [problems add: 'a second execution differs'].
   (keys notEmpty and: [((1 to: got size) allSatisfy: [:i |
       Oracle sameSlots: (Oracle slotsOf: (got at: i) keys: keys) as: (Oracle slotsOf: (again at: i) keys: keys)]) not])
     ifTrue: [problems add: 'a second execution orders differently'].
   info := plan explain.
   problems isEmpty
     ifTrue: [Oracle classify: info]
     ifFalse: [failures add: label , ': ' , problems first , ' (' , expr printString , ', ' , (keys collect: [:k | k describe]) printString
       , ', limit ' , limit printString , ', offset ' , offset printString , ')'. nil]]
    on: Error do: [:e | failures add: label , ': ' , e class name , ': ' , e messageText printString , ' (' , expr printString , ')'. e return: nil]].

1 to: seeds do: [:seed |
  kinds do: [:kind | | gen items coll queries |
    gen := PropGen seed: seed * 101 + (kinds indexOf: kind).
    items := (1 to: (gen pick: #(0 3 12 40 40 90))) asArray collect: [:i | gen element].
    (#('Set' 'CountedSet') includes: kind) ifTrue: [items := items select: [:e | PBKeys isOrderable: e]].
    items := items , (items copyFrom: 1 to: ((gen between: 0 and: 3) min: items size)).
    coll := gen indexes inject: (PropGen build: kind of: items) into: [:acc :index | acc addIndex: index].
    queries := (1 to: 10) asArray collect: [:q | { gen condition. gen order. (gen chance: 0.5) ifTrue: [nil] ifFalse: [gen between: 0 and: 6].
      (gen chance: 0.5) ifTrue: [0] ifFalse: [gen between: 0 and: 5] }].
    queries doWithIndex: [:query :q | | path |
      path := plain value: 'seed ' , seed printString , ' ' , kind , ' query ' , q printString value: coll
        value: (query at: 1) value: (query at: 2) value: (query at: 3) value: (query at: 4).
      path isNil ifFalse: [census at: path put: (census at: path ifAbsent: [0]) + 1].
      saved add: { seed. kind. coll. query. path }].
    readers add: { seed. kind. PBPlanner plan: coll where: (queries last at: 1) orderBy: nil limit: nil offset: 0 }.
    storage save: coll]].
storage close.

"Read back through a fresh storage: lazy, nothing cached; the same access path and answers."
storage := PBFileStorage path: dir pathString.
saved do: [:each | | loaded query path |
  query := each at: 4.
  loaded := PBTypeRegistry unloadedAtomFor: (each at: 3) tag at: (each at: 3) pointer storage: storage.
  path := plain value: 'seed ' , (each at: 1) printString , ' ' , (each at: 2) , ' reloaded' value: loaded
    value: (query at: 1) value: (query at: 2) value: (query at: 3) value: (query at: 4).
  (path notNil and: [path ~= (each at: 5)]) ifTrue: [
    failures add: 'seed ' , (each at: 1) printString , ' ' , (each at: 2) , ' reloaded plans by ' , path , ', not ' , (each at: 5) printString]].
storage close.

"Concurrent readers: four actors run one plan per seed and kind at once."
readers do: [:each | | futures answers |
  futures := (1 to: 4) asArray collect: [:i | PlanReader new asActor identitiesOf: (each at: 3)].
  answers := futures collect: [:f | f wait].
  ((answers allSatisfy: [:a | a = answers first]) and: [answers first = (PlanReader new identitiesOf: (each at: 3))]) ifFalse: [
    failures add: 'seed ' , (each at: 1) printString , ' ' , (each at: 2) , ': concurrent readers disagree']].

('census ' , (#('scan' 'index' 'union' 'ordered') collect: [:p | p , ' ' , (census at: p ifAbsent: [0]) printString]) printString
  , ', ' , saved size printString , ' queries, ' , seeds printString , ' seeds') displayNl.
failures do: [:f | ('FAIL ' , f) displayNl].
c := Check new.
c that: 'the planned result equals the scan, as a multiset and sorted by the order keys, over every collection kind, reloaded and read by concurrent actors'
  is: failures size equals: 0.
c that: 'every access path was exercised: scan, index, union and ordered scan'
  is: (#('scan' 'index' 'union' 'ordered') reject: [:p | census includesKey: p]) equals: #().
((c report) = 'ok 2' ifTrue: ['ok'] ifFalse: ['failed']) displayNl.
