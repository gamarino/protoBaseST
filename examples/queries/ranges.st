"EXPECT: ranges ok (12 checks)"
"Ranges and ordered reads. Quoted by docs/queries.md, 'Ordered reads, windows and pages'.

 A range index on the age of chapter 18's 600 people (ten of each age, 18 to 77) answers the
 comparisons and the between forms by IndexRange, counts a range by rank, and yields its key in
 order: orderBy: with take: streams an IndexOrderedScan and seeks the window by rank (a Limit with
 'by_rank'), ascending or descending, and any plan with rank access answers windowFrom:to:
 without producing the rows before the window (proto_db D56).

 Run it: STPATH=<repository>/src protost ranges.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson cities people planOf age q youngest oldest |
lesson := Lesson named: 'ranges'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
people := PBDictionary new.
0 to: 599 do: [:i |
    people := people setAt: i value: (PBObject withAll: {
        'name' -> ('person' , i printString). 'city' -> (cities at: i \\ 4 + 1). 'age' -> (18 + (i \\ 60)) })].
people := people addIndex: (PBRangeIndex name: 'by_age' path: 'age').

"The node names of a query's plan, from the root down its first children."
planOf := [:query | | names node |
    names := OrderedCollection new.
    node := query explain.
    [node isNil] whileFalse: [
        names add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].
q := PBQuery from: people.
age := PBField path: 'age'.

lesson check: 'a comparison is a range of the index' is: (planOf value: (q where: age > 70)) equals: 'IndexRange'.
lesson check: 'seven ages of ten people' is: (q where: age > 70) count equals: 70.
lesson check: 'counted by rank' is: ((PBCountPlan source: (q where: age > 70) plan) explain at: 'by_rank') equals: true.
youngest := (q orderBy: 'age') take: 5.
lesson check: 'an ordered read streams the index' is: (planOf value: youngest) equals: 'Limit <- IndexOrderedScan'.
lesson check: 'and seeks its window by rank' is: (youngest explain at: 'by_rank') equals: true.
lesson check: 'the five youngest' is: (youngest asArray collect: [:p | p at: 'age']) equals: #(18 18 18 18 18).
oldest := (q orderBy: 'age' descending: true) take: 3.
lesson check: 'descending reads the index backwards' is: (oldest asArray collect: [:p | p at: 'age']) equals: #(77 77 77).
lesson check: 'a window of any plan with rank access'
    is: (((q orderBy: 'age') plan windowFrom: 100 to: 103) collect: [:p | p at: 'age']) equals: #(28 28 28).

"The between forms, each a range: [30, 35] holds six ages, (30, 35) four, the half-open ones five."
lesson check: 'the between forms count their bounds'
    is: { (q where: (age between: 30 and: 35)) count. (q where: (age betweenOpen: 30 and: 35)) count.
        (q where: (age betweenLeftOpen: 30 and: 35)) count. (q where: (age betweenRightOpen: 30 and: 35)) count }
    equals: #(60 40 50 50).
lesson check: 'each one a range of the index'
    isTrue: ({ age between: 30 and: 35. age betweenOpen: 30 and: 35. age betweenLeftOpen: 30 and: 35. age betweenRightOpen: 30 and: 35 }
        allSatisfy: [:each | (planOf value: (q where: each)) = 'IndexRange']).
lesson check: 'a selective range is sorted, not streamed'
    is: (planOf value: (((q where: (age between: 30 and: 35)) orderBy: 'age') take: 5)) equals: 'Limit <- Sort <- IndexRange'.
lesson check: 'skip: and take: are one window: people 11 to 13 by age'
    is: ((((q orderBy: 'age') skip: 10) take: 3) asArray collect: [:p | p at: 'age']) equals: #(19 19 19).

lesson finish.
