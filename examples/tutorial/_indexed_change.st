"_indexed_change.st: protoST's step of the indexed part of lesson 11 (a helper, run by
 11_indexed_interop.sh).

 Usage: protost _indexed_change.st <directory>
 Changes the collection Python indexed, through its mutators and through a merge of a blind
 write. The last line is the lesson's: '11 indexed interop ok (N checks)'."
Import from: 'protobase'.
Import from: '_lesson'.

| lesson space db people inOslo mine docs nearest query |
lesson := Lesson named: '11 indexed interop'.
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space openDatabase: 'people'.
inOslo := [:ps | ((PBQuery from: ps) where: ((PBField path: 'city') eq: 'Oslo')) count].
people := db newTransaction getRootObject: 'people'.
lesson check: 'Python''s indexes are read' is: people indexNames equals: #('by_age' 'by_city').
lesson check: 'and queried here' is: (inOslo value: people) equals: 10.
db run: [:tr | | ps |
    ps := tr getRootObject: 'people'.
    ps := ps setAt: 0 value: ((ps getAt: 0) with: 'city' value: 'Oslo').
    ps := ps removeAt: 1.
    ps := ps setAt: 40 value: (tr newObject: { 'name' -> 'person40'. 'city' -> 'Oslo'. 'age' -> 58 }).
    tr setRootObject: 'people' value: ps].
lesson check: 'protoST changed a Python-indexed collection' is: (inOslo value: (db newTransaction getRootObject: 'people')) equals: 11.
mine := db newTransaction.
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 41 value: (mine newObject: { 'name' -> 'person41'. 'city' -> 'Oslo'. 'age' -> 59 })).
mine commit.
people := db newTransaction getRootObject: 'people'.
lesson check: 'a blind write merged onto it' is: (inOslo value: people) equals: 12.
lesson check: 'every element is there' is: people count equals: 41.
lesson check: 'the indexes are still Python''s two' is: people indexNames equals: #('by_age' 'by_city').
lesson check: 'and each equals a scan'
    is: ([people validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.

"The vector index (0.4.0): Python's, queried, changed and merged onto here, as the others."
query := #(12.25 3.0 0.5).
nearest := [:ds | ((PBQuery from: ds) where: ((PBField path: 'vec') near: query k: 3)) asArray collect: [:d | d at: 'title']].
docs := db newTransaction getRootObject: 'docs'.
lesson check: 'Python''s vector index is read' is: docs indexNames equals: #('by_vec').
lesson check: 'and searched here' is: (nearest value: docs) equals: #('doc13' 'doc12' 'doc10').
db run: [:tr | | ds |
    ds := tr getRootObject: 'docs'.
    ds := ds setAt: 12 value: ((ds getAt: 12) with: 'vec' value: #(30.0 0.0 0.5)).
    ds := ds removeAt: 13.
    ds := ds setAt: 40 value: (tr newObject: { 'title' -> 'doc40'. 'vec' -> #(12.25 3.0 0.5) }).
    tr setRootObject: 'docs' value: ds].
mine := db newTransaction.
mine setRootObject: 'docs' value: (mine newDictionary
    setAt: 41 value: (mine newObject: { 'title' -> 'doc41'. 'vec' -> #(12.0 3.0 0.5) })).
mine commit.
docs := db newTransaction getRootObject: 'docs'.
lesson check: 'a blind write merged onto it: protoST''s two documents come first'
    is: ((nearest value: docs) first: 2) equals: #('doc40' 'doc41').
lesson check: 'every document is there' is: docs count equals: 41.
lesson check: 'the vector index equals a scan'
    is: ([docs validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
space close.
lesson finish.
