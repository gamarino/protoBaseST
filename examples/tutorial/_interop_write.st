"_interop_write.st: protoST's first step of lesson 11 (a helper, run by 11_python_interop.sh).

 Usage: protost _interop_write.st <directory>
 Creates the database 'library' with two books (records of type tutorial.interop.Book), a
 mutable cell for their author, and an empty dictionary of tags. Prints 'protoST wrote 2 books'."
Import from: 'protobase'.

PBObject subclass: #Book.

Book class >> typeName
  ^ 'tutorial.interop.Book'.

PBObjectSpace registerAtomClass: Book.

| space db author |
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space newDatabase: 'library'.
author := PBMutableObject name: 'author:goldberg'.
db newTransactionDo: [:tr |
    tr newMutable: author name value: 'Adele Goldberg'.
    tr setRootObject: 'books' value: ((tr newDictionary
        setAt: 1 value: (Book withAll: {
            'title' -> 'Smalltalk-80: The Language'.
            'author' -> author.
            'price' -> (Decimal fromString: '54.90').
            'published' -> (CalendarDate year: 1989 month: 1 day: 1).
            'cover' -> #[137 80 78 71] }))
        setAt: 2 value: (Book withAll: {
            'title' -> 'Bits of History, Words of Advice'.
            'author' -> author.
            'price' -> (Decimal fromString: '39.00').
            'published' -> (CalendarDate year: 1983 month: 1 day: 1).
            'cover' -> #[] })).
    tr setRootObject: 'tags' value: tr newDictionary].
space close.
'protoST wrote 2 books' displayNl.
