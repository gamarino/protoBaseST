"EXPECT: 08 bytes ok (9 checks)"
"Lesson 08: large values, bytes, and what a new version costs on disk.
 Tutorial chapter: docs/tutorial/08-bytes.md

 What it teaches:
 - a ByteArray is a value like any other: it is stored, read back byte for byte, and shared
   with Python as the format's bytes kind;
 - a new version writes only what changed. A commit that does not touch a 1 MiB value
   writes a few hundred bytes, not another MiB: the new version refers to the old bytes;
 - a value that changes is written again whole: there is no partial update of a value, so
   large and often-changing data is better split into several values (here, in chunks).
 There is no separate BLOB or stream API in protoBaseST: the format's BLOB records are not
 written by this prototype (see the chapter).

 Run it: STPATH=<repository>/src protost 08_bytes.st"
Import from: 'protobase'.
Import from: '_lesson'.

| lesson dir space db scan photo grew read chunks |
lesson := Lesson named: '08 bytes'.
dir := FileSystem temp / ('pbst-tutorial-08-' , Smalltalk pid printString).
dir deleteAll.
"The bytes the directory holds, all segment files together."
scan := [(dir children select: [:f | f basename endsWith: '.seg']) inject: 0 into: [:sum :f | sum + f size]].
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'media'.

photo := ByteArray randomBytes: 1048576.
db newTransactionDo: [:t |
    t setRootObject: 'cover' value: photo.
    t setRootObject: 'views' value: 0].
lesson check: 'the directory holds the MiB' isTrue: scan value > 1048576.

"Ten commits that do not touch the cover."
grew := scan value.
1 to: 10 do: [:i | db run: [:t | t setRootObject: 'views' value: (t getRootObject: 'views') + 1]].
grew := scan value - grew.
lesson say: 'ten small commits wrote ' , grew printString , ' bytes'.
lesson check: 'they did not copy the cover' isTrue: grew < 20000.

"Read back, here and from a new space."
read := db newTransaction getRootObject: 'cover'.
lesson check: 'read back byte for byte' isTrue: read = photo.
lesson check: 'as a ByteArray' is: read class equals: ByteArray.
space close.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space openDatabase: 'media'.
lesson check: 'and after reopening' isTrue: (db newTransaction getRootObject: 'cover') = photo.

"Changing one byte of a value writes the value again."
grew := scan value.
db newTransactionDo: [:t |
    t setRootObject: 'cover' value: ((photo copyFrom: 1 to: 1048575) , #[0])].
grew := scan value - grew.
lesson check: 'a changed value is written whole' isTrue: grew > 1048576.

"Split large, changing data into chunks: a change rewrites one chunk and the path to it."
chunks := PBList new.
1 to: 16 do: [:i | chunks := chunks appendLast: (photo copyFrom: (i - 1) * 65536 + 1 to: i * 65536)].
db newTransactionDo: [:t | t setRootObject: 'chunked' value: chunks].
grew := scan value.
db newTransactionDo: [:t |
    | list |
    list := t getRootObject: 'chunked'.
    t setRootObject: 'chunked' value: (list setAt: 5 value: (ByteArray new: 65536))].
grew := scan value - grew.
lesson say: 'changing one 64 KiB chunk wrote ' , grew printString , ' bytes'.
lesson check: 'one chunk, not the MiB' isTrue: grew < 100000.
lesson check: 'the chunks still add up' is: ((db newTransaction getRootObject: 'chunked') elements
    inject: 0 into: [:sum :each | sum + each size]) equals: 1048576.
lesson check: 'the old version still holds the old chunk'
    isTrue: (((db snapshotAt: (db history at: 2)) getRootObject: 'chunked') getAt: 5) = (photo copyFrom: 5 * 65536 + 1 to: 6 * 65536).
space close.
dir deleteAll.
lesson finish.
