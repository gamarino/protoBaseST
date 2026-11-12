"_st_commit_space.st: protoST's side of st_commit_to_py.sh (plan Task 18): commits through the
 transaction API and the publisher.

  protost _st_commit_space.st create <dir>   creates the database 'tx' (version 0), then commits
                                              version 1 (roots 'n', 'tags', 'list', 'person', the
                                              cell 'counter') and version 2 (a blind merge into
                                              'tags', the cell set to 6); prints 'created'
  protost _st_commit_space.st extend <dir>   after ProtoBase's commit (version 3: 'tags' gets
                                              'py' by a blind merge, 'counter' 7): checks that
                                              protoST reads it, then commits version 4 with a
                                              blind merge of 'st2' into 'tags'; prints 'extended'
 Any failure is an error (a non-zero exit)."
Import from: 'protobase'.

| args mode dir space db tx tags expect |
args := Smalltalk arguments.
mode := args at: 1.
dir := args at: 2.
expect := [:label :actual :expected |
  actual = expected ifFalse: [^ Error signal: label , ': expected ' , expected printString , ', got ' , actual printString]].
space := PBObjectSpace storage: (PBFileStorage path: dir).
mode = 'create' ifTrue: [
  db := space newDatabase: 'tx'.
  db newTransactionDo: [:t |
    t setRootObject: 'n' value: 42.
    t setRootObject: 'tags' value: (t newDictionary setAt: 'a' value: 1).
    t setRootObject: 'list' value: ((t newList appendLast: 'x') appendLast: 'y').
    t setRootObject: 'person' value: (t newObject: { 'name' -> 'Ada'. 'born' -> 1815 }).
    t newMutable: 'counter' value: 5].
  db newTransactionDo: [:t |
    t setRootObject: 'tags' value: (t newDictionary setAt: 'b' value: 2).
    t setMutable: 'counter' value: 6].
  'created' displayNl].
mode = 'extend' ifTrue: [
  db := space openDatabase: 'tx'.
  tx := db newTransaction.
  expect value: 'versions' value: (db history collect: [:e | e version]) asArray value: #(3 2 1 0).
  tags := tx getRootObject: 'tags'.
  expect value: 'the tags after ProtoBase''s merge' value: tags keys asArray value: #('a' 'b' 'py').
  expect value: 'the cell' value: (tx getMutable: 'counter') value: 7.
  tx abort.
  db newTransactionDo: [:t | t setRootObject: 'tags' value: (t newDictionary setAt: 'st2' value: true)].
  'extended' displayNl].
space close.
