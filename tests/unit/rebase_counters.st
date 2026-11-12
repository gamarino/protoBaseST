"EXPECT: ok 10"
"PBCountedSet and PBRepeatedKeysDictionary are ConcurrentOptimized, as in ProtoBase
 (sets.py CountedSet, dictionaries.py RepeatedKeysDictionary; Task 16 review I1): a new
 empty one has a complete (empty) log, so a commit merges it, and its rebase onto a current
 value answers that current value unchanged, as ProtoBase's rebase_onto of an empty log
 (CountedSet().log_is_complete and RepeatedKeysDictionary().log_is_complete are True in
 v2.0.0rc1). A fresh empty one written as an unread root therefore keeps the committed
 content instead of replacing it. Their writes are not here: PBCountedSet's (with the counter
 merge, plan Task 22) are in counted_set_ops.st and rebase_counted_set.st,
 PBRepeatedKeysDictionary's are a non-goal. The currents
 are the roots 'bag' (a CountedSet) and 'multi' (a RepeatedKeysDictionary) of the database
 vector."
Import from: 'protobase'.
Import from: '_check'.

| c base dir space snap bag multi |
c := Check new.
base := FileSystem temp / ('pbst-rebase-counters-' , Smalltalk pid printString).
base deleteAll.
dir := base / 'database'.
dir ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: dir / f basename].
space := PBObjectSpace storage: (PBFileStorage path: dir).
snap := (space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first.
bag := snap getRootObject: 'bag'.
multi := snap getRootObject: 'multi'.
c that: 'a new PBCountedSet is mergeable' isTrue: PBCountedSet new isMergeable.
c that: 'with an empty log' is: PBCountedSet new opLog size equals: 0.
c that: 'a new PBRepeatedKeysDictionary is mergeable' isTrue: PBRepeatedKeysDictionary new isMergeable.
c that: 'the current bag holds elements' isTrue: bag count > 0.
c that: 'an empty PBCountedSet rebased onto a bag answers that bag' isTrue: (PBCountedSet new rebaseOnto: bag) == bag.
c that: 'an empty PBRepeatedKeysDictionary rebased onto a multimap answers it'
  isTrue: (PBRepeatedKeysDictionary new rebaseOnto: multi) == multi.
c that: 'a loaded one is not mergeable' is: bag isMergeable equals: false.
c that: 'marked consumed, a new one is no longer mergeable' is: PBCountedSet new markConsumed isMergeable equals: false.
c that: 'a current of another class' signals: PBValidationError during: [PBCountedSet new rebaseOnto: multi].
c that: 'a PBSet is not a PBCountedSet' signals: PBValidationError during: [PBCountedSet new rebaseOnto: PBSet new].
space close.
base deleteAll.
c report displayNl.
