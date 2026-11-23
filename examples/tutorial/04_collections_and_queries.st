"EXPECT: 04 collections and queries ok (19 checks)"
"Lesson 04: the four writable collections, and how to ask questions of them.
 Tutorial chapter: docs/tutorial/04-collections-and-queries.md

 What it teaches:
 - PBDictionary (ordered by the format's order key), PBHashDictionary (by hash), PBSet and
   PBCountedSet, all answering new versions;
 - keys follow the format's equality, not protoST's =: 1, 1.0 and Decimal 1.00 are one key;
 - a PBTuple is an ordered, composite key;
 - there is no query language and no index query in this prototype: a question is a walk
   over a collection, or a lookup in a second collection that the program keeps up to date
   in the same transaction (a hand-made index). Since 0.3.0 protoBaseST also maintains
   and queries proto_db's equality and range indexes (chapters 17-19), and since 0.4.0 it
   maintains its vector indexes; only a collection holding an index of a kind it does not
   know refuses every change.

 Run it: STPATH=<repository>/src protost 04_collections_and_queries.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson prices byYear shelf a b counts dir space db books old found addBook copy people changed |
lesson := Lesson named: '04 collections and queries'.

"PBDictionary: keys are compared and ordered by the format's order key."
prices := PBDictionary new setAt: 1 value: 'one'.
prices := prices setAt: 1.0 value: 'one, as a float'.
prices := prices setAt: (Decimal fromString: '1.00') value: 'one, as a decimal'.
lesson check: '1, 1.0 and 1.00 are one key' is: prices count equals: 1.
lesson check: 'the last write won' is: (prices getAt: 1) equals: 'one, as a decimal'.
lesson check: 'true is not 1' isTrue: (prices has: true) not.
lesson check: 'getAt:default: for an absent key' is: (prices getAt: 2 default: 'none') equals: 'none'.

"A PBTuple is a composite key; tuples order item by item."
byYear := PBDictionary new.
byYear := byYear setAt: (PBTuple withAll: #(1989 'The Language')) value: 'blue'.
byYear := byYear setAt: (PBTuple withAll: #(1983 'Bits of History')) value: 'green'.
byYear := byYear setAt: (PBTuple withAll: #(1983 'The Interactive Programming Environment')) value: 'orange'.
lesson check: 'iteration is in key order' is: byYear values asArray equals: #('green' 'orange' 'blue').

"PBSet and PBCountedSet."
a := (PBSet new add: 'pharo') add: 'gemstone'.
b := (PBSet new add: 'gemstone') add: 'protost'.
lesson check: 'union' is: (a union: b) elements equals: #('gemstone' 'pharo' 'protost').
lesson check: 'intersection' is: (a intersection: b) elements equals: #('gemstone').
lesson check: 'difference' is: (a difference: b) elements equals: #('pharo').
counts := ((PBCountedSet new add: 'loan') add: 'loan') add: 'return'.
lesson check: 'a counted set counts occurrences' is: (counts countOf: 'loan') equals: 2.
lesson check: 'count is distinct elements, totalCount all of them' is: { counts count. counts totalCount } equals: #(2 3).

"PBHashDictionary: the same protocol, iterated in hash order."
lesson check: 'a hash dictionary' is: ((PBHashDictionary new setAt: 'k' value: 1) getAt: 'k') equals: 1.

"Queries. A catalogue of books, and a hand-made index by year, kept in the same transaction."
dir := FileSystem temp / ('pbst-tutorial-04-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'library'.
db newTransactionDo: [:tr |
    tr setRootObject: 'books' value: tr newDictionary.
    tr setRootObject: 'byYear' value: tr newDictionary].
"Adds a book and its index entry in one transaction: both change, or neither."
addBook := [:isbn :title :year |
    db run: [:tr |
        | catalogue index |
        catalogue := tr getRootObject: 'books'.
        index := tr getRootObject: 'byYear'.
        tr setRootObject: 'books' value: (catalogue setAt: isbn
            value: (tr newObject: { 'title' -> title. 'year' -> year })).
        tr setRootObject: 'byYear' value: (index setAt: year
            value: ((index getAt: year default: PBSet new) add: isbn))]].
addBook value: '0201113716' value: 'Smalltalk-80: The Language and its Implementation' value: 1983.
addBook value: '0201136880' value: 'Bits of History, Words of Advice' value: 1983.
addBook value: '0201113724' value: 'Smalltalk-80: The Interactive Programming Environment' value: 1984.
addBook value: '0201139421' value: 'Smalltalk/V' value: 1986.

books := db newTransaction getRootObject: 'books'.
"A query is a walk: no planner, no index, every element visited."
old := OrderedCollection new.
books keysAndValuesDo: [:isbn :book | (book at: 'year') < 1985 ifTrue: [old add: isbn]].
lesson check: 'a walk: books before 1985' is: old asArray equals: #('0201113716' '0201113724' '0201136880').
"The hand-made index answers the same question by lookups."
found := OrderedCollection new.
(db newTransaction getRootObject: 'byYear') keysAndValuesDo: [:year :isbns |
    year < 1985 ifTrue: [isbns do: [:isbn | found add: isbn]]].
lesson check: 'the index agrees with the walk' is: (found asArray asSortedCollection: [:x :y | x <= y]) asArray
    equals: old asArray.
lesson check: 'a lookup by year' is: ((db newTransaction getRootObject: 'byYear') getAt: 1983) elements
    equals: #('0201113716' '0201136880').
lesson say: 'catalogue of ' , books count printString , ' books, ' , (db newTransaction getRootObject: 'byYear') count printString , ' years indexed'.
space close.

"proto_db's own indexes are read, and an equality or range index is maintained by every change
 (0.3.0, chapter 17). The conformance database written by proto_db has a root 'people' with two
 indexes."
copy := dir / 'indexed'.
copy ensureCreateDirectory.
'../../tests/conformance/vectors/database' asFileReference files do: [:f | f copyTo: copy / f basename].
space := PBObjectSpace storage: (PBFileStorage path: copy pathString).
people := (space openDatabase: 'db') newTransaction getRootObject: 'people'.
lesson check: 'the indexes are read' is: people indexNames equals: #('by_age' 'by_city').
lesson check: 'an index keeps its definition' is: (people getIndex: 'by_age') name equals: 'by_age'.
lesson check: 'the indexed collection is read as usual' is: people count equals: people keys size.
changed := people setAt: 'zed' value: (PBObject withAll: { 'name' -> 'Zed'. 'age' -> 40 }).
lesson check: 'a change answers a new version with one more element' is: changed count equals: people count + 1.
lesson check: 'whose indexes were maintained in the same step'
    is: ([changed validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.
space close.
dir deleteAll.
lesson finish.
