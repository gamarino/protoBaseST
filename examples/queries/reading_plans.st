"EXPECT: reading plans ok (20 checks)"
"The worked plans of docs/queries.md ('Reading a plan'). The expected estimates are model estimates, not
 measurements: the output of proto_db's cost model (proto_db/indexing/keyed.py, KeyGroupIndex >>
 estimate; proto_db/query/plans.py, the estimate of each node) for this data. They were first
 worked out from those formulas; ruling CR10 requires them to equal proto_db's own planner output
 for the same data, generated from proto_db by a script (tests/interop/py_guide_plans.py), and
 tests/docs/guide_plans.sh checks both the guide's figures and this program's. The program
 checks that protoBaseST's planner computes the same. Costs are compared within 1e-9, because
 protoST's log: is ln x / ln b and may differ from C's log2 in the last bit (deviation R2).

 Run it: STPATH=<repository>/src protost reading_plans.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson dir space db cities people close q city age oslo plan index old filter range withoutAge scanOnly window sort |
lesson := Lesson named: 'reading plans'.
dir := FileSystem temp / ('pbst-queries-plans-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'people'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
db newTransactionDo: [:t |
    | ps |
    ps := t newDictionary.
    0 to: 599 do: [:i |
        ps := ps setAt: i value: (t newObject: {
            'name' -> ('person' , i printString).
            'city' -> (cities at: i \\ 4 + 1).
            'age' -> (18 + (i \\ 60)) })].
    t setRootObject: 'people' value: ((ps
        addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
        addIndex: (PBRangeIndex name: 'by_age' path: 'age'))].
people := db newTransaction getRootObject: 'people'.
close := [:a :b | (a - b) abs < 1.0e-9].
q := PBQuery from: people.
city := PBField path: 'city'.
age := PBField path: 'age'.

"Plan 1: one equality, one index."
oslo := q where: (city eq: 'Oslo').
plan := oslo explain.
index := plan at: 'index'.
lesson check: 'plan 1 is an index lookup' is: (plan at: 'plan') equals: 'IndexLookup'.
lesson check: 'the index explains itself' is: { index at: 'index'. index at: 'kind'. index at: 'key' } equals: #('by_city' 'EqualityIndex' 'city').
lesson check: 'its size: entries, keys, unorderable' is: { index at: 'entries'. index at: 'keys'. index at: 'unorderable' } equals: #(600 4 0).
lesson check: 'the term' is: { (plan at: 'term') at: 'path'. (plan at: 'term') at: 'op'. (plan at: 'term') at: 'value' } equals: #('city' '==' 'Oslo').
lesson check: 'rows: the size of the Oslo group' is: ((plan at: 'estimate') at: 'rows') equals: 150.
lesson check: 'cost: rows plus one descent, log2 (4 + 2)' isTrue: (close value: ((plan at: 'estimate') at: 'cost') value: 152.58496250072116).
lesson check: 'a leaf has no children' isTrue: (plan at: 'children') isEmpty.

"The same query in the 0.1 list syntax, planned directly."
lesson check: 'PBPlanner with the list syntax plans the same tree'
    is: (PBPlanner plan: people where: { 'city'. '=='. 'Oslo' } orderBy: nil limit: nil offset: 0) explain
    equals: plan.

"Plan 2: two conditions."
old := q where: ((city eq: 'Oslo') & (age > 70)).
filter := old explain.
range := (filter at: 'children') at: 1.
lesson check: 'plan 2 is a filter over the age range' is: { filter at: 'plan'. range at: 'plan' } equals: #('Filter' 'IndexRange').
lesson check: 'the range: 7 keys of 10 rows' is: ((range at: 'estimate') at: 'rows') equals: 70.
lesson check: 'its cost: rows + log2 (60 + 2) + keys' isTrue: (close value: ((range at: 'estimate') at: 'cost') value: 82.95419631038688).
lesson check: 'the filter halves the rows, per term' is: ((filter at: 'estimate') at: 'rows') equals: 35.
lesson check: 'and pays one unit per row it reads' isTrue: (close value: ((filter at: 'estimate') at: 'cost') value: 152.95419631038686).
withoutAge := (PBQuery from: (people removeIndex: 'by_age')) where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'the rejected candidate, made visible: the city lookup and a filter'
    isTrue: (close value: ((withoutAge explain at: 'estimate') at: 'cost') value: 302.5849625007212).
scanOnly := (PBQuery from: ((people removeIndex: 'by_age') removeIndex: 'by_city')) where: ((city eq: 'Oslo') & (age > 70)).
lesson check: 'and the scan: two units per element' is: ((scanOnly explain at: 'estimate') at: 'cost') equals: 1200.

"Plan 3: an ordered window."
window := (((q where: (age between: 30 and: 35)) orderBy: 'age') take: 5) explain.
sort := (window at: 'children') at: 1.
lesson check: 'plan 3: a limit over a sort over the range' is: { window at: 'plan'. sort at: 'plan'. ((sort at: 'children') at: 1) at: 'plan' } equals: #('Limit' 'Sort' 'IndexRange').
lesson check: 'the limit: its window, read by rank' is: { window at: 'limit'. window at: 'offset'. window at: 'by_rank' } equals: #(5 0 true).
lesson check: 'the sort key' is: ((sort at: 'keys') at: 1) equals: (PBFrozenDict withAssociations: { 'key' -> 'age'. 'descending' -> false }).
lesson check: 'the sort pays n log2 n on 60 rows'
    isTrue: (close value: ((sort at: 'estimate') at: 'cost') value: 426.367632046898).
lesson check: 'the limit is charged its whole source' isTrue: (close value: ((window at: 'estimate') at: 'cost') value: 426.367632046898).

space close.
dir deleteAll.
lesson finish.
