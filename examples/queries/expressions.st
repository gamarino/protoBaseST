"EXPECT: expressions ok (17 checks)"
"The expression language. Quoted by docs/queries.md, 'The expression language'.

 PBField builds proto_db's terms with protoST's names (ruling IQ2): eq: and ne: for == and !=, the
 binary comparisons with the field as the receiver, between:and: and its open forms, in:, isNone,
 notNone, isTrue, notTrue and contains:. & | and not combine expressions only (ruling CR5); = is not
 overridden on a field (call IC4). The 0.1 prefix list syntax compiles to the same conditions.
 Evaluation is two-valued, so the negation of a comparison is true for an element without the
 key. A block enters a query only through where:, runs in a BlockFilter, and never uses an index;
 chained where: calls combine with AND; an OR or a NOT holding a block is one BlockFilter for the
 whole condition (linq.py:48-61); where: refuses anything else with ruling CR6's text.

 Run it: STPATH=<repository>/src protost expressions.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson cities people planOf city age ageless q sevens oldSevens inOslo |
lesson := Lesson named: 'expressions'.

"Chapter 18's 600 people (four cities in turn, ages 18 to 77, ten of each age), indexed by city
 and by age."
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
people := PBDictionary new.
0 to: 599 do: [:i |
    people := people setAt: i value: (PBObject withAll: {
        'name' -> ('person' , i printString). 'city' -> (cities at: i \\ 4 + 1). 'age' -> (18 + (i \\ 60)) })].
people := (people addIndex: (PBEqualityIndex name: 'by_city' path: 'city')) addIndex: (PBRangeIndex name: 'by_age' path: 'age').
ageless := PBObject withAll: { 'name' -> 'ageless'. 'city' -> 'Oslo' }.

"The node names of a query's plan, from the root down its first children."
planOf := [:query | | names node |
    names := OrderedCollection new.
    node := query explain.
    [node isNil] whileFalse: [
        names add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].

city := PBField path: 'city'.
age := PBField path: 'age'.
lesson check: 'eq: builds a term' is: (city eq: 'Oslo') equals: (PBTerm path: 'city' op: '==' value: 'Oslo').
lesson check: 'between:and: includes both bounds' is: (age between: 30 and: 35) op equals: 'between[]'.
lesson check: '& builds a PBAnd' is: ((city eq: 'Oslo') & (age > 70)) class equals: PBAnd.
lesson check: 'not not is the condition itself' is: (age > 70) not not equals: age > 70.
lesson check: 'a field compared with = is a Boolean, not a condition' is: city = 'Oslo' equals: false.
lesson check: 'the half-open forms'
    is: { (age betweenOpen: 30 and: 35) op. (age betweenLeftOpen: 30 and: 35) op. (age betweenRightOpen: 30 and: 35) op }
    equals: #('between()' 'between(]' 'between[)').
lesson check: '& takes expressions only'
    signals: PBValidationError containing: 'PBExpression'
    during: [(city eq: 'Oslo') & [:p | true]].

lesson check: 'the list syntax compiles to the same condition'
    is: (PBExpression compile: { 'city'. '=='. 'Oslo'. 'age'. '>'. 70 })
    equals: (city eq: 'Oslo') & (age > 70).
lesson check: 'asList answers the list syntax' is: (city eq: 'Oslo') asList equals: #('city' '==' 'Oslo').

lesson check: 'age < 5 is false for an element without an age' is: ((age < 5) evaluate: ageless) equals: false.
lesson check: 'so (age < 5) not is true for it' is: ((age < 5) not evaluate: ageless) equals: true.
lesson check: 'notNone asks for presence' is: (age notNone evaluate: ageless) equals: false.

q := PBQuery from: people.
lesson check: 'where: refuses a Boolean'
    signals: PBValidationError containing: 'where: expects a PBExpression or a one-argument block, got a Boolean'
    during: [q where: city = 'Oslo'].
sevens := q where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'a block is a BlockFilter over a scan' is: (planOf value: sevens) equals: 'BlockFilter <- CollectionScan'.
oldSevens := (q where: age > 70) where: [:p | (p at: 'age') \\ 7 = 0].
lesson check: 'chained where: is AND: the block filters on top' is: (planOf value: oldSevens) equals: 'BlockFilter <- IndexRange'.
inOslo := PBBlockPredicate block: [:p | (p at: 'city') = 'Oslo'] description: 'city is Oslo'.
lesson check: 'an OR holding a block is one BlockFilter for the whole condition'
    is: ((q where: (age > 70) | inOslo) explain at: 'description') equals: '(age > 70) | (city is Oslo)'.
lesson check: 'and it answers what the condition says: 70 old people, 150 in Oslo, 20 both'
    is: (q where: (age > 70) | inOslo) count equals: 200.

lesson finish.
