"EXPECT: 03 records ok (15 checks)"
"Lesson 03: record classes, and records that change by new versions.
 Tutorial chapter: docs/tutorial/03-records.md

 What it teaches:
 - an application record type subclasses PBObject, declares a language-neutral type name and
   is registered once per process with PBObjectSpace registerAtomClass:;
 - accessors only answer the stored value; a method that computes is behaviour, and its name
   is declared reserved, so no implementation may store an attribute under it;
 - with:value: and withAll: answer a new version (a new identity); the receiver is unchanged;
 - records refer to other records; after a reload the references still lead to one record.

 Run it: STPATH=<repository>/src protost 03_records.st"
Import from: 'protobase'.
Import from: '_lesson'.

PBObject subclass: #Author.

Author class >> typeName
  ^ 'tutorial.library.Author'.

Author >> name
  ^ self at: 'name'.

PBObject subclass: #Book.

Book class >> typeName
  ^ 'tutorial.library.Book'.

"Names the type was stored under before (none yet)."
Book class >> typeAliases
  ^ #().

"Behaviour names: never stored as attributes, by any implementation of the type."
Book class >> reservedAttributeNames
  ^ #('isClassic').

Book >> title
  ^ self at: 'title'.

Book >> year
  ^ self at: 'year'.

Book >> author
  ^ self at: 'author'.

"Behaviour: computed, so its name is reserved above."
Book >> isClassic
  ^ self year < 1990.

PBObjectSpace registerAtomClass: Author.
PBObjectSpace registerAtomClass: Book.

| lesson goldberg blue green revised dir space db books reread |
lesson := Lesson named: '03 records'.

goldberg := Author withAll: { 'name' -> 'Adele Goldberg' }.
blue := Book withAll: {
    'title' -> 'Smalltalk-80: The Language and its Implementation'.
    'year' -> 1983.
    'author' -> goldberg }.
green := Book withAll: {
    'title' -> 'Smalltalk-80: Bits of History, Words of Advice'.
    'year' -> 1983.
    'author' -> goldberg }.
lesson check: 'an accessor answers the stored value' is: blue year equals: 1983.
lesson check: 'behaviour computes from it' isTrue: blue isClassic.
lesson check: 'the attribute names' is: blue attributeNames asArray equals: #('author' 'title' 'year').
lesson check: 'an absent attribute is nil' isTrue: (blue at: 'publisher') isNil.

"A change is a new version, with its own identity. The receiver does not change."
revised := blue withAll: { 'title' -> 'Smalltalk-80: The Language'. 'year' -> 1989 }.
lesson check: 'the new version has the new title' is: revised title equals: 'Smalltalk-80: The Language'.
lesson check: 'the old version keeps the old one' is: blue title equals: 'Smalltalk-80: The Language and its Implementation'.
lesson check: 'two versions are two identities' isTrue: (revised = blue) not.
lesson check: 'what did not change is shared' isTrue: revised author == blue author.

"The format reserves some attribute names; the class reserves its behaviour names."
lesson check: 'a reserved behaviour name cannot be stored'
    signals: PBValidationError containing: 'isClassic' during: [blue with: 'isClassic' value: true].
lesson check: 'names starting with _ belong to the format'
    signals: PBValidationError containing: '_private' during: [blue with: '_private' value: 1].

"Stored and read back: the class comes back, and so does the shared author."
dir := FileSystem temp / ('pbst-tutorial-03-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'library'.
db newTransactionDo: [:tr |
    tr setRootObject: 'books' value: ((tr newDictionary setAt: 1 value: revised) setAt: 2 value: green)].
space close.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
books := (space openDatabase: 'library') newTransaction getRootObject: 'books'.
reread := books getAt: 1.
lesson check: 'the record comes back as a Book' is: reread class equals: Book.
lesson check: 'with its behaviour' is: reread isClassic equals: true.
lesson check: 'its author is an Author' is: reread author name equals: 'Adele Goldberg'.
lesson check: 'both books lead to one author record' isTrue: (books getAt: 1) author = (books getAt: 2) author.
lesson check: 'the type name is what the file holds' is: Book typeName equals: 'tutorial.library.Book'.
lesson say: 'stored ' , books count printString , ' books; type names are shared with any language that declares them'.
space close.
dir deleteAll.
lesson finish.
