"EXPECT: ok 94"
"The concurrency table with two protoST actors in one process (design spec 10.4, last line;
 plan Task 21). For every case of tests/interop/concurrency_cases.json, on a new space set up
 by protoST: the actor A starts its transaction and runs its steps, then the actor B does,
 then B commits, then A commits (plan call C12's order). Each step is a send whose Future the
 driver waits on before the next one, so the interleaving is fixed and nothing depends on
 timing; the driver is the script itself and never waits inside an actor, and an actor waits
 only on its commit's Future, settled by the space's round runner (open question K23, ruling
 R19, CC10). The outcomes and the final contents must be proto_db's
 reference, as the JSON records it, for every case (CaseTable expectedFor: refuses a recorded
 difference; the blind write onto an indexed root merges since indexed queries plan Task 4b).
 The table also holds the swapped variant of row 7 (fix round 1), 13 counted set cases (plan
 Task 22 and its review), two concurrent addIndex: cases (plan Task 4b) and two blind writes onto
 a vector-indexed root (vectors phase V5), so it has 31 cases.
 The same steps and dump as the cross-language runs (_case_ops.st)."
Import from: 'protobase'.
Import from: '../tests/interop/_case_ops'.
Import from: '_check'.

| c base cases |
c := Check new.
base := FileSystem temp / ('pbst-concurrency-actors-' , Smalltalk pid printString).
cases := CaseTable load.
c that: 'the 13 rows of design spec 10.4, the swapped row 7, the 13 counted set cases, the 2 addIndex: cases and the 2 vector-indexed roots' is: cases size equals: 31.
[base deleteAll.
 cases do: [:case | | id dir space db a b outcomeA outcomeB recorded |
   id := case at: 'id'.
   dir := base / id.
   CaseTable setup: case in: dir pathString.
   space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
   [db := space openDatabase: (CaseTable databaseOf: case).
    a := CaseSide new asActor.
    b := CaseSide new asActor.
    (a start: (case at: 'a') in: db) wait.
    (b start: (case at: 'b') in: db) wait.
    outcomeB := b commit wait.
    outcomeA := a commit wait.
    recorded := CaseTable expectedFor: case.
    c that: id , ': the outcomes' is: 'A=' , outcomeA , ' B=' , outcomeB equals: (recorded at: 'outcome').
    c that: id , ': the final contents' is: (CaseTable dump: case in: db) equals: (recorded at: 'dump') asArray.
    c that: id , ': a new space reads them too' is: [ | other |
        other := PBObjectSpace storage: (PBFileStorage path: dir pathString).
        [CaseTable dump: case in: (other openDatabase: (CaseTable databaseOf: case))] ensure: [other close]] value
      equals: (recorded at: 'dump') asArray] ensure: [space close]]]
  ensure: [base deleteAll].
c report displayNl.
