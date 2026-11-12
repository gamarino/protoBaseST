"_st_interleave.st: protoST's side of st_py_interleaved.sh (plan Task 18, fix round 1, review M2).

  protost _st_interleave.st setup <dir>      creates the database 'il': x = 1, tags = {a: 1}
  protost _st_interleave.st st-first <dir>   transaction A reads x and B writes tags blindly;
                                              ProtoBase commits in between (py_interleave.py
                                              commit, run as a subprocess: x = 'py' and a
                                              blind write of tags {py}); then A's commit is
                                              PBConflictError and B's merges
  protost _st_interleave.st commit <dir>     one-shot, for py_interleave.py py-first: x = 'st2'
                                              and a blind write of tags {st2}
 Each mode prints one line ('setup', 'ok', 'committed'); any failure is an error."
Import from: 'protobase'.

| args mode dir space db a b run expect outcome |
args := Smalltalk arguments.
mode := args at: 1.
dir := args at: 2.
expect := [:label :actual :expected |
  actual = expected ifFalse: [^ Error signal: label , ': expected ' , expected printString , ', got ' , actual printString]].
space := PBObjectSpace storage: (PBFileStorage path: dir).
mode = 'setup' ifTrue: [
  db := space newDatabase: 'il'.
  db newTransactionDo: [:t |
    t setRootObject: 'x' value: 1.
    t setRootObject: 'tags' value: (t newDictionary setAt: 'a' value: 1)].
  'setup' displayNl].
mode = 'commit' ifTrue: [
  (space openDatabase: 'il') newTransactionDo: [:t |
    t setRootObject: 'x' value: 'st2'.
    t setRootObject: 'tags' value: (t newDictionary setAt: 'st2' value: 1)].
  'committed' displayNl].
mode = 'st-first' ifTrue: [
  db := space openDatabase: 'il'.
  a := db newTransaction.
  b := db newTransaction.
  expect value: 'A reads x' value: (a getRootObject: 'x') value: 1.
  b setRootObject: 'tags' value: (b newDictionary setAt: 'st' value: 1).
  run := OSProcess run: (Smalltalk getenv: 'PY') arguments: { 'py_interleave.py'. 'commit'. dir }.
  expect value: 'ProtoBase commits in between' value: { run exitCode. run output trimBoth } value: { 0. 'committed' }.
  a setRootObject: 'x' value: 'st'.
  outcome := [a commit. 'committed'] on: PBConflictError do: [:e | 'conflict'].
  expect value: 'A read x, which ProtoBase changed' value: outcome value: 'conflict'.
  b commit.
  db := space openDatabase: 'il'.
  expect value: 'x is ProtoBase''s' value: (db newTransaction getRootObject: 'x') value: 'py'.
  expect value: 'the blind writes merged' value: (db newTransaction getRootObject: 'tags') keys asArray
    value: #('a' 'py' 'st').
  'ok' displayNl].
space close.
