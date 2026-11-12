"_st_case.st: protoST's side of one case of the concurrency table (design spec 10.4, plan Task 21
 and call C12), run by concurrency.sh and by py_case.py.

  protost _st_case.st a <case> <dir>   starts A, runs ProtoBase's B to completion as a
                                        subprocess ($PY py_case.py b), then commits A; prints the
                                        outcome line 'A=<outcome> B=<outcome>' and the dump
  protost _st_case.st b <case> <dir>   one-shot, for py_case.py a: starts B and commits it;
                                        prints 'B=<outcome>'
  protost _st_case.st dump <case> <dir>  prints the dump, read by protoBaseST

The space must exist (py_case.py setup). The steps and the dump are those of _case_ops.st."
Import from: 'protobase'.
Import from: '_case_ops'.

| args mode case dir space db a b run line |
args := Smalltalk arguments.
mode := args at: 1.
case := CaseTable case: (args at: 2).
dir := args at: 3.
space := PBObjectSpace storage: (PBFileStorage path: dir).
db := space openDatabase: (CaseTable databaseOf: case).
mode = 'a' ifTrue: [
  a := CaseSide new start: (case at: 'a') in: db.
  run := OSProcess run: (Smalltalk getenv: 'PY') arguments: { 'py_case.py'. 'b'. case at: 'id'. dir }.
  line := run output trimBoth.
  (run exitCode = 0 and: [line beginsWith: 'B=']) ifFalse: [
    ^ Error signal: 'ProtoBase''s B failed (exit ' , run exitCode printString , '): ' , line].
  b := line copyFrom: 3 to: line size.
  ('A=' , a commit , ' B=' , b) displayNl.
  (CaseTable dump: case in: db) do: [:each | each displayNl]].
mode = 'b' ifTrue: [
  b := CaseSide new start: (case at: 'b') in: db.
  ('B=' , b commit) displayNl].
mode = 'dump' ifTrue: [(CaseTable dump: case in: db) do: [:each | each displayNl]].
space close.
