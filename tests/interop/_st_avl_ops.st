"_st_avl_ops.st <pos|key|counted> <steps>: runs the seeded AVL operation sequence of the
 unit tests (tests/unit/_avl_ops.st, on STPATH) and prints it with the trees it builds, for
 py_avl_replay.py to replay in ProtoBase (plan Task 14). A helper of avl_ops_identical.sh,
 never run as a test. Prints, per operation, 'op <words>', and every 100 operations and
 after the last one, 'dump <n>' followed by 'node <line>' for each line of AvlOps dump:
 of the current tree."
Import from: 'protobase'.
Import from: '_avl_ops'.

| args kind steps ops root size emit |
args := Smalltalk arguments.
args size = 2 ifFalse: ['usage: _st_avl_ops.st <pos|key|counted> <steps>' displayNl. Smalltalk exit: 2].
kind := args at: 1.
steps := (args at: 2) asNumber.
ops := AvlOps new.
root := nil.
size := 0.
emit := [:i |
  ('dump ' , i printString) displayNl.
  (AvlOps dump: root) do: [:line | ('node ' , line) displayNl]].
1 to: steps do: [:i |
  | op |
  kind = 'pos' ifTrue: [
    op := ops nextPosOpFor: size.
    (op at: 1) = #insert ifTrue: [root := PBAvl posInsert: root at: (op at: 2) value: (AvlOps valueOf: (op at: 3))].
    (op at: 1) = #append ifTrue: [root := PBAvl posAppend: root value: (AvlOps valueOf: (op at: 3))].
    (op at: 1) = #set ifTrue: [root := PBAvl posSet: root at: (op at: 2) value: (AvlOps valueOf: (op at: 3))].
    (op at: 1) = #remove ifTrue: [root := PBAvl posRemove: root at: (op at: 2)]].
  kind = 'pos' ifFalse: [
    op := kind = 'key' ifTrue: [ops nextKeyOp] ifFalse: [ops nextCountedOp].
    (op at: 1) = #put ifTrue: [
      root := PBAvl keyPut: root key: (AvlOps valueOf: (op at: 2)) value: (AvlOps valueOf: (op at: 3))
        nodeClass: (kind = 'key' ifTrue: [PBKeyNode] ifFalse: [PBCountedKeyNode])].
    (op at: 1) = #delete ifTrue: [root := PBAvl keyRemove: root key: (AvlOps valueOf: (op at: 2))]].
  size := root isNil ifTrue: [0] ifFalse: [root count].
  ('op ' , (AvlOps textOf: op)) displayNl.
  (i \\ 100 = 0 or: [i = steps]) ifTrue: [emit value: i]].
'end' displayNl.
