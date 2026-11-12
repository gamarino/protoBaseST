"Step 3, protoST: tag invoices from both languages at once.

  protost 3_tag.st <directory>

protoST opens a transaction and tags invoice 1003 without reading 'tags'. Before it commits,
a Python process (3_tag_peer.py) tags invoice 1010 and commits. Neither side read the
dictionary, so the second commit replays its operations onto the one the first left: both
tags survive, and nobody retries."
Import from: 'protobase'.
Import from: 'erp_model'.

| directory space db tr peer tags |
directory := Smalltalk arguments at: 1.
space := PBObjectSpace storage: (PBFileStorage path: directory).
db := space openDatabase: 'erp'.

tr := db newTransaction.
tr setRootObject: 'tags' value: (tr newDictionary setAt: 1003 value: 'disputed').

peer := OSProcess run: (Smalltalk getenv: 'PY') arguments: { '3_tag_peer.py'. directory }.
peer exitCode = 0 ifFalse: [^ Error signal: 'the Python peer failed: ' , peer output].
tr commit.

tags := (db snapshotAt: db history first) getRootObject: 'tags'.
((tags getAt: 1003) = 'disputed' and: [(tags getAt: 1010) = 'urgent'])
    ifFalse: [^ Error signal: 'a tag was lost'].
space close.
