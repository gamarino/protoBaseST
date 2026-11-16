"EXPECT: 12 refusals ok (14 checks)"
"Lesson 12: what protoBaseST refuses, and what each refusal protects.
 Tutorial chapter: docs/tutorial/12-refusals.md

 What it teaches: if a value, a type, a version or an operation cannot be stored or done
 exactly, protoBaseST signals an error naming it, at the call that receives it. It never
 stores something else in its place. Each refusal below protects a property of the file that
 Python and protoST share. The full list is docs/deviations.md.

 Run it: STPATH=<repository>/src protost 12_refusals.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson d dir space db tr text |
lesson := Lesson named: '12 refusals'.
d := PBDictionary new.

"Values with no kind in the format, or whose bytes would not be fixed."
text := lesson check: 'a Fraction: storing it as a float would be another number'
    signals: PBValidationError containing: 'a Fraction cannot be stored' during: [d setAt: 'k' value: 1/3].
lesson say: text.
lesson check: 'a protoST Dictionary: its order is unspecified, and a map''s order is in its bytes'
    signals: PBValidationError containing: 'its order is unspecified' during: [d setAt: 'k' value: Dictionary new].
lesson check: 'a Symbol longer than six bytes: the format has no symbol kind yet'
    signals: PBValidationError containing: 'a Symbol cannot be stored' during: [d setAt: 'k' value: #customer].
lesson check: 'a Set (protoST''s): use a PBSet'
    signals: PBValidationError containing: 'Set' during: [d setAt: 'k' value: (Set with: 1)].
lesson check: 'a block: code is not stored'
    signals: PBValidationError containing: 'cannot be stored' during: [d setAt: 'k' value: [:x | x]].
lesson check: 'a list as a key: keys must be orderable, use a PBTuple'
    signals: PBValidationError containing: 'not an orderable key' during: [d setAt: (PBFrozenList withAll: #(1)) value: 0].
lesson check: 'what is accepted instead: a PBFrozenDict keeps its order'
    is: ((d setAt: 'k' value: (PBFrozenDict withAssociations: { 'b' -> 1. 'a' -> 2 })) getAt: 'k') keys asArray
    equals: #('b' 'a').

"Names that belong to the format."
dir := FileSystem temp / ('pbst-tutorial-12-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'refusals'.
tr := db newTransaction.
lesson check: 'a root name starting with __'
    signals: PBValidationError containing: 'reserved for the format' during: [tr setRootObject: '__meta' value: 1].
lesson check: 'an attribute named oid'
    signals: PBValidationError containing: 'oid' during: [tr newObject: { 'oid' -> 1 }].
tr abort.

"Misuse: a finished transaction, a closed space, a database that does not exist."
lesson check: 'a transaction after its end'
    signals: PBUserError containing: 'aborted' during: [tr setRootObject: 'x' value: 1].
lesson check: 'a database that does not exist'
    signals: PBValidationError containing: 'nope' during: [space openDatabase: 'nope'].
space close.
lesson check: 'a closed space'
    signals: PBClosedError containing: '' during: [space openDatabase: 'refusals'].

"Directories this prototype cannot handle exactly are refused when opened."
(dir / 'cluster') ensureCreateDirectory.
lesson check: 'a cluster directory (no cluster mode here)'
    signals: PBNotSupportedError containing: 'cluster' during: [PBFileStorage path: dir pathString].

"Short symbols: in protoST a literal of six bytes or fewer IS a String, so it is accepted."
lesson check: '#paid is the String ''paid''' is: ((d setAt: 'k' value: #paid) getAt: 'k') equals: 'paid'.
dir deleteAll.
lesson finish.
