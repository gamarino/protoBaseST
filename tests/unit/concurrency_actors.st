"EXPECT: ok 40"
"The concurrency table with two protoST actors in one process (design spec 10.4, last line;
 plan Task 21). For every case of tests/interop/concurrency_cases.json, on a new space set up
 by protoST: the actor A starts its transaction and runs its steps, then the actor B does,
 then B commits, then A commits (plan call C12's order). Each step is a send whose Future the
 driver waits on before the next one, so the interleaving is fixed and nothing depends on
 timing; the driver is the script itself and never waits inside an actor, and an actor waits
 only on the publisher (known issue K23). The outcomes and the final contents must be ProtoBase's
 reference, as the JSON records it, except for the blind write onto an indexed root, where
 both commits end in protoBaseST's documented PBNotSupportedError (design spec 7.4; the JSON's
 'protobasest' entry). The same steps and dump as the cross-language runs (_case_ops.st)."
Import from: 'protobase'.
Import from: '../interop/_case_ops'.
Import from: '_check'.

| c base cases |
c := Check new.
base := FileSystem temp / ('pbst-concurrency-actors-' , Smalltalk pid printString).
base deleteAll.
cases := CaseTable load.
c that: 'the 13 rows of design spec 10.4' is: cases size equals: 13.
cases do: [:case | | id dir space db a b outcomeA outcomeB recorded |
  id := case at: 'id'.
  dir := base / id.
  CaseTable setup: case in: dir pathString.
  space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
  db := space openDatabase: (CaseTable databaseOf: case).
  a := CaseSide new asActor.
  b := CaseSide new asActor.
  (a start: (case at: 'a') in: db) wait.
  (b start: (case at: 'b') in: db) wait.
  outcomeB := b commit wait.
  outcomeA := a commit wait.
  recorded := (case includesKey: 'protobasest')
    ifTrue: [(case at: 'protobasest') at: 'actors']
    ifFalse: [case at: 'expected'].
  c that: id , ': the outcomes' is: 'A=' , outcomeA , ' B=' , outcomeB equals: (recorded at: 'outcome').
  c that: id , ': the final contents' is: (CaseTable dump: case in: db) equals: (recorded at: 'dump') asArray.
  c that: id , ': a new space reads them too' is: [ | other |
      other := PBObjectSpace storage: (PBFileStorage path: dir pathString).
      [CaseTable dump: case in: (other openDatabase: (CaseTable databaseOf: case))] ensure: [other close]] value
    equals: (recorded at: 'dump') asArray.
  space close].
base deleteAll.
c report displayNl.
