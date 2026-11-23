"EXPECT: vector plans ok (15 checks)"
"The worked vector plan of docs/queries.md ('A worked vector plan'): one collection with two vector
 indexes on the same path, an exact one and an IVF-Flat one that probes 2 of its 8 lists, and the
 plans the planner builds for a k-nearest query, the same query with a condition, and a threshold.
 Every figure checked here is a model estimate (the cost model of docs/queries.md, D30), never a
 measurement; ruling CR10 requires each to equal proto_db's own planner output for the same data,
 which tests/interop/py_guide_plans.py generates and tests/docs/guide_plans.sh compares with the
 guide's text and with the literal figures below.

 The data is that of vector_search.st: 300 documents with an 8-dimensional embedding from a seeded
 generator written here (Park and Miller's), so every run builds the same data.

 Run it from examples/queries: STPATH=<repository>/src protost vector_plans.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson topics seed next docs both query vec nearest plan child exactOnly music filtered close est exactFive |
lesson := Lesson named: 'vector plans'.
topics := #('sports' 'music' 'science').
seed := 7.
next := [seed := seed * 16807 \\ 2147483647. seed / 2147483647.0 * 2.0 - 1.0].
docs := (0 to: 299) collect: [:i | PBObject withAll: {
    'i' -> i. 'topic' -> (topics at: i \\ 3 + 1). 'vec' -> ((1 to: 8) collect: [:j | next value]) }].
est := [:node :field | (node at: 'estimate') at: field].

"One collection, two vector indexes on 'vec': exact, and IVF-Flat probing 2 of its 8 lists."
both := PBList new addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 8 metric: 'cosine').
both := both addIndex: (PBVectorIndex name: 'by_vec_ivf' keySpec: (PBKeySpec path: 'vec') dim: 8
    metric: 'cosine' backend: 'ivf_flat' params: (Dictionary new at: 'nlist' put: 8; at: 'nprobe' put: 2; yourself)).
docs do: [:d | both := both appendLast: d].
query := (docs at: 43) at: 'vec'.
vec := PBField path: 'vec'.

"Plan 1: the five nearest. Both indexes support the term; the planner takes the cheaper."
nearest := (PBQuery from: both) where: (vec near: query k: 5).
plan := nearest explain.
child := (plan at: 'children') at: 1.
lesson check: 'plan 1 is a VectorSearch over the IVF index' is: { plan at: 'plan'. child at: 'plan'. (plan at: 'index') at: 'index' }
    equals: #('VectorSearch' 'VectorIvfFlat' 'by_vec_ivf').
lesson check: 'the IVF index: 8 lists, 300 members' is: { (plan at: 'index') at: 'lists'. (plan at: 'index') at: 'members' } equals: #(8 300).
lesson check: 'rows: k' is: (est value: plan value: 'rows') equals: 5.0.
lesson check: 'cost: 8 centroids + 300 x 2/8 + rows + 1' is: (est value: plan value: 'cost') equals: 89.0.
exactOnly := (PBQuery from: (both removeIndex: 'by_vec_ivf')) where: (vec near: query k: 5).
lesson check: 'the rejected candidate, made visible: the exact index' is: ((exactOnly explain at: 'index') at: 'index') equals: 'by_vec'.
lesson check: 'its cost: 300 + rows + 1' is: (est value: exactOnly explain value: 'cost') equals: 306.0.

"Plan 2: the three nearest music documents. The condition goes inside the search (rule 2), which
 touches each probed member twice: once to evaluate the condition, once to score it."
music := (PBQuery from: both) where: ((vec near: query k: 3) & ((PBField path: 'topic') eq: 'music')).
filtered := music explain.
lesson check: 'plan 2 is one VectorSearch with a where, no Filter' is: { filtered at: 'plan'. filtered includesKey: 'where' } equals: #('VectorSearch' true).
lesson check: 'its index is the IVF one again' is: ((filtered at: 'index') at: 'index') equals: 'by_vec_ivf'.
lesson check: 'its cost: 8 + 300 x 2/8 x 2 + 3 + 1' is: (est value: filtered value: 'cost') equals: 162.0.
lesson check: 'the exact index would cost 2 x 300 + 3 + 1'
    is: (est value: ((PBQuery from: (both removeIndex: 'by_vec_ivf'))
        where: ((vec near: query k: 3) & ((PBField path: 'topic') eq: 'music'))) explain value: 'cost') equals: 604.0.

"Plan 3: a threshold alone. Without k the model guesses half the members."
close := ((PBQuery from: both) where: (vec near: query threshold: 0.6)) explain.
lesson check: 'plan 3: half the members' is: (est value: close value: 'rows') equals: 150.0.
lesson check: 'its cost: 8 + 75 + 150 + 1' is: (est value: close value: 'cost') equals: 234.0.
lesson check: 'the exact index would cost 300 + 150 + 1'
    is: (est value: ((PBQuery from: (both removeIndex: 'by_vec_ivf')) where: (vec near: query threshold: 0.6)) explain value: 'cost')
    equals: 451.0.

"The cheaper plan is the approximate one: the model counts work, not recall. Probing 2 lists of 8,
 the IVF search finds only some of the exact five."
exactFive := (exactOnly asArray collect: [:d | d at: 'i']) asSet.
lesson check: 'the IVF answer is five documents' is: nearest asArray size equals: 5.
lesson check: 'of them, among the exact five' is: (nearest asArray select: [:d | exactFive includes: (d at: 'i')]) size equals: 3.
lesson finish.
