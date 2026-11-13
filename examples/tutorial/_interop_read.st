"_interop_read.st: protoST's last step of lesson 11 (a helper, run by 11_python_interop.sh).

 Usage: protost _interop_read.st <directory>
 Reads what Python committed, asserts it, and adds a blind tag of its own. The last line is
 the lesson's: '11 python interop ok (N checks)'."
Import from: 'protobase'.
Import from: '_lesson'.

PBObject subclass: #Book.

Book class >> typeName
  ^ 'tutorial.interop.Book'.

PBObjectSpace registerAtomClass: Book.

| lesson space db tr books third |
lesson := Lesson named: '11 python interop'.
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space openDatabase: 'library'.
tr := db newTransaction.
books := tr getRootObject: 'books'.
third := books getAt: 3.
lesson check: 'Python''s book is a Book here' is: third class equals: Book.
lesson check: 'its title' is: (third at: 'title') equals: 'Smalltalk-80: The Interactive Programming Environment'.
lesson check: 'its price, a Decimal with its scale' is: (third at: 'price') printString equals: '47.50'.
lesson check: 'its date' is: (third at: 'published') equals: (CalendarDate year: 1984 month: 1 day: 1).
lesson check: 'its author is the same cell' is: (third at: 'author') name equals: 'author:goldberg'.
lesson check: 'renamed by Python' is: ((third at: 'author') get: tr) equals: 'Adele J. Goldberg'.
lesson check: 'versions: protoST 0 and 1, Python 2' is: (db history collect: [:e | e version]) asArray equals: #(2 1 0).
tr abort.
db newTransactionDo: [:t | t setRootObject: 'tags' value: (t newDictionary setAt: 'and' value: 'protoST')].
lesson check: 'both tags, merged' is: (db newTransaction getRootObject: 'tags') keys equals: #('and' 'from').
space close.
lesson finish.
