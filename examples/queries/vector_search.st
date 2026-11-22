"EXPECT: vector search ok (14 checks)"
"Vector similarity search: a vector index on a collection, k-nearest queries combined with
 conditions. A port of proto_db's examples/vector_search.py (v2.0.0rc4, lines 1-85). Quoted by
 docs/queries.md, 'Vector search'.

 Written by the vectors task V0 against the API of Addendum V
 (docs/superpowers/specs/2026-11-19-vectors-addendum.md, sections 2.3 to 2.9) before that API
 existed; moved here from examples/queries/pending/ by task V7, which built the last of it (the
 planner's near[] rules and PBField near:), and run as a test since, unchanged.

 300 documents carry a small embedding. One collection holds an exact vector index, another the
 same documents with an IVF-Flat index whose nprobe equals its nlist (so it probes every list and
 its answer is exact). Both answer near queries; explain shows which backend ran; every answer is
 checked against a brute-force search, as the Python example does. The embeddings come from a
 seeded generator written here (Park and Miller's): protoST's Random is not Python's, so the data
 is not the Python example's, and the program checks the answers, not the Python example's ids.

 Run it from examples/queries: STPATH=<repository>/src protost vector_search.st"
Import from: 'protobase'.
Import from: '../tutorial/_lesson'.

| lesson topics seed next docs dot norm cosine query ranked exact ivf |
lesson := Lesson named: 'vector search'.
topics := #('sports' 'music' 'science').
seed := 7.
next := [seed := seed * 16807 \\ 2147483647. seed / 2147483647.0 * 2.0 - 1.0].
docs := (0 to: 299) collect: [:i | PBObject withAll: {
    'i' -> i. 'topic' -> (topics at: i \\ 3 + 1). 'vec' -> ((1 to: 8) collect: [:j | next value]) }].
dot := [:a :b | | s | s := 0.0. 1 to: a size do: [:j | s := s + ((a at: j) * (b at: j))]. s].
norm := [:a | (dot value: a value: a) sqrt].
cosine := [:a :b | (dot value: a value: b) / ((norm value: a) * (norm value: b))].

"Two collections of the same documents: an exact index, and IVF-Flat probing all of its 8 lists."
exact := PBList new addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 8 metric: 'cosine').
ivf := PBList new addIndex: (PBVectorIndex name: 'by_vec_ivf' keySpec: (PBKeySpec path: 'vec') dim: 8
    metric: 'cosine' backend: 'ivf_flat' params: (Dictionary new at: 'nlist' put: 8; at: 'nprobe' put: 8; yourself)).
docs do: [:d | exact := exact appendLast: d. ivf := ivf appendLast: d].

query := (docs at: 43) at: 'vec'.
ranked := docs asSortedCollection: [:a :b | (cosine value: query value: (a at: 'vec')) >= (cosine value: query value: (b at: 'vec'))].
{ exact -> 'exact'. ivf -> 'ivf_flat' } do: [:pair | | coll nearest plan music close |
    coll := pair key.
    nearest := (PBQuery from: coll) where: ((PBField path: 'vec') near: query k: 5).
    plan := nearest explain.
    lesson check: pair value , ': the plan is a VectorSearch' is: (plan at: 'plan') equals: 'VectorSearch'.
    lesson check: pair value , ': its backend' is: ((plan at: 'index') at: 'backend') equals: pair value.
    lesson check: pair value , ': the five nearest, as brute force'
        is: (nearest asArray collect: [:d | d at: 'i']) equals: ((ranked first: 5) asArray collect: [:d | d at: 'i']).

    "The k nearest among the documents of one topic: the condition applies before the k are chosen."
    music := ((PBQuery from: coll) where: (((PBField path: 'vec') near: query k: 3) & ((PBField path: 'topic') eq: 'music'))) asArray.
    lesson check: pair value , ': the three nearest music documents'
        is: (music collect: [:d | d at: 'i'])
        equals: (((ranked select: [:d | (d at: 'topic') = 'music']) first: 3) asArray collect: [:d | d at: 'i']).

    "Everything within a similarity threshold."
    close := ((PBQuery from: coll) where: ((PBField path: 'vec') near: query threshold: 0.6)) asArray.
    lesson check: pair value , ': every document at least 0.6 similar'
        is: (close collect: [:d | d at: 'i']) asSet
        equals: ((docs select: [:d | (cosine value: query value: (d at: 'vec')) >= 0.6]) collect: [:d | d at: 'i']) asSet].

"Neither collection was changed by being queried, and both validate."
lesson check: 'the exact collection validates' is: exact validate size equals: 300.
lesson check: 'the IVF collection validates, trained' is: ((ivf validate getIndex: 'by_vec_ivf') explain at: 'trained_size') > 0 equals: true.
lesson check: 'the IVF lists' is: ((ivf getIndex: 'by_vec_ivf') explain at: 'lists') equals: 8.
lesson check: 'a near[] term is refused by a scan' signals: PBNotSupportedError containing: 'near'
    during: [((PBField path: 'vec') near: query k: 1) matches: (docs at: 1)].
lesson finish.
