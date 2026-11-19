"_st_avl_ops.st <kind>: runs a seeded AVL operation sequence and prints it with the trees it
 builds, for py_avl_replay.py to replay in ProtoBase (plan Task 14). A helper of
 avl_ops_identical.sh, never run as a test. Prints, per operation, 'op <words>', and at
 each checkpoint and after the last operation 'dump <n>' followed by 'node <line>' for each
 line of AvlOps dump: of the current tree (tests/unit/_avl_ops.st, on STPATH); then 'end'.

  pos, key, counted   the random sequences of the unit tests (Random seed: 20261110),
                      1000 / 1000 / 600 operations, a checkpoint every 10
  list                1000 PBList operations (AvlOps nextListOpFor:, plan Task 15): at
                      each checkpoint (every 10) a 'list <count> <state keys>' line, then
                      the dump of the list's tree
  pos-large           2000 appends, 1000 random operations, 500 removes of the first
                      element, 500 removes of the last; a checkpoint every 500
  key-large           2000 puts of ascending Integer keys, 1000 random operations (four in
                      five on keys inside the tree's range, Integers and halves, so
                      deletes remove interior nodes with two children; one in five
                      mixed-rank, at the ends), 1000 deletes of descending keys; a
                      checkpoint every 500

  bulk                the balanced keyed builds (indexed queries, plan Task 1): for each
                      size n in 0..64 and 2000, 'op bulk key <n> <key> <value> ...' builds a
                      PBKeyNode tree by keyFromSorted:nodeClass: and 'op bulk counted <n> ...'
                      a PBCountedKeyNode tree by keyFromSortedOrderKeys:nodeClass:, each
                      followed by its dump. The keys ascend: Integers, then Strings (the last
                      quarter); the values include boxed Strings and bytes, and the counted
                      values are (payload, count) pairs with counts 0 to 5

The large sequences are the sequential patterns of a database (list appends, monotonic
keys, queues): long right-spine rotation cascades and repeated first-node pops, at heights
11 to 12."
Import from: 'protobase'.
Import from: '_avl_ops'.

| args kind ops root size every steps queue apply emit next |
args := Smalltalk arguments.
args size = 1 ifFalse: ['usage: _st_avl_ops.st <pos|key|counted|list|pos-large|key-large|bulk>' displayNl. Smalltalk exit: 2].
kind := args at: 1.
ops := AvlOps new.
root := nil.
size := 0.
steps := 0.
every := (kind endsWith: '-large') ifTrue: [500] ifFalse: [kind = 'bulk' ifTrue: [1] ifFalse: [10]].
emit := [
  ('dump ' , steps printString) displayNl.
  (AvlOps dump: root) do: [:line | ('node ' , line) displayNl]].
apply := [:op |
  | o |
  o := op at: 1.
  o = #insert ifTrue: [root := PBAvl posInsert: root at: (op at: 2) value: (AvlOps valueOf: (op at: 3))].
  o = #append ifTrue: [root := PBAvl posAppend: root value: (AvlOps valueOf: (op at: 3))].
  o = #set ifTrue: [root := PBAvl posSet: root at: (op at: 2) value: (AvlOps valueOf: (op at: 3))].
  o = #remove ifTrue: [root := PBAvl posRemove: root at: (op at: 2)].
  o = #put ifTrue: [
    root := (PBAvl keyPut: root key: (AvlOps valueOf: (op at: 2)) value: (AvlOps valueOf: (op at: 3))
      nodeClass: (kind = 'counted' ifTrue: [PBCountedKeyNode] ifFalse: [PBKeyNode])) first].
  o = #delete ifTrue: [root := (PBAvl keyRemove: root key: (AvlOps valueOf: (op at: 2))) first].
  o = #bulk ifTrue: [
    | pairs |
    pairs := (1 to: (op at: 3)) asArray collect: [:i |
      { AvlOps valueOf: (op at: 2 + (2 * i)). AvlOps valueOf: (op at: 3 + (2 * i)) }].
    root := (op at: 2) = 'key'
      ifTrue: [PBAvl keyFromSorted: pairs nodeClass: PBKeyNode]
      ifFalse: [PBAvl keyFromSortedOrderKeys: (pairs collect: [:p | { PBKeys orderKey: (p at: 1). p at: 1. p at: 2 }])
        nodeClass: PBCountedKeyNode]].
  size := root isNil ifTrue: [0] ifFalse: [root count].
  steps := steps + 1.
  ('op ' , (AvlOps textOf: op)) displayNl.
  steps \\ every = 0 ifTrue: [emit value]].
kind = 'pos' ifTrue: [1000 timesRepeat: [apply value: (ops nextPosOpFor: size)]].
kind = 'list' ifTrue: [
  | list |
  list := PBList new.
  1000 timesRepeat: [
    | op |
    op := ops nextListOpFor: list count.
    list := AvlOps applyListOp: op to: list.
    root := list stateAt: 'root'.
    steps := steps + 1.
    ('op ' , (AvlOps textOf: op)) displayNl.
    steps \\ every = 0 ifTrue: [
      ('list ' , list count printString , ' '
        , (list state keys inject: '' into: [:acc :k | acc isEmpty ifTrue: [k] ifFalse: [acc , ',' , k]])) displayNl.
      emit value]]].
kind = 'key' ifTrue: [1000 timesRepeat: [apply value: ops nextKeyOp]].
kind = 'counted' ifTrue: [600 timesRepeat: [apply value: ops nextCountedOp]].
kind = 'pos-large' ifTrue: [
  1 to: 2000 do: [:i | apply value: { #append. size. 'i:' , i printString }].
  1000 timesRepeat: [apply value: (ops nextPosOpFor: size)].
  500 timesRepeat: [apply value: { #remove. 0 }].
  500 timesRepeat: [apply value: { #remove. size - 1 }]].
kind = 'key-large' ifTrue: [
  1000 to: 2999 do: [:i | apply value: { #put. 'i:' , i printString. 'i:' , (i * 7) printString }].
  1000 timesRepeat: [
    (ops between: 1 and: 5) = 1
      ifTrue: [apply value: ops nextKeyOp]
      ifFalse: [apply value: (ops nextKeyOpFrom: 1000 to: 2998)]].
  2999 to: 2000 by: -1 do: [:i | apply value: { #delete. 'i:' , i printString }]].
kind = 'bulk' ifTrue: [
  ((0 to: 64) asArray copyWith: 2000) do: [:n | #('key' 'counted') do: [:cls |
    | op |
    op := OrderedCollection new.
    op add: #bulk; add: cls; add: n.
    1 to: n do: [:i |
      op add: (i <= (n - (n // 4)) ifTrue: ['i:' , (3 * i) printString] ifFalse: ['s:k' , (100000 + i) printString]).
      op add: (cls = 'counted'
        ifTrue: ['t:' , i printString , ':' , (i \\ 6) printString]
        ifFalse: [i \\ 13 = 0 ifTrue: ['E:300'] ifFalse: [i \\ 17 = 0 ifTrue: ['B:260'] ifFalse: ['i:' , (7 * i) printString]]])].
    apply value: op asArray]]].
steps = 0 ifTrue: [('unknown kind ' , kind) displayNl. Smalltalk exit: 2].
steps \\ every = 0 ifFalse: [emit value].
'end' displayNl.
