"EXPECT: compound ok (10 checks)"
"Compound conditions and their plans. Quoted by docs/queries.md, 'How the planner chooses'.

 Over chapter 18's 600 people, indexed by city (equality) and by age (range): an AND is one access
 path with the other conjuncts as a residual Filter; an OR is a Union only when every branch has an
 index, otherwise one scan filtered by the whole condition; a negated term is a residual filter
 (proto_db's planner.py, ported line for line). explain shows each choice, and every answer equals
 the scan's over the same people without indexes.

 Run it: STPATH=<repository>/src protost compound.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson cities plain people planOf city age q both either unindexed notOslo conditions names scanCost |
lesson := Lesson named: 'compound'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
plain := PBDictionary new.
0 to: 599 do: [:i |
    plain := plain setAt: i value: (PBObject withAll: {
        'name' -> ('person' , i printString). 'city' -> (cities at: i \\ 4 + 1). 'age' -> (18 + (i \\ 60)) })].
people := (plain addIndex: (PBEqualityIndex name: 'by_city' path: 'city')) addIndex: (PBRangeIndex name: 'by_age' path: 'age').

"The node names of a query's plan, from the root down its first children."
planOf := [:query | | nodes node |
    nodes := OrderedCollection new.
    node := query explain.
    [node isNil] whileFalse: [
        nodes add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    nodes inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].
q := PBQuery from: people.
city := PBField path: 'city'.
age := PBField path: 'age'.

both := q where: (city eq: 'Oslo') & (age > 70).
lesson check: 'AND: one access path, the other conjunct a residual filter' is: (planOf value: both) equals: 'Filter <- IndexRange'.
lesson check: 'the filter holds the city term' is: ((both explain at: 'predicate') at: 'path') equals: 'city'.
either := q where: (city eq: 'Oslo') | (age > 70).
lesson check: 'OR of two indexed branches: a union' is: (planOf value: either) equals: 'Union <- IndexLookup'.
lesson check: 'the union keeps each person once' is: either count equals: 200.
unindexed := q where: (city eq: 'Oslo') | ((PBField path: 'name') contains: '7').
lesson check: 'OR with an unindexed branch: one scan for the whole condition' is: (planOf value: unindexed) equals: 'Filter <- CollectionScan'.
notOslo := q where: (city eq: 'Oslo') not.
lesson check: 'NOT of a term: a residual filter over a scan' is: (planOf value: notOslo) equals: 'Filter <- CollectionScan'.

"The union's branches, from its explain: the city lookup and the age range."
lesson check: 'the union reads both indexes'
    is: ((either explain at: 'children') asArray collect: [:each | each at: 'plan']) equals: #('IndexLookup' 'IndexRange').
scanCost := (((PBQuery from: plain) where: (city eq: 'Oslo') & (age > 70)) explain at: 'estimate') at: 'cost'.
lesson check: 'the chosen AND plan costs less than the scan it beat'
    isTrue: ((both explain at: 'estimate') at: 'cost') < scanCost.

"Every answer equals the scan's over the same people without indexes."
conditions := { (city eq: 'Oslo') & (age > 70). (city eq: 'Oslo') | (age > 70).
    (city eq: 'Oslo') | ((PBField path: 'name') contains: '7'). (city eq: 'Oslo') not }.
names := [:source :condition | (((PBQuery from: source) where: condition) asArray collect: [:p | p at: 'name']) asSortedCollection asArray].
lesson check: 'the counts' is: (conditions collect: [:each | ((PBQuery from: people) where: each) count]) equals: #(20 200 228 450).
lesson check: 'the same people as a scan'
    isTrue: (conditions allSatisfy: [:each | (names value: people value: each) = (names value: plain value: each)]).

lesson finish.
