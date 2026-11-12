"_st_over_text.st <space directory>: a helper of st_deep_to_py.sh (never run as a test). Reads
 the root 'over' of database 'db', a record 1025 MessagePack containers deep, and prints the
 text of the PBCorruptionError protoST refuses it with (ProtoBase's
 storage.format.undecodable_atom sentence); exits 1 if it is read or refused otherwise."
Import from: 'protobase'.

| args space tx text |
args := Smalltalk arguments.
args size = 1 ifFalse: ['usage: _st_over_text.st <space directory>' displayNl. Smalltalk exit: 2].
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
tx := (space openDatabase: 'db') newTransaction.
text := [(tx getRootObject: 'over') at: 'v'. nil] on: PBCorruptionError do: [:e | e messageText].
tx abort.
space close.
text isNil ifTrue: ['FAIL: the record 1025 deep was read' displayNl. Smalltalk exit: 1].
text displayNl.
