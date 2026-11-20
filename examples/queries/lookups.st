"EXPECT: lookups ok (11 checks)"
"Equality indexes and lookups: what an equality index answers, by which plan, and that it never
 changes an answer. Quoted by docs/queries.md, 'Equality and range indexes'.

 600 people, as in chapter 18, but every tenth one has no city and every tenth from the fifth has
 an explicit nil city, so the presence tests have something to find. An equality index on the
 city answers ==, 'in' and isNone ('?N') by IndexLookup, notNone ('?!N') by IndexRange over the
 present keys, and ne: ('!=') by IndexComplement, the whole index less one group (proto_db,
 indexing/keyed.py; decision D30). The same queries over the collection without the index answer
 the same rows.

 Run it: STPATH=<repository>/src protost lookups.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson cities people plain planOf city index conditions |
lesson := Lesson named: 'lookups'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
people := PBDictionary new.
0 to: 599 do: [:i |
    people := people setAt: i value: (PBObject withAll: { 'name' -> ('person' , i printString). 'age' -> (18 + (i \\ 60)) }
        , (i \\ 10 = 0 ifTrue: [#()] ifFalse: [{ 'city' -> (i \\ 10 = 5 ifTrue: [nil] ifFalse: [cities at: i \\ 4 + 1]) }]))].
plain := people.

"The node names of the plan of a query over people with condition, from the root down its first
 children."
planOf := [:condition | | names node |
    names := OrderedCollection new.
    node := ((PBQuery from: people) where: condition) explain.
    [node isNil] whileFalse: [
        names add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].

people := people addIndex: (PBEqualityIndex name: 'by_city' path: 'city').
city := PBField path: 'city'.
lesson check: 'a lookup' is: (planOf value: (city eq: 'Oslo')) equals: 'IndexLookup'.
lesson check: 'in: is one lookup of several keys' is: (planOf value: (city in: #('Oslo' 'Rome'))) equals: 'IndexLookup'.
lesson check: 'isNone looks up nil and MISSING' is: (planOf value: city isNone) equals: 'IndexLookup'.
lesson check: 'notNone is a range over the present keys' is: (planOf value: city notNone) equals: 'IndexRange'.
lesson check: 'ne: is the complement of a group' is: (planOf value: (city ne: 'Oslo')) equals: 'IndexComplement'.

"The index explains itself: 600 entries in six key groups (four cities, nil and MISSING)."
index := (people getIndex: 'by_city') explain.
lesson check: 'the index explains itself'
    is: { index at: 'kind'. index at: 'entries'. index at: 'keys'. index at: 'unorderable' } equals: #('EqualityIndex' 600 6 0).

"An index never changes an answer: the same queries over the collection without it."
conditions := { city eq: 'Oslo'. city in: #('Oslo' 'Rome'). city isNone. city notNone. city ne: 'Oslo' }.
lesson check: 'the counts, by the index'
    is: (conditions collect: [:each | ((PBQuery from: people) where: each) count]) equals: #(120 240 120 480 420).
lesson check: 'the same counts by a scan'
    is: (conditions collect: [:each | ((PBQuery from: plain) where: each) count]) equals: #(120 240 120 480 420).
lesson check: 'and the same people'
    is: (((PBQuery from: people) where: (city ne: 'Oslo')) asArray collect: [:p | p at: 'name']) asSortedCollection asArray
    equals: (((PBQuery from: plain) where: (city ne: 'Oslo')) asArray collect: [:p | p at: 'name']) asSortedCollection asArray.
lesson check: 'ne: matches an explicit nil, a value, and never an absent key'
    is: ((PBQuery from: people) where: ((city ne: 'Oslo') & city isNone)) count equals: 60.
lesson check: 'eq: nil finds the explicit nils only' is: ((PBQuery from: people) where: (city eq: nil)) count equals: 60.

lesson finish.
