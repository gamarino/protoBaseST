"avl_workload.st: the PBAvl workload of plan Tasks 14 and 16b, on 1000-element trees with
 Integer keys and values. py_avl_workload.py runs the same operations in ProtoBase; run_avl.sh
 runs both and prints the ratios.

 Each operation prints one line, tab-separated:
   op <name> <operations> <microseconds per operation> <checksum>
 The checksum is computed from the results and compared here with the expected value (the
 Python mirror computes the same one): a wrong result signals an Error and the run exits
 non-zero. The last line is 'avl_workload ok'.

 Usage: protost avl_workload.st"
Import from: 'protobase'.
| time report n reps pos key us sum expected r |
time := [:aBlock | | t0 | t0 := Time microsecondClockValue. aBlock value. Time microsecondClockValue - t0].
report := [:name :ops :micros :checksum :want |
  checksum = want ifFalse: [Error signal: name , ': checksum ' , checksum printString , ', expected ' , want printString].
  ('op' , (String with: Character tab) , name , (String with: Character tab) , ops printString
    , (String with: Character tab) , (micros / ops) asFloat printString
    , (String with: Character tab) , checksum printString) displayNl].
n := 1000.
reps := 2000.

pos := nil.
us := time value: [1 to: n do: [:i | pos := PBAvl posAppend: pos value: i * 10]].
report value: 'posAppend' value: n value: us value: pos count value: n.

key := nil.
us := time value: [1 to: n do: [:i | key := (PBAvl keyPut: key key: i value: i * 10 nodeClass: PBKeyNode) first]].
report value: 'keyPut-new' value: n value: us value: key count value: n.

"posAt: i \\ n answers (i \\ n + 1) * 10."
expected := (1 to: reps) inject: 0 into: [:a :i | a + ((i \\ n) + 1 * 10)].
sum := 0.
us := time value: [1 to: reps do: [:i | sum := sum + (PBAvl posAt: pos index: i \\ n)]].
report value: 'posAt' value: reps value: us value: sum value: expected.

sum := 0.
us := time value: [1 to: reps do: [:i | sum := sum + (PBAvl keyAt: key key: (i \\ n) + 1) value]].
report value: 'keyAt' value: reps value: us value: sum value: expected.

"Replaces the values of keys 1..500 by the key; sums the old values."
sum := 0.
us := time value: [1 to: 500 do: [:i |
  r := PBAvl keyPut: key key: i value: i nodeClass: PBKeyNode.
  (r at: 2) ifFalse: [Error signal: 'keyPut-replace: key ' , i printString , ' was not replaced'].
  sum := sum + (r at: 3)]].
report value: 'keyPut-replace' value: 500 value: us value: sum value: ((1 to: 500) inject: 0 into: [:a :i | a + (i * 10)]).

"Three whole-tree checks each; the checksum is the node count checked."
sum := 0.
us := time value: [3 timesRepeat: [sum := sum + (PBAvl check: pos) count]].
report value: 'check-pos' value: 3 value: us value: sum value: 3 * n.

sum := 0.
us := time value: [3 timesRepeat: [sum := sum + (PBAvl check: key) count]].
report value: 'check-key' value: 3 value: us value: sum value: 3 * n.

'avl_workload ok' displayNl.
